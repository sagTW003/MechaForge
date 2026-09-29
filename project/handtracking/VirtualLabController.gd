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
##   Dos puños          agarra la escena: moverlos la traslada en 3D (pantalla y
##                      profundidad, acercando o alejando las manos de la cámara) y
##                      girarlos como un volante la rota.
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
var grab_gain: float = 1.0      # traslación con dos puños
var grab_depth: float = 1.5     # profundidad: fracción de la distancia de la cámara por unidad de ln(escala)
var grab_rotate: bool = true    # girar con los dos puños («volante»)
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
	grab_rotate = bool(s.get("grab_rotate", grab_rotate))
	recognizer.pinch_on_cm = float(s.get("pinch_on", recognizer.pinch_on_cm))
	recognizer.pinch_off_cm = float(s.get("pinch_off", recognizer.pinch_off_cm))
	var bs := float(s.get("box_size", 0.6))
	recognizer.box_size = Vector2(bs, bs * 0.8333)
	recognizer.box_center = Vector2(0.5, float(s.get("box_y", 0.55)))

func save_settings() -> void:
	tracker.settings = {"primary": primary, "orbit_gain": orbit_gain, "fine": fine, "skeleton": show_skeleton, "move_mouse": move_mouse,
		"pinch_on": recognizer.pinch_on_cm, "pinch_off": recognizer.pinch_off_cm,
		"box_size": recognizer.box_size.x, "box_y": recognizer.box_center.y, "zoom_sens": zoom_sens,
		"adaptive": adaptive, "slow_gain": slow_gain, "grab_gain": grab_gain, "grab_rotate": grab_rotate}
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

## Dos puños: traslación en el plano de la pantalla, profundidad y giro.
func _on_grab_move(d: Vector3, angle: float) -> void:
	if frozen:
		return
	var vp := _vp()
	lab.cam.pan(d.x * vp.x * grab_gain, d.y * vp.y * grab_gain)
	# Acercar las manos a la cámara (escala mayor) trae la escena hacia uno.
	var fwd: Vector3 = -lab.cam.global_transform.basis.z
	lab.cam.target += fwd * d.z * lab.cam.distance * grab_depth * grab_gain
	if grab_rotate and absf(angle) > 0.002:
		lab.cam.yaw -= angle * 1.5

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
	LabUI.check(box, "Precisión adaptativa (lento = fino)", adaptive, func(v):
		adaptive = v
		save_settings())
	LabUI.slider(box, "Ganancia en movimientos lentos", 0.1, 1.0, 0.05, slow_gain, func(v):
		slow_gain = v
		save_settings())
	LabUI.slider(box, "Sensibilidad del zoom (dos pellizcos)", 0.5, 4.0, 0.1, zoom_sens, func(v):
		zoom_sens = v
		save_settings(), "%.1f")
	LabUI.slider(box, "Sensibilidad de los dos puños", 0.2, 3.0, 0.05, grab_gain, func(v):
		grab_gain = v
		save_settings())
	LabUI.check(box, "Dos puños: girar como un volante", grab_rotate, func(v):
		grab_rotate = v
		save_settings())
	LabUI.check(box, "Mostrar el esqueleto de las manos", show_skeleton, func(v):
		show_skeleton = v
		save_settings())
	LabUI.check(box, "Mover también el puntero del ratón", move_mouse, func(v):
		move_mouse = v
		save_settings())
	LabUI.note(box, "☝ apuntar: cursor · 🤏 pellizco: girar, arrastrar deslizadores, pulsar · 🤏🤏 dos manos: zoom · ✊✊ dos puños: mover la escena en 3D (acercar/alejar las manos = profundidad, girarlas = rotar) · 🖐 palma: pausa (1 s: reinicia la vista). La cámara solo se usa mientras el seguimiento está activo; no se guarda ninguna imagen.")
	panel.set_collapsed(true)
	panel.visible = false
	return panel

# --- HUD: cursor, esqueleto y estado --------------------------------------------------

const BONES := [[0, 1], [1, 2], [2, 3], [3, 4], [0, 5], [5, 6], [6, 7], [7, 8], [5, 9], [9, 10], [10, 11], [11, 12],
	[9, 13], [13, 14], [14, 15], [15, 16], [13, 17], [0, 17], [17, 18], [18, 19], [19, 20]]

const PHASE_COLORS := {"lejos": Color(0.5, 0.55, 0.6), "acercando": Color(1.0, 0.9, 0.35), "cerrando": Color(1.0, 0.75, 0.3),
	"activo": Color(1.0, 0.6, 0.15), "soltando": Color(0.9, 0.9, 1.0)}

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
		# Agarre con dos puños: línea entre las palmas y cruz de movimiento.
		if rec.grabbing:
			var pts := []
			for label in rec.states:
				if int(rec.states[label]["gesture"]) == GestureRecognizer.Gesture.FIST:
					pts.append((rec.states[label]["palm_c"] as Vector2) * vp)
			if pts.size() >= 2:
				var gc := Color(0.55, 1.0, 0.6)
				draw_line(pts[0], pts[1], gc, 3.0, true)
				for q in pts:
					draw_arc(q, 18.0, 0.0, TAU, 36, gc, 3.0, true)
				var m: Vector2 = (pts[0] + pts[1]) * 0.5
				for dirv in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
					draw_line(m + dirv * 6.0, m + dirv * 20.0, gc, 2.5, true)
					draw_line(m + dirv * 20.0, m + dirv * 15.0 + dirv.orthogonal() * 4.0, gc, 2.5, true)
					draw_line(m + dirv * 20.0, m + dirv * 15.0 - dirv.orthogonal() * 4.0, gc, 2.5, true)
				_label(font, m + Vector2(28, -10), "✊✊ mover en 3D · acerca o aleja las manos: profundidad · gíralas: rotar", 13, gc)
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

	## Barra 0–8 cm con la zona de activación (naranja) y la de histéresis (amarilla),
	## la distancia actual pulgar–índice y la fase del gesto.
	func _pinch_meter(font: Font, pos: Vector2, rec: GestureRecognizer, label: String) -> void:
		var ph := rec.pinch_phase(label)
		if ph == "lejos":
			return
		var cm := float(rec.states[label]["pinch_cm"])
		var w := 120.0
		var h := 6.0
		var maxcm := 8.0
		draw_rect(Rect2(pos, Vector2(w, h)), Color(0.05, 0.08, 0.12, 0.9))
		draw_rect(Rect2(pos, Vector2(w * rec.pinch_on_cm / maxcm, h)), Color(1.0, 0.6, 0.2, 0.4))
		draw_rect(Rect2(pos + Vector2(w * rec.pinch_on_cm / maxcm, 0), Vector2(w * (rec.pinch_off_cm - rec.pinch_on_cm) / maxcm, h)), Color(1.0, 0.85, 0.3, 0.22))
		var col: Color = VirtualLabController.PHASE_COLORS.get(ph, Color.WHITE)
		var x := clampf(cm / maxcm, 0.0, 1.0) * w
		draw_rect(Rect2(pos + Vector2(x - 1.5, -3), Vector2(3, h + 6)), col)
		_label(font, pos + Vector2(0, h + 15), "pellizco %.1f cm · %s" % [cm, ph], 11, col)

	## Texto con un fondo oscuro para que se lea sobre cualquier escena.
	func _label(font: Font, pos: Vector2, text: String, size: int, col: Color) -> void:
		var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
		draw_rect(Rect2(pos + Vector2(-4, -sz.y + 3), sz + Vector2(8, 4)), Color(0.02, 0.03, 0.05, 0.72))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
