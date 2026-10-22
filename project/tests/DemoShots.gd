extends Node
## DemoShots — Capturas de demostración del refactor gráfico.
##   Godot --path project -- mfshot11 <salida.png> [env <0|1|2>] [gizmo]
## Escena: bastidor de perfiles en T sobre placa perforada, tren de engranajes con
## motor, electrónica (PCB, batería, LED) con cables físicos soldados, placa de
## fibra de carbono y pieza de cobre; opcionalmente el gizmo 3D sobre una pieza.

var main: Node

func run(out_path: String, env_mode: int, show_gizmo: bool, close: bool = false, template: String = "") -> void:
	main.work_env.set_mode(env_mode)
	if template == "seguidor":
		await _template_shot(out_path)
		return
	if template == "indicador":
		main._open_example("res://templates/01_brazo_4gdl.mforge")
		for p in [main.biblioteca_panel, main.propiedades_panel, main.uniones_panel, main.circuito_panel]:
			if p: p.visible = false
		main._toggle_simulation()
		await get_tree().create_timer(1.5).timeout
		main.graph_selector.select(2)
		main._on_graph_selected(2)
		MaterialLibrary.wait_textures()
		await get_tree().create_timer(2.0).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out_path)
		print("[SHOT11] Guardado en %s" % ProjectSettings.globalize_path(out_path))
		get_tree().quit()
		return
	if template == "uniones":
		main._open_example("res://templates/01_brazo_4gdl.mforge")
		for p in [main.biblioteca_panel, main.propiedades_panel, main.mcu_panel, main.circuito_panel]:
			if p: p.visible = false
		main.uniones_panel.position = Vector2(8, 60)
		main._select_connection(main.connections[3].uid)
		MaterialLibrary.wait_textures()
		await get_tree().create_timer(2.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out_path)
		print("[SHOT11] Guardado en %s" % ProjectSettings.globalize_path(out_path))
		get_tree().quit()
		return
	if template.begins_with("cochera"):
		await _garage_shot(out_path, template)
		return
	if template in ["multimetro", "dmmcerca", "arduino", "corto", "dip", "fusible"]:
		await _electronics_shot(out_path, template)
		return
	if template.begins_with("ej:"):
		await _example_shot("res://templates/%s.mforge" % template.substr(3), out_path)
		return
	if template == "vr0":
		await _vr0_shot(out_path)
		return
	if template == "vr1":
		await _vr1_shot(out_path)
		return
	if template == "vr2":
		await _vr2_shot(out_path)
		return
	if template == "vr3":
		await _vr3_shot(out_path)
		return
	var sp := func(id: String, mat: String, pos: Vector3, rot := Vector3.ZERO) -> PartInstance:
		return main._spawn(id, mat, pos, rot)
	# Placa base perforada y bastidor de perfiles 2020.
	sp.call("placa_base_200x200", "acero", Vector3(0, 0.004, 0))
	for x in [-0.09, 0.09]:
		sp.call("perfil_2020_200", "aluminio", Vector3(x, 0.108, -0.09))
	sp.call("perfil_2020_200", "aluminio_anodizado", Vector3(0, 0.218, -0.09), Vector3(0, 0, PI / 2.0))
	# Tren de engranajes: Z20 (acero) + Z40 (acero) sobre ejes, y motor DC.
	sp.call("eje_acero_d10_150", "acero_inox", Vector3(-0.03, 0.083, 0.03))
	sp.call("eje_acero_d10_150", "acero_inox", Vector3(0.0, 0.083, 0.03))
	sp.call("engranaje_m1_z20", "acero", Vector3(-0.03, 0.12, 0.03))
	sp.call("engranaje_m1_z40", "cobre", Vector3(0.0, 0.12, 0.03), Vector3(0, deg_to_rad(4.5), 0))
	sp.call("motor_dc", "acero", Vector3(-0.07, 0.035, 0.06))
	# Electrónica.
	var mcu: PartInstance = sp.call("microcontrolador", "abs", Vector3(0.065, 0.013, 0.05))
	var bat: PartInstance = sp.call("bateria_lipo_3s", "abs", Vector3(0.02, 0.0205, 0.125))
	var led: PartInstance = sp.call("led", "abs", Vector3(0.08, 0.012, -0.02))
	sp.call("placa_100x100", "fibra_carbono", Vector3(-0.2, 0.0025, 0.05))
	sp.call("placa_100x100", "cobre", Vector3(-0.2, 0.0075, -0.08), Vector3(0, 0.3, 0))
	main.wires = [
		{"uid": "d1", "a_key": main._key(bat.uid, "V+"), "b_key": main._key(mcu.uid, "5V"), "tipo": "power", "color": "auto", "soldado_b": true},
		{"uid": "d2", "a_key": main._key(bat.uid, "GND"), "b_key": main._key(mcu.uid, "GND"), "tipo": "gnd", "color": "auto", "soldado_b": true},
		{"uid": "d3", "a_key": main._key(mcu.uid, "D1"), "b_key": main._key(led.uid, "anodo"), "tipo": "signal", "color": "amarillo"},
		{"uid": "d4", "a_key": main._key(led.uid, "catodo"), "b_key": main._key(mcu.uid, "D2"), "tipo": "gnd", "color": "verde"},
	]
	main._redraw_wires()
	main._update_counts()
	for p in [main.biblioteca_panel, main.propiedades_panel, main.uniones_panel, main.circuito_panel, main.mcu_panel]:
		if p: p.visible = false
	if show_gizmo:
		var sel: PartInstance = main._find_part(mcu.uid)
		main._select(sel)
	else:
		main._select(null)
	var cam: CameraOrbit = main.camera
	cam.target = Vector3(0.0, 0.06, 0.03)
	cam.distance = 0.52
	cam._yaw = deg_to_rad(-28)
	cam._pitch = deg_to_rad(-24)
	if close:
		cam.target = Vector3(0.07, 0.02, 0.085)
		cam.distance = 0.2
		cam._yaw = deg_to_rad(-150)
		cam._pitch = deg_to_rad(-38)
	cam._update_transform()
	MaterialLibrary.wait_textures()
	await get_tree().create_timer(3.5).timeout
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_path)
	print("[SHOT11] Guardado en %s" % ProjectSettings.globalize_path(out_path))
	get_tree().quit()

