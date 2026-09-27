class_name Sensors
extends RefCounted
## Sensors — Lectura de sensores durante la simulación (API del microcontrolador).
##
## Cada sensor de la escena expone variables numeradas por tipo, en orden de
## colocación, que el programa del microcontrolador (script o bloques) puede usar:
##   distN        Ultrasonido: distancia (m) al obstáculo frente a su cara +X (máx. 4 m).
##   lidarN       LiDAR: distancia mínima (m) en un barrido de 360° (24 rayos, máx. 8 m).
##   encN         Encoder: ángulo acumulado (°) de giro sobre su eje propio (Y local).
##   imuN_pitch   IMU: cabeceo (°);  imuN_roll: alabeo (°);  imuN_gyro: |ω| (rad/s).
##   finN         Final de carrera: 1 si algo toca su palanca (cara +Y, 3 mm), si no 0.
##   fuerzaN      Sensor de fuerza: fuerza de contacto sobre su cara (N).
##   lineaN       Sensor de línea (IR hacia abajo): 1 sobre la cinta negra, si no 0.
## Fuera de simulación todas valen 0 (útil para validar programas).

const KINDS := {
	"sensor_ultrasonido": "dist", "lidar": "lidar", "encoder": "enc", "imu": "imu",
	"final_carrera": "fin", "sensor_fuerza": "fuerza", "sensor_linea": "linea",
}
const DESCR := {
	"dist": "distancia ultrasonido (m)", "lidar": "distancia mínima LiDAR (m)", "enc": "ángulo encoder (°)",
	"imu": "IMU: _pitch, _roll (°), _gyro (rad/s)", "fin": "final de carrera (0/1)", "fuerza": "fuerza (N)", "linea": "línea bajo el sensor (0/1)",
}

var _enc_state: Dictionary = {}     # uid -> {q0, last, acc}

## [{var, kind, part}] de los sensores de la escena (orden estable).
static func list(parts_root: Node) -> Array:
	var out := []
	var count := {}
	for c in parts_root.get_children():
		if not (c is PartInstance):
			continue
		var kind: String = KINDS.get((c as PartInstance).def_id, "")
		if kind == "":
			continue
		count[kind] = int(count.get(kind, 0)) + 1
		out.append({"var": "%s%d" % [kind, count[kind]], "kind": kind, "part": c})
	return out

## Nombres de variables disponibles (para validar y para el editor de bloques).
static func variable_names(parts_root: Node) -> Array:
	var names := []
	for s in list(parts_root):
		if s["kind"] == "imu":
			names.append_array([s["var"] + "_pitch", s["var"] + "_roll", s["var"] + "_gyro"])
		else:
			names.append(s["var"])
	return names

## Variables con valor 0 (validación fuera de simulación).
static func zero_vars(parts_root: Node) -> Dictionary:
	var d := {}
	for n in variable_names(parts_root):
		d[n] = 0.0
	return d

## Lee todos los sensores. "sim" es el Simulator (cuerpos rígidos activos).
func read(parts_root: Node, sim: Simulator, space: PhysicsDirectSpaceState3D) -> Dictionary:
	var vars := zero_vars(parts_root)
	for s in list(parts_root):
		var part: PartInstance = s["part"]
		var body := sim.get_body(part.uid) if sim and sim.is_running() else null
		var v: String = s["var"]
		if body == null:
			continue
		var xf := body.global_transform
		var half := PartLibrary.dims_m(part.def) * 0.5
		match s["kind"]:
			"dist":
				var dir := xf.basis.x.normalized()
				vars[v] = _ray(space, xf.origin + dir * (half.x + 0.001), dir, 4.0, body)
			"lidar":
				var best := 8.0
				for k in range(24):
					var ang := TAU * k / 24.0
					var dir := (xf.basis.x * cos(ang) + xf.basis.z * sin(ang)).normalized()
					best = minf(best, _ray(space, xf.origin + dir * (maxf(half.x, half.z) + 0.001), dir, 8.0, body))
				vars[v] = best
			"enc":
				vars[v] = _encoder(part.uid, xf.basis)
			"imu":
				var up := xf.basis.y.normalized()
				var fwd := xf.basis.x.normalized()
				vars[v + "_pitch"] = rad_to_deg(asin(clampf(fwd.y, -1.0, 1.0)))
				vars[v + "_roll"] = rad_to_deg(atan2(xf.basis.z.normalized().y, up.y))
				vars[v + "_gyro"] = body.angular_velocity.length()
			"fin":
				var dir := xf.basis.y.normalized()
				vars[v] = 1.0 if _ray(space, xf.origin + dir * (half.y + 0.0005), dir, 0.003, body) < 0.003 else 0.0
			"fuerza":
				vars[v] = _contact_force(body)
			"linea":
				# Infrarrojo hacia abajo: 1 si ve la cinta negra (capa de marcas).
				var down := -xf.basis.y.normalized()
				var q := PhysicsRayQueryParameters3D.create(xf.origin + down * (half.y + 0.0005), xf.origin + down * 0.05, Simulator.MARK_LAYER)
				vars[v] = 0.0 if space.intersect_ray(q).is_empty() else 1.0
	return vars

static func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, max_d: float, exclude: RigidBody3D) -> float:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * max_d, 1)
	q.exclude = [exclude.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return max_d
	return from.distance_to(hit["position"])

## Ángulo acumulado (con desenrollado) de giro alrededor del eje Y local inicial.
func _encoder(uid: String, b: Basis) -> float:
	var q := b.get_rotation_quaternion()
	if not _enc_state.has(uid):
		_enc_state[uid] = {"q0": q, "last": 0.0, "acc": 0.0}
	var st: Dictionary = _enc_state[uid]
	var rel: Quaternion = (st["q0"] as Quaternion).inverse() * q
	var ang := 2.0 * atan2(rel.y, rel.w)                # giro alrededor de Y local
	var d := wrapf(ang - float(st["last"]), -PI, PI)
	st["last"] = ang
	st["acc"] = float(st["acc"]) + d
	return rad_to_deg(float(st["acc"]))

## Suma de los impulsos de contacto / dt (requiere contact_monitor en el cuerpo).
static func _contact_force(body: RigidBody3D) -> float:
	var st := PhysicsServer3D.body_get_direct_state(body.get_rid())
	if st == null:
		return 0.0
	var imp := 0.0
	for i in range(st.get_contact_count()):
		imp += st.get_contact_impulse(i).length()
	return imp * float(Engine.physics_ticks_per_second)

func reset() -> void:
	_enc_state.clear()
