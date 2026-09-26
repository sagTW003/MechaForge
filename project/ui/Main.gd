extends Node3D
## Main — Controlador principal de MechaForge (Fase 1).
##
## Construye por código el entorno 3D (iluminación realista, cielo, suelo con
## rejilla), la cámara orbital y la interfaz en español (tema oscuro). Gestiona la
## colocación de piezas estructurales con snapping, selección, edición de
## propiedades, deshacer/rehacer y guardado/carga de proyectos en JSON.

const GRID_SIZE_OPTIONS := [1.0, 5.0, 10.0, 20.0, 50.0]  # mm
const ROT_STEP_OPTIONS := [5.0, 15.0, 45.0, 90.0]        # grados

# --- Nodos 3D ---
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var fill_light: DirectionalLight3D
var camera: CameraOrbit
var floor_mesh: MeshInstance3D
var parts_root: Node3D
var ghost: PartInstance

# --- Estado de edición ---
var current_def_id: String = ""
var current_material: String = "aluminio"
var selected_part: PartInstance = null
var placing: bool = false
var _pending_transform: Dictionary = {}  # para deshacer movimientos

# --- Física / simulación (Fase 2) ---
var simulator: Simulator
var sim_root: Node3D
var connections_root: Node3D
var connections: Array = []               # Array[Connection]
var connect_mode: bool = false
var connect_first: PartInstance = null
var sim_button: Button
var reset_button: Button
var connect_button: Button
var conn_dialog: Panel
var _conn_widgets: Dictionary = {}

# --- Deshacer / rehacer (basado en comandos) ---
var _undo: Array = []
var _redo: Array = []
const MAX_HISTORY := 200

# --- Referencias UI ---
var ui_layer: CanvasLayer
var fps_label: Label
var status_label: Label
var counts_label: Label
var parts_tree: Tree
var prop_container: VBoxContainer
var mat_option: OptionButton
var profile_option: OptionButton
var snap_check: CheckButton
var grid_option: OptionButton
var rot_option: OptionButton
var help_panel: Control
var file_dialog: FileDialog

var _mouse_over_ui: bool = false

func _ready() -> void:
	randomize()
	_build_environment()
	_build_camera()
	_build_floor()
	parts_root = Node3D.new()
	parts_root.name = "Piezas"
	add_child(parts_root)

	sim_root = Node3D.new()
	sim_root.name = "Simulacion"
	add_child(sim_root)
	connections_root = Node3D.new()
	connections_root.name = "MarcadoresUniones"
	add_child(connections_root)
	simulator = Simulator.new()
	simulator.name = "Simulador"
	add_child(simulator)
	simulator.setup(parts_root, sim_root)
	simulator.simulation_started.connect(_on_sim_started)
	simulator.simulation_stopped.connect(_on_sim_stopped)

	_build_ui()
	GraphicsProfiles.apply_auto(world_env.environment, get_viewport())
	_refresh_profile_option()
	_sync_grid_ui()
	Config.status_message.connect(_on_status)
	Config.notify("MechaForge listo. Elige una pieza en el panel izquierdo y haz clic para colocarla.", 6.0)
	set_process(true)
	if "mfbench" in OS.get_cmdline_user_args() or "--mfbench" in OS.get_cmdline_args():
		call_deferred("_run_benchmark")
	elif "mfshot" in OS.get_cmdline_user_args():
		call_deferred("_run_screenshot")
	elif "mftest" in OS.get_cmdline_user_args():
		call_deferred("_run_tests")
	elif "mfphys" in OS.get_cmdline_user_args():
		call_deferred("_run_phys_tests")
	elif "mfshot2" in OS.get_cmdline_user_args():
		call_deferred("_run_physics_shot")

func _run_physics_shot() -> void:
	var uargs := OS.get_cmdline_user_args()
	var i := uargs.find("mfshot2")
	var out_path := "user://mechaforge_fase2.png"
	if i >= 0 and i + 1 < uargs.size():
		out_path = uargs[i + 1]
	# Base pesada + poste fijo + brazo motorizado con bisagra.
	var base := _spawn("placa_base_200x200", "acero", Vector3(0, 0.004, 0))
	var post := _spawn("perfil_4040_300", "aluminio_anodizado", Vector3(0, 0.154, 0))
	var arm := _spawn("perfil_2020_400", "aluminio", Vector3(0.2, 0.29, 0), Vector3(0, 0, PI / 2.0))
	var weight := _spawn("eje_acero_d10_150", "acero_inox", Vector3(0.39, 0.29, 0), Vector3(PI / 2.0, 0, 0))
	# Uniones.
	var c1 := Connection.new(); c1.a_uid = base.uid; c1.b_uid = post.uid; c1.tipo = Connection.Tipo.FIJA
	c1.anchor = Vector3(0, 0.02, 0)
	var c2 := Connection.new(); c2.a_uid = post.uid; c2.b_uid = arm.uid; c2.tipo = Connection.Tipo.BISAGRA
	c2.axis = 2; c2.anchor = Vector3(0, 0.29, 0)
	c2.motor_enabled = true; c2.motor_target_speed = 2.5; c2.motor_stall_torque = 6.0; c2.motor_noload_speed = 5.0
	var c3 := Connection.new(); c3.a_uid = arm.uid; c3.b_uid = weight.uid; c3.tipo = Connection.Tipo.FIJA
	c3.anchor = Vector3(0.39, 0.29, 0)
	connections = [c1, c2, c3]
	_redraw_connection_markers()
	_update_counts()
	camera.target = Vector3(0.1, 0.2, 0)
	camera.distance = 1.3
	simulator.start(connections)
	_select(weight)
	await get_tree().create_timer(1.6).timeout
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_path)
	print("[SHOT2] Guardado en %s" % ProjectSettings.globalize_path(out_path))
	get_tree().quit()

#region PRUEBAS DE FÍSICA (Fase 2) ----------------------------------------------

func _pcheck(cond: bool, nombre: String) -> void:
	if cond:
		_test_ok += 1
		print("  [OK]   %s" % nombre)
	else:
		_test_fail += 1
		print("  [FALLO] %s" % nombre)

func _spawn(def_id: String, mat: String, pos: Vector3, rot := Vector3.ZERO) -> PartInstance:
	return _spawn_from_dict({"def_id": def_id, "material": mat, "pos": [pos.x, pos.y, pos.z], "rot": [rot.x, rot.y, rot.z]})

func _phys_wait(frames: int) -> void:
	for i in range(frames):
		await get_tree().physics_frame

