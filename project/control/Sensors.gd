class_name Sensors
extends RefCounted
## Sensors — Lectura de sensores durante la simulación (API del microcontrolador).
##
## Cada sensor de la escena expone variables numeradas por tipo, en orden de
## colocación, que el programa del microcontrolador (script o bloques) puede usar:
##   distN        Ultrasonido: distancia (m) al obstáculo frente a su cara +X (máx. 4 m).
##   lidarN       LiDAR: distancia mínima (m) en un barrido de 360° (24 rayos, máx. 8 m).
##   encN         Encoder: ángulo acumulado (°) de giro sobre su eje propio (Y local).
##   imuN_ax/ay/az  IMU (MPU-6050): aceleración medida en g (fuerza específica: en
##                reposo y plana da az = +1 g; en caída libre, 0).
##   imuN_gx/gy/gz  IMU: velocidad angular en °/s alrededor de los ejes del chip.
##   imuN_roll/pitch/yaw  IMU: orientación VERDADERA en ° (referencia para comparar
##                lo que estime el programa; un MPU-6050 real no la da).
##   imuN_gyro    IMU: |ω| (rad/s);  imuN_nueva: 1 si en este paso llegó una muestra.
##   imuN_ok      IMU: 1 si responde. Un módulo con cables debe estar bien conectado
##                al bus I²C de una placa (I2CBus); sin ningún cable funciona directo.
##                El móvil cuenta como IMU (la suya interna).
##   finN         Final de carrera: 1 si algo toca su palanca (cara +Y, 3 mm), si no 0.
##   fuerzaN      Sensor de fuerza: fuerza de contacto sobre su cara (N).
##   lineaN       Sensor de línea (IR hacia abajo): 1 sobre la cinta negra, si no 0.
## Fuera de simulación todas valen 0 (útil para validar programas).
##
## IMU — ejes del chip como en un GY-521 montado plano con su flecha X hacia +X de la
## pieza: x adelante (+X), y a la izquierda (−Z), z arriba (+Y). Ángulos de Tait-Bryan
## ZYX en ese marco (convención del MPU-6050 y de los tutoriales de Arduino):
##   roll  > 0  lado derecho abajo   (giro alrededor de x; ≈ ∫gx dt)
##   pitch > 0  morro abajo          (giro alrededor de y; ≈ ∫gy dt)
##   yaw   > 0  gira a la izquierda  (giro alrededor de z; ≈ ∫gz dt)
## Con el acelerómetro: roll = atan2(ay, az), pitch = atan2(−ax, √(ay² + az²)).
## Modelo del sensor (parámetros en "imu" de la pieza y en su estado): muestreo a
## odr_hz (entre muestras se mantiene el último valor), ruido blanco con la densidad
## del datasheet en un ancho de banda odr/2, sesgo inicial por pieza (reproducible),
## deriva del sesgo del giroscopio (paseo aleatorio), saturación al fondo de escala y
## cuantización a 16 bits. Con "ideal" no hay ruido, sesgo, deriva ni cuantización.
## No hay magnetómetro: el yaw estimado integrando gz deriva, como en el real.

const KINDS := {
	"sensor_ultrasonido": "dist", "lidar": "lidar", "encoder": "enc", "imu": "imu", "movil_61": "imu",
	"final_carrera": "fin", "sensor_fuerza": "fuerza", "sensor_linea": "linea",
}
const DESCR := {
	"dist": "distancia ultrasonido (m)", "lidar": "distancia mínima LiDAR (m)", "enc": "ángulo encoder (°)",
	"imu": "IMU: _ax _ay _az (g), _gx _gy _gz (°/s), _roll _pitch _yaw (° reales), _nueva", "fin": "final de carrera (0/1)", "fuerza": "fuerza (N)", "linea": "línea bajo el sensor (0/1)",
}
const IMU_SUFFIXES := ["_ax", "_ay", "_az", "_gx", "_gy", "_gz", "_roll", "_pitch", "_yaw", "_gyro", "_nueva", "_ok"]

## Parámetros por defecto de la IMU (MPU-6050, datasheet rev. 3.4; sesgos residuales
## típicos tras calibrar). Se sobrescriben con "imu" de la definición y del estado.
const IMU_DEFAULTS := {
	"modelo": "MPU-6050",
	"odr_hz": 100.0,          # frecuencia de muestreo (Hz)
	"gyro_fs_dps": 250.0,     # fondo de escala del giroscopio: ±250/500/1000/2000 °/s
	"accel_fs_g": 2.0,        # fondo de escala del acelerómetro: ±2/4/8/16 g
	"gyro_ruido": 0.005,      # densidad de ruido del giroscopio (°/s/√Hz)
	"accel_ruido": 400.0,     # densidad de ruido del acelerómetro (µg/√Hz)
	"gyro_sesgo": 0.5,        # sesgo inicial máximo por eje (°/s)
	"accel_sesgo": 20.0,      # sesgo inicial máximo por eje (mg)
	"gyro_deriva": 0.002,     # paseo aleatorio del sesgo del giroscopio (°/s/√s)
	"ideal": false,           # sensor perfecto: sin ruido, sesgo, deriva ni cuantización
}
const G0 := 9.80665               # 1 g (m/s²)

