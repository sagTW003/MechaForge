extends Node
## MultimetroTests — Circuito vivo (LED = diodo), protoboard multipín (DIP),
## multímetro digital con sondas, cortocircuitos y protecciones.
##   Godot --headless --path project -- mfmulti

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

func rt() -> CircuitRuntime:
	return main.circuit_rt

func steps(n: int, dt: float = 1.0 / 60.0) -> void:
	for i in range(n):
		rt().step(dt)

func run() -> void:
	print("[TEST] Multímetro, protoboard multipín y cortocircuitos...")
	rt().enabled = false            # el test avanza el circuito a mano (determinista)
	_test_lcd()
	_test_insertion()
	_test_dip()
	_test_led_circuit()
	_test_dmm_voltage()
	_test_dmm_ohm_cont()
	_test_dmm_current_and_fuse()
	await _test_parent_child()
	await _test_short_circuit()
	_test_led_burn()
	_test_555()
	await _test_simulation()
	_test_save_load()
	rt().enabled = true
	main._on_new()
	print("[TEST] Multímetro: %d OK, %d FALLOS" % [ok, fail])
	get_tree().quit(1 if fail > 0 else 0)

# --- utilidades ---------------------------------------------------------------

func _pb() -> PartInstance:
	return main._spawn("protoboard", "abs", Vector3(0, 0.0045, 0))

## Coloca una pieza sobre la protoboard con su centro en la columna/fila dadas
## (en mm locales de la placa) y la inserta (snap real).
func _insert(def_id: String, pb: PartInstance, x_mm: float, z_mm: float, yaw := 0.0) -> PartInstance:
	var def := PartLibrary.get_def(def_id)
	var dm := PartLibrary.dims_m(def)
	var p: PartInstance = main._spawn(def_id, "abs", pb.global_transform * Vector3(x_mm / 1000.0, 0.0045 + dm.y * 0.5 + 0.001, z_mm / 1000.0), Vector3(0, yaw, 0))
	var r := BreadboardSnap.try_insert(p.def, p.global_transform, pb)
	if r.get("ok", false):
		p.global_transform = r["xf"]
	main._refresh_insertion(p)
	return p

func _col(c: int) -> float:
	return PartInstance.bb_column_x(c)

func _k(p: PartInstance, t: String) -> String:
	return main._key(p.uid, t)

## Circuito de prueba: batería 9 V → riel + → puente a col. 10 → R 470 Ω (10–14)
## → LED (ánodo col. 14, cátodo col. 15) → puente al riel −.
func _circuit() -> Dictionary:
	main._on_new()
	var pb := _pb()
	var bat: PartInstance = main._spawn("bateria_9v", "acero", Vector3(-0.02, 0.00875, -0.07))
	var res := _insert("resistencia_470", pb, (_col(10) + _col(14)) * 0.5, PartInstance.bb_row_z(true, 2))
	var led := _insert("led", pb, (_col(14) + _col(15)) * 0.5, PartInstance.bb_row_z(true, 1), PI)
	main.wires = [
		{"uid": "w_vp", "a_key": _k(bat, "V+"), "b_key": _k(pb, "P1_3"), "tipo": "power", "color": "auto"},
		{"uid": "w_gn", "a_key": _k(bat, "GND"), "b_key": _k(pb, "N1_2"), "tipo": "gnd", "color": "auto"},
		{"uid": "w_j1", "a_key": _k(pb, "P1_8"), "b_key": _k(pb, "a10_4"), "tipo": "power", "color": "rojo"},
		{"uid": "w_j2", "a_key": _k(pb, "a15_4"), "b_key": _k(pb, "N1_12"), "tipo": "gnd", "color": "negro"},
	]
	main._redraw_wires()
	rt().invalidate()
	return {"pb": pb, "bat": bat, "res": res, "led": led}

# --- pruebas ------------------------------------------------------------------