func _run_phys_tests() -> void:
	print("[TEST] Pruebas de física (Fase 2)...")

	# --- 1) Gravedad + reinicio al estado inicial ---
	_on_new()
	var caida := _spawn("eje_acero_d10_150", "acero_inox", Vector3(0, 0.5, 0))
	var y0 := caida.position.y
	simulator.start([])
	await _phys_wait(80)
	var b := simulator.get_body(caida.uid)
	_pcheck(b != null and b.global_position.y < 0.45, "La pieza cae por gravedad (y baja)")
	simulator.stop()
	_pcheck(absf(caida.position.y - y0) < 1.0e-5, "Al detener, la pieza vuelve al estado inicial")

	# --- 2) Unión fija: mantiene la distancia entre piezas ---
	_on_new()
	var f1 := _spawn("perfil_2020_200", "aluminio", Vector3(-0.03, 0.5, 0))
	var f2 := _spawn("perfil_2020_200", "aluminio", Vector3(0.03, 0.5, 0))
	var cf := Connection.new(); cf.a_uid = f1.uid; cf.b_uid = f2.uid; cf.tipo = Connection.Tipo.FIJA
	cf.anchor = (f1.global_position + f2.global_position) * 0.5
	simulator.start([cf])
	var d0 := simulator.get_body(f1.uid).global_position.distance_to(simulator.get_body(f2.uid).global_position)
	await _phys_wait(100)
	var d1 := simulator.get_body(f1.uid).global_position.distance_to(simulator.get_body(f2.uid).global_position)
	_pcheck(absf(d1 - d0) < 0.005, "Unión fija conserva la distancia (%.4f→%.4f m)" % [d0, d1])
	simulator.stop()

	# --- 3) Motor de bisagra en espacio libre: velocidad RELATIVA no nula ---
	_on_new()
	var base := _spawn("eje_acero_d10_150", "acero", Vector3(-0.03, 1.0, 0), Vector3(0, 0, PI / 2.0))
	var arm := _spawn("eje_acero_d10_150", "acero", Vector3(0.03, 1.0, 0), Vector3(0, 0, PI / 2.0))
	var cm := Connection.new(); cm.a_uid = base.uid; cm.b_uid = arm.uid
	cm.tipo = Connection.Tipo.BISAGRA; cm.axis = 2
	cm.anchor = (base.global_position + arm.global_position) * 0.5
	cm.motor_enabled = true; cm.motor_target_speed = 6.0
	cm.motor_stall_torque = 3.0; cm.motor_noload_speed = 8.0
	simulator.start([cm])
	await _phys_wait(150)
	var ba := simulator.get_body(base.uid)
	var bb := simulator.get_body(arm.uid)
	var rel := absf((bb.angular_velocity - ba.angular_velocity).dot(cm.axis_vector()))
	_pcheck(rel > 0.2, "El motor genera giro relativo entre piezas (Δω=%.2f rad/s)" % rel)
	simulator.stop()

	# --- 4) Engranaje: acoplamiento cinemático ω_b = -ratio·ω_a ---
	_on_new()
	var g1 := _spawn("eje_acero_d10_150", "acero", Vector3(-0.1, 0.5, 0), Vector3(PI / 2.0, 0, 0))
	var g2 := _spawn("eje_acero_d10_150", "acero", Vector3(0.1, 0.5, 0), Vector3(PI / 2.0, 0, 0))
	var cg := Connection.new(); cg.a_uid = g1.uid; cg.b_uid = g2.uid
	cg.tipo = Connection.Tipo.ENGRANAJE; cg.axis = 1; cg.gear_ratio = 2.0
	simulator.start([cg])
	simulator.get_body(g1.uid).angular_velocity = Vector3.UP * 2.0
	await _phys_wait(5)
	var wb := simulator.get_body(g2.uid).angular_velocity.dot(Vector3.UP)
	_pcheck(absf(wb - (-4.0)) < 0.6, "Engranaje ratio 2: ω_b ≈ -4 rad/s (obtenido %.2f)" % wb)
	simulator.stop()

	_on_new()
	print("[TEST] Física: %d OK, %d FALLOS" % [_test_ok, _test_fail])
	get_tree().quit(1 if _test_fail > 0 else 0)

#endregion

#region PRUEBAS AUTOMATIZADAS (Fase 1) ------------------------------------------

var _test_ok: int = 0
var _test_fail: int = 0

func _check(cond: bool, nombre: String) -> void:
	if cond:
		_test_ok += 1
		print("  [OK]   %s" % nombre)
	else:
		_test_fail += 1
		print("  [FALLO] %s" % nombre)

func _run_tests() -> void:
	print("[TEST] Ejecutando pruebas de MechaForge (Fase 1)...")

	# 1. Biblioteca de piezas cargada.
	_check(not PartLibrary.all_ids().is_empty(), "PartLibrary carga definiciones JSON")
	_check(PartLibrary.has_part("perfil_2020_200"), "Existe la pieza 'perfil_2020_200'")

	# 2. Cálculo de masa (perfil 20x20x200 mm de aluminio).
	var def := PartLibrary.get_def("perfil_2020_200")
	var vol := PartLibrary.volume_m3(def)          # 0.02*0.2*0.02 = 8e-5 m³
	_check(absf(vol - 8.0e-5) < 1.0e-7, "Volumen del perfil 20x20x200 correcto")
	var inst := PartInstance.new()
	add_child(inst)
	inst.setup(def)
	var masa := inst.mass_kg()                     # 2700 * 8e-5 = 0.216 kg
	_check(absf(masa - 0.216) < 1.0e-3, "Masa del perfil (aluminio) ≈ 0.216 kg")
	inst.queue_free()

	# 3. Snapping a la rejilla.
	Config.snap_enabled = true
	Config.set_grid_size_mm(10.0)
	_check(absf(Config.snap_scalar(0.017) - 0.02) < 1.0e-6, "Snapping redondea 17 mm -> 20 mm")

	# 4. Serialización: ida y vuelta.
	for c in parts_root.get_children():
		c.queue_free()
	await get_tree().process_frame
	var a := _spawn_from_dict({"def_id": "perfil_2020_200", "material": "acero", "pos": [0.1, 0.05, -0.2], "rot": [0, 0.5, 0]})
	var b := _spawn_from_dict({"def_id": "placa_100x100", "material": "aluminio", "pos": [0, 0.0025, 0], "rot": [0, 0, 0]})
	var doc := ProjectSerializer.build_document(parts_root)
	_check(doc.get("piezas", []).size() == 2, "Documento serializa 2 piezas")
	var tmp := "user://test_roundtrip.mforge"
	_check(ProjectSerializer.save(parts_root, tmp) == OK, "Guardado sin error")
	var loaded := ProjectSerializer.load_document(tmp)
	_check(not loaded.is_empty() and loaded["piezas"].size() == 2, "Carga recupera 2 piezas")
	var n := ProjectSerializer.apply_document(loaded, parts_root)
	_check(n == 2, "Reconstrucción instancia 2 piezas")
	# Verifica que se conserva material y posición de una pieza.
	var recuperada := _find_part(a.uid)
	_check(recuperada != null and recuperada.material_id == "acero", "Se conserva el material 'acero'")
	_check(recuperada != null and recuperada.position.distance_to(Vector3(0.1, 0.05, -0.2)) < 1.0e-4, "Se conserva la posición")

	# 5. Unidades.
	_check(Units.fmt_mass(0.216) == "216.0 g", "Formato de masa < 1 kg en gramos")

	print("[TEST] Resultado: %d OK, %d FALLOS" % [_test_ok, _test_fail])
	get_tree().quit(1 if _test_fail > 0 else 0)

