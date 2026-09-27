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
	if template.begins_with("ej:"):
		await _example_shot("res://templates/%s.mforge" % template.substr(3), out_path)
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
	main._toggle_simulation()
	MaterialLibrary.wait_textures()
	await get_tree().create_timer(3.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_path)
	print("[SHOT11] Guardado en %s" % ProjectSettings.globalize_path(out_path))
	get_tree().quit()