func _test_lcd() -> void:
	var e := DMMController.lcd_encode("OL")
	check(e["seg"] == [0, 0, 63, 56], "LCD: «OL» con segmentos de 7 (O = abcdef, L = def)")
	var f := DMMController.lcd_encode("FUSE")
	check(f["seg"] == [113, 62, 109, 121], "LCD: «FUSE» cabe en los 4 dígitos")
	var n := DMMController.lcd_encode("-1.953")
	check(n["minus"] and n["dp"] == 1 and n["seg"] == [6, 111, 109, 79], "LCD: signo menos y punto decimal (-1.953)")
	check(DMMController.lcd_encode("Err")["seg"] == [0, 121, 80, 80], "LCD: «Err»")

func _test_insertion() -> void:
	var c := _circuit()
	var res: PartInstance = c["res"]
	var led: PartInstance = c["led"]
	check(res.is_inserted() and res.pin_map.size() == 2, "Resistencia insertada: sus 2 patas en agujeros (%s)" % BreadboardSnap.describe(res.pin_map))
	check(str(res.pin_map.get("A", "")) == "a14_2" and str(res.pin_map.get("B", "")) == "a10_2", "Patas de la resistencia en c11 y c15 (columnas 10 y 14): %s" % str(res.pin_map))
	check(led.is_inserted() and str(led.pin_map.get("anodo", "")) == "a14_1" and str(led.pin_map.get("catodo", "")) == "a15_1", "LED insertado girado 180°: ánodo en col. 14, cátodo en col. 15")
	# Una pata entre dos agujeros atrae a la pieza al agujero más cercano (snap).
	var pb: PartInstance = c["pb"]
	var def := PartLibrary.get_def("resistencia_1k")
	var xf := pb.global_transform * Transform3D(Basis.IDENTITY, Vector3((_col(40) + 1.1) / 1000.0, 0.0045 + 0.004, PartInstance.bb_row_z(false, 3) / 1000.0))
	var r := BreadboardSnap.try_insert(def, xf, pb)
	check(r.get("ok", false) and absf((pb.global_transform.affine_inverse() * (r["xf"] as Transform3D)).origin.x * 1000.0 - _col(40)) < 0.01,
		"Snap magnético: 1.1 mm fuera de rejilla → centrada en la columna exacta")
	# Dos patas en la misma tira = componente cortocircuitado (aviso).
	var xf2 := pb.global_transform * Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(_col(50) / 1000.0, 0.008, PartInstance.bb_row_z(true, 2) / 1000.0))
	var r2 := BreadboardSnap.try_insert(PartLibrary.get_def("led"), xf2, pb)
	check(r2.get("ok", false) and r2.get("short", false), "LED con las dos patas en la misma columna: se detecta el cortocircuito")
	check(not (BreadboardSnap.try_insert(def, Transform3D(Basis.IDENTITY, Vector3(0.5, 0.01, 0.5)), pb).get("near", true)), "Lejos de la placa no hay inserción")
	# Un puente largo apoya SOBRE la protoboard (antes podía atravesarla y quedar oculto).
	main.wires = [{"uid": "largo", "a_key": _k(pb, "P1_12"), "b_key": _k(pb, "N2_24"), "tipo": "signal", "color": "amarillo"}]
	main._redraw_wires()
	var pts: PackedVector3Array = main._wire_pts["largo"]
	var top := pb.global_position.y + 0.0045
	var lowest := INF
	for q in pts:
		lowest = minf(lowest, q.y)
	check(lowest >= top - 0.0001, "Puente largo de riel a riel: el cable apoya sobre la placa (mín. %.1f mm, superficie %.1f mm)" % [lowest * 1000.0, top * 1000.0])
	main.wires = []

