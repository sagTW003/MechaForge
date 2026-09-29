class_name VirtualLabController
extends Node
## VirtualLabController — Capa 3 del seguimiento de manos: gestos → Laboratorio.
##
##   Apuntar            cursor en pantalla (resalta controles; sobre la escena 3D,
##                      tooltip con coordenadas y valores).
##   Pellizco + mover   · sobre un deslizador: ajuste fino del valor (la mano recorre
##                        `fine` veces el ancho del control para todo el rango);
##                      · sobre botones, casillas y desplegables: clic;
##                      · sobre la escena 3D: giro orbital (o perturbación si la
##                        herramienta «✋ Perturbar» está activa);
##                      · en vista superior 2D o en módulos planos: desplazamiento.
##   Dos pellizcos      zoom por la variación de distancia entre las manos
##                      (ratio^zoom_sens: más sensible que 1:1).
##   Dos puños          agarra la escena en 3D, como un objeto sujeto con las dos
##                      manos: moverlos la desplaza (izquierda/derecha, arriba/abajo,
##                      empujar hacia la pantalla la aleja); una mano hacia delante y
##                      otra hacia atrás la gira; doblar las muñecas la inclina.
##                      Mientras hay un puño, los pellizcos de esa mano no cuentan.
##   Palma abierta      congela la interacción; mantenida 1 s reinicia la vista.
##
## Precisión adaptativa del pellizco: los movimientos lentos de la mano se escalan
## por slow_gain (ajuste fino) y los rápidos van 1:1, como la aceleración de un ratón.
##
## Los clics y arrastres sobre la interfaz se inyectan como eventos de ratón en el
## viewport (Viewport.push_input), así funcionan con cualquier control sin código
## específico. La escena se mueve con la API de la cámara del laboratorio.

signal enabled_changed(on: bool)

var lab                       # MathLab
var tracker: HandTracker
var recognizer := GestureRecognizer.new()
var enabled: bool = false
var primary: String = "Right"   # "Right", "Left" o "" (cualquiera)
var orbit_gain: float = 0.9
var fine: float = 3.0
var show_skeleton: bool = true
var move_mouse: bool = true     # mover también el puntero del sistema (resalta los controles bajo el cursor)
var zoom_sens: float = 1.8      # exponente del zoom con dos manos (1 = proporcional)
var adaptive: bool = true       # precisión adaptativa en los arrastres con pellizco
var slow_gain: float = 0.35     # ganancia en movimientos lentos (≤ SLOW_V)
var grab_gain: float = 1.0      # desplazamiento con dos puños (1: GRAB_REACH m de mano cruzan la vista)
var grab_depth: float = 1.0     # profundidad respecto al desplazamiento lateral (1 = igual en los tres ejes)
var grab_rot_gain: float = 1.0  # giro e inclinación (1 = la escena gira lo mismo que las manos)
var grab_turn: bool = true      # girar: una mano hacia la pantalla y la otra hacia atrás
var grab_tilt: bool = true      # inclinar: doblar las muñecas hacia delante o hacia atrás
const GRAB_REACH := 0.45        # m de recorrido de la mano para cruzar el ancho de la vista
const TURN_DEAD := 0.087        # rad (5°): zona muerta del giro desde el inicio del agarre
const TILT_DEAD := 0.14         # rad (8°): zona muerta de la inclinación
const SETTINGS_VERSION := 2
var last_gain: float = 1.0      # última ganancia aplicada (para el HUD)
const SLOW_V := 120.0           # px/s: por debajo, ganancia mínima
const FAST_V := 900.0           # px/s: por encima, 1:1
var frozen: bool = false
var cursor := Vector2(-1, -1)   # píxeles
var cursor_hand: String = ""
var drag_mode: String = ""      # "", "gui", "slider", "orbit", "pan", "perturb", "none"
var palm_progress: float = 0.0
var hud: Control
var panel: FloatingPanel
var status_label: Label
var _slider: Range
var _slider_value: float = 0.0
var _gui_pressed: bool = false
var injected: Array = []        # últimos clics inyectados [pulsado, posición] (diagnóstico y pruebas)
var _frame_dt: float = 1.0 / 30.0
var _last_t: float = 0.0
var _zoom_acc: float = 0.0
var _grab_rot := Vector3.ZERO   # giro acumulado del agarre (para las zonas muertas)

func setup(p_lab: Node) -> void:
	lab = p_lab
	name = "ControlManos"
	tracker = HandTracker.new()
	tracker.name = "HandTracker"
	add_child(tracker)
	tracker.hands_updated.connect(_on_hands)
	tracker.status_changed.connect(_on_status)
	recognizer.pointed.connect(_on_point)
	recognizer.pinch_started.connect(_on_pinch_start)
	recognizer.pinch_moved.connect(_on_pinch_move)
	recognizer.pinch_ended.connect(_on_pinch_end)
	recognizer.zoom_changed.connect(_on_zoom)
	recognizer.palm_started.connect(_on_palm_start)
	recognizer.palm_held.connect(func(_h, p): palm_progress = p)
	recognizer.palm_reset.connect(_on_palm_reset)
	recognizer.palm_ended.connect(_on_palm_end)
	recognizer.hand_lost.connect(_on_hand_lost)
	recognizer.grab_started.connect(_on_grab_start)
	recognizer.grab_moved.connect(_on_grab_move)
	recognizer.grab_ended.connect(_on_grab_end)
	_load_settings()
	hud = Hud.new()
	hud.ctrl = self
	hud.name = "HudManos"
	hud.visible = false
	lab.ui.add_child(hud)

