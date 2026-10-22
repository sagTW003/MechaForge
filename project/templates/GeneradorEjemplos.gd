extends Node
## GeneradorEjemplos — Construye los proyectos de ejemplo y los guarda en
## res://templates/*.mforge (los muestra el menú «Ejemplos»).
##   Godot --headless --path project -- mfgen [id ...]   (sin id: todos)
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
		"Batería LiPo, resistencia de 470 Ω y LED rojo con sus patas INSERTADAS en la protoboard: el LED (diodo real) se enciende con ≈20 mA. Pulsa «Analizar circuito»."],
	["07_grua", "Grúa giratoria con contrapeso",
		"Torre anclada, pluma con giro controlado por PID y contrapeso. Activa «Esfuerzos» para ver la estabilidad."],
	["08_puente_carga", "Puente con carga",
		"Viga de acero sobre dos pilares con dos placas de carga. Activa «Esfuerzos» para ver el mapa de color."],
	["09_pendulo_doble", "Péndulo doble (caótico)",
		"Dos eslabones articulados que parten horizontales: movimiento caótico, sensible a las condiciones iniciales."],
	["10_multimetro", "Multímetro en protoboard",
		"Mide con el multímetro (📟): tensión del LED (≈1.85 V), caída en la resistencia (sonda roja a la columna 11), continuidad de un riel (apaga la alimentación) y corriente EN SERIE (quita el puente negro e intercala las sondas en A⎓)."],
	["11_arduino_555", "Arduino Nano y NE555 (DIP) en protoboard",
		"Integrados DIP que cruzan el canal central: el Nano (USB) alimenta los rieles, el 555 astable hace parpadear el LED rojo y el programa (d2, d13) el LED verde. Pulsa ▶ Simular."],
	["12_gafas_vr", "Gafas VR caseras",
		"Carcasa impresa en PLA con pantalla de 5.5\", dos lentes de f = 45 mm en deslizaderas (distancia entre ojos de 63 mm) y una ESP32 que lee el MPU-6050 por I²C y estima la orientación con un filtro complementario. Selecciona una lente para ver su óptica."],
	["13_visor_cabeza", "Gafas VR en cabeza de prueba",
		"Las gafas caseras sobre una cabeza impresa que mueven tres servos (guiñada, cabeceo y alabeo) con perfiles senoidales. La ESP32 estima la orientación con la IMU y las cámaras del visor la siguen: abre 👓 Visor y pulsa ▶ Simular para comparar la orientación real con la estimada (error, deriva de la guiñada y latencia)."],
]

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://templates"))
	var ua := OS.get_cmdline_user_args()
	var only := ua.slice(ua.find("mfgen") + 1)
	for e in EJEMPLOS:
		if not only.is_empty() and not e[0] in only:
			continue
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

## Inserta un componente en la protoboard con su centro en (x, z) mm locales.
func _ins(def_id: String, pb: PartInstance, x_mm: float, z_mm: float, yaw := 0.0) -> PartInstance:
	var def := PartLibrary.get_def(def_id)
	var dm := PartLibrary.dims_m(def)
	var p := _sp(def_id, str(def.get("material", "abs")), pb.global_transform * Vector3(x_mm / 1000.0, 0.0045 + dm.y * 0.5 + 0.001, z_mm / 1000.0), Vector3(0, yaw, 0))
	var r := BreadboardSnap.try_insert(p.def, p.global_transform, pb)
	if r.get("ok", false):
		p.global_transform = r["xf"]
	main._refresh_insertion(p)
	return p

func _col(c: int) -> float:
	return PartInstance.bb_column_x(c)

## Agujero de la misma tira (columna) en otra fila: "b42_1" -> "b42_4".
func _same_col(hole: String, row: int) -> String:
	return hole.substr(0, hole.rfind("_") + 1) + str(row)

func _ej_circuito_led() -> void:
	var pb := _sp("protoboard", "abs", Vector3(0, 0.0045, 0))
	var bat := _sp("bateria_lipo_3s", "abs", Vector3(0, 0.0125, -0.065))
	_ins("resistencia_470", pb, (_col(10) + _col(14)) * 0.5, PartInstance.bb_row_z(true, 2))
	_ins("led", pb, (_col(14) + _col(15)) * 0.5, PartInstance.bb_row_z(true, 1), PI)
	var k := func(p: PartInstance, t: String) -> String: return main._key(p.uid, t)
	main.wires = [
		{"uid": "e1", "a_key": k.call(bat, "V+"), "b_key": k.call(pb, "P1_2"), "tipo": "power", "color": "auto", "soldado_a": true},
		{"uid": "e2", "a_key": k.call(pb, "P1_7"), "b_key": k.call(pb, "a10_4"), "tipo": "power", "color": "rojo"},
		{"uid": "e5", "a_key": k.call(pb, "a15_4"), "b_key": k.call(pb, "N1_11"), "tipo": "gnd", "color": "negro"},
		{"uid": "e6", "a_key": k.call(bat, "GND"), "b_key": k.call(pb, "N1_1"), "tipo": "gnd", "color": "auto", "soldado_a": true},
	]
	main._redraw_wires()
	_view(Vector3(-0.045, 0.01, 0.0), 0.28, -25, -38, 0)