func _test_dip() -> void:
	main._on_new()
	var pb := _pb()
	var ic := _insert("ne555", pb, (_col(20) + _col(23)) * 0.5, 0.0)
	check(ic.is_inserted() and ic.pin_map.size() == 8, "NE555 (DIP-8) insertado cruzando el canal central")
	var halves := {}
	for pin in ic.pin_map:
		halves[str(ic.pin_map[pin]).substr(0, 1)] = true
	check(halves.has("a") and halves.has("b"), "  una fila de patas en a–e y la otra en f–j")
	check(str(ic.pin_map["GND"]).begins_with("b") or str(ic.pin_map["GND"]).begins_with("a"), "  cada pata tiene su agujero (GND → %s)" % BreadboardSnap.hole_name(str(ic.pin_map["GND"])))
	# Sin cruzar el canal: no se inserta y se explica por qué.
	var def := PartLibrary.get_def("ne555")
	var xf := pb.global_transform * Transform3D(Basis.IDENTITY, Vector3((_col(40) + _col(43)) * 0.5 / 1000.0, 0.0045 + 0.0035, PartInstance.bb_row_z(true, 2) / 1000.0 - 0.00127))
	var r := BreadboardSnap.try_insert(def, xf, pb)
	check(not r.get("ok", true) and str(r.get("reason", "")).contains("canal central"), "DIP que no cruza el canal: rechazado («%s»)" % r.get("reason", ""))
	# Girado 90° (patas a lo largo de las columnas): tampoco.
	var xf2 := pb.global_transform * Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(_col(30) / 1000.0, 0.008, 0.0))
	check(not BreadboardSnap.try_insert(def, xf2, pb).get("ok", true), "DIP girado 90° sobre el canal: rechazado")
	# Arduino Nano (DIP-30, 0.6"): filas asimétricas respecto del canal.
	var nano := _insert("arduino_nano", pb, _col(46), -1.27)
	check(nano.is_inserted() and nano.pin_map.size() == 30, "Arduino Nano (DIP-30) insertado: 30 patas en agujeros")
	var rows := {}
	for pin in nano.pin_map:
		var h := BreadboardSnap.hole_name(str(nano.pin_map[pin]))
		rows[h.substr(0, 1)] = true
	check(rows.size() == 2 and not rows.has("e") and not rows.has("f"), "  Nano en filas %s (0.6″ = 15.24 mm: asimétrico)" % str(rows.keys()))

func _test_led_circuit() -> void:
	var c := _circuit()
	var r := rt().solve_once()
	check(r.get("ok", false), "Circuito vivo resuelto por Newton-Raphson (%d iteraciones)" % int(r.get("iters", 0)))
	var led: PartInstance = c["led"]
	var i := rt().led_current(led.uid)
	var vled := rt().voltage(_k(led, "anodo")) - rt().voltage(_k(led, "catodo"))
	check(i > 0.013 and i < 0.017, "LED con 470 Ω a 9 V: I = %.2f mA (≈ (9 − 1.9)/470)" % (i * 1000.0))
	check(vled > 1.8 and vled < 2.05, "Tensión directa del LED rojo: %.3f V (diodo real, no resistencia)" % vled)
	steps(2)
	check(float(rt().led_level.get(led.uid, 0.0)) > 0.6, "El LED se ilumina según su corriente (brillo %.2f)" % float(rt().led_level.get(led.uid, 0.0)))
	# Sin cables no hay corriente.
	main.wires = []
	rt().solve_once()
	check(absf(rt().led_current(led.uid)) < 1e-6, "Sin cables: circuito abierto, LED apagado")

func _dmm(red: String, black: String, mode: int) -> DMMController:
	var d: PartInstance = main._find_part_by_def("multimetro")
	if d == null:
		d = main._spawn("multimetro", "abs", Vector3(0.18, 0.018, 0.0))
	rt()._sync_dmm()
	var m := rt().dmm
	m.set_mode(mode)
	m.set_probe("roja", red)
	m.set_probe("negra", black)
	steps(3)
	return m

