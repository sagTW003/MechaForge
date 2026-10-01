extends Node
## FinalTests — Pruebas de los últimos detalles del proyecto (documento original).
## Ejecutar:  Godot --headless --path project -- mffinal
##
## API local para OpenClaw (HTTP real contra 127.0.0.1), sensores y bloques del
## microcontrolador, control del tiempo, temperatura del motor, autoguardado,
## copiar/pegar y simetría, anclaje al mundo, plantillas (brazo 4 GDL y seguidor
## de línea) y persistencia de modelos importados.

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
	print("[TEST] Detalles finales (API, sensores, bloques, tiempo, plantillas...)")
	await _test_api()
	await _test_sensors_and_blocks()
	await _test_velocity_pid()
	await _test_time_controls()
	await _test_temperature()
	_test_clipboard_mirror()
	await _test_anchor()
	await _test_autosave_import()
	await _test_arm4()
	await _test_line_follower()
	main._on_new()
	print("[TEST] Detalles finales: %d OK, %d FALLOS" % [ok, fail])
	get_tree().quit(1 if fail > 0 else 0)

#region API ---------------------------------------------------------------------

func _http(method: int, path: String, body: String, token: String) -> Dictionary:
	var req := HTTPRequest.new()
	add_child(req)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if token != "":
		headers.append("Authorization: Bearer " + token)
	req.request("http://127.0.0.1:%d%s" % [main.tool_server.port, path], headers, method, body)
	var res: Array = await req.request_completed
	req.queue_free()
	var parsed = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	return {"code": res[1], "json": parsed if typeof(parsed) == TYPE_DICTIONARY else {}}

func _rpc(method: String, params: Dictionary) -> Dictionary:
	var r := await _http(HTTPClient.METHOD_POST, "/rpc", JSON.stringify({"jsonrpc": "2.0", "id": 7, "method": method, "params": params}), main.tool_server.token)
	return r["json"]

func _test_api() -> void:
	main._on_new()
	var ts: ToolServer = main.tool_server
	check(ts.is_listening(), "API: servidor escuchando en 127.0.0.1:%d" % ts.port)
	var h := await _http(HTTPClient.METHOD_GET, "/health", "", "")
	check(h["code"] == 200 and h["json"].get("ok", false), "API: /health responde")
	var bad := await _http(HTTPClient.METHOD_GET, "/tools", "", "token-falso")
	check(bad["code"] == 401, "API: sin token válido → 401")
	var tools := await _http(HTTPClient.METHOD_GET, "/tools", "", ts.token)
	var names: Array = (tools["json"].get("tools", []) as Array).map(func(t): return t["name"])
	check(names.has("get_scene_state") and names.has("add_part") and names.has("analyze_design") and names.has("write_controller_script"),
		"API: /tools lista las herramientas con esquema (%d)" % names.size())
	var r := await _rpc("add_part", {"def_id": "perfil_2020_200", "material": "aluminio", "pos": [0, 0.1, 0]})
	var pid := int(r.get("result", {}).get("proposal_id", -1))
	check(r.get("result", {}).get("status", "") == "pending_confirmation", "API: add_part queda pendiente de confirmación (vista previa)")
	check(main.ai_ghost_root.get_child_count() == 1 and main.parts_root.get_child_count() == 0, "API: se muestra una pieza fantasma y la escena no cambia")
	main._ai_apply()
	var st := await _rpc("get_proposal_status", {"id": pid})
	check(st.get("result", {}).get("status", "") == "applied", "API: tras Aplicar la propuesta figura como aplicada")
	var scene := await _rpc("get_scene_state", {})
	var piezas: Array = scene.get("result", {}).get("piezas", [])
	check(piezas.size() == 1 and piezas[0]["def_id"] == "perfil_2020_200", "API: get_scene_state devuelve la pieza aplicada")
	var err := await _rpc("add_part", {"def_id": "no_existe", "pos": [0, 0, 0]})
	check(err.has("error"), "API: def_id inexistente → error JSON-RPC")
	var an := await _rpc("analyze_design", {})
	check(an.get("result", {}).has("estable") and an["result"].get("masa_total_kg", 0.0) > 0.0, "API: analyze_design (masa, estabilidad, esfuerzos)")
	var run := await _rpc("run_simulation", {})
	check(run.get("result", {}).get("simulando", false), "API: run_simulation inicia la física")
	await wait_phys(5)
	var tel := await _rpc("get_telemetry", {})
	check(tel.get("result", {}).get("piezas", {}).size() == 1, "API: get_telemetry con la simulación en marcha")
	await _rpc("stop_simulation", {})
	check(not main.simulator.is_running(), "API: stop_simulation")