## Captura de la plantilla del carro seguidor de línea en marcha.
func _template_shot(out_path: String) -> void:
	main._tpl_seguidor()
	for p in [main.biblioteca_panel, main.propiedades_panel, main.uniones_panel, main.circuito_panel]:
		if p: p.visible = false
	main.mcu_panel.set_collapsed(false)
	var cam: CameraOrbit = main.camera
	cam.target = Vector3(-0.2, 0.0, -0.1)
	cam.distance = 0.9
	cam._yaw = deg_to_rad(-60)
	cam._pitch = deg_to_rad(-35)
	cam._update_transform()
	main._toggle_simulation()
	MaterialLibrary.wait_textures()
	await get_tree().create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_path)
	print("[SHOT11] Guardado en %s" % ProjectSettings.globalize_path(out_path))
	get_tree().quit()

## Abre un proyecto de ejemplo desde su archivo, lo simula 3 s y captura.
func _example_shot(path: String, out_path: String) -> void:
	main._open_example(path)
	for p in [main.biblioteca_panel, main.propiedades_panel, main.uniones_panel, main.circuito_panel]:
		if p: p.visible = false
	if "cerca" in OS.get_cmdline_user_args():
		main.camera.distance *= 0.35
		main.camera._pitch = deg_to_rad(-50)
		main.camera._update_transform()
		for p in [main.mcu_panel, main.elec_panel]:
			if p: p.visible = false
		main.set_process(true)
	main._toggle_simulation()
	MaterialLibrary.wait_textures()
	await get_tree().create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_path)
	print("[SHOT11] Guardado en %s" % ProjectSettings.globalize_path(out_path))
	get_tree().quit()