func _load_settings() -> void:
	var s: Dictionary = tracker.settings
	primary = str(s.get("primary", primary))
	orbit_gain = float(s.get("orbit_gain", orbit_gain))
	fine = float(s.get("fine", fine))
	show_skeleton = bool(s.get("skeleton", show_skeleton))
	move_mouse = bool(s.get("move_mouse", move_mouse))
	zoom_sens = float(s.get("zoom_sens", zoom_sens))
	adaptive = bool(s.get("adaptive", adaptive))
	slow_gain = float(s.get("slow_gain", slow_gain))
	grab_gain = float(s.get("grab_gain", grab_gain))
	grab_depth = float(s.get("grab_depth", grab_depth))
	grab_rot_gain = float(s.get("grab_rot_gain", grab_rot_gain))
	grab_turn = bool(s.get("grab_turn", grab_turn))
	grab_tilt = bool(s.get("grab_tilt", grab_tilt))
	recognizer.pinch_on_cm = float(s.get("pinch_on", recognizer.pinch_on_cm))
	recognizer.pinch_off_cm = float(s.get("pinch_off", recognizer.pinch_off_cm))
	recognizer.far_px = float(s.get("far_px", recognizer.far_px))
	recognizer.hfov_deg = float(s.get("hfov", recognizer.hfov_deg))
	var bs := float(s.get("box_size", recognizer.box_size.x))
	# Ajustes de la versión 1: la zona de 0.6 (el valor por defecto de entonces) pasa a 0.8.
	if int(s.get("v", 1)) < SETTINGS_VERSION and absf(bs - 0.6) < 0.005:
		bs = 0.8
	recognizer.box_size = Vector2(bs, bs * 0.8333)
	recognizer.box_center = Vector2(0.5, float(s.get("box_y", 0.55)))

func save_settings() -> void:
	tracker.settings = {"v": SETTINGS_VERSION, "primary": primary, "orbit_gain": orbit_gain, "fine": fine, "skeleton": show_skeleton,
		"move_mouse": move_mouse, "pinch_on": recognizer.pinch_on_cm, "pinch_off": recognizer.pinch_off_cm,
		"far_px": recognizer.far_px, "hfov": recognizer.hfov_deg,
		"box_size": recognizer.box_size.x, "box_y": recognizer.box_center.y, "zoom_sens": zoom_sens,
		"adaptive": adaptive, "slow_gain": slow_gain, "grab_gain": grab_gain, "grab_depth": grab_depth,
		"grab_rot_gain": grab_rot_gain, "grab_turn": grab_turn, "grab_tilt": grab_tilt}
	tracker.save_config()

func set_enabled(on: bool) -> void:
	if on == enabled:
		return
	if on:
		if not tracker.start():
			_on_status(tracker.status_text, "error")
			enabled_changed.emit(false)
			return
	else:
		_cancel_drag()
		tracker.stop()
		cursor = Vector2(-1, -1)
		frozen = false
	enabled = on
	hud.visible = on
	enabled_changed.emit(on)
	lab._status("✋ Seguimiento de manos %s" % ("activado: muestra la mano a la cámara" if on else "desactivado"))

func _on_status(text: String, level: String) -> void:
	if status_label:
		status_label.text = text
		status_label.add_theme_color_override("font_color", {"error": Color(1.0, 0.45, 0.35), "ok": Color(0.45, 0.95, 0.55)}.get(level, Color(0.75, 0.8, 0.88)))
	if level == "error":
		lab._status("✋ " + text)
		if enabled and not tracker.running:
			enabled = false
			hud.visible = false
			enabled_changed.emit(false)

func _on_hands(hands: Array) -> void:
	var t: float = hands[0]["t"] if not hands.is_empty() else HandTracker.now()
	if _last_t > 0.0:
		_frame_dt = clampf(t - _last_t, 1.0 / 240.0, 0.1)
	_last_t = t
	recognizer.update(hands, t)
	if hud:
		hud.queue_redraw()

# --- Conversión de coordenadas e inyección de eventos ---------------------------------

func _vp() -> Vector2:
	return lab.get_viewport().get_visible_rect().size

func to_px(pos01: Vector2) -> Vector2:
	return pos01 * _vp()

func _push_motion(px: Vector2, rel: Vector2, mask: int = 0) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = px
	ev.global_position = px
	ev.relative = rel
	ev.button_mask = mask
	lab.get_viewport().push_input(ev)

func _push_button(px: Vector2, pressed: bool) -> void:
	# La interfaz ignora los clics si cree que el ratón está fuera de la ventana (p. ej.
	# con el puntero real en otro monitor): la mano sí está «dentro».
	lab.get_viewport().notification(Node.NOTIFICATION_VP_MOUSE_ENTER)
	var ev := InputEventMouseButton.new()
	ev.position = px
	ev.global_position = px
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	injected.append([pressed, px])
	if injected.size() > 16:
		injected.pop_front()
	lab.get_viewport().push_input(ev)

