class_name Simulator
extends Node
## Simulator — Motor de simulación física de MechaForge (Jolt / Godot).
##
## Convierte las piezas del modo edición en cuerpos rígidos, crea las uniones
## (fija/bisagra/deslizadera/rótula/engranaje) y las gobierna cada paso físico:
## motores con curva torque–velocidad y engranajes acoplados cinemáticamente.
## Al detener, restaura el estado inicial exacto.
##
## Todas las magnitudes en SI. El paso físico se fija en project.godot (120 Hz).

signal simulation_started
signal simulation_stopped

var _parts_root: Node3D
var _sim_root: Node3D
var _running: bool = false

var _bodies: Dictionary = {}          # uid -> RigidBody3D
var _kin_drives: Array = []           # servos ideales, en orden de la cadena (ver _setup_ideal_servos)
## Los perfiles de consigna arrancan con una rampa suave (sin el salto de un desfase).
const PROFILE_RAMP_S := 1.0
## Piezas insertadas en una protoboard: comparten el cuerpo de la placa (cuerpo
## compuesto rígido); aquí se guarda su transformación relativa a ese cuerpo.
var _body_offset: Dictionary = {}     # uid -> Transform3D
var _joints: Array = []               # de {conn, joint, ...}
var _connections: Array = []          # Array[Connection] activas
var _com_marker: MeshInstance3D
var _ground: StaticBody3D

# --- Control y electrónica (Fase 3) ---
var _pid_ids: Dictionary = {}       # conn.uid -> id de PID (autoload Electronics)
var _ctrl_angle: Dictionary = {}    # conn.uid -> ángulo acumulado (rad)
var _runtime_target: Dictionary = {} # conn.uid -> velocidad objetivo efectiva
var _motor_frac: Dictionary = {}    # conn.uid -> fracción de par (0..1) => corriente
var _ctrl_meas: Dictionary = {}     # conn.uid -> medida actual (ángulo o velocidad)
var _history: Dictionary = {}       # conn.uid -> {t:[], sp:[], meas:[]}
var _sim_time: float = 0.0
var _hist_accum: float = 0.0
var _elec: Dictionary = {}          # último resultado eléctrico
var _step_pos: Dictionary = {}      # conn.uid -> posición del paso actual del stepper (rad)
var _step_timer: Dictionary = {}    # conn.uid -> tiempo acumulado hasta el siguiente paso
var _stall_time: Dictionary = {}    # conn.uid -> tiempo en bloqueo (servo/motor)
var _stalled: Dictionary = {}       # conn.uid -> true si el eje está bloqueado
var _temp: Dictionary = {}          # conn.uid -> temperatura estimada del bobinado (°C)
var _sp_prev: Dictionary = {}       # conn.uid -> consigna anterior (prealimentación)
var _sp_ff: Dictionary = {}         # conn.uid -> derivada filtrada de la consigna
var _overheat_warned: Dictionary = {}

# --- Modelo térmico del motor (primer orden) ---
# C·dT/dt = I²·R − (T − T_amb)/R_th ; R del bobinado = V_nominal / I_bloqueo.
const T_AMBIENT := 25.0     # °C
const THERMAL_RTH := 8.0    # K/W  (motor DC pequeño, carcasa ~Ø25-37 mm)
const THERMAL_CTH := 30.0   # J/K  (constante de tiempo ≈ 4 min)
const T_WARN := 90.0        # °C: aviso de sobretemperatura
var _elec_accum: float = 0.0
const HIST_MAX := 300
const HIST_PERIOD := 0.033          # ~30 Hz de muestreo para las gráficas

const WORLD_LAYER := 1
## Capa de piezas "sin colisión" (cinta de línea): solo la detectan los sensores.
const MARK_LAYER := 8
## El motor de HingeJoint3D impulsa A respecto de B: con este signo, una consigna
## positiva hace girar B en sentido positivo del eje respecto de A (convención de
## la medida (ω_b - ω_a)·eje que usan el PID y la telemetría).
const MOTOR_SIGN := 1.0

func setup(parts_root: Node3D, sim_root: Node3D) -> void:
	_parts_root = parts_root
	_sim_root = sim_root

func is_running() -> bool:
	return _running

#region CONTROL DEL TIEMPO (pausa, paso a paso, cámara lenta) -------------------

var paused: bool = false

## Pausa/reanuda la física (el mundo Jolt deja de avanzar).
func set_paused(p: bool) -> void:
	if not _running:
		return
	paused = p
	PhysicsServer3D.set_active(not p)
	set_physics_process(not p)

## Avanza exactamente "n" pasos físicos estando en pausa.
func step_frames(n: int = 1) -> void:
	if not _running or not paused:
		return
	PhysicsServer3D.set_active(true)
	set_physics_process(true)
	for i in range(n):
		await get_tree().physics_frame
	if paused and _running:
		PhysicsServer3D.set_active(false)
		set_physics_process(false)

## Cámara lenta: escala del tiempo (1 = real). La física sigue a 120 Hz con
## pasos más cortos, así que es estable y medible.
func set_time_scale(k: float) -> void:
	Engine.time_scale = clampf(k, 0.01, 4.0)

func sim_time() -> float:
	return _sim_time

#endregion

#region ARRANQUE / PARADA -------------------------------------------------------

