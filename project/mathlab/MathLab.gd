class_name MathLab
extends Node3D
## MathLab — Laboratorio matemático 3D interactivo de MechaForge.
##
## Visualiza e interactúa con funciones y ecuaciones en cuatro pilares:
##   1. EDPs y física matemática: onda, calor y Schrödinger (en tiempo real).
##   2. Métodos numéricos: gráficas de funciones, raíces, sistemas, optimización, interpolación y
##      ajuste, integración numérica y solución numérica de EDPs.
##   3. Análisis complejo: coloreado de dominio 3D, mapeos conformes y fractales.
##   4. Campos vectoriales: flechas, líneas de corriente y partículas, divergencia
##      y rotacional, teoremas de Gauss y Stokes.
##   5. Física moderna (docs/FISICA_MODERNA.md): átomo de hidrógeno y partículas cargadas
##      con las fuerzas en la GPU; panel «Modelo y límites» con el nivel de fidelidad.
## Escenario holodeck con post-procesado, cámara orbital amortiguada (perspectiva,
## superior 2D, isométrica), herramienta «Perturbar», tooltip 3D flotante y
## planos de corte X/Y/Z.
## Seguimiento de manos opcional (botón «🖐 Manos» o tecla H): handtracking/.

signal closed

const PILLARS := ["EDPs y física", "Métodos numéricos", "Análisis complejo", "Campos vectoriales", "Física moderna"]
const MODULES := [
	{"id": "onda", "pilar": 0, "nombre": "Ecuación de onda 2D", "ruta": "res://mathlab/modules/OndaModule.gd",
		"desc": "Membrana vibrante: pulsos, interferencia, reflexión y modos normales de un tambor."},
	{"id": "calor", "pilar": 0, "nombre": "Ecuación de calor", "ruta": "res://mathlab/modules/CalorModule.gd",
		"desc": "Conducción térmica en una placa con materiales, fuentes y disipación."},
	{"id": "schrodinger", "pilar": 0, "nombre": "Schrödinger (efecto túnel)", "ruta": "res://mathlab/modules/SchrodingerModule.gd",
		"desc": "Paquete de ondas cuántico: |ψ|² como altura y la fase como color; barreras y pozos."},
	{"id": "graficas", "pilar": 1, "nombre": "Gráficas", "ruta": "res://mathlab/modules/GraficasModule.gd",
		"desc": "Calculadora gráfica: hasta 4 funciones con raíces, extremos y cortes; paramétricas, polares, superficies z = f(x, y) y puntos."},
	{"id": "raices", "pilar": 1, "nombre": "Ecuaciones no lineales", "ruta": "res://mathlab/modules/RaicesModule.gd",
		"desc": "15 métodos: bisección, regula falsi, Illinois, Ridders, Brent, Newton, Halley, secante, Steffensen, Müller, punto fijo… y su comparación."},
	{"id": "sistemas", "pilar": 1, "nombre": "Sistemas de ecuaciones", "ruta": "res://mathlab/modules/SistemasModule.gd",
		"desc": "Tres planos: Jacobi, Gauss-Seidel, SOR, gradiente conjugado…; eliminación geométrica, LU, Cholesky, QR."},
	{"id": "nolineal", "pilar": 1, "nombre": "Sistemas no lineales", "ruta": "res://mathlab/modules/NoLinealesModule.gd",
		"desc": "F(x, y) = 0: Newton, Broyden, punto fijo, Levenberg–Marquardt… y cuencas de atracción."},
	{"id": "optimizacion", "pilar": 1, "nombre": "Optimización multivariable", "ruta": "res://mathlab/modules/OptimizacionModule.gd",
		"desc": "Gradiente descendente y Newton sobre z = f(x, y)."},
	{"id": "interpolacion", "pilar": 1, "nombre": "Interpolación y ajuste", "ruta": "res://mathlab/modules/InterpolacionModule.gd",
		"desc": "Splines 3D, B-spline y Bézier; mínimos cuadrados; superficies por IDW, RBF y Delaunay."},
	{"id": "interp1d", "pilar": 1, "nombre": "Métodos de interpolación (1D)", "ruta": "res://mathlab/modules/InterpolacionMetodosModule.gd",
		"desc": "Lagrange, Newton, splines, Hermite, PCHIP, Akima, Floater–Hormann…; Runge y Chebyshev."},
	{"id": "integracion", "pilar": 1, "nombre": "Integración y derivación (2D)", "ruta": "res://mathlab/modules/IntegracionModule.gd",
		"desc": "Integral doble en a ≤ x ≤ b, c(x) ≤ y ≤ d(x) con 19 métodos (producto, Romberg, Gauss, cubatura, iteradas adaptativas, Genz–Malik, Monte Carlo…) y derivadas parciales, laplaciano, gradiente y direccional con 11 métodos."},
	{"id": "calculo", "pilar": 1, "nombre": "Integración y derivación (1D)", "ruta": "res://mathlab/modules/CalculoModule.gd",
		"desc": "18 cuadraturas (Newton–Cotes, Romberg, Gauss, Kronrod, tanh-sinh, Monte Carlo…) y 14 derivadas numéricas (diferencias, Richardson, paso complejo, automática, simbólica…)."},
	{"id": "edp1d", "pilar": 1, "nombre": "EDP numérica (calor 1D)", "ruta": "res://mathlab/modules/EdpNumericaModule.gd",
		"desc": "Explícito, implícito y Crank-Nicolson: estabilidad y error en superficies espacio-tiempo."},
	{"id": "coloreado", "pilar": 2, "nombre": "Coloreado de dominio 3D", "ruta": "res://mathlab/modules/ColoreadoModule.gd",
		"desc": "|f(z)| como altura y arg f(z) como color; ceros, polos y cortes de rama."},
	{"id": "conforme", "pilar": 2, "nombre": "Mapeos conformes", "ruta": "res://mathlab/modules/ConformeModule.gd",
		"desc": "Deformación animada de rejillas: eᶻ, z², 1/z, Joukowsky, Möbius…"},
	{"id": "fractales", "pilar": 2, "nombre": "Fractales (Mandelbrot y Julia)", "ruta": "res://mathlab/modules/FractalesModule.gd",
		"desc": "Conjuntos de Mandelbrot y Julia en relieve; clic para elegir c."},
	{"id": "campo", "pilar": 3, "nombre": "Campos vectoriales 3D", "ruta": "res://mathlab/modules/CampoModule.gd",
		"desc": "Flechas instanciadas, gradiente, líneas de corriente, partículas, divergencia y rotacional."},
	{"id": "teoremas", "pilar": 3, "nombre": "Teoremas de Gauss y Stokes", "ruta": "res://mathlab/modules/TeoremasModule.gd",
		"desc": "Flujo por una esfera frente a la divergencia; circulación frente al rotacional."},
	{"id": "hidrogeno", "pilar": 4, "nombre": "Átomo de hidrógeno", "ruta": "res://mathlab/modules/HidrogenoModule.gd",
		"desc": "Orbitales exactos ψₙₗₘ como nube de puntos de |ψ|² con la fase en color; energías, ⟨r⟩ y nodos."},
	{"id": "particulas", "pilar": 4, "nombre": "Partículas y fuerza de Coulomb", "ruta": "res://mathlab/modules/ParticulasModule.gd",
		"desc": "Miles de cargas clásicas con las fuerzas en la GPU: plasma neutro y átomo clásico; campo B (Lorentz) y líneas de campo."},
	{"id": "desintegraciones", "pilar": 4, "nombre": "Desintegraciones y cámara de burbujas", "ruta": "res://mathlab/modules/DesintegracionesModule.gd",
		"desc": "Partículas del Modelo Estándar (PDG 2026): desintegraciones con vidas medias y fracciones reales, trazas en un campo B y leyes de conservación en cada vértice."},
	{"id": "bateria", "pilar": 4, "nombre": "Batería cuántica", "ruta": "res://mathlab/modules/BateriaModule.gd",
		"desc": "Cadena de hasta 12 espines: carga, almacenamiento y descarga con evolución exacta; energía, potencia, ergotropía y esferas de Bloch."},
]

