extends Node
## EntornoTests — Protoboard MB-102, selección de uniones, cochera y texturas reales.
##   Godot --headless --path project -- mfentorno

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
	print("[TEST] Protoboard, uniones, cochera y texturas...")
	_test_protoboard()
	await _test_union_selection()
	await _test_garage()
	_test_textures()
	_test_thin_cables()
	await _test_joint_indicator()
	main.work_env.set_mode(WorkEnvironment.Mode.ESTUDIO)
	main._on_new()
	print("[TEST] Entorno: %d OK, %d FALLOS" % [ok, fail])
	get_tree().quit(1 if fail > 0 else 0)

func _test_protoboard() -> void:
	main._on_new()
	var pb: PartInstance = main._spawn("protoboard", "abs", Vector3(0, 0.005, 0))
	var terms: Array = pb.def["terminales"]
	check(terms.size() == 830, "Protoboard MB-102: 830 puntos (%d)" % terms.size())
	var ids := {}
	for t in terms:
		ids[t["id"]] = t
	check(ids.size() == 830, "Protoboard: ids únicos")
	var a0: Array = ids["a0_0"]["pos_mm"]
	var a1: Array = ids["a1_0"]["pos_mm"]
	check(absf(float(a1[0]) - float(a0[0]) - 2.54) < 1e-6 and absf(float(a0[0]) + 78.74) < 1e-4, "Paso de 2.54 mm y 63 columnas centradas (a0 en x = −78.74 mm)")
	check(absf(float(ids["a0_0"]["pos_mm"][2]) - 3.81) < 1e-6 and absf(float(ids["b0_0"]["pos_mm"][2]) + 3.81) < 1e-6, "Canal central de 7.62 mm entre las filas e y f")
	var rail := []
	for k in range(50):
		rail.append(float(ids["P1_%d" % k]["pos_mm"][0]))
	var gaps := 0
	for k in range(49):
		if rail[k + 1] - rail[k] > 3.0:
			gaps += 1
	check(gaps == 9, "Rieles de 50 puntos en 10 grupos de 5 (%d huecos)" % gaps)
	var grp := 0
	for t in terms:
		if t.get("grupo", "") == "TA10":
			grp += 1
	check(grp == 5, "Cada columna es un grupo interno de 5 agujeros")
	# Los agujeros del shader usan la misma fórmula que los terminales.
	check(is_equal_approx(PartInstance.bb_column_x(62), 78.74) and is_equal_approx(PartInstance.bb_row_z(false, 4), -13.97),
		"Agujeros dibujados = posiciones de los terminales (columna 63 en 78.74 mm, fila j en −13.97 mm)")

func _test_union_selection() -> void:
	main._on_new()
	var a: PartInstance = main._spawn("perfil_2020_200", "aluminio", Vector3(0, 0.1, 0))
	var b: PartInstance = main._spawn("perfil_2020_200", "aluminio", Vector3(0.1, 0.1, 0))
	var c: PartInstance = main._spawn("perfil_2020_200", "aluminio", Vector3(0.2, 0.1, 0))
	main._tpl_fix(a, b, Vector3(0.05, 0.1, 0))
	main._tpl_hinge(b, c, Vector3(0.15, 0.1, 0), 2, false)
	main._redraw_connection_markers()
	main._refresh_uniones_panel()
	var c1: Connection = main.connections[0]
	var c2: Connection = main.connections[1]
	var labels := []
	for uid in main._conn_markers:
		labels.append((main._conn_markers[uid]["label"] as Label3D).text)
	labels.sort()
	check(labels == ["1", "2"], "Marcadores 3D numerados como la lista (%s)" % str(labels))
	main._select_connection(c2.uid)
	check(b._highlight_box != null and c._highlight_box != null and a._highlight_box == null, "Seleccionar la unión 2 resalta sus dos piezas")
	check((main._conn_markers[c2.uid]["holder"] as Node3D).scale.x > 1.5, "El marcador seleccionado se agranda")
	# Clic sobre el marcador en pantalla selecciona la unión.
	var cam: CameraOrbit = main.camera
	cam.target = c1.anchor; cam.distance = 0.5; cam._update_transform()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var sp := cam.unproject_position(c1.anchor)
	check(main._pick_connection(sp) == c1.uid, "Clic en el marcador 3D selecciona esa unión")
	main._select_connection(c1.uid)
	main._delete_selected()
	check(main.connections.size() == 1 and main.connections[0].uid == c2.uid, "Supr borra solo la unión seleccionada")
	check(main._connection_details(c2, "A", "B").contains("Eje Z"), "Detalle de la unión (piezas, eje, anclaje)")