#endregion

#region CAPTURA (screenshot de demostración) ------------------------------------

func _run_screenshot() -> void:
	var uargs := OS.get_cmdline_user_args()
	var idx := uargs.find("mfshot")
	var out_path := "user://mechaforge_demo.png"
	if idx >= 0 and idx + 1 < uargs.size():
		out_path = uargs[idx + 1]
	# Pequeño ensamblaje demo: placa base + 4 columnas + travesaños.
	_spawn_from_dict({"def_id": "placa_base_200x200", "material": "acero", "pos": [0, 0.004, 0], "rot": [0,0,0]})
	var xs := [-0.09, 0.09]
	var zs := [-0.09, 0.09]
	for x in xs:
		for z in zs:
			_spawn_from_dict({"def_id": "perfil_2020_200", "material": "aluminio", "pos": [x, 0.108, z], "rot": [0,0,0]})
	for x in xs:
		_spawn_from_dict({"def_id": "perfil_2020_200", "material": "aluminio_anodizado", "pos": [x, 0.208, 0], "rot": [1.5708, 0, 0]})
	_spawn_from_dict({"def_id": "eje_acero_d10_150", "material": "acero_inox", "pos": [0, 0.26, 0], "rot": [0,0,1.5708]})
	_update_counts()
	_select(null)
	camera.target = Vector3(0, 0.12, 0)
	camera.distance = 0.75
	await get_tree().create_timer(3.0).timeout  # deja converger SDFGI
	await RenderingServer.frame_post_draw       # asegura un frame dibujado
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	print("[SHOT] size=%s vacia=%s piezas=%d" % [img.get_size(), img.is_empty(), parts_root.get_child_count()])
	if not img.is_empty():
		print("[SHOT] pixel_centro=%s" % img.get_pixel(int(img.get_width()/2.0), int(img.get_height()/2.0)))
	var err := img.save_png(out_path)
	print("[SHOT] Guardado en %s (err=%d)" % [ProjectSettings.globalize_path(out_path), err])
	get_tree().quit()

#endregion

#region BENCHMARK ---------------------------------------------------------------

var _bench_active: bool = false
var _bench_frames: int = 0
var _bench_time: float = 0.0
var _bench_min_fps: float = 9999.0
var _bench_sum_fps: float = 0.0

func _run_benchmark() -> void:
	# Coloca ~200 piezas en una cuadrícula para estresar el render.
	var ids := PartLibrary.all_ids()
	if ids.is_empty():
		print("[BENCH] Sin piezas en la biblioteca."); get_tree().quit(); return
	var n := 200
	var side := 15
	for k in range(n):
		var def_id: String = ids[k % ids.size()]
		var gx := (k % side) * 0.12 - 0.9
		var gz := (k / side) * 0.12 - 0.9
		var def := PartLibrary.get_def(def_id)
		_spawn_from_dict({
			"def_id": def_id, "material": def.get("material", "aluminio"),
			"pos": [gx, PartLibrary.dims_m(def).y * 0.5, gz], "rot": [0, 0, 0],
		})
	_update_counts()
	_select(null)
	camera.distance = 4.0
	_bench_active = true
	print("[BENCH] %d piezas colocadas. Midiendo FPS con perfil %s..." % [n, GraphicsProfiles.profile_name()])

func _bench_tick(delta: float) -> void:
	# Ignora el primer medio segundo (calentamiento).
	_bench_time += delta
	if _bench_time < 0.5:
		return
	_bench_frames += 1
	var fps := Engine.get_frames_per_second()
	_bench_sum_fps += fps
	_bench_min_fps = minf(_bench_min_fps, fps)
	if _bench_time >= 5.0:
		var avg := _bench_sum_fps / maxf(1.0, _bench_frames)
		print("[BENCH] Resultado -> Perfil: %s | GPU: %s" % [GraphicsProfiles.profile_name(), GraphicsProfiles.adapter_name])
		print("[BENCH] FPS promedio: %.1f | FPS minimo: %.1f | Piezas: 200 | Escala 3D: %.2f" % [avg, _bench_min_fps, GraphicsProfiles.current_scale()])
		_bench_active = false
		get_tree().quit()

#endregion

#region ENTORNO 3D --------------------------------------------------------------

func _build_environment() -> void:
	world_env = WorldEnvironment.new()
	world_env.name = "Entorno"
	var env := Environment.new()

	# Cielo físico para iluminación ambiental realista.
	var sky := Sky.new()
	var sky_mat := PhysicalSkyMaterial.new()
	sky_mat.rayleigh_coefficient = 2.0
	sky_mat.mie_coefficient = 0.005
	sky_mat.turbidity = 6.0
	sky_mat.sun_disk_scale = 1.0
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	# Tonemapping filmico (ACES) y exposición.
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0

	# Oclusión ambiental, iluminación indirecta y reflejos en pantalla.
	env.ssao_enabled = true
	env.ssao_radius = 0.5
	env.ssao_intensity = 2.0
	env.ssil_enabled = true
	env.ssr_enabled = true
	env.ssr_max_steps = 32

	# Iluminación global en tiempo real.
	env.sdfgi_enabled = true
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 4

	# Glow / bloom para brillos metálicos.
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.05

	# Niebla volumétrica sutil (ambiente de taller).
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.008
	env.volumetric_fog_albedo = Color(0.7, 0.75, 0.8)

	world_env.environment = env
	add_child(world_env)

	# Sol direccional con sombras suaves.
	sun = DirectionalLight3D.new()
	sun.name = "Sol"
	sun.rotation_degrees = Vector3(-50, -40, 0)
	sun.light_energy = 1.4
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.shadow_blur = 1.5
	add_child(sun)

	# Luz de relleno fría para las zonas en sombra.
	fill_light = DirectionalLight3D.new()
	fill_light.name = "Relleno"
	fill_light.rotation_degrees = Vector3(-20, 140, 0)
	fill_light.light_energy = 0.25
	fill_light.light_color = Color(0.7, 0.8, 1.0)
	fill_light.shadow_enabled = false
	add_child(fill_light)

func _build_camera() -> void:
	camera = CameraOrbit.new()
	camera.name = "Camara"
	camera.target = Vector3(0, 0.1, 0)
	camera.distance = 1.2
	add_child(camera)
	camera.current = true

func _build_floor() -> void:
	floor_mesh = MeshInstance3D.new()
	floor_mesh.name = "Suelo"
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	floor_mesh.mesh = plane
	var shader := load("res://rendering/floor_grid.gdshader")
	if shader:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("minor_step", Config.grid_size_m)
		floor_mesh.material_override = mat
	floor_mesh.position = Vector3.ZERO
	add_child(floor_mesh)
	Config.grid_settings_changed.connect(_update_floor_grid)

