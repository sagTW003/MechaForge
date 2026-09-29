class_name GestureRecognizer
extends RefCounted
## GestureRecognizer — Capa 2 del seguimiento de manos: gestos y máquina de estados.
##
## Recibe las manos filtradas de HandTracker y emite eventos de alto nivel:
##
##   Gesto (por mano)                          Señales («onX» del diseño)
##   Apuntar: índice extendido, resto cerrados  pointed(hand, pos)                      onPoint
##   Pellizco pulgar–índice                     pinch_started / pinch_moved / pinch_ended  onPinchStart/Move/End
##   Pellizco con las dos manos                 zoom_started / zoom_changed / zoom_ended   onZoomStart/Move/End
##   Palma abierta (5 dedos extendidos)         palm_started / palm_held / palm_reset / palm_ended
##
## · Las posiciones pos van en [0, 1]² de pantalla, tras la «zona de interacción»:
##   un rectángulo cómodo de la imagen de la cámara (a la altura del pecho, sin
##   levantar el brazo) que se estira a toda la pantalla.
## · Histéresis: el pellizco se activa por debajo de pinch_on_cm (3 cm) y solo se
##   suelta por encima de pinch_off_cm (4.5 cm); los dedos extendidos igual.
## · Antirrebote: un gesto nuevo debe mantenerse confirm_time (50 ms) para contar.
## · Sin saltos del cursor: al pasar de apuntar (punta del índice) a pellizcar (punto
##   medio pulgar–índice) se conserva la posición con un desfase que luego se disipa.
## · Distancias en coordenadas métricas de MediaPipe (independientes de lo cerca que
##   esté la mano de la cámara).

signal pointed(hand: String, pos: Vector2)
signal pinch_started(hand: String, pos: Vector2)
signal pinch_moved(hand: String, pos: Vector2, delta: Vector2)
signal pinch_ended(hand: String, pos: Vector2, cancelled: bool)
signal zoom_started(distance: float)
signal zoom_changed(ratio: float, total: float)
signal zoom_ended()
signal palm_started(hand: String)
signal palm_held(hand: String, progress: float)
signal palm_reset(hand: String)
signal palm_ended(hand: String)
signal gesture_changed(hand: String, gesture: int)
signal hand_lost(hand: String)

enum Gesture { NONE, IDLE, POINT, PINCH, PALM }
const NAMES := ["sin mano", "reposo", "apuntar", "pellizco", "palma abierta"]

# Índices de MediaPipe Hands.
const WRIST := 0
const THUMB_TIP := 4
const INDEX_MCP := 5
const INDEX_TIP := 8
const PINKY_MCP := 17
const TIPS := [8, 12, 16, 20]
const PIPS := [6, 10, 14, 18]

var pinch_on_cm: float = 3.0
var pinch_off_cm: float = 4.5
var ext_on: float = 1.18        # |muñeca–punta| / |muñeca–PIP| para pasar a extendido
var ext_off: float = 1.05       # … y para volver a cerrado
var thumb_on: float = 1.4       # |pulgar–MCP meñique| / ancho de la palma
var thumb_off: float = 1.2
var spread_min: float = 1.15    # |índice–meñique| en las puntas / ancho de la palma (palma abierta)
var release_cm: float = 1.0     # separación sobre el mínimo del pellizco que indica que se está soltando
var pinch_reach: float = 0.95   # |punta del índice – centro de la palma| / ancho: pellizco delante de la mano, no un puño
var confirm_time: float = 0.05
var palm_reset_time: float = 1.0
var lost_time: float = 0.25
var offset_decay: float = 0.12  # s: vida media del desfase del cursor tras un cambio de gesto
var box_center := Vector2(0.5, 0.55)
var box_size := Vector2(0.6, 0.5)

var states := {}                # label → estado de la mano
var zooming: bool = false
var _zoom_d0: float = 0.0
var _zoom_prev: float = 0.0
var _zoom_lock := {}            # manos que deben soltar el pellizco antes de volver a arrastrar
var _t: float = 0.0

## Zona de interacción: imagen → pantalla [0, 1]².
func to_screen(p: Vector3) -> Vector2:
	var q := (Vector2(p.x, p.y) - (box_center - box_size * 0.5)) / box_size
	return q.clamp(Vector2.ZERO, Vector2.ONE)