#endregion

#region SENSORES Y BLOQUES -------------------------------------------------------

func _test_sensors_and_blocks() -> void:
	main._on_new()
	var wall: PartInstance = main._spawn("placa_base_200x200", "acero", Vector3(0.3, 0.1, 0), Vector3(0, 0, PI / 2.0))
	wall.anchored = true
	var us: PartInstance = main._spawn("sensor_ultrasonido", "abs", Vector3(0.0, 0.1, 0))
	us.anchored = true
	var imu: PartInstance = main._spawn("imu", "abs", Vector3(-0.2, 0.1, 0), Vector3(0, 0, deg_to_rad(20)))
	imu.anchored = true
	var names := Sensors.variable_names(main.parts_root)
	check(names.has("dist1") and names.has("imu1_pitch"), "Sensores: variables dist1, imu1_pitch… disponibles")
	main.simulator.start([])
	await wait_phys(3)
	var sens := Sensors.new()
	var v := sens.read(main.parts_root, main.simulator, main.get_world_3d().direct_space_state)
	# Sensor en x=0 (cara +X en 0.0225), placa vertical con cara en x = 0.3 - 0.004.
	check(absf(float(v.get("dist1", 0.0)) - 0.2735) < 0.01, "Ultrasonido mide la distancia a la pared (%.3f m ≈ 0.274)" % float(v.get("dist1", 0.0)))
	# Convención del MPU-6050: pitch > 0 = morro abajo; la pieza está 20° morro arriba.
	check(absf(float(v.get("imu1_pitch", 0.0)) + 20.0) < 1.0, "IMU mide el cabeceo (%.1f° ≈ −20°, morro arriba)" % float(v.get("imu1_pitch", 0.0)))
	main.simulator.stop()
	# Bloques → script → ejecución.
	var be := BlockEditor.new()
	be.blocks = [
		{"kind": "seguir", "vals": {"var": "e", "kp": "10", "ref": "0.5", "sensor": "dist1"}},
		{"kind": "si", "vals": {"var": "e", "cond": "e > 2", "a": "2", "b": "e"}},
		{"kind": "motor", "vals": {"n": "2", "expr": "e * 3"}},
		{"kind": "salida", "vals": {"expr": "e"}},
	]
	var script := be.to_script()
	var outv := {}
	main._mcu_sensor_vars = {"dist1": 0.3}
	main.simulator.start([])
	var y: float = main._mcu_run(script.split("\n"), 0.0, 0.0, 0.01, outv)
	main.simulator.stop()
	check(absf(y - 2.0) < 1e-6 and absf(float(outv.get("m2", 0.0)) - 6.0) < 1e-6,
		"Bloques: seguir sensor + si/si no + motor 2 compilan y ejecutan (salida %.2f, m2 %.2f)" % [y, float(outv.get("m2", 0.0))])
	be.free()

#endregion

#region TIEMPO Y TEMPERATURA -----------------------------------------------------

## Control de velocidad (rueda en el aire): converge a la consigna sin oscilar.
func _test_velocity_pid() -> void:
	main._on_new()
	var a: PartInstance = main._spawn("placa_100x100", "aluminio", Vector3(0, 1.0, 0))
	var b: PartInstance = main._spawn("rueda_65", "caucho", Vector3(0, 1.0, 0.08), Vector3(PI / 2.0, 0, 0))
	a.anchored = true
	var c := Connection.new(); c.a_uid = a.uid; c.b_uid = b.uid
	c.tipo = Connection.Tipo.BISAGRA; c.axis = 2; c.anchor = b.position
	c.motor_enabled = true; c.motor_stall_torque = 1.0; c.motor_noload_speed = 10.0
	c.control_mode = Connection.ControlMode.VELOCIDAD; c.ctrl_setpoint = 3.0
	c.ctrl_kp = 0.3; c.ctrl_ki = 1.0; c.ctrl_kd = 0.0
	main.simulator.start([c])
	main.simulator.get_body(b.uid).gravity_scale = 0.0
	await wait_phys(120)
	var w := []
	for i in range(6):
		await wait_phys(1)
		w.append((main.simulator.get_body(b.uid).angular_velocity - main.simulator.get_body(a.uid).angular_velocity).dot(Vector3.BACK))
	check(absf(w.min() - 3.0) < 0.1 and absf(w.max() - 3.0) < 0.1, "Control de velocidad PID: rueda a 3 rad/s estable (mín %.2f, máx %.2f)" % [w.min(), w.max()])
	main.simulator.stop()