enum Tool { ORBITAR, PERTURBAR }
## Subpasos de paso fijo por fotograma como mucho: si el cálculo no da abasto, la
## simulación va más lenta en lugar de acumular retraso sin fin.
const MAX_SUBSTEPS := 8
const UNDO_MAX := 50
## Versión del estado del laboratorio que se guarda en el proyecto («laboratorio»).
const STATE_VERSION := 1

var main_scene: Node
var start_module: String = "onda"
var stage: HoloStage
var cam: LabCamera
var module_root: Node3D
var module: LabModule
var module_id: String = ""
var pillar: int = 0
var tool: int = Tool.ORBITAR
var playing: bool = true
var speed: float = 1.0
var clip_on := Vector3.ZERO
var clip_pos := Vector3.ZERO
var clip_side := Vector3.ONE
var seed_value: int = 1
## Estado guardado que aplicar al abrir (lo pasa MechaForge al cargar un proyecto).
var pending_state: Dictionary = {}
var physics_ms: float = 0.0
var _acc: float = 0.0
var _undo: Array = []
var _redo: Array = []

# --- UI ---
var ui: CanvasLayer
var modules_panel: FloatingPanel
var modules_box: VBoxContainer
var params_panel: FloatingPanel
var params_box: VBoxContainer
var info_panel: FloatingPanel
var info_label: RichTextLabel
var clip_panel: FloatingPanel
var status_label: Label
var pillar_buttons: Array = []
var tool_buttons: Array = []
var play_button: Button
var hands: VirtualLabController
var hands_button: Button
var speed_option: OptionButton
var view_buttons: Array = []
var topbar_panel: Control
var model_panel: FloatingPanel
var model_label: RichTextLabel
var model_button: Button
var metrics_panel: FloatingPanel
var metrics_label: Label
var _info_accum: float = 0.0
var _crit_index: int = -1