## Control de la interfaz bajo el punto: {tipo: "ninguno" | "interactivo" | "pasivo", control}.
## Búsqueda propia (el «hover» de Godot sigue al ratón real, no a los eventos inyectados).
func gui_at(px: Vector2) -> Dictionary:
	var vp: Viewport = lab.get_viewport()
	for w in vp.get_embedded_subwindows():
		if w.visible and Rect2(Vector2(w.position), Vector2(w.size)).has_point(px):
			return {"tipo": "interactivo", "control": null}
	var c := control_at(lab.ui, px)
	if c == null:
		return {"tipo": "ninguno", "control": null}
	if c is BaseButton or c is Range or c is LineEdit or c is TextEdit or c is ItemList or c is TabBar:
		return {"tipo": "interactivo", "control": c}
	return {"tipo": "pasivo", "control": c}

## Control visible más profundo bajo px que recibe el ratón (de arriba abajo en el orden de dibujo).
static func control_at(node: Node, px: Vector2) -> Control:
	for i in range(node.get_child_count() - 1, -1, -1):
		var ch := node.get_child(i)
		if not (ch is Control) or not (ch as Control).is_visible_in_tree():
			continue
		var c := ch as Control
		var inside := c.get_global_rect().has_point(px)
		if c.clip_contents and not inside:
			continue
		var deeper := control_at(c, px)
		if deeper != null:
			return deeper
		if inside and c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			return c
	return null

## Mueve el cursor: eventos de movimiento inyectados y, si se quiere, el puntero real.
func _move_to(px: Vector2, rel: Vector2, mask: int = 0) -> void:
	if move_mouse and DisplayServer.get_name() != "headless":
		lab.get_viewport().warp_mouse(px)
	_push_motion(px, rel, mask)

func _is_cursor_hand(hand: String) -> bool:
	if cursor_hand != "" and cursor_hand != hand and drag_mode != "":
		return false
	return primary == "" or hand == primary or recognizer.gesture_of(primary) in [GestureRecognizer.Gesture.NONE, GestureRecognizer.Gesture.IDLE, GestureRecognizer.Gesture.FIST]

## Ganancia de un arrastre según la velocidad de la mano (precisión adaptativa).
func ballistic(rel: Vector2) -> float:
	if not adaptive:
		return 1.0
	var speed := rel.length() / _frame_dt
	return lerpf(slow_gain, 1.0, smoothstep(SLOW_V, FAST_V, speed))

# --- Eventos de gestos -------------------------------------------------------------------

func _on_point(hand: String, pos: Vector2) -> void:
	if frozen or not _is_cursor_hand(hand):
		return
	cursor_hand = hand
	var px := to_px(pos)
	var rel := px - cursor if cursor.x >= 0.0 else Vector2.ZERO
	cursor = px
	_move_to(px, rel)

func _on_pinch_start(hand: String, pos: Vector2) -> void:
	if frozen or not _is_cursor_hand(hand):
		return
	cursor_hand = hand
	cursor = to_px(pos)
	var g := gui_at(cursor)
	match str(g["tipo"]):
		"interactivo":
			var c = g["control"]
			if c is Slider:
				drag_mode = "slider"
				_slider = c
				_slider_value = (c as Range).value
			else:
				drag_mode = "gui"
				_push_button(cursor, true)
				_gui_pressed = true
		"pasivo":
			drag_mode = "none"
		_:
			if lab.tool == MathLab.Tool.PERTURBAR:
				drag_mode = "perturb"
				_push_button(cursor, true)
				_gui_pressed = true
			elif lab.cam.view_mode == LabCamera.ViewMode.SUPERIOR or (lab.module and lab.module.has_method("planar") and lab.module.planar()):
				drag_mode = "pan"
			else:
				drag_mode = "orbit"

func _on_pinch_move(hand: String, pos: Vector2, _delta: Vector2) -> void:
	if frozen or hand != cursor_hand or drag_mode == "":
		return
	var px := to_px(pos)
	var rel := px - cursor
	cursor = px
	var g := ballistic(rel)
	last_gain = g
	match drag_mode:
		"slider":
			if is_instance_valid(_slider):
				var w := maxf(40.0, _slider.size.x)
				_slider_value += rel.x * g * (_slider.max_value - _slider.min_value) / (w * fine)
				_slider.value = clampf(_slider_value, _slider.min_value, _slider.max_value)
		"gui", "perturb":
			_move_to(px, rel, MOUSE_BUTTON_MASK_LEFT)
		"orbit":
			lab.cam.orbit(rel.x * orbit_gain * g, rel.y * orbit_gain * g)
		"pan":
			lab.cam.pan(rel.x * g, rel.y * g)

func _on_pinch_end(hand: String, _pos: Vector2, _cancelled: bool) -> void:
	if hand != cursor_hand:
		return
	_cancel_drag()

func _cancel_drag() -> void:
	if _gui_pressed:
		_push_button(cursor, false)
		_gui_pressed = false
	drag_mode = ""
	_slider = null

## Zoom con dos manos: distancia de la cámara × ratio^(−zoom_sens). Los cambios
## minúsculos se acumulan (zona muerta) para que el temblor no haga «respirar» la vista.
func _on_zoom(ratio: float, _total: float) -> void:
	if frozen or ratio <= 0.0:
		return
	_zoom_acc += log(ratio)
	if absf(_zoom_acc) < 0.001:
		return
	lab.cam.zoom(clampf(exp(-zoom_sens * _zoom_acc), 0.7, 1.4))
	_zoom_acc = 0.0

