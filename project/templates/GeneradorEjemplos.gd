extends Node
## GeneradorEjemplos — Construye los proyectos de ejemplo y los guarda en
## res://templates/*.mforge (los muestra el menú «Ejemplos»).
##   Godot --headless --path project -- mfgen
## Cada ejemplo es una escena completa y funcional: piezas, uniones, cables,
## programa del microcontrolador, vista de cámara y entorno.

var main: Node

const EJEMPLOS := [
	["01_brazo_4gdl", "Brazo robótico 4 GDL",
		"Cuatro articulaciones con PID de posición; el microcontrolador genera trayectorias senoidales (m1…m4)."],
	["02_seguidor_linea", "Carro seguidor de línea",
		"Dos sensores IR sobre una pista de cinta y control diferencial de velocidad de las ruedas."],
	["03_evita_obstaculos", "Robot evita-obstáculos",
		"Carro con sensor ultrasónico en un recinto cerrado: si detecta una pared a menos de 25 cm, gira."],
	["04_reductora", "Reductora de engranajes 16:60",
		"Motor con control de velocidad que invierte el giro; el engranaje Z60 gira 3.75 veces más lento y muestra el huelgo."],
	["05_banco_pid", "Banco de control PID",
		"Brazo en voladizo con PID de posición siguiendo una onda (programa por bloques) y encoder en el eje. Mira la gráfica."],
	["06_circuito_led", "Circuito LED en protoboard",
		"Batería LiPo, resistencia de 100 Ω y LED cableados en una protoboard. Pulsa «Analizar circuito»."],
	["07_grua", "Grúa giratoria con contrapeso",
		"Torre anclada, pluma con giro controlado por PID y contrapeso. Activa «Esfuerzos» para ver la estabilidad."],
	["08_puente_carga", "Puente con carga",
		"Viga de acero sobre dos pilares con dos placas de carga. Activa «Esfuerzos» para ver el mapa de color."],
	["09_pendulo_doble", "Péndulo doble (caótico)",
		"Dos eslabones articulados que parten horizontales: movimiento caótico, sensible a las condiciones iniciales."],
]

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://templates"))
	for e in EJEMPLOS:
		main._on_new()
		await get_tree().process_frame
		await call("_ej_" + e[0].substr(3))
		main.project_meta = {"nombre": e[1], "descripcion": e[2]}
		var path := "res://templates/%s.mforge" % e[0]
		var err := ProjectSerializer.save(main.parts_root, path, main.connections, main.wires, main._project_extra())
		print("[GEN] %s -> %s (%d piezas, %d uniones)" % [e[1], path if err == OK else "ERROR %d" % err,
			main.parts_root.get_child_count(), main.connections.size()])
	main._on_new()
	get_tree().quit()

#region Utilidades ---------------------------------------------------------------

func _sp(id: String, mat: String, pos: Vector3, rot := Vector3.ZERO) -> PartInstance:
	return main._spawn(id, mat, pos, rot)

func _anchor(p: PartInstance) -> PartInstance:
	p.anchored = true
	return p

func _hinge(a: PartInstance, b: PartInstance, anchor: Vector3, axis: int) -> Connection:
	var c := Connection.new()
	c.a_uid = a.uid; c.b_uid = b.uid
	c.tipo = Connection.Tipo.BISAGRA; c.axis = axis; c.anchor = anchor
	main.connections.append(c)
	return c

func _vel_motor(c: Connection, sp: float, stall: float, noload: float) -> void:
	c.motor_enabled = true; c.motor_stall_torque = stall; c.motor_noload_speed = noload
	c.control_mode = Connection.ControlMode.VELOCIDAD; c.ctrl_setpoint = sp
	c.ctrl_kp = 0.3; c.ctrl_ki = 1.5; c.ctrl_kd = 0.0

func _program(script: String) -> void:
	main.mcu_editor.text = script
	main._apply_mcu()

func _view(target: Vector3, dist: float, yaw_deg: float, pitch_deg: float, env: int) -> void:
	main.work_env.set_mode(env)
	main.camera.target = target
	main.camera.distance = dist
	main.camera._yaw = deg_to_rad(yaw_deg)
	main.camera._pitch = deg_to_rad(pitch_deg)
	main.camera._update_transform()

## Carro diferencial (avanza hacia −X). Devuelve [chasis, rueda_izq, rueda_der].
func _car(x0: float, z0: float) -> Array:
	var chasis := _sp("placa_chasis_160x120", "aluminio", Vector3(x0, 0.022, z0))
	var rl := _sp("rueda_65", "caucho", Vector3(x0 + 0.045, 0.0325, z0 + 0.075), Vector3(PI / 2.0, 0, 0))
	var rr := _sp("rueda_65", "caucho", Vector3(x0 + 0.045, 0.0325, z0 - 0.075), Vector3(PI / 2.0, 0, 0))
	var bola := _sp("bola_loca_20", "ptfe", Vector3(x0 - 0.06, 0.010, z0))
	var bat := _sp("bateria_lipo_3s", "abs", Vector3(x0 + 0.01, 0.036, z0))
	for w in [rl, rr]:
		_vel_motor(_hinge(chasis, w, w.position, 2), 6.0, 0.8, 14.0)
	for q in [bola, bat]:
		main._tpl_fix(chasis, q, q.position)
	return [chasis, rl, rr]

