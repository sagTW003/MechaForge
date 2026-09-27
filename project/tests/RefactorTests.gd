extends Node
## RefactorTests — Pruebas del refactor gráfico / construcción / física.
## Ejecutar:  Godot --headless --path project -- mfrefactor
##
## Cubre: texturas procedurales, mallas (perfil en T, engranaje, tubo), encaje
## inteligente a orificios, gizmo 3D, rotación en 3 ejes, física de cables,
## soldadura, engranaje dinámico con huelgo y rendimiento, stepper a pasos,
## velocidad del servo y serialización de los nuevos campos.

var main: Node
var ok: int = 0
var fail: int = 0

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
	print("[TEST] Refactor gráfico / construcción / física...")
	_test_textures()
	_test_meshes()
	await _test_snap()
	await _test_gizmo()
	_test_rotation()
	_test_cables()
	await _test_solder()
	await _test_gear_backlash()
	await _test_gear_efficiency()
	await _test_stepper()
	await _test_servo()
	_test_serialization()
	main._on_new()
	print("[TEST] Refactor: %d OK, %d FALLOS" % [ok, fail])
	get_tree().quit(1 if fail > 0 else 0)

#region GRÁFICOS ------------------------------------------------------------------

func _test_textures() -> void:
	for pat in ["cepillado", "carbono", "pcb", "madera", "cobre"]:
		var imgs := ProceduralTextures.generate(pat, Color(0.6, 0.6, 0.6), 0.4, 3)
		var alb: Image = imgs["albedo"]
		var nrm: Image = imgs["normal"]
		var ok_size := alb.get_width() == ProceduralTextures.SIZE and nrm.get_width() == ProceduralTextures.SIZE
		# El mapa de normales no debe ser plano (hay relieve).
		var varied := false
		var c0 := nrm.get_pixel(0, 0)
		for i in range(0, 256, 17):
			if nrm.get_pixel(i, (i * 7) % 256).r != c0.r:
				varied = true
				break
		check(ok_size and varied and imgs["rough"] != null, "Textura procedural '%s' (albedo/rugosidad/normales con relieve)" % pat)
	var m := MaterialLibrary.get_visual("fibra_carbono")
	MaterialLibrary.wait_textures()
	check(m.uv1_triplanar and m.clearcoat_enabled, "Material fibra de carbono: triplanar + laca (clearcoat)")

func _test_meshes() -> void:
	var ts := MeshFactory.tslot_profile(Vector3(0.02, 0.2, 0.02))
	var ab := ts.get_aabb()
	check(ts.get_surface_count() == 1 and absf(ab.size.y - 0.2) < 1e-4 and absf(ab.size.x - 0.02) < 1e-4, "Perfil 2020 con ranuras en T (%.3f x %.3f m)" % [ab.size.x, ab.size.y])
	var verts: PackedVector3Array = ts.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(verts.size() > 200, "Perfil en T con geometría de ranuras (%d vértices)" % verts.size())
	var g := MeshFactory.gear(20, 0.001, 0.008, 0.005)
	check(absf(g.get_aabb().size.x - 0.022) < 5e-4, "Engranaje Z20 m1: Ø de cabeza 22 mm (%.1f mm)" % (g.get_aabb().size.x * 1000.0))
	var tb := MeshFactory.tube(0.0125, 0.0105, 0.3)
	check(absf(tb.get_aabb().size.x - 0.025) < 1e-4, "Tubo hueco Ø25")
	check(MeshFactory.plate_hole_positions(Vector3(0.2, 0.008, 0.2)).size() == 81, "Placa 200x200: 81 orificios M5 cada 20 mm")
	var def := PartLibrary.get_def("engranaje_m1_z40")
	check(not def.is_empty() and PartLibrary.gear_teeth(def) == 40, "Biblioteca: engranaje Z40 (transmisión)")

#endregion

#region CONSTRUCCIÓN --------------------------------------------------------------