# --- Ratón y tooltip ---
var _dragging_left: bool = false
var _dragging_right: bool = false
var _dragging_mid: bool = false
var _perturbing: bool = false
var tooltip: Label3D
var tip_marker: MeshInstance3D

func _ready() -> void:
	name = "LaboratorioMatematico"
	stage = HoloStage.new()
	add_child(stage)
	cam = LabCamera.new()
	add_child(cam)
	cam.make_current()
	module_root = Node3D.new()
	module_root.name = "Modulo"
	add_child(module_root)
	_build_tooltip()
	_build_ui()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	open_pillar(0)
	open_module(start_module if module_info(start_module).size() > 0 else "onda")
	if not pending_state.is_empty() and str(pending_state.get("modulo", "")) == module_id:
		var err := module.cargar(pending_state.get("estado", {}))
		if err != "":
			_status("⚠ El estado guardado del laboratorio no es válido: " + err)
	pending_state = {}

#region MÓDULOS --------------------------------------------------------------------

func module_info(id: String) -> Dictionary:
	for m in MODULES:
		if m["id"] == id:
			return m
	return {}

func open_pillar(p: int) -> void:
	pillar = p
	for i in range(pillar_buttons.size()):
		(pillar_buttons[i] as Button).set_pressed_no_signal(i == p)
	for c in modules_box.get_children():
		c.queue_free()
	for m in MODULES:
		if int(m["pilar"]) != p:
			continue
		var b := Button.new()
		b.text = m["nombre"]
		b.tooltip_text = m["desc"]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.button_pressed = m["id"] == module_id
		b.set_meta("id", m["id"])
		var id: String = m["id"]
		b.pressed.connect(func(): open_module(id))
		modules_box.add_child(b)
		var d := Label.new()
		d.text = m["desc"]
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(230, 0)
		d.add_theme_font_size_override("font_size", 11)
		d.add_theme_color_override("font_color", Color(0.58, 0.62, 0.68))
		# Solo se muestra la descripción del módulo abierto (lista compacta).
		d.set_meta("desc_for", m["id"])
		d.visible = m["id"] == module_id
		modules_box.add_child(d)
	modules_panel.set_title("Módulos · " + PILLARS[p])

func open_module(id: String) -> void:
	var info := module_info(id)
	if info.is_empty():
		return
	if int(info["pilar"]) != pillar:
		open_pillar(int(info["pilar"]))
	var scr: Script = load(info["ruta"])
	open_instance(scr.new(), info)

## Monta un módulo ya creado (open_module lo carga del registro; las pruebas montan
## módulos propios).
func open_instance(m: LabModule, info: Dictionary) -> void:
	var id := str(info["id"])
	if module:
		module.liberar()
		module_root.remove_child(module)
		module.queue_free()
		module = null
	module_id = id
	module = m
	module.lab = self
	module.name = id
	module.rng.seed = seed_value
	module_root.add_child(module)
	module.setup()
	_acc = 0.0
	_undo.clear()
	_redo.clear()
	for c in params_box.get_children():
		c.queue_free()
	LabUI.section(params_box, info["nombre"])
	module.build_ui(params_box)
	params_panel.set_title("Parámetros · " + info["nombre"])
	for b in modules_box.get_children():
		if b is Button:
			(b as Button).set_pressed_no_signal(str(b.get_meta("id", "")) == id)
		elif b.has_meta("desc_for"):
			b.visible = str(b.get_meta("desc_for")) == id
	modules_panel.reset_size()
	var v: Dictionary = module.view()
	cam.target = v["target"]
	cam.distance = float(v["dist"])
	cam.yaw = deg_to_rad(float(v["yaw"]))
	cam.pitch = deg_to_rad(float(v["pitch"]))
	if cam.view_mode != LabCamera.ViewMode.PERSPECTIVA:
		cam.set_view(cam.view_mode)
	play_button.disabled = not module.uses_time()
	_crit_index = -1
	for cm in module.clip_materials:
		apply_clip_to(cm)
	_refresh_model_panel()
	_update_info(true)
	_hide_tooltip()
	_status("%s — %s" % [info["nombre"], module.perturb_hint()])