func _test_dmm_voltage() -> void:
	var c := _circuit()
	var pb: PartInstance = c["pb"]
	var led: PartInstance = c["led"]
	# Sondas en los agujeros de las columnas del LED (fila e), no en sus patas.
	var m := _dmm(_k(pb, "a14_0"), _k(pb, "a15_0"), DMMController.Mode.V_DC)
	var vled := rt().voltage(_k(led, "anodo")) - rt().voltage(_k(led, "catodo"))
	check(absf(m.value - vled) < 0.002 and m.unit == "V", "V⎓ sobre el LED: %s (solver %.3f V)" % [m.reading_text(), vled])
	m.set_probe("roja", _k(pb, "a10_0"))
	m.set_probe("negra", _k(pb, "a14_0"))
	steps(2)
	var vr := m.value
	var i := rt().led_current(led.uid)
	check(absf(vr - i * 470.0) < 0.01, "Caída en la resistencia: %s = I·R (%.3f V)" % [m.reading_text(), i * 470.0])
	# Sondas invertidas: lectura negativa.
	m.set_probe("roja", _k(pb, "a14_0"))
	m.set_probe("negra", _k(pb, "a10_0"))
	steps(2)
	check(m.value < 0.0 and m.display.begins_with("-"), "Sondas invertidas: %s" % m.reading_text())
	# El voltímetro no altera el circuito (10 MΩ).
	check(absf(rt().led_current(led.uid) - i) < 1e-6, "El voltímetro (10 MΩ) no altera la corriente del circuito")
	# V~ en continua: ~0.
	m.set_mode(DMMController.Mode.V_AC)
	steps(10)
	check(absf(m.value) < 0.01, "V~ en un circuito de continua: %s" % m.reading_text())

func _test_dmm_ohm_cont() -> void:
	var c := _circuit()
	var pb: PartInstance = c["pb"]
	var m := _dmm(_k(pb, "a10_0"), _k(pb, "a14_0"), DMMController.Mode.OHM)
	check(m.display == "Err", "Ω con el circuito energizado: la pantalla muestra «Err»")
	rt().power_on = false
	steps(2)
	# La resistencia está en paralelo con: puente→riel+→batería (abierta sin fuente)... solo R.
	check(absf(m.value - 470.0) < 1.0 and m.display == "470.0", "Ω desenergizado: %s (resistencia de 470 Ω)" % m.reading_text())
	m.set_probe("roja", _k(pb, "P1_20"))
	m.set_probe("negra", _k(pb, "P1_40"))
	m.set_mode(DMMController.Mode.CONT)
	steps(2)
	check(m.beeping and m.value < 1.0, "Continuidad del riel +: pita (%.2f Ω < 50 Ω)" % m.value)
	m.set_probe("negra", _k(pb, "N1_40"))
	steps(2)
	check(not m.beeping and m.display == "OL", "Riel + contra riel −: sin continuidad («OL»)")
	m.set_probe("roja", _k(pb, "a10_0"))
	m.set_probe("negra", _k(pb, "a14_0"))
	steps(2)
	check(not m.beeping, "A través de 470 Ω no pita (umbral 50 Ω)")
	rt().power_on = true

