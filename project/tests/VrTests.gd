extends Node
## VrTests — Pruebas del visor VR casero, empezando por la Fase 0 (prerrequisitos).
## Ejecutar:  Godot --headless --path project -- mfvr
##
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