#endregion

#region BUCLE ----------------------------------------------------------------------

func _process(delta: float) -> void:
	if module and playing and module.uses_time():
		advance(delta * speed)
	_info_accum += delta
	if _info_accum >= 0.2:
		_info_accum = 0.0
		_update_info(false)
		_update_metrics()

## Avanza la simulación «sim_dt» segundos: de una vez o en pasos fijos si el módulo
## los pide (fixed_dt). Si el estado deja de ser finito, pausa y avisa.
func advance(sim_dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	var h := module.fixed_dt()
	if h <= 0.0:
		module.step(sim_dt)
	else:
		_acc += sim_dt
		# Número de pasos de una vez: restar h repetidas veces arrastra error de redondeo.
		var n := mini(int(_acc / h + 1e-6), MAX_SUBSTEPS)
		for i in n:
			module.step(h)
		_acc = 0.0 if n == MAX_SUBSTEPS else maxf(0.0, _acc - n * h)
	var bien := module.finito()       # con la GPU, aquí se espera a que termine: cuenta como física
	physics_ms = (Time.get_ticks_usec() - t0) / 1000.0
	if not bien:
		if playing:
			toggle_play()
		_status("⚠ La simulación dio NaN o ∞ y se ha pausado. Reinicia (R) o cambia los parámetros.")

## Un paso con la simulación en pausa (⏭).
func step_once() -> void:
	if module == null or not module.uses_time():
		return
	if playing:
		toggle_play()
	advance(module.fixed_dt() if module.fixed_dt() > 0.0 else 1.0 / 60.0)
	_update_info(false)

func _update_info(full: bool) -> void:
	if module == null or info_label == null:
		return
	var t := "[font_size=15][color=#5fd8ff]%s[/color][/font_size]\n" % module.formula()
	t += module.info()
	info_label.text = t
	if full:
		info_panel.set_collapsed(false)
	call_deferred("_anchor_info")

## Mantiene el panel de información pegado al borde inferior aunque crezca.
func _anchor_info() -> void:
	if info_panel == null:
		return
	var vp := get_viewport().get_visible_rect().size
	info_panel.position.y = maxf(topbar_bottom(), vp.y - info_panel.size.y - 36.0)

#endregion

#region ENTRADA --------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed: cam.zoom(0.9)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed: cam.zoom(1.1)
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					if tool == Tool.PERTURBAR and module:
						var hit = _pick(mb.position)
						if hit != null:
							_perturbing = true
							module.perturb(hit, true)
							_update_info(false)
							return
					_dragging_left = true
				else:
					_dragging_left = false
					_perturbing = false
			MOUSE_BUTTON_RIGHT:
				_dragging_right = mb.pressed
			MOUSE_BUTTON_MIDDLE:
				_dragging_mid = mb.pressed
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _perturbing and module:
			var hit2 = _pick(mm.position)
			if hit2 != null:
				module.perturb(hit2, false)
		elif _dragging_mid or (_dragging_right and Input.is_key_pressed(KEY_SHIFT)):
			cam.pan(mm.relative.x, mm.relative.y)
		elif _dragging_left or _dragging_right:
			cam.orbit(mm.relative.x, mm.relative.y)
		_hover(mm.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		match k.keycode:
			KEY_Z when k.ctrl_pressed and k.shift_pressed: redo()
			KEY_Z when k.ctrl_pressed: undo()
			KEY_Y when k.ctrl_pressed: redo()
			KEY_F: frame_next()
			KEY_1: set_view(LabCamera.ViewMode.PERSPECTIVA)
			KEY_2: set_view(LabCamera.ViewMode.SUPERIOR)
			KEY_3: set_view(LabCamera.ViewMode.ISOMETRICA)
			KEY_SPACE: toggle_play()
			KEY_R: reset_module()
			KEY_P: set_tool(Tool.PERTURBAR if tool == Tool.ORBITAR else Tool.ORBITAR)
			KEY_H: toggle_hands(not (hands != null and hands.enabled))
			KEY_ESCAPE: go_back()

func _pick(screen: Vector2):
	if module == null:
		return null
	var r := cam.screen_ray(screen)
	return module.pick(r["origin"], r["dir"])

func _hover(screen: Vector2) -> void:
	var hit = _pick(screen)
	if hit == null:
		_hide_tooltip()
		return
	var txt := module.hover_text(hit)
	if txt == "":
		_hide_tooltip()
		return
	tooltip.text = txt
	tooltip.visible = true
	tip_marker.visible = true
	tip_marker.global_position = hit
	tooltip.global_position = hit + Vector3(0, 0.12 + cam.distance * 0.012, 0)

func _build_tooltip() -> void:
	tooltip = Label3D.new()
	tooltip.name = "Tooltip3D"
	tooltip.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tooltip.no_depth_test = true
	tooltip.fixed_size = true
	tooltip.pixel_size = 0.0006
	tooltip.font_size = 24
	tooltip.outline_size = 10
	tooltip.modulate = Color(0.9, 0.97, 1.0)
	tooltip.outline_modulate = Color(0.0, 0.05, 0.1, 0.92)
	tooltip.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	tooltip.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	tooltip.render_priority = 10
	tooltip.visible = false
	add_child(tooltip)
	tip_marker = LabModule.sphere(0.03, LabModule.glow_mat(Color(1.0, 0.85, 0.3), 4.0))
	tip_marker.visible = false
	add_child(tip_marker)

func _hide_tooltip() -> void:
	if tooltip:
		tooltip.visible = false
		tip_marker.visible = false

#endregion

#region ACCIONES -------------------------------------------------------------------

func set_view(mode: int) -> void:
	cam.set_view(mode)
	for i in range(view_buttons.size()):
		(view_buttons[i] as Button).set_pressed_no_signal(i == mode)

func set_tool(t: int) -> void:
	tool = t
	for i in range(tool_buttons.size()):
		(tool_buttons[i] as Button).set_pressed_no_signal(i == t)
	_status("Herramienta: %s" % ("Orbitar (arrastra para girar la vista)" if t == Tool.ORBITAR else "Perturbar — " + (module.perturb_hint() if module else "")))

func toggle_play() -> void:
	playing = not playing
	play_button.text = "⏸" if playing else "▶"

## Vista inicial del módulo (sin cambiar el modo de vista).
func reset_view() -> void:
	if module == null:
		return
	var v: Dictionary = module.view()
	cam.target = v["target"]
	cam.distance = float(v["dist"])
	if cam.view_mode == LabCamera.ViewMode.PERSPECTIVA:
		cam.yaw = deg_to_rad(float(v["yaw"]))
		cam.pitch = deg_to_rad(float(v["pitch"]))
	else:
		cam.set_view(cam.view_mode)

## Activa o desactiva el seguimiento de manos (crea el controlador la primera vez).
func toggle_hands(on: bool) -> void:
	if hands == null:
		hands = VirtualLabController.new()
		add_child(hands)
		hands.setup(self)
		hands.build_panel(ui)
		hands.enabled_changed.connect(func(v):
			if hands_button:
				hands_button.set_pressed_no_signal(v))
	if on:
		hands.panel.visible = true
		hands.panel.set_collapsed(false)
		var vp := get_viewport().get_visible_rect().size
		hands.panel.position = Vector2(vp.x - 620, topbar_bottom())
	hands.set_enabled(on)
	if hands_button:
		hands_button.set_pressed_no_signal(hands.enabled)

func set_speed(s: float) -> void:
	var speeds := [0.25, 0.5, 1.0, 2.0, 4.0, 8.0]
	var i := speeds.find(s)
	if i >= 0:
		speed = s
		speed_option.select(i)

## Aviso en la barra de estado de lo que ha hecho OpenClaw a través de la API.
func notify_ai(t: String) -> void:
	_status("🤖 OpenClaw: " + t)

func reset_module() -> void:
	if module:
		module.rng.seed = seed_value
		module.reset()
		_update_info(false)
		_status("Reiniciado.")

## Encuadre animado del siguiente punto crítico del módulo.
func frame_next() -> void:
	if module == null:
		return
	var pts: Array = module.critical_points()
	if pts.is_empty():
		var v: Dictionary = module.view()
		cam.frame(v["target"], float(v["dist"]))
		_status("Vista general.")
		return
	_crit_index = (_crit_index + 1) % (pts.size() + 1)
	if _crit_index == pts.size():
		var v2: Dictionary = module.view()
		cam.frame(v2["target"], float(v2["dist"]))
		_status("Vista general.")
		return
	var p: Dictionary = pts[_crit_index]
	cam.frame(p["pos"], float(p.get("dist", 2.5)))
	_status("🎯 %s (%d/%d) — F para el siguiente" % [p["nombre"], _crit_index + 1, pts.size()])

func apply_clip_to(m: ShaderMaterial) -> void:
	if m == null:
		return
	m.set_shader_parameter("clip_on", clip_on)
	m.set_shader_parameter("clip_pos", clip_pos)
	m.set_shader_parameter("clip_side", clip_side)

func _apply_clip() -> void:
	if module:
		for m in module.clip_materials:
			apply_clip_to(m)

func go_back() -> void:
	closed.emit()

## Antes de un cambio del usuario (LabModule.remember): guarda el estado para deshacer.
func record_undo() -> void:
	if module == null:
		return
	_undo.append(module.estado().duplicate(true))
	if _undo.size() > UNDO_MAX:
		_undo.pop_front()
	_redo.clear()

func undo() -> void:
	if module and not _undo.is_empty():
		_redo.append(module.estado().duplicate(true))
		module.cargar(_undo.pop_back())
		_update_info(false)
		_status("Deshecho.")

func redo() -> void:
	if module and not _redo.is_empty():
		_undo.append(module.estado().duplicate(true))
		module.cargar(_redo.pop_back())
		_update_info(false)
		_status("Rehecho.")

## Lo que MechaForge guarda en el proyecto: el módulo abierto y su estado.
func snapshot() -> Dictionary:
	return {"version": STATE_VERSION, "modulo": module_id, "estado": module.estado() if module else {}}

## "" si «d» es un estado del laboratorio que se puede aplicar; si no, el motivo.
static func validate_snapshot(d: Variant) -> String:
	if typeof(d) != TYPE_DICTIONARY:
		return "no es un diccionario"
	if int(d.get("version", 0)) != STATE_VERSION:
		return "versión %s (se esperaba %d)" % [str(d.get("version", "?")), STATE_VERSION]
	if MODULES.filter(func(m): return m["id"] == str(d.get("modulo", ""))).is_empty():
		return "módulo desconocido «%s»" % str(d.get("modulo", ""))
	if typeof(d.get("estado", {})) != TYPE_DICTIONARY:
		return "el estado del módulo no es un diccionario"
	return ""

## Si la aplicación se cierra con el laboratorio abierto, MechaForge está fuera del
## árbol y nadie lo liberaría (el ejecutable exportado terminaba con código 127). El
## módulo abierto suelta sus recursos de GPU.
func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	if module:
		module.liberar()
	if is_instance_valid(main_scene) and not main_scene.is_inside_tree():
		main_scene.free()

func _status(t: String) -> void:
	if status_label:
		status_label.text = t

#endregion

#region INTERFAZ -------------------------------------------------------------------

func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(vb)
	vb.add_child(_topbar())
	var mid := Control.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(mid)
	var sb := PanelContainer.new()
	sb.custom_minimum_size = Vector2(0, 30)
	sb.add_theme_stylebox_override("panel", _bar_style())
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 13)
	sb.add_child(status_label)
	vb.add_child(sb)

	modules_panel = FloatingPanel.new("Módulos")
	ui.add_child(modules_panel)
	modules_panel.position = Vector2(8, topbar_bottom())
	modules_box = VBoxContainer.new()
	modules_box.custom_minimum_size = Vector2(240, 0)
	modules_panel.add_content(modules_box)

	params_panel = FloatingPanel.new("Parámetros")
	ui.add_child(params_panel)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(290, 520)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	params_panel.add_content(sc)
	params_box = VBoxContainer.new()
	params_box.custom_minimum_size = Vector2(270, 0)
	params_box.add_theme_constant_override("separation", 6)
	sc.add_child(params_box)

	info_panel = FloatingPanel.new("Información")
	ui.add_child(info_panel)
	info_label = RichTextLabel.new()
	info_label.bbcode_enabled = true
	info_label.fit_content = true
	info_label.custom_minimum_size = Vector2(340, 90)
	info_label.scroll_active = false
	info_panel.add_content(info_label)

	clip_panel = FloatingPanel.new("Planos de corte")
	ui.add_child(clip_panel)
	var cb := VBoxContainer.new()
	cb.custom_minimum_size = Vector2(240, 0)
	clip_panel.add_content(cb)
	for axis in range(3):
		var ax := axis
		var nm: String = ["X", "Y (altura)", "Z"][axis]
		LabUI.check(cb, "Corte en " + nm, false, func(v):
			clip_on[ax] = 1.0 if v else 0.0
			_apply_clip())
		LabUI.slider(cb, "  posición", -3.0, 3.0, 0.01, 0.0, func(v):
			clip_pos[ax] = v
			_apply_clip())
	LabUI.check(cb, "Invertir el lado cortado", false, func(v):
		clip_side = -Vector3.ONE if v else Vector3.ONE
		_apply_clip())
	clip_panel.set_collapsed(true)

	model_panel = FloatingPanel.new("Modelo y límites")
	ui.add_child(model_panel)
	model_label = RichTextLabel.new()
	model_label.bbcode_enabled = true
	model_label.fit_content = true
	model_label.custom_minimum_size = Vector2(420, 60)
	model_label.scroll_active = false
	model_panel.add_content(model_label)
	model_panel.visible = false

	metrics_panel = FloatingPanel.new("Métricas y tiempo")
	ui.add_child(metrics_panel)
	var mb := VBoxContainer.new()
	mb.custom_minimum_size = Vector2(230, 0)
	metrics_panel.add_content(mb)
	metrics_label = Label.new()
	metrics_label.add_theme_font_size_override("font_size", 12)
	mb.add_child(metrics_label)
	var seed_box := LabUI.spin(mb, "Semilla", 0, 999999, 1, seed_value, func(v): seed_value = int(v))
	seed_box.tooltip_text = "Semilla de los números aleatorios: con la misma semilla, «⟲ Reiniciar» repite la simulación"
	metrics_panel.visible = false
	call_deferred("_layout")

## Panel «Modelo y límites» con lo que declara el módulo (fidelidad()). El nivel va en
## palabras además de en color.
func _refresh_model_panel() -> void:
	var f: Array = module.fidelidad() if module else []
	model_button.disabled = f.is_empty()
	if f.is_empty():
		model_panel.visible = false
		return
	var cols := {"exacto": "#7dffa0", "aproximado": "#ffd36b", "ilustrativo": "#ff9ad5"}
	var t := ""
	for s in f:
		var nivel := str(s.get("nivel", "?"))
		t += "[b]%s[/b] — [color=%s]%s[/color]\n" % [s.get("subsistema", "?"), cols.get(nivel, "#ffffff"), nivel.to_upper()]
		for k in ["modelo", "ecuaciones", "unidades", "referencias"]:
			if str(s.get(k, "")) != "":
				t += "  [color=#8fa3b8]%s:[/color] %s\n" % [k, s[k]]
	model_label.text = t

func _update_metrics() -> void:
	if metrics_panel == null or not metrics_panel.visible:
		return
	var vp := get_viewport().get_viewport_rid()
	var t := "FPS: %d\nFísica: %.2f ms\nRender: %.2f ms CPU · %.2f ms GPU\nMemoria: %.0f MB" % [
		Engine.get_frames_per_second(), physics_ms,
		RenderingServer.viewport_get_measured_render_time_cpu(vp),
		RenderingServer.viewport_get_measured_render_time_gpu(vp),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0]
	if module:
		var m: Dictionary = module.metricas()
		for k in m:
			t += "\n%s: %s" % [str(k).capitalize(), str(m[k])]
	metrics_label.text = t

func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	params_panel.position = Vector2(vp.x - params_panel.size.x - 8, topbar_bottom())
	info_panel.position = Vector2(8, vp.y - info_panel.size.y - 40)
	clip_panel.position = Vector2(vp.x - clip_panel.size.x - 8, vp.y - clip_panel.size.y - 40)

func _bar_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.03, 0.05, 0.08, 0.92)
	s.border_color = Color(0.1, 0.55, 0.8, 0.6)
	s.border_width_bottom = 1
	s.set_content_margin_all(6)
	return s