## Vista amplia de la cochera con el robot evita-obstáculos en marcha.
##   "cochera" (hacia el portón) o "cochera_fondo" (hacia el banco de trabajo).
func _garage_shot(out_path: String, which: String) -> void:
	main._open_example("res://templates/03_evita_obstaculos.mforge")
	main.work_env.set_mode(WorkEnvironment.Mode.COCHERA)
	for p in [main.biblioteca_panel, main.propiedades_panel, main.uniones_panel, main.circuito_panel, main.mcu_panel, main.elec_panel]:
		if p: p.visible = false
	var cam: CameraOrbit = main.camera
	cam.target = Vector3(0, 0.4, -0.3)
	cam.distance = 3.2
	cam._yaw = deg_to_rad(180.0 if which == "cochera" else 20.0)
	cam._pitch = deg_to_rad(-14)
	cam._update_transform()
	main._toggle_simulation()
	MaterialLibrary.wait_textures()
	await get_tree().create_timer(4.0).timeout
	await RenderingServer.frame_post_draw
	for p in [main.elec_panel, main.mcu_panel]:
		if p: p.visible = false
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_path)
	print("[SHOT11] Guardado en %s" % ProjectSettings.globalize_path(out_path))
	get_tree().quit()

## Capturas de la electrónica nueva: multímetro, integrados DIP y cortocircuito.
## Fase 0 del visor VR: carcasa importada impresa en PLA (malla estanca con hueco),
## placas de PETG y cartón, IMU y microcontrolador; panel de propiedades de la carcasa.
func _vr0_shot(out_path: String) -> void:
	main._on_new()
	var vt: Node = load("res://tests/VrTests.gd").new()
	var def: Dictionary = vt._import("visor_carcasa", vt._cup(0.16, 0.08, 0.09, 0.003))
	vt.free()
	main._spawn("placa_base_200x200", "carton", Vector3(0, 0.004, 0))
	var shell: PartInstance = main._spawn(def["id"], "pla", Vector3(-0.02, 0.048, 0))
	main._spawn("placa_100x100", "petg", Vector3(0.12, 0.0105, 0.09), Vector3(0, 0.4, 0))
	main._spawn("imu", "abs", Vector3(0.1, 0.013, -0.06))
	main._spawn("microcontrolador", "abs", Vector3(0.17, 0.015, -0.02))
	for p in [main.biblioteca_panel, main.uniones_panel, main.circuito_panel, main.mcu_panel, main.music_panel, main.ai_panel, main.graphics_panel]:
		if p: p.visible = false
	main._update_counts()
	main._select(shell)
	var cam: CameraOrbit = main.camera
	cam.target = Vector3(0.03, 0.04, 0.0); cam.distance = 0.55
	cam._yaw = deg_to_rad(-25); cam._pitch = deg_to_rad(-32)
	cam._update_transform()
	MaterialLibrary.wait_textures()
	await get_tree().create_timer(2.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_path)
	print("[SHOT11] Guardado en %s" % ProjectSettings.globalize_path(out_path))
	get_tree().quit()

## Fase 1 del visor VR: el ejemplo «Gafas VR caseras» con una lente seleccionada
## (óptica en el panel de propiedades) y la pantalla encendida con la carta de ajuste.
func _vr1_shot(out_path: String) -> void:
	main._open_example("res://templates/12_gafas_vr.mforge")
	await get_tree().process_frame
	for p in [main.biblioteca_panel, main.uniones_panel, main.circuito_panel, main.mcu_panel, main.music_panel, main.ai_panel, main.graphics_panel]:
		if p: p.visible = false
	main.circuit_rt.solve_once()
	main.circuit_rt.step(0.01)
	for c in main.parts_root.get_children():
		if c is PartInstance and (c as PartInstance).def_id == "lente_cardboard_37":
			main._select(c)
			break
	main.connections_root.visible = false
	main.gizmo.attach(null)
	# Panel de propiedades más alto y desplazado hasta la óptica del visor.
	var scroll: ScrollContainer = main.prop_container.get_parent()
	scroll.custom_minimum_size = Vector2(276, 760)
	await get_tree().process_frame
	await get_tree().process_frame
	for n in main.prop_container.get_children():
		if n is Label and str((n as Label).text).begins_with("Óptica"):
			scroll.scroll_vertical = int((n as Control).position.y) - 230
	MaterialLibrary.wait_textures()
	await get_tree().create_timer(2.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_path)
	print("[SHOT11] Guardado en %s" % ProjectSettings.globalize_path(out_path))
	get_tree().quit()