func _test_time_controls() -> void:
	main._on_new()
	var p: PartInstance = main._spawn("eje_acero_d10_150", "acero", Vector3(0, 1.0, 0))
	main.simulator.start([])
	await wait_phys(10)
	main.simulator.set_paused(true)
	var b: RigidBody3D = main.simulator.get_body(p.uid)
	var y0 := b.global_position.y
	await wait_phys(20)
	check(absf(b.global_position.y - y0) < 1e-6, "Pausa: la física se detiene")
	await main.simulator.step_frames(1)
	var y1 := b.global_position.y
	check(y1 < y0 and y0 - y1 < 0.01, "Paso a paso: avanza exactamente un paso (Δy=%.5f m)" % (y0 - y1))
	main.simulator.set_paused(false)
	main.simulator.set_time_scale(0.25)
	check(is_equal_approx(Engine.time_scale, 0.25), "Cámara lenta: escala de tiempo 0.25×")
	main.simulator.stop()
	check(is_equal_approx(Engine.time_scale, 1.0) and not main.simulator.paused, "Al detener se restablece el tiempo real")

func _test_temperature() -> void:
	main._on_new()
	var a: PartInstance = main._spawn("eje_acero_d10_150", "acero", Vector3(-0.03, 1.0, 0), Vector3(0, 0, PI / 2.0))
	var b: PartInstance = main._spawn("eje_acero_d10_150", "acero", Vector3(0.03, 1.0, 0), Vector3(0, 0, PI / 2.0))
	a.anchored = true
	var c := Connection.new()
	c.a_uid = a.uid; c.b_uid = b.uid; c.tipo = Connection.Tipo.BISAGRA; c.axis = 2
	c.anchor = (a.position + b.position) * 0.5
	c.motor_enabled = true; c.motor_target_speed = 5.0; c.motor_stall_torque = 2.0
	c.limit_enabled = true; c.limit_lower = -0.1; c.limit_upper = 0.1   # eje bloqueado por el tope
	main.simulator.start([c])
	main.simulator.set_time_scale(1.0)
	await wait_phys(240)
	var t: float = main.simulator.motor_temperature(c.uid)
	check(t > Simulator.T_AMBIENT + 0.5, "Temperatura del motor sube con carga (%.1f °C tras 2 s)" % t)
	main.simulator.stop()

#endregion

#region EDICIÓN ------------------------------------------------------------------

func _test_clipboard_mirror() -> void:
	main._on_new()
	var p: PartInstance = main._spawn("perfil_2020_200", "aluminio", Vector3(0.1, 0.1, 0.05), Vector3(0, 0.4, 0.2))
	main._select(p)
	main._copy_selected()
	main._paste()
	check(main.parts_root.get_child_count() == 2, "Copiar/pegar crea una pieza nueva")
	main._select(p)
	main._mirror_selected()
	var m: PartInstance = main.selected_part
	check(m != p and absf(m.position.x + 0.1) < 1e-6 and absf(m.position.z - 0.05) < 1e-6, "Simetría: x → −x")
	var mirror_basis := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
	var expected := mirror_basis * p.basis * mirror_basis
	check(m.basis.is_equal_approx(expected), "Simetría: orientación reflejada (M·R·M)")
	main.undo()
	check(main.parts_root.get_child_count() == 2, "La simetría se deshace con Ctrl+Z")

