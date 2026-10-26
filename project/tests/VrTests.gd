extends Node
## VrTests — Pruebas del visor VR casero, empezando por la Fase 0 (prerrequisitos).
## Ejecutar:  Godot --headless --path project -- mfvr
## (sin --headless se añade el render real: bolas en direcciones conocidas de cada ojo;
## con la variable MF_VR_DUMP=<carpeta> guarda las imágenes renderizadas)
##
## Fase 5: las gafas completas montadas solo con la API (como OpenClaw), errores de la
## API y la carta de calibración del ejemplo de la cabeza.
## Fase 4: verificación óptica (distorsión y color residuales, desalineación, prisma
## por la IPD del render y del usuario), ergonomía, holguras y vista a través de la lente.
## Fase 3: perfiles de consigna, cabeza de prueba, base de la IMU, latencia y deriva,
## y el ejemplo de la cabeza motorizada (seguimiento real frente a estimado).
## Fase 2: render estéreo (ojos sobre el eje de cada lente, frustum con la distorsión,
## la cuenta del shader píxel → dirección y su inversa, capas, simulación).
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
	if "fase5" in OS.get_cmdline_user_args():
		await _run_phase5()
		main._on_new()
		print("[TEST] Visor VR: %d OK, %d FALLOS" % [ok, fail])
		get_tree().quit(1 if fail > 0 else 0)
		return
	if "fase4" in OS.get_cmdline_user_args():
		await _run_phase4()
		main._on_new()
		print("[TEST] Visor VR: %d OK, %d FALLOS" % [ok, fail])
		get_tree().quit(1 if fail > 0 else 0)
		return
	if "fase3" in OS.get_cmdline_user_args():
		await _run_phase3()
		main._on_new()
		print("[TEST] Visor VR: %d OK, %d FALLOS" % [ok, fail])
		get_tree().quit(1 if fail > 0 else 0)
		return
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
	print("[TEST] Visor VR — Fase 2 (render estéreo)")
	_test_rig_layout()
	_test_rig_mapping()
	await _test_rig_cameras()
	await _test_rig_sim()
	await _test_rig_render()
	await _run_phase3()
	await _run_phase4()
	await _run_phase5()
	main._on_new()
	print("[TEST] Visor VR: %d OK, %d FALLOS" % [ok, fail])
	get_tree().quit(1 if fail > 0 else 0)

#region MICROCONTROLADOR --------------------------------------------------------

func _run_phase3() -> void:
	print("[TEST] Visor VR — Fase 3 (cabeza de prueba y seguimiento con la IMU)")
	_test_profiles()
	_test_imu_basis()
	_test_head_part()
	_test_latency_estimator()
	await _test_fixed_fusion()
	await _test_head_motion()
	await _test_head_tracking_variants()
	await _test_tracking_ui()

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
	var r: Dictionary = MeshTools.Compute(_box(Vector3(0.3, 0.2, 0.1), Vector3.ONE * 0.1))
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
	var rh: Dictionary = MeshTools.Compute(hollow)
	check(absf(float(rh["volumen"]) - (1e-3 - 0.08 * 0.08 * 0.08)) < 1e-8 and rh["cerrada"],
		"Masa de malla: caja hueca cerrada → V = 1000 − 512 = 488 cm³")
	var flipped := PackedVector3Array()
	var cube := _box(Vector3.ZERO, Vector3.ONE * 0.1)
	for i in range(cube.size() / 3):
		flipped.append_array([cube[3 * i], cube[3 * i + 2], cube[3 * i + 1]])
	var rf: Dictionary = MeshTools.Compute(flipped)
	check(absf(float(rf["volumen"]) - 1e-3) < 1e-8 and rf["cerrada"], "Masa de malla: caras al revés → mismo volumen positivo")
	var open := cube.slice(0, cube.size() - 6)
	check(not bool(MeshTools.Compute(open)["cerrada"]), "Masa de malla: una caja sin tapa no es estanca")

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

#region FASE 2: RENDER ESTÉREO ---------------------------------------------------

const VR_EXAMPLE := "res://templates/12_gafas_vr.mforge"

func _rig() -> HeadsetRig:
	return main.headset_rig

func _vr_layout(q := 1.0) -> Dictionary:
	return HeadsetRig.compute_layout(main.parts_root, Callable(main, "_part_live_xform"), q)

func _part_by_def(id: String) -> Array:
	var out := []
	for c in main.parts_root.get_children():
		if c is PartInstance and (c as PartInstance).def_id == id:
			out.append(c)
	return out

## Dirección (tangentes) con que el ojo verá una esquina de su mitad de pantalla,
## calculada aparte (lente delgada + distorsión, canal azul = el más ampliado).
func _corner_tan(du: float, dw: float, s: float, k1: float, k2: float, dl: float) -> Vector2:
	return Optics.distort(Vector2(du, dw) * s * (1.0 + dl), k1, k2)

func _test_rig_layout() -> void:
	main._open_example(VR_EXAMPLE)
	var lay := _vr_layout()
	check(lay.get("ok", false) and lay["estereo"] and (lay["eyes"] as Array).size() == 2 and str(lay["eyes"][0]["lado"]) == "izquierda",
		"Render: el ejemplo da dos ojos, el izquierdo primero")
	check(absf(float(lay["ipd_m"]) - 0.063) < 1e-4, "Render: cámaras separadas 63 mm, como las lentes (%.2f mm)" % (float(lay["ipd_m"]) * 1000.0))
	var scr: PartInstance = _part_by_def("pantalla_55")[0]
	var sx: Transform3D = scr.global_transform
	var n := sx.basis.y.normalized()
	var worst := 0.0
	for e in lay["eyes"]:
		var lens: PartInstance = main._find_part(str(e["uid"]))
		var ew: Vector3 = sx * (e["pos_local"] as Vector3)
		worst = maxf(worst, ew.distance_to(lens.global_position + n * 0.015))
	check(worst < 2e-4, "Render: cada ojo está sobre el eje de su lente, a 15 mm de ella (error %.3f mm)" % (worst * 1000.0))
	var e0: Dictionary = lay["eyes"][0]
	var s := 0.045 / (0.040 * 0.045 + 0.015 * 0.005)
	var dl := 0.015 * 0.040 / ((0.040 * 0.045 + 0.015 * 0.005) * 2.0 * 57.0)
	check(absf(float(e0["escala"]) - s) < 1e-4 and absf((e0["cromatica"] as Vector3).z - 1.0 - dl) < 1e-6 and absf(1.0 - (e0["cromatica"] as Vector3).x - dl) < 1e-6,
		"Render: escala de la lente %.1f /m y ±%.2f %% para azul/rojo (acrílico, Abbe 57)" % [s, dl * 100.0])
	# Ojo izquierdo: su mitad va de x = −60.9 mm a 0 (espectador) y el eje está en −31.5 mm.
	var t_out := _corner_tan(-0.0294, 0.03425, s, 0.215, 0.215, dl)
	var t_in := _corner_tan(0.0315, 0.03425, s, 0.215, 0.215, dl)
	var ta := 0.0185 / 0.015
	var tans: Vector4 = e0["tans"]
	var px := 1.0 / ((1600.0 / 0.1218) / s)
	check(absf(tans.x - t_out.x) < 2.0 * px and absf(tans.y - t_in.x) < 2.0 * px,
		"Render: frustum horizontal del ojo izquierdo de %.3f a %.3f (esquinas de su mitad, con la distorsión)" % [tans.x, tans.y])
	check(absf(tans.w - ta) < 1e-4 and absf(tans.z + ta) < 1e-4 and t_in.y > ta,
		"Render: en vertical lo recorta el borde de la lente (tan = r/e = %.3f)" % ta)
	var sz: Vector2i = e0["size"]
	check(lay["comp_size"] == Vector2i(1600, 900) and absi(sz.y - int(ceil(2.0 * ta / px))) <= 1 and absi(sz.x - int(round((t_in.x - t_out.x) / px))) <= 2,
		"Render: imagen de 1600×900 y %d×%d px por ojo (misma densidad que la pantalla en el centro)" % [sz.x, sz.y])
	var eh := _vr_layout(0.5)
	check(absi((eh["eyes"][0]["size"] as Vector2i).y - int(ceil(sz.y * 0.5))) <= 1, "Render: la calidad ½ divide la resolución de cada ojo")

