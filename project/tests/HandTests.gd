extends Node
## HandTests — Pruebas del seguimiento de manos (sin cámara).
##   Godot --headless --path project -- mfmanos
## Genera manos sintéticas con la geometría de MediaPipe (21 puntos, en metros y en
## coordenadas de imagen) y recorre las tres capas: filtro One Euro, reconocedor de
## gestos y controlador del laboratorio. Al final, si hay Python con mediapipe,
## lanza mf_hands.py --selftest (modelo real + UDP real, sin cámara).

var lab: MathLab
var ok: int = 0
var fail: int = 0
var t: float = 1000.0

func check(cond: bool, name: String) -> void:
	if cond:
		ok += 1
		print("  [OK]   %s" % name)
	else:
		fail += 1
		print("  [FALLO] %s" % name)

func run() -> void:
	print("[TEST] Seguimiento de manos...")
	await get_tree().process_frame
	_t_one_euro()
	_t_classify()
	_t_hysteresis()
	_t_debounce_and_cursor()
	_t_zoom_events()
	_t_pinch_phases()
	_t_grab_events()
	await _t_controller()
	await _t_udp()
	await _t_sidecar()
	print("[TEST] Manos: %d OK, %d FALLOS" % [ok, fail])
	get_tree().quit(1 if fail > 0 else 0)

# --- Manos sintéticas ------------------------------------------------------------------

const WRIST := Vector3(0, 0.09, 0)
const OPEN := [Vector3(0, 0.09, 0),
	Vector3(-0.025, 0.075, 0), Vector3(-0.045, 0.055, 0), Vector3(-0.06, 0.035, 0), Vector3(-0.07, 0.015, 0),
	Vector3(-0.022, 0, 0), Vector3(-0.025, -0.035, 0), Vector3(-0.027, -0.058, 0), Vector3(-0.028, -0.078, 0),
	Vector3(0, -0.003, 0), Vector3(0, -0.042, 0), Vector3(0, -0.067, 0), Vector3(0, -0.088, 0),
	Vector3(0.02, 0, 0), Vector3(0.022, -0.035, 0), Vector3(0.023, -0.058, 0), Vector3(0.024, -0.076, 0),
	Vector3(0.038, 0.01, 0), Vector3(0.043, -0.015, 0), Vector3(0.046, -0.032, 0), Vector3(0.048, -0.048, 0)]
const SCALE := 2.2   # metros → coordenadas de imagen (mano ≈ 20 % de la imagen)

static func _curl(w: Array, mcp: int) -> void:
	var m: Vector3 = w[mcp]
	w[mcp + 1] = m + Vector3(0, -0.025, -0.01)
	w[mcp + 2] = m + Vector3(0, -0.012, -0.03)
	w[mcp + 3] = m + Vector3(0, 0.008, -0.022)

static func _fold_thumb(w: Array) -> void:
	w[2] = Vector3(-0.035, 0.05, -0.01)
	w[3] = Vector3(-0.02, 0.03, -0.025)
	w[4] = Vector3(-0.005, 0.02, -0.03)

## Mundo (m) de una pose: open, point, fist o pinch (con la separación pinch_cm).
static func world(pose: String, pinch_cm: float = 1.0) -> Array:
	var w := OPEN.duplicate()
	match pose:
		"point":
			_fold_thumb(w)
			for m in [9, 13, 17]:
				_curl(w, m)
		"fist":
			_fold_thumb(w)
			for m in [5, 9, 13, 17]:
				_curl(w, m)
		"pinch":
			w[2] = Vector3(-0.045, 0.05, -0.005)
			w[3] = Vector3(-0.055, 0.03, -0.015)
			w[4] = Vector3(-0.055, 0.01, -0.025)
			w[6] = Vector3(-0.035, -0.03, -0.01)
			w[7] = Vector3(-0.045, -0.03, -0.025)
			w[8] = w[4] + Vector3(0, -pinch_cm / 100.0, 0)
			for m in [9, 13, 17]:
				_curl(w, m)
	return w