## Inversa de to_screen (útil para pruebas y para dibujar la zona).
func from_screen(q: Vector2) -> Vector2:
	return box_center - box_size * 0.5 + q * box_size

func gesture_of(label: String) -> int:
	return int(states[label]["gesture"]) if states.has(label) else Gesture.NONE

func _new_state() -> Dictionary:
	return {"gesture": Gesture.NONE, "candidate": Gesture.NONE, "since": 0.0, "ext": [false, false, false, false, false],
		"pinch": false, "pinch_cm": 99.0, "pos": Vector2(-1, -1), "offset": Vector2.ZERO, "palm_since": 0.0,
		"palm_fired": false, "dragging": false, "last_t": 0.0, "anchor": Vector2.ZERO, "pinch_min": 99.0, "holding": false, "reach": 0.0}

## Procesa un fotograma: hands como las publica HandTracker; t en segundos.
func update(hands: Array, t: float) -> void:
	var dt := clampf(t - _t, 0.0, 0.2) if _t > 0.0 else 0.0
	_t = t
	var seen := {}
	for h in hands:
		var label := str(h["label"])
		seen[label] = true
		_update_hand(label, h, t, dt)
	for label in states.keys():
		if not seen.has(label) and t - float(states[label]["last_t"]) > lost_time:
			_lose(label)
	_update_zoom()

## Clasificación instantánea (sin antirrebote) a partir de los landmarks.
func classify(st: Dictionary, h: Dictionary) -> int:
	var w: PackedVector3Array = h["wlm"] if (h["wlm"] as PackedVector3Array).size() >= 21 else h["lm"]
	var ext: Array = st["ext"]
	for f in range(4):
		var r := w[WRIST].distance_to(w[TIPS[f]]) / maxf(1e-6, w[WRIST].distance_to(w[PIPS[f]]))
		ext[f + 1] = r > ext_off if ext[f + 1] else r > ext_on
	var palm_w := maxf(1e-6, w[INDEX_MCP].distance_to(w[PINKY_MCP]))
	var rt := w[THUMB_TIP].distance_to(w[PINKY_MCP]) / palm_w
	ext[0] = rt > thumb_off if ext[0] else rt > thumb_on
	# Pellizco en cm (coordenadas métricas); sin ellas, relativo al ancho de la palma (≈ 7 cm).
	var cm := w[THUMB_TIP].distance_to(w[INDEX_TIP]) * 100.0
	if (h["wlm"] as PackedVector3Array).size() < 21:
		cm = w[THUMB_TIP].distance_to(w[INDEX_TIP]) / palm_w * 7.0
	st["pinch_cm"] = cm
	# En un puño la punta del pulgar también toca el índice doblado: para empezar un
	# pellizco los dedos deben juntarse delante de la mano, lejos del centro de la palma.
	var center := (w[WRIST] + w[INDEX_MCP] + w[PINKY_MCP]) / 3.0
	var reach := w[INDEX_TIP].distance_to(center) / palm_w
	st["reach"] = reach
	st["pinch"] = cm < pinch_off_cm if st["pinch"] else (cm < pinch_on_cm and reach > pinch_reach)
	if st["pinch"]:
		return Gesture.PINCH
	var spread := w[INDEX_TIP].distance_to(w[20]) / palm_w
	if ext[0] and ext[1] and ext[2] and ext[3] and ext[4] and spread > spread_min:
		return Gesture.PALM
	if ext[1] and not ext[2] and not ext[3] and not ext[4]:
		return Gesture.POINT
	return Gesture.IDLE

