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
	# 1) Crear un cuerpo rígido por pieza.
	for child in _parts_root.get_children():
		if child is PartInstance and not child.is_queued_for_deletion():
			var part := child as PartInstance
			part.initial_transform = part.transform
			part.visible = false
			part.set_pick_enabled(false)
			_bodies[part.uid] = _make_body(part)
	# 2) Crear las uniones. Las piezas unidas no "duermen": en mecanismos pequeños
	# la velocidad lineal cae bajo el umbral de reposo de Jolt y se congelarían.
	for conn in _connections:
		_make_joint(conn)
		for u in [conn.a_uid, conn.b_uid]:
			if _bodies.has(u):
				(_bodies[u] as RigidBody3D).can_sleep = false
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
	for uid in _bodies:
		if is_instance_valid(_bodies[uid]):
			_discard(_bodies[uid])
	_bodies.clear()
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
	var cs := CollisionShape3D.new()
	cs.shape = part.make_collision_shape()
	body.add_child(cs)
	body.add_child(part.make_visual_clone())
	body.set_meta("part_uid", part.uid)
	# Anclada al mundo: cuerpo congelado (estático) — bancos de prueba, pistas.
	if part.anchored:
		body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		body.freeze = true
	if part.def.get("sin_colision", false):
		body.collision_layer = MARK_LAYER
		body.collision_mask = 0
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
	for jd in _joints:
		var conn: Connection = jd["conn"]
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
	for uid in _bodies:
		var b: RigidBody3D = _bodies[uid]
		if is_instance_valid(b):
			acc += b.global_position * b.mass
			total += b.mass
	return {"pos": (acc / total) if total > 0.0 else Vector3.ZERO, "mass": total}

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

func telemetry(uid: String) -> Dictionary:
	var b: RigidBody3D = _bodies.get(uid)
	if b == null or not is_instance_valid(b):
		return {}
	return {
		"pos": b.global_position,
		"vel": b.linear_velocity,
		"speed": b.linear_velocity.length(),
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