func _test_rig_mapping() -> void:
	main._open_example(VR_EXAMPLE)
	var lay := _vr_layout()
	var a: Vector2 = lay["area"]
	var e0: Dictionary = lay["eyes"][0]
	var c: Vector2 = e0["centro"]
	var uv_c := Vector2(c.x / a.x + 0.5, 0.5 - c.y / a.y)
	var r0 := HeadsetRig.screen_to_eye(lay, uv_c)
	check(int(r0["ojo"]) == 0 and (r0["t"] as Vector2).length() < 1e-6, "Shader: el píxel del eje de la lente se ve de frente (t = 0)")
	var uv_10 := Vector2((c.x + 0.010) / a.x + 0.5, uv_c.y)
	var s: float = e0["escala"]
	var tg: Vector2 = HeadsetRig.screen_to_eye(lay, uv_10)["t"]
	var lin := 0.010 * s
	var want := lin * (1.0 + 0.215 * lin * lin + 0.215 * pow(lin, 4))
	check(absf(tg.x - want) < 1e-5 and absf(tg.y) < 1e-6, "Shader: 10 mm a la derecha del eje → tan %.5f (lente %.4f + distorsión de cojín)" % [tg.x, lin])
	var tr: Vector2 = HeadsetRig.screen_to_eye(lay, uv_10, 0)["t"]
	var tb: Vector2 = HeadsetRig.screen_to_eye(lay, uv_10, 2)["t"]
	check(tr.x < tg.x and tg.x < tb.x and tb.x / tg.x > (e0["cromatica"] as Vector3).z,
		"Shader: el azul se ve más afuera que el verde y el rojo más adentro (aberración lateral)")
	check(int(HeadsetRig.screen_to_eye(lay, Vector2(0.7, 0.5))["ojo"]) == 1 and int(HeadsetRig.screen_to_eye(lay, Vector2(0.3, 0.5))["ojo"]) == 0,
		"Shader: la mitad izquierda es del ojo izquierdo y la derecha del derecho")
	var worst := 0.0
	for uv in [Vector2(0.1, 0.2), Vector2(0.4, 0.85), Vector2(0.62, 0.1), Vector2(0.93, 0.66)]:
		for ch in range(3):
			var r := HeadsetRig.screen_to_eye(lay, uv, ch)
			var back := HeadsetRig.eye_to_screen(lay, int(r["ojo"]), r["t"], ch)
			worst = maxf(worst, back.distance_to(uv))
	check(worst < 1e-5, "Shader: píxel → dirección → píxel vuelve al mismo sitio (error %s)" % str(snappedf(worst, 1e-9)))
	var tl: Vector2 = HeadsetRig.screen_to_eye(lay, uv_10, 1, false)["t"]
	check(absf(tl.x - lin) < 1e-6, "Shader: sin predistorsión es la lente ideal (tan = s·x)")
	# Predistorsión de barril: una recta vertical del ojo se dibuja curvada hacia el eje.
	var mid := HeadsetRig.eye_to_screen(lay, 0, Vector2(0.8, 0.0))
	var top := HeadsetRig.eye_to_screen(lay, 0, Vector2(0.8, 1.0))
	var bot := HeadsetRig.eye_to_screen(lay, 0, Vector2(0.8, -1.0))
	check(top.x < mid.x - 0.01 and absf(top.x - bot.x) < 1e-5,
		"Shader: una recta vertical del ojo sale en barril en la pantalla (extremos %.1f px hacia el eje)" % ((mid.x - top.x) * 1600.0))
	var t0 := Vector2(0.37, -0.52)
	check(Optics.undistort(Optics.distort(t0, 0.215, 0.215), 0.215, 0.215).distance_to(t0) < 1e-6, "Óptica: la inversa de la distorsión es exacta")

func _layers_of(n: Node) -> Array:
	var out := []
	for v in n.find_children("*", "VisualInstance3D", true, false):
		if not out.has((v as VisualInstance3D).layers):
			out.append((v as VisualInstance3D).layers)
	return out

func _test_rig_cameras() -> void:
	main._open_example(VR_EXAMPLE)
	var other: PartInstance = main._spawn("placa_100x100", "aluminio", Vector3(0.5, 0.0025, 0.0))
	var rig := _rig()
	rig.forced = true
	await get_tree().process_frame
	await get_tree().process_frame
	check(rig.is_active() and (rig.eyes[0]["vp"] as SubViewport).render_target_update_mode == SubViewport.UPDATE_ALWAYS,
		"Render: activo con el visor en escena (render de los ojos y de la pantalla)")
	var cam: Camera3D = rig.eyes[0]["cam"]
	var fwd := -cam.global_basis.z
	check(cam.global_position.distance_to(rig.eye_world(0)) < 1e-5 and fwd.dot(Vector3(1, 0, 0)) > 0.9999 and cam.global_basis.y.dot(Vector3.UP) > 0.9999,
		"Render: la cámara del ojo izquierdo en su sitio, mirando hacia delante del visor (+X)")
	var t: Vector4 = rig.layout["eyes"][0]["tans"]
	check(cam.projection == Camera3D.PROJECTION_FRUSTUM and absf(cam.size - HeadsetRig.NEAR * (t.w - t.z)) < 1e-7 and absf(cam.frustum_offset.x - HeadsetRig.NEAR * (t.x + t.y) * 0.5) < 1e-7,
		"Render: frustum asimétrico con las tangentes del ojo")
	check(cam.cull_mask & HeadsetRig.LAYER_VISOR == 0 and cam.cull_mask & HeadsetRig.LAYER_EDITOR == 0 and cam.cull_mask & 1 == 1,
		"Render: los ojos no ven el visor ni las ayudas del editor")
	var vis_ok := true
	for c in main.parts_root.get_children():
		if c is PartInstance and c != other:
			vis_ok = vis_ok and _layers_of(c) == [HeadsetRig.LAYER_VISOR]
	var wires_ok: bool = main._wire_nodes.size() == 6
	for uid in main._wire_nodes:
		wires_ok = wires_ok and _layers_of(main._wire_nodes[uid]) == [HeadsetRig.LAYER_VISOR]
	check(vis_ok and wires_ok and _layers_of(other) == [1],
		"Render: carcasa, pantalla, lentes, soporte, ESP32, IMU y sus cables en la capa del visor; la placa de delante, visible")
	check(_layers_of(main.connections_root).all(func(m): return m == HeadsetRig.LAYER_EDITOR), "Render: marcadores de uniones en la capa del editor")
	check(rig.glass_texture() == rig.screen_vp.get_texture(), "Render: la pantalla del visor muestra la imagen lado a lado")
	# El visor girado 30° sobre Y: las cámaras lo siguen.
	var R := Transform3D(Basis(Vector3.UP, deg_to_rad(30.0)), Vector3.ZERO)
	for c in main.parts_root.get_children():
		if c is PartInstance and c != other:
			(c as PartInstance).global_transform = R * (c as PartInstance).global_transform
	rig.refresh()
	rig.update_cameras()
	var fwd2 := -cam.global_basis.z
	var want := Vector3(cos(deg_to_rad(30.0)), 0, -sin(deg_to_rad(30.0)))
	check(fwd2.dot(want) > 0.9999 and absf(float(rig.layout["ipd_m"]) - 0.063) < 1e-4 and cam.global_position.distance_to(rig.eye_world(0)) < 1e-5,
		"Render: con el visor girado 30° las cámaras giran con él (IPD igual)")
	rig.forced = false
	await get_tree().process_frame
	await get_tree().process_frame
	check(not rig.is_active() and rig.glass_texture() == PartVisuals.sbs_pattern() and (rig.eyes[1]["vp"] as SubViewport).render_target_update_mode == SubViewport.UPDATE_DISABLED,
		"Render: sin panel ni simulación se apaga y la pantalla vuelve a la carta de ajuste")
	# Una sola lente: imagen única en toda la pantalla.
	var lens2: PartInstance = _part_by_def("lente_cardboard_37")[1]
	main.connections = main.connections.filter(func(cc): return cc.a_uid != lens2.uid and cc.b_uid != lens2.uid)
	main.parts_root.remove_child(lens2)
	lens2.queue_free()
	var mono := _vr_layout()
	check(mono.get("ok", false) and not mono["estereo"] and (mono["eyes"] as Array).size() == 1, "Render: con una lente, un ojo e imagen única")

func _glass_tex(root: Node) -> Texture2D:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if mi.has_meta("pantalla_luz"):
			return ((mi as MeshInstance3D).material_override as StandardMaterial3D).emission_texture
	return null

func _test_rig_sim() -> void:
	main._open_example(VR_EXAMPLE)
	var rig := _rig()
	rig.forced = false
	main._toggle_simulation()
	await wait_phys(30)
	await get_tree().process_frame
	var scr: PartInstance = _part_by_def("pantalla_55")[0]
	var roots: Array = main.circuit_rt._visual_roots(scr)
	check(rig.is_active() and rig.screen_lit() and roots.size() == 2 and _glass_tex(roots[1]) == rig.screen_vp.get_texture(),
		"Render: al simular con la pantalla a 5 V se enciende el render y la pantalla en vivo lo muestra")
	var cam: Camera3D = rig.eyes[1]["cam"]
	check(cam.global_position.distance_to(rig.eye_world(1)) < 1e-5 and rig.eye_world(1).distance_to(scr.global_transform * (rig.layout["eyes"][1]["pos_local"] as Vector3)) < 0.002,
		"Render: durante la simulación las cámaras siguen al cuerpo del visor")
	var esp: PartInstance = _part_by_def("esp32_devkit")[0]
	check(_layers_of(main.circuit_rt._visual_roots(esp)[1]) == [HeadsetRig.LAYER_VISOR],
		"Render: las piezas del visor siguen ocultas a los ojos durante la simulación")
	main._toggle_simulation()
	await get_tree().process_frame
	await get_tree().process_frame
	check(not rig.is_active() and rig.glass_texture() == PartVisuals.sbs_pattern(), "Render: al parar la simulación se apaga")
	# Sin los 5 V (sin el cable v1) y sin panel, no se renderiza.
	main._open_example(VR_EXAMPLE)
	main.wires = main.wires.filter(func(w): return str(w["uid"]) != "v1")
	main._redraw_wires()
	main._toggle_simulation()
	await wait_phys(20)
	await get_tree().process_frame
	check(not rig.is_active() and not rig.screen_lit(), "Render: con la pantalla sin alimentación no gasta en renderizar")
	main.visor_panel.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	rig.refresh()
	check(rig.is_active() and str(rig.info_label.text).contains("apagada"), "Render: con el panel abierto se ve lo que mostraría (y avisa de que está apagada)")
	main.visor_panel.visible = false
	main._toggle_simulation()
	await get_tree().process_frame
	var api: Dictionary = main.api_headset()
	check(api.get("render", {}).has("ojos") and (api["render"]["ojos"] as Array).size() == 2 and JSON.stringify(api).find("inf") < 0,
		"API: analyze_headset trae las cámaras de los ojos (posición, campo, resolución)")