#endregion

#region Ejemplos -----------------------------------------------------------------

func _ej_brazo_4gdl() -> void:
	main._tpl_brazo4()
	_program("# Trayectorias senoidales para las 4 articulaciones (grados).\nm1 = 45 * sin(0.4 * t)\nm2 = 20 + 15 * sin(0.6 * t)\nm3 = -35 + 20 * sin(0.8 * t)\nm4 = 15 * sin(1.2 * t)\noutput = m1")
	_view(Vector3(0.15, 0.2, 0), 1.1, -30, -22, 0)

func _ej_seguidor_linea() -> void:
	main._tpl_seguidor()
	_view(Vector3(0, 0, 0), 1.6, -35, -45, 1)

func _ej_evita_obstaculos() -> void:
	# Recinto de 1 × 1 m con paredes de placas de acero ancladas.
	var h := 0.5
	for k in range(5):
		var t := -0.4 + k * 0.2
		_anchor(_sp("placa_base_200x200", "acero", Vector3(h + 0.004, 0.1, t), Vector3(0, 0, PI / 2.0)))
		_anchor(_sp("placa_base_200x200", "acero", Vector3(-h - 0.004, 0.1, t), Vector3(0, 0, PI / 2.0)))
		_anchor(_sp("placa_base_200x200", "acero", Vector3(t, 0.1, h + 0.004), Vector3(PI / 2.0, 0, 0)))
		_anchor(_sp("placa_base_200x200", "acero", Vector3(t, 0.1, -h - 0.004), Vector3(PI / 2.0, 0, 0)))
	var car := _car(0.1, 0.05)
	# Sensor ultrasónico al frente, mirando hacia −X (su cara emisora es la +X local).
	var us := _sp("sensor_ultrasonido", "abs", Vector3(0.1 - 0.07, 0.034, 0.05), Vector3(0, PI, 0))
	main._tpl_fix(car[0], us, us.position)
	_program("# Evita obstáculos: con una pared a menos de 25 cm gira sobre sí mismo.\ncerca = dist1 < 0.25\nm1 = -4 if cerca else 6\nm2 = 6\noutput = m1")
	_view(Vector3(0, 0, 0), 1.7, -30, -55, 1)

func _ej_reductora() -> void:
	var base := _anchor(_sp("placa_base_200x200", "aluminio", Vector3(0, 0.004, 0)))
	var y := 0.008 + 0.0064 + 0.001
	var g1 := _sp("engranaje_m1_z16", "acero", Vector3(-0.038, y, 0))
	var g2 := _sp("engranaje_m1_z60", "cobre", Vector3(0.0, y, 0))
	# Indicador de giro corto (no alcanza la zona del Z16), 3 mm sobre los cubos.
	var brazo := _sp("perfil_2020_100", "aluminio_anodizado", Vector3(0.005, y + 0.0194, 0), Vector3(0, 0, PI / 2.0))
	brazo.def["dimensiones_mm"]["y"] = 40.0
	brazo.rebuild()
	var m := _hinge(base, g1, g1.position, 1)
	_vel_motor(m, 10.0, 1.5, 20.0)
	_hinge(base, g2, g2.position, 1)
	var c := Connection.new()
	c.a_uid = g1.uid; c.b_uid = g2.uid; c.tipo = Connection.Tipo.ENGRANAJE; c.axis = 1
	c.gear_z1 = 16; c.gear_z2 = 60; c.gear_backlash_deg = 2.0; c.gear_efficiency = 0.95
	main.connections.append(c)
	main._tpl_fix(g2, brazo, g2.position)
	_program("# Motor a ±10 rad/s, invierte cada ~6 s (observa el huelgo al invertir).\noutput = 10 if sin(0.5 * t) > 0 else -10")
	_view(Vector3(-0.01, 0.015, 0), 0.3, -25, -45, 0)

func _ej_banco_pid() -> void:
	_anchor(_sp("placa_base_200x200", "acero", Vector3(0, 0.004, 0)))
	var col := _anchor(_sp("perfil_4040_300", "aluminio_anodizado", Vector3(0, 0.158, 0)))
	var brazo := _sp("perfil_2020_200", "aluminio", Vector3(0.1, 0.29, 0.035), Vector3(0, 0, PI / 2.0))
	var enc := _sp("encoder", "abs", Vector3(0.0, 0.29, 0.056), Vector3(PI / 2.0, 0, 0))
	main._tpl_servo_joint(col, brazo, Vector3(0.0, 0.29, 0.035), 2, 0.0)
	main._tpl_fix(brazo, enc, enc.position)
	# Programa por bloques: onda de 60° a 0.25 Hz, limitada a ±75°.
	var be: BlockEditor = main.mcu_blocks
	be.blocks = [
		{"kind": "onda", "vals": {"var": "ang", "amp": "60", "f": "0.25"}},
		{"kind": "limitar", "vals": {"var": "ang", "min": "-75", "max": "75"}},
		{"kind": "salida", "vals": {"expr": "ang"}},
	]
	be._rebuild()
	_program(be.to_script())
	_view(Vector3(0.05, 0.2, 0), 0.9, -20, -15, 0)

