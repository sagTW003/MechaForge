extends Node
## PhysicsTests — Pruebas de física (Fase 2): gravedad, reinicio, uniones y motores.
## Ejecutar:  Godot --headless --path project -- mfphys

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

func wait_phys(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame

func run() -> void:
	print("[TEST] Pruebas de física (Fase 2)...")

	# --- 1) Gravedad + reinicio al estado inicial ---
	main._on_new()
	var caida = main._spawn("eje_acero_d10_150", "acero_inox", Vector3(0, 0.5, 0))
	var y0 = caida.position.y
	main.simulator.start([])
	await wait_phys(80)
	var b = main.simulator.get_body(caida.uid)
	check(b != null and b.global_position.y < 0.45, "La pieza cae por gravedad (y baja)")
	main.simulator.stop()
	check(absf(caida.position.y - y0) < 1.0e-5, "Al detener, la pieza vuelve al estado inicial")

	# --- 2) Unión fija: mantiene la distancia entre piezas ---
	main._on_new()
	var f1 = main._spawn("perfil_2020_200", "aluminio", Vector3(-0.03, 0.5, 0))
	var f2 = main._spawn("perfil_2020_200", "aluminio", Vector3(0.03, 0.5, 0))
	var cf = Connection.new(); cf.a_uid = f1.uid; cf.b_uid = f2.uid; cf.tipo = Connection.Tipo.FIJA
	cf.anchor = (f1.global_position + f2.global_position) * 0.5
	main.simulator.start([cf])
	var d0 = main.simulator.get_body(f1.uid).global_position.distance_to(main.simulator.get_body(f2.uid).global_position)
	await wait_phys(100)
	var d1 = main.simulator.get_body(f1.uid).global_position.distance_to(main.simulator.get_body(f2.uid).global_position)
	check(absf(d1 - d0) < 0.005, "Unión fija conserva la distancia (%.4f→%.4f m)" % [d0, d1])
	main.simulator.stop()

	# --- 3) Motor de bisagra en espacio libre: velocidad RELATIVA no nula ---
	main._on_new()
	var base = main._spawn("eje_acero_d10_150", "acero", Vector3(-0.03, 1.0, 0), Vector3(0, 0, PI / 2.0))
	var arm = main._spawn("eje_acero_d10_150", "acero", Vector3(0.03, 1.0, 0), Vector3(0, 0, PI / 2.0))
	var cm = Connection.new(); cm.a_uid = base.uid; cm.b_uid = arm.uid
	cm.tipo = Connection.Tipo.BISAGRA; cm.axis = 2
	cm.anchor = (base.global_position + arm.global_position) * 0.5
	cm.motor_enabled = true; cm.motor_target_speed = 6.0
	cm.motor_stall_torque = 3.0; cm.motor_noload_speed = 8.0
	main.simulator.start([cm])
	for bb0 in [main.simulator.get_body(base.uid), main.simulator.get_body(arm.uid)]:
		bb0.gravity_scale = 0.0          # banco de pruebas en el aire (sin contacto)
	await wait_phys(150)
	var ba = main.simulator.get_body(base.uid)
	var bb = main.simulator.get_body(arm.uid)
	var rel = absf((bb.angular_velocity - ba.angular_velocity).dot(cm.axis_vector()))
	var rel_signed = (bb.angular_velocity - ba.angular_velocity).dot(cm.axis_vector())
	check(absf(rel_signed - 6.0) < 0.3, "Motor: Δω = consigna (+6 rad/s) en el eje y sentido pedidos (%.2f)" % rel_signed)
	main.simulator.stop()

	# --- 4) Engranaje: restricción dinámica ω_b = -ratio·ω_a (conserva el momento) ---
	main._on_new()
	var g1 = main._spawn("eje_acero_d10_150", "acero", Vector3(-0.1, 0.5, 0), Vector3(PI / 2.0, 0, 0))
	var g2 = main._spawn("eje_acero_d10_150", "acero", Vector3(0.1, 0.5, 0), Vector3(PI / 2.0, 0, 0))
	var cg = Connection.new(); cg.a_uid = g1.uid; cg.b_uid = g2.uid
	cg.tipo = Connection.Tipo.ENGRANAJE; cg.axis = 1; cg.gear_ratio = 2.0
	main.simulator.start([cg])
	main.simulator.get_body(g1.uid).angular_velocity = Vector3.UP * 2.0
	await wait_phys(8)
	var wa = main.simulator.get_body(g1.uid).angular_velocity.dot(Vector3.UP)
	var wb = main.simulator.get_body(g2.uid).angular_velocity.dot(Vector3.UP)
	check(absf(wa) > 0.05 and absf(wb / wa + 2.0) < 0.25, "Engranaje ratio 2: ω_b/ω_a ≈ -2 (obtenido %.2f / %.2f)" % [wb, wa])
	check(wa < 2.0 and wa > 0.0, "La carga del engranaje frena al conductor (ω_a %.2f < 2.0)" % wa)
	main.simulator.stop()

	# --- Control PID de posición: la bisagra alcanza el ángulo consigna ---
	main._on_new()
	var cb = main._spawn("eje_acero_d10_150", "acero", Vector3(-0.03, 1.0, 0), Vector3(0, 0, PI / 2.0))
	var ca = main._spawn("eje_acero_d10_150", "acero", Vector3(0.03, 1.0, 0), Vector3(0, 0, PI / 2.0))
	var cc = Connection.new(); cc.a_uid = cb.uid; cc.b_uid = ca.uid
	cc.tipo = Connection.Tipo.BISAGRA; cc.axis = 2
	cc.anchor = (cb.global_position + ca.global_position) * 0.5
	cc.motor_enabled = true; cc.motor_stall_torque = 4.0; cc.motor_noload_speed = 10.0
	cc.control_mode = Connection.ControlMode.POSICION; cc.ctrl_setpoint = 1.0
	cc.ctrl_kp = 8.0; cc.ctrl_ki = 1.0; cc.ctrl_kd = 0.4
	main.simulator.start([cc])
	for bb1 in [main.simulator.get_body(cb.uid), main.simulator.get_body(ca.uid)]:
		bb1.gravity_scale = 0.0
	await wait_phys(400)
	var ang = main.simulator.control_measure(cc.uid)
	check(absf(ang - 1.0) < 0.3, "Control PID alcanza el ángulo consigna (%.2f rad)" % ang)
	var elec = main.simulator.electrical()
	check(float(elec.get("current", 0.0)) > 0.0, "El motor consume corriente (%.2f A)" % float(elec.get("current", 0.0)))
	main.simulator.stop()

	# --- 5) Encaje por superficie: posar una pieza encima de otra ---
	main._on_new()
	Config.surface_snap_enabled = true
	var mesa = main._spawn("placa_base_200x200", "acero", Vector3(0, 0.004, 0))  # cara superior en y=0.008
	await wait_phys(3)
	main.camera.target = Vector3(0, 0.004, 0)
	main.camera._yaw = 0.0
	main.camera._pitch = deg_to_rad(-89.0)
	main.camera.distance = 1.0
	main.camera._update_transform()
	await get_tree().process_frame
	var centro = main.get_viewport().get_visible_rect().size * 0.5
	var dims = PartLibrary.dims_m(PartLibrary.get_def("perfil_2020_100"))  # y=0.1
	var snap = main._try_surface_snap(centro, dims, null)
	check(not snap.is_empty() and snap.get("target") == mesa, "Encaje detecta la pieza bajo el cursor")
	if not snap.is_empty():
		var esperado = 0.008 + dims.y * 0.5
		check(absf(snap["pos"].y - esperado) < 0.02, "Encaje posa la pieza encima (y=%.3f, esperado %.3f)" % [snap["pos"].y, esperado])

	main._on_new()
	print("[TEST] Física: %d OK, %d FALLOS" % [ok, fail])
	get_tree().quit(1 if fail > 0 else 0)