## Centroide (px) de una bola en el canal ch, en una ventana de la imagen: lo que ese
## canal supera al fondo (mediana del borde de la ventana). Cada canal se mira solo:
## con la corrección cromática los otros dos canales de la bola salen desplazados.
func _blob(img: Image, center: Vector2, half: int, ch: int) -> Vector3:
	var x0 := maxi(0, int(center.x) - half)
	var x1 := mini(img.get_width(), int(center.x) + half)
	var y0 := maxi(0, int(center.y) - half)
	var y1 := mini(img.get_height(), int(center.y) + half)
	var border := []
	for x in range(x0, x1):
		border.append(img.get_pixel(x, y0)[ch])
		border.append(img.get_pixel(x, y1 - 1)[ch])
	for y in range(y0, y1):
		border.append(img.get_pixel(x0, y)[ch])
		border.append(img.get_pixel(x1 - 1, y)[ch])
	border.sort()
	var bg: float = border[border.size() / 2]
	var sum := Vector2.ZERO
	var nn := 0.0
	for y in range(y0, y1):
		for x in range(x0, x1):
			var d: float = img.get_pixel(x, y)[ch] - bg
			if d > 0.15:
				sum += Vector2(x + 0.5, y + 0.5) * d
				nn += d
	return Vector3(sum.x / nn, sum.y / nn, nn) if nn > 0.0 else Vector3(-1, -1, 0)