func _test_dmm_current_and_fuse() -> void:
	var c := _circuit()
	var pb: PartInstance = c["pb"]
	var led: PartInstance = c["led"]
	# Abrir el circuito: se quita el puente del cátodo y se intercalan las sondas.
	main.wires.remove_at(3)
	var m := _dmm(_k(pb, "a15_0"), _k(pb, "N1_20"), DMMController.Mode.A_DC)
	var i := rt().led_current(led.uid)
	check(m.unit == "mA" and absf(m.value - i) < 1e-5 and i > 0.012, "A⎓ en SERIE: %s (corriente del LED %.2f mA)" % [m.reading_text(), i * 1000.0])
	check(m.fuse_ok, "  el fusible sigue intacto")
	# Error clásico: amperímetro en PARALELO con la batería.
	var bat: PartInstance = c["bat"]
	m.set_probe("roja", _k(bat, "V+"))
	m.set_probe("negra", _k(bat, "GND"))
	var sparks_before := _count_fx("Chispas")
	steps(4)
	check(not m.fuse_ma_ok and m.display == "FUSE", "Amperímetro en paralelo con la fuente: fusible de 400 mA FUNDIDO («%s»)" % m.display)
	check(_count_fx("Chispas") > sparks_before, "  chispas en las puntas de prueba")
	check(bool(m.part.estado.get("fusible", true)) == false, "  el fusible fundido queda guardado en el multímetro")
	m.replace_fuse()
	m.set_probe("roja", _k(pb, "a15_0"))
	m.set_probe("negra", _k(pb, "N1_20"))
	steps(2)
	check(m.fuse_ok and m.unit == "mA" and m.value > 0.012, "Fusible reemplazado: vuelve a medir %s" % m.reading_text())
	# API para OpenClaw: estado del circuito y medida de solo lectura.
	var st: Dictionary = main.tool_server.api.call_tool("get_circuit_state", {})
	check(st["leds"].size() == 1 and st["insertados"].size() == 2 and st["multimetro"]["modo"] == "A_DC", "API get_circuit_state: LED, piezas insertadas y multímetro")
	var mv: Dictionary = main.tool_server.api.call_tool("measure_voltage", {"a": _k(pb, "a10_0"), "b": _k(pb, "a14_0")})
	check(absf(float(mv.get("tension_v", 0.0)) - 470.0 * i) < 0.02, "API measure_voltage (solo lectura): %.3f V en la resistencia" % float(mv.get("tension_v", 0.0)))
	# Borne 10 A: aguanta los ~5 A del cortocircuito de una pila de 9 V.
	m.set_jack_10a(true)
	m.set_probe("roja", _k(bat, "V+"))
	m.set_probe("negra", _k(bat, "GND"))
	steps(3)
	check(m.fuse_10a_ok and m.unit == "A" and m.value > 4.0, "Borne 10 A contra la pila de 9 V: %s sin fundir (límite de la pila)" % m.reading_text())
	m.set_jack_10a(false)
	m.set_probe("roja", "")
	m.set_probe("negra", "")
	rt().rearm()

func _count_fx(prefix: String) -> int:
	var n := 0
	for ch in rt().fx.get_children():
		if str(ch.name).begins_with(prefix):
			n += 1
	return n

func _test_parent_child() -> void:
	var c := _circuit()
	var pb: PartInstance = c["pb"]
	var res: PartInstance = c["res"]
	var m := _dmm(_k(pb, "a14_0"), _k(pb, "a15_0"), DMMController.Mode.V_DC)
	main._refresh_all_insertions()
	var rel := pb.global_transform.affine_inverse() * res.global_transform
	# Mover y girar la protoboard (como con el gizmo).
	pb.global_transform = Transform3D(Basis(Vector3.UP, 0.6), Vector3(0.05, 0.0045, 0.03))
	await get_tree().process_frame
	await get_tree().process_frame
	var rel2 := pb.global_transform.affine_inverse() * res.global_transform
	check(rel2.origin.distance_to(rel.origin) < 1e-5 and res.is_inserted(), "Jerarquía padre-hijo: al mover y girar la protoboard, la resistencia la sigue rígidamente")
	var hole = main._terminal_live_by_key(_k(pb, "a14_0"))
	check(m.probe_tip("roja").distance_to(hole) < 1e-6, "  la sonda enganchada sigue a su agujero")
	var pose: Transform3D = main.probes.probe_pose("roja")
	check(pose.basis.y.normalized().y > 0.95, "  sonda a 90° (vertical) en un agujero de la protoboard")
	m.set_probe("roja", _k(c["bat"], "V+"))
	var pose2: Transform3D = main.probes.probe_pose("roja")
	var ang := rad_to_deg(acos(clampf(pose2.basis.y.normalized().y, -1, 1)))
	check(absf(ang - 45.0) < 3.0, "  sonda a 45° sobre el borne de la batería (%.0f°)" % ang)
	# Arrastrar el componente fuera lo desenchufa; deshacer lo vuelve a insertar.
	var before := res.global_transform
	res.global_position += Vector3(0.0, 0.02, 0.03)
	main._refresh_insertion(res)
	check(not res.is_inserted(), "Retirado de la protoboard: ya no está insertado")
	res.global_transform = before
	main._refresh_insertion(res)
	check(res.is_inserted(), "De vuelta a sus agujeros: insertado otra vez (estado derivado de la geometría)")