func _ej_multimetro() -> void:
	var pb := _sp("protoboard", "abs", Vector3(0, 0.0045, 0))
	var bat := _sp("bateria_9v", "acero", Vector3(-0.05, 0.00875, -0.075), Vector3(0, PI / 2.0, 0))
	_ins("resistencia_470", pb, (_col(10) + _col(14)) * 0.5, PartInstance.bb_row_z(true, 2))
	_ins("led", pb, (_col(14) + _col(15)) * 0.5, PartInstance.bb_row_z(true, 1), PI)
	var k := func(p: PartInstance, t: String) -> String: return main._key(p.uid, t)
	main.wires = [
		{"uid": "m1", "a_key": k.call(bat, "V+"), "b_key": k.call(pb, "P1_3"), "tipo": "power", "color": "auto"},
		{"uid": "m2", "a_key": k.call(bat, "GND"), "b_key": k.call(pb, "N1_2"), "tipo": "gnd", "color": "auto"},
		{"uid": "m3", "a_key": k.call(pb, "P1_8"), "b_key": k.call(pb, "a10_4"), "tipo": "power", "color": "rojo"},
		{"uid": "m4", "a_key": k.call(pb, "a15_4"), "b_key": k.call(pb, "N1_12"), "tipo": "gnd", "color": "negro"},
	]
	main._redraw_wires()
	var dmm := _sp("multimetro", "abs", Vector3(0.0, 0.018, 0.13), Vector3(0, PI, 0))
	dmm.estado = {"modo": "V_DC", "fusible": true,
		"roja": {"clave": k.call(pb, "a14_0"), "pos": null}, "negra": {"clave": k.call(pb, "a15_0"), "pos": null}}
	_view(Vector3(-0.02, 0.01, 0.05), 0.42, -12, -48, 0)

func _ej_arduino_555() -> void:
	var pb := _sp("protoboard", "abs", Vector3(0, 0.0045, 0))
	var nano := _ins("arduino_nano", pb, _col(51), -1.27)
	var ic := _ins("ne555", pb, (_col(20) + _col(23)) * 0.5, 0.0)
	_ins("resistencia_220", pb, (_col(22) + _col(26)) * 0.5, PartInstance.bb_row_z(true, 2))
	_ins("led", pb, (_col(26) + _col(27)) * 0.5, PartInstance.bb_row_z(true, 3), PI)
	_ins("resistencia_330", pb, (_col(33) + _col(37)) * 0.5, PartInstance.bb_row_z(true, 2))
	_ins("led_verde", pb, (_col(37) + _col(38)) * 0.5, PartInstance.bb_row_z(true, 3), PI)
	var k := func(h: String) -> String: return main._key(pb.uid, h)
	var n5v := str(nano.pin_map["5V"])
	var ngnd := str(nano.pin_map["GND2"])
	var nd2 := str(nano.pin_map["D2"])
	main.wires = [
		{"uid": "n1", "a_key": k.call(_same_col(n5v, 4)), "b_key": k.call("P2_40"), "tipo": "power", "color": "rojo"},
		{"uid": "n2", "a_key": k.call(_same_col(ngnd, 4)), "b_key": k.call("N2_37"), "tipo": "gnd", "color": "negro"},
		{"uid": "n3", "a_key": k.call("P2_1"), "b_key": k.call("P1_1"), "tipo": "power", "color": "rojo"},
		{"uid": "n4", "a_key": k.call("N2_0"), "b_key": k.call("N1_0"), "tipo": "gnd", "color": "negro"},
		{"uid": "n5", "a_key": k.call(_same_col(str(ic.pin_map["VCC"]), 4)), "b_key": k.call("P2_16"), "tipo": "power", "color": "rojo"},
		{"uid": "n6", "a_key": k.call(_same_col(str(ic.pin_map["GND"]), 4)), "b_key": k.call("N1_16"), "tipo": "gnd", "color": "negro"},
		{"uid": "n7", "a_key": k.call(_same_col(str(ic.pin_map["RESET"]), 4)), "b_key": k.call("P1_19"), "tipo": "power", "color": "naranja"},
		{"uid": "n8", "a_key": k.call("a27_4"), "b_key": k.call("N1_22"), "tipo": "gnd", "color": "negro"},
		{"uid": "n9", "a_key": k.call(_same_col(nd2, 4)), "b_key": k.call("a33_4"), "tipo": "signal", "color": "amarillo"},
		{"uid": "n10", "a_key": k.call("a38_4"), "b_key": k.call("N1_31"), "tipo": "gnd", "color": "negro"},
	]
	main._redraw_wires()
	var dmm := _sp("multimetro", "abs", Vector3(0.0, 0.018, 0.13), Vector3(0, PI, 0))
	dmm.estado = {"modo": "V_DC", "fusible": true,
		"roja": {"clave": k.call(_same_col(str(ic.pin_map["OUT"]), 3)), "pos": null}, "negra": {"clave": k.call("N1_24"), "pos": null}}
	_program("# Arduino Nano: el LED «L» (D13) y el LED verde (D2)\n# parpadean a 1 Hz; el LED rojo lo hace oscilar el NE555.\nd13 = floor(fmod(t * 2, 2))\nd2 = d13\nd13")
	_view(Vector3(0.0, 0.01, 0.04), 0.4, -10, -50, 0)