## Mano como la publica HandTracker, con el ancla (punta del índice, o punto medio
## del pellizco) en la posición de pantalla q.
func hand(pose: String, q: Vector2, label: String = "Right", pinch_cm: float = 1.0, rec: GestureRecognizer = null, smul: float = 1.0) -> Dictionary:
	var w := world(pose, pinch_cm)
	var anchor: Vector3 = (w[4] + w[8]) * 0.5 if pose == "pinch" else w[8]
	var r := rec if rec != null else GestureRecognizer.new()
	var target := r.from_screen(q)
	var lm := PackedVector3Array()
	var wlm := PackedVector3Array()
	for p in w:
		var d: Vector3 = p - anchor
		lm.append(Vector3(target.x + d.x * SCALE * smul, target.y + d.y * SCALE * smul, p.z))
		wlm.append(p)
	return {"label": label, "score": 0.98, "lm": lm, "wlm": wlm, "t": t}

func step_time(dt: float = 1.0 / 60.0) -> float:
	t += dt
	return t

# --- Filtro One Euro -----------------------------------------------------------------------

func _t_one_euro() -> void:
	var f := OneEuroFilter.new(1.0, 10.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var tt := 0.0
	var raw := []
	var out := []
	for i in range(240):
		tt += 1.0 / 60.0
		var v := 0.5 + rng.randfn(0.0, 0.004)
		raw.append(v)
		out.append(float(f.filter(v, tt)))
	var sr := _std(raw.slice(60))
	var so := _std(out.slice(60))
	check(so < sr / 3.0, "One Euro: en reposo el temblor baja ×%.1f (σ %.4f → %.4f)" % [sr / maxf(so, 1e-9), sr, so])
	var g := OneEuroFilter.new(1.0, 10.0)
	var lag := 0.0
	tt = 0.0
	for i in range(60):
		tt += 1.0 / 60.0
		var truth := 0.2 + 1.5 * tt
		lag = absf(float(g.filter(truth, tt)) - truth)
	var h := OneEuroFilter.new(1.0, 0.0)
	var lag0 := 0.0
	tt = 0.0
	for i in range(60):
		tt += 1.0 / 60.0
		var truth2 := 0.2 + 1.5 * tt
		lag0 = absf(float(h.filter(truth2, tt)) - truth2)
	check(lag < 0.03 and lag < lag0 / 5.0, "One Euro: en un movimiento rápido β reduce el retardo (%.3f frente a %.3f sin β)" % [lag, lag0])
	var v3 = OneEuroFilter.new().filter(Vector3(1, 2, 3), 0.0)
	check(typeof(v3) == TYPE_VECTOR3 and v3 == Vector3(1, 2, 3), "One Euro: filtra Vector3 componente a componente")

static func _std(a: Array) -> float:
	var m := 0.0
	for x in a: m += float(x)
	m /= a.size()
	var s := 0.0
	for x in a: s += (float(x) - m) * (float(x) - m)
	return sqrt(s / a.size())

# --- Reconocedor -----------------------------------------------------------------------------

func _t_classify() -> void:
	var r := GestureRecognizer.new()
	var names := {}
	for pose in ["open", "point", "fist", "pinch"]:
		var st := r._new_state()
		names[pose] = r.classify(st, hand(pose, Vector2(0.5, 0.5)))
	check(names["open"] == GestureRecognizer.Gesture.PALM and names["point"] == GestureRecognizer.Gesture.POINT
		and names["fist"] == GestureRecognizer.Gesture.FIST and names["pinch"] == GestureRecognizer.Gesture.PINCH,
		"Gestos: palma abierta, apuntar, puño y pellizco se clasifican bien %s" % str(names))
	var stf := r._new_state()
	r.classify(stf, hand("fist", Vector2(0.5, 0.5)))
	check(float(stf["pinch_cm"]) < r.pinch_on_cm and not stf["pinch"], "Gestos: un puño no es un pellizco aunque el pulgar toque el índice (%.1f cm)" % float(stf["pinch_cm"]))

func _t_hysteresis() -> void:
	var r := GestureRecognizer.new()
	var starts := [0]
	var ends := [0]
	r.pinch_started.connect(func(_h, _p): starts[0] += 1)
	r.pinch_ended.connect(func(_h, _p, _c): ends[0] += 1)
	var seq := [6.0, 3.8, 3.6, 3.2, 2.6, 2.2, 3.4, 4.0, 4.3, 3.9, 4.2, 5.2, 6.0]
	var states := []
	for d in seq:
		for k in range(6):
			r.update([hand("pinch", Vector2(0.5, 0.5), "Right", d, r)], step_time())
		states.append(r.gesture_of("Right") == GestureRecognizer.Gesture.PINCH)
	check(not states[1] and not states[3] and states[4] and states[6] and states[7] and states[8] and states[10] and not states[11],
		"Pellizco con histéresis: se activa por debajo de 3 cm y solo se suelta por encima de 4.5 cm")
	check(starts[0] == 1 and ends[0] == 1, "Pellizco: un solo inicio y un solo fin aunque la distancia oscile entre 3 y 4.5 cm")

func _t_debounce_and_cursor() -> void:
	var r := GestureRecognizer.new()
	for k in range(6):
		r.update([hand("point", Vector2(0.4, 0.4), "Right", 1.0, r)], step_time())
	r.update([hand("open", Vector2(0.4, 0.4), "Right", 1.0, r)], step_time())
	var still_point := r.gesture_of("Right") == GestureRecognizer.Gesture.POINT
	for k in range(6):
		r.update([hand("open", Vector2(0.4, 0.4), "Right", 1.0, r)], step_time())
	check(still_point and r.gesture_of("Right") == GestureRecognizer.Gesture.PALM, "Antirrebote: un fotograma suelto no cambia el gesto; mantenido 50 ms sí")
	# Continuidad del cursor al pasar de apuntar a pellizcar.
	var r2 := GestureRecognizer.new()
	var last := [Vector2.ZERO]
	var start_pos := [Vector2(-9, -9)]
	r2.pointed.connect(func(_h, p): last[0] = p)
	r2.pinch_started.connect(func(_h, p): start_pos[0] = p)
	for k in range(6):
		r2.update([hand("point", Vector2(0.6, 0.5), "Right", 1.0, r2)], step_time())
	var wp := world("pinch")
	var wq := world("point")
	# Misma posición de la muñeca: el punto medio del pellizco no coincide con la punta del índice.
	var shift: Vector3 = ((wp[4] + wp[8]) * 0.5 - wq[8]) * SCALE
	var q_pinch := Vector2(0.6, 0.5) + Vector2(shift.x, shift.y) / r2.box_size
	for k in range(6):
		r2.update([hand("pinch", q_pinch, "Right", 1.0, r2)], step_time())
	check(start_pos[0].distance_to(last[0]) < 1e-4 and q_pinch.distance_to(Vector2(0.6, 0.5)) > 0.02,
		"Cursor sin saltos: el pellizco empieza donde estaba el puntero (el punto medio está a %.3f)" % q_pinch.distance_to(Vector2(0.6, 0.5)))

func _t_zoom_events() -> void:
	var r := GestureRecognizer.new()
	var ratio := [1.0]
	var cancelled := [0]
	r.zoom_changed.connect(func(_rt, total): ratio[0] = total)
	r.pinch_ended.connect(func(_h, _p, c): cancelled[0] += 1 if c else 0)
	for k in range(6):
		r.update([hand("pinch", Vector2(0.4, 0.5), "Right", 1.0, r), hand("pinch", Vector2(0.6, 0.5), "Left", 1.0, r)], step_time())
	for k in range(10):
		var s := 0.1 + 0.01 * (k + 1)
		r.update([hand("pinch", Vector2(0.5 - s, 0.5), "Right", 1.0, r), hand("pinch", Vector2(0.5 + s, 0.5), "Left", 1.0, r)], step_time())
	check(r.zooming and absf(ratio[0] - 2.0) < 0.05 and cancelled[0] == 2, "Dos manos: al separar los pellizcos el zoom es ×%.2f (distancia doble) y los arrastres se anulan" % ratio[0])
	for k in range(6):
		r.update([hand("pinch", Vector2(0.3, 0.5), "Right", 1.0, r), hand("point", Vector2(0.7, 0.5), "Left", 1.0, r)], step_time())
	check(not r.zooming, "Dos manos: al soltar una, el zoom termina")
	for k in range(30):
		r.update([hand("pinch", Vector2(0.3, 0.5), "Right", 1.0, r)], step_time())
	check(not r.states.has("Left"), "Una mano que sale de la imagen se da por perdida a los 0.25 s")

func _t_pinch_phases() -> void:
	var r := GestureRecognizer.new()
	var seen := []
	for d in [10.0, 6.0, 2.5, 2.5, 2.5, 2.5, 2.5, 4.0, 5.2]:
		r.update([hand("pinch", Vector2(0.5, 0.5), "Right", d, r)], step_time())
		var ph := r.pinch_phase("Right")
		if seen.is_empty() or seen[seen.size() - 1] != ph:
			seen.append(ph)
	check(seen.slice(0, 5) == ["lejos", "acercando", "cerrando", "activo", "soltando"], "Medidor del pellizco: lejos → acercando → cerrando → activo → soltando %s" % str(seen))

func _t_grab_events() -> void:
	var r := GestureRecognizer.new()
	var started := [0]
	var ended := [0]
	var acc := [Vector3.ZERO, 0.0]
	r.grab_started.connect(func(): started[0] += 1)
	r.grab_ended.connect(func(): ended[0] += 1)
	r.grab_moved.connect(func(d, a):
		acc[0] += d
		acc[1] += a)
	# Un solo puño no agarra.
	for k in range(6):
		r.update([hand("fist", Vector2(0.4, 0.5), "Right", 1.0, r), hand("point", Vector2(0.6, 0.5), "Left", 1.0, r)], step_time())
	var single_ok: bool = started[0] == 0 and r.gesture_of("Right") == GestureRecognizer.Gesture.FIST
	for k in range(6):
		r.update([hand("fist", Vector2(0.4, 0.5), "Right", 1.0, r), hand("fist", Vector2(0.6, 0.5), "Left", 1.0, r)], step_time())
	check(single_ok and started[0] == 1 and r.grabbing, "Dos puños: un puño solo no hace nada; con los dos empieza el agarre")
	for k in range(10):
		var dx := 0.01 * (k + 1)
		r.update([hand("fist", Vector2(0.4 + dx, 0.5), "Right", 1.0, r), hand("fist", Vector2(0.6 + dx, 0.5), "Left", 1.0, r)], step_time())
	var moved: Vector3 = acc[0]
	check(absf(moved.x - 0.1) < 0.005 and absf(moved.y) < 0.005 and absf(moved.z) < 0.01, "Dos puños: mover las dos manos traslada la escena (Δx = %.3f)" % moved.x)
	acc[0] = Vector3.ZERO
	for k in range(10):
		var sm := 1.0 + 0.02 * (k + 1)
		r.update([hand("fist", Vector2(0.5, 0.5), "Right", 1.0, r, sm), hand("fist", Vector2(0.7, 0.5), "Left", 1.0, r, sm)], step_time())
	var depth: float = (acc[0] as Vector3).z
	check(absf(depth - log(1.2)) < 0.03, "Dos puños: acercar las manos a la cámara (×1.2 de tamaño) mueve en profundidad (ln = %.3f)" % depth)
	acc[1] = 0.0
	for k in range(10):
		var dy := 0.01 * (k + 1)
		r.update([hand("fist", Vector2(0.5, 0.5 - dy), "Right", 1.0, r, 1.2), hand("fist", Vector2(0.7, 0.5 + dy), "Left", 1.0, r, 1.2)], step_time())
	var ang: float = acc[1]
	check(ang > 0.3, "Dos puños: girar las manos como un volante da un ángulo (%.2f rad)" % ang)
	for k in range(6):
		r.update([hand("fist", Vector2(0.5, 0.4), "Right", 1.0, r), hand("open", Vector2(0.7, 0.6), "Left", 1.0, r)], step_time())
	check(ended[0] == 1 and not r.grabbing, "Dos puños: al abrir una mano termina el agarre")

# --- Controlador sobre el laboratorio real --------------------------------------------------

func _feed(ctrl: VirtualLabController, hands: Array, frames: int = 1) -> void:
	for k in range(frames):
		var tt := step_time()
		var hs := []
		for h in hands:
			var c: Dictionary = (h as Dictionary).duplicate()
			c["t"] = tt
			hs.append(c)
		ctrl._on_hands(hs)

func _slide(ctrl: VirtualLabController, pose: String, a: Vector2, b: Vector2, frames: int) -> void:
	for k in range(frames + 1):
		_feed(ctrl, [hand(pose, a.lerp(b, float(k) / frames), "Right", 1.0, ctrl.recognizer)])

func _t_controller() -> void:
	lab.open_module("onda")
	await get_tree().process_frame
	lab.toggle_hands(false)
	if lab.hands == null:
		lab.hands = VirtualLabController.new()
		lab.add_child(lab.hands)
		lab.hands.setup(lab)
		lab.hands.build_panel(lab.ui)
	var ctrl: VirtualLabController = lab.hands
	ctrl.enabled = true
	ctrl.primary = "Right"
	ctrl.move_mouse = false   # las pruebas no mueven el puntero real del usuario
	var vp := ctrl._vp()
	# Apuntar: el cursor sigue al índice.
	_feed(ctrl, [hand("point", Vector2(0.5, 0.45), "Right", 1.0, ctrl.recognizer)], 6)
	check(ctrl.cursor.distance_to(Vector2(0.5, 0.45) * vp) < 2.0, "Controlador: apuntar mueve el cursor a la punta del índice")
	# Pellizco + arrastre sobre la escena 3D: giro orbital.
	var yaw0: float = lab.cam.yaw
	var q0 := ctrl.recognizer.states["Right"]["pos"] as Vector2
	_slide(ctrl, "pinch", q0, q0, 5)
	var mode: String = ctrl.drag_mode
	_slide(ctrl, "pinch", q0, q0 + Vector2(0.12, 0.0), 12)
	check(mode == "orbit" and lab.cam.yaw < yaw0 - 0.1, "Controlador: pellizco + arrastre sobre la gráfica 3D la gira (Δyaw = %.2f rad)" % (lab.cam.yaw - yaw0))
	_slide(ctrl, "point", Vector2(0.62, 0.45), Vector2(0.62, 0.45), 6)
	check(ctrl.drag_mode == "", "Controlador: al soltar el pellizco termina el arrastre")
	# Vista superior 2D: desplazamiento.
	lab.set_view(LabCamera.ViewMode.SUPERIOR)
	var tg0: Vector3 = lab.cam.target
	var q1 := ctrl.recognizer.states["Right"]["pos"] as Vector2
	_slide(ctrl, "pinch", q1, q1, 5)
	_slide(ctrl, "pinch", q1, q1 + Vector2(0.0, 0.1), 10)
	check(ctrl.drag_mode == "pan" and lab.cam.target.distance_to(tg0) > 0.05, "Controlador: en la vista superior 2D el pellizco desplaza el plano")
	_slide(ctrl, "point", Vector2(0.5, 0.45), Vector2(0.5, 0.45), 6)
	lab.set_view(LabCamera.ViewMode.PERSPECTIVA)
	# Zoom con las dos manos.
	var d0: float = lab.cam.distance
	for k in range(6):
		_feed(ctrl, [hand("pinch", Vector2(0.42, 0.5), "Right", 1.0, ctrl.recognizer), hand("pinch", Vector2(0.58, 0.5), "Left", 1.0, ctrl.recognizer)])
	for k in range(12):
		var s := 0.08 + 0.01 * (k + 1)
		_feed(ctrl, [hand("pinch", Vector2(0.5 - s, 0.5), "Right", 1.0, ctrl.recognizer), hand("pinch", Vector2(0.5 + s, 0.5), "Left", 1.0, ctrl.recognizer)])
	var want := pow(2.5, -ctrl.zoom_sens)
	check(absf(lab.cam.distance / d0 - want) < 0.03, "Controlador: separar las manos pellizcando ×2.5 acerca la cámara ×%.3f (sensibilidad %.1f: 2.5^−%.1f = %.3f)" % [lab.cam.distance / d0, ctrl.zoom_sens, ctrl.zoom_sens, want])
	_feed(ctrl, [hand("point", Vector2(0.5, 0.45), "Right", 1.0, ctrl.recognizer)], 30)
	# Palma abierta: pausa y, mantenida, reinicia la vista.
	var target_dist := float(lab.module.view()["dist"])
	_feed(ctrl, [hand("open", Vector2(0.5, 0.45), "Right", 1.0, ctrl.recognizer)], 10)
	var froze := ctrl.frozen
	var d_before: float = lab.cam.distance
	_feed(ctrl, [hand("open", Vector2(0.5, 0.45), "Right", 1.0, ctrl.recognizer)], 60)
	check(froze and absf(d_before - target_dist) > 0.5 and absf(lab.cam.distance - target_dist) < 1e-4, "Controlador: la palma abierta congela y, mantenida 1 s, reinicia la vista")
	_feed(ctrl, [hand("point", Vector2(0.5, 0.45), "Right", 1.0, ctrl.recognizer)], 8)
	check(not ctrl.frozen, "Controlador: al cerrar la palma se reanuda la interacción")
	# Dos puños: traslación en pantalla, profundidad y giro.
	var cam: LabCamera = lab.cam
	var right_v: Vector3 = cam.global_transform.basis.x
	var fwd_v: Vector3 = -cam.global_transform.basis.z
	var t0: Vector3 = cam.target
	for k in range(6):
		_feed(ctrl, [hand("fist", Vector2(0.4, 0.5), "Right", 1.0, ctrl.recognizer), hand("fist", Vector2(0.6, 0.5), "Left", 1.0, ctrl.recognizer)])
	var gmode: String = ctrl.drag_mode
	for k in range(10):
		var dx := 0.01 * (k + 1)
		_feed(ctrl, [hand("fist", Vector2(0.4 + dx, 0.5), "Right", 1.0, ctrl.recognizer), hand("fist", Vector2(0.6 + dx, 0.5), "Left", 1.0, ctrl.recognizer)])
	var shift: Vector3 = cam.target - t0
	check(gmode == "grab" and shift.dot(right_v) < -0.05, "Controlador: con dos puños la escena se arrastra con las manos (Δ = %.2f)" % shift.length())
	var t1: Vector3 = cam.target
	for k in range(10):
		var sm := 1.0 + 0.02 * (k + 1)
		_feed(ctrl, [hand("fist", Vector2(0.5, 0.5), "Right", 1.0, ctrl.recognizer, sm), hand("fist", Vector2(0.7, 0.5), "Left", 1.0, ctrl.recognizer, sm)])
	check((cam.target - t1).dot(fwd_v) > 0.1, "Controlador: acercar los dos puños a la cámara mueve la escena en profundidad")
	var y1: float = cam.yaw
	for k in range(10):
		var dy := 0.01 * (k + 1)
		_feed(ctrl, [hand("fist", Vector2(0.5, 0.5 - dy), "Right", 1.0, ctrl.recognizer, 1.2), hand("fist", Vector2(0.7, 0.5 + dy), "Left", 1.0, ctrl.recognizer, 1.2)])
	check(absf(cam.yaw - y1) > 0.3, "Controlador: girar los dos puños como un volante rota la escena (Δyaw = %.2f)" % (cam.yaw - y1))
	_feed(ctrl, [hand("point", Vector2(0.5, 0.45), "Right", 1.0, ctrl.recognizer)], 30)
	check(ctrl.drag_mode == "", "Controlador: al soltar los puños termina el agarre")
	# Precisión adaptativa: el mismo recorrido gira menos si la mano va despacio.
	var qa := ctrl.recognizer.states["Right"]["pos"] as Vector2
	_slide(ctrl, "pinch", qa, qa, 5)
	var ya: float = cam.yaw
	_slide(ctrl, "pinch", qa, qa + Vector2(60.0 / vp.x, 0.0), 60)
	var slow_d: float = absf(cam.yaw - ya)
	_slide(ctrl, "point", qa, qa, 30)
	var qb0 := ctrl.recognizer.states["Right"]["pos"] as Vector2
	_slide(ctrl, "pinch", qb0, qb0, 5)
	var yb: float = cam.yaw
	_slide(ctrl, "pinch", qb0, qb0 + Vector2(60.0 / vp.x, 0.0), 3)
	var fast_d: float = absf(cam.yaw - yb)
	_slide(ctrl, "point", qb0, qb0, 30)
	check(slow_d < fast_d * 0.5 and absf(slow_d / fast_d - ctrl.slow_gain) < 0.12, "Pellizco con precisión adaptativa: despacio gira ×%.2f de lo que gira rápido (ganancia lenta %.2f)" % [slow_d / maxf(fast_d, 1e-9), ctrl.slow_gain])
	# Deslizador: ajuste fino con pellizco (sin precisión adaptativa para medir el factor fijo).
	ctrl.adaptive = false
	var slider: HSlider = null
	for c in lab.params_box.find_children("*", "HSlider", true, false):
		if str(c.get_meta("lab_param", "")) == "Velocidad de onda c":
			slider = c
	await get_tree().process_frame
	var center := slider.get_global_rect().get_center()
	var v0 := slider.value
	var qs := center / vp
	_slide(ctrl, "point", qs, qs, 30)
	var qn := ctrl.recognizer.states["Right"]["pos"] as Vector2
	_slide(ctrl, "pinch", qn, qn, 5)
	var smode: String = ctrl.drag_mode
	_slide(ctrl, "pinch", qn, qn + Vector2(60.0 / vp.x, 0.0), 10)
	var dv := slider.value - v0
	var expected := 60.0 * (slider.max_value - slider.min_value) / (slider.size.x * ctrl.fine)
	var hit: Control = VirtualLabController.control_at(lab.ui, center)
	check(smode == "slider" and dv > expected * 0.6 and dv < expected * 1.4, "Controlador: pellizco sobre un deslizador = ajuste fino (Δ = %.3f; esperado %.3f con ×%.0f) [modo %s, bajo el centro: %s, cursor %s, centro %s]" % [dv, expected, ctrl.fine, smode, hit.get_class() if hit else "nada", str(ctrl.cursor), str(center)])
	_slide(ctrl, "point", qn, qn, 6)
	ctrl.adaptive = true
	# Botón: el pellizco hace clic.
	var btn: Button = null
	for c in lab.params_box.find_children("*", "Button", true, false):
		if c is Button and not (c is CheckBox) and not (c is OptionButton) and (c as Button).text == "Quitar fuentes":
			btn = c
	var clicks := [0]
	btn.pressed.connect(func(): clicks[0] += 1)
	var qb := btn.get_global_rect().get_center() / vp
	_slide(ctrl, "point", qb, qb, 30)
	var qb2 := ctrl.recognizer.states["Right"]["pos"] as Vector2
	_slide(ctrl, "pinch", qb2, qb2, 5)
	var bmode: String = ctrl.drag_mode
	_slide(ctrl, "point", qb2, qb2, 6)
	var inj: Array = ctrl.injected.slice(maxi(0, ctrl.injected.size() - 2))
	var inj_ok: bool = inj.size() == 2 and inj[0][0] == true and inj[1][0] == false and btn.get_global_rect().has_point(inj[0][1]) and btn.get_global_rect().has_point(inj[1][1])
	check(bmode == "gui" and inj_ok, "Controlador: pellizcar sobre un botón inyecta pulsación y liberación dentro del botón")
	if DisplayServer.get_name() != "headless":
		check(clicks[0] == 1, "Controlador: con ventana real el botón recibe exactamente un clic")
	else:
		print("  [--]   En modo headless la interfaz no recibe eventos inyectados: el clic real se prueba con ventana")
	ctrl.enabled = false
	ctrl._cancel_drag()

# --- Canal UDP ------------------------------------------------------------------------------

func _t_udp() -> void:
	var tr := HandTracker.new()
	add_child(tr)
	tr.load_config()
	var port := 18797
	check(tr._udp.bind(port, "127.0.0.1") == OK, "UDP: HandTracker escucha solo en 127.0.0.1")
	tr.running = true
	var got := [0]
	tr.hands_updated.connect(func(hs): got[0] = hs.size())
	var peer := PacketPeerUDP.new()
	peer.set_dest_address("127.0.0.1", port)
	var h := hand("point", Vector2(0.5, 0.5))
	var lm := []
	var wlm := []
	for i in range(21):
		lm.append([h["lm"][i].x, h["lm"][i].y, h["lm"][i].z])
		wlm.append([h["wlm"][i].x, h["wlm"][i].y, h["wlm"][i].z])
	var pkt := {"type": "hands", "t_cap": HandTracker.now(), "inf_ms": 7.5, "hands": [{"label": "Right", "score": 0.9, "lm": lm, "wlm": wlm}]}
	pkt["token"] = "token-falso"
	peer.put_packet(JSON.stringify(pkt).to_utf8_buffer())
	for k in range(5):
		await get_tree().process_frame
	var ignored: bool = got[0] == 0
	pkt["token"] = tr.token
	peer.put_packet(JSON.stringify(pkt).to_utf8_buffer())
	for k in range(5):
		await get_tree().process_frame
	check(ignored and got[0] == 1 and absf(tr.inference_ms - 7.5) < 1e-6, "UDP: se ignoran los paquetes sin el token y se aceptan los buenos")
	tr.stop()
	tr.queue_free()

# --- Proceso de Python (modelo real, sin cámara) ---------------------------------------------

func _t_sidecar() -> void:
	var tr := HandTracker.new()
	add_child(tr)
	tr.load_config()
	var out := []
	var code := OS.execute(tr.python, ["-c", "import mediapipe, cv2"], out, true)
	if code != 0:
		print("  [--]   Sin Python con mediapipe y opencv: se omite la autoprueba de mf_hands.py")
		tr.queue_free()
		return
	var rec := GestureRecognizer.new()
	var points := [0]
	rec.pointed.connect(func(_h, _p): points[0] += 1)
	tr.hands_updated.connect(func(hs): rec.update(hs, hs[0]["t"] if not hs.is_empty() else HandTracker.now()))
	check(tr.start(true), "Autoprueba: se lanza mf_hands.py (%s)" % tr.find_script().get_file())
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 40000 and not tr.selftest_ok and tr.status_level != "error":
		await get_tree().process_frame
	check(tr.selftest_ok and tr.inference_ms > 0.0 and tr.inference_ms < 60.0, "Autoprueba: MediaPipe carga el modelo (inferencia %.1f ms) y los datos llegan por UDP" % tr.inference_ms)
	check(points[0] > 10, "Autoprueba: la mano sintética del proceso se reconoce como «apuntar» (%d fotogramas)" % points[0])
	tr.stop()
	tr.queue_free()