func _test_snap() -> void:
	main._on_new()
	Config.surface_snap_enabled = true
	var plate: PartInstance = main._spawn("placa_base_200x200", "acero", Vector3(0, 0.004, 0))
	var prof: PartInstance = main._spawn("perfil_2020_100", "aluminio", Vector3(0.004, 0.058, -0.005))
	await get_tree().process_frame
	var snap := SnapPoints.find_snap(prof, prof.def, prof.global_transform, main.parts_root.get_children(), 0.012)
	check(not snap.is_empty() and snap["target"] == plate, "Encaje inteligente detecta la placa")
	if not snap.is_empty():
		var p: Vector3 = prof.global_position + snap["offset"]
		check(absf(p.x) < 1e-4 and absf(p.z) < 1e-4 and absf(p.y - 0.058) < 1e-4,
			"Perfil encaja centrado en un orificio (%s → %s): %.3f, %.3f, %.3f" % [snap["kind_from"], snap["kind_to"], p.x, p.y, p.z])
	# Eje de motor: el engranaje encaja sobre el eje (tipo "eje").
	var pts := SnapPoints.local_points(PartLibrary.get_def("motor_dc"))
	var has_shaft := false
	for q in pts:
		if q["k"] == "eje" and (q["n"] as Vector3).y > 0.5:
			has_shaft = true
	check(has_shaft, "El motor expone su eje como punto de encaje")

func _test_gizmo() -> void:
	main._on_new()
	var part: PartInstance = main._spawn("perfil_2020_100", "aluminio", Vector3(0, 0.05, 0))
	main._select(part)
	var cam: CameraOrbit = main.camera
	cam.target = Vector3(0, 0.05, 0); cam.distance = 0.6
	cam._yaw = deg_to_rad(-35); cam._pitch = deg_to_rad(-25); cam._update_transform()
	var gz: TransformGizmo = main.gizmo
	gz.set_mode(TransformGizmo.Mode.MOVER)
	await get_tree().process_frame
	await get_tree().process_frame
	var o := part.global_position
	var s := gz.scale.x
	var start := cam.unproject_position(o + Vector3.RIGHT * 0.7 * s)
	check(gz.begin_drag(start), "Gizmo: clic sobre la flecha X la selecciona")
	var endp := cam.unproject_position(o + Vector3.RIGHT * (0.7 * s + 0.05))
	gz.update_drag(endp)
	gz.end_drag()
	var moved := part.global_position - o
	check(absf(moved.x - 0.05) < 0.011 and absf(moved.y) < 1e-6 and absf(moved.z) < 1e-6,
		"Gizmo: arrastre mueve solo en X, ajustado a rejilla (Δ=%.3f, %.3f, %.3f)" % [moved.x, moved.y, moved.z])
	main.undo()
	check(part.global_position.distance_to(o) < 1e-6, "Gizmo: el movimiento se deshace con Ctrl+Z")

func _test_rotation() -> void:
	var part: PartInstance = main.selected_part
	if part == null:
		check(false, "Rotación en 3 ejes (sin pieza)")
		return
	Config.rotation_step_deg = 90.0
	main._rotate_selected(0)
	var y_axis := part.global_transform.basis.y
	check(absf(y_axis.dot(Vector3.BACK)) > 0.99, "Rotar 90° en X (Mayús+R): el perfil queda horizontal")
	check(part.position.y >= SnapPoints.world_aabb(part, part.def).size.y * 0.5 - 1e-4, "Tras girar, la pieza sigue apoyada (no atraviesa el suelo)")
	Config.rotation_step_deg = 15.0

func _test_cables() -> void:
	var a := Vector3(-0.1, 0.02, 0)
	var b := Vector3(0.1, 0.02, 0)
	var hi := CableSim.solve(a + Vector3.UP * 0.2, b + Vector3.UP * 0.2, [])
	var low_hi := INF
	var mid_i := hi.size() / 2
	for p in hi:
		low_hi = minf(low_hi, p.y)
	check(hi[0].distance_to(a + Vector3.UP * 0.2) < 1e-6, "Cable: extremos anclados a los terminales")
	check(low_hi < 0.2 - 0.02 and absf(hi[mid_i].y - low_hi) < 0.01, "Cable: catenaria por gravedad, punto más bajo al centro (caída %.0f mm)" % ((0.226 - low_hi) * 1000.0))
	var free := CableSim.solve(a, b, [])
	var low := INF
	for p in free:
		low = minf(low, p.y)
	check(low >= CableSim.RADIUS - 1e-6, "Cable: se apoya en el suelo sin atravesarlo (mín y=%.4f)" % low)
	# Obstáculo (caja) entre los terminales: el cable debe pasar por encima.
	var box := {"xf": Transform3D(Basis.IDENTITY, Vector3(0, 0.015, 0)), "half": Vector3(0.03, 0.015, 0.05)}
	var over := CableSim.solve(a, b, [box])
	var inside := 0
	for i in range(3, over.size() - 3):
		var lp: Vector3 = over[i] - Vector3(0, 0.015, 0)
		if absf(lp.x) < 0.03 - 1e-4 and absf(lp.y) < 0.015 - 1e-4 and absf(lp.z) < 0.05 - 1e-4:
			inside += 1
	check(inside == 0, "Cable: no atraviesa componentes sólidos (%d puntos dentro)" % inside)
	check(CableSim.polyline_length(over) > a.distance_to(b), "Cable: longitud mayor que la distancia (holgura)")