func start(connections: Array) -> void:
	if _running:
		return
	_connections = connections
	_build_ground()
	# 1) Crear un cuerpo rígido por pieza. Las insertadas en una protoboard se
	# funden después en el cuerpo de la placa (jerarquía rígida padre-hijo), y las
	# unidas con uniones fijas forman un solo cuerpo (ver _fixed_groups).
	var inserted := []
	var free_parts := []
	for child in _parts_root.get_children():
		if child is PartInstance and not child.is_queued_for_deletion():
			var part := child as PartInstance
			part.initial_transform = part.transform
			part.visible = false
			part.set_pick_enabled(false)
			if part.inserted_in != "":
				inserted.append(part)
			else:
				free_parts.append(part)
	for g in _fixed_groups(free_parts):
		var gb := _make_group_body(g)
		for gp in g:
			_bodies[(gp as PartInstance).uid] = gb
	for part in free_parts:
		if not _bodies.has(part.uid):
			_bodies[part.uid] = _make_body(part)
	for part in inserted:
		var host: RigidBody3D = _bodies.get(part.inserted_in)
		if host == null:
			_bodies[part.uid] = _make_body(part)
			continue
		var rel: Transform3D = host.global_transform.affine_inverse() * part.global_transform
		for sd in part.make_collision_shapes():
			var cs := CollisionShape3D.new()
			cs.shape = sd["shape"]
			cs.transform = rel * (sd["xf"] as Transform3D)
			host.add_child(cs)
		var vis: Node3D = part.make_visual_clone()
		vis.name = "Visual_%s" % part.uid
		vis.transform = rel * vis.transform
		host.add_child(vis)
		host.mass += maxf(0.0002, part.mass_kg())
		_bodies[part.uid] = host
		_body_offset[part.uid] = rel
	# 2) Crear las uniones. Las piezas unidas no "duermen": en mecanismos pequeños
	# la velocidad lineal cae bajo el umbral de reposo de Jolt y se congelarían.
	for conn in _connections:
		_make_joint(conn)
		for u in [conn.a_uid, conn.b_uid]:
			if _bodies.has(u):
				(_bodies[u] as RigidBody3D).can_sleep = false
	_setup_ideal_servos()
	# 2b) Engranajes: grupo rígido de cada rueda (piezas unidas con uniones fijas),
	# para usar la inercia real del conjunto en la restricción de engrane.
	for jd in _joints:
		if (jd["conn"] as Connection).tipo == Connection.Tipo.ENGRANAJE:
			jd["grp_a"] = _rigid_group(jd["a"])
			jd["grp_b"] = _rigid_group(jd["b"])
	# 3) Marcador de centro de masa.
	_com_marker = _make_com_marker()
	_sim_root.add_child(_com_marker)
	# Tamaño proporcional al conjunto (en una protoboard no debe tapar nada).
	var box := AABB()
	var first := true
	for uid in _bodies:
		var p: Vector3 = (_bodies[uid] as RigidBody3D).global_position
		if first:
			box = AABB(p, Vector3.ZERO); first = false
		else:
			box = box.expand(p)
	_com_marker.scale = Vector3.ONE * clampf(box.get_longest_axis_size() * 0.04 / 0.02, 0.2, 1.0)
	# 4) Control: crea un PID por bisagra con control de posición.
	_sim_time = 0.0
	for conn in _connections:
		if conn.tipo == Connection.Tipo.BISAGRA and conn.motor_enabled:
			_ctrl_angle[conn.uid] = 0.0
			if conn.control_mode != Connection.ControlMode.NINGUNO:
				var pid: int = Electronics.PidCreate()
				Electronics.PidConfigure(pid, conn.ctrl_kp, conn.ctrl_ki, conn.ctrl_kd)
				Electronics.PidSetLimits(pid, -conn.motor_noload_speed, conn.motor_noload_speed)
				Electronics.PidSetSetpoint(pid, conn.ctrl_setpoint)
				_pid_ids[conn.uid] = pid
				_history[conn.uid] = {"t": [], "sp": [], "meas": []}
	_compute_electrical()
	_running = true
	set_physics_process(true)
	simulation_started.emit()

func stop() -> void:
	if not _running:
		return
	set_physics_process(false)
	paused = false
	PhysicsServer3D.set_active(true)
	Engine.time_scale = 1.0
	# Se retiran del árbol YA (no solo queue_free): si no, siguen en el espacio
	# físico hasta el final del frame y chocarían con los de un reinicio inmediato.
	for j in _joints:
		if is_instance_valid(j["joint"]):
			_discard(j["joint"])
	_joints.clear()
	_kin_drives.clear()
	for uid in _bodies:
		if is_instance_valid(_bodies[uid]):
			_discard(_bodies[uid])
	_bodies.clear()
	_body_offset.clear()
	if _com_marker: _discard(_com_marker)
	if _ground: _discard(_ground)
	for uid in _pid_ids:
		Electronics.PidDestroy(_pid_ids[uid])
	_pid_ids.clear(); _ctrl_angle.clear(); _runtime_target.clear()
	_step_pos.clear(); _step_timer.clear(); _stall_time.clear(); _stalled.clear()
	_temp.clear(); _overheat_warned.clear(); _sp_prev.clear(); _sp_ff.clear(); _angle_ref.clear(); _axis_local.clear()
	_motor_frac.clear(); _history.clear(); _elec = {}
	# Restaurar piezas a su estado inicial.
	for child in _parts_root.get_children():
		if child is PartInstance:
			var part := child as PartInstance
			part.transform = part.initial_transform
			part.visible = true
			part.set_pick_enabled(true)
	_running = false
	simulation_stopped.emit()

func _discard(n: Node) -> void:
	if n.get_parent():
		n.get_parent().remove_child(n)
	n.queue_free()

func _build_ground() -> void:
	_ground = StaticBody3D.new()
	_ground.name = "SueloFisico"
	var cs := CollisionShape3D.new()
	var shape := WorldBoundaryShape3D.new()   # plano infinito en y=0
	shape.plane = Plane(Vector3.UP, 0.0)
	cs.shape = shape
	_ground.add_child(cs)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.8
	pm.bounce = 0.0
	_ground.physics_material_override = pm
	_ground.collision_layer = WORLD_LAYER
	_sim_root.add_child(_ground)

## Piezas unidas con uniones fijas: cada grupo (de 2 o más) va en UN cuerpo rígido.
## Jolt resuelve las uniones fijas entre cuerpos dinámicos como un resorte cuya
## rigidez depende de las masas (una viga de 0.6 kg sobre un soporte de 32 g cedía 8°,
## y los motores de una bisagra montada sobre una pieza fija no sostenían su carga);
## un solo cuerpo es rígido de verdad. Las deslizaderas bloqueadas (ajustes) cuentan
## como fijas. El sensor de fuerza (mide sus propios contactos) y las piezas sin
## colisión (marcas como la cinta de la pista) conservan su cuerpo.
func _fixed_groups(parts: Array) -> Array:
	var parent := {}
	var by_uid := {}
	for p in parts:
		var pi := p as PartInstance
		if pi.def_id == "sensor_fuerza" or pi.def.get("sin_colision", false):
			continue
		parent[pi.uid] = pi.uid
		by_uid[pi.uid] = pi
	var find := func(u: String) -> String:
		var r := u
		while parent[r] != r:
			r = parent[r]
		return r
	for c in _connections:
		var conn := c as Connection
		var rigid := conn.tipo == Connection.Tipo.FIJA or (conn.tipo == Connection.Tipo.DESLIZADERA and conn.slide_locked)
		if not rigid or not parent.has(conn.a_uid) or not parent.has(conn.b_uid):
			continue
		var ra: String = find.call(conn.a_uid)
		var rb: String = find.call(conn.b_uid)
		if ra != rb:
			parent[rb] = ra
	var groups := {}
	for u in parent:
		var r: String = find.call(u)
		if not groups.has(r):
			groups[r] = []
		groups[r].append(by_uid[u])
	var out := []
	for r in groups:
		if (groups[r] as Array).size() >= 2:
			out.append(groups[r])
	return out