func _ball(color: Color, r: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = 2.0 * r
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(mi)
	return mi

func _render_frames() -> Image:
	for i in range(4):
		await RenderingServer.frame_post_draw
	return _rig().screen_vp.get_texture().get_image()

## Prueba de punta a punta (solo con ventana): una bola en una dirección conocida de
## cada ojo debe salir en la pantalla donde dice la inversa del shader.
func _test_rig_render() -> void:
	if DisplayServer.get_name() == "headless":
		print("  (render real omitido sin ventana: Godot --path project -- mfvr)")
		return
	main._open_example(VR_EXAMPLE)
	var rig := _rig()
	rig.quality = 2
	rig.forced = true
	await get_tree().process_frame
	await get_tree().process_frame
	var lay: Dictionary = rig.layout
	var cs: Vector2 = Vector2(lay["comp_size"])
	var cb := (rig.eyes[0]["cam"] as Camera3D).global_basis
	var t := Vector2(0.5, 0.25)
	var ball := _ball(Color(0, 1, 0), 0.015)
	ball.global_position = rig.eye_world(0) + cb * Vector3(t.x, t.y, -1.0)
	var img: Image = await _render_frames()
	var dump := OS.get_environment("MF_VR_DUMP")
	if dump != "":
		img.save_png(dump + "/sbs.png")
		(rig.eyes[0]["vp"] as SubViewport).get_texture().get_image().save_png(dump + "/eye0.png")
		get_viewport().get_texture().get_image().save_png(dump + "/main.png")
	var want := HeadsetRig.eye_to_screen(lay, 0, t) * cs
	var got := _blob(img, want, 60, 1)
	check(got.z > 0.0 and Vector2(got.x, got.y).distance_to(want) < 2.0,
		"Render real: bola a tan (0.5, 0.25) del ojo izquierdo en el píxel previsto (%.1f, %.1f), medido (%.1f, %.1f)" % [want.x, want.y, got.x, got.y])
	# Ojo derecho: la misma bola desde su posición (paralaje de 63 mm).
	var rel: Vector3 = cb.inverse() * (ball.global_position - rig.eye_world(1))
	var tr := Vector2(rel.x, rel.y) / -rel.z
	var want_r := HeadsetRig.eye_to_screen(lay, 1, tr) * cs
	var got_r := _blob(img, want_r, 60, 1)
	check(got_r.z > 0.0 and Vector2(got_r.x, got_r.y).distance_to(want_r) < 2.0,
		"Render real: el ojo derecho la ve a tan (%.3f, %.3f) y sale en (%.1f, %.1f), medido (%.1f, %.1f)" % [tr.x, tr.y, want_r.x, want_r.y, got_r.x, got_r.y])
	rig.predistort = false
	rig.apply_settings()
	var img2: Image = await _render_frames()
	var want_lin := HeadsetRig.eye_to_screen(lay, 0, t, 1, false) * cs
	var got_lin := _blob(img2, want_lin, 60, 1)
	var cpx := HeadsetRig.eye_to_screen(lay, 0, Vector2.ZERO) * cs
	check(got_lin.z > 0.0 and Vector2(got_lin.x, got_lin.y).distance_to(want_lin) < 2.0 and Vector2(got.x, got.y).distance_to(cpx) < want_lin.distance_to(cpx) - 10.0,
		"Render real: sin predistorsión sale %.0f px más lejos del eje (la predistorsión la acerca, en barril)" % (want_lin.distance_to(cpx) - Vector2(got.x, got.y).distance_to(cpx)))
	rig.predistort = true
	rig.apply_settings()
	# Aberración cromática: una bola roja y luego azul en la misma dirección, lejos del
	# eje (sobre la pared gris): el rojo se dibuja más afuera y el azul más adentro.
	var tc := Vector2(-0.55, 0.7)
	ball.global_position = rig.eye_world(0) + cb * Vector3(tc.x, tc.y, -1.0)
	(ball.material_override as StandardMaterial3D).albedo_color = Color(1, 0, 0)
	var img_r: Image = await _render_frames()
	(ball.material_override as StandardMaterial3D).albedo_color = Color(0, 0, 1)
	var img_b: Image = await _render_frames()
	if dump != "":
		img_r.save_png(dump + "/sbs_r.png")
		img_b.save_png(dump + "/sbs_b.png")
	var w_r := HeadsetRig.eye_to_screen(lay, 0, tc, 0) * cs
	var w_b := HeadsetRig.eye_to_screen(lay, 0, tc, 2) * cs
	var g_r := _blob(img_r, w_r, 40, 0)
	var g_b := _blob(img_b, w_b, 40, 2)
	var sep_want := w_r.distance_to(w_b)
	var sep_got := Vector2(g_r.x, g_r.y).distance_to(Vector2(g_b.x, g_b.y))
	check(g_r.z > 0.0 and g_b.z > 0.0 and Vector2(g_r.x, g_r.y).distance_to(w_r) < 1.5 and Vector2(g_b.x, g_b.y).distance_to(w_b) < 1.5 and absf(sep_got - sep_want) < 0.8
		and Vector2(g_r.x, g_r.y).distance_to(cpx) > Vector2(g_b.x, g_b.y).distance_to(cpx),
		"Render real: corrección cromática, el rojo %.1f px más afuera que el azul (previsto %.1f px)" % [sep_got, sep_want])
	ball.queue_free()
	rig.forced = false
	rig.quality = 1

#endregion

#region FASE 3: SEGUIMIENTO CON LA IMU -------------------------------------------

const HEAD_EXAMPLE := "res://templates/13_visor_cabeza.mforge"

func _test_profiles() -> void:
	var c := Connection.new()
	c.tipo = Connection.Tipo.BISAGRA
	c.control_mode = Connection.ControlMode.POSICION
	c.profile = Connection.Profile.SENO
	c.profile_amp = 30.0; c.profile_freq = 0.5; c.profile_phase_deg = 90.0; c.profile_center = 5.0
	var v0 := rad_to_deg(c.profile_value(0.0))
	var v1 := rad_to_deg(c.profile_value(0.5))
	check(absf(v0 - 35.0) < 1e-4 and absf(v1 - 5.0) < 1e-4, "Perfil senoidal: centro + amplitud·sen(2πft + desfase) (%.2f°, %.2f°)" % [v0, v1])
	c.profile = Connection.Profile.CUADRADA
	c.profile_phase_deg = 0.0
	check(absf(rad_to_deg(c.profile_value(0.2)) - 35.0) < 1e-4 and absf(rad_to_deg(c.profile_value(1.2)) + 25.0) < 1e-4,
		"Perfil cuadrado: escalones de ±amplitud alrededor del centro")
	var d := Connection.from_dict(c.to_dict())
	check(d.profile == c.profile and d.profile_amp == 30.0 and d.profile_freq == 0.5 and d.profile_center == 5.0, "Perfil: se guarda y se recupera con el proyecto")
	check(not c.mcu_driven(), "Perfil: una bisagra con perfil no la mueve el microcontrolador")
	main._on_new()
	var a: PartInstance = main._spawn("servo", "abs", Vector3(0, 0.02, 0))
	var b: PartInstance = main._spawn("servo", "abs", Vector3(0, 0.06, 0))
	var h1 := Connection.new(); h1.a_uid = a.uid; h1.b_uid = b.uid; h1.control_mode = Connection.ControlMode.POSICION
	var h2 := Connection.new(); h2.a_uid = a.uid; h2.b_uid = b.uid; h2.control_mode = Connection.ControlMode.POSICION
	h2.profile = Connection.Profile.SENO
	main.connections = [h1, h2]
	check(main._controlled_connections() == [h1], "Perfil: el programa solo recibe las uniones con control y sin perfil (m1…)")
	main.connections = []

func _test_imu_basis() -> void:
	var worst := 0.0
	for rpy in [Vector3(0, 0, 0), Vector3(12, -7, 33), Vector3(-25, 18, -140), Vector3(40, -60, 170), Vector3(-5, 3, 95)]:
		var back := Sensors.imu_angles(Sensors.imu_basis(rpy))
		var dz := wrapf(back.z - rpy.z, -180.0, 180.0)
		worst = maxf(worst, maxf(absf(back.x - rpy.x), maxf(absf(back.y - rpy.y), absf(dz))))
	check(worst < 1e-3, "IMU: la base de la pieza a partir de los ángulos es la inversa de imu_angles (error %s°)" % str(snappedf(worst, 1e-7)))
	var b := Sensors.imu_basis(Vector3(0, 0, 30))
	var p := Sensors.imu_basis(Vector3(0, 20, 0))
	var r := Sensors.imu_basis(Vector3(15, 0, 0))
	check(b.x.z < -0.49 and p.x.y < -0.34 and r.z.y < -0.25 and Sensors.imu_basis(Vector3.ZERO).is_equal_approx(Basis.IDENTITY),
		"IMU: guiñada + gira el frente a la izquierda, cabeceo + lo baja y alabeo + baja el lado derecho")

func _test_head_part() -> void:
	main._on_new()
	var head: PartInstance = main._spawn("cabeza_prueba", "pla", Vector3(0, 0.2, 0))
	var mm := PartLibrary.mass_model(head.def)
	var v := 4.0 / 3.0 * PI * 0.095 * 0.115 * 0.075
	check(absf(float(mm["volumen"]) - v) < 1e-9 and absf(float(mm["area"]) - 0.1127) < 0.002,
		"Cabeza de prueba: elipsoide de %.2f L y %.3f m² de superficie" % [v * 1000.0, float(mm["area"])])
	head.estado["impresion"] = {"relleno": 0.1, "paredes_mm": 1.2}
	var m := head.mass_kg()
	var area := float(mm["area"])
	var want := 1240.0 * (area * 0.0012 + 0.1 * (v - area * 0.0012))
	var it := head.inertia_local()
	check(absf(m - want) < 1e-6 and absf(it.x - m * (0.115 * 0.115 + 0.075 * 0.075) / 5.0) < 1e-7 and it.z > it.x and it.x > it.y,
		"Cabeza de prueba: impresa al 10 %% pesa %.0f g, con la inercia de un elipsoide" % (m * 1000.0))
	var shapes := head.make_collision_shapes()
	var pts: PackedVector3Array = (shapes[0]["shape"] as ConvexPolygonShape3D).points
	var on := true
	for q in pts:
		on = on and absf(pow(q.x / 0.095, 2) + pow(q.y / 0.115, 2) + pow(q.z / 0.075, 2) - 1.0) < 1e-4
	check(shapes.size() == 1 and pts.size() > 100 and on, "Cabeza de prueba: colisión convexa sobre la superficie del elipsoide (%d puntos)" % pts.size())

func _test_latency_estimator() -> void:
	var tr := HeadTracking.new()
	var tau := 0.037
	var w := [TAU * 0.3, TAU * 0.2, TAU * 0.25]
	var amp := [20.0, 10.0, 30.0]
	for i in range(1200):
		var t := i / 120.0
		var real := Vector3(amp[0] * sin(w[0] * t), amp[1] * sin(w[1] * t + 1.0), amp[2] * sin(w[2] * t))
		var td := t - tau
		var est := Vector3(amp[0] * sin(w[0] * td), amp[1] * sin(w[1] * td + 1.0) + 0.4, amp[2] * sin(w[2] * td) + 0.5 * t)
		tr.add(t, real, est, 0.0)
	var s := tr.stats()
	check(absf(float(s["latencia_ms"]) - 37.0) < 0.5, "Seguimiento: la latencia de una señal retrasada 37 ms sale %.2f ms (con sesgo y deriva)" % float(s["latencia_ms"]))
	check(absf(float(s["deriva_guinada_deg_min"]) - 30.0) < 1.5, "Seguimiento: deriva de 0.5 °/s → %.1f °/min" % float(s["deriva_guinada_deg_min"]))
	var c := tr.csv().split("\n")
	check(c[0].begins_with("tiempo_s,alabeo_real,alabeo_est") and c.size() == 1202, "Seguimiento: CSV con cabecera y una fila por muestra")
	check(tr.est_at(0.5 + 1.0 / 240.0).distance_to((tr.est_at(0.5) + tr.est_at(0.5 + 1.0 / 120.0)) * 0.5) < 1e-4, "Seguimiento: orientación estimada interpolada entre muestras")

## Simula el ejemplo de la cabeza «secs» segundos (retardo del enlace link_ms).
func _run_head(secs: float, link_ms := 20.0, ideal := false, yaw_only := false) -> void:
	main._open_example(HEAD_EXAMPLE)
	_rig().link_ms = link_ms
	if yaw_only:
		for c in main.connections:
			if (c as Connection).profile != Connection.Profile.NINGUNO and (c as Connection).axis != 1:
				(c as Connection).profile_amp = 0.0
	if ideal:
		for c in main.parts_root.get_children():
			if c is PartInstance and (c as PartInstance).def_id == "imu":
				(c as PartInstance).estado["imu"] = {"ideal": true}
	main._toggle_simulation()
	await wait_phys(int(secs * 120.0))

func _test_head_motion() -> void:
	await _run_head(9.0)
	var rig := _rig()
	check(main.mcu_enabled and main.mcu_target_uid == "" and main.mcu_last_vars.has("yaw"),
		"Banco: el programa corre en la ESP32 (las uniones con perfil no son suyas) y calcula roll, pitch y yaw")
	var worst := 0.0
	for c in main.connections:
		if (c as Connection).profile != Connection.Profile.NINGUNO:
			var sp := rad_to_deg((c as Connection).profile_value(main.simulator.sim_time()))
			worst = maxf(worst, absf(rad_to_deg(main.simulator.control_measure(c.uid)) - sp))
	check(worst < 0.01, "Banco: los tres servos ideales siguen su perfil senoidal (error %.4f°)" % worst)
	var holder: PartInstance = _part_by_def("soporte_lentes")[0]
	var slip := 0.0
	for ln in _part_by_def("lente_cardboard_37"):
		var r0: Transform3D = holder.global_transform.affine_inverse() * (ln as PartInstance).global_transform
		var r1: Transform3D = main._part_live_xform(holder).affine_inverse() * main._part_live_xform(ln)
		slip = maxf(slip, r0.origin.distance_to(r1.origin))
	check(slip < 0.001 and absf(float(rig.layout["ipd_m"]) - 0.063) < 1e-4,
		"Banco: con el ajuste de IPD bloqueado las lentes no resbalan al girar la cabeza (%.2f mm) y la óptica no cambia" % (slip * 1000.0))
	var s := rig.tracking.stats()
	var rng: Array = s.get("recorrido_deg", [0, 0, 0])
	check(rig.tracking.size() > 1000 and absf(float(rng[2]) - 70.0) < 4.0 and float(rng[1]) > 20.0 and float(rng[0]) > 12.0,
		"Banco: la cabeza gira de verdad (recorrido real: alabeo %.0f°, cabeceo %.0f°, guiñada %.0f°)" % [rng[0], rng[1], rng[2]])
	var rms: Array = s["rms_deg"]
	print("    seguimiento: ", JSON.stringify(s))
	check(float(rms[0]) < 2.0 and float(rms[1]) < 2.0 and float(rms[2]) < 3.0,
		"Seguimiento: el filtro complementario sigue la cabeza (RMS alabeo %.2f°, cabeceo %.2f°, guiñada %.2f°)" % [rms[0], rms[1], rms[2]])
	var lat := float(s["latencia_ms"])
	check(lat >= 0.0 and lat < 40.0, "Seguimiento: latencia del filtro %.1f ms (muestreo de la IMU a 100 Hz y filtro)" % lat)
	# Con la estimación perfecta (los ángulos reales), las cámaras quedarían como las reales.
	var imu: PartInstance = main._find_part(rig._imu_uid)
	var scr: PartInstance = main._find_part(str(rig.layout["screen_uid"]))
	var real := Sensors.imu_angles(main._part_live_xform(imu).basis)
	real.z -= float(rig._ref["yaw0"])
	var cb_true := HeadsetRig.camera_basis(main._part_live_xform(scr).basis)
	var ang := rad_to_deg((cb_true.inverse() * rig._imu_camera_basis(real)).get_rotation_quaternion().get_angle())
	check(ang < 0.05, "Seguimiento: con los ángulos reales la vista IMU coincide con la real (%.3f°)" % ang)
	rig.update_cameras()
	var cam: Camera3D = rig.eyes[0]["cam"]
	var used := rig._imu_camera_basis(rig.tracking.est_at(main.simulator.sim_time() - 0.02))
	var c0: Vector3 = rig._ref["c0"]
	var mid := ((rig.eyes[0]["cam"] as Camera3D).global_position + (rig.eyes[1]["cam"] as Camera3D).global_position) * 0.5
	check(rig.imu_driving() and rad_to_deg((cam.global_basis.inverse() * used).get_rotation_quaternion().get_angle()) < 0.01 and mid.distance_to(c0) < 1e-4,
		"Seguimiento: en modo IMU las cámaras usan la estimación de hace 20 ms y giran sobre los ojos del arranque (3 GdL)")
	var verr := float(s["error_vista_rms_deg"])
	check(verr > 0.0 and verr < 4.0, "Seguimiento: error de la vista %.2f° RMS (máx %.2f°)" % [verr, float(s["error_vista_max_deg"])])
	_stats_link20 = verr
	main._toggle_simulation()
	await get_tree().process_frame
	var api: Dictionary = main.api_headset()
	check(api.get("seguimiento", {}).get("modo", "") == "imu" and api["seguimiento"].has("rms_deg") and JSON.stringify(api).find("inf") < 0 and JSON.stringify(api).find("nan") < 0,
		"API: analyze_headset trae el seguimiento (modo IMU, errores, deriva y latencia)")

var _stats_link20 := 0.0

## Uniones fijas: las piezas forman un solo cuerpo rígido (Jolt resolvía las uniones
## fijas entre cuerpos dinámicos como resortes: una viga de 0.6 kg sobre un servo de
## 32 g cedía 8°).
func _test_fixed_fusion() -> void:
	main._on_new()
	var base: PartInstance = main._spawn("placa_base_200x200", "acero", Vector3(0, 0.004, 0))
	base.anchored = true
	var s1: PartInstance = main._spawn("servo", "abs", Vector3(0, 0.027, 0))
	var beam: PartInstance = main._spawn("perfil_2020_400", "acero", Vector3(0.2, 0.056, 0), Vector3(0, 0, PI / 2.0))
	main._tpl_fix(base, s1, s1.position)
	main._tpl_fix(s1, beam, s1.position + Vector3(0, 0.029, 0))
	var b0 := beam.global_basis
	main._toggle_simulation()
	await wait_phys(60)
	var droop := rad_to_deg((b0.inverse() * main._part_live_xform(beam).basis).get_rotation_quaternion().get_angle())
	check(main.simulator.get_body(beam.uid) == main.simulator.get_body(base.uid) and droop < 0.01,
		"Uniones fijas: base, servo y viga en voladizo forman un solo cuerpo rígido (cede %.4f°)" % droop)
	main._toggle_simulation()
	# Conjunto libre: masa, centro de masa e inercia de las piezas (Steiner).
	main._on_new()
	var a: PartInstance = main._spawn("placa_100x100", "acero", Vector3(0, 0.3, 0))
	var b: PartInstance = main._spawn("placa_100x100", "aluminio", Vector3(0.1, 0.3, 0))
	main._tpl_fix(a, b, Vector3(0.05, 0.3, 0))
	main._toggle_simulation()
	await get_tree().physics_frame
	var body: RigidBody3D = main.simulator.get_body(a.uid)
	var ma := a.mass_kg()
	var mb := b.mass_kg()
	var com := Simulator.body_com(body)
	var want := (Vector3(0, 0.3, 0) * ma + Vector3(0.1, 0.3, 0) * mb) / (ma + mb)
	var izz := (ma + mb) * (0.1 * 0.1 + 0.005 * 0.005) / 12.0 + ma * pow(want.x, 2) + mb * pow(0.1 - want.x, 2)
	check(main.simulator.get_body(b.uid) == body and absf(body.mass - ma - mb) < 1e-6 and com.distance_to(want) < 0.002 and absf(body.inertia.z - izz) < 1e-6,
		"Uniones fijas: el conjunto tiene la masa (%.0f g), el centro de masa y la inercia de sus piezas" % ((ma + mb) * 1000.0))
	check(main._part_live_xform(b).origin.distance_to(Vector3(0.1, 0.3, 0)) < 0.002 and main.simulator.telemetry(b.uid)["pos"].distance_to(main._part_live_xform(b).origin) < 1e-5,
		"Uniones fijas: cada pieza del conjunto conserva su posición (transformación y telemetría)")
	main._toggle_simulation()

func _test_head_tracking_variants() -> void:
	await _run_head(6.0, 80.0)
	var s80 := _rig().tracking.stats()
	main._toggle_simulation()
	check(float(s80["error_vista_rms_deg"]) > _stats_link20 + 0.5,
		"Seguimiento: con 80 ms de retardo el error de la vista sube de %.2f° a %.2f° RMS" % [_stats_link20, float(s80["error_vista_rms_deg"])])
	# Solo guiñada con la IMU real: sin acoplamiento con alabeo y cabeceo, la deriva de
	# la guiñada es el sesgo del giroscopio en z (el de esta IMU, que sale de su uid).
	await _run_head(8.0, 20.0, false, true)
	var sy := _rig().tracking.stats()
	var gb: Vector3 = main.mcu_sensors._imu_state[_rig()._imu_uid]["gb"]
	main._toggle_simulation()
	var drift := float(sy["deriva_guinada_deg_min"])
	check(absf(drift - gb.z * 60.0) < 0.1 * absf(gb.z * 60.0) + 0.5,
		"Seguimiento: solo guiñada, la deriva (%+.2f °/min) es el sesgo del giroscopio en z (%+.2f °/min)" % [drift, gb.z * 60.0])
	# IMU ideal y solo guiñada: sin sesgo ni acoplamiento con alabeo y cabeceo, no hay
	# deriva (con el movimiento combinado, los errores de alabeo y cabeceo del filtro
	# se cuelan en la guiñada: es una deriva real del firmware, no del sensor).
	await _run_head(8.0, 20.0, true, true)
	var si := _rig().tracking.stats()
	main._toggle_simulation()
	var rms: Array = si["rms_deg"]
	print("    ideal, solo guiñada: ", JSON.stringify(si))
	check(absf(float(si["deriva_guinada_deg_min"])) < 1.0 and float(rms[2]) < 0.5 and float(rms[0]) < 0.5 and float(rms[1]) < 0.5,
		"Seguimiento: IMU ideal y solo guiñada: sin deriva (%+.2f °/min), RMS alabeo %.2f°, cabeceo %.2f°, guiñada %.2f°" % [float(si["deriva_guinada_deg_min"]), rms[0], rms[1], rms[2]])

func _test_tracking_ui() -> void:
	await _run_head(3.0)
	var rig := _rig()
	main.visor_panel.visible = true
	rig.graph_axis = 2
	rig.update_tracking_ui()
	check(rig.track_graph._series.size() == 2 and (rig.track_graph._series[0]["valores"] as Array).size() > 50 and rig.track_label.text.contains("Deriva de la guiñada"),
		"Panel: gráfica real frente a estimada (guiñada) y resumen del seguimiento")
	main._toggle_simulation()
	main.visor_panel.visible = false
	var extra: Dictionary = main._project_extra()
	check(extra.get("visor", {}).get("seguimiento", -1) == HeadsetRig.Track.IMU, "Proyecto: guarda el modo de seguimiento del visor")
	main._on_new()
	check(rig.track_mode == HeadsetRig.Track.REAL and rig.tracking.size() == 0, "Proyecto: uno nuevo vuelve al seguimiento real y sin datos")
	main._open_example(HEAD_EXAMPLE)
	check(rig.track_mode == HeadsetRig.Track.IMU and main.visor_track_opt.selected == HeadsetRig.Track.IMU, "Proyecto: el ejemplo de la cabeza abre en modo IMU (también en el panel)")

#endregion

#region FASE 4: VERIFICACIÓN ÓPTICA Y ERGONOMÍA ----------------------------------

func _run_phase4() -> void:
	print("[TEST] Visor VR — Fase 4 (verificación óptica, ergonomía y holguras)")
	_test_check_design()
	_test_check_predistort_off()
	_test_check_render_ipd()
	_test_check_user_ipd()
	_test_check_cardboard()
	_test_check_interference()
	_test_eyeview_math()
	_test_check_ui_api()
	await _test_eyeview_render()
	_reset_check()

func _reset_check() -> void:
	var rig := _rig()
	rig.profile_mode = HeadsetRig.Profile.DISENO
	rig.profile_manual = {"ipd_mm": 63.0, "dist_mm": 41.7, "k1": 0.215, "k2": 0.215}
	rig.user_ipd_mm = 63.0
	rig.predistort = true
	rig.chroma = true
	rig.set_view_mode(0)

## Informe del visor del ejemplo 12 con los ajustes dados.
func _check(profile := HeadsetRig.Profile.DISENO, user_ipd := 63.0, manual := {}) -> Dictionary:
	var rig := _rig()
	rig.profile_mode = profile
	if not manual.is_empty():
		rig.profile_manual = manual
	rig.user_ipd_mm = user_ipd
	rig.relayout()
	return HeadsetCheck.report(main, rig)

func _test_check_design() -> void:
	main._open_example(VR_EXAMPLE)
	_reset_check()
	var r := _check()
	var o: Dictionary = r["optica"]
	var worst := 0.0
	for e in o["ojos"]:
		worst = maxf(worst, maxf(float(e["distorsion_max_arcmin"]), maxf(float(e["cromatica_max_arcmin"]),
			maxf(absf(float(e["desalineacion_h_arcmin"])), absf(float(e["desalineacion_v_arcmin"]))))))
	check(r.get("ok", false) and worst < 0.5 and absf(float(o["convergencia_prisma"])) < 0.01 and absf(float(o["vertical_prisma"])) < 0.01,
		"Verificación: con el perfil del diseño la imagen llega recta, alineada y sin flecos de color (peor %.2f′)" % worst)
	check(int(o["ojos"][0]["muestras"]) > 200, "Verificación: se mide sobre %d direcciones del campo de cada ojo" % int(o["ojos"][0]["muestras"]))
	# Ergonomía, calculada aparte.
	var mass := 0.0
	var acc := Vector3.ZERO
	for c in main.parts_root.get_children():
		var p := c as PartInstance
		mass += p.mass_kg()
		acc += (p.global_transform * p.com_local()) * p.mass_kg()
	var com := acc / mass
	var eye_mid := (HeadsetCheck.physical_eye(main, _rig().layout, 0) + HeadsetCheck.physical_eye(main, _rig().layout, 1)) * 0.5
	var dfwd := (com - (eye_mid + Vector3(HeadsetCheck.FACE_OFFSET, 0, 0))).dot(Vector3(1, 0, 0))
	var g: Dictionary = r["ergonomia"]
	check(absf(float(g["masa_g"]) - mass * 1000.0) < 0.01 and absf(float(g["delante_de_la_cara_mm"]) - dfwd * 1000.0) < 0.05
		and absf(float(g["par_Nm"]) - mass * 9.80665 * dfwd) < 1e-4 and str(g["valoracion_masa"]) == "ligero",
		"Ergonomía: %.0f g, centro de masa %.1f mm por delante de la cara, par %.3f N·m" % [g["masa_g"], g["delante_de_la_cara_mm"], g["par_Nm"]])
	var h: Dictionary = r["holguras"]
	var t := float(PartLibrary.lens_geometry(_part_by_def("lente_cardboard_37")[0].def)["t"])
	var l0: Dictionary = h["lentes"][0]
	check(absf(float(l0["lente_pantalla_mm"]) - (40.0 - t * 500.0)) < 0.05 and absf(float(l0["pestanas_mm"]) - (15.0 - t * 500.0)) < 0.05,
		"Holguras: lente a %.1f mm de la pantalla y %.1f mm de las pestañas (canto de %.1f mm)" % [l0["lente_pantalla_mm"], l0["pestanas_mm"], t * 1000.0])
	var states := {}
	for p in h["pares"]:
		states[str(p["a"]) + "|" + str(p["b"])] = str(p["estado"])
		states[str(p["b"]) + "|" + str(p["a"])] = str(p["estado"])
	var scr_name := str(_part_by_def("pantalla_55")[0].def["nombre"])
	var shell_name := str(_part_by_def("carcasa_visor")[0].def["nombre"])
	var holder_name := str(_part_by_def("soporte_lentes")[0].def["nombre"])
	check(states.get(scr_name + "|" + shell_name, "") == "en contacto" and states.get("lente izquierda|" + holder_name, "") == "en su guía"
		and not states.values().has("interferencia") and (r["avisos"] as Array).is_empty(),
		"Holguras: la pantalla apoya en la carcasa, las lentes en su guía, sin interferencias ni avisos")

func _test_check_predistort_off() -> void:
	_rig().predistort = false
	var r := _check()
	_rig().predistort = true
	var e: Dictionary = r["optica"]["ojos"][0]
	check(float(e["distorsion_max_arcmin"]) > 60.0 and float(e["distorsion_borde_pct"]) > 5.0 and str(r["avisos"]).contains("cojín"),
		"Verificación: sin predistorsión el ojo ve cojín (%.0f′, %+.1f %% en el borde)" % [e["distorsion_max_arcmin"], e["distorsion_borde_pct"]])

func _test_check_render_ipd() -> void:
	var s := 0.045 / (0.040 * 0.045 + 0.015 * 0.005)
	var r := _check(HeadsetRig.Profile.MANUAL, 63.0, {"ipd_mm": 60.0, "dist_mm": 1000.0 / s, "k1": 0.215, "k2": 0.215})
	var o: Dictionary = r["optica"]
	var th := atan(Optics.distort(Vector2(s * 0.0015, 0.0), 0.215, 0.215).x)
	var want := 100.0 * tan(2.0 * th)
	check(absf(float(o["convergencia_prisma"]) - want) < 0.01 * want and str(r["avisos"]).contains("converger"),
		"Verificación: render con IPD 60 y lentes a 63 mm → las imágenes piden converger %.2f Δ (previsto %.2f Δ)" % [o["convergencia_prisma"], want])
	check(float(o["ojos"][0]["distorsion_max_arcmin"]) > 5.0,
		"Verificación: además, la imagen descentrada 1.5 mm de la lente se deforma de forma asimétrica (%.0f′ en el borde)" % float(o["ojos"][0]["distorsion_max_arcmin"]))

func _test_check_user_ipd() -> void:
	var r := _check(HeadsetRig.Profile.DISENO, 58.0)
	var o: Dictionary = r["optica"]
	var L := 0.375
	var th := atan(Optics.distort(Vector2(-0.0025 / L, 0.0), 0.215, 0.215).x)
	var want := 100.0 * tan(2.0 * th)
	check(absf(float(o["convergencia_prisma"]) - want) < 0.01 * absf(want) and str(r["avisos"]).contains("divergir"),
		"Verificación: usuario con IPD 58 y lentes a 63 mm (imagen a 0.375 m) → divergencia de %.2f Δ (previsto %.2f Δ)" % [-float(o["convergencia_prisma"]), -want])

func _test_check_cardboard() -> void:
	var r := _check(HeadsetRig.Profile.CARDBOARD_V1)
	var e: Dictionary = r["optica"]["ojos"][0]
	check(float(e["distorsion_max_arcmin"]) > 5.0 and not (r["avisos"] as Array).is_empty(),
		"Verificación: el perfil de Cardboard v1 no casa con estas lentes (distorsión residual %.0f′, %d avisos)" % [e["distorsion_max_arcmin"], (r["avisos"] as Array).size()])
	_reset_check()

func _test_check_interference() -> void:
	var scr: PartInstance = _part_by_def("pantalla_55")[0]
	var x0 := scr.position
	scr.position += Vector3(0.002, 0, 0)
	var r := _check()
	scr.position = x0
	var found := -1.0
	for p in r["holguras"]["pares"]:
		if str(p["estado"]) == "interferencia" and (str(p["a"]).contains("Pantalla") or str(p["b"]).contains("Pantalla")):
			found = -float(p["holgura_mm"])
	check(absf(found - 2.0) < 0.3 and str(r["avisos"]).contains("Interferencia"), "Holguras: la pantalla metida 2 mm en la pared de la carcasa da una interferencia de %.2f mm" % found)

func _test_eyeview_math() -> void:
	_reset_check()
	var lay := _check()
	lay = _rig().layout
	var worst := 0.0
	for t in [Vector2(0.0, 0.0), Vector2(0.4, -0.3), Vector2(-0.7, 0.5), Vector2(0.9, 0.2)]:
		for ch in range(3):
			var uv := HeadsetRig.eye_view_to_screen(lay, 0, t, ch, 0.063)
			var back: Vector2 = HeadsetRig.screen_to_eye(lay, uv, ch)["t"]
			worst = maxf(worst, back.distance_to(t))
	check(worst < 1e-5, "Vista a través de la lente: lo que el ojo ve en t es lo que el render puso en t (error %s)" % str(snappedf(worst, 1e-8)))
	var uv58 := HeadsetRig.eye_view_to_screen(lay, 0, Vector2.ZERO, 1, 0.058)
	var t58: Vector2 = HeadsetRig.screen_to_eye(lay, uv58, 1)["t"]
	check(t58.x > 0.005, "Vista a través de la lente: con la IPD del usuario menor, el ojo izquierdo mira por la parte de la nariz de la lente")

func _test_check_ui_api() -> void:
	_reset_check()
	main._toggle_check_panel()
	check(main.check_panel.visible and main.check_text.get_parsed_text().contains("Ergonomía") and main.check_text.get_parsed_text().contains("Sin avisos"),
		"Panel: «Verificación del visor» muestra óptica, ergonomía y holguras")
	main.check_profile_opt.select(HeadsetRig.Profile.MANUAL)
	main.check_profile_opt.item_selected.emit(HeadsetRig.Profile.MANUAL)
	check(main.check_manual.visible and _rig().profile_mode == HeadsetRig.Profile.MANUAL, "Panel: el perfil manual muestra IPD, distancia, k1 y k2")
	var extra: Dictionary = main._project_extra()
	check(int(extra["visor"]["perfil"]) == HeadsetRig.Profile.MANUAL and extra["visor"].has("ipd_usuario_mm"), "Proyecto: guarda el perfil del render y la IPD del usuario")
	main.check_panel.visible = false
	_reset_check()
	var api: Dictionary = main.api_headset_check()
	var js := JSON.stringify(api)
	check(api.get("ok", false) and api.has("optica") and api.has("ergonomia") and js.find("inf") < 0 and js.find("nan") < 0,
		"API: check_headset devuelve la verificación en JSON válido")

## Render real (con ventana): la bola en la dirección t de la cámara del ojo izquierdo
## se ve, a través de la lente real, en la misma dirección (con predistorsión) o
## desplazada hacia fuera en cojín (sin ella).
func _test_eyeview_render() -> void:
	if DisplayServer.get_name() == "headless":
		print("  (vista a través de la lente real omitida sin ventana)")
		return
	main._open_example(VR_EXAMPLE)
	_reset_check()
	var rig := _rig()
	rig.quality = 2
	rig.forced = true
	rig.set_view_mode(1)
	await get_tree().process_frame
	await get_tree().process_frame
	var lay: Dictionary = rig.layout
	var ph: Dictionary = lay["eyes"][0]["fisico"]
	var ft: Vector4 = ph["tans"]
	var sz := Vector2(ph["size"])
	var cb := (rig.eyes[0]["cam"] as Camera3D).global_basis
	var t := Vector2(0.5, 0.25)
	var ball := _ball(Color(0, 1, 0), 0.015)
	ball.global_position = rig.eye_world(0) + cb * Vector3(t.x, t.y, -1.0)
	var to_px := func(tt: Vector2) -> Vector2: return Vector2((tt.x - ft.x) / (ft.y - ft.x), (ft.w - tt.y) / (ft.w - ft.z)) * sz
	for i in range(5):
		await RenderingServer.frame_post_draw
	var img := rig.eyeview_vp.get_texture().get_image()
	if OS.get_environment("MF_VR_DUMP") != "":
		img.save_png(OS.get_environment("MF_VR_DUMP") + "/eyeview.png")
		rig.screen_vp.get_texture().get_image().save_png(OS.get_environment("MF_VR_DUMP") + "/eyeview_sbs.png")
		print("    eyeview ", rig.eyeview_vp.size, " modo ", rig.eyeview_vp.render_target_update_mode, " vista ", rig.view_mode, " activo ", rig.is_active())
	var want: Vector2 = to_px.call(t)
	var got := _blob(img, want, 50, 1)
	check(got.z > 0.0 and Vector2(got.x, got.y).distance_to(want) < 2.0,
		"Vista a través de la lente (render real): la bola se ve en su dirección, píxel (%.1f, %.1f), medido (%.1f, %.1f)" % [want.x, want.y, got.x, got.y])
	rig.predistort = false
	rig.apply_settings()
	for i in range(5):
		await RenderingServer.frame_post_draw
	var img2 := rig.eyeview_vp.get_texture().get_image()
	var want2: Vector2 = to_px.call(HeadsetCheck.seen(lay, 0, t, 1, 0.063, false)[0])
	var got2 := _blob(img2, want2, 50, 1)
	check(got2.z > 0.0 and Vector2(got2.x, got2.y).distance_to(want2) < 2.0 and want2.distance_to(to_px.call(Vector2.ZERO)) > want.distance_to(to_px.call(Vector2.ZERO)) + 5.0,
		"Vista a través de la lente (render real): sin predistorsión se ve más afuera (cojín), en (%.1f, %.1f) como prevé el modelo" % [got2.x, got2.y])
	rig.predistort = true
	ball.queue_free()
	rig.forced = false
	rig.quality = 1
	rig.set_view_mode(0)

#endregion

#region FASE 5: INTEGRACIÓN (OPENCLAW MONTA LAS GAFAS POR LA API) -----------------

func _run_phase5() -> void:
	print("[TEST] Visor VR — Fase 5 (las gafas montadas solo con la API de OpenClaw)")
	await _test_api_build_headset()
	_test_api_errors()
	_test_calibration_chart()
	await _test_live_wires()

func _uids_of(def_id: String) -> Array:
	var out := []
	for c in main.parts_root.get_children():
		if c is PartInstance and (c as PartInstance).def_id == def_id:
			out.append((c as PartInstance).uid)
	return out

func _test_api_build_headset() -> void:
	main._on_new()
	var api := SimulatorApi.new(main)
	var yc := 0.0475
	var fe := Basis(Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)).get_euler()
	var face := [rad_to_deg(fe.x), rad_to_deg(fe.y), rad_to_deg(fe.z)]
	var plan := [["carcasa_visor", "pla", [0.0, yc, 0.0], [0, 0, 0]], ["pantalla_55", "abs", [0.027, yc, 0.0], face],
		["soporte_lentes", "pla", [-0.016, yc, 0.0], face], ["lente_cardboard_37", "acrilico", [-0.016, yc, 0.0315], face],
		["lente_cardboard_37", "acrilico", [-0.016, yc, -0.0315], face], ["esp32_devkit", "abs", [0.005, 0.1, -0.045], [0, 0, 0]],
		["imu", "abs", [-0.005, 0.099, 0.03], [0, 0, 0]]]
	var pending := true
	for it in plan:
		var r := api.call_tool("add_part", {"def_id": it[0], "material": it[1], "pos": it[2], "rot_deg": it[3]})
		pending = pending and str(r.get("status", "")) == "pending_confirmation"
	check(pending and main.parts_root.get_child_count() == 0 and main.ai_pending.size() == 7,
		"API: siete piezas del visor propuestas en vista previa, sin tocar la escena hasta que el usuario aplica")
	main._ai_apply()
	var shell: String = _uids_of("carcasa_visor")[0]
	var scr: String = _uids_of("pantalla_55")[0]
	var holder: String = _uids_of("soporte_lentes")[0]
	var lenses := _uids_of("lente_cardboard_37")
	var esp: String = _uids_of("esp32_devkit")[0]
	var imu: String = _uids_of("imu")[0]
	api.call_tool("set_property", {"uid": shell, "anclada": true})
	api.call_tool("set_property", {"uid": lenses[0], "estado": {"ojo_mm": 15.0}})
	main._ai_apply()
	for u in [scr, holder, esp, imu]:
		api.call_tool("connect_parts", {"a": shell, "b": u, "union": "fija", "anclaje": main._arr(main._find_part(u).position)})
	for l in lenses:
		api.call_tool("connect_parts", {"a": holder, "b": l, "union": "deslizadera", "eje": "Z", "limites": [-9, 9], "bloqueada": true,
			"anclaje": main._arr(main._find_part(l).position)})
	main._ai_apply()
	var k := func(u: String, t: String) -> String: return "%s:%s" % [u, t]
	for w in [[k.call(esp, "5V"), k.call(scr, "5V")], [k.call(esp, "GND"), k.call(scr, "GND")], [k.call(esp, "3V3"), k.call(imu, "VCC")],
			[k.call(esp, "GND2"), k.call(imu, "GND")], [k.call(esp, "GPIO22"), k.call(imu, "SCL")], [k.call(esp, "GPIO21"), k.call(imu, "SDA")]]:
		api.call_tool("connect_wire", {"a": w[0], "b": w[1]})
	api.call_tool("write_controller_script", {"script": preload("res://templates/GeneradorEjemplos.gd").VR_PROGRAM})
	api.call_tool("configure_headset", {"seguimiento": "real", "perfil": "diseno", "ipd_usuario_mm": 63.0, "retardo_ms": 15})
	main._ai_apply()
	var slid: Array = main.connections.filter(func(c): return (c as Connection).tipo == Connection.Tipo.DESLIZADERA)
	check(main.parts_root.get_child_count() == 7 and main.connections.size() == 6 and main.wires.size() == 6 and slid.size() == 2
		and (slid[0] as Connection).slide_locked and absf((slid[0] as Connection).limit_upper - 0.009) < 1e-9 and main._find_part(shell).anchored
		and absf(_rig().link_ms - 15.0) < 1e-6 and main.mcu_enabled,
		"API: uniones (fijas y deslizaderas bloqueadas con límites), 6 cables, programa y ajustes del visor aplicados")
	var ah: Dictionary = main.api_headset()
	var ch: Dictionary = main.api_headset_check()
	check(ah.get("ok", false) and absf(float(ah["ipd_mm"]) - 63.0) < 0.05 and ch.get("ok", false) and (ch["avisos"] as Array).is_empty(),
		"API: analyze_headset (IPD %.1f mm) y check_headset (sin avisos) sobre las gafas montadas por la API" % float(ah.get("ipd_mm", 0.0)))
	api.call_tool("run_simulation", {})
	await wait_phys(240)
	var tel: Dictionary = api.call_tool("get_telemetry", {})
	var vars: Dictionary = tel.get("microcontrolador", {}).get("variables", {})
	var bus: Dictionary = tel.get("bus_i2c", {})
	check(int(vars.get("quien", 0)) == 0x68 and bool(bus.get(imu, {}).get("ok", false)) and main.circuit_rt.screen_powered(main._find_part(scr))
		and absf(float(vars.get("roll", 99.0))) < 2.5,
		"API: simulando, la ESP32 lee el MPU-6050 por I²C (WHO_AM_I 0x%X), la pantalla se enciende y el visor está nivelado" % int(vars.get("quien", 0)))
	await get_tree().process_frame
	var cap: Dictionary = api.call_tool("capture_headset_view", {"vista": "pantalla"})
	if DisplayServer.get_name() == "headless":
		check(cap.has("ruta") or cap.has("error"), "API: capture_headset_view responde (sin ventana no hay imagen que guardar)")
	else:
		await RenderingServer.frame_post_draw
		cap = api.call_tool("capture_headset_view", {"vista": "pantalla"})
		check(cap.has("ruta") and FileAccess.file_exists(str(cap["ruta"])) and int(cap["px"][0]) == 1600, "API: capture_headset_view guarda la pantalla del visor en PNG (%s)" % str(cap.get("px", [])))
	api.call_tool("stop_simulation", {})
	await get_tree().process_frame