func _update_floor_grid() -> void:
	if floor_mesh and floor_mesh.material_override is ShaderMaterial:
		(floor_mesh.material_override as ShaderMaterial).set_shader_parameter("minor_step", Config.grid_size_m)

#endregion

#region INTERFAZ ----------------------------------------------------------------

func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UI"
	add_child(ui_layer)

	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(root)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vbox)

	vbox.add_child(_build_topbar())

	var middle := HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(middle)

	middle.add_child(_build_left_panel())
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle.add_child(spacer)
	middle.add_child(_build_right_panel())

	vbox.add_child(_build_statusbar())

	_build_help_panel()
	_build_file_dialog()

func _panel(min_size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = min_size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.11, 0.13, 0.94)
	sb.border_color = Color(0.22, 0.24, 0.28)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", sb)
	return p

func _build_topbar() -> Control:
	var panel := _panel(Vector2(0, 44))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	panel.add_child(hb)

	hb.add_child(_button("Nuevo", _on_new))
	hb.add_child(_button("Abrir…", _on_open))
	hb.add_child(_button("Guardar", _on_save))
	hb.add_child(_button("Guardar como…", _on_save_as))
	hb.add_child(_vsep())
	hb.add_child(_button("Deshacer", undo))
	hb.add_child(_button("Rehacer", redo))
	hb.add_child(_vsep())

	sim_button = _button("▶  Simular", _toggle_simulation)
	hb.add_child(sim_button)
	reset_button = _button("⟲  Reiniciar", _reset_simulation)
	hb.add_child(reset_button)
	connect_button = _button("🔗  Conectar", _toggle_connect_mode)
	connect_button.toggle_mode = true
	hb.add_child(connect_button)
	hb.add_child(_vsep())

	snap_check = CheckButton.new()
	snap_check.text = "Snapping"
	snap_check.button_pressed = Config.snap_enabled
	snap_check.toggled.connect(func(v): Config.snap_enabled = v; Config.notify("Snapping: %s" % ("activado" if v else "desactivado")))
	hb.add_child(snap_check)

	hb.add_child(_label("Rejilla:"))
	grid_option = OptionButton.new()
	for mm in GRID_SIZE_OPTIONS:
		grid_option.add_item("%d mm" % int(mm))
	grid_option.item_selected.connect(func(i): Config.set_grid_size_mm(GRID_SIZE_OPTIONS[i]))
	hb.add_child(grid_option)

	hb.add_child(_label("Rotar:"))
	rot_option = OptionButton.new()
	for deg in ROT_STEP_OPTIONS:
		rot_option.add_item("%d°" % int(deg))
	rot_option.item_selected.connect(func(i): Config.rotation_step_deg = ROT_STEP_OPTIONS[i])
	rot_option.select(1)
	hb.add_child(rot_option)

	hb.add_child(_vsep())
	hb.add_child(_label("Calidad:"))
	profile_option = OptionButton.new()
	for i in [GraphicsProfiles.Profile.BAJO, GraphicsProfiles.Profile.MEDIO, GraphicsProfiles.Profile.ALTO, GraphicsProfiles.Profile.ULTRA]:
		profile_option.add_item(GraphicsProfiles.PROFILE_NAMES[i])
	profile_option.item_selected.connect(_on_profile_selected)
	hb.add_child(profile_option)

	var grow := Control.new()
	grow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(grow)

	fps_label = _label("FPS: --")
	fps_label.custom_minimum_size = Vector2(120, 0)
	hb.add_child(fps_label)

	return panel

func _build_left_panel() -> Control:
	var panel := _panel(Vector2(240, 0))
	var vb := VBoxContainer.new()
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(vb)

	var title := _label("Biblioteca de piezas")
	title.add_theme_font_size_override("font_size", 15)
	vb.add_child(title)

	parts_tree = Tree.new()
	parts_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parts_tree.hide_root = true
	parts_tree.item_selected.connect(_on_part_tree_selected)
	vb.add_child(parts_tree)
	_populate_parts_tree()
	return panel

func _populate_parts_tree() -> void:
	parts_tree.clear()
	var root := parts_tree.create_item()
	var cat_names := {
		"estructural": "Estructurales", "union": "Uniones", "transmision": "Transmisión",
		"actuador": "Actuadores", "sensor": "Sensores", "electronica": "Electrónica", "otros": "Otros",
	}
	for cat in PartLibrary.categories():
		var cat_item := parts_tree.create_item(root)
		cat_item.set_text(0, cat_names.get(cat, cat.capitalize()))
		cat_item.set_selectable(0, false)
		cat_item.set_custom_color(0, Color(0.96, 0.65, 0.14))
		for pid in PartLibrary.parts_in(cat):
			var def := PartLibrary.get_def(pid)
			var it := parts_tree.create_item(cat_item)
			it.set_text(0, def.get("nombre", pid))
			it.set_metadata(0, pid)

func _build_right_panel() -> Control:
	var panel := _panel(Vector2(280, 0))
	var vb := VBoxContainer.new()
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(vb)

	var title := _label("Propiedades")
	title.add_theme_font_size_override("font_size", 15)
	vb.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)

	prop_container = VBoxContainer.new()
	prop_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(prop_container)

	_refresh_properties()
	return panel

func _build_statusbar() -> Control:
	var panel := _panel(Vector2(0, 34))
	var hb := HBoxContainer.new()
	panel.add_child(hb)
	status_label = _label("Listo.")
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(status_label)
	counts_label = _label("")
	hb.add_child(counts_label)
	var hint := _label("  [H] Ayuda  ·  [Rueda] Zoom  ·  [Central] Orbitar  ·  [Mayús+Central] Pan")
	hint.add_theme_color_override("font_color", Color(0.55, 0.58, 0.62))
	hb.add_child(hint)
	return panel

func _build_help_panel() -> void:
	help_panel = _panel(Vector2(520, 0))
	help_panel.set_anchors_preset(Control.PRESET_CENTER)
	help_panel.position = Vector2(540, 220)
	help_panel.visible = false
	var vb := VBoxContainer.new()
	help_panel.add_child(vb)
	var t := _label("Atajos de teclado — MechaForge")
	t.add_theme_font_size_override("font_size", 16)
	vb.add_child(t)
	var help := """
CONSTRUCCIÓN
[Clic izquierdo]      Colocar pieza / seleccionar
[Clic derecho / Esc]  Cancelar / deseleccionar
[R]                   Rotar la pieza seleccionada
[Supr]                Eliminar la pieza seleccionada
[Ctrl+D]              Duplicar la pieza seleccionada
[Ctrl+Z] / [Ctrl+Y]   Deshacer / Rehacer
[G]                   Alternar snapping a la rejilla

SIMULACIÓN Y UNIONES
[Espacio]             Iniciar / detener la simulación
[⟲ Reiniciar]         Volver al estado inicial
[🔗 Conectar]         Unir dos piezas (bisagra, fija, etc.)

PROYECTO / CÁMARA
[Ctrl+S] / [Ctrl+O]   Guardar / Abrir proyecto
[F]                   Centrar la cámara
[Rueda]               Zoom
[Botón central]       Orbitar cámara
[Mayús+Central]       Desplazar (pan)
[H] / [F1]            Mostrar/ocultar esta ayuda
"""
	var rt := Label.new()
	rt.text = help
	rt.add_theme_font_size_override("font_size", 13)
	vb.add_child(rt)
	var close := _button("Cerrar", func(): help_panel.visible = false)
	vb.add_child(close)
	ui_layer.add_child(help_panel)

