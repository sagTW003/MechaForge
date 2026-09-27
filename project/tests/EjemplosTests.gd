extends Node
## EjemplosTests — Abre cada proyecto de ejemplo (res://templates) DESDE SU ARCHIVO,
## lo simula y comprueba que funciona.
##   Godot --headless --path project -- mfejemplos

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
	print("[TEST] Proyectos de ejemplo...")
	var list: Array = main._example_projects()
	check(list.size() >= 9, "Menú Ejemplos: %d proyectos encontrados en res://templates" % list.size())
	for e in list:
		var id: String = str(e["ruta"]).get_file().get_basename()
		main._open_example(e["ruta"])
		await get_tree().process_frame
		check(main.parts_root.get_child_count() > 0 and main.project_meta.get("nombre", "") == e["nombre"], "%s: se abre (%d piezas)" % [e["nombre"], main.parts_root.get_child_count()])
		var fn := "_t_" + id.substr(3)
		if has_method(fn):
			await call(fn)
		else:
			await _generic(3.0)
		if main.simulator.is_running():
			main.simulator.stop()
	main._on_new()
	print("[TEST] Ejemplos: %d OK, %d FALLOS" % [ok, fail])
	get_tree().quit(1 if fail > 0 else 0)

func _body(def_id: String) -> RigidBody3D:
	for c in main.parts_root.get_children():
		if c is PartInstance and c.def_id == def_id:
			return main.simulator.get_body(c.uid)
	return null

## Simula "secs" y comprueba que nada explota ni atraviesa el suelo.
func _generic(secs: float) -> void:
	main._toggle_simulation()
	await wait_phys(int(secs * 120))
	var sane := true
	for c in main.parts_root.get_children():
		var b: RigidBody3D = main.simulator.get_body(c.uid)
		if b == null:
			continue
		var p := b.global_position
		if is_nan(p.x) or p.length() > 5.0 or p.y < -0.03 or b.linear_velocity.length() > 20.0:
			sane = false
	check(sane, "  simulación estable %.0f s (sin explosiones ni piezas bajo el suelo)" % secs)

func _t_brazo_4gdl() -> void:
	check(main.mcu_enabled and main.mcu_editor.text.contains("m4"), "  programa del microcontrolador restaurado (m1…m4)")
	await _generic(4.0)
	var worst := 0.0
	for c in main._controlled_connections():
		worst = maxf(worst, absf(rad_to_deg(main.simulator.control_measure(c.uid) - c.ctrl_setpoint)))
	check(worst < 12.0, "  las 4 articulaciones siguen su trayectoria (error máx %.1f°)" % worst)

func _t_seguidor_linea() -> void:
	var b := func() -> Vector3: return _body("placa_chasis_160x120").global_position
	main._toggle_simulation()
	await wait_phys(1)
	var p0: Vector3 = b.call()
	await wait_phys(360)
	var p1: Vector3 = b.call()
	check(Vector2(p1.x - p0.x, p1.z - p0.z).length() > 0.3, "  el carro recorre la pista")

func _t_evita_obstaculos() -> void:
	main._toggle_simulation()
	await wait_phys(1)
	var inside := true
	var travel := 0.0
	var last := _body("placa_chasis_160x120").global_position
	var turned := false
	var good := 0
	for i in range(100):
		await wait_phys(12)
		var p := _body("placa_chasis_160x120").global_position
		travel += Vector2(p.x - last.x, p.z - last.z).length()
		last = p
		if absf(p.x) > 0.47 or absf(p.z) > 0.47:
			inside = false
		if float(main._mcu_sensor_vars.get("dist1", 9.0)) < 0.25:
			turned = true
		var c2: Connection = main._controlled_connections()[1]
		if absf(main.simulator.control_measure(c2.uid) - 6.0) < 1.5:
			good += 1
	check(turned, "  el ultrasonido detecta la pared y el robot gira")
	check(good >= 80, "  la rueda derecha mantiene 6 rad/s aunque el chasis gire (%d/100 muestras)" % good)
	check(inside and travel > 0.5, "  recorre el recinto sin chocar (%.2f m en 10 s)" % travel)

func _t_reductora() -> void:
	main._toggle_simulation()
	await wait_phys(240)
	var w1 := _body("engranaje_m1_z16").angular_velocity.y
	var w2 := _body("engranaje_m1_z60").angular_velocity.y
	check(absf(w1) > 1.0 and absf(w2 / w1 + 16.0 / 60.0) < 0.015, "  relación ω60/ω16 = −16/60 = −0.267 (%.3f)" % (w2 / w1))

func _t_banco_pid() -> void:
	await _generic(4.0)
	var c: Connection = main._controlled_connections()[0]
	var err := absf(rad_to_deg(main.simulator.control_measure(c.uid) - c.ctrl_setpoint))
	check(err < 10.0, "  el PID sigue la onda (error %.1f°)" % err)
	var enc := float(main._mcu_sensor_vars.get("enc1", 999.0))
	var meas := rad_to_deg(main.simulator.control_measure(c.uid))
	check(absf(enc - meas) < 3.0, "  el encoder mide el ángulo del brazo (enc %.1f° / unión %.1f°)" % [enc, meas])

func _t_circuito_led() -> void:
	var pairs := []
	for w in main.wires:
		pairs.append({"a": w["a_key"], "b": w["b_key"]})
	pairs.append_array(main._protoboard_virtual_wires())
	var r: Dictionary = WiringSolver.solve(main._build_components(), pairs)
	check(float(r.get("current", 0.0)) > 0.01, "  el circuito cierra: %.3f A" % float(r.get("current", 0.0)))
	check(main._solder_stats().x == 2, "  dos uniones soldadas en la batería")

func _t_grua() -> void:
	await _generic(4.0)
	var up := _body("perfil_4040_300").global_transform.basis.y
	check(up.y > 0.98, "  la torre no vuelca mientras la pluma gira")

func _t_puente_carga() -> void:
	await _generic(3.0)
	check(_body("viga_acero_500").global_position.y > 0.19, "  el puente sostiene la carga")

## Energía mecánica total de los cuerpos libres (cinética + potencial).
func _energy() -> float:
	var e := 0.0
	for c in main.parts_root.get_children():
		var bb: RigidBody3D = main.simulator.get_body(c.uid)
		if bb and not bb.freeze:
			var st := PhysicsServer3D.body_get_direct_state(bb.get_rid())
			var inertia: Basis = st.inverse_inertia_tensor.inverse()
			e += 0.5 * bb.mass * bb.linear_velocity.length_squared() + 0.5 * bb.angular_velocity.dot(inertia * bb.angular_velocity) + bb.mass * 9.81 * bb.global_position.y
	return e

func _t_pendulo_doble() -> void:
	main._toggle_simulation()
	await wait_phys(2)
	var e0 := _energy()
	var peak := 0.0
	var emax := e0
	for i in range(30):
		await wait_phys(8)
		for c in main.parts_root.get_children():
			if c is PartInstance and c.def_id == "perfil_2020_200" and c.position.x > 0.2:
				peak = maxf(peak, absf(main.simulator.get_body(c.uid).angular_velocity.z))
		emax = maxf(emax, _energy())
	check(peak > 2.0, "  el péndulo oscila (ω pico en el eje %.1f rad/s)" % peak)
	check(emax <= e0 * 1.05, "  la energía no crece (%.3f J → máx %.3f J)" % [e0, emax])