func _test_garage() -> void:
	main._on_new()
	var env: WorkEnvironment = main.work_env
	env.set_mode(WorkEnvironment.Mode.COCHERA)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(env._garage != null and env._garage.is_inside_tree(), "Entorno Cochera: la nave está en la escena")
	check(env.world_env.environment.sky.sky_material is PanoramaSkyMaterial and (env.world_env.environment.sky.sky_material as PanoramaSkyMaterial).panorama != null,
		"Cochera: HDRI real de fondo (Preller Drive)")
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(0, 1.0, 0), Vector3(0, 1.0, -10), 1)
	var hit := space.intersect_ray(q)
	check(not hit.is_empty() and absf((hit["position"] as Vector3).z + 4.0) < 0.05, "Pared del fondo con colisión (z = −4 m)")
	var q2 := PhysicsRayQueryParameters3D.create(Vector3(0, 1.0, 0), Vector3(0, 1.0, 10), 1)
	check(space.intersect_ray(q2).is_empty(), "El portón está abierto (se puede salir hacia la entrada)")
	# Una pieza que cae sobre la rampa queda por encima del suelo.
	var p: PartInstance = main._spawn("placa_100x100", "acero", Vector3(1.8, 0.3, 1.1))
	main.simulator.start([])
	await wait_phys(120)
	var y: float = main.simulator.get_body(p.uid).global_position.y
	check(y > 0.06, "La rampa tiene colisión: la placa queda apoyada sobre ella (y = %.3f m)" % y)
	main.simulator.stop()
	env.set_mode(WorkEnvironment.Mode.ESTUDIO)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(space.intersect_ray(q).is_empty(), "Al cambiar de entorno, la cochera y sus colisiones se retiran")

func _test_textures() -> void:
	for id in ["Plastic013A", "Plastic006", "Metal009", "Metal011", "Rubber004", "Concrete042A",
			"PaintedPlaster017", "Plaster003", "Wood066", "CorrugatedSteel009", "Metal055A", "Cardboard004"]:
		if not TextureSets.has_set(id):
			check(false, "Textura real %s disponible" % id)
			return
	check(true, "Texturas reales ambientCG (CC0) disponibles: 12 juegos")
	var abs_mat := MaterialLibrary.get_visual("abs")
	check(abs_mat.albedo_texture != null and abs_mat.albedo_texture.resource_path.contains("Plastic013A"), "Plástico ABS usa la textura fotográfica")
	var m := PartVisuals.mat(Color(0.1, 0.3, 0.7))
	check(m.albedo_texture != null and m.normal_enabled, "Carcasas de electrónica/actuadores: plástico real teñido con normales")
	var g := PartVisuals.mat(Color(0.85, 0.68, 0.25), 0.95, 0.3)
	check(g.albedo_texture != null and g.metallic > 0.9, "Pines y contactos: metal satinado real")
	check(main.work_env.find_hdris().has("res://assets/hdri/preller_drive_2k.hdr"), "HDRI incluido en la lista de entornos")

func _test_thin_cables() -> void:
	check(CableSim.RADIUS * 2.0 <= 0.0015, "Cables finos: Ø %.1f mm (jumper 22 AWG)" % (CableSim.RADIUS * 2000.0))
	# Dos cables casi superpuestos: el segundo se aparta del primero.
	var a1 := Vector3(-0.08, 0.01, 0.0)
	var b1 := Vector3(0.08, 0.01, 0.0)
	var c1 := CableSim.solve(a1, b1, [], 1.1)
	var c2 := CableSim.solve(a1 + Vector3(0, 0, 0.0005), b1 + Vector3(0, 0, 0.0005), [], 1.1, 22, 80, [c1])
	var min_d := INF
	for i in range(10, c2.size() - 10):
		for q in c1:
			min_d = minf(min_d, c2[i].distance_to(q))
	check(min_d >= CableSim.RADIUS * 2.0 + CableSim.GAP * 0.8, "Los cables no se atraviesan ni se enciman (separación mínima %.2f mm)" % (min_d * 1000.0))

func _test_joint_indicator() -> void:
	main._open_example("res://templates/01_brazo_4gdl.mforge")
	main._toggle_simulation()
	await wait_phys(30)
	var n: int = main.graph_selector.item_count
	check(n == 4 and main.graph_selector.get_item_text(1).begins_with("Unión 3"), "Gráfica: las uniones usan el mismo número que el panel (%s)" % main.graph_selector.get_item_text(1))
	main.graph_selector.select(2)
	main._on_graph_selected(2)
	await wait_phys(30)
	var conn: Connection = main._find_conn(main.graph_uid)
	var lbl: Label3D = null
	if main._joint_ind:
		for c in main._joint_ind.get_children():
			if c is Label3D: lbl = c
	check(lbl != null and lbl.text == "Unión %d" % (main.connections.find(conn) + 1), "En simulación, la unión elegida en la gráfica se señala en el modelo (%s)" % (lbl.text if lbl else "-"))
	check(main._joint_ind_boxes.size() == 2, "Sus dos piezas simuladas se resaltan")
	# La etiqueta sigue al anclaje (en el marco del cuerpo A).
	var b: RigidBody3D = main.simulator.get_body(conn.a_uid)
	main._update_joint_indicator()     # se actualiza en cada fotograma dibujado
	check(main._joint_ind.global_position.distance_to(b.global_transform * main._joint_ind_local) < 1e-4, "El indicador sigue al anclaje en movimiento")
	# Selector del microcontrolador: también señala.
	main.mcu_target_selector.select(1)
	main.mcu_target_selector.item_selected.emit(1)
	await wait_phys(2)
	var uid_m: String = main.mcu_target_selector.get_item_metadata(1)
	var lbl2: Label3D = null
	for c in main._joint_ind.get_children():
		if c is Label3D: lbl2 = c
	check(lbl2 != null and lbl2.text == "Unión %d" % (main.connections.find(main._find_conn(uid_m)) + 1), "Microcontrolador: «Actúa sobre» señala la unión en el modelo")
	main._toggle_simulation()
	check(main._joint_ind == null, "Al detener la simulación el indicador se retira")