## Un cuerpo para un grupo de piezas fijas entre sí: el de la pieza anclada (o la más
## pesada) más las formas y la vista de las demás en su sitio, con la masa, el centro
## de masa y la inercia del conjunto (teorema de Steiner; sin productos de inercia).
func _make_group_body(group: Array) -> RigidBody3D:
	var root: PartInstance = group[0]
	for p in group:
		var pi := p as PartInstance
		if pi.anchored and not root.anchored:
			root = pi
		elif pi.anchored == root.anchored and pi.mass_kg() > root.mass_kg():
			root = pi
	var body := _make_body(root)
	var rx := root.global_transform
	var items := [{"part": root, "rel": Transform3D.IDENTITY}]
	var uids := [root.uid]
	for p in group:
		var part := p as PartInstance
		if part == root:
			continue
		var rel := rx.affine_inverse() * part.global_transform
		for sd in part.make_collision_shapes():
			var cs := CollisionShape3D.new()
			cs.shape = sd["shape"]
			cs.transform = rel * (sd["xf"] as Transform3D)
			body.add_child(cs)
		var vis := part.make_visual_clone()
		vis.name = "Visual_%s" % part.uid
		vis.transform = rel * vis.transform
		body.add_child(vis)
		_body_offset[part.uid] = rel
		items.append({"part": part, "rel": rel})
		uids.append(part.uid)
		var dm := PartLibrary.dims_m(part.def)
		if minf(dm.x, minf(dm.y, dm.z)) < 0.03:
			body.continuous_cd = true
	if not root.anchored:
		var mp := group_mass(items)
		body.mass = maxf(0.001, float(mp["mass"]))
		body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		body.center_of_mass = mp["com"]
		var it: Vector3 = mp["inertia"]
		if it.x > 0.0 and it.y > 0.0 and it.z > 0.0:
			body.inertia = it
	body.set_meta("piezas", uids)
	return body

## Masa, centro de masa e inercia (diagonal, ejes del cuerpo) de piezas en un cuerpo:
## items = [{part, rel}] con rel la transformación de cada pieza en el cuerpo.
static func group_mass(items: Array) -> Dictionary:
	var total := 0.0
	var acc := Vector3.ZERO
	var parts := []
	for it in items:
		var p: PartInstance = it["part"]
		var rel: Transform3D = it["rel"]
		var m := maxf(0.0001, p.mass_kg())
		var c: Vector3 = rel * p.com_local()
		parts.append({"m": m, "c": c, "R": rel.basis.orthonormalized(), "I": part_inertia(p, m)})
		total += m
		acc += c * m
	var com := acc / total
	var diag := Vector3.ZERO
	for q in parts:
		var R: Basis = q["R"]
		var I: Vector3 = q["I"]
		var r: Vector3 = (q["c"] as Vector3) - com
		var m: float = q["m"]
		for k in range(3):
			# (R·diag(I)·Rᵀ)_kk = Σ_j R_kj² I_j ; Steiner: m(|r|² − r_k²).
			var rot := 0.0
			for j in range(3):
				var rkj: float = R[j][k]
				rot += rkj * rkj * I[j]
			diag[k] += rot + m * (r.length_squared() - r[k] * r[k])
	return {"mass": total, "com": com, "inertia": diag}

## Inercia diagonal de una pieza (kg·m², sus ejes, respecto de su centro de masa): la
## propia si tiene geometría propia; si no, la de su forma (caja, cilindro, esfera).
static func part_inertia(p: PartInstance, m: float) -> Vector3:
	var it := p.inertia_local()
	if it != Vector3.ZERO:
		return it
	var d := PartLibrary.dims_m(p.def)
	match str(p.def.get("forma", "caja")):
		"cilindro", "tubo":
			var r := d.x * 0.5
			var ri := 0.0
			if str(p.def.get("forma", "")) == "tubo":
				ri = maxf(0.0, r - float(p.def.get("dimensiones_mm", {}).get("espesor", 2.0)) / 1000.0)
			var side := m * (3.0 * (r * r + ri * ri) + d.y * d.y) / 12.0
			return Vector3(side, m * (r * r + ri * ri) * 0.5, side)
		"esfera":
			return Vector3.ONE * 0.4 * m * pow(d.x * 0.5, 2)
		_:
			return Vector3(d.y * d.y + d.z * d.z, d.x * d.x + d.z * d.z, d.x * d.x + d.y * d.y) * m / 12.0

func _make_body(part: PartInstance) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = "Body_%s" % part.uid
	_sim_root.add_child(body)
	body.global_transform = part.global_transform
	body.mass = maxf(0.001, part.mass_kg())
	var pm := PhysicsMaterial.new()
	pm.friction = part.friction()
	pm.bounce = part.restitution()
	body.physics_material_override = pm
	body.can_sleep = true
	body.collision_layer = WORLD_LAYER | PartInstance.PICK_LAYER
	body.collision_mask = WORLD_LAYER
	for sd in part.make_collision_shapes():
		var cs := CollisionShape3D.new()
		cs.shape = sd["shape"]
		cs.transform = sd["xf"]
		body.add_child(cs)
	# Piezas con geometría propia (malla importada estanca, carcasa, soporte de lentes):
	# centro de masa e inercia reales (si no, Jolt los deduce de las formas de
	# colisión con densidad uniforme).
	if PartLibrary.has_custom_mass(part.def):
		body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		body.center_of_mass = part.com_local()
		var inertia := part.inertia_local()
		if inertia.x > 0.0 and inertia.y > 0.0 and inertia.z > 0.0:
			body.inertia = inertia
	var vis := part.make_visual_clone()
	vis.name = "Visual_%s" % part.uid
	body.add_child(vis)
	body.set_meta("part_uid", part.uid)
	# Anclada al mundo: cuerpo congelado (estático) — bancos de prueba, pistas.
	if part.anchored:
		body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		body.freeze = true
	if part.def.get("sin_colision", false):
		body.collision_layer = MARK_LAYER
		body.collision_mask = 0
	# Piezas pequeñas o de paredes finas: detección continua de colisiones. Con pasos
	# discretos una bola de 2 cm que cae a 1.6 m/s avanza 13 mm por paso y atravesaba
	# el fondo de 6 mm de una carcasa importada.
	var dm := PartLibrary.dims_m(part.def)
	if minf(dm.x, minf(dm.y, dm.z)) < 0.03 or (part.def.get("forma", "") == "custom" and part.collision_mode() == "multiple"):
		body.continuous_cd = true
	# El sensor de fuerza lee los impulsos de contacto de su cuerpo.
	if part.def_id == "sensor_fuerza":
		body.contact_monitor = true
		body.max_contacts_reported = 16
	return body

