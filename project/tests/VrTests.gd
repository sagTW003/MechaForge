extends Node
## VrTests — Pruebas del visor VR casero, empezando por la Fase 0 (prerrequisitos).
## Ejecutar:  Godot --headless --path project -- mfvr
##
## Fase 1: pantalla y móvil, lentes (geometría, masa y óptica de lente delgada),
## carcasa y soporte de lentes (cajas, colisión y masa), ESP32 por USB, bus I²C
## (alimentación, SDA/SCL, GND común, direcciones) y registros del MPU-6050.
## Fase 0: microcontrolador con memoria entre pasos («inicio:»/«bucle:», sin uniones),
## IMU MPU-6050 (fuerza específica, giroscopio, orientación de referencia, muestreo,
## ruido, sesgo, saturación, cuantización), materiales PLA/PETG/cartón y masa, centro
## de masa, inercia y colisión reales de las mallas importadas.

var main: Node
var ok: int = 0
var fail: int = 0

const G_REST := 9.8 / 9.80665      # lo que mide el acelerómetro en reposo (g)

func check(cond: bool, name: String) -> void:
	if cond:
		ok += 1
		print("  [OK]   %s" % name)
	else:
		fail += 1
		print("  [FALLO] %s" % name)

func wait_phys(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame

func run() -> void:
	print("[TEST] Visor VR — Fase 0 (microcontrolador, IMU, materiales, mallas)")
	_test_mcu_memory()
	_test_materials()
	_test_mesh_mass()
	_test_import_mass()
	await _test_imu_static()
	await _test_imu_motion()
	await _test_imu_noise()
	await _test_mcu_imu_loop()
	await _test_mesh_com_sim()
	await _test_cavity_collision()
	_test_properties_ui()
	print("[TEST] Visor VR — Fase 1 (pantalla, lentes, carcasa, ESP32 y bus I²C, óptica)")
	_test_vr_parts()
	await _test_housing()
	_test_screen_power()
	_test_i2c_bus()
	await _test_i2c_registers()
	await _test_phone_mcu()
	_test_optics()
	_test_vr_properties_ui()
	main._on_new()
	print("[TEST] Visor VR: %d OK, %d FALLOS" % [ok, fail])
	get_tree().quit(1 if fail > 0 else 0)

#region MICROCONTROLADOR --------------------------------------------------------

func _test_mcu_memory() -> void:
	main._on_new()
	var prog := "inicio:\n  n = 10\nbucle:\n  n = n + 1\n  output = n".split("\n")
	var st := {}
	var r := []
	for i in range(3):
		r.append(main._mcu_run(prog, 0.0, 0.0, 0.01, null, st))
	check(r == [11.0, 12.0, 13.0], "Microcontrolador: «inicio:» una vez y variables que se conservan (%s)" % str(r))
	check(main._mcu_run(prog, 0.0, 0.0, 0.01) == 11.0 and main._mcu_run(prog, 0.0, 0.0, 0.01) == 11.0,
		"Microcontrolador: sin memoria (validación) cada llamada empieza de cero")
	var acc := "acc = acc + 2".split("\n")
	var st2 := {}
	var r2 := []
	for i in range(3):
		r2.append(main._mcu_run(acc, 0.0, 0.0, 0.01, null, st2))
	check(r2 == [2.0, 4.0, 6.0], "Microcontrolador: una variable sin iniciar empieza en 0 e integra (%s)" % str(r2))
	var legacy: float = main._mcu_run("amp = 40\noutput = sin(t) * amp".split("\n"), PI / 2.0, 0.0, 0.01)
	check(absf(legacy - 40.0) < 1e-9, "Microcontrolador: los programas de antes funcionan igual (%.3f)" % legacy)
	var tern: float = main._mcu_run("y = (1) if (x >= 2) else (0)".split("\n"), 0.0, 3.0, 0.01)
	var cmp: float = main._mcu_run("x == 3".split("\n"), 0.0, 3.0, 0.01)
	check(tern == 1.0 and cmp == 1.0, "Microcontrolador: «>=» y «==» no se confunden con una asignación")

#endregion

#region MATERIALES --------------------------------------------------------------

func _test_materials() -> void:
	var ml = MaterialLibrary
	check(ml.has_material("pla") and ml.has_material("petg") and ml.has_material("carton"),
		"Materiales: PLA, PETG y cartón corrugado disponibles")
	check(ml.density("pla") == 1240.0 and ml.density("petg") == 1270.0 and ml.density("carton") == 250.0,
		"Materiales: densidades PLA 1240, PETG 1270 y cartón 250 kg/m³")
	check(ml.is_printable("pla") and ml.is_printable("petg") and not ml.is_printable("carton") and not ml.is_printable("abs"),
		"Materiales: solo PLA y PETG llevan el modelo de impresión (paredes + relleno)")
	var imp: Dictionary = ProceduralTextures.generate("impreso", Color(0.8, 0.8, 0.8), 0.5, 3)
	var alb: Image = imp["albedo"]
	var row0 := 0.0
	var row2 := 0.0
	for x in range(alb.get_width()):
		row0 += alb.get_pixel(x, 0).v
		row2 += alb.get_pixel(x, 2).v
	check(alb.get_width() == ProceduralTextures.SIZE and row2 > row0 * 1.03,
		"Textura «impreso»: capas de 4 px (centro del cordón más claro que la junta)")
	var car: Dictionary = ProceduralTextures.generate("carton", Color(0.64, 0.49, 0.32), 0.9, 3)
	check((car["albedo"] as Image).get_width() == ProceduralTextures.SIZE and car.has("normal"), "Textura «carton» generada")

#endregion

#region MALLAS: GEOMETRÍA DE PRUEBA ---------------------------------------------

## Dos triángulos de un cuadrilátero con la cara hacia "n".
func _quad(out: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	_tri(out, a, b, c, n)
	_tri(out, a, c, d, n)

func _tri(out: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	if (b - a).cross(c - a).dot(n) >= 0.0:
		out.append_array([a, b, c])
	else:
		out.append_array([a, c, b])

## Caja cerrada (hacia fuera, o hacia dentro para el hueco de una caja hueca).
func _box(center: Vector3, size: Vector3, inward := false) -> PackedVector3Array:
	var out := PackedVector3Array()
	var h := size * 0.5
	var s := -1.0 if inward else 1.0
	for ax in range(3):
		for sg in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[ax] = sg
			var u := Vector3.ZERO
			u[(ax + 1) % 3] = h[(ax + 1) % 3]
			var v := Vector3.ZERO
			v[(ax + 2) % 3] = h[(ax + 2) % 3]
			var c := center + n * h[ax]
			_quad(out, c - u - v, c + u - v, c + u + v, c - u + v, n * s)
	return out

## Vaso abierto por arriba: fondo y paredes de grosor t (sólido estanco con hueco).
func _cup(w: float, hgt: float, d: float, t: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var co := [Vector2(-w / 2, -d / 2), Vector2(w / 2, -d / 2), Vector2(w / 2, d / 2), Vector2(-w / 2, d / 2)]
	var ci := [Vector2(-w / 2 + t, -d / 2 + t), Vector2(w / 2 - t, -d / 2 + t), Vector2(w / 2 - t, d / 2 - t), Vector2(-w / 2 + t, d / 2 - t)]
	var ob := []
	var ot := []
	var it := []
	var ib := []
	for k in range(4):
		ob.append(Vector3(co[k].x, 0.0, co[k].y))
		ot.append(Vector3(co[k].x, hgt, co[k].y))
		it.append(Vector3(ci[k].x, hgt, ci[k].y))
		ib.append(Vector3(ci[k].x, t, ci[k].y))
	_quad(out, ob[0], ob[1], ob[2], ob[3], Vector3.DOWN)
	_quad(out, ib[0], ib[1], ib[2], ib[3], Vector3.UP)
	for k in range(4):
		var k2 := (k + 1) % 4
		var mid: Vector3 = (ob[k] + ob[k2]) * 0.5
		var outward := Vector3(mid.x, 0.0, mid.z).normalized()
		_quad(out, ob[k], ob[k2], ot[k2], ot[k], outward)
		_quad(out, ot[k], ot[k2], it[k2], it[k], Vector3.UP)
		_quad(out, it[k], it[k2], ib[k2], ib[k], -outward)
	return out

## Prisma triangular: triángulo rectángulo (0,0)-(a,0)-(0,b) en XY, extruido c en Z.
func _wedge(a: float, b: float, c: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var p := [Vector3(0, 0, 0), Vector3(a, 0, 0), Vector3(0, b, 0)]
	var q := [Vector3(0, 0, c), Vector3(a, 0, c), Vector3(0, b, c)]
	_tri(out, p[0], p[1], p[2], Vector3.FORWARD)
	_tri(out, q[0], q[1], q[2], Vector3.BACK)
	_quad(out, p[0], p[1], q[1], q[0], Vector3.DOWN)
	_quad(out, p[0], p[2], q[2], q[0], Vector3.LEFT)
	_quad(out, p[1], p[2], q[2], q[1], Vector3(b, a, 0).normalized())
	return out

func _write_obj(name: String, tris: PackedVector3Array) -> String:
	var path := ProjectSettings.globalize_path("user://%s.obj" % name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	for p in tris:
		f.store_line("v %.9f %.9f %.9f" % [p.x, p.y, p.z])
	for i in range(tris.size() / 3):
		f.store_line("f %d %d %d" % [3 * i + 1, 3 * i + 2, 3 * i + 3])
	f.close()
	return path

func _import(name: String, tris: PackedVector3Array) -> Dictionary:
	var def := MeshImporter.make_part_def(_write_obj(name, tris))
	PartLibrary.register(def)
	return def

#endregion

#region MALLAS: MASA ------------------------------------------------------------

func _test_mesh_mass() -> void:
	var mm = load("res://core/MeshMass.cs").new()
	var r: Dictionary = mm.Compute(_box(Vector3(0.3, 0.2, 0.1), Vector3.ONE * 0.1))
	var it: Array = r["inercia"]
	check(absf(float(r["volumen"]) - 1e-3) < 1e-8 and absf(float(r["area"]) - 0.06) < 1e-7 and r["cerrada"],
		"Masa de malla: cubo de 10 cm → V = 1000 cm³, A = 600 cm², estanco")
	check((r["centroide"] as Vector3).distance_to(Vector3(0.3, 0.2, 0.1)) < 1e-6,
		"Masa de malla: centroide de un cubo desplazado = su centro")
	var i0 := 1e-3 * 0.02 / 12.0
	check(absf(float(it[0]) - i0) < i0 * 1e-4 and absf(float(it[1]) - i0) < i0 * 1e-4 and absf(float(it[2]) - i0) < i0 * 1e-4
		and absf(float(it[3])) < i0 * 1e-4 and absf(float(it[4])) < i0 * 1e-4 and absf(float(it[5])) < i0 * 1e-4,
		"Masa de malla: inercia del cubo V·(a²+a²)/12 = %s y productos nulos" % str(i0))
	var hollow := _box(Vector3.ZERO, Vector3.ONE * 0.1)
	hollow.append_array(_box(Vector3.ZERO, Vector3.ONE * 0.08, true))
	var rh: Dictionary = mm.Compute(hollow)
	check(absf(float(rh["volumen"]) - (1e-3 - 0.08 * 0.08 * 0.08)) < 1e-8 and rh["cerrada"],
		"Masa de malla: caja hueca cerrada → V = 1000 − 512 = 488 cm³")
	var flipped := PackedVector3Array()
	var cube := _box(Vector3.ZERO, Vector3.ONE * 0.1)
	for i in range(cube.size() / 3):
		flipped.append_array([cube[3 * i], cube[3 * i + 2], cube[3 * i + 1]])
	var rf: Dictionary = mm.Compute(flipped)
	check(absf(float(rf["volumen"]) - 1e-3) < 1e-8 and rf["cerrada"], "Masa de malla: caras al revés → mismo volumen positivo")
	var open := cube.slice(0, cube.size() - 6)
	check(not bool(mm.Compute(open)["cerrada"]), "Masa de malla: una caja sin tapa no es estanca")

func _test_import_mass() -> void:
	main._on_new()
	var def := _import("vr_cubo", _box(Vector3.ZERO, Vector3.ONE * 0.1))
	check(PartLibrary.has_mesh_mass(def) and absf(PartLibrary.volume_m3(def) - 1e-3) < 1e-8,
		"Importado: el volumen es el de la malla estanca")
	var p: PartInstance = main._spawn(def["id"], "pla", Vector3(0, 0.05, 0))
	var expect := 1240.0 * (0.06 * 0.0008 + 0.2 * (1e-3 - 0.06 * 0.0008))
	check(absf(p.mass_kg() - expect) < 1e-6, "PLA impreso: paredes 0.8 mm + relleno 20 %% → %.4f kg (≈ %.4f)" % [p.mass_kg(), expect])
	p.set_print_setting("relleno", 1.0)
	check(absf(p.mass_kg() - 1.24) < 1e-6, "PLA impreso al 100 % → 1.24 kg (macizo)")
	p.material_id = "abs"
	check(absf(p.mass_kg() - 1.05) < 1e-6, "ABS (no imprimible) → masa maciza 1.05 kg")
	p.material_id = "pla"
	p.set_print_setting("relleno", 0.0)
	p.set_print_setting("paredes_mm", 100.0)
	check(absf(p.mass_kg() - 1.24) < 1e-6, "Paredes más gruesas que la pieza: nunca más que macizo")
	# Malla abierta: vuelve a la caja envolvente.
	var cube := _box(Vector3.ZERO, Vector3.ONE * 0.1)
	var dopen := _import("vr_abierta", cube.slice(0, cube.size() - 6))
	check(not PartLibrary.has_mesh_mass(dopen) and absf(PartLibrary.volume_m3(dopen) - 1e-3) < 1e-6,
		"Importado con malla abierta: volumen de la caja envolvente (como antes)")
	# Centroide de un prisma triangular: a/3, b/3 respecto al ángulo recto.
	var dw := _import("vr_cuna", _wedge(0.1, 0.06, 0.04))
	main._on_new()
	var pw: PartInstance = main._spawn(dw["id"], "abs", Vector3(0, 0.1, 0))
	var com := pw.com_local()
	check(com.distance_to(Vector3(-0.1 / 6.0, -0.06 / 6.0, 0.0)) < 1e-6 and absf(PartLibrary.volume_m3(dw) - 0.1 * 0.06 * 0.04 / 2.0) < 1e-9,
		"Importado: centro de masa de una cuña en (a/3, b/3) y V = abc/2 (%s)" % str(com))
	var st: Dictionary = main._stability_data()
	check((st["com"] as Vector3).distance_to(Vector3(0, 0.1, 0) + com) < 1e-6, "Estabilidad: usa el centro de masa real de la malla")

#endregion

#region IMU ---------------------------------------------------------------------

func _imu(pos: Vector3, rot := Vector3.ZERO, ideal := true, anchored := true) -> PartInstance:
	var p: PartInstance = main._spawn("imu", "abs", pos, rot)
	p.anchored = anchored
	if ideal:
		p.estado["imu"] = {"ideal": true}
	return p

func _sv(k: String) -> float:
	return float(main._mcu_sensor_vars.get(k, NAN))

func _test_imu_static() -> void:
	main._on_new()
	_imu(Vector3(0, 0.1, 0))
	var names := Sensors.variable_names(main.parts_root)
	check(names.has("imu1_ax") and names.has("imu1_gz") and names.has("imu1_yaw") and names.has("imu1_nueva"),
		"IMU: variables _ax/_ay/_az, _gx/_gy/_gz, _roll/_pitch/_yaw y _nueva")
	main.simulator.start([])
	await wait_phys(6)
	check(absf(_sv("imu1_az") - G_REST) < 1e-4 and absf(_sv("imu1_ax")) < 1e-4 and absf(_sv("imu1_ay")) < 1e-4,
		"IMU plana en reposo: az = +1 g (%.5f), ax = ay = 0" % _sv("imu1_az"))
	check(absf(_sv("imu1_gx")) < 1e-6 and absf(_sv("imu1_gy")) < 1e-6 and absf(_sv("imu1_gz")) < 1e-6, "IMU en reposo: giroscopio a 0")
	main.simulator.stop()
	# Inclinaciones: alabeo, cabeceo y guiñada en la convención del MPU-6050.
	main._on_new()
	_imu(Vector3(0, 0.1, 0), Vector3(deg_to_rad(30), 0, 0))
	_imu(Vector3(0.2, 0.1, 0), Vector3(0, 0, deg_to_rad(20)))
	_imu(Vector3(0.4, 0.1, 0), Vector3(0, deg_to_rad(40), 0))
	main.simulator.start([])
	await wait_phys(6)
	var roll_acc := rad_to_deg(atan2(_sv("imu1_ay"), _sv("imu1_az")))
	check(absf(_sv("imu1_roll") - 30.0) < 0.01 and absf(roll_acc - 30.0) < 0.01,
		"IMU: lado derecho abajo 30° → roll = +30° y atan2(ay, az) = %.2f°" % roll_acc)
	var ax2 := _sv("imu2_ax")
	var pitch_acc := rad_to_deg(atan2(-ax2, sqrt(pow(_sv("imu2_ay"), 2) + pow(_sv("imu2_az"), 2))))
	check(absf(_sv("imu2_pitch") + 20.0) < 0.01 and absf(pitch_acc + 20.0) < 0.01 and ax2 > 0.0,
		"IMU: morro arriba 20° → pitch = −20° y atan2(−ax, √(ay²+az²)) = %.2f°" % pitch_acc)
	check(absf(_sv("imu3_yaw") - 40.0) < 0.01 and absf(_sv("imu3_az") - G_REST) < 1e-4,
		"IMU: girada 40° a la izquierda → yaw = +40° (%.2f°), sin cambiar az" % _sv("imu3_yaw"))
	main.simulator.stop()

func _test_imu_motion() -> void:
	# Giro libre sin gravedad alrededor de la vertical: gz = ω, sin aceleración.
	main._on_new()
	var a := _imu(Vector3(0, 0.5, 0), Vector3.ZERO, true, false)
	var b := _imu(Vector3(0.3, 0.5, 0), Vector3.ZERO, true, false)
	main.simulator.start([])
	for pair in [[a, 1.0], [b, 10.0]]:
		var body: RigidBody3D = main.simulator.get_body((pair[0] as PartInstance).uid)
		body.gravity_scale = 0.0
		body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		body.angular_damp = 0.0
		body.angular_velocity = Vector3(0, pair[1], 0)
	await wait_phys(30)
	check(absf(_sv("imu1_gz") - rad_to_deg(1.0)) < 0.05 and absf(_sv("imu1_gx")) < 0.05 and absf(_sv("imu1_gy")) < 0.05,
		"IMU girando a 1 rad/s sobre la vertical → gz = %.3f °/s (57.296)" % _sv("imu1_gz"))
	check(absf(_sv("imu1_az")) < 0.01, "IMU sin gravedad (cuerpo libre) → az ≈ 0 g (%.4f)" % _sv("imu1_az"))
	check(_sv("imu2_gz") == 250.0, "IMU a 573 °/s con fondo de escala ±250 °/s → satura en 250")
	var yaw1 := _sv("imu1_yaw")
	await wait_phys(12)
	var dyaw := wrapf(_sv("imu1_yaw") - yaw1, -180.0, 180.0)
	check(absf(dyaw - rad_to_deg(1.0) * 0.1) < 0.6, "IMU: la guiñada de referencia avanza ω·t (%.2f° en 0.1 s)" % dyaw)
	main.simulator.stop()
	# Caída libre: la fuerza específica es nula.
	main._on_new()
	_imu(Vector3(0, 1.0, 0), Vector3.ZERO, true, false)
	main.simulator.start([])
	await wait_phys(12)
	var fa := Vector3(_sv("imu1_ax"), _sv("imu1_ay"), _sv("imu1_az")).length()
	check(fa < 0.02, "IMU en caída libre → |a| ≈ 0 g (%.4f)" % fa)
	main.simulator.stop()

func _test_imu_noise() -> void:
	main._on_new()
	var p := _imu(Vector3(0, 0.1, 0), Vector3.ZERO, false)
	var q := _imu(Vector3(0.2, 0.1, 0), Vector3.ZERO, false)
	q.estado["imu"] = {"odr_hz": 50.0}
	main.simulator.start([])
	var gz := []
	var ax := []
	var first_run := []
	var news := 0
	var held_ok := true
	var last_q := NAN
	for i in range(240):
		await wait_phys(1)
		if _sv("imu1_nueva") == 1.0:
			gz.append(_sv("imu1_gz"))
			ax.append(_sv("imu1_ax"))
		if _sv("imu2_nueva") == 1.0:
			news += 1
		elif not is_nan(last_q) and _sv("imu2_gz") != last_q:
			held_ok = false
		last_q = _sv("imu2_gz")
	first_run = gz.slice(0, 5)
	main.simulator.stop()
	var lsb := 250.0 / 32768.0
	var on_grid := true
	for v in gz:
		if absf(v / lsb - roundf(v / lsb)) > 1e-3:
			on_grid = false
	check(on_grid, "IMU: lecturas cuantizadas a 16 bits (múltiplos de %.5f °/s)" % lsb)
	var sd := _std(gz)
	var sd_expect := sqrt(pow(0.005 * sqrt(50.0), 2) + lsb * lsb / 12.0)
	check(gz.size() >= 195 and gz.size() <= 205, "IMU a 100 Hz con física a 120 Hz: %d muestras en 2 s" % gz.size())
	check(absf(sd - sd_expect) < sd_expect * 0.3, "IMU: ruido del giroscopio σ = %.4f °/s (datasheet: %.4f)" % [sd, sd_expect])
	var sda := _std(ax)
	check(absf(sda - 0.000400 * sqrt(50.0)) < 0.000400 * sqrt(50.0) * 0.3, "IMU: ruido del acelerómetro σ = %.2f mg (datasheet: 2.83)" % (sda * 1000.0))
	var mean := _mean(gz)
	check(absf(mean) <= 0.5 + 0.02 and absf(mean) > 1e-4, "IMU: sesgo del giroscopio (%.3f °/s, dentro de ±0.5)" % mean)
	check(news >= 98 and news <= 102 and held_ok, "IMU a 50 Hz: %d muestras en 2 s y entre muestras mantiene el valor" % news)
	# Misma pieza → mismo sesgo y mismo ruido en otra simulación (reproducible).
	main.simulator.start([])
	var again := []
	while again.size() < 5:
		await wait_phys(1)
		if _sv("imu1_nueva") == 1.0:
			again.append(_sv("imu1_gz"))
	main.simulator.stop()
	check(again == first_run, "IMU: cada pieza tiene siempre el mismo sesgo y ruido (simulación reproducible)")

func _mean(a: Array) -> float:
	var s := 0.0
	for v in a:
		s += float(v)
	return s / maxf(1.0, a.size())

func _std(a: Array) -> float:
	var m := _mean(a)
	var s := 0.0
	for v in a:
		s += pow(float(v) - m, 2)
	return sqrt(s / maxf(1.0, a.size() - 1))

func _test_mcu_imu_loop() -> void:
	# Placa + IMU sin uniones: el programa integra el giroscopio (memoria entre pasos).
	main._on_new()
	main._spawn("microcontrolador", "abs", Vector3(0.3, 0.1, 0))
	var p := _imu(Vector3(0, 0.5, 0), Vector3.ZERO, true, false)
	main.mcu_editor.text = "inicio:\n  yaw_est = 0\nbucle:\n  yaw_est = yaw_est + imu1_gz * dt\n  err = yaw_est - imu1_yaw"
	main._apply_mcu()
	check(main.mcu_enabled and main.mcu_target_uid == "" and str(main.mcu_status.text).contains("microcontrolador"),
		"Microcontrolador sin uniones: el programa queda activo en la placa")
	main.simulator.start([])
	var body: RigidBody3D = main.simulator.get_body(p.uid)
	body.gravity_scale = 0.0
	body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.angular_damp = 0.0
	body.angular_velocity = Vector3(0, 0.5, 0)
	await wait_phys(120)
	var v: Dictionary = main.mcu_last_vars
	check(v.has("yaw_est") and absf(float(v["yaw_est"])) > 20.0 and absf(float(v.get("err", 99.0))) < 1.0,
		"Integrar gz da la guiñada real (estimada %.2f°, error %.3f°)" % [float(v.get("yaw_est", 0.0)), float(v.get("err", 99.0))])
	var tel: Dictionary = main.api_telemetry("")
	check(tel.get("sensores", {}).has("imu1_gz") and tel.get("microcontrolador", {}).get("variables", {}).has("yaw_est"),
		"API: get_telemetry incluye los sensores y las variables del microcontrolador")
	main.simulator.stop()
	# IMU real quieta: la guiñada integrada deriva con el sesgo (no hay magnetómetro).
	main._on_new()
	main._spawn("microcontrolador", "abs", Vector3(0.3, 0.1, 0))
	var r := _imu(Vector3(0, 0.1, 0), Vector3.ZERO, false)
	main.mcu_editor.text = "yaw_est = yaw_est + imu1_gz * dt"
	main._apply_mcu()
	main.simulator.start([])
	await wait_phys(240)
	var bias: float = (main.mcu_sensors._imu_state[r.uid]["gb"] as Vector3).z
	var yaw_est := float(main.mcu_last_vars.get("yaw_est", 0.0))
	var t: float = main.mcu_time
	check(absf(yaw_est - bias * t) < 0.05 and absf(_sv("imu1_yaw")) < 1e-3,
		"Deriva: quieta, la guiñada integrada sube con el sesgo (%.3f° ≈ %.3f °/s · %.2f s)" % [yaw_est, bias, t])
	main.simulator.stop()
	# Filtro complementario (el del README) con una IMU real inclinada: converge a la
	# orientación verdadera salvo el error del sesgo del acelerómetro (±20 mg ≈ ±1.2°).
	main._on_new()
	main._spawn("microcontrolador", "abs", Vector3(0.3, 0.1, 0))
	_imu(Vector3(0, 0.1, 0), Vector3(deg_to_rad(25), 0, deg_to_rad(-10)), false)
	main.mcu_editor.text = COMPLEMENTARY
	main._apply_mcu()
	main.simulator.start([])
	await wait_phys(240)
	var cv: Dictionary = main.mcu_last_vars
	var er := absf(float(cv.get("roll", 99.0)) - _sv("imu1_roll"))
	var ep := absf(float(cv.get("pitch", 99.0)) - _sv("imu1_pitch"))
	check(er < 2.0 and ep < 2.0, "Filtro complementario: roll %.2f° (real %.2f°), pitch %.2f° (real %.2f°)" % [float(cv.get("roll", 0.0)), _sv("imu1_roll"), float(cv.get("pitch", 0.0)), _sv("imu1_pitch")])
	main.simulator.stop()
	main._stop_mcu()

const COMPLEMENTARY := """inicio:
  roll = atan2(imu1_ay, imu1_az) * 180 / pi
  pitch = atan2(-imu1_ax, sqrt(imu1_ay * imu1_ay + imu1_az * imu1_az)) * 180 / pi
bucle:
  roll_acc = atan2(imu1_ay, imu1_az) * 180 / pi
  pitch_acc = atan2(-imu1_ax, sqrt(imu1_ay * imu1_ay + imu1_az * imu1_az)) * 180 / pi
  roll = 0.98 * (roll + imu1_gx * dt) + 0.02 * roll_acc
  pitch = 0.98 * (pitch + imu1_gy * dt) + 0.02 * pitch_acc
  yaw = yaw + imu1_gz * dt"""

#endregion

#region MALLAS: CENTRO DE MASA Y COLISIÓN EN LA SIMULACIÓN ----------------------

func _test_mesh_com_sim() -> void:
	main._on_new()
	var dw := _import("vr_cuna2", _wedge(0.1, 0.06, 0.04))
	var pw: PartInstance = main._spawn(dw["id"], "abs", Vector3(0, 0.2, 0))
	pw.anchored = true
	main.simulator.start([])
	await wait_phys(2)
	var body: RigidBody3D = main.simulator.get_body(pw.uid)
	check(body.center_of_mass_mode == RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM and body.center_of_mass.distance_to(pw.com_local()) < 1e-6,
		"Simulación: el cuerpo usa el centro de masa de la malla")
	var com: Dictionary = main.simulator.center_of_mass()
	check((com["pos"] as Vector3).distance_to(Vector3(0, 0.2, 0) + pw.com_local()) < 1e-5,
		"Simulación: el marcador de centro de masa usa el de la malla")
	check(body.inertia.x > 0.0 and absf(body.mass - pw.mass_kg()) < 1e-6, "Simulación: masa e inercia de la malla real")
	main.simulator.stop()

func _shape_count(uid: String) -> int:
	var n := 0
	var body: RigidBody3D = main.simulator.get_body(uid)
	for c in body.get_children():
		if c is CollisionShape3D:
			n += 1
	return n

## Vaso de 12×8×12 cm con paredes de 6 mm: una bola soltada encima entra en el hueco
## con colisión de varias piezas convexas y se queda arriba con la caja envolvente.
func _test_cavity_collision() -> void:
	var dc := _import("vr_vaso", _cup(0.12, 0.08, 0.12, 0.006))
	var expect_v := 0.12 * 0.08 * 0.12 - 0.108 * 0.074 * 0.108
	check(PartLibrary.has_mesh_mass(dc) and absf(PartLibrary.volume_m3(dc) - expect_v) < 1e-8,
		"Vaso abierto: malla estanca con V = %.1f cm³" % (expect_v * 1e6))
	var results := {}
	for mode in ["multiple", "convexa", "caja"]:
		main._on_new()
		var cup: PartInstance = main._spawn(dc["id"], "pla", Vector3(0, 0.04, 0))
		cup.anchored = true
		cup.estado["colision"] = mode
		var ball: PartInstance = main._spawn("bola_loca_20", "ptfe", Vector3(0.01, 0.16, 0.005))
		main.simulator.start([])
		var n := _shape_count(cup.uid)
		var bb: RigidBody3D = main.simulator.get_body(ball.uid)
		await wait_phys(150)
		check(bb.continuous_cd, "Bola de 2 cm con detección continua de colisiones (%s)" % mode)
		results[mode] = [n, main.simulator.get_body(ball.uid).global_position.y]
		main.simulator.stop()
	check(int(results["multiple"][0]) > 1 and float(results["multiple"][1]) > 0.014 and float(results["multiple"][1]) < 0.025,
		"Colisión «varias piezas convexas»: %d piezas; la bola entra y se apoya en el fondo de 6 mm (y = %.4f m)" % [results["multiple"][0], results["multiple"][1]])
	check(int(results["convexa"][0]) == 1 and float(results["convexa"][1]) > 0.08,
		"Colisión «un casco convexo»: tapa el hueco (bola arriba, y = %.3f m)" % results["convexa"][1])
	check(int(results["caja"][0]) == 1 and float(results["caja"][1]) > 0.08,
		"Colisión «caja envolvente»: igual que antes (bola arriba, y = %.3f m)" % results["caja"][1])

#endregion

#region PANEL DE PROPIEDADES ------------------------------------------------------

func _find_text(n: Node, cls: String, txt: String) -> bool:
	if n.is_class(cls) and str(n.get("text")).contains(txt):
		return true
	for c in n.get_children():
		if _find_text(c, cls, txt):
			return true
	return false

func _test_properties_ui() -> void:
	main._on_new()
	var imu: PartInstance = main._spawn("imu", "abs", Vector3(0, 0.1, 0))
	main._select(imu)
	main._refresh_properties()
	check(_find_text(main.prop_container, "CheckBox", "Sensor ideal"), "Propiedades: la IMU muestra muestreo, fondos de escala y «Sensor ideal»")
	var dc := _import("vr_vaso_ui", _cup(0.12, 0.08, 0.12, 0.006))
	var cup: PartInstance = main._spawn(dc["id"], "pla", Vector3(0.3, 0.04, 0))
	main._select(cup)
	main._refresh_properties()
	check(_find_text(main.prop_container, "Label", "Impresión 3D") and _find_text(main.prop_container, "Label", "cerrada"),
		"Propiedades: pieza importada en PLA con impresión 3D, malla y colisión")

#endregion

#region FASE 1: PIEZAS DEL VISOR -------------------------------------------------

const FACE := Vector3.ZERO    # pantalla y lentes en su orientación por defecto (+Y arriba)

func _test_vr_parts() -> void:
	var ids := ["pantalla_55", "movil_61", "lente_cardboard_37", "lente_fresnel_50", "soporte_lentes", "carcasa_visor", "esp32_devkit"]
	var missing := ids.filter(func(i): return not PartLibrary.has_part(i))
	check(missing.is_empty(), "Fase 1: piezas del visor en la biblioteca (faltan: %s)" % str(missing))
	# Lente biconvexa: R = 2(n − 1)f, h = R − √(R² − r²), grosor = canto + 2h.
	var dl := PartLibrary.get_def("lente_cardboard_37")
	var R := 2.0 * 0.49 * 0.045
	var r := 0.0185
	var h := R - sqrt(R * R - r * r)
	var lg := PartLibrary.lens_geometry(dl)
	check(absf(float(lg["R"]) - R) < 1e-9 and absf(PartLibrary.dims_m(dl).y - (0.001 + 2.0 * h)) < 1e-9,
		"Lente Ø37 f = 45 mm: R = %.1f mm y grosor central %.2f mm" % [R * 1000.0, (0.001 + 2.0 * h) * 1000.0])
	# Volumen por integración numérica del perfil (camino independiente de la fórmula).
	var n := 4000
	var vnum := 0.0
	for i in range(n):
		var rho := r * (i + 0.5) / n
		var thick := 0.001 + 2.0 * (sqrt(R * R - rho * rho) - (R - h))
		vnum += TAU * rho * thick * r / n
	var vlib := PartLibrary.volume_m3(dl)
	check(absf(vlib - vnum) < vnum * 1e-5, "Lente: volumen %.0f mm³ = integral del perfil (%.0f mm³)" % [vlib * 1e9, vnum * 1e9])
	var mesh := MeshFactory.lens(lg["r"], lg["R"], lg["h"], lg["edge"], lg["fresnel"])
	check(absf(mesh.get_aabb().size.y - float(lg["t"])) < 1e-6 and absf(mesh.get_aabb().size.x - 2.0 * r) < 1e-4,
		"Lente: la malla mide lo mismo que su geometría (%.2f mm de grosor)" % (mesh.get_aabb().size.y * 1000.0))
	var df := PartLibrary.get_def("lente_fresnel_50")
	check(absf(PartLibrary.volume_m3(df) - PI * 0.025 * 0.025 * 0.002) < 1e-10 and absf(PartLibrary.dims_m(df).y - 0.002) < 1e-7,
		"Lente Fresnel Ø50: lámina de 2 mm (%.1f g en acrílico)" % (PartLibrary.volume_m3(df) * 1180.0 * 1000.0))

func _overlap_volume(boxes: Array) -> float:
	var tot := 0.0
	for i in range(boxes.size()):
		for j in range(i + 1, boxes.size()):
			var a := AABB((boxes[i]["c"] as Vector3) - (boxes[i]["s"] as Vector3) / 2.0, boxes[i]["s"])
			var b := AABB((boxes[j]["c"] as Vector3) - (boxes[j]["s"] as Vector3) / 2.0, boxes[j]["s"])
			var x := a.intersection(b)
			tot += x.size.x * x.size.y * x.size.z
	return tot

func _test_housing() -> void:
	var dc := PartLibrary.get_def("carcasa_visor")
	var boxes := PartLibrary.compound_boxes(dc)
	var L := 0.065
	var H := 0.095
	var W := 0.16
	var t := 0.0025
	var expect := t * H * W + 2.0 * (L - t) * (H - 2.0 * t) * t + ((L - t) * W - 0.03 * 0.016) * t + ((L - t) * W - 0.04 * 0.022) * t
	check(boxes.size() == 9 and _overlap_volume(boxes) < 1e-10,
		"Carcasa: 9 cajas sin solaparse (frente, laterales, techo con pasacables, suelo con nariz)")
	check(absf(PartLibrary.volume_m3(dc) - expect) < expect * 1e-5, "Carcasa: volumen de las paredes %.1f cm³ (cuenta a mano %.1f)" % [PartLibrary.volume_m3(dc) * 1e6, expect * 1e6])
	var mm := PartLibrary.mass_model(dc)
	check((mm["centroide"] as Vector3).x > 0.002, "Carcasa: el centro de masa se desplaza hacia la pared frontal (x = %.1f mm)" % ((mm["centroide"] as Vector3).x * 1000.0))
	var ds := PartLibrary.get_def("soporte_lentes")
	var sb := PartLibrary.compound_boxes(ds)
	check(sb.size() == 5 and absf(PartLibrary.volume_m3(ds) - (0.14 * 0.05 - 2.0 * 0.056 * 0.034) * 0.003) < 1e-10 and _overlap_volume(sb) < 1e-10,
		"Soporte de lentes: placa con dos ranuras de 56 × 34 mm (5 cajas)")
	# En la simulación: colisión de 9 cajas, con el hueco de la nariz de verdad.
	main._on_new()
	var shell: PartInstance = main._spawn("carcasa_visor", "pla", Vector3(0, H / 2.0, 0))
	shell.anchored = true
	main.simulator.start([])
	await wait_phys(2)
	var n := 0
	for c in main.simulator.get_body(shell.uid).get_children():
		if c is CollisionShape3D:
			n += 1
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var ray := func(p: Vector3) -> float:
		var q := PhysicsRayQueryParameters3D.create(p, p + Vector3.DOWN, 1)
		var hit := space.intersect_ray(q)
		return float(hit["position"].y) if not hit.is_empty() else -1.0
	var y_nose: float = ray.call(Vector3(-L / 2.0 + 0.01, 0.05, 0.0))
	var y_floor: float = ray.call(Vector3(-L / 2.0 + 0.01, 0.05, 0.05))
	check(n == 9 and absf(y_nose) < 1e-3 and absf(y_floor - t) < 1e-3,
		"Carcasa en simulación: %d formas; por el hueco de la nariz se llega al suelo (y = %.4f) y al lado se toca el fondo (y = %.4f)" % [n, y_nose, y_floor])
	var mass_ok := absf(main.simulator.get_body(shell.uid).center_of_mass.x - (mm["centroide"] as Vector3).x) < 1e-6
	check(mass_ok, "Carcasa en simulación: centro de masa de sus paredes")
	main.simulator.stop()

func _glass_energy(p: PartInstance) -> float:
	for mi in p.find_children("*", "MeshInstance3D", true, false):
		if mi.has_meta("pantalla_luz"):
			return ((mi as MeshInstance3D).material_override as StandardMaterial3D).emission_energy_multiplier
	return -1.0

func _wire(uid: String, a: PartInstance, ta: String, b: PartInstance, tb: String) -> Dictionary:
	return {"uid": uid, "a_key": main._key(a.uid, ta), "b_key": main._key(b.uid, tb), "tipo": "signal", "color": "auto"}

func _test_screen_power() -> void:
	main._on_new()
	var scr: PartInstance = main._spawn("pantalla_55", "abs", Vector3(0, 0.003, 0))
	var esp: PartInstance = main._spawn("esp32_devkit", "abs", Vector3(0.12, 0.005, 0))
	main.circuit_rt.step(0.01)
	var off := _glass_energy(scr)
	main.wires = [_wire("p1", esp, "5V", scr, "5V"), _wire("p2", esp, "GND", scr, "GND")]
	main.circuit_rt.invalidate()
	main.circuit_rt.step(0.01)
	check(off == 0.0 and main.circuit_rt.screen_powered(scr) and _glass_energy(scr) > 0.5,
		"Pantalla: apagada sin cables, encendida con 5 V de la ESP32 (USB)")
	var cur := absf(main.circuit_rt.voltage(main._key(scr.uid, "5V")) - main.circuit_rt.voltage(main._key(scr.uid, "GND"))) / 10.0
	check(absf(cur - 0.49) < 0.03, "Pantalla: consume ~0.5 A a 5 V (%.2f A)" % cur)
	main.wires = []
	var ph: PartInstance = main._spawn("movil_61", "aluminio_anodizado", Vector3(0, 0.004, 0.2))
	check(_glass_energy(ph) > 0.5, "Móvil: pantalla siempre encendida (batería propia)")

## Escena de bus I²C: ESP32 + IMU con los cables que se pidan.
func _bus_scene(pairs: Array, extra := []) -> Dictionary:
	main._on_new()
	var esp: PartInstance = main._spawn("esp32_devkit", "abs", Vector3(0.1, 0.005, 0))
	var imu: PartInstance = main._spawn("imu", "abs", Vector3(0, 0.004, 0))
	var ws := []
	for pr in pairs:
		ws.append(_wire("w%d" % ws.size(), esp, pr[0], imu, pr[1]))
	main.wires = ws + extra
	main.circuit_rt.invalidate()
	main.circuit_rt.solve_once()
	return {"esp": esp, "imu": imu, "st": I2CBus.statuses(main).get(imu.uid, {})}

const BUS_OK := [["3V3", "VCC"], ["GND2", "GND"], ["GPIO22", "SCL"], ["GPIO21", "SDA"]]

func _test_i2c_bus() -> void:
	main._on_new()
	var lone: PartInstance = main._spawn("imu", "abs", Vector3(0, 0.004, 0))
	var st0: Dictionary = I2CBus.statuses(main).get(lone.uid, {})
	check(st0.get("ok", false) and not st0.get("cableada", true), "Bus I²C: una IMU sin cables funciona directa (como antes)")
	var good := _bus_scene(BUS_OK)
	check(good["st"].get("ok", false) and good["st"].get("placa", "") == (good["esp"] as PartInstance).uid,
		"Bus I²C: VCC→3V3, GND, SCL→GPIO22 y SDA→GPIO21 → conectada (%s)" % good["st"].get("motivo", ""))
	var nognd := _bus_scene([["3V3", "VCC"], ["GPIO22", "SCL"], ["GPIO21", "SDA"]])
	check(not nognd["st"].get("ok", true) and str(nognd["st"].get("motivo", "")).contains("alimentación"),
		"Bus I²C: sin GND no hay alimentación (%s)" % nognd["st"].get("motivo", ""))
	var crossed := _bus_scene([["3V3", "VCC"], ["GND2", "GND"], ["GPIO22", "SDA"], ["GPIO21", "SCL"]])
	check(not crossed["st"].get("ok", true) and str(crossed["st"].get("motivo", "")).contains("cruzados"),
		"Bus I²C: SDA y SCL cruzados → no responde (%s)" % crossed["st"].get("motivo", ""))
	var half := _bus_scene([["3V3", "VCC"], ["GND2", "GND"], ["GPIO21", "SDA"]])
	check(not half["st"].get("ok", true) and str(half["st"].get("motivo", "")).contains("SCL"),
		"Bus I²C: falta SCL → no responde (%s)" % half["st"].get("motivo", ""))
	# Alimentada con otra batería y sin GND común con la placa.
	main._on_new()
	var esp: PartInstance = main._spawn("esp32_devkit", "abs", Vector3(0.1, 0.005, 0))
	var imu: PartInstance = main._spawn("imu", "abs", Vector3(0, 0.004, 0))
	var bat: PartInstance = main._spawn("bateria_18650", "abs", Vector3(-0.1, 0.01, 0))
	main.wires = [_wire("b1", bat, "V+", imu, "VCC"), _wire("b2", bat, "GND", imu, "GND"),
		_wire("b3", esp, "GPIO22", imu, "SCL"), _wire("b4", esp, "GPIO21", imu, "SDA")]
	main.circuit_rt.invalidate()
	main.circuit_rt.solve_once()
	var sg: Dictionary = I2CBus.statuses(main).get(imu.uid, {})
	check(not sg.get("ok", true) and str(sg.get("motivo", "")).contains("GND"), "Bus I²C: GND no común con la placa → no responde (%s)" % sg.get("motivo", ""))
	# 9 V en VCC: fuera de rango.
	main.wires = [_wire("b1", bat, "V+", imu, "VCC")]
	main._on_new()
	esp = main._spawn("esp32_devkit", "abs", Vector3(0.1, 0.005, 0))
	imu = main._spawn("imu", "abs", Vector3(0, 0.004, 0))
	var b9: PartInstance = main._spawn("bateria_9v", "acero", Vector3(-0.1, 0.01, 0))
	main.wires = [_wire("c1", b9, "V+", imu, "VCC"), _wire("c2", b9, "GND", imu, "GND"), _wire("c3", b9, "GND", esp, "GND"),
		_wire("c4", esp, "GPIO22", imu, "SCL"), _wire("c5", esp, "GPIO21", imu, "SDA")]
	main.circuit_rt.invalidate()
	main.circuit_rt.solve_once()
	var s9: Dictionary = I2CBus.statuses(main).get(imu.uid, {})
	check(not s9.get("ok", true) and str(s9.get("motivo", "")).contains("excesiva"), "Bus I²C: 9 V en VCC → tensión excesiva (%s)" % s9.get("motivo", ""))
	# Dos IMU en la misma dirección: conflicto; con AD0 alto (0x69), las dos responden.
	main._on_new()
	esp = main._spawn("esp32_devkit", "abs", Vector3(0.1, 0.005, 0))
	var i1: PartInstance = main._spawn("imu", "abs", Vector3(0, 0.004, 0))
	var i2: PartInstance = main._spawn("imu", "abs", Vector3(0, 0.004, 0.05))
	var ws := []
	for im in [i1, i2]:
		for pr in BUS_OK:
			ws.append(_wire("d%d" % ws.size(), esp, pr[0], im, pr[1]))
	main.wires = ws
	main.circuit_rt.invalidate()
	main.circuit_rt.solve_once()
	var sts := I2CBus.statuses(main)
	check(not sts[i1.uid]["ok"] and not sts[i2.uid]["ok"] and str(sts[i1.uid]["motivo"]).contains("repetida"),
		"Bus I²C: dos IMU en 0x68 → conflicto de dirección")
	i2.estado["i2c_dir"] = 0x69
	sts = I2CBus.statuses(main)
	check(sts[i1.uid]["ok"] and sts[i2.uid]["ok"] and int(sts[i2.uid]["dir"]) == 0x69, "Bus I²C: con AD0 a VCC (0x69) responden las dos")
	main.wires = []

func _test_i2c_registers() -> void:
	var sc := _bus_scene(BUS_OK)
	var imu: PartInstance = sc["imu"]
	imu.rotation = Vector3(0, 0, deg_to_rad(-20))       # morro abajo: ax < 0
	main.mcu_editor.text = "inicio:\n  quien = i2c_leer(0x68, 0x75)\n  dormido = i2c16(0x68, 0x3F)\n  ok = i2c_escribir(0x68, 0x6B, 0)\nbucle:\n  az = i2c16(0x68, 0x3F)\n  ax = i2c16(0x68, 0x3B)\n  temp = i2c16(0x68, 0x41) / 340 + 36.53\n  nadie = i2c_leer(0x69, 0x75)\n  hay = i2c_ok(0x68)"
	main._apply_mcu()
	check(main.mcu_enabled, "Registros: programa con i2c_… válido en la ESP32")
	imu.anchored = true
	main.simulator.start([])
	await wait_phys(30)
	var v: Dictionary = main.mcu_last_vars
	var az_exp := cos(deg_to_rad(20)) * 9.8 / 9.80665 * 16384.0
	var ax_exp := -sin(deg_to_rad(20)) * 9.8 / 9.80665 * 16384.0
	check(int(v.get("quien", 0)) == 0x68 and int(v.get("hay", 0)) == 1 and int(v.get("nadie", 0)) == -1,
		"Registros: WHO_AM_I = 0x68, i2c_ok(0x68) = 1 y nadie responde en 0x69 (−1)")
	check(int(v.get("dormido", 1)) == 0 and int(v.get("ok", 0)) == 1, "Registros: dormido al arrancar (datos a 0) hasta escribir PWR_MGMT_1 = 0")
	check(absf(float(v.get("az", 0)) - az_exp) < 600.0 and absf(float(v.get("ax", 0)) - ax_exp) < 600.0 and float(v.get("ax", 0)) < 0.0,
		"Registros: ACCEL_Z = %d (≈ %d) y ACCEL_X = %d (≈ %d, con signo) a ±2 g" % [int(v.get("az", 0)), int(az_exp), int(v.get("ax", 0)), int(ax_exp)])
	check(absf(float(v.get("temp", 0)) - 25.0) < 0.01, "Registros: temperatura %.2f °C (raw/340 + 36.53)" % float(v.get("temp", 0)))
	main.simulator.stop()
	# Fondo de escala por registro: ACCEL_CONFIG = 0x08 → ±4 g (8192 cuentas por g).
	main.mcu_editor.text = "inicio:\n  ok = i2c_escribir(0x68, 0x6B, 0) + i2c_escribir(0x68, 0x1C, 0x08)\nbucle:\n  az = i2c16(0x68, 0x3F)"
	main._apply_mcu()
	imu.rotation = Vector3.ZERO
	main.simulator.start([])
	await wait_phys(30)
	var az4 := float(main.mcu_last_vars.get("az", 0))
	check(absf(az4 - 8192.0 * 9.8 / 9.80665) < 300.0 and absf(_sv("imu1_az") - G_REST) < 0.05,
		"Registros: ACCEL_CONFIG = 0x08 → ±4 g: ACCEL_Z = %d (≈ 8187) y imu1_az sigue en g" % int(az4))
	main.simulator.stop()
	main._stop_mcu()
	check(is_nan(main._mcu_run("q = i2c_leer(0x68)".split("\n"), 0.0, 0.0, 0.01)), "Registros: número de argumentos incorrecto → error en el programa")
	check(is_nan(main._mcu_run("q = get(\"main\")".split("\n"), 0.0, 0.0, 0.01)) and is_nan(main._mcu_run("q = i2c_ok(0x68) + self".split("\n"), 0.0, 0.0, 0.01)),
		"Seguridad: el programa no puede llegar a objetos de la aplicación (sin base en la Expression)")
	main.wires = []

func _test_phone_mcu() -> void:
	main._on_new()
	var ph: PartInstance = main._spawn("movil_61", "aluminio_anodizado", Vector3(0, 0.004, 0))
	ph.anchored = true
	main.mcu_editor.text = "g = imu1_az"
	main._apply_mcu()
	check(main.mcu_enabled and Sensors.variable_names(main.parts_root).has("imu1_az"), "Móvil: corre el programa y su IMU interna es imu1")
	main.simulator.start([])
	await wait_phys(20)
	check(absf(float(main.mcu_last_vars.get("g", 0.0)) - G_REST) < 0.02 and _sv("imu1_ok") == 1.0, "Móvil: imu1_az = %.3f g en reposo" % float(main.mcu_last_vars.get("g", 0.0)))
	main.simulator.stop()
	main._stop_mcu()

## Pantalla en el origen mirando a +Y y lentes encima (eje Y) a "d" de su cara.
func _optics_scene(d: float, zs: Array, dy := []) -> Dictionary:
	main._on_new()
	var scr: PartInstance = main._spawn("pantalla_55", "abs", Vector3(0, 0.0, 0))
	var top := 0.003
	var lenses := []
	for i in range(zs.size()):
		var off: float = dy[i] if i < dy.size() else 0.0
		lenses.append(main._spawn("lente_cardboard_37", "acrilico", Vector3(zs[i], top + d, off)))
	return Optics.analyze(main.parts_root)

func _test_optics() -> void:
	var r := _optics_scene(0.040, [0.0315, -0.0315])
	var L: Dictionary = r["lentes"][0] if r["lentes"][0]["lado"] == "izquierda" else r["lentes"][1]
	var tan_k := 0.045 / (0.040 * 0.045 + 0.015 * 0.005)
	var fov_h := rad_to_deg(atan((0.0609 - 0.0315) * tan_k)) + rad_to_deg(atan(0.0315 * tan_k))
	var fov_v := 2.0 * rad_to_deg(atan(0.03425 * tan_k))
	check(r["ok"] and absf(float(L["distancia_mm"]) - 40.0) < 1e-3 and absf(float(L["aumento"]) - 9.0) < 1e-3 and absf(float(L["imagen_m"]) - 0.375) < 1e-4,
		"Óptica: pantalla a 40 mm de una lente de 45 mm → imagen virtual a 0.375 m del ojo, ×9")
	check(absf(float(L["fov_h"]) - fov_h) < 0.01 and absf(float(L["fov_v"]) - fov_v) < 0.01,
		"Óptica: campo %.1f° × %.1f° por ojo (tan θ = x·f / (d·f + e·(f − d)))" % [fov_h, fov_v])
	check(absf(float(r["ipd_mm"]) - 63.0) < 1e-3 and absf(float(L["ppd"]) - 2560.0 / 121.8 * (0.001875 / 0.045 * 1000.0) * PI / 180.0) < 1e-3,
		"Óptica: IPD 63 mm y %.1f píxeles por grado en el centro" % float(L["ppd"]))
	check(r["avisos"].is_empty() and str(L["lado"]) == "izquierda", "Óptica: visor bien montado, sin avisos (lente en +X = ojo izquierdo)")
	var far := _optics_scene(0.050, [0.0315, -0.0315])
	check(not far["lentes"][0]["enfocado"] and str(far["avisos"]).contains("borrosa"), "Óptica: pantalla más allá de la focal → aviso de imagen borrosa")
	var near := _optics_scene(0.040, [0.025, -0.025])
	check(str(near["avisos"]).contains("fuera del rango") and str(near["avisos"]).contains("centrada"),
		"Óptica: lentes a 50 mm → IPD fuera de rango y ejes descentrados de su mitad de pantalla")
	var tilt := _optics_scene(0.040, [0.0315, -0.0315], [0.0, 0.002])
	check(absf(float(tilt["desnivel_mm"]) - 2.0) < 1e-3 and str(tilt["avisos"]).contains("distinta altura"), "Óptica: lentes a distinta altura (2 mm) → aviso de visión doble")
	var api: Dictionary = main.api_headset()
	check(api.get("ok", false) and JSON.stringify(api).find("inf") < 0, "API: analyze_headset devuelve JSON válido")
	main._on_new()
	main._spawn("pantalla_55", "abs", Vector3.ZERO)
	main._spawn("lente_cardboard_37", "acrilico", Vector3(0, -0.04, 0))
	var behind := Optics.analyze(main.parts_root)
	check(not behind["ok"] and str(behind["motivo"]).contains("no apunta"), "Óptica: lente detrás de la pantalla → no apunta a su cara")

func _test_vr_properties_ui() -> void:
	_optics_scene(0.040, [0.0315, -0.0315])
	var lens: PartInstance = null
	for c in main.parts_root.get_children():
		if c is PartInstance and (c as PartInstance).def_id == "lente_cardboard_37":
			lens = c
	main._select(lens)
	main._refresh_properties()
	check(_find_text(main.prop_container, "Label", "Óptica del visor") and _find_text(main.prop_container, "Label", "×9.0"),
		"Propiedades: la lente muestra su óptica (imagen ×9.0, campo, IPD)")
	var sc := _bus_scene(BUS_OK)
	main._select(sc["imu"])
	main._refresh_properties()
	check(_find_text(main.prop_container, "Label", "conectada a ESP32"), "Propiedades: la IMU muestra el estado del bus I²C")
	main.wires = []

#endregion
