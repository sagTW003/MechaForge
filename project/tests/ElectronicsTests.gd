extends Node
## ElectronicsTests — Pruebas de electrónica y control (Fase 3): solver, PID, cableado, microcontrolador
## y protoboard.
## Ejecutar:  Godot --headless --path project -- mfelec

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
	print("[TEST] Pruebas de electrónica y control (Fase 3)...")

	# 1) Resistencia única: 12 V / 6 Ω = 2 A, 24 W.
	var r1: Dictionary = Electronics.SolveCircuit(2, [[1, 0, 6.0]], [[1, 0, 12.0]])
	check(r1["ok"], "Solver resuelve circuito simple")
	check(absf(float(r1["main_current"]) - 2.0) < 1.0e-6, "Ley de Ohm: I = 2 A")
	check(absf(float(r1["total_power"]) - 24.0) < 1.0e-6, "Potencia = 24 W")

	# 2) Serie 4 Ω + 8 Ω a 12 V: I = 1 A, nodo medio a 8 V.
	var r2: Dictionary = Electronics.SolveCircuit(3, [[1, 2, 4.0], [2, 0, 8.0]], [[1, 0, 12.0]])
	var volts: PackedFloat64Array = r2["node_voltages"]
	check(absf(float(r2["main_current"]) - 1.0) < 1.0e-6, "Serie: I = 1 A")
	check(absf(volts[2] - 8.0) < 1.0e-6, "Divisor de tensión: nodo medio = 8 V")

	# 3) Paralelo 6 Ω || 12 Ω a 12 V: I = 3 A.
	var r3: Dictionary = Electronics.SolveCircuit(2, [[1, 0, 6.0], [1, 0, 12.0]], [[1, 0, 12.0]])
	check(absf(float(r3["main_current"]) - 3.0) < 1.0e-6, "Paralelo: I = 3 A")

	# 4) Autonomía: 2 A con 2000 mAh = 1 h.
	check(absf(Electronics.Autonomy(2.0, 2000.0) - 1.0) < 1.0e-6, "Autonomía = 1 h")

	# 5) PID converge a la consigna con una planta de primer orden.
	var pid: int = Electronics.PidCreate()
	Electronics.PidConfigure(pid, 2.0, 1.0, 0.05)
	Electronics.PidSetLimits(pid, -10.0, 10.0)
	Electronics.PidSetSetpoint(pid, 5.0)
	var y = 0.0
	var dt = 0.02
	for i in range(600):
		var u: float = Electronics.PidUpdate(pid, y, dt)
		y += (u - 0.5 * y) * dt          # planta: dy/dt = u - 0.5 y
	Electronics.PidDestroy(pid)
	check(absf(y - 5.0) < 0.2, "PID lleva la planta a la consigna (y=%.2f)" % y)

	# 6) Cableado: batería 12 V + carga 6 Ω en lazo => 2 A.
	var comps = [
		{"uid": "bat", "kind": "bateria", "voltaje": 12.0, "capacidad_mah": 2000.0, "a": "bat:V+", "b": "bat:GND"},
		{"uid": "r1", "kind": "carga", "resistencia": 6.0, "a": "r1:A", "b": "r1:B"},
	]
	var wpairs = [{"a": "bat:V+", "b": "r1:A"}, {"a": "r1:B", "b": "bat:GND"}]
	var wr = WiringSolver.solve(comps, wpairs)
	check(wr["ok"] and absf(float(wr["current"]) - 2.0) < 1.0e-4, "Cableado: lazo batería→carga da 2 A")
	check(absf(WiringSolver.solve(comps, []).get("current", -1.0)) < 1.0e-9, "Cableado: sin cables => circuito abierto (0 A)")

	# 7) Microcontrolador: script con variables y funciones matemáticas.
	check(absf(main._mcu_run(["amp = 40", "output = amp * 2"], 0.0, 0.0, 0.008) - 80.0) < 1.0e-6, "MCU: variables y salida")
	check(absf(main._mcu_run(["sin(pi/2) * 10"], 0.0, 0.0, 0.008) - 10.0) < 1.0e-4, "MCU: funciones matemáticas (sin)")
	check(absf(main._mcu_run(["x * 3 + t"], 5.0, 2.0, 0.008) - 11.0) < 1.0e-6, "MCU: usa entradas t y x")
	check(is_nan(main._mcu_run(["sin("], 0.0, 0.0, 0.008)), "MCU: script inválido se detecta")
	check(absf(main._mcu_run(["a = clamp(x, 0, 3)", "a * 2 if x > 0 else -1"], 0.0, 5.0, 0.008) - 6.0) < 1.0e-6,
		"MCU: clamp y «a if c else b» siguen funcionando")
	# Una Expression sin objeto base llega igualmente a str_to_var, que carga un script
	# de la aplicación para reescribirlo y ejecutarlo; un proyecto compartido con el
	# programa activo ejecutaría código al abrirse.
	var probe: GDScript = load("res://tests/McuProbe.gd")
	var R = 'str_to_var("Resource(\\"res://tests/McuProbe.gd\\")")'
	main._mcu_run(['a = [%s.set_source_code("extends RefCounted\\nconst HIT = 1"), %s.reload()]' % [R, R]], 0.0, 0.0, 0.008)
	check(not probe.get_script_constant_map().has("HIT"), "MCU: no puede cargar ni reescribir scripts (str_to_var)")
	check(is_nan(main._mcu_run(["a = instance_from_id(%d).get_class()" % get_instance_id()], 0.0, 0.0, 0.008)),
		"MCU: no llega a los objetos de la aplicación (instance_from_id)")

	# 8) Protoboard funcional: circuito cerrado por columnas y rieles internos.
	main._on_new()
	var pb = main._spawn("protoboard", "abs", Vector3(0, 0.005, 0))
	var bat = main._spawn("bateria_lipo_3s", "abs", Vector3(0, 0.02, -0.12))
	var res = main._spawn("resistencia_100", "abs", Vector3(0.12, 0.01, 0))
	main.wires = [
		{"uid": "w1", "a_key": main._key(bat.uid, "V+"), "b_key": main._key(pb.uid, "a0_0"), "tipo": "power"},
		{"uid": "w2", "a_key": main._key(res.uid, "A"), "b_key": main._key(pb.uid, "a0_2"), "tipo": "power"},
		{"uid": "w3", "a_key": main._key(res.uid, "B"), "b_key": main._key(pb.uid, "N1_0"), "tipo": "gnd"},
		{"uid": "w4", "a_key": main._key(bat.uid, "GND"), "b_key": main._key(pb.uid, "N1_5"), "tipo": "gnd"},
	]
	var wp = []
	for w in main.wires:
		wp.append({"a": w["a_key"], "b": w["b_key"]})
	wp.append_array(main._protoboard_virtual_wires())
	var rpb = WiringSolver.solve(main._build_components(), wp)
	check(rpb["ok"] and float(rpb["current"]) > 0.05, "Protoboard funcional: circuito cierra por columnas/rieles (%.3f A)" % float(rpb["current"]))
	main.wires = []
	main._on_new()

	# 9) Integración F1: el circuito alimenta el motor (duty por voltaje).
	await get_tree().process_frame
	await get_tree().process_frame
	var bat2 = main._spawn("bateria_lipo_3s", "abs", Vector3(0, 0.02, -0.12))
	var mot = main._spawn("motor_dc", "acero", Vector3(0.12, 0.025, 0))
	var a1 = main._spawn("eje_acero_d10_150", "acero", Vector3(-0.03, 0.5, 0))
	var a2 = main._spawn("eje_acero_d10_150", "acero", Vector3(0.03, 0.5, 0))
	var cf = Connection.new(); cf.tipo = Connection.Tipo.BISAGRA; cf.motor_enabled = true
	cf.a_uid = a1.uid; cf.b_uid = a2.uid; cf.elec_uid = mot.uid; cf.elec_voltaje_nominal = 11.1
	main.connections = [cf]
	main.wires = [
		{"uid": "w1", "a_key": main._key(bat2.uid, "V+"), "b_key": main._key(mot.uid, "M+"), "tipo": "power"},
		{"uid": "w2", "a_key": main._key(mot.uid, "M-"), "b_key": main._key(bat2.uid, "GND"), "tipo": "gnd"},
	]
	main._circuit_tick()
	check(cf.elec_duty > 0.8, "F1: motor alimentado por el circuito (duty=%.2f)" % cf.elec_duty)
	main.wires = []
	main._circuit_tick()
	check(cf.elec_duty < 0.05, "F1: sin cables el motor se detiene (duty=%.2f)" % cf.elec_duty)
	main.connections = []
	main._on_new()

	print("[TEST] Electrónica: %d OK, %d FALLOS" % [ok, fail])
	get_tree().quit(1 if fail > 0 else 0)