func _build_file_dialog() -> void:
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.use_native_dialog = true
	file_dialog.add_filter("*.%s ; Proyecto MechaForge" % Config.PROJECT_EXTENSION)
	ui_layer.add_child(file_dialog)

# --- Fábricas de widgets ---
func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b

func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l

func _vsep() -> VSeparator:
	return VSeparator.new()

#endregion

#region PROPIEDADES -------------------------------------------------------------

func _refresh_properties() -> void:
	if prop_container == null:
		return
	if simulator and simulator.is_running():
		_build_telemetry_panel()
		return
	for c in prop_container.get_children():
		c.queue_free()

	if selected_part == null:
		var info := _label("Ninguna pieza seleccionada.\n\nElige una pieza del panel izquierdo\ny haz clic en el suelo para colocarla.")
		info.add_theme_color_override("font_color", Color(0.6, 0.62, 0.66))
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		prop_container.add_child(info)
		return

	var def := selected_part.def
	_add_prop_row("Pieza", def.get("nombre", selected_part.def_id))
	_add_prop_row("Categoría", def.get("categoria", "-"))

	# Material editable.
	prop_container.add_child(_label("Material:"))
	mat_option = OptionButton.new()
	var idx := 0
	var sel := -1
	for mid in MaterialLibrary.ids():
		mat_option.add_item(MaterialLibrary.display_name(mid))
		mat_option.set_item_metadata(idx, mid)
		if mid == selected_part.material_id:
			sel = idx
		idx += 1
	if sel >= 0:
		mat_option.select(sel)
	mat_option.item_selected.connect(_on_material_changed)
	prop_container.add_child(mat_option)

	var dims := PartLibrary.dims_m(def)
	_add_prop_row("Dimensiones", "%s × %s × %s" % [Units.fmt_length(dims.x), Units.fmt_length(dims.y), Units.fmt_length(dims.z)])
	_add_prop_row("Volumen", Units.fmt_volume_cm3(PartLibrary.volume_m3(def)))
	_add_prop_row("Densidad", "%.0f kg/m³" % MaterialLibrary.density(selected_part.material_id))
	_add_prop_row("Masa", Units.fmt_mass(selected_part.mass_kg()))
	_add_prop_row("Posición", "X %.3f  Y %.3f  Z %.3f m" % [selected_part.position.x, selected_part.position.y, selected_part.position.z])
	_add_prop_row("Rotación Y", Units.fmt_angle(selected_part.rotation.y))

	prop_container.add_child(HSeparator.new())
	var hb := HBoxContainer.new()
	hb.add_child(_button("Duplicar", _duplicate_selected))
	hb.add_child(_button("Eliminar", _delete_selected))
	prop_container.add_child(hb)

func _add_prop_row(k: String, v: String) -> void:
	var hb := HBoxContainer.new()
	var kl := _label(k + ":")
	kl.custom_minimum_size = Vector2(110, 0)
	kl.add_theme_color_override("font_color", Color(0.6, 0.63, 0.68))
	hb.add_child(kl)
	var vl := _label(v)
	vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hb.add_child(vl)
	prop_container.add_child(hb)

func _on_material_changed(i: int) -> void:
	if selected_part == null:
		return
	var new_mat: String = mat_option.get_item_metadata(i)
	selected_part.material_id = new_mat
	selected_part._build_visual()
	selected_part.set_selected(true)
	Config.project_dirty = true
	_refresh_properties()

#endregion

#region COLOCACIÓN Y SELECCIÓN --------------------------------------------------

func _on_part_tree_selected() -> void:
	if editing_locked:
		return
	if connect_mode:
		_set_connect_mode(false)
	var it := parts_tree.get_selected()
	if it == null:
		return
	var pid = it.get_metadata(0)
	if pid == null:
		return
	current_def_id = pid
	_start_placing()

func _start_placing() -> void:
	placing = true
	_clear_ghost()
	var def := PartLibrary.get_def(current_def_id)
	if def.is_empty():
		return
	ghost = PartInstance.new()
	add_child(ghost)
	ghost.setup(def)
	ghost.material_id = current_material if MaterialLibrary.has_material(current_material) else def.get("material", "aluminio")
	_make_ghost_visual(ghost)
	Config.notify("Colocando: %s. Clic para confirmar, clic derecho/Esc para cancelar." % def.get("nombre", current_def_id), 4.0)

func _make_ghost_visual(inst: PartInstance) -> void:
	for c in inst.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).material_override = MaterialLibrary.get_ghost(inst.material_id, true)
		elif c is StaticBody3D:
			c.queue_free()  # el fantasma no debe ser seleccionable

func _clear_ghost() -> void:
	if ghost:
		ghost.queue_free()
		ghost = null

func _cancel_placing() -> void:
	placing = false
	_clear_ghost()
	if parts_tree.get_selected():
		parts_tree.deselect_all()

func _ground_point(screen_pos: Vector2) -> Variant:
	var ray := camera.screen_ray(screen_pos)
	var plane := Plane(Vector3.UP, 0.0)
	var hit = plane.intersects_ray(ray["origin"], ray["dir"])
	return hit

func _process(_delta: float) -> void:
	if fps_label:
		fps_label.text = "FPS: %d  (x%.2f)" % [Engine.get_frames_per_second(), GraphicsProfiles.current_scale()]
	GraphicsProfiles.update_dynamic(_delta)
	if _bench_active:
		_bench_tick(_delta)
	if simulator and simulator.is_running():
		_tele_accum += _delta
		if _tele_accum >= 0.1:
			_tele_accum = 0.0
			_update_telemetry()
	if placing and ghost:
		var p = _ground_point(get_viewport().get_mouse_position())
		if p != null:
			var pos: Vector3 = Config.snap_vector(p)
			# Apoya la pieza sobre el suelo (su centro sube media altura).
			pos.y = PartLibrary.dims_m(ghost.def).y * 0.5
			ghost.position = pos

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if placing:
				_confirm_placement()
			elif connect_mode:
				_connect_pick(mb.position)
			else:
				_try_select(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if placing:
				_cancel_placing()
			elif connect_mode:
				_set_connect_mode(false)
			else:
				_select(null)
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event as InputEventKey)

func _confirm_placement() -> void:
	if ghost == null:
		return
	var cmd := {
		"type": "add",
		"data": {
			"uid": "",
			"def_id": current_def_id,
			"material": ghost.material_id,
			"pos": [ghost.position.x, ghost.position.y, ghost.position.z],
			"rot": [ghost.rotation.x, ghost.rotation.y, ghost.rotation.z],
		}
	}
	_do(cmd)
	# Mantener el modo colocación para poner varias piezas seguidas.
	_start_placing()