## Fase 2: simulando las gafas, con piezas delante y la «Vista del visor» abierta.
func _vr2_shot(out_path: String) -> void:
	main._open_example("res://templates/12_gafas_vr.mforge")
	await get_tree().process_frame
	for p in [main.biblioteca_panel, main.propiedades_panel, main.uniones_panel, main.circuito_panel, main.mcu_panel, main.music_panel, main.ai_panel, main.graphics_panel]:
		if p: p.visible = false
	var props := [
		main._spawn("perfil_2020_200", "aluminio_anodizado", Vector3(0.30, 0.1, -0.09)),
		main._spawn("perfil_2020_200", "aluminio", Vector3(0.36, 0.1, 0.1)),
		main._spawn("engranaje_m1_z40", "cobre", Vector3(0.24, 0.045, 0.0), Vector3(0, 0, PI / 2.0)),
		main._spawn("motor_dc", "acero", Vector3(0.17, 0.02, 0.07)),
		main._spawn("rueda_65", "abs", Vector3(0.2, 0.033, -0.07), Vector3(PI / 2.0, 0, 0)),
		main._spawn("placa_100x100", "fibra_carbono", Vector3(0.42, 0.0025, 0.0)),
	]
	for q in props:
		(q as PartInstance).anchored = true
	main._update_counts()
	main.connections_root.visible = false
	main._select(null)
	main.gizmo.attach(null)
	main._toggle_simulation()
	if main.elec_panel: main.elec_panel.visible = false
	main._toggle_visor_panel()
	var vs := get_viewport().get_visible_rect().size
	main.visor_panel.position = Vector2(vs.x - 600.0, main.topbar_bottom() + 8.0)
	var cam: CameraOrbit = main.camera
	cam.target = Vector3(0.06, 0.05, 0.0)
	cam.distance = 0.4
	cam._yaw = deg_to_rad(74)
	cam._pitch = deg_to_rad(-14)
	cam._update_transform()
	MaterialLibrary.wait_textures()
	await get_tree().create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_path)
	print("[SHOT11] Guardado en %s" % ProjectSettings.globalize_path(out_path))
	get_tree().quit()

## Fase 3: la cabeza de prueba en marcha, con piezas delante de las gafas y la «Vista
## del visor» en modo IMU con la gráfica de la guiñada real frente a la estimada.
func _vr3_shot(out_path: String) -> void:
	main._open_example("res://templates/13_visor_cabeza.mforge")
	await get_tree().process_frame
	for p in [main.biblioteca_panel, main.propiedades_panel, main.uniones_panel, main.circuito_panel, main.mcu_panel, main.music_panel, main.ai_panel, main.graphics_panel]:
		if p: p.visible = false
	var props := [
		main._spawn("perfil_2020_400", "aluminio_anodizado", Vector3(0.45, 0.2, -0.13)),
		main._spawn("perfil_2020_400", "aluminio", Vector3(0.55, 0.2, 0.16)),
		main._spawn("engranaje_m1_z40", "cobre", Vector3(0.36, 0.46, 0.0), Vector3(0, 0, PI / 2.0)),
		main._spawn("rueda_65", "abs", Vector3(0.42, 0.37, 0.11), Vector3(PI / 2.0, 0, 0)),
		main._spawn("motor_dc", "acero", Vector3(0.4, 0.53, -0.07)),
	]
	for q in props:
		(q as PartInstance).anchored = true
	main._update_counts()
	main.connections_root.visible = false
	main._select(null)
	main.gizmo.attach(null)
	main._toggle_simulation()
	if main.elec_panel: main.elec_panel.visible = false
	main._toggle_visor_panel()
	main.headset_rig.graph_axis = 2
	main.visor_axis_opt.select(2)
	var vs := get_viewport().get_visible_rect().size
	main.visor_panel.position = Vector2(vs.x - 600.0, main.topbar_bottom() + 8.0)
	var cam: CameraOrbit = main.camera
	cam.target = Vector3(0.1, 0.36, 0.12)
	cam.distance = 1.0
	cam._yaw = deg_to_rad(-128)
	cam._pitch = deg_to_rad(-12)
	cam._update_transform()
	MaterialLibrary.wait_textures()
	await get_tree().create_timer(9.0).timeout
	main._clear_joint_indicator()
	main.headset_rig.update_tracking_ui()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_path)
	print("[SHOT11] Guardado en %s" % ProjectSettings.globalize_path(out_path))
	get_tree().quit()