func _test_short_circuit() -> void:
	main._on_new()
	var bat: PartInstance = main._spawn("bateria_lipo_3s", "abs", Vector3(0, 0.0125, 0))
	main.wires = [{"uid": "w_sc", "a_key": _k(bat, "V+"), "b_key": _k(bat, "GND"), "tipo": "power", "color": "rojo"}]
	main._redraw_wires()
	rt().invalidate()
	steps(1)
	check(rt().short_active or rt().tripped.has(bat.uid), "Cable directo V+ → GND: CORTOCIRCUITO CRÍTICO detectado (%.0f A)" % float(rt().short_info.get("current", 0.0)))
	check(_count_fx("Chispas") > 0, "  chispas 3D (partículas GPU) al cerrar el cortocircuito")
	check(float(rt().wire_temp.get("w_sc", 0.0)) > CircuitRuntime.T_GLOW, "  el cable se calienta al rojo (%.0f °C)" % float(rt().wire_temp.get("w_sc", 0.0)))
	var node: Node3D = main._wire_nodes.get("w_sc")
	var tube := node.get_child(0) as MeshInstance3D if node else null
	check(tube != null and tube.material_override is ShaderMaterial, "  shader de incandescencia aplicado al cable")
	steps(3)
	check(rt().tripped.has(bat.uid), "  protección térmica: la batería queda DESCONECTADA")
	check(rt().fx.smoking_count() > 0, "  humo saliendo del aislamiento recalentado")
	check(absf(rt().totals()["current"]) < 1e-6, "  tras desconectar no circula corriente")
	await get_tree().process_frame
	main._update_dmm_ui()
	check(main.short_banner.visible and main.short_banner_label.text.contains("protección"), "  aviso rojo en pantalla con botón «Rearmar»")
	steps(240, 1.0 / 30.0)
	check(float(rt().wire_temp.get("w_sc", 999.0)) < 150.0, "  el cable se enfría al quedar sin corriente (%.0f °C)" % float(rt().wire_temp.get("w_sc", 0.0)))
	# Con una pila de 9 V (resistencia interna 1.7 Ω) tarda más en dispararse.
	main._on_new()
	var b9: PartInstance = main._spawn("bateria_9v", "acero", Vector3(0, 0.00875, 0))
	main.wires = [{"uid": "w9", "a_key": _k(b9, "V+"), "b_key": _k(b9, "GND"), "tipo": "power", "color": "rojo"}]
	main._redraw_wires()
	rt().invalidate()
	steps(30)
	check(rt().short_active and not rt().tripped.has(b9.uid) and absf(float(rt().short_info["current"]) - 9.0 / 1.75) < 0.3,
		"Pila de 9 V en cortocircuito: %.2f A limitados por su resistencia interna" % float(rt().short_info.get("current", 0.0)))
	steps(150)
	check(rt().tripped.has(b9.uid), "  desconexión por protección tras el cortocircuito sostenido")
	# Rearmar sin corregir: vuelve a dispararse; corregido: funciona.
	main.wires = []
	main._rearm_circuit()
	steps(2)
	check(rt().tripped.is_empty() and not rt().short_active, "Rearmar tras corregir el cableado: fuente reconectada")

func _test_led_burn() -> void:
	main._on_new()
	var pb := _pb()
	var bat: PartInstance = main._spawn("bateria_9v", "acero", Vector3(-0.02, 0.00875, -0.07))
	var led := _insert("led", pb, (_col(30) + _col(31)) * 0.5, PartInstance.bb_row_z(true, 1), PI)
	main.wires = [
		{"uid": "b1", "a_key": _k(bat, "V+"), "b_key": _k(pb, "a30_4"), "tipo": "power", "color": "auto"},
		{"uid": "b2", "a_key": _k(bat, "GND"), "b_key": _k(pb, "a31_4"), "tipo": "gnd", "color": "auto"},
	]
	rt().invalidate()
	steps(1)
	var i := rt().led_current(led.uid)
	check(i > 0.1, "LED directo a 9 V sin resistencia: %.0f mA (muy por encima de 30 mA)" % (i * 1000.0))
	steps(30)
	check(rt().burned.has(led.uid), "  el LED se QUEMA (queda abierto) con una bocanada de humo")
	check(absf(rt().led_current(led.uid)) < 1e-9, "  LED quemado: ya no conduce")
	main._rearm_circuit()
	check(not rt().burned.has(led.uid), "Rearmar repone el componente quemado")