func _try_select(screen_pos: Vector2) -> void:
	var ray := camera.screen_ray(screen_pos)
	var space := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(
		ray["origin"], ray["origin"] + ray["dir"] * 1000.0, PartInstance.PICK_LAYER)
	var hit := space.intersect_ray(params)
	if hit.is_empty():
		_select(null)
		return
	var collider: Node = hit["collider"]
	if collider is RigidBody3D and collider.has_meta("part_uid"):
		_select(_find_part(collider.get_meta("part_uid")))
		return
	var part := collider.get_parent()
	if part is PartInstance:
		_select(part)
	else:
		_select(null)

func _select(part) -> void:
	if selected_part and is_instance_valid(selected_part):
		selected_part.set_selected(false)
	selected_part = part
	if selected_part:
		selected_part.set_selected(true)
	_refresh_properties()

#endregion

#region TECLADO -----------------------------------------------------------------

func _handle_key(k: InputEventKey) -> void:
	var ctrl := k.ctrl_pressed
	match k.keycode:
		KEY_ESCAPE:
			if placing: _cancel_placing()
			elif connect_mode: _set_connect_mode(false)
			else: _select(null)
		KEY_H, KEY_F1:
			help_panel.visible = not help_panel.visible
		KEY_SPACE:
			_toggle_simulation()
		KEY_G:
			Config.snap_enabled = not Config.snap_enabled
			snap_check.button_pressed = Config.snap_enabled
		KEY_R when not editing_locked:
			_rotate_selected()
		KEY_DELETE when not editing_locked:
			_delete_selected()
		KEY_Z when ctrl and not editing_locked:
			undo()
		KEY_Y when ctrl and not editing_locked:
			redo()
		KEY_S when ctrl:
			_on_save()
		KEY_O when ctrl:
			_on_open()
		KEY_D when ctrl and not editing_locked:
			_duplicate_selected()

func _rotate_selected() -> void:
	if selected_part == null:
		if placing and ghost:
			ghost.rotation.y += deg_to_rad(Config.rotation_step_deg)
		return
	var old_rot := selected_part.rotation
	var new_rot := old_rot
	new_rot.y += deg_to_rad(Config.rotation_step_deg)
	_do({
		"type": "transform", "uid": selected_part.uid,
		"old": _xf_of(selected_part), "new": {"pos": _arr(selected_part.position), "rot": _arr(new_rot)},
	})

#endregion

#region COMANDOS / DESHACER-REHACER ---------------------------------------------

func _do(cmd: Dictionary) -> void:
	_apply(cmd)
	_undo.append(cmd)
	if _undo.size() > MAX_HISTORY:
		_undo.pop_front()
	_redo.clear()
	Config.project_dirty = true
	_update_counts()

func _apply(cmd: Dictionary) -> void:
	match cmd["type"]:
		"add":
			var inst := _spawn_from_dict(cmd["data"])
			cmd["data"]["uid"] = inst.uid   # fija el uid para deshacer coherente
			_select(inst)
		"remove":
			var inst := _find_part(cmd["data"]["uid"])
			if inst:
				if selected_part == inst: _select(null)
				inst.queue_free()
		"transform":
			var inst := _find_part(cmd["uid"])
			if inst:
				inst.position = _vec(cmd["new"]["pos"])
				inst.rotation = _vec(cmd["new"]["rot"])
				if selected_part == inst: _refresh_properties()

func _revert(cmd: Dictionary) -> void:
	match cmd["type"]:
		"add":
			var inst := _find_part(cmd["data"]["uid"])
			if inst:
				if selected_part == inst: _select(null)
				inst.queue_free()
		"remove":
			_spawn_from_dict(cmd["data"])
		"transform":
			var inst := _find_part(cmd["uid"])
			if inst:
				inst.position = _vec(cmd["old"]["pos"])
				inst.rotation = _vec(cmd["old"]["rot"])
				if selected_part == inst: _refresh_properties()

func undo() -> void:
	if _undo.is_empty():
		Config.notify("Nada que deshacer.")
		return
	var cmd: Dictionary = _undo.pop_back()
	_revert(cmd)
	_redo.append(cmd)
	Config.project_dirty = true
	_update_counts()
	Config.notify("Deshacer.")

func redo() -> void:
	if _redo.is_empty():
		Config.notify("Nada que rehacer.")
		return
	var cmd: Dictionary = _redo.pop_back()
	_apply(cmd)
	_undo.append(cmd)
	Config.project_dirty = true
	_update_counts()
	Config.notify("Rehacer.")

func _delete_selected() -> void:
	if selected_part == null:
		return
	_do({"type": "remove", "data": selected_part.to_dict()})

func _duplicate_selected() -> void:
	if selected_part == null:
		return
	var d := selected_part.to_dict()
	d["uid"] = ""
	d["pos"][0] += Config.grid_size_m * 4.0
	_do({"type": "add", "data": d})

#endregion

#region UTILIDADES DE PIEZAS ----------------------------------------------------

func _spawn_from_dict(d: Dictionary) -> PartInstance:
	var def := PartLibrary.get_def(d["def_id"])
	var inst := PartInstance.new()
	parts_root.add_child(inst)
	inst.setup(def, d.get("uid", ""))
	inst.material_id = d.get("material", def.get("material", "aluminio"))
	inst._build_visual()
	inst.position = _vec(d.get("pos", [0, 0, 0]))
	inst.rotation = _vec(d.get("rot", [0, 0, 0]))
	return inst

func _find_part(uid: String) -> PartInstance:
	for c in parts_root.get_children():
		if c is PartInstance and (c as PartInstance).uid == uid:
			return c
	return null

func _xf_of(p: PartInstance) -> Dictionary:
	return {"pos": _arr(p.position), "rot": _arr(p.rotation)}

func _arr(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func _vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])

func _update_counts() -> void:
	if counts_label == null:
		return
	var n := 0
	var total_mass := 0.0
	for c in parts_root.get_children():
		if c is PartInstance:
			n += 1
			total_mass += (c as PartInstance).mass_kg()
	counts_label.text = "Piezas: %d   Uniones: %d   Masa total: %s     " % [n, connections.size(), Units.fmt_mass(total_mass)]

#endregion

#region PERFIL / ESTADO / ARCHIVOS ----------------------------------------------

func _on_profile_selected(i: int) -> void:
	var profiles := [GraphicsProfiles.Profile.BAJO, GraphicsProfiles.Profile.MEDIO, GraphicsProfiles.Profile.ALTO, GraphicsProfiles.Profile.ULTRA]
	GraphicsProfiles.apply_profile(int(profiles[i]), world_env.environment, get_viewport())

func _refresh_profile_option() -> void:
	if profile_option:
		profile_option.select(GraphicsProfiles.current_profile)

