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
var _elec_accum: float = 0.0
const HIST_MAX := 300
const HIST_PERIOD := 0.033          # ~30 Hz de muestreo para las gráficas

const WORLD_LAYER := 1

func setup(parts_root: Node3D, sim_root: Node3D) -> void:
	_parts_root = parts_root
	_sim_root = sim_root

func is_running() -> bool:
	return _running

#region ARRANQUE / PARADA -------------------------------------------------------

func start(connections: Array) -> void:
	if _running:
		return
	_connections = connections
	_build_ground()
	# 1) Crear un cuerpo rígido por pieza.
	for child in _parts_root.get_children():
		if child is PartInstance:
			var part := child as PartInstance
			part.initial_transform = part.transform
			part.visible = false
			part.set_pick_enabled(false)
			_bodies[part.uid] = _make_body(part)
	# 2) Crear las uniones.
	for conn in _connections:
		_make_joint(conn)
	# 3) Marcador de centro de masa.
	_com_marker = _make_com_marker()
	_sim_root.add_child(_com_marker)
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
	for j in _joints:
		if is_instance_valid(j["joint"]):
			j["joint"].queue_free()
	_joints.clear()
	for uid in _bodies:
		if is_instance_valid(_bodies[uid]):
			_bodies[uid].queue_free()
	_bodies.clear()
	if _com_marker: _com_marker.queue_free()
	if _ground: _ground.queue_free()
	for uid in _pid_ids:
		Electronics.PidDestroy(_pid_ids[uid])
	_pid_ids.clear(); _ctrl_angle.clear(); _runtime_target.clear()
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
		_joints.append({"conn": conn, "joint": null, "a": a, "b": b})
		return

	# La bisagra usa HingeJoint3D (motor y límites robustos en Jolt).
	if conn.tipo == Connection.Tipo.BISAGRA:
		var hinge := HingeJoint3D.new()
		_sim_root.add_child(hinge)
		hinge.global_transform = Transform3D(_axis_basis(conn.axis_vector()), conn.anchor)
		hinge.node_a = hinge.get_path_to(a)
		hinge.node_b = hinge.get_path_to(b)
		if conn.limit_enabled:
			hinge.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
			hinge.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, conn.limit_lower)
			hinge.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, conn.limit_upper)
		if conn.motor_enabled:
			hinge.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR, true)
			hinge.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, conn.motor_target_speed)
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
		elif conn.tipo == Connection.Tipo.ENGRANAJE:
			_drive_gear(jd)
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
	var axis := conn.axis_vector().normalized()
	var omega: float = (b.angular_velocity - a.angular_velocity).dot(axis)
	# Ángulo relativo acumulado (integración de la velocidad).
	_ctrl_angle[conn.uid] = _ctrl_angle.get(conn.uid, 0.0) + omega * delta
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
	var cmd: float = Electronics.PidUpdate(pid, meas, delta)
	_runtime_target[conn.uid] = clampf(cmd, -conn.motor_noload_speed, conn.motor_noload_speed)

## Motor de bisagra con curva torque–velocidad de motor DC:
##   torque disponible = stall * (1 - |ω| / ω_sin_carga), acotado a [0, stall].
func _drive_motor(jd: Dictionary) -> void:
	var conn: Connection = jd["conn"]
	var hinge: HingeJoint3D = jd["joint"]
	var a: RigidBody3D = jd["a"]
	var b: RigidBody3D = jd["b"]
	var axis := conn.axis_vector().normalized()
	# Curva torque–velocidad de motor DC: torque disponible cae con la velocidad.
	var omega: float = (b.angular_velocity - a.angular_velocity).dot(axis)
	var frac := clampf(1.0 - absf(omega) / maxf(0.001, conn.motor_noload_speed), 0.0, 1.0)
	var torque := conn.motor_stall_torque * frac
	_motor_frac[conn.uid] = frac
	var step := 1.0 / float(Engine.physics_ticks_per_second)
	# Objetivo efectivo: el del controlador si hay control, si no el fijo.
	var target: float = _runtime_target.get(conn.uid, conn.motor_target_speed)
	# Alimentación por circuito (F1): el voltaje/PWM cableado escala el motor.
	var duty: float = clampf(conn.elec_duty, 0.0, 1.0)
	hinge.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY, target * duty)
	hinge.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE, torque * duty * step)

## Engranaje acoplado cinemáticamente: ω_b(eje) = -ratio * ω_a(eje).
func _drive_gear(jd: Dictionary) -> void:
	var conn: Connection = jd["conn"]
	var a: RigidBody3D = jd["a"]
	var b: RigidBody3D = jd["b"]
	var axis := conn.axis_vector().normalized()
	var wa: float = a.angular_velocity.dot(axis)
	var target_b := -conn.effective_gear_ratio() * wa
	var wb_now: Vector3 = b.angular_velocity
	# Sustituye solo la componente sobre el eje, preserva el resto.
	b.angular_velocity = wb_now - axis * wb_now.dot(axis) + axis * target_b

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
			var frac: float = _motor_frac.get(conn.uid, 0.0)
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
