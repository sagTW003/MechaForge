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
##   Puño con las dos manos (agarrar)           grab_started / grab_moved / grab_ended     onGrabStart/Move/End
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
##   esté la mano de la cámara). Con la mano lejos los puntos son menos precisos: los
##   umbrales del pellizco crecen según el tamaño aparente de la mano (far_px).
## · Reconstrucción 3D de cada mano (cámara estenopeica): la profundidad sale de
##   comparar los huesos de la palma en la imagen (px) con los métricos (m); x e y,
##   de la posición en la imagen a esa profundidad. Así un mismo gesto mide lo mismo
##   con la mano cerca o lejos.
## · Agarre con dos puños (en 3D): el punto medio de los puños mueve la escena en
##   x, y, z; una mano hacia delante y otra hacia atrás la gira; doblar las muñecas
##   la inclina.
## · Modo puño: mientras una mano está en puño (y hasta que se abre) sus pellizcos no
##   cuentan; durante el agarre, un pellizco accidental no lo interrumpe.

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
signal grab_started()
## delta: desplazamiento del punto medio de los puños en metros, en el marco del
## usuario (x derecha, y arriba, z hacia la pantalla). rot (rad): x inclinación de
## las muñecas (arriba hacia la pantalla > 0), y giro horizontal (mano derecha hacia
## la pantalla > 0), z «volante» (mano derecha abajo > 0).
signal grab_moved(delta: Vector3, rot: Vector3)
signal grab_ended()
signal gesture_changed(hand: String, gesture: int)
signal hand_lost(hand: String)

enum Gesture { NONE, IDLE, POINT, PINCH, PALM, FIST }
const NAMES := ["sin mano", "reposo", "apuntar", "pellizco", "palma abierta", "puño"]

# Índices de MediaPipe Hands.
const WRIST := 0
const THUMB_TIP := 4
const INDEX_MCP := 5
const INDEX_TIP := 8
const PINKY_MCP := 17
const TIPS := [8, 12, 16, 20]
const PIPS := [6, 10, 14, 18]
const MEASURE_BONES := [[0, 5], [0, 17], [5, 17], [0, 9]]   # huesos de la palma (no cambian al cerrar la mano)
const NOMINAL_BONES_M := 0.33   # suma típica de esos huesos, si no hay coordenadas métricas
const S_REF := 70.0             # px: tamaño medio de esos huesos por debajo del cual se compensa (mano a ≈ 0.75 m)

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
var box_size := Vector2(0.8, 0.667)
var hfov_deg: float = 62.0      # campo de visión horizontal de la webcam (reconstrucción 3D)
var far_px: float = 12.0        # imprecisión de los puntos (px) que se compensa con la mano lejos
var unlock_time: float = 0.3    # s con la mano abierta tras un puño para volver a pellizcar

var states := {}                # label → estado de la mano
var zooming: bool = false
var grabbing: bool = false
var _grab_prev := {}
var _grab_total := {"move": Vector3.ZERO, "rot": Vector3.ZERO}
var _fist_lock := {}            # manos en «modo puño»: sus pellizcos no cuentan hasta que se abren
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
		"palm_fired": false, "dragging": false, "last_t": 0.0, "anchor": Vector2.ZERO, "pinch_min": 99.0, "holding": false, "reach": 0.0,
		"palm_c": Vector2.ZERO, "size_px": 100.0, "p3": Vector3(0, 0, 0.5), "tilt": 0.0, "far": 0.0, "comp": 0.0,
		"open_since": -1.0}

## Umbrales del pellizco de una mano, con la compensación por distancia.
func on_cm(label: String) -> float:
	return pinch_on_cm + (float(states[label]["comp"]) if states.has(label) else 0.0)

func off_cm(label: String) -> float:
	return pinch_off_cm + (float(states[label]["comp"]) if states.has(label) else 0.0)

## ¿Tiene la mano los pellizcos bloqueados por un puño?
func fist_locked(label: String) -> bool:
	return _fist_lock.has(label)