func _tb(parent: Control, text: String, cb: Callable, toggle := false, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = toggle
	b.tooltip_text = tip
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func topbar_bottom() -> float:
	return topbar_panel.get_global_rect().end.y + 6.0 if is_instance_valid(topbar_panel) else 52.0

## Si la barra pasa a dos filas (ventana estrecha), baja los paneles que quedarían debajo.
func _on_topbar_resized() -> void:
	var b := topbar_bottom()
	for fp in [modules_panel, params_panel, hands.panel if hands else null]:
		if fp and fp.position.y < b:
			fp.position.y = b

func _topbar() -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _bar_style())
	topbar_panel = p
	# Se parte en filas si no cabe: con una sola fila, a 1920 px ya quedaban fuera
	# «📐 Modelo» y 📊 (y en pantallas de 1366 px, Macro, Manos y Cortes).
	var hb := HFlowContainer.new()
	hb.add_theme_constant_override("h_separation", 6)
	hb.add_theme_constant_override("v_separation", 4)
	p.add_child(hb)
	p.resized.connect(_on_topbar_resized)
	_tb(hb, "← MechaForge", go_back, false, "Volver al simulador (Esc)")
	var t := Label.new()
	t.text = "∑  Laboratorio matemático"
	t.add_theme_color_override("font_color", Color(0.35, 0.85, 1.0))
	t.add_theme_font_size_override("font_size", 17)
	hb.add_child(t)
	hb.add_child(VSeparator.new())
	for i in range(PILLARS.size()):
		var idx := i
		pillar_buttons.append(_tb(hb, PILLARS[i], func(): open_pillar(idx), true))
	hb.add_child(VSeparator.new())
	var views := ["3D", "2D", "Iso"]
	var view_tips := ["Perspectiva (tecla 1)", "Superior 2D, ortográfica: mapas de calor y contornos (tecla 2)", "Isométrica (tecla 3)"]
	for i in range(3):
		var vi := i
		var b := _tb(hb, views[i], func(): set_view(vi), true, view_tips[i])
		b.button_pressed = i == 0
		view_buttons.append(b)
	_tb(hb, "🎯 Encuadrar", frame_next, false, "Recorre los puntos críticos (F)")
	hb.add_child(VSeparator.new())
	tool_buttons.append(_tb(hb, "🖱 Orbitar", func(): set_tool(Tool.ORBITAR), true, "Arrastrar gira la vista"))
	tool_buttons.append(_tb(hb, "✋ Perturbar", func(): set_tool(Tool.PERTURBAR), true, "Clic/arrastre sobre la superficie: pulsos, calor, barreras… (P)"))
	(tool_buttons[0] as Button).button_pressed = true
	play_button = _tb(hb, "⏸", toggle_play, false, "Pausa / reanudar (Espacio)")
	_tb(hb, "⏭", step_once, false, "Un paso con la simulación en pausa")
	_tb(hb, "⟲", reset_module, false, "Reiniciar el módulo (R)")
	_tb(hb, "↶", undo, false, "Deshacer (Ctrl+Z)")
	_tb(hb, "↷", redo, false, "Rehacer (Ctrl+Y)")
	var sp := OptionButton.new()
	speed_option = sp
	sp.focus_mode = Control.FOCUS_NONE
	for s in [0.25, 0.5, 1.0, 2.0, 4.0, 8.0]:
		sp.add_item("%s×" % str(s))
	sp.select(2)
	sp.item_selected.connect(func(i): speed = [0.25, 0.5, 1.0, 2.0, 4.0, 8.0][i])
	sp.tooltip_text = "Velocidad de la simulación"
	hb.add_child(sp)
	hb.add_child(VSeparator.new())
	var macro := _tb(hb, "Macro", func(): pass, true, "Profundidad de campo (efecto macro)")
	macro.toggled.connect(func(v): stage.set_macro(v, cam.distance))
	hands_button = _tb(hb, "🖐 Manos", func(): toggle_hands(hands_button.button_pressed), true, "Seguimiento de manos con la cámara (H): apuntar, pellizcar, zoom con dos manos, palma para pausar")
	_tb(hb, "Cortes", func():
		clip_panel.visible = true
		clip_panel.set_collapsed(not clip_panel.is_collapsed()), false, "Planos de corte X/Y/Z")
	model_button = _tb(hb, "📐 Modelo", func():
		model_panel.visible = not model_panel.visible, false, "Modelo y límites: ecuaciones, unidades, referencias y nivel de fidelidad")
	_tb(hb, "📊", func():
		metrics_panel.visible = not metrics_panel.visible
		_update_metrics(), false, "Métricas (FPS, tiempos, memoria, entidades) y semilla")
	return p

#endregion