#endregion

#region UNIONES -----------------------------------------------------------------

func _make_joint(conn: Connection) -> void:
	var a: RigidBody3D = _bodies.get(conn.a_uid)
	var b: RigidBody3D = _bodies.get(conn.b_uid)
	if a == null or b == null:
		push_warning("Unión con piezas inexistentes: %s" % conn.uid)
		return
	if a == b:
		return    # ambas piezas forman ya un mismo cuerpo (insertada en su protoboard)

	# El engranaje NO crea un joint físico: es un acoplamiento cinemático de
	# velocidad. Cada engranaje se monta aparte con su propia bisagra.
	if conn.tipo == Connection.Tipo.ENGRANAJE:
		_joints.append({"conn": conn, "joint": null, "a": a, "b": b, "phase": 0.0, "torque": 0.0})
		return

	# La bisagra usa HingeJoint3D (motor y límites robustos en Jolt).
	if conn.tipo == Connection.Tipo.BISAGRA:
		var hinge := HingeJoint3D.new()
		_sim_root.add_child(hinge)
		# El eje de giro de HingeJoint3D es su Z LOCAL: se orienta Z hacia el eje pedido.
		hinge.global_transform = Transform3D(_axis_basis_z(conn.axis_vector()), conn.anchor)
		hinge.node_a = hinge.get_path_to(a)
		hinge.node_b = hinge.get_path_to(b)
		if conn.limit_enabled:
			hinge.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
			hinge.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, conn.limit_lower)
			hinge.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, conn.limit_upper)
		if conn.motor_enabled:
			hinge.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, true)
			hinge.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, -conn.motor_target_speed * MOTOR_SIGN)
			hinge.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, conn.motor_stall_torque / 120.0)
		_joints.append({"conn": conn, "joint": hinge, "a": a, "b": b})
		return

	var joint := Generic6DOFJoint3D.new()
	_sim_root.add_child(joint)
	joint.global_transform = Transform3D(_axis_basis(conn.axis_vector()), conn.anchor)
	joint.node_a = joint.get_path_to(a)
	joint.node_b = joint.get_path_to(b)

	match conn.tipo:
		Connection.Tipo.FIJA:
			_lock_all(joint)
		Connection.Tipo.DESLIZADERA:
			_lock_all_angular(joint)
			_lock_linear_yz(joint)
			if conn.limit_enabled:
				_set_linear_limit_x(joint, conn.limit_lower, conn.limit_upper)
			else:
				_free_linear_x(joint)
		Connection.Tipo.ROTULA:
			_lock_linear(joint)
			_free_all_angular(joint)

	_joints.append({"conn": conn, "joint": joint, "a": a, "b": b})

# --- Helpers de bloqueo/liberación (Generic6DOFJoint3D) ---
func _set_lin(joint: Generic6DOFJoint3D, ax: String, en: bool, lo: float, hi: float) -> void:
	joint.set("linear_limit_%s/enabled" % ax, en)
	joint.set("linear_limit_%s/lower_distance" % ax, lo)
	joint.set("linear_limit_%s/upper_distance" % ax, hi)

func _set_ang(joint: Generic6DOFJoint3D, ax: String, en: bool, lo: float, hi: float) -> void:
	joint.set("angular_limit_%s/enabled" % ax, en)
	joint.set("angular_limit_%s/lower_angle" % ax, lo)
	joint.set("angular_limit_%s/upper_angle" % ax, hi)

func _lock_linear(joint) -> void:
	for ax in ["x", "y", "z"]:
		_set_lin(joint, ax, true, 0.0, 0.0)

func _lock_linear_yz(joint) -> void:
	_set_lin(joint, "y", true, 0.0, 0.0)
	_set_lin(joint, "z", true, 0.0, 0.0)

func _lock_all_angular(joint) -> void:
	for ax in ["x", "y", "z"]:
		_set_ang(joint, ax, true, 0.0, 0.0)

func _lock_angular_yz(joint) -> void:
	_set_ang(joint, "y", true, 0.0, 0.0)
	_set_ang(joint, "z", true, 0.0, 0.0)

func _lock_all(joint) -> void:
	_lock_linear(joint)
	_lock_all_angular(joint)

func _free_angular_x(joint) -> void:
	_set_ang(joint, "x", false, 0.0, 0.0)

func _set_angular_limit_x(joint, lo: float, hi: float) -> void:
	_set_ang(joint, "x", true, lo, hi)

func _free_linear_x(joint) -> void:
	_set_lin(joint, "x", false, 0.0, 0.0)

func _set_linear_limit_x(joint, lo: float, hi: float) -> void:
	_set_lin(joint, "x", true, lo, hi)

func _free_all_angular(joint) -> void:
	for ax in ["x", "y", "z"]:
		_set_ang(joint, ax, false, 0.0, 0.0)