func _update_hand(label: String, h: Dictionary, t: float, dt: float) -> void:
	if not states.has(label):
		states[label] = _new_state()
	var st: Dictionary = states[label]
	st["last_t"] = t
	var lm: PackedVector3Array = h["lm"]
	var tip := to_screen(lm[INDEX_TIP])
	var mid := to_screen((lm[THUMB_TIP] + lm[INDEX_TIP]) * 0.5)
	var raw := classify(st, h)
	# Antirrebote: el gesto candidato debe mantenerse confirm_time.
	if raw != int(st["gesture"]):
		if raw != int(st["candidate"]):
			st["candidate"] = raw
			st["since"] = t
		if t - float(st["since"]) >= confirm_time or int(st["gesture"]) == Gesture.NONE:
			_switch(label, st, raw, t, tip, mid)
	else:
		st["candidate"] = raw
	st["anchor"] = mid if int(st["gesture"]) == Gesture.PINCH else tip
	match int(st["gesture"]):
		Gesture.POINT:
			# Desfase que se disipa: el cursor no salta al cambiar de gesto.
			st["offset"] = (st["offset"] as Vector2) * pow(0.5, dt / offset_decay) if dt > 0.0 else st["offset"]
			# Deriva del clic: al empezar a pellizcar, la punta del índice baja hacia el
			# pulgar. Con los dedos ya cerca (bajo el umbral de soltar) el cursor se fija.
			if float(st["pinch_cm"]) >= pinch_off_cm or (st["pos"] as Vector2).x < 0.0:
				st["pos"] = tip + (st["offset"] as Vector2)
			pointed.emit(label, st["pos"])
		Gesture.PINCH:
			# Deriva al soltar: si los dedos se separan más de release_cm desde el mínimo
			# de este pellizco, se está soltando: el punto se queda quieto.
			var cm := float(st["pinch_cm"])
			st["pinch_min"] = minf(float(st["pinch_min"]), cm)
			if cm > float(st["pinch_min"]) + release_cm:
				st["holding"] = true
			else:
				if st["holding"]:
					st["offset"] = (st["pos"] as Vector2) - mid   # se retoma sin salto
					st["holding"] = false
				var p: Vector2 = mid + (st["offset"] as Vector2)
				var delta: Vector2 = p - (st["pos"] as Vector2)
				st["pos"] = p
				if st["dragging"] and not zooming:
					pinch_moved.emit(label, p, delta)
		Gesture.PALM:
			var prog := clampf((t - float(st["palm_since"])) / palm_reset_time, 0.0, 1.0)
			palm_held.emit(label, prog)
			if prog >= 1.0 and not st["palm_fired"]:
				st["palm_fired"] = true
				palm_reset.emit(label)

func _switch(label: String, st: Dictionary, g: int, t: float, tip: Vector2, mid: Vector2) -> void:
	var old := int(st["gesture"])
	if old == Gesture.PINCH:
		if st["dragging"]:
			pinch_ended.emit(label, st["pos"], false)
		st["dragging"] = false
		_zoom_lock.erase(label)
	elif old == Gesture.PALM:
		palm_ended.emit(label)
	var prev: Vector2 = st["pos"]
	st["gesture"] = g
	match g:
		Gesture.PINCH:
			st["offset"] = prev - mid if prev.x >= 0.0 else Vector2.ZERO
			st["pos"] = mid + (st["offset"] as Vector2)
			st["pinch_min"] = float(st["pinch_cm"])
			st["holding"] = false
			if not zooming and not _zoom_lock.has(label):
				st["dragging"] = true
				pinch_started.emit(label, st["pos"])
		Gesture.POINT:
			st["offset"] = prev - tip if prev.x >= 0.0 else Vector2.ZERO
			st["pos"] = tip + (st["offset"] as Vector2)
		Gesture.PALM:
			st["palm_since"] = t
			st["palm_fired"] = false
			palm_started.emit(label)
	gesture_changed.emit(label, g)

func _lose(label: String) -> void:
	var st: Dictionary = states[label]
	match int(st["gesture"]):
		Gesture.PINCH:
			if st["dragging"]:
				pinch_ended.emit(label, st["pos"], false)
		Gesture.PALM:
			palm_ended.emit(label)
	states.erase(label)
	_zoom_lock.erase(label)
	hand_lost.emit(label)

## Pellizco con las dos manos: la distancia entre ambos pellizcos hace zoom.
func _update_zoom() -> void:
	var pinching := []
	for label in states:
		if int(states[label]["gesture"]) == Gesture.PINCH:
			pinching.append(label)
	if pinching.size() >= 2:
		var d := (states[pinching[0]]["anchor"] as Vector2).distance_to(states[pinching[1]]["anchor"])
		if not zooming:
			zooming = true
			_zoom_d0 = d
			_zoom_prev = d
			for label in pinching:
				if states[label]["dragging"]:
					states[label]["dragging"] = false
					pinch_ended.emit(label, states[label]["pos"], true)
			zoom_started.emit(d)
		elif _zoom_prev > 1e-4 and _zoom_d0 > 1e-4:
			zoom_changed.emit(d / _zoom_prev, d / _zoom_d0)
			_zoom_prev = d
	elif zooming:
		zooming = false
		zoom_ended.emit()
		for label in pinching:
			_zoom_lock[label] = true