var _enc_state: Dictionary = {}     # uid -> {q0, last, acc}
var _imu_state: Dictionary = {}     # uid -> estado del modelo de la IMU
## Estado del bus I²C de cada IMU con cables (uid -> I2CBus.status); lo fija Main.
var bus: Dictionary = {}
## Configuración escrita por registros durante la simulación (uid -> parámetros):
## fondos de escala y muestreo que el programa cambia con i2c_escribir.
var runtime: Dictionary = {}

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
			for suf in IMU_SUFFIXES:
				names.append(s["var"] + suf)
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
		# La transformación de la pieza (en un cuerpo de varias piezas fijas no es la
		# del cuerpo).
		var xf: Transform3D = sim.part_transform(part.uid)
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
				_read_imu(part, body, sim, v, vars)
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

#region IMU ---------------------------------------------------------------------

## Parámetros de la IMU de una pieza: IMU_DEFAULTS ← def["imu"] ← estado["imu"].
static func imu_params(part: PartInstance) -> Dictionary:
	var p: Dictionary = IMU_DEFAULTS.duplicate()
	p.merge(part.def.get("imu", {}), true)
	p.merge(part.estado.get("imu", {}), true)
	return p

## Orientación verdadera (°) de una base: Tait-Bryan ZYX en los ejes del chip.
static func imu_angles(b: Basis) -> Vector3:
	var bx := b.x.normalized()
	var by := b.y.normalized()
	var bz := b.z.normalized()
	return Vector3(
		rad_to_deg(atan2(-bz.y, by.y)),                 # roll
		rad_to_deg(-asin(clampf(bx.y, -1.0, 1.0))),     # pitch
		rad_to_deg(atan2(-bx.z, bx.x)))                 # yaw

## Inversa de imu_angles: base de la pieza (x adelante, y arriba, z a la derecha, en
## el mundo) con alabeo, cabeceo y guiñada (°) dados. En ejes del chip (x adelante,
## y izquierda, z arriba) es Rz(guiñada)·Ry(cabeceo)·Rx(alabeo).
static func imu_basis(rpy: Vector3) -> Basis:
	var r := deg_to_rad(rpy.x)
	var p := deg_to_rad(rpy.y)
	var y := deg_to_rad(rpy.z)
	var cr := cos(r)
	var sr := sin(r)
	var cp := cos(p)
	var sp := sin(p)
	var cy := cos(y)
	var sy := sin(y)
	var c1 := Vector3(cy * cp, sy * cp, -sp)
	var c2 := Vector3(cy * sp * sr - sy * cr, sy * sp * sr + cy * cr, cp * sr)
	var c3 := Vector3(cy * sp * cr + sy * sr, sy * sp * cr - cy * sr, cp * cr)
	# Del chip al mundo de Godot: (x, y, z) → (x, z, −y).
	var g := func(v: Vector3) -> Vector3: return Vector3(v.x, v.z, -v.y)
	return Basis(g.call(c1), g.call(c3), -g.call(c2))

## Parámetros en uso de una IMU: los de la pieza más lo escrito por registros.
func params_for(part: PartInstance) -> Dictionary:
	var p := imu_params(part)
	p.merge(runtime.get(part.uid, {}), true)
	return p

## Última muestra de una IMU en cuentas del ADC (lo que guardan sus registros):
## "ax".."gz" con el fondo de escala actual. 0 si aún no hay muestra.
func raw_counts(part: PartInstance, key: String) -> int:
	var st: Dictionary = _imu_state.get(part.uid, {})
	if st.is_empty():
		return 0
	var prm := params_for(part)
	var fs := float(prm["accel_fs_g"]) if key.begins_with("a") else float(prm["gyro_fs_dps"])
	return clampi(int(roundf(float(st["out"].get(key, 0.0)) / (fs / 32768.0))), -32768, 32767)