## Visor VR (adelante = +X, la cara en −X). La pantalla, el soporte y las lentes usan
## la misma orientación: su +Y mira hacia el ojo (−X), su +X a −Z y su +Z arriba.
func _ej_gafas_vr() -> void:
	_anchor(_headset(0.0))
	_program(VR_PROGRAM)
	_view(Vector3(-0.005, 0.055, 0.0), 0.4, 62, -24, 0)

## Gafas completas (carcasa, pantalla, soporte con dos lentes en deslizaderas, ESP32 e
## IMU con sus cables), subidas «lift» metros. Devuelve la carcasa.
func _headset(lift: float) -> PartInstance:
	var yc := 0.0475 + lift
	var face := Basis(Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)).get_euler()
	var shell := _sp("carcasa_visor", "pla", Vector3(0, yc, 0))
	var scr := _sp("pantalla_55", "abs", Vector3(0.027, yc, 0), face)
	var holder := _sp("soporte_lentes", "pla", Vector3(-0.016, yc, 0), face)
	var lenses := []
	for z in [0.0315, -0.0315]:
		lenses.append(_sp("lente_cardboard_37", "acrilico", Vector3(-0.016, yc, z), face))
	# Electrónica sobre el techo: los cables de la pantalla bajan por el pasacables.
	var esp := _sp("esp32_devkit", "abs", Vector3(0.005, 0.1 + lift, -0.045))
	var imu := _sp("imu", "abs", Vector3(-0.005, 0.099 + lift, 0.03))
	for q in [scr, holder, esp, imu]:
		main._tpl_fix(shell, q, q.position)
	for ln in lenses:
		var c := Connection.new()
		c.a_uid = holder.uid; c.b_uid = ln.uid
		c.tipo = Connection.Tipo.DESLIZADERA; c.axis = 2; c.anchor = ln.position
		c.limit_enabled = true; c.limit_lower = -0.009; c.limit_upper = 0.009
		c.slide_locked = true               # el ajuste de IPD no se mueve al usar las gafas
		main.connections.append(c)
	var k := func(p: PartInstance, t: String) -> String: return main._key(p.uid, t)
	main.wires = [
		{"uid": "v1", "a_key": k.call(esp, "5V"), "b_key": k.call(scr, "5V"), "tipo": "power", "color": "auto"},
		{"uid": "v2", "a_key": k.call(esp, "GND"), "b_key": k.call(scr, "GND"), "tipo": "gnd", "color": "auto"},
		{"uid": "v3", "a_key": k.call(esp, "3V3"), "b_key": k.call(imu, "VCC"), "tipo": "power", "color": "naranja"},
		{"uid": "v4", "a_key": k.call(esp, "GND2"), "b_key": k.call(imu, "GND"), "tipo": "gnd", "color": "negro"},
		{"uid": "v5", "a_key": k.call(esp, "GPIO22"), "b_key": k.call(imu, "SCL"), "tipo": "signal", "color": "amarillo"},
		{"uid": "v6", "a_key": k.call(esp, "GPIO21"), "b_key": k.call(imu, "SDA"), "tipo": "signal", "color": "azul"},
	]
	main._redraw_wires()
	return shell