func _test_api_errors() -> void:
	var api := SimulatorApi.new(main)
	var esp: String = _uids_of("esp32_devkit")[0]
	var e1 := api.call_tool("connect_wire", {"a": esp + ":NOEXISTE", "b": esp + ":5V"})
	var e2 := api.call_tool("configure_headset", {"brillo": 3})
	var e3 := api.call_tool("set_property", {"uid": esp, "estado": {"def": {}}})
	var e4 := api.call_tool("capture_headset_view", {"vista": "nariz"})
	check(e1.has("error") and e2.has("error") and e3.has("error") and e4.has("error") and main.ai_pending.is_empty(),
		"API: terminales, ajustes y campos de estado desconocidos se rechazan sin proponer nada")
	var lp: Dictionary = api.call_tool("list_parts", {"categoria": "electronica"})
	var esp_def: Array = (lp["piezas"] as Array).filter(func(p): return p["def_id"] == "esp32_devkit")
	check(not esp_def.is_empty() and str(esp_def[0].get("terminales", [])).contains("GPIO21 (signal)"),
		"API: list_parts da los terminales de cada pieza para cablear")
	main._ai_discard()

## Mayor distancia entre los extremos de cada cable dibujado y sus terminales en vivo.
func _wire_end_error() -> float:
	var worst := 0.0
	for w in main.wires:
		var uid := str(w["uid"])
		var holder: Node3D = main._wire_nodes.get(uid)
		var pts: PackedVector3Array = main._wire_pts.get(uid, PackedVector3Array())
		if holder == null or pts.is_empty():
			return INF
		var pa: PartInstance = main._find_part(str(w["a_key"]).split(":")[0])
		var pb: PartInstance = main._find_part(str(w["b_key"]).split(":")[0])
		var ea: Vector3 = main._wire_end_live(str(w["a_key"]), pa)
		var eb: Vector3 = main._wire_end_live(str(w["b_key"]), pb)
		worst = maxf(worst, (holder.global_transform * pts[0]).distance_to(ea))
		worst = maxf(worst, (holder.global_transform * pts[pts.size() - 1]).distance_to(eb))
	return worst