func _sync_grid_ui() -> void:
	var idx := GRID_SIZE_OPTIONS.find(Config.grid_size_mm())
	if idx >= 0 and grid_option:
		grid_option.select(idx)

func _on_status(text: String, _seconds: float) -> void:
	if status_label:
		status_label.text = text

func _on_new() -> void:
	if simulator.is_running():
		simulator.stop()
	for c in parts_root.get_children():
		c.queue_free()
	connections.clear()
	_redraw_connection_markers()
	_undo.clear()
	_redo.clear()
	_select(null)
	Config.current_project_path = ""
	Config.project_dirty = false
	_update_counts()
	Config.notify("Proyecto nuevo.")

func _on_save() -> void:
	if Config.current_project_path == "":
		_on_save_as()
		return
	var err := ProjectSerializer.save(parts_root, Config.current_project_path, connections)
	if err == OK:
		Config.project_dirty = false
		Config.notify("Guardado en %s" % Config.current_project_path, 4.0)
	else:
		Config.notify("Error al guardar (código %d)" % err, 5.0)

func _on_save_as() -> void:
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.title = "Guardar proyecto MechaForge"
	file_dialog.current_file = "proyecto.%s" % Config.PROJECT_EXTENSION
	_connect_dialog(func(path):
		Config.current_project_path = path
		_on_save())
	file_dialog.popup_centered_ratio(0.6)

func _on_open() -> void:
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.title = "Abrir proyecto MechaForge"
	_connect_dialog(func(path):
		var doc := ProjectSerializer.load_document(path)
		if doc.is_empty():
			Config.notify("No se pudo abrir el archivo.", 5.0)
			return
		if simulator.is_running(): simulator.stop()
		var n := ProjectSerializer.apply_document(doc, parts_root)
		connections = ProjectSerializer.parse_connections(doc)
		_redraw_connection_markers()
		_undo.clear(); _redo.clear(); _select(null)
		Config.current_project_path = path
		Config.project_dirty = false
		_sync_grid_ui()
		_update_counts()
		Config.notify("Cargadas %d piezas desde %s" % [n, path], 4.0))
	file_dialog.popup_centered_ratio(0.6)

var _dialog_cb: Callable = Callable()
func _connect_dialog(cb: Callable) -> void:
	if file_dialog.file_selected.is_connected(_dialog_relay):
		file_dialog.file_selected.disconnect(_dialog_relay)
	_dialog_cb = cb
	file_dialog.file_selected.connect(_dialog_relay)

func _dialog_relay(path: String) -> void:
	if _dialog_cb.is_valid():
		_dialog_cb.call(path)

#endregion

#region SIMULACIÓN Y UNIONES (Fase 2) -------------------------------------------

var editing_locked: bool = false
var _tele_labels: Dictionary = {}
var _tele_accum: float = 0.0

func _toggle_simulation() -> void:
	if simulator.is_running():
		simulator.stop()
	else:
		_cancel_placing()
		_set_connect_mode(false)
		simulator.start(connections)

func _reset_simulation() -> void:
	if simulator.is_running():
		simulator.stop()
		await get_tree().process_frame
		simulator.start(connections)
		Config.notify("Simulación reiniciada al estado inicial.")

func _on_sim_started() -> void:
	sim_button.text = "⏸  Editar"
	_select(null)
	_set_editing_enabled(false)
	connections_root.visible = false
	Config.notify("Simulación en marcha. Selecciona una pieza para ver su telemetría.", 4.0)

func _on_sim_stopped() -> void:
	sim_button.text = "▶  Simular"
	_select(null)
	_set_editing_enabled(true)
	connections_root.visible = true
	_refresh_properties()
	Config.notify("Modo edición.")

func _set_editing_enabled(en: bool) -> void:
	editing_locked = not en
	if connect_button: connect_button.disabled = not en
	if parts_tree and not en: parts_tree.deselect_all()

# --- Modo conexión ---
func _toggle_connect_mode() -> void:
	_set_connect_mode(not connect_mode)

func _set_connect_mode(on: bool) -> void:
	if simulator.is_running():
		on = false
	connect_mode = on
	if connect_button: connect_button.button_pressed = on
	if connect_first and is_instance_valid(connect_first):
		connect_first.set_selected(false)
	connect_first = null
	if on:
		_cancel_placing()
		_select(null)
		Config.notify("Conexión: clic en la 1.ª pieza y luego en la 2.ª para unirlas.", 6.0)

func _connect_pick(screen_pos: Vector2) -> void:
	var part := _pick_part(screen_pos)
	if part == null:
		return
	if connect_first == null:
		connect_first = part
		part.set_selected(true)
		Config.notify("1.ª pieza: %s. Ahora elige la 2.ª." % part.def.get("nombre", part.def_id))
	elif part == connect_first:
		Config.notify("Elige una pieza distinta para conectar.")
	else:
		var a := connect_first
		connect_first = null
		a.set_selected(false)
		_open_connection_dialog(a, part)

func _pick_part(screen_pos: Vector2) -> PartInstance:
	var ray := camera.screen_ray(screen_pos)
	var space := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(
		ray["origin"], ray["origin"] + ray["dir"] * 1000.0, PartInstance.PICK_LAYER)
	var hit := space.intersect_ray(params)
	if hit.is_empty():
		return null
	var collider: Node = hit["collider"]
	if collider is RigidBody3D and collider.has_meta("part_uid"):
		return _find_part(collider.get_meta("part_uid"))
	var p := collider.get_parent()
	return p if p is PartInstance else null