## Banco de pruebas: la cabeza impresa sobre tres servos apilados (guiñada sobre el
## poste, cabeceo y alabeo) que siguen perfiles senoidales, con las gafas puestas: los
## ojos de la cabeza coinciden con los del visor (15 mm detrás de las lentes).
func _ej_visor_cabeza() -> void:
	var hx := -0.115                     # centro de la cabeza (los ojos, 84 mm delante)
	var base := _anchor(_sp("placa_base_200x200", "acero", Vector3(hx, 0.004, 0)))
	var post := _sp("perfil_2020_200", "aluminio", Vector3(hx, 0.108, 0))
	var s_yaw := _sp("servo", "abs", Vector3(hx, 0.227, 0))
	var s_pitch := _sp("servo", "abs", Vector3(hx, 0.267, 0))
	var s_roll := _sp("servo", "abs", Vector3(hx, 0.307, 0))
	var head := _sp("cabeza_prueba", "pla", Vector3(hx, 0.443, 0))
	head.estado["impresion"] = {"relleno": 0.1, "paredes_mm": 1.2}
	main._tpl_fix(base, post, post.position)
	main._tpl_fix(post, s_yaw, s_yaw.position)
	_servo(_hinge(s_yaw, s_pitch, Vector3(hx, 0.247, 0), 1), 35.0, 0.2, 0.0, 70.0)
	_servo(_hinge(s_pitch, s_roll, Vector3(hx, 0.287, 0), 2), 15.0, 0.3, 90.0, 40.0)
	_servo(_hinge(s_roll, head, Vector3(hx, 0.327, 0), 0), 10.0, 0.25, 45.0, 35.0)
	var shell := _headset(0.4055)
	main._tpl_fix(head, shell, shell.position)
	_program(VR_PROGRAM)
	main.headset_rig.track_mode = HeadsetRig.Track.IMU
	_view(Vector3(-0.05, 0.33, 0.0), 0.85, -125, -12, 0)

## Servo de posición del banco: perfil senoidal (amplitud °, frecuencia Hz, desfase °),
## límites ±lim° y servo ideal (el banco sigue el perfil exacto: en Jolt, un motor
## entre dos piezas que se mueven no sostiene bien una carga encima).
func _servo(c: Connection, amp: float, freq: float, phase: float, lim: float) -> void:
	c.motor_enabled = true
	c.motor_type = Connection.MotorType.SERVO
	c.motor_stall_torque = 2.5
	c.motor_noload_speed = 9.0
	c.servo_min_deg = -90.0
	c.servo_max_deg = 90.0
	c.servo_sec_per_60 = 0.12
	c.control_mode = Connection.ControlMode.POSICION
	c.ctrl_kp = 12.0; c.ctrl_ki = 2.0; c.ctrl_kd = 0.3
	c.limit_enabled = true; c.limit_lower = deg_to_rad(-lim); c.limit_upper = deg_to_rad(lim)
	c.profile = Connection.Profile.SENO
	c.profile_amp = amp; c.profile_freq = freq; c.profile_phase_deg = phase
	c.profile_ideal = true

## Firmware del visor: filtro complementario con la cinemática de los ángulos de Euler
## (el giroscopio da velocidades en ejes del chip; con el visor inclinado no son las
## derivadas de alabeo, cabeceo y guiñada).
const VR_PROGRAM := """# ESP32 + MPU-6050 por I²C (dirección 0x68): despierta el sensor, lee sus
# registros y estima la orientación (grados) con un filtro complementario:
# integra el giroscopio con la cinemática de los ángulos de Euler y corrige
# el alabeo y el cabeceo con la gravedad que mide el acelerómetro.
inicio:
  ok = i2c_escribir(0x68, 0x6B, 0)
  quien = i2c_leer(0x68, 0x75)
bucle:
  ax = i2c16(0x68, 0x3B) / 16384.0
  ay = i2c16(0x68, 0x3D) / 16384.0
  az = i2c16(0x68, 0x3F) / 16384.0
  gx = i2c16(0x68, 0x43) / 131.0
  gy = i2c16(0x68, 0x45) / 131.0
  gz = i2c16(0x68, 0x47) / 131.0
  r = roll * pi / 180
  p = pitch * pi / 180
  giro = sin(r) * gy + cos(r) * gz
  roll = 0.98 * (roll + (gx + giro * tan(p)) * dt) + 0.02 * atan2(ay, az) * 180 / pi
  pitch = 0.98 * (pitch + (cos(r) * gy - sin(r) * gz) * dt) + 0.02 * atan2(-ax, sqrt(ay * ay + az * az)) * 180 / pi
  yaw = yaw + giro / cos(p) * dt"""

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