## Los cables siguen a sus piezas al simular (antes se quedaban donde estaban y, con
## las gafas moviéndose con la cabeza, quedaban sueltos sobre la carcasa).
func _test_live_wires() -> void:
	main._open_example(HEAD_EXAMPLE)
	main._toggle_simulation()
	await wait_phys(240)
	await get_tree().process_frame
	var head: PartInstance = _part_by_def("cabeza_prueba")[0]
	var moved := rad_to_deg((head.global_transform.basis.inverse() * main._part_live_xform(head).basis).get_rotation_quaternion().get_angle())
	main._update_live_wires()           # lo que hace cada fotograma antes de dibujar
	var err := _wire_end_error()
	check(moved > 5.0 and err < 0.0005, "Cables: con las gafas girando con la cabeza (%.0f°), los 6 cables siguen a sus terminales (error %.2f mm)" % [moved, err * 1000.0])
	main._toggle_simulation()
	await get_tree().process_frame
	check(_wire_end_error() < 0.0005 and (main._wire_nodes.values()[0] as Node3D).global_transform.is_equal_approx(Transform3D.IDENTITY),
		"Cables: al parar vuelven a su forma de edición")
	# Extremos en cuerpos distintos: un LED que cae, cableado a una batería en el suelo.
	main._on_new()
	var bat: PartInstance = main._spawn("bateria_lipo_3s", "abs", Vector3(0, 0.0205, 0))
	var led: PartInstance = main._spawn("led", "abs", Vector3(0.12, 0.15, 0))
	main.wires = [{"uid": "w1", "a_key": main._key(bat.uid, "V+"), "b_key": main._key(led.uid, "anodo"), "tipo": "power", "color": "auto"}]
	main._redraw_wires()
	main._toggle_simulation()
	await wait_phys(120)
	await get_tree().process_frame
	var fell: float = led.global_position.y - main._part_live_xform(led).origin.y
	var err2 := _wire_end_error()
	check(fell > 0.05 and err2 < float(main.WIRE_RETENSE_M) + 0.0005, "Cables: entre piezas que se mueven por separado se vuelven a tender (el LED cayó %.0f mm; error %.2f mm)" % [fell * 1000.0, err2 * 1000.0])
	main._toggle_simulation()
	# Muchos cables a la vez: como mucho WIRE_RETENSE_PER_FRAME tendidos por frame (cada
	# uno ~7 ms; antes se tendían todos y la simulación se arrastraba), por turnos, y
	# cuando las piezas se paran todos quedan al día.
	main._on_new()
	var bat2: PartInstance = main._spawn("bateria_lipo_3s", "abs", Vector3(0, 0.0205, 0))
	main.wires = []
	for i in 6:
		var led_i: PartInstance = main._spawn("led", "abs", Vector3(0.1 + 0.03 * i, 0.15, 0))
		main.wires.append({"uid": "m%d" % i, "a_key": main._key(bat2.uid, "V+"), "b_key": main._key(led_i.uid, "anodo"), "tipo": "power", "color": "auto"})
	main._redraw_wires()
	main._toggle_simulation()
	var most := 0
	var prev: Dictionary = main._wire_nodes.duplicate()
	for f in 40:
		await get_tree().process_frame
		var changed := 0
		for uid in prev:
			if main._wire_nodes.get(uid) != prev[uid]:
				changed += 1
		most = maxi(most, changed)
		prev = main._wire_nodes.duplicate()
	await wait_phys(120)
	await get_tree().process_frame
	var err3 := _wire_end_error()
	check(most > 0 and most <= main.WIRE_RETENSE_PER_FRAME and err3 < main.WIRE_RETENSE_M + 0.0005,
		"Cables: con 6 LED cayendo, como mucho %d tendidos por frame (máx. %d) y al pararse todos al día (error %.2f mm)" % [main.WIRE_RETENSE_PER_FRAME, most, err3 * 1000.0])
	main._toggle_simulation()
	main.wires = []
	main._redraw_wires()

func _test_calibration_chart() -> void:
	main._open_example(HEAD_EXAMPLE)
	var chart := _part_by_def("carta_calibracion")
	var tex := PartVisuals.calibration_texture().get_image()
	check(chart.size() == 1 and tex.get_width() == 840 and tex.get_pixel(30, 30).r > 0.8 and tex.get_pixel(30, 30).g < 0.3
		and tex.get_pixel(810, 30).g > 0.6 and tex.get_pixel(30, 564).b > 0.8,
		"Carta de calibración en el ejemplo de la cabeza: tablero con esquinas de color (rojo, verde, azul, amarillo)")
	var lay := HeadsetRig.compute_layout(main.parts_root, Callable(main, "_part_live_xform"))
	var ew: Vector3 = main._part_live_xform(_part_by_def("pantalla_55")[0]) * (lay["eyes"][0]["pos_local"] as Vector3)
	var cpos: Vector3 = (chart[0] as PartInstance).global_position
	check(absf(cpos.y - ew.y) < 0.01 and cpos.x - ew.x > 0.4, "Carta de calibración: a la altura de los ojos y %.2f m por delante" % (cpos.x - ew.x))

#endregion
