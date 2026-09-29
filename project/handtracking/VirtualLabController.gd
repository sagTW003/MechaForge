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
##   Dos pellizcos      zoom por la variación de distancia entre las manos.
##   Palma abierta      congela la interacción; mantenida 1 s reinicia la vista.
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
	recognizer.pinch_on_cm = float(s.get("pinch_on", recognizer.pinch_on_cm))
	recognizer.pinch_off_cm = float(s.get("pinch_off", recognizer.pinch_off_cm))
	var bs := float(s.get("box_size", 0.6))
	recognizer.box_size = Vector2(bs, bs * 0.8333)
	recognizer.box_center = Vector2(0.5, float(s.get("box_y", 0.55)))

func save_settings() -> void:
	tracker.settings = {"primary": primary, "orbit_gain": orbit_gain, "fine": fine, "skeleton": show_skeleton, "move_mouse": move_mouse,
		"pinch_on": recognizer.pinch_on_cm, "pinch_off": recognizer.pinch_off_cm,
		"box_size": recognizer.box_size.x, "box_y": recognizer.box_center.y}
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
	recognizer.update(hands, hands[0]["t"] if not hands.is_empty() else HandTracker.now())
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
	return primary == "" or hand == primary or recognizer.gesture_of(primary) in [GestureRecognizer.Gesture.NONE, GestureRecognizer.Gesture.IDLE]

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
	match drag_mode:
		"slider":
			if is_instance_valid(_slider):
				var w := maxf(40.0, _slider.size.x)
				_slider_value += rel.x * (_slider.max_value - _slider.min_value) / (w * fine)
				_slider.value = clampf(_slider_value, _slider.min_value, _slider.max_value)
		"gui", "perturb":
			_move_to(px, rel, MOUSE_BUTTON_MASK_LEFT)
		"orbit":
			lab.cam.orbit(rel.x * orbit_gain, rel.y * orbit_gain)
		"pan":
			lab.cam.pan(rel.x, rel.y)

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

func _on_zoom(ratio: float, _total: float) -> void:
	if frozen:
		return
	lab.cam.zoom(1.0 / clampf(ratio, 0.8, 1.25))

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
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(270, 0)
	panel.add_content(box)
	status_label = LabUI.note(box, tracker.status_text)
	LabUI.option(box, "Mano principal:", ["Derecha", "Izquierda", "Cualquiera"], ["Right", "Left", ""].find(primary), func(i):
		primary = ["Right", "Left", ""][i]
		save_settings())
	LabUI.slider(box, "Zona de interacción (tamaño)", 0.3, 1.0, 0.01, recognizer.box_size.x, func(v):
		recognizer.box_size = Vector2(v, v * 0.8333)
		save_settings())
	LabUI.slider(box, "Altura de la zona", 0.3, 0.75, 0.01, recognizer.box_center.y, func(v):
		recognizer.box_center.y = v
		save_settings())
	LabUI.slider(box, "Pellizco: se activa a (cm)", 1.0, 5.0, 0.1, recognizer.pinch_on_cm, func(v):
		recognizer.pinch_on_cm = v
		recognizer.pinch_off_cm = maxf(recognizer.pinch_off_cm, v + 0.5)
		save_settings(), "%.1f")
	LabUI.slider(box, "Pellizco: se suelta a (cm)", 1.5, 8.0, 0.1, recognizer.pinch_off_cm, func(v):
		recognizer.pinch_off_cm = maxf(v, recognizer.pinch_on_cm + 0.5)
		save_settings(), "%.1f")
	LabUI.slider(box, "Suavizado (corte mínimo, Hz)", 0.1, 5.0, 0.05, tracker.min_cutoff, func(v):
		tracker.set_filter_params(v, tracker.beta)
		save_settings())
	LabUI.slider(box, "Reactividad (β)", 0.0, 60.0, 0.5, tracker.beta, func(v):
		tracker.set_filter_params(tracker.min_cutoff, v)
		save_settings(), "%.1f")
	LabUI.slider(box, "Sensibilidad de giro", 0.2, 2.5, 0.05, orbit_gain, func(v):
		orbit_gain = v
		save_settings())
	LabUI.slider(box, "Ajuste fino de deslizadores (×)", 1.0, 8.0, 0.5, fine, func(v):
		fine = v
		save_settings(), "%.1f")
	LabUI.check(box, "Mostrar el esqueleto de las manos", show_skeleton, func(v):
		show_skeleton = v
		save_settings())
	LabUI.check(box, "Mover también el puntero del ratón", move_mouse, func(v):
		move_mouse = v
		save_settings())
	LabUI.note(box, "☝ apuntar: cursor · 🤏 pellizco: girar, arrastrar deslizadores, pulsar · 🤏🤏 dos manos: zoom · 🖐 palma: pausa (1 s: reinicia la vista). La cámara solo se usa mientras el seguimiento está activo; no se guarda ninguna imagen.")
	panel.set_collapsed(true)
	panel.visible = false
	return panel

# --- HUD: cursor, esqueleto y estado --------------------------------------------------

const BONES := [[0, 1], [1, 2], [2, 3], [3, 4], [0, 5], [5, 6], [6, 7], [7, 8], [5, 9], [9, 10], [10, 11], [11, 12],
	[9, 13], [13, 14], [14, 15], [15, 16], [13, 17], [0, 17], [17, 18], [18, 19], [19, 20]]

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
		var mm := Rect2(Vector2(vp.x - 250, vp.y - 290), Vector2(232, 174))
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
				var wr: Vector3 = lm[0]
				draw_string(font, mm.position + Vector2(wr.x, wr.y) * mm.size + Vector2(-20, 14), "%s · %s" % ["D" if str(h["label"]) == "Right" else "I", GestureRecognizer.NAMES[g]], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
		var live := tr.running
		draw_circle(mm.position + Vector2(10, 10), 4.0, Color(1.0, 0.25, 0.25) if live else Color(0.4, 0.4, 0.45))
		var line := "cámara activa · %d mano(s) · %.0f fps · latencia %.0f ms (inferencia %.1f ms)" % [tr.hands.size(), tr.fps_measured, tr.latency_ms, tr.inference_ms] if live else tr.status_text
		draw_multiline_string(font, mm.position + Vector2(20, 14), line, HORIZONTAL_ALIGNMENT_LEFT, mm.size.x - 26, 10, 2, Color(0.8, 0.86, 0.94))
		if live and tr.hands.is_empty():
			draw_string(font, mm.position + Vector2(10, mm.size.y * 0.55), "Muestra la mano a la cámara", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.8, 0.9))
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
			var k := clampf((rec.pinch_off_cm * 2.0 - cm) / (rec.pinch_off_cm * 2.0 - rec.pinch_on_cm), 0.0, 1.0)
			if k > 0.0:
				draw_arc(c, 9.0, -PI * 0.5, -PI * 0.5 + TAU * k, 32, Color(1.0, 0.8, 0.4, 0.8), 2.0, true)
		if ctrl.frozen:
			draw_arc(c, 22.0, -PI * 0.5, -PI * 0.5 + TAU * ctrl.palm_progress, 48, Color(1, 1, 1, 0.9), 3.0, true)
			draw_string(font, c + Vector2(26, 5), "⏸ pausa · mantén para reiniciar la vista", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1))
		elif ctrl.drag_mode != "" and ctrl.drag_mode != "none":
			var names := {"slider": "ajuste fino", "gui": "clic", "orbit": "girar", "pan": "desplazar", "perturb": "perturbar"}
			draw_string(font, c + Vector2(20, 5), str(names.get(ctrl.drag_mode, "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col2)