## Base cuyo eje X local apunta en la dirección dada (el eje de la unión).
func _axis_basis(dir: Vector3) -> Basis:
	var x := dir.normalized()
	var up := Vector3.UP if absf(x.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var z := x.cross(up).normalized()
	var y := z.cross(x).normalized()
	return Basis(x, y, z)

## Base cuyo eje Z local apunta en la dirección dada (eje de giro de HingeJoint3D).
func _axis_basis_z(dir: Vector3) -> Basis:
	var z := dir.normalized()
	var up := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	var y := z.cross(x).normalized()
	return Basis(x, y, z)

#endregion

#region PASO FÍSICO: MOTORES, ENGRANAJES, COM -----------------------------------

func _physics_process(delta: float) -> void:
	_sim_time += delta
	_drive_ideal_servos()
	for jd in _joints:
		var conn: Connection = jd["conn"]
		if jd.get("ideal", false):
			continue
		if conn.tipo == Connection.Tipo.BISAGRA and conn.motor_enabled:
			_update_control(jd, delta)
			_drive_motor(jd)
			_update_thermal(conn, delta)
		elif conn.tipo == Connection.Tipo.ENGRANAJE:
			_drive_gear(jd, delta)
	_update_com()
	# Registro para gráficas y cálculo eléctrico periódico.
	_hist_accum += delta
	if _hist_accum >= HIST_PERIOD:
		_hist_accum = 0.0
		_record_history()
	_elec_accum += delta
	if _elec_accum >= 0.1:
		_elec_accum = 0.0
		_compute_electrical()

## Servos ideales (bisagras de posición con perfil marcado «ideal»): su pieza B pasa a
## cuerpo cinemático y sigue el perfil exacto respecto de la A. Solo si la A está
## quieta (anclada) o es a su vez cinemática: se ordenan por la cadena (una cabeza de
## prueba sobre tres servos apilados). Jolt da a los cuerpos cinemáticos la velocidad
## de su movimiento, así que la IMU mide giros y aceleraciones reales.
func _setup_ideal_servos() -> void:
	_kin_drives.clear()
	var pending := []
	for jd in _joints:
		var c: Connection = jd["conn"]
		if c.tipo == Connection.Tipo.BISAGRA and c.profile != Connection.Profile.NINGUNO and c.profile_ideal \
				and c.control_mode == Connection.ControlMode.POSICION and jd["a"] != jd["b"]:
			pending.append(jd)
	var driven := {}
	var progress := true
	while progress and not pending.is_empty():
		progress = false
		for jd in pending.duplicate():
			var a: RigidBody3D = jd["a"]
			var b: RigidBody3D = jd["b"]
			if not (a.freeze or driven.has(a)):
				continue
			pending.erase(jd)
			progress = true
			if b.freeze or driven.has(b):
				continue                      # B anclada o ya movida por otro servo
			b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			b.freeze = true
			driven[b] = true
			var conn: Connection = jd["conn"]
			var a0 := a.global_transform
			jd["ideal"] = true
			_kin_drives.append({"conn": conn, "a": a, "b": b, "rel0": a0.affine_inverse() * b.global_transform,
				"anchor": a0.affine_inverse() * conn.anchor, "axis": (a0.basis.inverse() * conn.axis_vector()).normalized()})
	for jd in pending:
		push_warning("Servo ideal sobre una pieza que no está fija ni movida por otro servo ideal: se usa el PID (%s)." % (jd["conn"] as Connection).uid)

## Consigna del perfil con la rampa de arranque (suave: smoothstep en PROFILE_RAMP_S).
static func profile_setpoint(conn: Connection, t: float) -> float:
	return conn.profile_value(t) * smoothstep(0.0, PROFILE_RAMP_S, t)

## Coloca cada pieza movida por un servo ideal en su ángulo del perfil (al final del
## paso que empieza): B = A · giro(eje, θ) alrededor del anclaje · B0 relativo a A0.
func _drive_ideal_servos() -> void:
	var targets := {}
	for kd in _kin_drives:
		var conn: Connection = kd["conn"]
		var th := profile_setpoint(conn, _sim_time)
		if conn.limit_enabled:
			th = clampf(th, conn.limit_lower, conn.limit_upper)
		if conn.motor_type == Connection.MotorType.SERVO:
			th = clampf(th, deg_to_rad(conn.servo_min_deg), deg_to_rad(conn.servo_max_deg))
		conn.ctrl_setpoint = th
		var anchor: Vector3 = kd["anchor"]
		var rel := Transform3D(Basis(kd["axis"], th), anchor) * Transform3D(Basis.IDENTITY, -anchor) * (kd["rel0"] as Transform3D)
		var a: RigidBody3D = kd["a"]
		var b: RigidBody3D = kd["b"]
		var bx: Transform3D = (targets.get(a, a.global_transform) as Transform3D) * rel
		b.global_transform = bx
		targets[b] = bx
		_ctrl_angle[conn.uid] = th
		_ctrl_meas[conn.uid] = th

## Aplica el controlador PID a una bisagra motorizada (posición o velocidad).
func _update_control(jd: Dictionary, delta: float) -> void:
	var conn: Connection = jd["conn"]
	var a: RigidBody3D = jd["a"]
	var b: RigidBody3D = jd["b"]
	var axis := _joint_axis(conn, a)
	var omega: float = (b.angular_velocity - a.angular_velocity).dot(axis)
	# Ángulo relativo EXACTO a partir de las orientaciones (sin deriva: integrar la
	# velocidad acumula error cuando el solver corrige posiciones).
	_ctrl_angle[conn.uid] = _joint_angle(conn.uid, a, b, axis)
	if conn.control_mode == Connection.ControlMode.NINGUNO:
		return
	var pid: int = _pid_ids.get(conn.uid, -1)
	if pid < 0:
		return
	# Perfil de consigna (banco de pruebas): manda sobre el valor fijo.
	if conn.profile != Connection.Profile.NINGUNO:
		conn.ctrl_setpoint = profile_setpoint(conn, _sim_time)
	# Consigna efectiva según el tipo de motor.
	var setpoint := conn.ctrl_setpoint
	if conn.motor_type == Connection.MotorType.STEPPER:
		setpoint = conn.snap_to_step(setpoint)          # pasos discretos (1.8°...)
	elif conn.motor_type == Connection.MotorType.SERVO:
		setpoint = clampf(setpoint, deg_to_rad(conn.servo_min_deg), deg_to_rad(conn.servo_max_deg))
	Electronics.PidSetSetpoint(pid, setpoint)
	var meas: float = _ctrl_angle[conn.uid] if conn.control_mode == Connection.ControlMode.POSICION else omega
	_ctrl_meas[conn.uid] = meas
	if conn.motor_type == Connection.MotorType.STEPPER:
		_runtime_target[conn.uid] = _stepper_command(conn, meas, setpoint, delta)
		return
	var cmd: float = Electronics.PidUpdate(pid, meas, delta)
	# Control de posición: prealimentación con la velocidad de la consigna, para
	# seguir trayectorias sin el retraso típico de un lazo proporcional.
	if conn.control_mode == Connection.ControlMode.POSICION:
		var prev: float = _sp_prev.get(conn.uid, setpoint)
		var ff: float = _sp_ff.get(conn.uid, 0.0)
		ff += ((setpoint - prev) / delta - ff) * 0.3
		_sp_prev[conn.uid] = setpoint
		_sp_ff[conn.uid] = ff
		cmd += ff
	# Control de velocidad: el motor de la bisagra ya es un servo de velocidad, así
	# que la consigna va como prealimentación y el PID solo corrige (carga, fricción).
	# Usar la salida del PID como velocidad directa hace oscilar el lazo cada paso.
	if conn.control_mode == Connection.ControlMode.VELOCIDAD:
		cmd = setpoint + cmd
	var vmax := conn.motor_noload_speed
	if conn.motor_type == Connection.MotorType.SERVO:
		vmax = minf(vmax, conn.servo_speed())          # velocidad nominal (s/60°)
	_runtime_target[conn.uid] = clampf(cmd, -vmax, vmax)
	_update_stall(conn, setpoint - meas, omega, delta)

var _angle_ref: Dictionary = {}     # conn.uid -> {qa0, qb0, axis_a, last, acc}
var _axis_local: Dictionary = {}    # conn.uid -> eje de la unión en el marco del cuerpo A

## Eje actual de la unión en el mundo: el definido al crearla, pero solidario al
## cuerpo A (en un vehículo que gira, el eje de las ruedas gira con el chasis).
func _joint_axis(conn: Connection, a: RigidBody3D) -> Vector3:
	var q := a.global_transform.basis.get_rotation_quaternion()
	if not _axis_local.has(conn.uid):
		_axis_local[conn.uid] = (q.inverse() * conn.axis_vector()).normalized()
	return (q * (_axis_local[conn.uid] as Vector3)).normalized()

## Giro de b respecto de a alrededor del eje de la unión desde el inicio (rad),
## desenrollado para admitir varias vueltas.
func _joint_angle(uid: String, a: RigidBody3D, b: RigidBody3D, axis: Vector3) -> float:
	var qa := a.global_transform.basis.get_rotation_quaternion()
	var qb := b.global_transform.basis.get_rotation_quaternion()
	if not _angle_ref.has(uid):
		_angle_ref[uid] = {"qa0": qa, "qb0": qb, "axis_a": (qa.inverse() * axis).normalized(), "last": 0.0, "acc": 0.0}
	var r: Dictionary = _angle_ref[uid]
	var d: Quaternion = qa.inverse() * qb * (r["qb0"] as Quaternion).inverse() * (r["qa0"] as Quaternion)
	var ax: Vector3 = r["axis_a"]
	var ang := 2.0 * atan2(Vector3(d.x, d.y, d.z).dot(ax), d.w)
	var step := wrapf(ang - float(r["last"]), -PI, PI)
	r["last"] = ang
	r["acc"] = float(r["acc"]) + step
	return r["acc"]

## Motor paso a paso: la posición avanza a SALTOS discretos (paso/microstep) hacia
## la consigna, a la frecuencia de pasos máxima; entre pasos el rotor se retiene
## en el paso actual (par de retención magnético), lo que produce el movimiento
## "a escalones" característico.
func _stepper_command(conn: Connection, meas: float, setpoint: float, delta: float) -> float:
	var step := deg_to_rad(conn.step_deg) / float(maxi(1, conn.microsteps))
	var pos: float = _step_pos.get(conn.uid, conn.snap_to_step(meas))
	var target := setpoint
	if conn.control_mode == Connection.ControlMode.VELOCIDAD:
		target = pos + signf(setpoint) * step * 2.0 if absf(setpoint) > 1e-4 else pos
	var rate := absf(setpoint) if conn.control_mode == Connection.ControlMode.VELOCIDAD else conn.motor_noload_speed
	var period := step / maxf(0.01, rate)                 # segundos por paso
	var t: float = _step_timer.get(conn.uid, 0.0) + delta
	while t >= period and absf(target - pos) > step * 0.5:
		pos += signf(target - pos) * step
		t -= period
	if absf(target - pos) <= step * 0.5:
		t = 0.0
	_step_timer[conn.uid] = t
	_step_pos[conn.uid] = pos
	# Retención: lleva el rotor al paso actual con alta rigidez.
	return clampf((pos - meas) * 90.0, -conn.motor_noload_speed * 3.0, conn.motor_noload_speed * 3.0)

## Detecta bloqueo del eje (stall): error grande, velocidad casi nula y par al
## máximo durante más de 0.4 s. El motor consume su corriente de bloqueo.
func _update_stall(conn: Connection, err: float, omega: float, delta: float) -> void:
	var stuck := absf(err) > deg_to_rad(5.0) and absf(omega) < 0.05
	var t: float = (_stall_time.get(conn.uid, 0.0) + delta) if stuck else 0.0
	_stall_time[conn.uid] = t
	var was: bool = _stalled.get(conn.uid, false)
	_stalled[conn.uid] = t > 0.4
	if _stalled[conn.uid] and not was:
		Config.notify("⚠ %s bloqueado (sobrecarga): par máximo %.2f N·m alcanzado." % [
			"Servo" if conn.motor_type == Connection.MotorType.SERVO else "Motor", conn.motor_stall_torque], 4.0)

## Calentamiento del bobinado por efecto Joule y enfriamiento hacia el ambiente.
func _update_thermal(conn: Connection, delta: float) -> void:
	var frac: float = 1.0 if _stalled.get(conn.uid, false) else _motor_frac.get(conn.uid, 0.0)
	var i: float = conn.elec_current_noload + (conn.elec_current_stall - conn.elec_current_noload) * frac
	var r_wind := maxf(0.1, conn.elec_voltaje_nominal / maxf(0.01, conn.elec_current_stall))
	var t: float = _temp.get(conn.uid, T_AMBIENT)
	t += (i * i * r_wind - (t - T_AMBIENT) / THERMAL_RTH) / THERMAL_CTH * delta
	_temp[conn.uid] = t
	if t > T_WARN and not _overheat_warned.get(conn.uid, false):
		_overheat_warned[conn.uid] = true
		Config.notify("🌡 Motor a %.0f °C: sobretemperatura (reduce la carga o el ciclo de trabajo)." % t, 5.0)

## Temperatura estimada del motor de una unión (°C).
func motor_temperature(uid: String) -> float:
	return _temp.get(uid, T_AMBIENT)

## Temperatura máxima entre todos los motores (°C).
func max_motor_temperature() -> float:
	var m := T_AMBIENT
	for k in _temp:
		m = maxf(m, _temp[k])
	return m

func is_stalled(uid: String) -> bool:
	return _stalled.get(uid, false)

## Motor de bisagra con curva par–velocidad de motor DC (ver modelo abajo).
func _drive_motor(jd: Dictionary) -> void:
	var conn: Connection = jd["conn"]
	var hinge: HingeJoint3D = jd["joint"]
	var a: RigidBody3D = jd["a"]
	var b: RigidBody3D = jd["b"]
	var axis := _joint_axis(conn, a)
	# Curva torque–velocidad de motor DC: torque disponible cae con la velocidad.
	var omega: float = (b.angular_velocity - a.angular_velocity).dot(axis)
	var step := 1.0 / float(Engine.physics_ticks_per_second)
	# Objetivo efectivo: el del controlador si hay control, si no el fijo.
	var target: float = _runtime_target.get(conn.uid, conn.motor_target_speed)
	# Alimentación por circuito (F1): el voltaje/PWM cableado escala el motor.
	var duty: float = clampf(conn.elec_duty, 0.0, 1.0)
	target *= duty
	# Modelo de motor DC: τ = τ_bloqueo · (u − ω/ω0), con u = consigna/ω0 (tensión
	# relativa). Da el par máximo en arranque, cero a la velocidad objetivo y par de
	# FRENADO (dinámico) si el eje gira más rápido que la consigna.
	var w0 := maxf(0.001, conn.motor_noload_speed)
	var frac := clampf(absf(target / w0 - omega / w0), 0.0, 1.0)
	var torque := conn.motor_stall_torque * frac
	_motor_frac[conn.uid] = frac
	hinge.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, -target * MOTOR_SIGN)
	hinge.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, torque * step)