## Fase del pellizco de una mano (para el medidor del HUD):
## "lejos", "acercando" (a menos de 1.6 × el umbral de soltar), "cerrando" (ya bajo el
## umbral de activación, pendiente del antirrebote), "activo" o "soltando".
## "bloqueado": pellizco de una mano en modo puño (no cuenta hasta que se abra).
func pinch_phase(label: String) -> String:
	if not states.has(label):
		return "lejos"
	var st: Dictionary = states[label]
	var cm := float(st["pinch_cm"])
	var off := off_cm(label)
	var g := int(st["gesture"])
	if g == Gesture.FIST:
		return "lejos"
	if (g == Gesture.PINCH or st["pinch"]) and _fist_lock.has(label):
		return "bloqueado"
	if g == Gesture.PINCH:
		return "soltando" if st["holding"] or cm > off else "activo"
	if st["pinch"]:
		return "cerrando"
	if cm < off * 1.6:
		return "acercando"
	return "lejos"

## Zona de interacción sin recortar (para el agarre, que puede salirse del rectángulo).
func to_box(p: Vector3) -> Vector2:
	return (Vector2(p.x, p.y) - (box_center - box_size * 0.5)) / box_size

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
	_update_grab()

func focal_px(img: Vector2) -> float:
	return img.x * 0.5 / tan(deg_to_rad(hfov_deg) * 0.5)

## Medidas de la mano: tamaño aparente (px), posición 3D en metros respecto a la
## webcam (x derecha, y abajo, z profundidad), inclinación de la muñeca y
## compensación del pellizco por distancia.
func measure(st: Dictionary, h: Dictionary) -> void:
	var lm: PackedVector3Array = h["lm"]
	var w: PackedVector3Array = h["wlm"]
	var has_w := w.size() >= 21
	var img: Vector2 = h.get("img", Vector2(640, 480))
	var sp := 0.0
	var sm := 0.0
	for b in MEASURE_BONES:
		var i0: int = b[0]
		var i1: int = b[1]
		sp += Vector2((lm[i1].x - lm[i0].x) * img.x, (lm[i1].y - lm[i0].y) * img.y).length()
		# Proyección del hueso métrico en el plano de la imagen: la rotación de la mano
		# acorta los dos por igual y no falsea la profundidad.
		if has_w:
			sm += Vector2(w[i1].x - w[i0].x, w[i1].y - w[i0].y).length()
	if not has_w:
		sm = NOMINAL_BONES_M
	sp = maxf(sp, 1.0)
	sm = maxf(sm, 1e-4)
	var size := sp / MEASURE_BONES.size()
	var f := focal_px(img)
	var z := f * sm / sp
	var pc := (lm[WRIST] + lm[INDEX_MCP] + lm[PINKY_MCP]) / 3.0
	st["size_px"] = size
	st["p3"] = Vector3((pc.x - 0.5) * img.x * z / f, (pc.y - 0.5) * img.y * z / f, z)
	st["far"] = clampf((S_REF / size - 1.0) / 1.2, 0.0, 1.0)
	# far_px de error en la imagen equivalen a far_px · (m por px) en la mano.
	st["comp"] = clampf(far_px * (sm / MEASURE_BONES.size()) * 100.0 * (1.0 / size - 1.0 / S_REF), 0.0, 3.0)
	if has_w:
		var v: Vector3 = w[9] - w[WRIST]
		st["tilt"] = atan2(-v.z, -v.y)