func _read_imu(part: PartInstance, body: RigidBody3D, sim: Simulator, v: String, vars: Dictionary) -> void:
	var prm := params_for(part)
	var xf: Transform3D = sim.part_transform(part.uid)
	var st: Dictionary = _imu_state.get(part.uid, {})
	if st.is_empty():
		st = _new_imu_state(part.uid, prm)
		_imu_state[part.uid] = st
	var t := sim.sim_time()
	var dt := t - float(st["t_last"])
	if dt > 1e-9:
		# Aceleración del punto donde está el chip: derivada de su velocidad.
		var vel: Vector3 = body.linear_velocity + body.angular_velocity.cross(xf.origin - Simulator.body_com(body))
		if st["has_v"]:
			st["a"] = (vel - (st["v_prev"] as Vector3)) / dt
		st["v_prev"] = vel
		st["has_v"] = true
		st["t_last"] = t
		st["nueva"] = false
		if t + 1e-9 >= float(st["t_next"]):
			_imu_sample(st, prm, xf.basis.orthonormalized(), body)
			var period := 1.0 / maxf(1.0, float(prm["odr_hz"]))
			st["t_next"] = float(st["t_next"]) + period
			if float(st["t_next"]) <= t:
				st["t_next"] = t + period
	var o: Dictionary = st["out"]
	var bs: Dictionary = bus.get(part.uid, {})
	var reachable := bs.is_empty() or bool(bs.get("ok", false))
	for k in o:
		vars[v + "_" + k] = o[k] if reachable else 0.0
	vars[v + "_ok"] = 1.0 if reachable else 0.0
	var ang := imu_angles(xf.basis)
	vars[v + "_roll"] = ang.x
	vars[v + "_pitch"] = ang.y
	vars[v + "_yaw"] = ang.z
	vars[v + "_gyro"] = body.angular_velocity.length()
	vars[v + "_nueva"] = 1.0 if st["nueva"] and reachable else 0.0

## Estado inicial: sesgos fijos por pieza (semilla = su uid, así cada IMU es siempre
## la misma de una simulación a otra) y salida a cero hasta la primera muestra.
func _new_imu_state(uid: String, prm: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(uid.hash()) + 1
	var gb := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * float(prm["gyro_sesgo"])
	var ab := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * float(prm["accel_sesgo"]) / 1000.0
	return {"rng": rng, "gb": gb, "ab": ab, "t_last": -1.0, "t_next": -1.0, "v_prev": Vector3.ZERO,
		"has_v": false, "a": Vector3.ZERO, "nueva": false,
		"out": {"ax": 0.0, "ay": 0.0, "az": 0.0, "gx": 0.0, "gy": 0.0, "gz": 0.0}}

## Una muestra del sensor: fuerza específica y velocidad angular en los ejes del chip,
## más sesgo, ruido, saturación y cuantización.
func _imu_sample(st: Dictionary, prm: Dictionary, b: Basis, body: RigidBody3D) -> void:
	var ex := b.x
	var ey := -b.z
	var ez := b.y
	var gdir: Vector3 = ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3.DOWN)
	var gvec: Vector3 = gdir * float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * body.gravity_scale
	var f: Vector3 = (st["a"] as Vector3) - gvec
	var acc := Vector3(f.dot(ex), f.dot(ey), f.dot(ez)) / G0
	var w := body.angular_velocity
	var gyr := Vector3(w.dot(ex), w.dot(ey), w.dot(ez)) * (180.0 / PI)
	var odr := maxf(1.0, float(prm["odr_hz"]))
	var gfs := float(prm["gyro_fs_dps"])
	var afs := float(prm["accel_fs_g"])
	var ideal := bool(prm["ideal"])
	if not ideal:
		var rng: RandomNumberGenerator = st["rng"]
		var sg := float(prm["gyro_ruido"]) * sqrt(odr * 0.5)
		var sa := float(prm["accel_ruido"]) * 1e-6 * sqrt(odr * 0.5)
		var walk := float(prm["gyro_deriva"]) * sqrt(1.0 / odr)
		st["gb"] = (st["gb"] as Vector3) + Vector3(rng.randfn(0.0, walk), rng.randfn(0.0, walk), rng.randfn(0.0, walk))
		gyr += (st["gb"] as Vector3) + Vector3(rng.randfn(0.0, sg), rng.randfn(0.0, sg), rng.randfn(0.0, sg))
		acc += (st["ab"] as Vector3) + Vector3(rng.randfn(0.0, sa), rng.randfn(0.0, sa), rng.randfn(0.0, sa))
	st["out"] = {
		"ax": _adc(acc.x, afs, ideal), "ay": _adc(acc.y, afs, ideal), "az": _adc(acc.z, afs, ideal),
		"gx": _adc(gyr.x, gfs, ideal), "gy": _adc(gyr.y, gfs, ideal), "gz": _adc(gyr.z, gfs, ideal),
	}
	st["nueva"] = true

## Saturación al fondo de escala y cuantización a 16 bits (LSB = fondo / 32768).
static func _adc(x: float, fs: float, ideal: bool) -> float:
	var y := clampf(x, -fs, fs)
	if ideal:
		return y
	var lsb := fs / 32768.0
	return clampf(roundf(y / lsb), -32768.0, 32767.0) * lsb

#endregion

func reset() -> void:
	_enc_state.clear()
	_imu_state.clear()
	runtime.clear()