func _on_grab_start() -> void:
	_cancel_drag()
	drag_mode = "grab"
	_grab_rot = Vector3.ZERO

## Ancho visible de la escena a la distancia del objetivo de la cámara (unidades del mundo).
func visible_width() -> float:
	var cam: LabCamera = lab.cam
	var vp := _vp()
	var h: float = cam.size if cam.projection == Camera3D.PROJECTION_ORTHOGONAL else 2.0 * cam.distance * tan(deg_to_rad(cam.fov) * 0.5)
	return h * vp.x / maxf(1.0, vp.y)

static func _dead(x: float, dz: float) -> float:
	return signf(x) * maxf(0.0, absf(x) - dz)

## Dos puños: la escena se mueve como un objeto sujeto con las dos manos.
##   d (m, x derecha, y arriba, z hacia la pantalla): el objeto se desplaza igual; la
##   cámara se mueve al revés. Empujar hacia la pantalla aleja la escena (la
##   distancia de la cámara crece), así el centro de giro sigue en el objeto.
##   rot.y (una mano hacia delante): el objeto gira sobre la vertical; rot.x (muñecas):
##   se inclina. La cámara orbital no tiene alabeo: el «volante» (rot.z) no se usa.
func _on_grab_move(d: Vector3, rot: Vector3) -> void:
	if frozen:
		return
	var cam: LabCamera = lab.cam
	var s := visible_width() / GRAB_REACH * grab_gain
	var b: Basis = cam.global_transform.basis
	cam.target -= (b.x * d.x + b.y * d.y) * s
	cam.distance = clampf(cam.distance * exp(d.z * s * grab_depth / maxf(0.01, cam.distance)), 0.4, 80.0)
	var prev := _grab_rot
	_grab_rot += rot * grab_rot_gain
	if grab_turn:
		cam.yaw -= _dead(_grab_rot.y, TURN_DEAD) - _dead(prev.y, TURN_DEAD)
	if grab_tilt and cam.view_mode != LabCamera.ViewMode.SUPERIOR:
		cam.pitch = clampf(cam.pitch - (_dead(_grab_rot.x, TILT_DEAD) - _dead(prev.x, TILT_DEAD)), deg_to_rad(-89.0), deg_to_rad(80.0))

## Cámara en 1280×720: los puntos de una mano lejana salen más precisos.
func set_hires(on: bool) -> void:
	tracker.width = 1280 if on else 640
	tracker.height = 720 if on else 480
	tracker.save_config()
	if enabled and tracker.running:
		tracker.stop()
		tracker.start()

func _on_grab_end() -> void:
	if drag_mode == "grab":
		drag_mode = ""

func _on_palm_start(_hand: String) -> void:
	_cancel_drag()
	frozen = true
	palm_progress = 0.0

func _on_palm_reset(_hand: String) -> void:
	lab.reset_view()
	lab._status("✋ Vista reiniciada (palma abierta mantenida)")

func _on_palm_end(_hand: String) -> void:
	frozen = false
	palm_progress = 0.0

func _on_hand_lost(hand: String) -> void:
	if hand == cursor_hand:
		_cancel_drag()
		cursor_hand = ""
	if recognizer.states.is_empty():
		frozen = false

# --- Panel de ajustes --------------------------------------------------------------------