func _test_solder() -> void:
	main._on_new()
	var bat: PartInstance = main._spawn("bateria_lipo_3s", "abs", Vector3(0, 0.013, -0.06))
	var led: PartInstance = main._spawn("led", "abs", Vector3(0.05, 0.012, 0.02))
	main.wires = [{"uid": "wt", "a_key": main._key(bat.uid, "V+"), "b_key": main._key(led.uid, "anodo"), "tipo": "power", "color": "amarillo"}]
	main._redraw_wires()
	var pos = main._terminal_pos_by_key(main.wires[0]["a_key"])
	main.soldering.solder_at(pos, main.wires[0]["a_key"], main.wires_root)
	await main.soldering.finished
	await get_tree().process_frame
	check(bool(main.wires[0].get("soldado_a", false)), "Soldadura: el extremo queda marcado como soldado")
	var found := false
	for c in main.wires_root.get_children():
		for cc in c.get_children():
			if cc.name.begins_with("Soldadura"):
				found = true
	check(found, "Soldadura: menisco de estaño visible en el cable")
	check(main._solder_stats() == Vector2i(1, 2), "Soldadura: estadística 1/2 extremos")

#endregion

#region FÍSICA -------------------------------------------------------------------

func _gear_pair(backlash: float, eff: float) -> Array:
	main._on_new()
	var g1: PartInstance = main._spawn("engranaje_m1_z20", "acero", Vector3(-0.05, 0.5, 0))
	var g2: PartInstance = main._spawn("engranaje_m1_z40", "acero", Vector3(0.05, 0.5, 0))
	var c := Connection.new()
	c.a_uid = g1.uid; c.b_uid = g2.uid
	c.tipo = Connection.Tipo.ENGRANAJE; c.axis = 1
	c.gear_z1 = 20; c.gear_z2 = 40
	c.gear_backlash_deg = backlash
	c.gear_efficiency = eff
	main.simulator.start([c])
	for u in [g1.uid, g2.uid]:
		main.simulator.get_body(u).gravity_scale = 0.0
	return [g1, g2, c]

func _test_gear_backlash() -> void:
	var r := _gear_pair(10.0, 1.0)
	var b1: RigidBody3D = main.simulator.get_body(r[0].uid)
	var b2: RigidBody3D = main.simulator.get_body(r[1].uid)
	b1.angular_velocity = Vector3.UP * 2.0
	await wait_phys(2)
	var wb_early := b2.angular_velocity.y
	check(absf(wb_early) < 0.05, "Huelgo 10°: al arrancar la rueda conducida aún no gira (ω_b=%.3f)" % wb_early)
	await wait_phys(40)
	var wa := b1.angular_velocity.y
	var wb := b2.angular_velocity.y
	check(absf(wb / wa + 0.5) < 0.06, "Tras cerrar el huelgo: ω_b/ω_a = -Z1/Z2 = -0.5 (%.3f)" % (wb / wa))
	var ph: float = main.simulator.gear_phase(r[2].uid)
	check(absf(ph) <= deg_to_rad(5.0) + 0.01, "Sin desincronización: error de fase dentro del huelgo (%.2f°)" % rad_to_deg(ph))
	main.simulator.stop()

func _test_gear_efficiency() -> void:
	var e := []
	for eff in [1.0, 0.6]:
		var r := _gear_pair(0.2, eff)
		main.simulator.get_body(r[0].uid).angular_velocity = Vector3.UP * 3.0
		await wait_phys(60)
		e.append(absf(main.simulator.get_body(r[1].uid).angular_velocity.y))
		main.simulator.stop()
	check(absf(e[0] - 0.3) < 0.05, "Engrane ideal: conserva el momento (ω_b = 0.30 rad/s esperado, %.3f)" % e[0])
	check(e[1] < e[0] - 1e-3, "Rendimiento del engrane: con η=60%% la rueda conducida gira menos (%.3f < %.3f)" % [e[1], e[0]])