func _test_anchor() -> void:
	main._on_new()
	var p: PartInstance = main._spawn("perfil_2020_200", "aluminio", Vector3(0, 0.5, 0))
	p.anchored = true
	main.simulator.start([])
	await wait_phys(30)
	check(absf(main.simulator.get_body(p.uid).global_position.y - 0.5) < 1e-6, "Anclada al mundo: la pieza no cae")
	main.simulator.stop()
	var d := p.to_dict()
	check(d.get("fijo", false), "Anclaje se guarda en el proyecto")

func _test_autosave_import() -> void:
	main._on_new()
	# Importación de un OBJ y persistencia al guardar/abrir.
	var obj := "user://test_cubo.obj"
	var f := FileAccess.open(obj, FileAccess.WRITE)
	f.store_string("v -0.01 -0.01 -0.01\nv 0.01 -0.01 -0.01\nv 0.01 0.01 -0.01\nv -0.01 0.01 -0.01\nv 0 0 0.02\nf 1 2 3\nf 1 3 4\nf 1 2 5\nf 2 3 5\nf 3 4 5\nf 4 1 5\n")
	f.close()
	var def := MeshImporter.make_part_def(ProjectSettings.globalize_path(obj))
	check(not def.is_empty() and def.has("_source"), "Importación: definición con ruta de origen")
	PartLibrary.register(def)
	main._spawn(def["id"], "aluminio", Vector3(0, 0.02, 0))
	Config.project_dirty = true
	check(main._autosave(), "Autoguardado: se escribe user://autoguardado.mforge")
	# Simula una sesión nueva: se olvida la definición importada y se recupera.
	PartLibrary._defs.erase(def["id"])
	main._on_new()
	main._recover_autosave()
	await get_tree().process_frame
	var found := false
	for c in main.parts_root.get_children():
		if c is PartInstance and c.def.get("forma", "") == "custom":
			found = true
	check(found, "Recuperar autoguardado re-importa el modelo 3D desde su archivo")

#endregion

#region PLANTILLAS ---------------------------------------------------------------

func _test_arm4() -> void:
	main._tpl_brazo4()
	var ctrl: Array = main._controlled_connections()
	check(ctrl.size() == 4, "Brazo 4 GDL: cuatro articulaciones con control PID")
	main.simulator.start(main.connections)
	await wait_phys(480)
	var errs := []
	for c in ctrl:
		errs.append(absf(rad_to_deg(main.simulator.control_measure(c.uid) - c.ctrl_setpoint)))
	check(errs.max() < 8.0, "Brazo 4 GDL: todas las articulaciones llegan a su consigna (error máx %.1f°)" % errs.max())
	main.simulator.stop()

func _test_line_follower() -> void:
	main._tpl_seguidor()
	check(main._controlled_connections().size() == 2 and Sensors.variable_names(main.parts_root).has("linea2"), "Seguidor: dos ruedas con control y dos sensores de línea")
	var chasis: PartInstance = null
	for c in main.parts_root.get_children():
		if c is PartInstance and c.def_id == "placa_chasis_160x120":
			chasis = c
	main._toggle_simulation()
	var seen := 0
	var max_dev := 0.0
	var start: Vector3 = main.simulator.get_body(chasis.uid).global_position
	var travelled := 0.0
	var last := start
	for i in range(60):
		await wait_phys(8)
		var p: Vector3 = main.simulator.get_body(chasis.uid).global_position
		travelled += Vector2(p.x - last.x, p.z - last.z).length()
		last = p
		var sv: Dictionary = main._mcu_sensor_vars
		if float(sv.get("linea1", 0.0)) > 0.5 or float(sv.get("linea2", 0.0)) > 0.5:
			seen += 1
		max_dev = maxf(max_dev, _track_distance(p))
	check(travelled > 0.5, "Seguidor: el carro avanza por la pista (%.2f m en 4 s)" % travelled)
	check(max_dev < 0.08, "Seguidor: se mantiene sobre la línea (desviación máx %.0f mm)" % (max_dev * 1000.0))
	main._toggle_simulation()

## Distancia en planta de un punto a la pista ovalada (rectas ±0.45 m, R = 0.25).
func _track_distance(p: Vector3) -> float:
	var R := 0.25
	var hx := 0.45
	if absf(p.x) <= hx:
		return absf(absf(p.z) - R)
	var cx := hx * signf(p.x)
	return absf(Vector2(p.x - cx, p.z).length() - R)

#endregion