func build_panel(parent: CanvasLayer) -> FloatingPanel:
	panel = FloatingPanel.new("✋ Seguimiento de manos")
	parent.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(300, clampf(parent.get_viewport().get_visible_rect().size.y - 200.0, 300.0, 640.0))
	panel.add_content(scroll)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(284, 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	status_label = LabUI.note(box, tracker.status_text)
	LabUI.option(box, "Mano principal:", ["Derecha", "Izquierda", "Cualquiera"], ["Right", "Left", ""].find(primary), func(i):
		primary = ["Right", "Left", ""][i]
		save_settings())
	LabUI.section(box, "Zona de interacción y cámara")
	LabUI.slider(box, "Zona de interacción (tamaño)", 0.3, 1.0, 0.01, recognizer.box_size.x, func(v):
		recognizer.box_size = Vector2(v, v * 0.8333)
		save_settings())
	LabUI.slider(box, "Altura de la zona", 0.3, 0.75, 0.01, recognizer.box_center.y, func(v):
		recognizer.box_center.y = v
		save_settings())
	LabUI.slider(box, "Campo de visión de la webcam (°)", 40.0, 100.0, 1.0, recognizer.hfov_deg, func(v):
		recognizer.hfov_deg = v
		save_settings(), "%.0f")
	LabUI.check(box, "Cámara en 1280×720 (mejor con la mano lejos)", tracker.width >= 1280, func(v):
		set_hires(v))
	LabUI.section(box, "Pellizco")
	LabUI.slider(box, "Pellizco: se activa a (cm)", 1.0, 5.0, 0.1, recognizer.pinch_on_cm, func(v):
		recognizer.pinch_on_cm = v
		recognizer.pinch_off_cm = maxf(recognizer.pinch_off_cm, v + 0.5)
		save_settings(), "%.1f")
	LabUI.slider(box, "Pellizco: se suelta a (cm)", 1.5, 8.0, 0.1, recognizer.pinch_off_cm, func(v):
		recognizer.pinch_off_cm = maxf(v, recognizer.pinch_on_cm + 0.5)
		save_settings(), "%.1f")
	LabUI.slider(box, "Compensación con la mano lejos (px)", 0.0, 30.0, 1.0, recognizer.far_px, func(v):
		recognizer.far_px = v
		save_settings(), "%.0f")
	LabUI.slider(box, "Sensibilidad de giro", 0.2, 2.5, 0.05, orbit_gain, func(v):
		orbit_gain = v
		save_settings())
	LabUI.slider(box, "Ajuste fino de deslizadores (×)", 1.0, 8.0, 0.5, fine, func(v):
		fine = v
		save_settings(), "%.1f")
	LabUI.check(box, "Precisión adaptativa (lento = fino)", adaptive, func(v):
		adaptive = v
		save_settings())
	LabUI.slider(box, "Ganancia en movimientos lentos", 0.1, 1.0, 0.05, slow_gain, func(v):
		slow_gain = v
		save_settings())
	LabUI.slider(box, "Sensibilidad del zoom (dos pellizcos)", 0.5, 4.0, 0.1, zoom_sens, func(v):
		zoom_sens = v
		save_settings(), "%.1f")
	LabUI.section(box, "Dos puños (agarre 3D)")
	LabUI.slider(box, "Desplazamiento", 0.2, 3.0, 0.05, grab_gain, func(v):
		grab_gain = v
		save_settings())
	LabUI.slider(box, "Profundidad (empujar / tirar)", 0.0, 3.0, 0.05, grab_depth, func(v):
		grab_depth = v
		save_settings())
	LabUI.slider(box, "Giro e inclinación (×)", 0.2, 3.0, 0.05, grab_rot_gain, func(v):
		grab_rot_gain = v
		save_settings())
	LabUI.check(box, "Girar: una mano adelante y otra atrás", grab_turn, func(v):
		grab_turn = v
		save_settings())
	LabUI.check(box, "Inclinar: doblar las muñecas", grab_tilt, func(v):
		grab_tilt = v
		save_settings())
	LabUI.section(box, "Filtro y pantalla")
	LabUI.slider(box, "Suavizado (corte mínimo, Hz)", 0.1, 5.0, 0.05, tracker.min_cutoff, func(v):
		tracker.set_filter_params(v, tracker.beta)
		save_settings())
	LabUI.slider(box, "Reactividad (β)", 0.0, 60.0, 0.5, tracker.beta, func(v):
		tracker.set_filter_params(tracker.min_cutoff, v)
		save_settings(), "%.1f")
	LabUI.check(box, "Mostrar el esqueleto de las manos", show_skeleton, func(v):
		show_skeleton = v
		save_settings())
	LabUI.check(box, "Mover también el puntero del ratón", move_mouse, func(v):
		move_mouse = v
		save_settings())
	LabUI.note(box, "☝ apuntar: cursor · 🤏 pellizco: girar, arrastrar deslizadores, pulsar · 🤏🤏 dos manos: zoom · ✊✊ dos puños: agarrar la escena en 3D (mover, empujar hacia la pantalla, una mano adelante = girar, muñecas = inclinar; con un puño los pellizcos de esa mano no cuentan) · 🖐 palma: pausa (1 s: reinicia la vista). La cámara solo se usa mientras el seguimiento está activo; no se guarda ninguna imagen.")
	panel.set_collapsed(true)
	panel.visible = false
	return panel

# --- HUD: cursor, esqueleto y estado --------------------------------------------------

const BONES := [[0, 1], [1, 2], [2, 3], [3, 4], [0, 5], [5, 6], [6, 7], [7, 8], [5, 9], [9, 10], [10, 11], [11, 12],
	[9, 13], [13, 14], [14, 15], [15, 16], [13, 17], [0, 17], [17, 18], [18, 19], [19, 20]]

const PHASE_COLORS := {"lejos": Color(0.5, 0.55, 0.6), "acercando": Color(1.0, 0.9, 0.35), "cerrando": Color(1.0, 0.75, 0.3),
	"activo": Color(1.0, 0.6, 0.15), "soltando": Color(0.9, 0.9, 1.0), "bloqueado": Color(1.0, 0.4, 0.4)}
const MINIMAP_SIZE := Vector2(320, 240)

class Hud extends Control:
	var ctrl

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_d: float) -> void:
		if visible:
			queue_redraw()

	func _draw() -> void:
		if ctrl == null:
			return
		var font := ThemeDB.fallback_font
		var vp: Vector2 = ctrl._vp()
		var rec: GestureRecognizer = ctrl.recognizer
		var tr: HandTracker = ctrl.tracker
		# Minimapa de la cámara con la zona de interacción y el esqueleto.
		var mm := Rect2(Vector2(vp.x - VirtualLabController.MINIMAP_SIZE.x - 18, vp.y - VirtualLabController.MINIMAP_SIZE.y - 116), VirtualLabController.MINIMAP_SIZE)
		draw_rect(mm, Color(0.02, 0.04, 0.07, 0.82))
		draw_rect(mm, Color(0.2, 0.55, 0.8, 0.6), false, 1.0)
		var bz := Rect2(mm.position + (rec.box_center - rec.box_size * 0.5) * mm.size, rec.box_size * mm.size)
		draw_rect(bz, Color(0.35, 0.85, 1.0, 0.35), false, 1.0)
		if ctrl.show_skeleton:
			for h in tr.hands:
				var lm: PackedVector3Array = h["lm"]
				var col := Color(0.3, 0.9, 1.0) if str(h["label"]) == "Right" else Color(1.0, 0.45, 0.85)
				var g: int = rec.gesture_of(str(h["label"]))
				for b in VirtualLabController.BONES:
					draw_line(mm.position + Vector2(lm[b[0]].x, lm[b[0]].y) * mm.size, mm.position + Vector2(lm[b[1]].x, lm[b[1]].y) * mm.size, col, 1.5, true)
				for p in lm:
					draw_circle(mm.position + Vector2(p.x, p.y) * mm.size, 1.8, col.lightened(0.3))
				# Pulgar–índice coloreado por la fase del pellizco.
				var ph := rec.pinch_phase(str(h["label"]))
				var a4 := mm.position + Vector2(lm[4].x, lm[4].y) * mm.size
				var a8 := mm.position + Vector2(lm[8].x, lm[8].y) * mm.size
				draw_line(a4, a8, VirtualLabController.PHASE_COLORS.get(ph, Color(0.5, 0.5, 0.55)), 2.5 if ph != "lejos" else 1.0, true)
				if ph == "activo":
					draw_circle((a4 + a8) * 0.5, 3.5, VirtualLabController.PHASE_COLORS["activo"])
				var wr: Vector3 = lm[0]
				draw_string(font, mm.position + Vector2(wr.x, wr.y) * mm.size + Vector2(-20, 14), "%s · %s" % ["D" if str(h["label"]) == "Right" else "I", GestureRecognizer.NAMES[g]], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
		var live := tr.running
		draw_circle(mm.position + Vector2(10, 10), 4.0, Color(1.0, 0.25, 0.25) if live else Color(0.4, 0.4, 0.45))
		var line := "cámara activa · %d mano(s) · %.0f fps · latencia %.0f ms (inferencia %.1f ms)" % [tr.hands.size(), tr.fps_measured, tr.latency_ms, tr.inference_ms] if live else tr.status_text
		draw_multiline_string(font, mm.position + Vector2(20, 14), line, HORIZONTAL_ALIGNMENT_LEFT, mm.size.x - 26, 10, 2, Color(0.8, 0.86, 0.94))
		if live and tr.hands.is_empty():
			draw_string(font, mm.position + Vector2(10, mm.size.y * 0.55), "Muestra la mano a la cámara", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.8, 0.9))
		# Vista 3D de los puños junto al minimapa (con algún puño o durante el agarre).
		var any_fist := rec.grabbing
		for label in rec.states:
			if int(rec.states[label]["gesture"]) == GestureRecognizer.Gesture.FIST:
				any_fist = true
		if any_fist:
			_grab_view(font, Rect2(mm.position - Vector2(262, 0), Vector2(250, mm.size.y)), rec)
		# Agarre con dos puños: línea entre las palmas y cruz de movimiento en 3D.
		if rec.grabbing:
			var pts := []
			var zs := []
			for label in rec.states:
				if int(rec.states[label]["gesture"]) in [GestureRecognizer.Gesture.FIST, GestureRecognizer.Gesture.PINCH]:
					pts.append((rec.states[label]["palm_c"] as Vector2) * vp)
					zs.append((rec.states[label]["p3"] as Vector3).z)
			if pts.size() >= 2:
				var gc := Color(0.55, 1.0, 0.6)
				draw_line(pts[0], pts[1], gc, 3.0, true)
				for j in range(2):
					# Más grande cuanto más cerca de la cámara (de la pantalla) está el puño.
					draw_arc(pts[j], clampf(18.0 * 0.6 / maxf(0.1, float(zs[j])), 10.0, 34.0), 0.0, TAU, 36, gc, 3.0, true)
				var m: Vector2 = (pts[0] + pts[1]) * 0.5
				for dirv in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN, Vector2(0.7, -0.7), Vector2(-0.7, 0.7)]:
					var dv: Vector2 = dirv
					draw_line(m + dv * 6.0, m + dv * 20.0, gc, 2.5, true)
					draw_line(m + dv * 20.0, m + dv * 15.0 + dv.orthogonal() * 4.0, gc, 2.5, true)
					draw_line(m + dv * 20.0, m + dv * 15.0 - dv.orthogonal() * 4.0, gc, 2.5, true)
				var gtxt := "✊✊ agarre 3D"
				var gw := font.get_string_size(gtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
				_label(font, Vector2(clampf(m.x + 28.0, 8.0, vp.x - gw - 12.0), m.y - 10.0), gtxt, 13, gc)
		# Cursor.
		var c: Vector2 = ctrl.cursor
		if c.x < 0.0:
			return
		var g2: int = rec.gesture_of(ctrl.cursor_hand) if ctrl.cursor_hand != "" else GestureRecognizer.Gesture.NONE
		var col2 := Color(0.35, 0.9, 1.0)
		if ctrl.frozen:
			col2 = Color(0.8, 0.8, 0.85)
		elif g2 == GestureRecognizer.Gesture.PINCH:
			col2 = Color(1.0, 0.65, 0.2)
		draw_arc(c, 15.0, 0.0, TAU, 40, col2, 2.5, true)
		draw_circle(c, 3.0, col2)
		if g2 == GestureRecognizer.Gesture.PINCH:
			draw_circle(c, 9.0, Color(col2.r, col2.g, col2.b, 0.45))
		elif ctrl.cursor_hand != "" and rec.states.has(ctrl.cursor_hand):
			# Aproximación al pellizco: el arco interior se cierra al acercar los dedos.
			var cm: float = rec.states[ctrl.cursor_hand]["pinch_cm"]
			var on: float = rec.on_cm(ctrl.cursor_hand)
			var off: float = rec.off_cm(ctrl.cursor_hand)
			var k := clampf((off * 2.0 - cm) / (off * 2.0 - on), 0.0, 1.0) if not rec.fist_locked(ctrl.cursor_hand) else 0.0
			if k > 0.0:
				draw_arc(c, 9.0, -PI * 0.5, -PI * 0.5 + TAU * k, 32, Color(1.0, 0.8, 0.4, 0.8), 2.0, true)
		if ctrl.frozen:
			draw_arc(c, 22.0, -PI * 0.5, -PI * 0.5 + TAU * ctrl.palm_progress, 48, Color(1, 1, 1, 0.9), 3.0, true)
			_label(font, c + Vector2(28, 5), "⏸ pausa · mantén para reiniciar la vista", 12, Color(1, 1, 1))
		elif ctrl.drag_mode != "" and ctrl.drag_mode != "none" and ctrl.drag_mode != "grab":
			var names := {"slider": "ajuste fino", "gui": "clic", "orbit": "girar", "pan": "desplazar", "perturb": "perturbar"}
			var txt := str(names.get(ctrl.drag_mode, ""))
			if ctrl.drag_mode in ["slider", "orbit", "pan"] and ctrl.adaptive:
				txt += "  ·  precisión ×%.2f" % ctrl.last_gain
			_label(font, c + Vector2(22, 5), txt, 12, col2)
		# Medidor del pellizco junto al cursor.
		if not ctrl.frozen and ctrl.cursor_hand != "" and rec.states.has(ctrl.cursor_hand):
			_pinch_meter(font, c + Vector2(20, 18), rec, ctrl.cursor_hand)

	## Barra con la zona de activación (naranja) y la de histéresis (amarilla), la
	## distancia actual pulgar–índice y la fase del gesto. Con la mano lejos las zonas
	## crecen (compensación) y se indica a qué distancia está la mano.
	func _pinch_meter(font: Font, pos: Vector2, rec: GestureRecognizer, label: String) -> void:
		var ph := rec.pinch_phase(label)
		if ph == "lejos":
			return
		var st: Dictionary = rec.states[label]
		var cm := float(st["pinch_cm"])
		var on := rec.on_cm(label)
		var off := rec.off_cm(label)
		var w := 120.0
		var h := 6.0
		var maxcm := maxf(8.0, off + 2.0)
		draw_rect(Rect2(pos, Vector2(w, h)), Color(0.05, 0.08, 0.12, 0.9))
		draw_rect(Rect2(pos, Vector2(w * on / maxcm, h)), Color(1.0, 0.6, 0.2, 0.4))
		draw_rect(Rect2(pos + Vector2(w * on / maxcm, 0), Vector2(w * (off - on) / maxcm, h)), Color(1.0, 0.85, 0.3, 0.22))
		var col: Color = VirtualLabController.PHASE_COLORS.get(ph, Color.WHITE)
		var x := clampf(cm / maxcm, 0.0, 1.0) * w
		draw_rect(Rect2(pos + Vector2(x - 1.5, -3), Vector2(3, h + 6)), col)
		var txt := "pellizco %.1f cm · %s" % [cm, ph]
		if ph == "bloqueado":
			txt = "🔒 modo puño: abre la mano para pellizcar"
		elif float(st["comp"]) > 0.05:
			txt += "  ·  mano a %.1f m (umbral +%.1f cm)" % [(st["p3"] as Vector3).z, float(st["comp"])]
		_label(font, pos + Vector2(0, h + 15), txt, 11, col)

	## Vista 3D de los puños: el volumen delante de la webcam en perspectiva caballera
	## (x derecha, y arriba; lo que se empuja hacia la pantalla va al fondo, arriba a la
	## derecha), con la sombra de cada mano en el suelo, los ejes del agarre y lo
	## desplazado y girado desde que empezó.
	func _grab_view(font: Font, r: Rect2, rec: GestureRecognizer) -> void:
		draw_rect(r, Color(0.02, 0.04, 0.07, 0.82))
		draw_rect(r, Color(0.35, 0.95, 0.55, 0.55), false, 1.0)
		draw_string(font, r.position + Vector2(8, 15), "✊✊ agarre 3D (vista de los puños)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 1.0, 0.65))
		var hx := 0.36
		var hy := 0.27
		var z_near := 0.3     # m a la webcam: fondo de la caja (junto a la pantalla)
		var z_far := 1.2      # frente de la caja (junto al usuario)
		var avail := r.size.y - 70.0                                  # alto libre entre el título y el texto de abajo
		var face := Vector2(r.size.x * 0.6, avail * 0.64)
		var o := r.position + Vector2(r.size.x * 0.04, 28.0 + avail)  # esquina inferior izquierda del frente
		var dep := Vector2(r.size.x * 0.32, -avail * 0.36)            # dirección del fondo (hacia la pantalla)
		var proj := func(p: Vector3) -> Vector2:
			var u := clampf((p.x + hx) / (2.0 * hx), -0.2, 1.2)
			var v := clampf((hy - p.y) / (2.0 * hy), -0.2, 1.2)     # y de la cámara hacia abajo
			var k := clampf((z_far - p.z) / (z_far - z_near), 0.0, 1.0)
			return o + Vector2(u * face.x, -v * face.y) + dep * k
		var edge := Color(0.4, 0.75, 0.9, 0.45)
		var cs := []
		for zz in [z_far, z_near]:
			var c4 := [proj.call(Vector3(-hx, hy, zz)), proj.call(Vector3(hx, hy, zz)), proj.call(Vector3(hx, -hy, zz)), proj.call(Vector3(-hx, -hy, zz))]
			cs.append(c4)
			for j in range(4):
				draw_line(c4[j], c4[(j + 1) % 4], edge, 1.0, true)
		for j in range(4):
			draw_line(cs[0][j], cs[1][j], edge, 1.0, true)
		for q in range(1, 4):
			var zq := lerpf(z_far, z_near, q / 4.0)
			draw_line(proj.call(Vector3(-hx, hy, zq)), proj.call(Vector3(hx, hy, zq)), Color(0.4, 0.75, 0.9, 0.18), 1.0)
		# c4: 0 abajo izquierda, 1 abajo derecha, 2 arriba derecha, 3 arriba izquierda (y de la cámara hacia abajo).
		draw_string(font, cs[1][2] + Vector2(-50, 12), "pantalla", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.7, 0.85))
		draw_string(font, cs[0][0] + Vector2(4, -5), "tú", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.5, 0.7, 0.85))
		var fists := []
		for label in rec.states:
			var st: Dictionary = rec.states[label]
			var g := int(st["gesture"])
			var p: Vector3 = st["p3"]
			var col := Color(0.3, 0.9, 1.0) if label == "Right" else Color(1.0, 0.45, 0.85)
			var k := clampf((z_far - p.z) / (z_far - z_near), 0.0, 1.0)
			var at: Vector2 = proj.call(p)
			var shadow: Vector2 = proj.call(Vector3(p.x, hy, p.z))
			draw_line(shadow, at, Color(col.r, col.g, col.b, 0.35), 1.0, true)
			draw_circle(shadow, 3.0, Color(0, 0, 0, 0.5))
			var rad := lerpf(10.0, 6.0, k)
			if g == GestureRecognizer.Gesture.FIST or (rec.grabbing and g == GestureRecognizer.Gesture.PINCH):
				draw_circle(at, rad, Color(col.r, col.g, col.b, 0.85))
				fists.append(at)
			else:
				draw_arc(at, rad, 0.0, TAU, 24, col, 1.5, true)
			draw_string(font, at + Vector2(rad + 2, 4), "%s %.2f m" % ["D" if label == "Right" else "I", p.z], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col)
		var tot := rec.grab_total()
		var mv: Vector3 = tot["move"]
		var ro: Vector3 = tot["rot"]
		if rec.grabbing and fists.size() >= 2:
			draw_line(fists[0], fists[1], Color(0.55, 1.0, 0.6), 2.0, true)
			var m: Vector2 = (fists[0] + fists[1]) * 0.5
			for ax in [[Vector2(22, 0), Color(1.0, 0.4, 0.35), "x"], [Vector2(0, -22), Color(0.45, 1.0, 0.45), "y"], [dep.normalized() * 22.0, Color(0.45, 0.65, 1.0), "z"]]:
				var tip: Vector2 = m + (ax[0] as Vector2)
				draw_line(m, tip, ax[1], 2.0, true)
				draw_string(font, tip + Vector2(2, -2), ax[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ax[1])
			draw_string(font, r.position + Vector2(8, r.size.y - 24), "Δ x %+.1f  y %+.1f  z %+.1f cm" % [mv.x * 100.0, mv.y * 100.0, mv.z * 100.0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.95, 0.9))
			draw_string(font, r.position + Vector2(8, r.size.y - 8), "giro %+.0f°   inclinación %+.0f°" % [rad_to_deg(ro.y), rad_to_deg(ro.x)], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.95, 0.9))
		else:
			draw_string(font, r.position + Vector2(8, r.size.y - 24), "cierra las dos manos para agarrar la escena", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.75, 0.85, 0.9))
			draw_string(font, r.position + Vector2(8, r.size.y - 8), "(con un puño, esa mano no pellizca)", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.7, 0.78))

	## Texto con un fondo oscuro para que se lea sobre cualquier escena.
	func _label(font: Font, pos: Vector2, text: String, size: int, col: Color) -> void:
		var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
		draw_rect(Rect2(pos + Vector2(-4, -sz.y + 3), sz + Vector2(8, 4)), Color(0.02, 0.03, 0.05, 0.72))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