func _motor_pair(mtype: int) -> Array:
	main._on_new()
	var base: PartInstance = main._spawn("eje_acero_d10_150", "acero", Vector3(-0.03, 1.0, 0), Vector3(0, 0, PI / 2.0))
	var arm: PartInstance = main._spawn("eje_acero_d10_150", "acero", Vector3(0.03, 1.0, 0), Vector3(0, 0, PI / 2.0))
	var c := Connection.new()
	c.a_uid = base.uid; c.b_uid = arm.uid
	c.tipo = Connection.Tipo.BISAGRA; c.axis = 2
	c.anchor = (base.global_position + arm.global_position) * 0.5
	c.motor_enabled = true; c.motor_stall_torque = 4.0; c.motor_noload_speed = 10.0
	c.motor_type = mtype
	c.control_mode = Connection.ControlMode.POSICION
	c.ctrl_kp = 12.0; c.ctrl_ki = 0.0; c.ctrl_kd = 0.2
	return [base, arm, c]

func _test_stepper() -> void:
	var r := _motor_pair(Connection.MotorType.STEPPER)
	var c: Connection = r[2]
	c.step_deg = 1.8; c.microsteps = 1
	c.motor_noload_speed = 0.6                 # pocos pasos/s: escalones visibles
	c.ctrl_setpoint = deg_to_rad(9.0)
	main.simulator.start([c])
	for u in [r[0].uid, r[1].uid]:
		main.simulator.get_body(u).gravity_scale = 0.0
	var on_step := 0
	var samples := 0
	for i in range(60):
		await wait_phys(4)
		var ang := rad_to_deg(main.simulator.control_measure(c.uid))
		samples += 1
		var k := ang / 1.8
		if absf(k - round(k)) < 0.25:
			on_step += 1
	var final := rad_to_deg(main.simulator.control_measure(c.uid))
	check(absf(final - 9.0) < 0.6, "Stepper: alcanza 9° = 5 pasos de 1.8° (%.2f°)" % final)
	check(on_step >= samples * 0.6, "Stepper: se mueve a saltos discretos (%d/%d muestras sobre un paso)" % [on_step, samples])
	main.simulator.stop()

func _test_servo() -> void:
	var r := _motor_pair(Connection.MotorType.SERVO)
	var c: Connection = r[2]
	c.servo_sec_per_60 = 0.5                  # 120°/s = 2.09 rad/s
	c.ctrl_setpoint = deg_to_rad(90.0)
	main.simulator.start([c])
	for u in [r[0].uid, r[1].uid]:
		main.simulator.get_body(u).gravity_scale = 0.0
	var peak := 0.0
	for i in range(90):
		await wait_phys(2)
		var ba: RigidBody3D = main.simulator.get_body(r[0].uid)
		var bb: RigidBody3D = main.simulator.get_body(r[1].uid)
		peak = maxf(peak, absf((bb.angular_velocity - ba.angular_velocity).z))
	check(peak <= c.servo_speed() * 1.1, "Servo: velocidad limitada por su especificación 0.5 s/60° (pico %.2f ≤ %.2f rad/s)" % [peak, c.servo_speed()])
	var ang := rad_to_deg(main.simulator.control_measure(c.uid))
	check(absf(ang - 90.0) < 8.0, "Servo: alcanza la posición 90° (%.1f°)" % ang)
	main.simulator.stop()

func _test_serialization() -> void:
	var c := Connection.new()
	c.gear_backlash_deg = 2.5; c.gear_efficiency = 0.9
	var c2 := Connection.from_dict(c.to_dict())
	check(absf(c2.gear_backlash_deg - 2.5) < 1e-6 and absf(c2.gear_efficiency - 0.9) < 1e-6, "Serialización: huelgo y rendimiento del engranaje")
	var doc := ProjectSerializer.build_document(main.parts_root, [], [{"uid": "w", "a_key": "a:1", "b_key": "b:2", "tipo": "signal", "color": "verde", "soldado_a": true}])
	var w: Dictionary = ProjectSerializer.parse_wires(doc)[0]
	check(w.get("color") == "verde" and w.get("soldado_a") == true, "Serialización: color del cable y soldadura")

#endregion