# --- Diálogo de configuración de unión ---
func _open_connection_dialog(a: PartInstance, b: PartInstance) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Nueva unión"
	dlg.ok_button_text = "Crear"
	dlg.get_cancel_button().text = "Cancelar"
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	dlg.add_child(vb)

	vb.add_child(_label("Unir:  %s  ↔  %s" % [a.def.get("nombre", a.def_id), b.def.get("nombre", b.def_id)]))

	vb.add_child(_label("Tipo de unión:"))
	var tipo_opt := OptionButton.new()
	for t in [Connection.Tipo.FIJA, Connection.Tipo.BISAGRA, Connection.Tipo.DESLIZADERA, Connection.Tipo.ROTULA, Connection.Tipo.ENGRANAJE]:
		tipo_opt.add_item(Connection.TIPO_NOMBRE[t])
	tipo_opt.select(1)
	vb.add_child(tipo_opt)

	vb.add_child(_label("Eje (mundo):"))
	var eje_opt := OptionButton.new()
	for ax in Connection.AXIS_NOMBRE:
		eje_opt.add_item(ax)
	eje_opt.select(1)
	vb.add_child(eje_opt)

	var lim_check := CheckBox.new(); lim_check.text = "Con límites (grados / mm)"
	vb.add_child(lim_check)
	var lim_hb := HBoxContainer.new()
	var low_spin := _spin(-360, 360, 1, -45)
	var high_spin := _spin(-360, 360, 1, 45)
	lim_hb.add_child(_label("inf")); lim_hb.add_child(low_spin)
	lim_hb.add_child(_label("sup")); lim_hb.add_child(high_spin)
	vb.add_child(lim_hb)

	var motor_check := CheckBox.new(); motor_check.text = "Motor (solo bisagra)"
	vb.add_child(motor_check)
	var motor_vb := VBoxContainer.new()
	var speed_spin := _spin(-50, 50, 0.5, 4.0)
	var torque_spin := _spin(0, 100, 0.1, 0.8)
	var noload_spin := _spin(0.1, 100, 0.5, 8.0)
	motor_vb.add_child(_label("Vel. objetivo (rad/s)")); motor_vb.add_child(speed_spin)
	motor_vb.add_child(_label("Torque de arranque (N·m)")); motor_vb.add_child(torque_spin)
	motor_vb.add_child(_label("Vel. sin carga (rad/s)")); motor_vb.add_child(noload_spin)
	vb.add_child(motor_vb)

	vb.add_child(_label("Relación (engranaje):"))
	var ratio_spin := _spin(-10, 10, 0.1, 1.0)
	vb.add_child(ratio_spin)

	ui_layer.add_child(dlg)
	dlg.confirmed.connect(func():
		var c := Connection.new()
		c.a_uid = a.uid; c.b_uid = b.uid
		c.tipo = [Connection.Tipo.FIJA, Connection.Tipo.BISAGRA, Connection.Tipo.DESLIZADERA, Connection.Tipo.ROTULA, Connection.Tipo.ENGRANAJE][tipo_opt.selected]
		c.axis = eje_opt.selected
		c.anchor = (a.global_position + b.global_position) * 0.5
		c.limit_enabled = lim_check.button_pressed
		if c.tipo == Connection.Tipo.DESLIZADERA:
			c.limit_lower = low_spin.value / 1000.0
			c.limit_upper = high_spin.value / 1000.0
		else:
			c.limit_lower = deg_to_rad(low_spin.value)
			c.limit_upper = deg_to_rad(high_spin.value)
		c.motor_enabled = motor_check.button_pressed
		c.motor_target_speed = speed_spin.value
		c.motor_stall_torque = torque_spin.value
		c.motor_noload_speed = noload_spin.value
		c.gear_ratio = ratio_spin.value
		connections.append(c)
		Config.project_dirty = true
		_redraw_connection_markers()
		_update_counts()
		Config.notify("Unión creada: %s (%s)." % [c.tipo_nombre(), Connection.AXIS_NOMBRE[c.axis]])
		dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.popup_centered(Vector2i(380, 460))

func _spin(mn: float, mx: float, step: float, val: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = mn; s.max_value = mx; s.step = step; s.value = val
	s.custom_minimum_size = Vector2(90, 0)
	return s

# --- Marcadores de uniones (modo edición) ---
func _redraw_connection_markers() -> void:
	for c in connections_root.get_children():
		c.queue_free()
	var colors := {
		Connection.Tipo.FIJA: Color(0.7, 0.7, 0.7), Connection.Tipo.BISAGRA: Color(0.96, 0.65, 0.14),
		Connection.Tipo.DESLIZADERA: Color(0.3, 0.6, 1.0), Connection.Tipo.ROTULA: Color(0.3, 0.9, 0.5),
		Connection.Tipo.ENGRANAJE: Color(0.7, 0.4, 1.0),
	}
	for conn in connections:
		var a := _find_part(conn.a_uid)
		var b := _find_part(conn.b_uid)
		if a == null or b == null:
			continue
		connections_root.add_child(_make_link_marker(a.global_position, b.global_position, colors.get(conn.tipo, Color.WHITE)))

func _make_link_marker(p1: Vector3, p2: Vector3, color: Color) -> Node3D:
	var holder := Node3D.new()
	var mid := (p1 + p2) * 0.5
	var dist := p1.distance_to(p2)
	var cyl := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.004; mesh.bottom_radius = 0.004
	mesh.height = maxf(0.001, dist)
	cyl.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true; mat.emission = color; mat.emission_energy_multiplier = 0.6
	cyl.material_override = mat
	holder.add_child(cyl)
	holder.global_position = mid
	if dist > 0.0001:
		# Orienta el eje Y del cilindro a lo largo de p1->p2.
		var dir := (p2 - p1).normalized()
		if absf(dir.dot(Vector3.UP)) < 0.999:
			holder.look_at(mid + dir, Vector3.UP)
			holder.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	# Esfera en el anclaje.
	var sph := MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = 0.012; sm.height = 0.024
	sph.mesh = sm; sph.material_override = mat
	sph.position = Vector3.ZERO
	holder.add_child(sph)
	return holder

# --- Telemetría en vivo durante la simulación ---
func _build_telemetry_panel() -> void:
	for c in prop_container.get_children():
		c.queue_free()
	_tele_labels.clear()
	if selected_part == null:
		var info := _label("Simulación en marcha.\nSelecciona una pieza para ver\nsu telemetría en vivo.")
		info.add_theme_color_override("font_color", Color(0.6, 0.62, 0.66))
		prop_container.add_child(info)
		_add_com_labels()
		return
	_add_prop_row("Pieza", selected_part.def.get("nombre", selected_part.def_id))
	for key in ["Posición", "Velocidad", "Rapidez", "Vel. angular", "Masa"]:
		var hb := HBoxContainer.new()
		var kl := _label(key + ":"); kl.custom_minimum_size = Vector2(96, 0)
		kl.add_theme_color_override("font_color", Color(0.6, 0.63, 0.68))
		hb.add_child(kl)
		var vl := _label("—"); vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(vl)
		prop_container.add_child(hb)
		_tele_labels[key] = vl
	prop_container.add_child(HSeparator.new())
	_add_com_labels()

func _add_com_labels() -> void:
	var hb := HBoxContainer.new()
	var kl := _label("Centro de masa:"); kl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.6))
	hb.add_child(kl)
	var vl := _label("—"); vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vl)
	prop_container.add_child(hb)
	_tele_labels["COM"] = vl

func _update_telemetry() -> void:
	if selected_part and _tele_labels.has("Posición"):
		var t := simulator.telemetry(selected_part.uid)
		if not t.is_empty():
			_tele_labels["Posición"].text = "X %.3f  Y %.3f  Z %.3f m" % [t["pos"].x, t["pos"].y, t["pos"].z]
			_tele_labels["Velocidad"].text = "%.3f, %.3f, %.3f m/s" % [t["vel"].x, t["vel"].y, t["vel"].z]
			_tele_labels["Rapidez"].text = Units.fmt_speed(t["speed"])
			_tele_labels["Vel. angular"].text = "%.2f rad/s" % t["ang_speed"]
			_tele_labels["Masa"].text = Units.fmt_mass(t["mass"])
	if _tele_labels.has("COM"):
		var com := simulator.center_of_mass()
		_tele_labels["COM"].text = "X %.3f Y %.3f Z %.3f m  ·  %s" % [com["pos"].x, com["pos"].y, com["pos"].z, Units.fmt_mass(com["mass"])]

#endregion