## Clasificación instantánea (sin antirrebote) a partir de los landmarks.
func classify(st: Dictionary, h: Dictionary) -> int:
	measure(st, h)
	var has_w := (h["wlm"] as PackedVector3Array).size() >= 21
	var w: PackedVector3Array = h["wlm"] if has_w else h["lm"]
	var ext: Array = st["ext"]
	for f in range(4):
		var r := w[WRIST].distance_to(w[TIPS[f]]) / maxf(1e-6, w[WRIST].distance_to(w[PIPS[f]]))
		ext[f + 1] = r > ext_off if ext[f + 1] else r > ext_on
	var palm_w := maxf(1e-6, w[INDEX_MCP].distance_to(w[PINKY_MCP]))
	var rt := w[THUMB_TIP].distance_to(w[PINKY_MCP]) / palm_w
	ext[0] = rt > thumb_off if ext[0] else rt > thumb_on
	# Pellizco en cm (coordenadas métricas); sin ellas, relativo al ancho de la palma (≈ 7 cm).
	# La profundidad (z) es la coordenada menos fiable, más aún con la mano lejos.
	var far01 := float(st["far"])
	var dv: Vector3 = w[THUMB_TIP] - w[INDEX_TIP]
	var cm := Vector3(dv.x, dv.y, dv.z * lerpf(1.0, 0.5, far01)).length() * 100.0
	if not has_w:
		cm = dv.length() / palm_w * 7.0
	st["pinch_cm"] = cm
	var comp := float(st["comp"])
	# En un puño la punta del pulgar también toca el índice doblado: para empezar un
	# pellizco los dedos deben juntarse delante de la mano, lejos del centro de la palma.
	var center := (w[WRIST] + w[INDEX_MCP] + w[PINKY_MCP]) / 3.0
	var reach := w[INDEX_TIP].distance_to(center) / palm_w
	st["reach"] = reach
	st["pinch"] = cm < pinch_off_cm + comp if st["pinch"] else (cm < pinch_on_cm + comp and reach > pinch_reach - 0.12 * far01)
	if st["pinch"]:
		return Gesture.PINCH
	var spread := w[INDEX_TIP].distance_to(w[20]) / palm_w
	if ext[0] and ext[1] and ext[2] and ext[3] and ext[4] and spread > spread_min:
		return Gesture.PALM
	if ext[1] and not ext[2] and not ext[3] and not ext[4]:
		return Gesture.POINT
	# Puño: los cuatro dedos cerrados con la punta del índice recogida contra la palma
	# (al ir a pellizcar queda delante); el pulgar da igual, también vale hacia arriba.
	if not ext[1] and not ext[2] and not ext[3] and not ext[4] and reach < pinch_reach:
		return Gesture.FIST
	return Gesture.IDLE

func _update_hand(label: String, h: Dictionary, t: float, dt: float) -> void:
	if not states.has(label):
		states[label] = _new_state()
	var st: Dictionary = states[label]
	st["last_t"] = t
	var lm: PackedVector3Array = h["lm"]
	var tip := to_screen(lm[INDEX_TIP])
	var mid := to_screen((lm[THUMB_TIP] + lm[INDEX_TIP]) * 0.5)
	# Centro de la palma en la pantalla (HUD del agarre).
	st["palm_c"] = to_box((lm[WRIST] + lm[INDEX_MCP] + lm[PINKY_MCP]) / 3.0)
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
	_update_lock(label, st, t)
	st["anchor"] = mid if int(st["gesture"]) == Gesture.PINCH else tip
	match int(st["gesture"]):
		Gesture.POINT:
			# Desfase que se disipa: el cursor no salta al cambiar de gesto.
			st["offset"] = (st["offset"] as Vector2) * pow(0.5, dt / offset_decay) if dt > 0.0 else st["offset"]
			# Deriva del clic: al empezar a pellizcar, la punta del índice baja hacia el
			# pulgar. Con los dedos ya cerca (bajo el umbral de soltar) el cursor se fija.
			if float(st["pinch_cm"]) >= pinch_off_cm + float(st["comp"]) or (st["pos"] as Vector2).x < 0.0:
				st["pos"] = tip + (st["offset"] as Vector2)
			pointed.emit(label, st["pos"])
		Gesture.PINCH:
			# Deriva al soltar: si los dedos se separan más de release_cm desde el mínimo
			# de este pellizco, se está soltando: el punto se queda quieto.
			var cm := float(st["pinch_cm"])
			st["pinch_min"] = minf(float(st["pinch_min"]), cm)
			if cm > float(st["pinch_min"]) + release_cm + float(st["comp"]) * 0.5:
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