func _ej_circuito_led() -> void:
	var pb := _sp("protoboard", "abs", Vector3(0, 0.005, 0))
	var bat := _sp("bateria_lipo_3s", "abs", Vector3(0, 0.013, -0.06))
	var res := _sp("resistencia_100", "abs", Vector3(-0.06, 0.012, 0.02))
	var led := _sp("led", "abs", Vector3(0.02, 0.012, 0.02))
	var k := func(p: PartInstance, t: String) -> String: return main._key(p.uid, t)
	main.wires = [
		{"uid": "e1", "a_key": k.call(bat, "V+"), "b_key": k.call(pb, "P1_2"), "tipo": "power", "color": "auto", "soldado_a": true},
		{"uid": "e2", "a_key": k.call(pb, "P1_5"), "b_key": k.call(res, "A"), "tipo": "power", "color": "rojo"},
		{"uid": "e3", "a_key": k.call(res, "B"), "b_key": k.call(pb, "a5_0"), "tipo": "signal", "color": "amarillo"},
		{"uid": "e4", "a_key": k.call(led, "anodo"), "b_key": k.call(pb, "a5_2"), "tipo": "signal", "color": "naranja"},
		{"uid": "e5", "a_key": k.call(led, "catodo"), "b_key": k.call(pb, "N1_4"), "tipo": "gnd", "color": "auto"},
		{"uid": "e6", "a_key": k.call(bat, "GND"), "b_key": k.call(pb, "N1_1"), "tipo": "gnd", "color": "auto", "soldado_a": true},
	]
	main._redraw_wires()
	_view(Vector3(-0.01, 0.02, 0), 0.4, -20, -35, 0)

func _ej_grua() -> void:
	var base := _anchor(_sp("placa_base_200x200", "acero", Vector3(0, 0.004, 0)))
	var torre := _sp("perfil_4040_300", "aluminio_anodizado", Vector3(0, 0.158, 0))
	var pluma := _sp("perfil_2020_400", "aluminio", Vector3(0.12, 0.318, 0), Vector3(0, 0, PI / 2.0))
	var contra := _sp("placa_100x100", "acero", Vector3(-0.07, 0.3305, 0))
	var carga := _sp("placa_100x100", "acero_inox", Vector3(0.28, 0.3305, 0))
	main._tpl_fix(base, torre, Vector3(0, 0.008, 0))
	main._tpl_servo_joint(torre, pluma, Vector3(0, 0.31, 0), 1, 0.0)
	main._tpl_fix(pluma, contra, contra.position)
	main._tpl_fix(pluma, carga, carga.position)
	_program("# Giro de la pluma: barrido de ±60° (PID de posición).\noutput = 60 * sin(0.3 * t)")
	_view(Vector3(0.05, 0.2, 0), 1.1, -35, -22, 2)

func _ej_puente_carga() -> void:
	main._tpl_puente()
	for c in main.parts_root.get_children():
		if c is PartInstance and c.def_id == "perfil_2020_200":
			c.anchored = true
	for x in [-0.12, 0.12]:
		var q := _sp("placa_base_200x200", "acero", Vector3(x, 0.224, 0))
		for c in main.parts_root.get_children():
			if c is PartInstance and c.def_id == "viga_acero_500":
				main._tpl_fix(c, q, q.position)
	_view(Vector3(0, 0.12, 0), 1.2, -30, -20, 2)

func _ej_pendulo_doble() -> void:
	var c1 := _anchor(_sp("perfil_4040_300", "aluminio_anodizado", Vector3(0, 0.15, 0)))
	var c2 := _anchor(_sp("perfil_4040_300", "aluminio_anodizado", Vector3(0, 0.45, 0)))
	var l1 := _sp("perfil_2020_200", "aluminio", Vector3(0.1, 0.58, 0.035), Vector3(0, 0, PI / 2.0))
	var l2 := _sp("perfil_2020_200", "aluminio", Vector3(0.3, 0.58, 0.058), Vector3(0, 0, PI / 2.0))
	_hinge(c2, l1, Vector3(0.0, 0.58, 0.035), 2)
	_hinge(l1, l2, Vector3(0.2, 0.58, 0.046), 2)
	_view(Vector3(0.1, 0.4, 0), 1.3, -15, -8, 0)

#endregion
