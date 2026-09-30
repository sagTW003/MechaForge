extends Node
## LabTests — Pruebas y capturas del Laboratorio matemático.
##   Godot --headless --path project -- mflabtest
##   Godot --path project -- mflabshot <salida.png> <módulo> [opciones]

var lab: MathLab
var ok: int = 0
var fail: int = 0

func check(cond: bool, name: String) -> void:
	if cond:
		ok += 1
		print("  [OK]   %s" % name)
	else:
		fail += 1
		print("  [FALLO] %s" % name)

func run() -> void:
	var ua := OS.get_cmdline_user_args()
	if "mflabshot" in ua:
		await _shot(ua)
		return
	print("[TEST] Laboratorio matemático...")
	await get_tree().process_frame
	for m in MathLab.MODULES:
		var fn := "_t_" + str(m["id"])
		lab.open_module(m["id"])
		await get_tree().process_frame
		check(lab.module != null and lab.module_id == m["id"], "Módulo «%s» abre" % m["nombre"])
		if has_method(fn):
			await call(fn)
	_t_expr()
	await _t_api()
	# Volver a MechaForge: la escena del simulador se conserva intacta.
	var tree := get_tree()
	var main_node: Node = lab.main_scene
	var n_parts: int = main_node.parts_root.get_child_count()
	get_parent().remove_child(self)
	tree.root.add_child(self)
	lab.go_back()
	await tree.process_frame
	await tree.process_frame
	check(tree.current_scene == main_node and main_node.is_inside_tree() and main_node.parts_root.get_child_count() == n_parts,
		"«← MechaForge» vuelve al simulador con su escena intacta")
	if _http_ok:
		var back: Dictionary = await _rpc("get_scene_state", {})
		check(back.has("result") and typeof(back["result"].get("piezas")) == TYPE_ARRAY,
			"API HTTP: tras volver del laboratorio la API sigue atendiendo (get_scene_state)")
	print("[TEST] Laboratorio: %d OK, %d FALLOS" % [ok, fail])
	tree.quit(1 if fail > 0 else 0)

# --- API del laboratorio para OpenClaw ------------------------------------------------

var _http_ok := false
var _ts: ToolServer