func _electronics_shot(out_path: String, which: String) -> void:
	for p in [main.biblioteca_panel, main.propiedades_panel, main.uniones_panel, main.mcu_panel, main.elec_panel]:
		if p: p.visible = false
	var cam: CameraOrbit = main.camera
	match which:
		"multimetro", "dmmcerca":
			main._open_example("res://templates/10_multimetro.mforge")
			if which == "dmmcerca":
				cam.target = Vector3(0.0, 0.02, 0.1); cam.distance = 0.24
				cam._yaw = deg_to_rad(-5); cam._pitch = deg_to_rad(-62)
				main.dmm_panel.visible = false
				main.circuito_panel.visible = false
			else:
				main.circuito_panel.visible = false
			cam._update_transform()
		"arduino":
			main._open_example("res://templates/11_arduino_555.mforge")
			main.circuito_panel.visible = false
			main._toggle_simulation()
		"dip":
			main._open_example("res://templates/11_arduino_555.mforge")
			main.circuito_panel.visible = false
			main.dmm_panel.visible = false
			cam.target = Vector3(0.02, 0.008, 0.0); cam.distance = 0.16
			cam._yaw = deg_to_rad(-30); cam._pitch = deg_to_rad(-35)
			cam._update_transform()
		"corto":
			main._on_new()
			main.circuito_panel.visible = false
			var pb: PartInstance = main._spawn("protoboard", "abs", Vector3(0, 0.0045, 0))
			var bat: PartInstance = main._spawn("bateria_9v", "acero", Vector3(-0.03, 0.00875, -0.07), Vector3(0, PI / 2.0, 0))
			main.wires = [
				{"uid": "s1", "a_key": main._key(bat.uid, "V+"), "b_key": main._key(pb.uid, "P1_4"), "tipo": "power", "color": "auto"},
				{"uid": "s2", "a_key": main._key(bat.uid, "GND"), "b_key": main._key(pb.uid, "N1_3"), "tipo": "gnd", "color": "auto"},
				{"uid": "s3", "a_key": main._key(pb.uid, "P1_12"), "b_key": main._key(pb.uid, "N1_34"), "tipo": "signal", "color": "amarillo"},
			]
			main._redraw_wires()
			cam.target = Vector3(-0.02, 0.01, -0.01); cam.distance = 0.2
			cam._yaw = deg_to_rad(-20); cam._pitch = deg_to_rad(-38)
			cam._update_transform()
		"fusible":
			main._open_example("res://templates/10_multimetro.mforge")
			main.circuito_panel.visible = false
			var d: DMMController = main.circuit_rt.dmm
			await get_tree().create_timer(0.3).timeout
			d.set_mode(DMMController.Mode.A_DC)
			var bat2: PartInstance = main._find_part_by_def("bateria_9v")
			d.set_probe("roja", main._key(bat2.uid, "V+"))
			d.set_probe("negra", main._key(bat2.uid, "GND"))
			cam.target = Vector3(-0.03, 0.01, -0.02); cam.distance = 0.3
			cam._yaw = deg_to_rad(-15); cam._pitch = deg_to_rad(-42)
			cam._update_transform()
	MaterialLibrary.wait_textures()
	var wait := 2.45 if which == "corto" else (0.35 if which == "fusible" else 3.0)
	await get_tree().create_timer(wait).timeout
	main._update_dmm_ui()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_path)
	print("[SHOT11] Guardado en %s" % ProjectSettings.globalize_path(out_path))
	get_tree().quit()