## Engranaje como RESTRICCIÓN DINÁMICA entre los dos cuerpos (no cinemática):
##   ω_b + r·ω_a = 0   con r = Z1/Z2 (o la relación indicada).
## Cada paso se aplican impulsos iguales y opuestos (ponderados por la inercia de
## cada rueda sobre el eje), de modo que la carga del engranaje conducido se
## refleja en el conductor y el par se transmite en proporción r (τ_a = r·τ_b).
## - Huelgo (backlash): holgura angular en la que los dientes no están en contacto;
##   dentro de ella no se transmite par (al invertir el giro hay un retardo).
## - Rendimiento/fricción: se pierde (1-η) del par transmitido como fricción.
## - Corrección de fase (Baumgarte): la posición relativa se integra y se corrige
##   para que las ruedas no se desincronicen ni "atraviesen" a altas revoluciones.
func _drive_gear(jd: Dictionary, delta: float) -> void:
	var conn: Connection = jd["conn"]
	var a: RigidBody3D = jd["a"]
	var b: RigidBody3D = jd["b"]
	var axis := _joint_axis(conn, a)
	var r := conn.effective_gear_ratio()
	var sa := PhysicsServer3D.body_get_direct_state(a.get_rid())
	var sb := PhysicsServer3D.body_get_direct_state(b.get_rid())
	if sa == null or sb == null:
		return
	# Inercia del CONJUNTO de cada rueda (rueda + piezas fijadas a ella).
	var inv_ia := _group_inv_inertia(jd.get("grp_a", [a]), a.global_position, axis)
	var inv_ib := _group_inv_inertia(jd.get("grp_b", [b]), b.global_position, axis)
	var denom := r * r * inv_ia + inv_ib
	if denom <= 0.0:
		return
	var wa := sa.angular_velocity.dot(axis)
	var wb := sb.angular_velocity.dot(axis)
	var cdot := wb + r * wa
	# Error de fase acumulado (rad, en la rueda b).
	var phase: float = jd["phase"] + cdot * delta
	var half_bl := deg_to_rad(conn.gear_backlash_deg) * 0.5
	var torque := 0.0
	if absf(phase) > half_bl:
		var pen := phase - signf(phase) * half_bl
		# Restricción de velocidad unilateral: el diente solo empuja (sin rebote).
		var lam := -cdot / denom
		lam = minf(lam, 0.0) if pen > 0.0 else maxf(lam, 0.0)
		if lam != 0.0:
			sb.apply_torque_impulse(axis * lam)
			sa.apply_torque_impulse(axis * (lam * r))
			torque = lam / delta
			# Pérdidas por fricción del engrane: se oponen al giro de la rueda conducida.
			var loss := (1.0 - clampf(conn.gear_efficiency, 0.0, 1.0)) * absf(lam)
			var wb_new := wb + inv_ib * lam
			if loss > 0.0 and absf(wb_new) > 1e-4:
				sb.apply_torque_impulse(axis * (-signf(wb_new) * minf(loss, absf(wb_new) / maxf(inv_ib, 1e-9))))
		# Proyección de posición: corrige la interpenetración girando la rueda b
		# (sin añadir velocidad), para que no se desincronicen con el tiempo.
		var slop := deg_to_rad(0.05)
		if absf(pen) > slop and inv_ib > 0.0:
			var corr := (pen - signf(pen) * slop) * 0.5
			_rotate_group(jd.get("grp_b", [b]), b.global_position, axis, -corr)
			phase -= corr
	jd["phase"] = phase
	jd["torque"] = torque