## Llamada JSON-RPC real por HTTP a la API local (como haría OpenClaw).
func _rpc(method: String, params: Dictionary) -> Dictionary:
	var ts := _ts
	var http := HTTPRequest.new()
	http.timeout = 5.0
	add_child(http)
	var body := JSON.stringify({"jsonrpc": "2.0", "id": 1, "method": method, "params": params})
	http.request("http://127.0.0.1:%d/rpc" % ts.port, ["Authorization: Bearer " + ts.token, "Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	var res: Array = await http.request_completed
	http.queue_free()
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"error": "http %d" % int(res[0])}
	var d = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	return d if typeof(d) == TYPE_DICTIONARY else {"error": "respuesta no JSON"}

func _t_api() -> void:
	var main_node: Node = lab.main_scene
	var api := SimulatorApi.new(main_node)
	var mods: Dictionary = api.call_tool("lab_list_modules", {})
	check(mods["modulos"].size() == MathLab.MODULES.size() and MathLab.MODULES.size() >= 16, "API: lab_list_modules devuelve los %d módulos" % MathLab.MODULES.size())
	var r: Dictionary = api.call_tool("lab_open", {"modulo": "coloreado"})
	check(not r.has("error") and lab.module_id == "coloreado", "API: lab_open cambia de módulo con el laboratorio abierto")
	var st: Dictionary = api.call_tool("lab_get_state", {})
	var js := JSON.stringify(st)
	check(st["abierto"] and st["modulo"] == "coloreado" and st["parametros"].size() >= 4 and not js.contains("Object#") and str(st["info"]).contains("Ceros"),
		"API: lab_get_state da fórmula, lecturas y %d controles (JSON limpio)" % st["parametros"].size())
	r = api.call_tool("lab_set_param", {"nombre": "f(z) =", "valor": "z^3 - 1"})
	check(r.get("ok", false) and lab.module.zeros.size() == 3, "API: lab_set_param cambia la función (z³ − 1 → 3 ceros)")
	r = api.call_tool("lab_set_param", {"nombre": "f(z) =", "valor": "z^^2 +"})
	check(r.has("error") and lab.module.zeros.size() == 3, "API: una expresión no válida se rechaza con su error")
	r = api.call_tool("lab_set_param", {"nombre": "no_existe", "valor": 1})
	check(r.has("error") and str(r["error"]).contains("disponibles"), "API: un control inexistente lista los disponibles")
	var smp: Dictionary = api.call_tool("lab_sample", {"x": 0.5, "y": 0.5})
	check(str(smp.get("lectura", "")).contains("f(z)"), "API: lab_sample lee f(z) en un punto")
	api.call_tool("lab_open", {"modulo": "raices"})
	r = api.call_tool("lab_set_param", {"nombre": "Comparar todos", "valor": true})
	var sti: Dictionary = api.call_tool("lab_get_state", {})
	check(r.get("ok", false) and str(sti["info"]).contains("Halley") and str(sti["info"]).contains("Brent"), "API: «Comparar todos los métodos» de raíces por nombre")
	var coords_ok := true
	for id in ["calor", "schrodinger", "optimizacion", "integracion", "fractales", "edp1d", "nolineal", "interp1d"]:
		api.call_tool("lab_open", {"modulo": id})
		var q: Dictionary = api.call_tool("lab_sample", {"x": 0.5, "y": 0.25})
		var lect := str(q.get("lectura", ""))
		if not lect.contains("0.5") or lect.contains("%"):
			coords_ok = false
			print("        ", id, ": ", lect.replace("\n", " / "))
	check(coords_ok, "API: lab_sample usa las mismas coordenadas que el tooltip de cada módulo")
	api.call_tool("lab_open", {"modulo": "onda"})
	r = api.call_tool("lab_set_param", {"nombre": "Frontera", "valor": "absorbente"})
	var fr: Dictionary = {}
	for q in LabApi.public_params(lab):
		if q["nombre"] == "Frontera":
			fr = q
	check(r.get("ok", false) and int(fr.get("valor", -1)) == 2, "API: elige una opción por su texto (frontera absorbente)")
	r = api.call_tool("lab_set_param", {"nombre": "Velocidad de onda c", "valor": 99})
	check(r.get("ok", false) and absf(float(r["valor"]) - 2.5) < 1e-6, "API: los deslizadores se limitan a su rango (c = 99 → 2.5)")
	lab.module.sim.Reset()
	var m0: float = lab.module.sim.MaxValue()
	r = api.call_tool("lab_perturb", {"x": 0.3, "y": -0.2})
	check(r.get("ok", false) and float(lab.module.sim.MaxValue()) > m0 + 0.05, "API: lab_perturb crea un pulso en la membrana")
	r = api.call_tool("lab_control", {"accion": "pausar"})
	var paused := not lab.playing
	api.call_tool("lab_control", {"accion": "reanudar"})
	api.call_tool("lab_control", {"accion": "velocidad", "valor": 3})
	check(paused and lab.playing and (lab.speed == 2.0 or lab.speed == 4.0), "API: lab_control pausa, reanuda y ajusta la velocidad")
	api.call_tool("lab_control", {"accion": "velocidad", "valor": 1})
	r = api.call_tool("get_scene_state", {})
	check(r.has("error") and str(r["error"]).contains("lab_close"), "API: con el laboratorio abierto la escena pide cerrarlo primero")
	# Servidor HTTP real: sigue vivo mientras el laboratorio ocupa la ventana.
	var ts: ToolServer = main_node.tool_server
	_ts = ts
	check(ts.is_inside_tree(), "API: el servidor local sigue en el árbol con el laboratorio abierto")
	if not ts.enabled:
		print("  [--]   API HTTP desactivada en la configuración: se omite la prueba de red")
		return
	if not ts.is_listening() and not ts.start():
		print("  [--]   Puerto %d ocupado (¿otra copia de MechaForge abierta?): se omite la prueba de red" % ts.port)
		return
	var h: Dictionary = await _rpc("lab_get_state", {})
	_http_ok = h.has("result") and str(h["result"].get("modulo", "")) == "onda"
	check(_http_ok, "API HTTP: lab_get_state responde por 127.0.0.1 con el laboratorio abierto")

## Captura del HUD de manos con manos sintéticas (sin cámara): la derecha pellizca y
## gira la gráfica; la izquierda está en reposo.
func _hands_demo(fists: bool = false) -> void:
	var ht = load("res://tests/HandTests.gd").new()
	lab.toggle_hands(false)
	var ctrl: VirtualLabController = lab.hands
	ctrl.use_defaults()
	ctrl.enabled = true
	ctrl.move_mouse = false
	ctrl.hud.visible = true
	ctrl.tracker.status_text = "Demostración con manos sintéticas (sin cámara)"
	var frames := []
	if fists:
		# Puños en 3D: se desplazan, se empujan hacia la pantalla y la derecha se adelanta (giro).
		for k in range(60):
			var u := minf(1.0, k / 45.0)
			frames.append(ht.fists3d(Vector3(0.06 * u, -0.03 * u, -0.12 * u), 0.72, -0.06 * u, Vector3(0.12 * u, 0, 0)))
	else:
		var hs := []
		for k in range(20):
			frames.append([["point", Vector2(0.46, 0.5)], ["fist", Vector2(0.3, 0.62)]])
		for k in range(10):
			frames.append([["pinch", Vector2(0.46, 0.5)], ["fist", Vector2(0.3, 0.62)]])
		for k in range(40):
			frames.append([["pinch", Vector2(0.46 + 0.0015 * k, 0.5 - 0.0005 * k)], ["fist", Vector2(0.3, 0.62)]])
		for f in frames:
			hs.append([ht.hand(f[0][0], f[0][1], "Right", 1.0, ctrl.recognizer), ht.hand(f[1][0], f[1][1], "Left", 1.0, ctrl.recognizer)])
		frames = hs
	for f in frames:
		ht.t += 1.0 / 60.0
		var pair := []
		for h in f:
			var c: Dictionary = (h as Dictionary).duplicate()
			c["t"] = ht.t
			pair.append(c)
		ctrl.tracker.hands = pair
		ctrl.tracker.last_packet = HandTracker.now()
		ctrl._on_hands(pair)
		await get_tree().process_frame
	ht.free()

func _shot(ua: PackedStringArray) -> void:
	var i := ua.find("mflabshot")
	var out: String = ua[i + 1]
	var id: String = ua[i + 2] if i + 2 < ua.size() else "onda"
	lab.open_module(id)
	var extra := ua.slice(i + 3)
	await get_tree().process_frame
	if lab.module.has_method("demo"):
		await lab.module.demo(extra)
	if "manos" in extra:
		await _hands_demo("punos" in extra)
		if "panel" in extra:
			lab.hands.panel.visible = true
			lab.hands.panel.set_collapsed(false)
			lab.hands.panel.position = Vector2(lab.get_viewport().get_visible_rect().size.x - 620, 56)
	if "teclado" in extra:
		await get_tree().process_frame
		for bt in lab.params_box.find_children("*", "Button", true, false):
			if (bt as Button).text == "⌨":
				(bt as Button).button_pressed = true
				break
	if "superior" in extra:
		lab.set_view(LabCamera.ViewMode.SUPERIOR)
	if "iso" in extra:
		lab.set_view(LabCamera.ViewMode.ISOMETRICA)
	if "corte" in extra:
		lab.clip_on = Vector3(1, 0, 0)
		lab.clip_pos = Vector3(0.2, 0, 0)
		lab._apply_clip()
	await get_tree().create_timer(float(extra[extra.find("t") + 1]) if "t" in extra else 2.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("[LABSHOT] %s" % out)
	get_tree().quit()

# --- Motor de expresiones ------------------------------------------------------------

func _t_expr() -> void:
	var e := MathExpr.parse("2x^2 - 3(x+1) + sin(pi/2)", ["x"])
	check(e.ok() and absf(e.eval_real({"x": 2.0}) - (8.0 - 9.0 + 1.0)) < 1e-9, "Expresión: multiplicación implícita, potencia y constantes")
	check(absf(MathExpr.parse("-x^2", ["x"]).eval_real({"x": 3.0}) + 9.0) < 1e-9, "Expresión: −x² = −(x²)")
	var oc := MathExpr.parse("sin(x", ["x"])
	check(oc.ok() and absf(oc.eval_real({"x": 0.5}) - sin(0.5)) < 1e-12 and not oc.notes.is_empty(), "Expresión: el paréntesis sin cerrar se cierra solo y se avisa («%s»)" % " ".join(PackedStringArray(oc.notes)))
	check(not MathExpr.parse("sin(x))", ["x"]).ok(), "Expresión: un «)» de más se detecta")
	check(not MathExpr.parse("foo(x)", ["x"]).ok(), "Expresión: nombre desconocido se detecta")
	var c := MathExpr.parse("(z^2 + 1)/(z - i)", ["z"], true)
	var zc := Vector2(1.0, 2.0)
	var expect := MathExpr.cdiv(MathExpr.cmul(zc, zc) + Vector2(1, 0), zc - Vector2(0, 1))
	check(c.ok() and c.eval_c({"z": zc}).distance_to(expect) < 1e-6, "Expresión compleja: (z² + 1)/(z − i)")
	check(MathExpr.parse("exp(i*pi)", ["z"], true).eval_c({}).distance_to(Vector2(-1, 0)) < 1e-6, "Identidad de Euler: e^{iπ} = −1 (precisión simple de Vector2)")
	var f := MathExpr.parse("x*y + cos(x)", ["x", "y"])
	check(f.compile_fast() and absf(f.eval_fast([1.5, 2.0]) - (3.0 + cos(1.5))) < 1e-6, "Evaluación rápida (Expression nativa) coincide")
	var g := f.to_glsl({"x": "p.x", "y": "p.y"})
	check(g.contains("p.x") and g.contains("cos("), "Traducción a GLSL real: %s" % g)
	check(c.to_glsl_complex({"z": "z"}).contains("cx_div("), "Traducción a GLSL complejo")
	_t_notation()

## Notación cómoda: se escribe como en papel.
func _t_notation() -> void:
	var X := 0.7
	var cases := [["sen x", sin(X)], ["sin 2x", sin(2 * X)], ["sin x cos x", sin(X) * cos(X)], ["sin^2 x + cos^2 x", 1.0],
		["cos²x", cos(X) * cos(X)], ["x² + e⁻ˣ", X * X + exp(-X)], ["√(x+1)", sqrt(X + 1)], ["2√x", 2 * sqrt(X)], ["∛8", 2.0],
		["sinx", sin(X)], ["xsinx", X * sin(X)], ["sen2x", sin(2 * X)], ["0,5x", 0.5 * X], ["ln|x - 2|", log(absf(X - 2))],
		["exp^(-x)", exp(-X)], ["e^-x^2", exp(-X * X)], ["log_2 8", 3.0], ["arcsen x", asin(X)], ["sin^-1 x", asin(X)],
		["2πx", TAU * X], ["x|x|", X * absf(X)], ["½x", 0.5 * X], ["raíz(x)", sqrt(X)], ["tg x", tan(X)], ["2 sin x", 2 * sin(X)],
		["max(1,2)", 2.0], ["x·(x−1)", X * (X - 1)]]
	var bad := []
	for c in cases:
		var m := MathExpr.parse(c[0], ["x"])
		if not m.ok() or absf(m.eval_real({"x": X}) - float(c[1])) > 1e-9:
			bad.append("%s (%s)" % [c[0], m.error if not m.ok() else str(m.eval_real({"x": X}))])
	check(bad.is_empty(), "Notación cómoda: %d expresiones como en papel (sen x, sin 2x, x², e⁻ˣ, √x, sinx, 0,5x, log_2 8, arcsen x, 2πx…) %s" % [cases.size(), str(bad) if not bad.is_empty() else ""])
	var sug := MathExpr.parse("sn(x)", ["x"])
	check(not sug.ok() and sug.error.contains("«sin»"), "Notación: un nombre mal escrito sugiere el correcto («%s»)" % sug.error)
	var pretty := [["exp(-(x^2+y^2))", "e^(−(x² + y²))"], ["2*x^2", "2x²"], ["sqrt(x+1)", "√(x + 1)"], ["abs(x)", "|x|"], ["e^(2x)", "e²ˣ"], ["1/(1+25x^2)", "1/(1 + 25x²)"]]
	var badp := []
	for q in pretty:
		var pp := MathExpr.parse(q[0], ["x", "y"]).to_pretty()
		if pp != q[1]:
			badp.append("%s → %s" % [q[0], pp])
	check(badp.is_empty(), "Notación: vista previa legible (e^(−(x² + y²)), 2x², √(x + 1), |x|, e²ˣ) %s" % str(badp))
	var rt := true
	for q in ["e^(-x²) sin 3x", "x^x", "1/(1+25x²)", "|x - 1| + √x", "log_2 x"]:
		var m1 := MathExpr.parse(q, ["x"])
		var m2 := MathExpr.parse(m1.to_text(), ["x"])
		rt = rt and m2.ok() and absf(m1.eval_real({"x": X}) - m2.eval_real({"x": X})) < 1e-12
	check(rt, "Notación: to_text() se vuelve a leer igual")
	# Derivada simbólica, diferenciación automática y paso complejo coinciden.
	var dbad := []
	for q in ["sin(x²)", "x³ - 2x", "e^(-x²) sin 3x", "ln x", "1/(1 + 25x²)", "x^x", "√(x² + 1)", "tan x", "atan x", "asin x", "cosh x", "cbrt(x)", "|x|"]:
		var m := MathExpr.parse(q, ["x"])
		var d := m.derivative("x")
		var dd := d.derivative("x")
		var j := m.eval_jet({"x": X}, "x")
		var cs: float = float(m.eval_cd({"x": [X, 1e-20]})[1]) / 1e-20
		var sym := d.eval_real({"x": X})
		if absf(sym - float(j[1])) > 1e-10 or absf(cs - float(j[1])) > 1e-10 or absf(dd.eval_real({"x": X}) - float(j[2])) > 1e-9:
			dbad.append("%s: simb %.10f, AD %.10f, paso complejo %.10f" % [q, sym, float(j[1]), cs])
	check(dbad.is_empty(), "Derivadas: simbólica, automática (f′ y f″) y paso complejo coinciden en 13 funciones %s" % str(dbad))
	check(MathExpr.parse("sin(x^2)", ["x"]).derivative("x").to_pretty() == "2x·cos(x²)" and MathExpr.parse("sqrt(x^2+1)", ["x"]).derivative("x").to_pretty() == "x/√(x² + 1)",
		"Derivada simbólica simplificada: d/dx sin(x²) = %s; d/dx √(x² + 1) = %s" % [MathExpr.parse("sin(x^2)", ["x"]).derivative("x").to_pretty(), MathExpr.parse("sqrt(x^2+1)", ["x"]).derivative("x").to_pretty()])
	var fz := MathExpr.parse("asinh(x) + log_2(x) + atanh(x/2)", ["x"])
	check(fz.compile_fast() and absf(fz.eval_fast([X]) - fz.eval_real({"x": X})) < 1e-12, "Funciones nuevas (asinh, atanh, log_2) también en la evaluación rápida")

# --- Pruebas por módulo ---------------------------------------------------------------

func _t_onda() -> void:
	var m = lab.module
	m.sim.Reset()
	m.sim.ClearSources()
	m.sim.SetParam("amortiguamiento", 0.0)
	m.sim.SetParam("frontera", 0)
	m.sim.Perturb(0.5, 0.5, 0.4, 0.04)
	var e0: float = m.sim.Energy()
	m.sim.Step(0.02, 50)
	e0 = m.sim.Energy()
	for k in range(40):
		m.sim.Step(0.02, 50)
	var e1: float = m.sim.Energy()
	check(absf(e1 - e0) / e0 < 0.08, "Onda: sin amortiguamiento la energía se conserva (%.4f → %.4f)" % [e0, e1])
	check(absf(float(m.sim.Sample(0.5, 0.5).x)) < 0.35, "Onda: el pulso se propaga desde el centro")
	m.sim.NormalMode(1, 1, 0.3)
	var a0: float = m.sim.Sample(0.5, 0.5).x
	check(absf(float(m.sim.Sample(0.02, 0.5).x)) < 0.02 and a0 > 0.29, "Onda: modo (1,1) con los bordes fijos y máximo en el centro")
	var hit = m.pick(Vector3(0.3, 6.0, 0.2), Vector3(0, -1, 0))
	check(hit != null and absf(hit.x - 0.3) < 1e-3, "Onda: el rayo del ratón encuentra la membrana")
	check(m.hover_text(hit).contains("u ="), "Onda: tooltip con coordenadas y valor")

func _t_calor() -> void:
	var m = lab.module
	m.sim.ClearHeatSources()
	m.sim.FillMaterial(1.11e-4)
	m.sim.Reset()
	m.sim.FillMaterial(1.11e-4)
	m.sim.SetParam("borde_calor", 0)
	m.sim.Perturb(0.5, 0.5, 100.0, 0.03)
	var t0: float = m.sim.ValueAt(0.5, 0.5)
	var far0: float = m.sim.ValueAt(0.62, 0.5)
	m.sim.Step(5.0, 3000)
	check(float(m.sim.ValueAt(0.5, 0.5)) < t0 and float(m.sim.ValueAt(0.62, 0.5)) > far0, "Calor: el calor se difunde del centro hacia fuera (%.1f → %.1f °C)" % [t0, float(m.sim.ValueAt(0.5, 0.5))])
	# Madera frente a cobre: la madera apenas conduce.
	m.sim.Reset()
	m.sim.FillMaterial(8.2e-8)
	m.sim.Perturb(0.5, 0.5, 100.0, 0.03)
	var w0: float = m.sim.ValueAt(0.56, 0.5)
	m.sim.Step(5.0, 3000)
	check(absf(float(m.sim.ValueAt(0.56, 0.5)) - w0) < 1.0, "Calor: la madera (α = 8·10⁻⁸) casi no conduce en 5 s")
	check(m.hover_text(Vector3(0, 0, 0)).contains("°C"), "Calor: tooltip con la temperatura y el material")

func _t_schrodinger() -> void:
	var m = lab.module
	m.sim.SetPotential("libre", 0.0, 0.5)
	m.sim.InitPacket(0.3, 0.5, 3.0, 0.0, 1.0)
	var n0: float = m.sim.Norm()
	var x0: float = m.sim.ExpectedPosition().x
	m.sim.Step(1.0, 2000)
	var n1: float = m.sim.Norm()
	var x1: float = m.sim.ExpectedPosition().x
	check(absf(n0 - 1.0) < 1e-3 and absf(n1 - 1.0) < 1e-2, "Schrödinger: norma conservada (%.4f → %.4f)" % [n0, n1])
	check(absf((x1 - x0) - 3.0) < 0.35, "Schrödinger: el paquete avanza a la velocidad de grupo v = ħk/m = 3 (Δx = %.2f)" % (x1 - x0))
	# Efecto túnel: con E < V₀ algo atraviesa, y menos si la barrera es más ancha.
	var trans := []
	for w in [0.4, 1.0]:
		m.sim.SetPotential("barrera", 5.0, w)
		m.sim.InitPacket(0.25, 0.5, 3.0, 0.0, 1.0)
		m.sim.Step(3.5, 6000)
		trans.append(float(m.sim.ProbabilityBeyond(0.5 + w / 20.0)))
	# En vivo: el módulo guarda el máximo transmitido aunque el borde lo absorba.
	m.preset = 1
	m.v0 = 5.0
	m.width = 0.4
	m.k0 = 3.0
	m._launch()
	var ts0: float = m.sim.Time
	while float(m.sim.Time) < ts0 + 10.0:
		m.step(0.05)
	check(m.trans_max > 0.3 and float(m.sim.ProbabilityBeyond(0.52)) < m.trans_max, "Schrödinger: el panel conserva T máx. = %.1f %% aunque el borde absorba el paquete" % (m.trans_max * 100.0))
	check(trans[0] > 0.01 and trans[0] > trans[1] * 2.0, "Schrödinger: efecto túnel con E ≈ 4.5 < V₀ = 5 (T = %.1f %% con a = 0.4; %.1f %% con a = 1.0)" % [trans[0] * 100.0, trans[1] * 100.0])

func _t_graficas() -> void:
	var m = lab.module
	var r: Dictionary = m.load_spec({"funciones": ["x^2 - 2", "y = sin x"], "x": [-3, 3], "titulo": "Prueba"})
	check(r["ok"] and m.tipo == 0 and m.f_text[1] == "sin x" and m.planar(), "Gráficas: dos funciones con load_spec («y =» se quita)")
	var roots := []
	var mins := []
	var cuts := []
	for mk in m.marks:
		if int(mk["f"]) == 0 and mk["tipo"] == "raíz":
			roots.append(float(mk["x"]))
		elif int(mk["f"]) == 0 and mk["tipo"] == "mínimo":
			mins.append(Vector2(mk["x"], mk["y"]))
		elif mk["tipo"] == "corte":
			cuts.append(float(mk["x"]))
	roots.sort()
	check(roots.size() == 2 and absf(roots[0] + sqrt(2.0)) < 1e-9 and absf(roots[1] - sqrt(2.0)) < 1e-9, "Gráficas: raíces de x² − 2 en ±√2")
	check(mins.size() == 1 and (mins[0] as Vector2).distance_to(Vector2(0, -2)) < 1e-6, "Gráficas: mínimo de x² − 2 en (0, −2)")
	var cuts_ok := cuts.size() == 2
	for x in cuts:
		cuts_ok = cuts_ok and absf(x * x - 2.0 - sin(x)) < 1e-9
	check(cuts_ok, "Gráficas: los dos cortes de x² − 2 con sin x")
	check("raíces x = -1.4142, 1.4142" in LabApi.plain(m.info()) and m.critical_points().size() == m.marks.size(),
		"Gráficas: raíces en el panel de información y como puntos críticos")
	var hit: Vector3 = m.api_points(1.0, 0.5)[0]
	var ht: String = m.hover_text(hit)
	check("x = 1.0000" in ht and "f₁(x) = -1.000000" in ht and "f₂(x) = 0.841471" in ht, "Gráficas: lectura flotante con f₁ y f₂ en x")
	m.load_preset(3)
	var tan_ok := true
	var n_tan := 0
	for mk in m.marks:
		if mk["tipo"] == "raíz":
			n_tan += 1
			tan_ok = tan_ok and absf(tan(float(mk["x"]))) < 1e-9
	check(tan_ok and n_tan == 5, "Gráficas: tan x en [−2π, 2π] tiene 5 raíces y las asíntotas no cuentan como raíces")
	var fake_ext: int = m.marks.filter(func(mk): return mk["tipo"] in ["máximo", "mínimo"]).size()
	check(fake_ext == 0, "Gráficas: las asíntotas de tan x tampoco cuentan como máximos o mínimos")
	r = m.load_spec({"parametrica": {"x": "cos t", "y": "sin t", "t": [0, "2pi"]}})
	var aspect: float = (m.win["x1"] - m.win["x0"]) / (m.win["y1"] - m.win["y0"])
	check(r["ok"] and m.tipo == 1 and absf(aspect - 3.2 / 1.9) < 1e-6, "Gráficas: paramétrica con la misma escala en los dos ejes")
	r = m.load_spec({"polar": {"r": "1 + cos θ", "t": [0, "2pi"]}})
	check(r["ok"] and m.tipo == 2 and m.r_text == "1 + cos t" and m.win["x0"] < 0.0, "Gráficas: polar r(θ) (θ se escribe como t)")
	m.load_spec({"polar": {"r": "t + tan(t/8)", "t": [0, 4]}})
	check("θ + tan(θ/8)" in m.formula().replace(" ", " "), "Gráficas: la fórmula polar muestra θ sin tocar «tan» (%s)" % m.formula())
	r = m.load_spec({"superficie": "z = x^2 - y^2", "x": [-2, 2], "y": [-2, 2]})
	await get_tree().process_frame
	check(r["ok"] and m.tipo == 3 and not m.planar() and m.surf_mesh.visible and absf(m.zr.x + 4.0) < 1e-6 and absf(m.zr.y - 4.0) < 1e-6,
		"Gráficas: superficie z = x² − y² con rango z ∈ [−4, 4]")
	r = m.load_spec({"funciones": ["x^^2", "cos x"], "x": ["-pi", "pi"]})
	check(not r["ok"] and r["errores"].size() == 1 and m.f_text[0] == "cos x" and absf(m.xr.x + PI) < 1e-6,
		"Gráficas: una fórmula mal escrita se omite y se avisa; intervalo con «-pi»")
	var pts: Array = m.parse_points("(1, 2); (3, 4.5)\n5 6")
	check(pts == [Vector2(1, 2), Vector2(3, 4.5), Vector2(5, 6)], "Gráficas: puntos «(x, y); …» o uno por línea")
	r = m.load_spec({"puntos": [[0, 1], [2, 3], {"x": 4, "y": -1}]})
	check(m.puntos.size() == 3 and m.xr.x < 0.0 and m.xr.y > 4.0, "Gráficas: solo datos, la ventana abarca los puntos")
	# Controles como los usa la API (lab_set_param).
	m.load_preset(0)
	await get_tree().process_frame
	var s1 := LabApi.set_param(lab, "f₂(x) =", "")
	await get_tree().process_frame
	check(s1.get("ok", false) and m.f_expr[1] == null, "Gráficas: un campo de función opcional se puede vaciar")
	var s2 := LabApi.set_param(lab, "Puntos (x, y)", "(0, 0); (1, 1)")
	await get_tree().process_frame
	check(s2.get("ok", false) and m.puntos.size() == 2, "Gráficas: campo de texto «Puntos (x, y)» desde la API")
	m.perturb(m.api_points(2.0, 2.0)[0], true)
	check(m.puntos.size() == 3 and (m.puntos[2] as Vector2).distance_to(Vector2(2, 2)) < 0.01, "Gráficas: clic con «Perturbar» añade el punto (x, y)")
	var api := SimulatorApi.new(lab.main_scene)
	var rp: Dictionary = api.call_tool("lab_plot", {"funciones": ["x^3 - x"], "x": [-2, 2]})
	check(rp.get("ok", false) and rp["marcas"].size() >= 5 and "raíces x = -1, 0, 1" in str(rp["info"]),
		"API lab_plot: dibuja y devuelve raíces y extremos (x³ − x)")
	await get_tree().process_frame

func _t_raices() -> void:
	var m = lab.module
	var orders := {}
	for meth in [0, 1, 2, 3]:
		m.method = meth
		m._rebuild_curve()
		m.reset()
		for k in range(60):
			if not m.do_step():
				break
		var last: Dictionary = m.hist[m.hist.size() - 1]
		check(absf(float(last["x"]) - 2.0945514815423265) < 1e-8, "Raíces: %s converge a 2.0945514815 (%d iteraciones)" % [m.METHODS[meth], m.hist.size() - 1])
		orders[meth] = m.hist.size() - 1
	check(orders[1] < orders[2] and orders[2] < orders[0], "Raíces: Newton (%d) < secante (%d) < bisección (%d) iteraciones" % [orders[1], orders[2], orders[0]])
	m.method = 1
	m.reset()
	for k in range(5): m.do_step()
	check(absf(m._order() - 2.0) < 0.3, "Raíces: orden observado de Newton ≈ 2 (%.2f)" % m._order())
	# Los quince métodos desde los mismos datos (ejemplo de Wallis).
	m.load_preset(0)
	m._compare_all()
	var bad := []
	for row in m.cmp_rows:
		if str(row["estado"]) != "ok" or absf(float(row["x"]) - 2.0945514815423265) > 1e-8:
			bad.append("%s (%s)" % [m.SHORT[int(row["m"])], row["estado"]])
	check(bad.is_empty() and m.cmp_rows.size() == 15, "Raíces: los 15 métodos convergen a la raíz de Wallis %s" % (", ".join(bad) if not bad.is_empty() else ""))
	var P := {}
	var IT := {}
	for row in m.cmp_rows:
		P[int(row["m"])] = float(row.get("p", NAN))
		IT[int(row["m"])] = int(row.get("iter", 999))
	check(P[9] > 2.4 and P[10] > 2.4 and absf(P[1] - 2.0) < 0.4 and P[2] > 1.35 and P[2] < 1.95 and P[11] > 1.6,
		"Raíces: órdenes observados Halley %.2f · Chebyshev %.2f · Newton %.2f · secante %.2f · Steffensen %.2f" % [P[9], P[10], P[1], P[2], P[11]])
	check(IT[7] < IT[0] and IT[5] < IT[4] and IT[6] < IT[0] and IT[14] < IT[3],
		"Raíces: Brent (%d) y Ridders (%d) < bisección (%d); Illinois (%d) < regula falsi (%d); Aitken (%d) < punto fijo (%d)" % [IT[7], IT[6], IT[0], IT[5], IT[4], IT[14], IT[3]])
	# Raíz triple: Newton se vuelve lineal y la versión para raíces múltiples no.
	m.load_preset(3)
	var hn: Array = m.run_full(1)
	var hm: Array = m.run_full(8)
	var pn: float = m.order_of(m._errors_of(hn, 1.0))
	check(hm.size() < hn.size() / 3 and absf(float(hm[hm.size() - 1]["x"]) - 1.0) < 1e-5 and absf(pn - 1.0) < 0.15,
		"Raíces: en (x − 1)³ Newton es lineal (p = %.2f, %d it.) y Newton para raíces múltiples converge en %d" % [pn, hn.size() - 1, hm.size() - 1])
	# Sin cambio de signo, los métodos de intervalo no se aplican.
	m.load_preset(2)
	m.a0 = 0.7
	m.b0 = 1.2
	m._compare_all()
	var na := 0
	for row in m.cmp_rows:
		if str(row["estado"]).begins_with("sin cambio"):
			na += 1
	check(not m.bracket_ok() and na == 5, "Raíces: sin cambio de signo en [a, b] los 5 métodos de intervalo no se aplican")
	check(m.roots.size() == 2, "Raíces: eˣ − 3x tiene dos raíces en el dominio (%d)" % m.roots.size())

func _t_sistemas() -> void:
	var m = lab.module
	var s: Vector3 = m.sol
	check(m.residual(s).length() < 1e-5, "Sistemas: la solución por eliminación anula el residuo")
	var jv: Vector3 = m.jac[m.jac.size() - 1]
	var g: Vector3 = m.gs[m.gs.size() - 1]
	check(m.residual(g).length() < m.residual(jv).length(), "Sistemas: Gauss-Seidel converge más rápido que Jacobi")
	check(m.spectral_radius(false) < 1.0 and m.spectral_radius(true) < m.spectral_radius(false), "Sistemas: ρ_GS (%.3f) < ρ_J (%.3f) < 1" % [m.spectral_radius(true), m.spectral_radius(false)])
	# SPD alargada: gradiente conjugado, SOR óptimo, Richardson y factorizaciones.
	m.A = [[10.0, 2.0, 0.0], [2.0, 3.0, 1.0], [0.0, 1.0, 1.0]]
	m.b = [12.0, 4.0, -1.0]
	m.n_iter = 30
	m._rebuild()
	var kcg: int = m.iterations_to(5, 1e-9)
	var ksd: int = m.iterations_to(4, 1e-9)
	check(kcg >= 1 and kcg <= 3 and (ksd < 0 or ksd > kcg), "Sistemas: gradiente conjugado resuelve el 3×3 SPD en %d pasos (descenso: %s)" % [kcg, str(ksd) if ksd >= 0 else "> 30"])
	m.omega = m.omega_opt()
	m._rebuild()
	check(m.spectral_radius_of(2) < m.spectral_radius_of(1) and absf(m.spectral_radius_of(2) - (m.omega - 1.0)) < 0.03,
		"Sistemas: SOR con ω óptimo = %.3f: ρ_SOR = %.3f ≈ ω − 1 < ρ_GS = %.3f" % [m.omega, m.spectral_radius_of(2), m.spectral_radius_of(1)])
	var ev: Array = m.sym_eigenvalues(m.A)
	var kap: float = float(ev[2]) / float(ev[0])
	check(absf(m.spectral_radius_of(3) - (kap - 1.0) / (kap + 1.0)) < 0.02, "Sistemas: Richardson con α óptimo tiene ρ = (κ − 1)/(κ + 1) = %.3f" % ((kap - 1.0) / (kap + 1.0)))
	var f = m.lu()
	var lu_ok := f != null
	if lu_ok:
		for i in range(3):
			for j in range(3):
				var sm := 0.0
				for k in range(3):
					sm += float(f[1][i][k]) * float(f[2][k][j])
				if absf(sm - float(m.A[int(f[0][i])][j])) > 1e-9:
					lu_ok = false
	check(lu_ok, "Sistemas: factorización PA = LU")
	var L = m.cholesky()
	var ch_ok := L != null
	if ch_ok:
		for i in range(3):
			for j in range(3):
				var sm2 := 0.0
				for k in range(3):
					sm2 += float(L[i][k]) * float(L[j][k])
				if absf(sm2 - float(m.A[i][j])) > 1e-9:
					ch_ok = false
	check(ch_ok, "Sistemas: Cholesky A = LLᵀ en la matriz SPD")
	var q = m.qr()
	var qr_ok := q != null
	if qr_ok:
		for i in range(3):
			for j in range(3):
				var sm3 := 0.0
				var dot := 0.0
				for k in range(3):
					sm3 += float(q[0][i][k]) * float(q[1][k][j])
					dot += float(q[0][k][i]) * float(q[0][k][j])
				if absf(sm3 - float(m.A[i][j])) > 1e-9 or absf(dot - (1.0 if i == j else 0.0)) > 1e-9:
					qr_ok = false
	check(qr_ok, "Sistemas: QR con Q ortogonal y QR = A")
	var fin: Array = m.elim_states[m.elim_states.size() - 1]
	var id_ok: bool = m.elim_states.size() == 6
	for i in range(3):
		for j in range(3):
			if absf(float(fin[0][i][j]) - (1.0 if i == j else 0.0)) > 1e-9:
				id_ok = false
		if absf(float(fin[1][i]) - float(m.sol[i])) > 1e-9:
			id_ok = false
	check(id_ok, "Sistemas: la eliminación de Gauss-Jordan acaba en I·x = x* (planos x, y, z = constante)")
	m.A = [[1.0, 2.0, -1.0], [2.0, 1.0, 1.0], [1.0, 1.0, 1.0]]
	m.b = [2.0, 3.0, 1.0]
	m._rebuild()
	check(m.cholesky() == null and m.iterations_to(5) >= 0, "Sistemas: sin simetría no hay Cholesky; el gradiente conjugado sobre AᵀA sí converge")
	check(m.spectral_radius(false) > 1.0, "Sistemas: sin dominancia, ρ_J = %.2f > 1 → Jacobi diverge" % m.spectral_radius(false))

func _t_optimizacion() -> void:
	var m = lab.module
	var n: Vector2 = m.nt_path[m.nt_path.size() - 1]
	check(n.distance_to(Vector2(1, 1)) < 1e-3, "Optimización: Newton alcanza el mínimo de Rosenbrock (1, 1) en %d pasos" % (m.nt_path.size() - 1))
	m.preset = 0
	m._load_preset(0)
	var g: Vector2 = m.gd_path[m.gd_path.size() - 1]
	check(g.length() < 1e-3, "Optimización: el gradiente descendente llega al mínimo del cuenco (%.4f, %.4f)" % [g.x, g.y])
	check(m.pick(Vector3(0.2, 8.0, 0.1), Vector3(0, -1, 0)) != null, "Optimización: el ratón encuentra la superficie z = f(x, y)")

func _t_interpolacion() -> void:
	var m = lab.module
	var sp: PackedVector3Array = m.spline_points(40)
	var ok := true
	for i in range(m.ctrl.size()):
		var best := INF
		for q in sp: best = minf(best, q.distance_to(m.ctrl[i]))
		if best > 1e-4: ok = false
	check(ok, "Interpolación: el spline pasa exactamente por los puntos de control")
	m.mode = 1
	m.noise = 0.0
	m._gen_data()
	check(m.r2 > 0.99999, "Ajuste: sin ruido la cuádrica recupera los datos (R² = %.6f)" % m.r2)
	m.noise = 0.3
	m._gen_data()
	check(m.r2 < 0.99 and m.r2 > 0.3, "Ajuste: con ruido R² = %.3f" % m.r2)
	var bs: PackedVector3Array = m.bspline_points()
	var bz: PackedVector3Array = m.bezier_points()
	var c0: Vector3 = m.ctrl[0]
	var cn: Vector3 = m.ctrl[m.ctrl.size() - 1]
	check(bs[0].distance_to(c0) < 1e-5 and bs[bs.size() - 1].distance_to(cn) < 1e-5 and bz[0].distance_to(c0) < 1e-5 and bz[bz.size() - 1].distance_to(cn) < 1e-5,
		"Interpolación: B-spline y Bézier empiezan y acaban en los puntos extremos")
	m.mode = 2
	var rms := []
	var interp_ok := true
	for k in range(6):
		m.sc_method = k
		m._fit_scattered()
		rms.append(m.sc_rms)
		if k != 4:
			for dq in m.sc_data:
				if absf(m.sc_eval(dq.x, dq.y) - dq.z) > 1e-6:
					interp_ok = false
	check(interp_ok, "Datos dispersos: IDW, las tres RBF y Delaunay pasan por todos los datos")
	check(float(rms[3]) < float(rms[0]) and float(rms[3]) < float(rms[4]), "Datos dispersos: thin-plate (RMS %s) mejora a IDW (%s) y al vecino más cercano (%s)" % [LabUI.sci(rms[3], 2), LabUI.sci(rms[0], 2), LabUI.sci(rms[4], 2)])

func _t_nolineal() -> void:
	var m = lab.module
	m.load_preset(0)
	check(m.roots.size() == 2, "No lineales: círculo y parábola se cortan en %d puntos (2)" % m.roots.size())
	var pn: Array = m.paths[0]
	var ln: Array = pn[pn.size() - 1]
	var xs := sqrt((1.0 + sqrt(13.0)) * 0.5)
	check(m.norm_F(ln[0], ln[1]) < 1e-10 and absf(float(ln[0]) - xs) < 1e-8 and pn.size() - 1 <= 8 and absf(m.order_of(pn) - 2.0) < 0.4,
		"No lineales: Newton llega a (%.6f, %.6f) en %d iteraciones con p ≈ %.2f" % [ln[0], ln[1], pn.size() - 1, m.order_of(pn)])
	var ok_all := true
	var names := []
	for k in [1, 2, 6]:
		var pk: Array = m.paths[k]
		var lk: Array = pk[pk.size() - 1]
		if m.norm_F(lk[0], lk[1]) > 1e-9:
			ok_all = false
			names.append(m.SHORT[k])
	var pb: float = m.order_of(m.paths[2])
	check(ok_all and pb > 1.1 and pb < 2.1, "No lineales: Newton amortiguado, Broyden (p ≈ %.2f, superlineal) y Levenberg–Marquardt convergen %s" % [pb, str(names) if not ok_all else ""])
	m.n_iter = 150
	m._compute_paths()
	var pf: Array = m.paths[3]
	var lf: Array = pf[pf.size() - 1]
	check(m.norm_F(lf[0], lf[1]) < 1e-9 and pf.size() > 20, "No lineales: punto fijo converge linealmente (%d iteraciones)" % (pf.size() - 1))
	m.load_preset(1)
	m._compute_paths()
	var pf2: Array = m.paths[3]
	var lf2: Array = pf2[pf2.size() - 1]
	check(absf(float(lf2[0]) - 1.0) < 1e-8 and absf(float(lf2[1]) - 1.0) < 1e-8, "No lineales: punto fijo de Burden–Faires converge a (1, 1)")
	m.load_preset(2)
	check(m.roots.size() == 3 and m.hover_text(m.api_points(0.9, 0.1)[0]).contains("Newton → x*"), "No lineales: z³ = 1 tiene 3 soluciones y el tooltip dice a cuál lleva Newton")
	check(m.basin_mat != null and m.basin_mat.shader.code.contains("F(vec2 p)"), "No lineales: shader de cuencas generado a partir de f₁ y f₂")

func _t_interp1d() -> void:
	var m = lab.module
	m.load_function(0)
	m.n = 11
	m.node_kind = 0
	m.rebuild()
	var e_eq: float = m.errs[0]["max"]
	var l_eq: float = m.lebesgue
	var e_fh: float = m.errs[10]["max"]
	m.node_kind = 1
	m.rebuild()
	var e_ch: float = m.errs[0]["max"]
	var l_ch: float = m.lebesgue
	check(e_eq > 1.0 and e_ch < 0.15, "Interpolación 1D: Runge con 11 nodos: equiespaciados ‖f − p‖∞ = %.2f; Chebyshev %.3f" % [e_eq, e_ch])
	check(l_eq > 10.0 * l_ch and l_ch < 3.0, "Interpolación 1D: constante de Lebesgue %.1f (equiespaciados) frente a %.2f (Chebyshev)" % [l_eq, l_ch])
	check(e_fh < e_eq / 5.0, "Interpolación 1D: Floater–Hormann evita Runge con nodos equiespaciados (%.3f)" % e_fh)
	var pass_ok := true
	var fails := []
	for k in range(12):
		for i in range(m.n):
			if absf(m.eval_method(k, m.xs[i]) - float(m.ys[i])) > 1e-8:
				pass_ok = false
				if not fails.has(m.SHORT[k]):
					fails.append(m.SHORT[k])
	check(pass_ok, "Interpolación 1D: los 12 métodos de interpolación pasan por los nodos %s" % (str(fails) if not pass_ok else ""))
	var same := true
	for i in range(50):
		var x := lerpf(-1.0, 1.0, i / 49.0)
		if absf(m.eval_method(0, x) - m.eval_method(1, x)) > 1e-8:
			same = false
	check(same, "Interpolación 1D: Newton (diferencias divididas) y Lagrange son el mismo polinomio")
	m.load_function(4)
	m.node_kind = 0
	m.n = 10
	m.rebuild()
	var e_nat: float = m.errs[4]["max"]
	var e_cl: float = m.errs[5]["max"]
	var e_lin10: float = m.errs[2]["max"]
	var e_cl10: float = e_cl
	m.n = 19
	m.rebuild()
	var r_lin: float = e_lin10 / float(m.errs[2]["max"])
	var r_cl: float = e_cl10 / float(m.errs[5]["max"])
	check(e_cl < e_nat / 5.0, "Interpolación 1D: con eˣ el spline sujeto (%s) mejora al natural (%s) en los bordes" % [LabUI.sci(e_cl, 2), LabUI.sci(e_nat, 2)])
	check(r_lin > 3.0 and r_lin < 5.5 and r_cl > 10.0 and r_cl < 24.0, "Interpolación 1D: al dividir h entre 2 el error lineal baja ×%.1f (h²) y el del spline ×%.1f (h⁴)" % [r_lin, r_cl])
	m.load_function(m.FUNCS.size() - 1)
	var lo := INF
	var hi := -INF
	var slo := INF
	var shi := -INF
	for i in range(401):
		var x := lerpf(m.a, m.b, i / 400.0)
		lo = minf(lo, m.eval_method(8, x))
		hi = maxf(hi, m.eval_method(8, x))
		slo = minf(slo, m.eval_method(4, x))
		shi = maxf(shi, m.eval_method(4, x))
	check(lo >= -1e-9 and hi <= 1.0 + 1e-9 and (shi > 1.02 or slo < -0.02), "Interpolación 1D: con datos en escalón PCHIP no se sale de [0, 1] y el spline natural sí (%.3f … %.3f)" % [slo, shi])

func _t_integracion() -> void:
	var m = lab.module
	var exact := PI * pow(0.9953222650189527, 2.0)
	check(absf(m.reference - exact) < 1e-6, "Integración: referencia ∬ e^(−x²−y²) = π·erf(2)² = %.8f" % exact)
	m.n = 8
	m._compute()
	check(absf(float(m.results[0]["orden"]) - 2.0) < 0.3 and absf(float(m.results[1]["orden"]) - 2.0) < 0.3, "Integración: punto medio y trapecio de orden 2")
	check(float(m.results[2]["orden"]) > 3.3, "Integración: Simpson de orden 4 (%.2f)" % float(m.results[2]["orden"]))
	check(float(m.results[3]["orden"]) > 5.3, "Integración doble: Gauss–Legendre 3 × 3 de orden 6 (%.2f)" % float(m.results[3]["orden"]))
	check(float(m.results[4]["error"]) < 4.0 * float(m.results[4]["sigma"]) and float(m.results[5]["error"]) < 0.05, "Integración doble: Monte Carlo dentro de 4σ (%s < 4·%s) y Halton cerca (%s)" % [LabUI.sci(float(m.results[4]["error"]), 2), LabUI.sci(float(m.results[4]["sigma"]), 2), LabUI.sci(float(m.results[5]["error"]), 2)])

func _t_calculo() -> void:
	var m = lab.module
	# --- Integración: los 18 métodos con ∫₀^π sin x dx = 2.
	m.set_mode(0)
	m._load_int(0)
	m.n = 16
	m._changed()
	var bad := []
	for k in range(m.INT_METHODS.size()):
		var r: Dictionary = m.rows[k]
		if k in [16, 17]:
			if str(r["estado"]) == "ok":
				bad.append("%s debería rechazar [0, π]" % m.INT_SHORT[k])
			continue
		var lim := 0.12 if k == 14 else (0.02 if k in [0, 1, 2, 3, 15] else 1e-3)
		if str(r["estado"]) != "ok" or float(r["error"]) > lim:
			bad.append("%s: %s" % [m.INT_SHORT[k], str(r.get("error", r["estado"]))])
	check(bad.is_empty(), "Integración 1D: los 16 métodos para [a, b] finito dan ∫₀^π sin x = 2 (y Laguerre/Hermite se niegan) %s" % str(bad))
	m._load_int(1)
	var orders := {}
	for k in [0, 3, 4, 6]:
		var e1: float = m.run_int(k, 8)["error"]
		var e2: float = m.run_int(k, 16)["error"]
		orders[k] = log(e1 / e2) / log(2.0)
	check(absf(float(orders[0]) - 1.0) < 0.15 and absf(float(orders[3]) - 2.0) < 0.1 and absf(float(orders[4]) - 4.0) < 0.2 and absf(float(orders[6]) - 6.0) < 0.3,
		"Integración 1D con eˣ: órdenes observados rectángulo %.2f, trapecio %.2f, Simpson %.2f, Boole %.2f (1, 2, 4, 6)" % [orders[0], orders[3], orders[4], orders[6]])
	check(float(m.run_int(7, 32)["error"]) < 1e-12 and float(m.run_int(8, 6)["error"]) < 1e-12, "Integración 1D: Romberg (6 niveles) y Gauss–Legendre de 6 nodos llegan a 10⁻¹² con eˣ")
	var gl := Quadrature.gauss_legendre(func(x: float) -> float: return pow(x, 9) + pow(x, 4), -1.0, 2.0, 5)
	check(absf(float(gl["valor"]) - (102.3 + 6.6)) < 1e-10, "Gauss–Legendre de 5 nodos es exacta para grado 9: ∫₋₁² (x⁹ + x⁴) = %.12f" % float(gl["valor"]))
	m._load_int(4)
	check(str(m.run_int(0, 16)["estado"]) != "ok" and float(m.run_int(13, 16)["error"]) < 1e-10 and float(m.run_int(10, 16)["error"]) < 1e-8,
		"ln x en [0, 1]: los rectángulos izquierdos fallan en x = 0; tanh-sinh (%s) y Gauss–Kronrod (%s) dan −1" % [LabUI.sci(float(m.run_int(13, 16)["error"]), 1), LabUI.sci(float(m.run_int(10, 16)["error"]), 1)])
	m._load_int(6)
	var ep: float = m.run_int(3, 16)["error"]
	var es: float = m.run_int(4, 16)["error"]
	check(ep < 1e-12 and es > 100.0 * ep, "Periódica e^(cos x) en un periodo: el trapecio con 16 puntos es exacto (%s) y mejor que Simpson (%s)" % [LabUI.sci(maxf(ep, 1e-17), 1), LabUI.sci(es, 1)])
	m._load_int(9)
	var inf_ok := true
	for k in [10, 13, 16]:
		inf_ok = inf_ok and str(m.rows[k]["estado"]) == "ok" and float(m.rows[k]["error"]) < 1e-8
	check(inf_ok and str(m.rows[3]["estado"]) != "ok", "∫₀^∞ e^(−x) = 1 con Gauss–Kronrod, tanh-sinh (exp-sinh) y Gauss–Laguerre; el trapecio pide un intervalo finito")
	m._load_int(10)
	m.n = 16
	m._changed()
	check(float(m.rows[17]["error"]) < 1e-10 and float(m.rows[13]["error"]) < 1e-10, "∫ e^(−x²) en ℝ = √π con Gauss–Hermite y sinh-sinh")
	m._load_int(0)
	m.mc_exp = 3.0
	m._changed()
	var mc: Dictionary = m.rows[14]
	check(float(mc["error"]) < 4.0 * float(mc["sigma"]) and float(m.rows[15]["error"]) < float(mc["sigma"]), "Monte Carlo con N = 1000: error %s dentro de 4σ (σ = %s); cuasi-Monte Carlo %s" % [LabUI.sci(float(mc["error"]), 2), LabUI.sci(float(mc["sigma"]), 2), LabUI.sci(float(m.rows[15]["error"]), 2)])
	m.compare = true
	m._changed()
	check(m.conv.size() == m.INT_METHODS.size() and m.info().contains("Gauss–Kronrod"), "Integración 1D: comparar todos da las 18 curvas de convergencia y la tabla")
	m.compare = false
	# --- Derivación.
	m.set_mode(1)
	m._load_diff(0)
	m.order = 1
	var ob := {}
	for k in [0, 2, 5]:
		var e1: float = m.run_diff(k, 1.0, 0.02)["error"]
		var e2: float = m.run_diff(k, 1.0, 0.01)["error"]
		ob[k] = log(e1 / e2) / log(2.0)
	var e7a: float = m.run_diff(6, 1.0, 0.2)["error"]
	var e7b: float = m.run_diff(6, 1.0, 0.1)["error"]
	ob[6] = log(e7a / e7b) / log(2.0)
	check(absf(float(ob[0]) - 1.0) < 0.05 and absf(float(ob[2]) - 2.0) < 0.05 and absf(float(ob[5]) - 4.0) < 0.1 and absf(float(ob[6]) - 6.0) < 0.2,
		"Derivación: órdenes observados adelante %.2f, centrada %.2f, 5 puntos %.2f, 7 puntos %.2f (1, 2, 4, 6)" % [ob[0], ob[2], ob[5], ob[6]])
	var e_small: float = m.run_diff(2, 1.0, 1e-13)["error"]
	var e_best: float = m.run_diff(2, 1.0, 1e-5)["error"]
	check(e_small > 100.0 * e_best, "Derivación: la «V» del error: con h = 10⁻¹³ domina el redondeo (%s) frente a h = 10⁻⁵ (%s)" % [LabUI.sci(e_small, 1), LabUI.sci(e_best, 1)])
	check(float(m.run_diff(8, 1.0, 1e-20)["error"]) < 1e-15 and float(m.run_diff(9, 1.0, 0.1)["error"]) < 1e-15 and float(m.run_diff(10, 1.0, 0.1)["error"]) < 1e-15,
		"Derivación: paso complejo con h = 10⁻²⁰, automática y simbólica exactas hasta el redondeo")
	check(float(m.run_diff(7, 1.0, 0.1)["error"]) < 1e-12 and float(m.run_diff(12, 1.0, 0.1)["error"]) < 1e-10, "Derivación: Richardson (4 niveles desde h = 0.1) y Chebyshev con N = 24 por debajo de 10⁻¹⁰")
	var s1: float = m.run_diff(13, 1.0, 0.1)["error"]
	var s2: float = m.run_diff(13, 1.0, 0.05)["error"]
	check(log(s1 / s2) / log(2.0) > 3.5, "Derivación: spline cúbico not-a-knot de orden 4 en el centro (%.2f)" % (log(s1 / s2) / log(2.0)))
	m.order = 2
	var f2a: float = m.run_diff(5, 1.0, 0.02)["error"]
	var f2b: float = m.run_diff(5, 1.0, 0.01)["error"]
	check(absf(log(f2a / f2b) / log(2.0) - 4.0) < 0.15 and float(m.run_diff(9, 1.0, 0.1)["error"]) < 1e-14, "Segunda derivada: centrada de 5 puntos de orden 4 (%.2f); la automática es exacta" % (log(f2a / f2b) / log(2.0)))
	m.order = 1
	m.noise_exp = -6.0
	var e_fwd: float = m.run_diff(0, 1.0, 1e-6)["error"]
	var e_sg: float = m.run_diff(11, 1.0, 0.05)["error"]
	check(e_fwd > 0.1 and e_sg < 1e-3, "Con ruido 10⁻⁶ en f, la diferencia hacia delante con h = 10⁻⁶ se dispara (%s) y Savitzky–Golay no (%s)" % [LabUI.sci(e_fwd, 1), LabUI.sci(e_sg, 1)])
	m.noise_exp = -17.0
	m._load_diff(4)
	check(m.d1_expr.ok() and absf(m.d1_expr.eval_real({"x": 0.4}) - m.exact_d(0.4, 1)) < 1e-12, "Derivación: la derivada simbólica del ejemplo es %s" % m.d1_expr.to_pretty())
	m.compare = true
	m._changed()
	check(m.conv.size() == m.DIFF_METHODS.size() and is_finite(m.h_opt), "Derivación: comparar todos da las 14 curvas error–h y el h óptimo (%s)" % LabUI.sci(m.h_opt, 1))
	m.compare = false
	m.set_mode(0)

func _t_edp1d() -> void:
	var m = lab.module
	m.r = 0.4
	m._solve_all()
	check(m.errs[0] < 1e-2 and m.errs[2] < m.errs[1], "EDP 1D: con r = 0.4 FTCS es estable y Crank-Nicolson es más preciso que Euler implícito")
	m.r = 0.6
	m._solve_all()
	check(m.errs[0] > 1.0 and m.errs[1] < 1e-2 and m.errs[2] < 1e-2, "EDP 1D: con r = 0.6 FTCS se vuelve inestable (error %s) y los implícitos no" % LabUI.sci(m.errs[0], 1))

func _t_coloreado() -> void:
	var m = lab.module
	check(m.zeros.size() == 2 and m.poles.size() == 2, "Coloreado: (z²−1)/(z²+1) tiene 2 ceros y 2 polos (%d, %d)" % [m.zeros.size(), m.poles.size()])
	m._set_expr(MathExpr.parse("(z - 1)/(z + 1)^2", ["z"], true))
	var double_pole := false
	for p in m.poles:
		if (p[0] as Vector2).distance_to(Vector2(-1, 0)) < 1e-3 and int(p[1]) == 2:
			double_pole = true
	check(double_pole, "Coloreado: detecta el polo doble en z = −1 por su índice (−2)")
	m._set_expr(MathExpr.parse("z^3 - 1", ["z"], true))
	check(m.zeros.size() == 3, "Coloreado: z³ − 1 tiene las 3 raíces cúbicas de la unidad")

func _t_conforme() -> void:
	var m = lab.module
	var ok := false
	for c in m.crit:
		if absf((c[0] as Vector2).length() - 1.0) < 0.02 and absf((c[0] as Vector2).y) < 0.02:
			ok = true
	check(ok, "Conforme: Joukowsky tiene puntos críticos en z = ±1 (f′ = 1 − 1/z² = 0)")
	check(m.lines.mesh != null and m.lines.mesh.get_surface_count() > 0, "Conforme: malla de la rejilla con posiciones z y w (deformación en GPU)")

func _t_fractales() -> void:
	var m = lab.module
	check(m.escape_count(Vector2(-0.5, 0.0), false) < 0 and m.escape_count(Vector2(1.0, 1.0), false) >= 0, "Fractales: c = −0.5 ∈ M; c = 1 + i ∉ M")
	check(m.escape_count(Vector2(0.0, 0.0), true) >= 0, "Fractales: Julia de c = −0.8 + 0.156i (disconexo: el origen escapa)")

func _t_campo() -> void:
	var m = lab.module
	check(absf(m.divergence(Vector3(0.3, 0.2, 0.1))) < 1e-4 and absf(m.curl(Vector3(0.3, 0.2, 0.1)).z - 2.0) < 1e-3, "Campo: el vórtice (−y, x, 0) tiene ∇·F = 0 y ∇×F = (0, 0, 2)")
	m.preset = 1
	m._load(1)
	check(absf(m.divergence(Vector3(0.5, -0.2, 0.3)) - 3.0) < 1e-3, "Campo: la fuente radial tiene ∇·F = 3")
	check(m.equilibria.size() == 1 and str(m.equilibria[0][1]).begins_with("fuente"), "Campo: equilibrio en el origen clasificado como fuente")
	var sl: Array = m.streamline(Vector3(1, 0, 0), 200)
	check(sl.size() > 50, "Campo: línea de corriente integrada por RK4 (%d puntos)" % sl.size())

func _t_teoremas() -> void:
	var m = lab.module
	check(absf(m.lhs - 4.0 * PI) < 0.01 and absf(m.rhs - 4.0 * PI) < 0.01, "Gauss: flujo de (x, y, z) por la esfera unidad = ∭ 3 dV = 4π (%.4f / %.4f)" % [m.lhs, m.rhs])
	m.theorem = 1
	m.preset = 0
	m._load(0)
	check(absf(m.lhs - m.rhs) < 0.01 and absf(m.lhs - 2.0 * PI * cos(deg_to_rad(m.n_theta))) < 0.02, "Stokes: circulación del vórtice = ∬ 2·n_z dA = 2π cos θ (%.4f / %.4f)" % [m.lhs, m.rhs])