func _test_555() -> void:
	main._on_new()
	var pb := _pb()
	var bat: PartInstance = main._spawn("bateria_9v", "acero", Vector3(-0.02, 0.00875, -0.07))
	var ic := _insert("ne555", pb, (_col(20) + _col(23)) * 0.5, 0.0)
	var vcc: String = str(ic.pin_map["VCC"])
	var gnd: String = str(ic.pin_map["GND"])
	var out: String = str(ic.pin_map["OUT"])
	main.wires = [
		{"uid": "c1", "a_key": _k(bat, "V+"), "b_key": _k(pb, vcc.substr(0, vcc.length() - 1) + "4"), "tipo": "power", "color": "auto"},
		{"uid": "c2", "a_key": _k(bat, "GND"), "b_key": _k(pb, gnd.substr(0, gnd.length() - 1) + "4"), "tipo": "gnd", "color": "auto"},
	]
	rt().invalidate()
	var highs := 0
	var lows := 0
	for i in range(120):
		rt().step(1.0 / 60.0)
		var v := rt().voltage(_k(pb, out)) - rt().voltage(_k(pb, gnd))
		if v > 5.0: highs += 1
		elif v < 0.5: lows += 1
	check(highs > 40 and lows > 40, "NE555 astable a 1 Hz: la salida conmuta (%d muestras en alto, %d en bajo)" % [highs, lows])

func _test_simulation() -> void:
	var c := _circuit()
	var pb: PartInstance = c["pb"]
	var res: PartInstance = c["res"]
	var led: PartInstance = c["led"]
	var m := _dmm(_k(pb, "a14_0"), _k(pb, "a15_0"), DMMController.Mode.V_DC)
	main.simulator.start([])
	for i in range(30):
		await get_tree().physics_frame
	check(main.simulator.get_body(res.uid) == main.simulator.get_body(pb.uid), "En simulación la resistencia forma un solo cuerpo rígido con su protoboard")
	var lx: Transform3D = main._part_live_xform(res)
	check(lx.origin.distance_to(res.global_transform.origin) < 0.002, "  su transformación en vivo coincide con la de edición (no cae ni tiembla)")
	steps(3)
	check(m.value > 1.8 and m.value < 2.05, "  el multímetro mide también durante la simulación (%s)" % m.reading_text())
	check(float(rt().led_level.get(led.uid, 0.0)) > 0.5, "  y el LED sigue encendido")
	main.simulator.stop()

func _test_save_load() -> void:
	var c := _circuit()
	var pb: PartInstance = c["pb"]
	var m := _dmm(_k(pb, "a14_0"), _k(pb, "a15_0"), DMMController.Mode.OHM)
	m.fuse_ma_ok = false
	m.part.estado["fusible"] = false
	var path := "user://prueba_multimetro.mforge"
	ProjectSerializer.save(main.parts_root, path, main.connections, main.wires, main._project_extra())
	main._on_new()
	main._load_project(path)
	var res: PartInstance = main._find_part(c["res"].uid)
	check(res != null and res.is_inserted() and str(res.pin_map.get("A", "")) == "a14_2", "Guardar/abrir conserva la inserción en la protoboard")
	rt()._sync_dmm()
	var d := rt().dmm
	check(d.mode == DMMController.Mode.OHM and d.probe_key("roja").ends_with("a14_0") and not d.fuse_ma_ok, "  y el estado del multímetro (modo, sondas y fusible)")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