## Cuerpos unidos rígidamente (uniones FIJAS, transitivo) a "body", incluido él.
func _rigid_group(body: RigidBody3D) -> Array:
	var group := [body]
	var i := 0
	while i < group.size():
		var cur: RigidBody3D = group[i]
		for c in _connections:
			if c.tipo != Connection.Tipo.FIJA:
				continue
			var other: RigidBody3D = null
			if _bodies.get(c.a_uid) == cur: other = _bodies.get(c.b_uid)
			elif _bodies.get(c.b_uid) == cur: other = _bodies.get(c.a_uid)
			if other and not group.has(other):
				group.append(other)
		i += 1
	return group

## Inversa del momento de inercia de un grupo rígido respecto de la recta
## (center, axis) — teorema de Steiner. 0 si el grupo está anclado.
func _group_inv_inertia(group: Array, center: Vector3, axis: Vector3) -> float:
	var total := 0.0
	for b in group:
		var body: RigidBody3D = b
		if body.freeze:
			return 0.0
		var st := PhysicsServer3D.body_get_direct_state(body.get_rid())
		if st == null:
			continue
		var inv: Basis = st.inverse_inertia_tensor
		var i_axis := 0.0
		if absf(inv.determinant()) > 1e-30:
			i_axis = axis.dot(inv.inverse() * axis)
		var r := body.global_position - center
		r -= axis * r.dot(axis)
		total += i_axis + body.mass * r.length_squared()
	return 1.0 / total if total > 0.0 else 0.0