## Modo puño: un puño bloquea los pellizcos de esa mano hasta que se abre (apuntar,
## palma, o unlock_time sin cerrarla). Evita que al formar o deshacer el puño el
## pulgar sobre el índice cuente como pellizco.
func _update_lock(label: String, st: Dictionary, t: float) -> void:
	var g := int(st["gesture"])
	if g == Gesture.FIST:
		_fist_lock[label] = true
		st["open_since"] = -1.0
	elif _fist_lock.has(label):
		if g == Gesture.POINT or g == Gesture.PALM:
			_fist_lock.erase(label)
		elif g == Gesture.PINCH:
			st["open_since"] = -1.0
		elif float(st["open_since"]) < 0.0:
			st["open_since"] = t
		elif t - float(st["open_since"]) >= unlock_time:
			_fist_lock.erase(label)

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
			if not zooming and not _zoom_lock.has(label) and not _fist_lock.has(label):
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
	_fist_lock.erase(label)
	hand_lost.emit(label)

## Pellizco con las dos manos: la distancia entre ambos pellizcos hace zoom.
func _update_zoom() -> void:
	var pinching := []
	for label in states:
		if int(states[label]["gesture"]) == Gesture.PINCH and not _fist_lock.has(label):
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

## Agarre con los dos puños, en 3D. Empieza con dos puños; sigue mientras las dos
## manos estén cerradas (un pellizco de una mano en modo puño también cuenta).
func _update_grab() -> void:
	var closed := []
	for label in states:
		var g := int(states[label]["gesture"])
		if g == Gesture.FIST or (grabbing and g == Gesture.PINCH and _fist_lock.has(label)):
			closed.append(label)
	if closed.size() >= 2 and not zooming:
		var a: Dictionary = states[closed[0]]
		var b: Dictionary = states[closed[1]]
		var pa: Vector3 = a["p3"]
		var pb: Vector3 = b["p3"]
		var l := pb - pa if pb.x >= pa.x else pa - pb    # de la mano de la izquierda a la de la derecha
		var mid := (pa + pb) * 0.5
		var ang := Vector3((float(a["tilt"]) + float(b["tilt"])) * 0.5, atan2(-l.z, l.x), atan2(l.y, l.x))
		if not grabbing:
			grabbing = true
			for label in closed:
				_fist_lock[label] = true
			_grab_prev = {"mid": mid, "ang": ang}
			_grab_total = {"move": Vector3.ZERO, "rot": Vector3.ZERO}
			grab_started.emit()
		else:
			var pm: Vector3 = _grab_prev["mid"]
			var pang: Vector3 = _grab_prev["ang"]
			# Cámara (x derecha, y abajo, z desde la webcam) → usuario (x derecha, y arriba, z hacia la pantalla).
			var d := Vector3(mid.x - pm.x, pm.y - mid.y, pm.z - mid.z)
			var dr := Vector3(wrapf(ang.x - pang.x, -PI, PI), wrapf(ang.y - pang.y, -PI, PI), wrapf(ang.z - pang.z, -PI, PI))
			_grab_prev = {"mid": mid, "ang": ang}
			_grab_total["move"] = (_grab_total["move"] as Vector3) + d
			_grab_total["rot"] = (_grab_total["rot"] as Vector3) + dr
			grab_moved.emit(d, dr)
	elif grabbing:
		grabbing = false
		grab_ended.emit()

## Desplazamiento (m) y giro (rad) acumulados desde el inicio del agarre.
func grab_total() -> Dictionary:
	return _grab_total.duplicate()

## Posición 3D (m, desde la webcam) de una mano, o null.
func hand_p3(label: String):
	return states[label]["p3"] if states.has(label) else null

## Punto medio del agarre en la pantalla [0, 1]² (HUD), o (-1, -1).
func grab_point() -> Vector2:
	if not grabbing:
		return Vector2(-1, -1)
	var pts := []
	for label in states:
		if int(states[label]["gesture"]) in [Gesture.FIST, Gesture.PINCH]:
			pts.append(states[label]["palm_c"])
	return (pts[0] + pts[1]) * 0.5 if pts.size() >= 2 else Vector2(-1, -1)
