extends Node
## BasicTests — Pruebas básicas (Fase 1): catálogo, masas, rejilla, guardado, deshacer, importación
## de mallas y motores.
## Ejecutar:  Godot --headless --path project -- mftest

var main: Node
var ok: int = 0
var fail: int = 0

func check(cond: bool, nombre: String) -> void:
	if cond:
		ok += 1
		print("  [OK]   %s" % nombre)
	else:
		fail += 1
		print("  [FALLO] %s" % nombre)

func run() -> void:
	print("[TEST] Ejecutando pruebas de MechaForge (Fase 1)...")

	# 1. Biblioteca de piezas cargada.
	check(not PartLibrary.all_ids().is_empty(), "PartLibrary carga definiciones JSON")
	check(PartLibrary.has_part("perfil_2020_200"), "Existe la pieza 'perfil_2020_200'")

	# 2. Cálculo de masa (perfil 20x20x200 mm de aluminio).
	var def = PartLibrary.get_def("perfil_2020_200")
	var vol = PartLibrary.volume_m3(def)          # 0.02*0.2*0.02 * 0.463 (sección en T) = 3.7e-5 m³
	check(absf(vol - 8.0e-5 * 0.463) < 1.0e-7, "Volumen del perfil 20x20x200 (sección en T) correcto")
	var inst = PartInstance.new()
	main.add_child(inst)
	inst.setup(def)
	var masa = inst.mass_kg()                     # 2700 * 8e-5 * 0.463 (sección en T) = 0.100 kg
	check(absf(masa - 0.100) < 1.0e-3, "Masa del perfil 2020 (aluminio, sección en T) ≈ 0.100 kg (0.5 kg/m)")
	inst.queue_free()

	# 3. Snapping a la rejilla.
	Config.snap_enabled = true
	Config.set_grid_size_mm(10.0)
	check(absf(Config.snap_scalar(0.017) - 0.02) < 1.0e-6, "Snapping redondea 17 mm -> 20 mm")

	# 4. Serialización: ida y vuelta.
	for c in main.parts_root.get_children():
		c.queue_free()
	await get_tree().process_frame
	var a = main._spawn_from_dict({"def_id": "perfil_2020_200", "material": "acero", "pos": [0.1, 0.05, -0.2], "rot": [0, 0.5, 0]})
	var b = main._spawn_from_dict({"def_id": "placa_100x100", "material": "aluminio", "pos": [0, 0.0025, 0], "rot": [0, 0, 0]})
	var doc = ProjectSerializer.build_document(main.parts_root)
	check(doc.get("piezas", []).size() == 2, "Documento serializa 2 piezas")
	var tmp = "user://test_roundtrip.mforge"
	check(ProjectSerializer.save(main.parts_root, tmp) == OK, "Guardado sin error")
	check(ProjectSerializer.save(main.parts_root, tmp) == OK and not FileAccess.file_exists(tmp + ".tmp"),
		"Guardar encima de un proyecto lo reemplaza entero (sin dejar .tmp)")
	DirAccess.make_dir_absolute(tmp + ".tmp")     # el temporal no se puede crear
	var save_failed = ProjectSerializer.save(main.parts_root, tmp) != OK
	DirAccess.remove_absolute(tmp + ".tmp")
	check(save_failed and ProjectSerializer.load_document(tmp).get("piezas", []).size() == 2,
		"Si el guardado falla, el proyecto anterior queda entero")
	var loaded = ProjectSerializer.load_document(tmp)
	check(not loaded.is_empty() and loaded["piezas"].size() == 2, "Carga recupera 2 piezas")
	var n = ProjectSerializer.apply_document(loaded, main.parts_root)
	check(n == 2, "Reconstrucción instancia 2 piezas")
	# Verifica que se conserva material y posición de una pieza.
	var recuperada = main._find_part(a.uid)
	check(recuperada != null and recuperada.material_id == "acero", "Se conserva el material 'acero'")
	check(recuperada != null and recuperada.position.distance_to(Vector3(0.1, 0.05, -0.2)) < 1.0e-4, "Se conserva la posición")

	# 5. Mover pieza (nudge) + deshacer.
	Config.set_grid_size_mm(10.0)
	main._select(recuperada)
	var p_ini: Vector3 = recuperada.position
	main._nudge(Vector3(1, 0, 0))
	check(absf(recuperada.position.x - (p_ini.x + 0.01)) < 1.0e-6, "Empuje mueve la pieza 1 celda en X")
	main.undo()
	check(recuperada.position.distance_to(p_ini) < 1.0e-6, "Deshacer restaura la posición")

	# 6. Unidades.
	check(Units.fmt_mass(0.216) == "216.0 g", "Formato de masa < 1 kg en gramos")

	# 7. Parser de acciones de la IA (Fase 4).
	var ai_reply = "Claro.\n```json\n{\"acciones\":[{\"tipo\":\"add_part\",\"def_id\":\"perfil_2020_200\",\"material\":\"aluminio\",\"pos\":[0,0.1,0]}]}\n```"
	var acts = AiActions.parse(ai_reply)
	check(acts.size() == 1 and str(acts[0]["tipo"]) == "add_part", "IA: extrae acciones del bloque JSON")
	check(AiActions.parse("Tu grúa se vuelca por el centro de masa.").is_empty(), "IA: prosa sin acciones => vacío")

	# 8. BOM (Fase 5).
	main._on_new()
	main._spawn("perfil_2020_200", "aluminio", Vector3(0, 0.1, 0))
	main._spawn("perfil_2020_200", "aluminio", Vector3(0.1, 0.1, 0))
	main._export_bom()
	var bom = FileAccess.get_file_as_string("user://bom.csv")
	check(bom.contains("TOTAL") and bom.contains("perfil_2020_200"), "BOM: exporta CSV con piezas y total")

	# 9. Importador OBJ (Fase 5).
	var of = FileAccess.open("user://test.obj", FileAccess.WRITE)
	of.store_string("v 0 0 0\nv 0.1 0 0\nv 0 0.1 0\nf 1 2 3\n"); of.close()
	var m = MeshImporter.load_mesh("user://test.obj")
	check(m != null and m.get_surface_count() > 0, "Importador OBJ carga una malla")

	# 10. Mapa de esfuerzos: color verde→rojo.
	check(main._stress_color(0.0).g > 0.7 and main._stress_color(1.0).r > 0.7, "Esfuerzos: verde (bajo) a rojo (alto)")

	# 11. Motores F2/F3: stepper, engranaje por dientes, servo.
	var cm = Connection.new()
	cm.step_deg = 1.8; cm.microsteps = 1
	check(absf(rad_to_deg(cm.snap_to_step(deg_to_rad(46.0))) - 46.8) < 0.05, "Stepper: 46° ajusta a 46.8° (paso 1.8°)")
	cm.gear_z1 = 20; cm.gear_z2 = 40
	check(absf(cm.effective_gear_ratio() - 0.5) < 1.0e-6, "Engranaje por dientes 20/40 = 0.5")
	cm.servo_sec_per_60 = 0.15
	check(absf(rad_to_deg(cm.servo_speed()) - 400.0) < 1.0, "Servo: 0.15 s/60° ≈ 400°/s")

	print("[TEST] Resultado: %d OK, %d FALLOS" % [ok, fail])
	get_tree().quit(1 if fail > 0 else 0)