## Gira rígidamente un grupo de cuerpos alrededor de la recta (center, axis).
func _rotate_group(group: Array, center: Vector3, axis: Vector3, ang: float) -> void:
	var rot := Basis(axis, ang)
	for b in group:
		var st := PhysicsServer3D.body_get_direct_state((b as RigidBody3D).get_rid())
		if st == null:
			continue
		var xf := st.transform
		xf.origin = center + rot * (xf.origin - center)
		xf.basis = rot * xf.basis
		st.transform = xf

## Par transmitido por un engranaje (N·m, último paso) — telemetría.
func gear_torque(uid: String) -> float:
	for jd in _joints:
		if (jd["conn"] as Connection).uid == uid:
			return jd.get("torque", 0.0)
	return 0.0

## Error de fase dentro del huelgo (rad) — telemetría/pruebas.
func gear_phase(uid: String) -> float:
	for jd in _joints:
		if (jd["conn"] as Connection).uid == uid:
			return jd.get("phase", 0.0)
	return 0.0

func _update_com() -> void:
	var com := center_of_mass()
	if _com_marker and com["mass"] > 0.0:
		_com_marker.global_position = com["pos"]

func center_of_mass() -> Dictionary:
	var total := 0.0
	var acc := Vector3.ZERO
	var seen := {}
	for uid in _bodies:
		var b: RigidBody3D = _bodies[uid]
		if is_instance_valid(b) and not seen.has(b):
			seen[b] = true
			acc += body_com(b) * b.mass
			total += b.mass
	return {"pos": (acc / total) if total > 0.0 else Vector3.ZERO, "mass": total}

## Centro de masa de un cuerpo en coordenadas de mundo (el propio, si es personalizado).
static func body_com(b: RigidBody3D) -> Vector3:
	if b.center_of_mass_mode == RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM:
		return b.global_transform * b.center_of_mass
	return b.global_position

func _make_com_marker() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.02
	s.height = 0.04
	mi.mesh = s
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.2, 0.5)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.2, 0.5)
	m.emission_energy_multiplier = 0.8
	mi.material_override = m
	return mi

#endregion

#region CONSULTA / TELEMETRÍA ---------------------------------------------------

func get_body(uid: String) -> RigidBody3D:
	return _bodies.get(uid)

## Transformación en vivo de una pieza (cuerpo × desplazamiento si está fundida
## en el cuerpo de su protoboard). null si no se simula.
func part_transform(uid: String):
	var b: RigidBody3D = _bodies.get(uid)
	if b == null or not is_instance_valid(b):
		return null
	return b.global_transform * (_body_offset.get(uid, Transform3D.IDENTITY) as Transform3D)

func telemetry(uid: String) -> Dictionary:
	var b: RigidBody3D = _bodies.get(uid)
	if b == null or not is_instance_valid(b):
		return {}
	# Posición y velocidad de la propia pieza (en un cuerpo de varias piezas, la de su
	# punto: v + ω × r).
	var p: Vector3 = (part_transform(uid) as Transform3D).origin
	var v := b.linear_velocity + b.angular_velocity.cross(p - body_com(b))
	return {
		"pos": p,
		"vel": v,
		"speed": v.length(),
		"ang_vel": b.angular_velocity,
		"ang_speed": b.angular_velocity.length(),
		"mass": b.mass,
	}

#endregion

#region ELECTRÓNICA Y CONTROL (Fase 3) ------------------------------------------

## Calcula el consumo del sistema: cada motor activo es una carga en paralelo
## sobre la batería; el solver (C#) devuelve corriente y potencia totales.
func _compute_electrical() -> void:
	var v := maxf(0.1, Config.battery_voltage)
	var resistors := []
	for conn in _connections:
		if conn.tipo == Connection.Tipo.BISAGRA and conn.motor_enabled:
			var frac: float = 1.0 if _stalled.get(conn.uid, false) else _motor_frac.get(conn.uid, 0.0)
			var i_motor: float = conn.elec_current_noload + (conn.elec_current_stall - conn.elec_current_noload) * frac
			resistors.append([1, 0, v / maxf(0.001, i_motor)])
	if resistors.is_empty():
		_elec = {"voltage": v, "current": 0.0, "power": 0.0, "autonomy_h": INF, "motors": 0}
		return
	var res: Dictionary = Electronics.SolveCircuit(2, resistors, [[1, 0, v]])
	var cur: float = res.get("main_current", 0.0)
	_elec = {
		"voltage": v, "current": cur, "power": res.get("total_power", 0.0),
		"autonomy_h": Electronics.Autonomy(cur, Config.battery_capacity_mah),
		"motors": resistors.size(),
	}

func _record_history() -> void:
	for uid in _history:
		var conn := _conn_by_uid(uid)
		if conn == null:
			continue
		var h: Dictionary = _history[uid]
		h["t"].append(_sim_time)
		h["sp"].append(conn.ctrl_setpoint)
		h["meas"].append(_ctrl_meas.get(uid, 0.0))
		if h["t"].size() > HIST_MAX:
			h["t"].pop_front(); h["sp"].pop_front(); h["meas"].pop_front()

func _conn_by_uid(uid: String) -> Connection:
	for c in _connections:
		if c.uid == uid:
			return c
	return null

func electrical() -> Dictionary:
	return _elec

## Lista de uniones con control activo (para elegir en la gráfica).
func controlled_uids() -> Array:
	return _history.keys()

func history(uid: String) -> Dictionary:
	return _history.get(uid, {})

func control_measure(uid: String) -> float:
	return _ctrl_meas.get(uid, 0.0)

#endregion
