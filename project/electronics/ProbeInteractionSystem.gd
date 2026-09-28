class_name ProbeInteractionSystem
extends Node3D
## ProbeInteractionSystem — Sondas del multímetro: modelo 3D, cables e interacción.
##
## Dos sondas (roja → VΩmA / 10 A, negra → COM) unidas al cuerpo del multímetro
## por cables de silicona con física de cuerda (CableSim: gravedad, holgura y
## contacto con el suelo). En modo «📟 Multímetro»:
##   · arrastra una sonda: su punta sigue al cursor y, cerca de un terminal
##     (agujero de la protoboard, pata de un componente, pin del Arduino), hace
##     un «snap» magnético suave; al soltar queda enganchada;
##   · orientación: 90° (vertical) en agujeros de la protoboard y pines finos;
##     45° inclinada hacia el multímetro en patas y bornes; tumbada si se suelta
##     sobre la mesa;
##   · clic en un terminal coloca la sonda activa (y alterna roja/negra);
##   · clic o rueda sobre el selector giratorio cambia el modo;
##   · clic derecho sobre una sonda la devuelve junto al multímetro.
## Las sondas enganchadas siguen a su terminal: si se mueve o gira la protoboard
## (o la pieza en simulación), se mueven rígidamente con ella.
## También actualiza la pantalla LCD/selector del modelo y genera el pitido de
## continuidad (Web Audio → AudioStreamGenerator, tono de 2.7 kHz).

signal mode_changed(active: bool)

const PROBE_LAYER := 32
const SNAP_PX := 30.0
const CABLE_R := 0.0016
const PROBE_LEN := 0.13            # de la punta al final de la funda

var main: Node
var active: bool = false
var active_probe: String = "roja"
var dragging: String = ""
var _drag_tip: Vector3 = Vector3.ZERO
var _drag_key: String = ""
var _drag_prev: Dictionary = {}
var _probes: Dictionary = {}       # "roja"/"negra" -> {node, cable, plug, last}
var _dial_pick: StaticBody3D
var _audio: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _phase: float = 0.0
var _t: float = 0.0

func _ready() -> void:
	name = "SondasMultimetro"
	for which in ["roja", "negra"]:
		var col := Color(0.8, 0.07, 0.06) if which == "roja" else Color(0.03, 0.03, 0.035)
		var node := _make_probe(col, which)
		add_child(node)
		var cable := MeshInstance3D.new()
		cable.name = "Cable_%s" % which
		var cm := StandardMaterial3D.new()
		cm.albedo_color = col
		cm.roughness = 0.35
		cm.clearcoat_enabled = true
		cm.clearcoat = 0.4
		cable.material_override = cm
		add_child(cable)
		var plug := _make_plug(col)
		add_child(plug)
		_probes[which] = {"node": node, "cable": cable, "plug": plug, "last": [Vector3.INF, Vector3.INF]}
	_dial_pick = StaticBody3D.new()
	_dial_pick.name = "SelectorPick"
	_dial_pick.collision_layer = PROBE_LAYER
	_dial_pick.collision_mask = 0
	_dial_pick.set_meta("dmm_dial", true)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.024
	sh.height = 0.012
	cs.shape = sh
	_dial_pick.add_child(cs)
	add_child(_dial_pick)
	# Pitido de continuidad: generador de audio sintético.
	_audio = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 44100.0
	gen.buffer_length = 0.1
	_audio.stream = gen
	_audio.volume_db = -14.0
	add_child(_audio)
	_set_visible(false)

func _dmm() -> DMMController:
	return main.circuit_rt.dmm if main and main.circuit_rt else null

func has_dmm() -> bool:
	var d := _dmm()
	return d != null and d.part != null and is_instance_valid(d.part)

#region MODELO 3D ---------------------------------------------------------------

func _pmat(c: Color, metal := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 1.0 if metal else 0.0
	m.roughness = 0.22 if metal else 0.3
	if not metal:
		m.clearcoat_enabled = true
		m.clearcoat = 0.5
	return m

func _cyl(r_top: float, r_bot: float, h: float, m: Material, y: float, segs := 20) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r_top; c.bottom_radius = r_bot; c.height = h; c.radial_segments = segs; c.rings = 1
	mi.mesh = c
	mi.material_override = m
	mi.position = Vector3(0, y, 0)
	return mi

## Sonda con la punta en el origen y el mango hacia +Y.
func _make_probe(col: Color, which: String) -> Node3D:
	var n := Node3D.new()
	n.name = "Sonda_%s" % which
	var steel := _pmat(Color(0.82, 0.82, 0.84), true)
	var plastic := _pmat(col)
	n.add_child(_cyl(0.0006, 0.00005, 0.002, steel, 0.001, 12))            # punta cónica
	n.add_child(_cyl(0.0006, 0.0006, 0.013, steel, 0.0085, 12))            # varilla
	n.add_child(_cyl(0.0012, 0.0014, 0.005, plastic, 0.0165))              # aislamiento de la punta
	n.add_child(_cyl(0.0045, 0.0068, 0.003, plastic, 0.0205, 28))          # guarda para los dedos
	n.add_child(_cyl(0.0045, 0.0045, 0.092, plastic, 0.068, 24))           # mango
	for k in range(7):
		n.add_child(_cyl(0.0048, 0.0048, 0.0014, plastic, 0.032 + k * 0.0075, 24))   # anillos de agarre
	n.add_child(_cyl(0.0021, 0.0043, 0.016, plastic, 0.122, 20))           # funda del cable
	var body := StaticBody3D.new()
	body.collision_layer = PROBE_LAYER
	body.collision_mask = 0
	body.set_meta("probe", which)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.008
	cap.height = 0.14
	cs.shape = cap
	cs.position = Vector3(0, 0.07, 0)
	body.add_child(cs)
	n.add_child(body)
	return n

func _make_plug(col: Color) -> Node3D:
	var n := Node3D.new()
	n.add_child(_cyl(0.0042, 0.0042, 0.013, _pmat(col), 0.0085, 20))
	n.add_child(_cyl(0.0035, 0.0045, 0.003, _pmat(col), 0.0165, 20))
	n.add_child(_cyl(0.002, 0.002, 0.004, _pmat(Color(0.8, 0.7, 0.4), true), 0.0015, 12))
	return n

func _set_visible(v: bool) -> void:
	for which in _probes:
		for k in ["node", "cable", "plug"]:
			(_probes[which][k] as Node3D).visible = v
	_dial_pick.collision_layer = PROBE_LAYER if v else 0
	for which in _probes:
		var body := (_probes[which]["node"] as Node).get_child(-1) as StaticBody3D
		if body:
			body.collision_layer = PROBE_LAYER if v else 0

#endregion

#region POSES Y CABLES -----------------------------------------------------------

## ¿El terminal es "fino" (agujero de protoboard o pin DIP)? → sonda vertical.
func _is_fine(key: String) -> bool:
	var parts := key.split(":")
	if parts.size() < 2:
		return false
	var p: PartInstance = main._find_part(parts[0])
	if p == null:
		return false
	for t in p.def.get("terminales", []):
		if str(t["id"]) == parts[1]:
			return bool(t.get("fino", false))
	return false

func _basis_along(h: Vector3) -> Basis:
	var y := h.normalized()
	var x := y.cross(Vector3.UP)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)

func _dmm_center() -> Vector3:
	return main._part_live_xform(_dmm().part).origin

## Pose de la sonda: la punta en el terminal / posición libre / reposo.
func probe_pose(which: String) -> Transform3D:
	var d := _dmm()
	var tip := d.probe_tip(which)
	var to_dmm := _dmm_center() - tip
	to_dmm.y = 0.0
	to_dmm = to_dmm.normalized() if to_dmm.length() > 0.001 else Vector3.BACK
	if dragging == which:
		var lean := (Vector3.UP * 1.7 + to_dmm).normalized()
		var lift := 0.0 if _drag_key != "" else 0.003
		return Transform3D(_basis_along(lean), _drag_tip + Vector3.UP * lift)
	var key := d.probe_key(which)
	if key != "" and main._terminal_live_by_key(key) != null:
		# Si la otra sonda está a menos de 2 cm, ambas se abren en «V» para no chocar.
		var other := "negra" if which == "roja" else "roja"
		var away := Vector3.ZERO
		if d.probe_key(other) != "":
			var ot := d.probe_tip(other)
			var sep := tip - ot
			sep.y = 0.0
			if sep.length() < 0.02:
				away = sep.normalized() if sep.length() > 0.0001 else Vector3.RIGHT * (1.0 if which == "roja" else -1.0)
		if _is_fine(key):
			# 90°: vertical, la punta entra 1.5 mm en el agujero.
			var tilt := (Vector3.UP * 8.0 + to_dmm + away * 3.2).normalized()
			return Transform3D(_basis_along(tilt), tip - Vector3.UP * 0.0015)
		# 45°: apoyada sobre la pata o el borne, inclinada hacia el multímetro.
		return Transform3D(_basis_along((Vector3.UP + (to_dmm + away).normalized()).normalized()), tip)
	# Tumbada sobre la mesa (libre o en reposo junto al multímetro).
	var fp = d.part.estado.get(which, {}).get("pos", null)
	var dir: Vector3
	if fp is Array:
		dir = to_dmm
	else:
		var xf: Transform3D = main._part_live_xform(d.part)
		dir = xf.basis.z.normalized()
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.001 else Vector3.BACK
	return Transform3D(_basis_along(dir), tip)

func _jack_world(which: String) -> Vector3:
	var d := _dmm()
	var xf: Transform3D = main._part_live_xform(d.part)
	var local: Vector3 = ElectronicsVisuals.DMM_JACK_COM
	if which == "roja":
		local = ElectronicsVisuals.DMM_JACK_A if (d.mode == DMMController.Mode.A_DC and d.jack_10a) else ElectronicsVisuals.DMM_JACK_V
	return xf * (local / 1000.0)

func _process(delta: float) -> void:
	_t += delta
	if main == null:
		return
	var show := has_dmm()
	if show != (_probes["roja"]["node"] as Node3D).visible:
		_set_visible(show)
	if not show:
		_beep(false)
		return
	var d := _dmm()
	var dxf: Transform3D = main._part_live_xform(d.part)
	for which in ["roja", "negra"]:
		var pr: Dictionary = _probes[which]
		var pose := probe_pose(which)
		(pr["node"] as Node3D).global_transform = pose
		var jack := _jack_world(which)
		(pr["plug"] as Node3D).global_transform = Transform3D(dxf.basis, jack)
		var a: Vector3 = pose * Vector3(0, PROBE_LEN, 0)
		var b: Vector3 = jack + dxf.basis.y * 0.018
		var last: Array = pr["last"]
		if a.distance_to(last[0]) > 0.0004 or b.distance_to(last[1]) > 0.0004:
			var quick := dragging != ""
			var pts := CableSim.solve(a, b, [], 1.3, 26, 25 if quick else 70)
			(pr["cable"] as MeshInstance3D).mesh = CableRenderer.tube_mesh(pts, CABLE_R, 10)
			pr["last"] = [a, b]
	_dial_pick.global_transform = Transform3D(dxf.basis, dxf * (ElectronicsVisuals.DMM_DIAL / 1000.0))
	# Pantalla, selector y LED del modelo (en edición y su copia en simulación).
	var blink := fmod(_t, 0.25) < 0.14
	for root in main.circuit_rt._visual_roots(d.part):
		ElectronicsVisuals.update_multimeter(root, d, blink)
	_beep(d.beeping)

## Tono de continuidad (onda casi cuadrada suavizada, 2.7 kHz).
func _beep(on: bool) -> void:
	if not on:
		if _audio.playing:
			_audio.stop()
			_playback = null
		return
	if not _audio.playing:
		_audio.play()
		_playback = _audio.get_stream_playback() as AudioStreamGeneratorPlayback
	if _playback == null:
		return
	var n := _playback.get_frames_available()
	var inc := 2700.0 / 44100.0
	for i in range(n):
		_phase = fmod(_phase + inc, 1.0)
		var s := clampf(sin(_phase * TAU) * 3.0, -1.0, 1.0) * 0.35
		_playback.push_frame(Vector2(s, s))

#endregion

#region INTERACCIÓN ---------------------------------------------------------------

func set_active(on: bool) -> void:
	if on and not has_dmm():
		main._ensure_multimeter()
	active = on and has_dmm()
	dragging = ""
	if active:
		main._build_terminal_markers()
		Config.notify("📟 Multímetro: arrastra una sonda (o haz clic en un terminal) para medir. Clic/rueda en el selector cambia el modo. Clic derecho: salir.", 7.0)
	else:
		main._clear_terminal_markers()
	mode_changed.emit(active)

func _ray_hit(screen: Vector2, mask: int) -> Dictionary:
	var ray: Dictionary = main.camera.screen_ray(screen)
	var q := PhysicsRayQueryParameters3D.create(ray["origin"], ray["origin"] + ray["dir"] * 100.0, mask)
	q.collide_with_areas = false
	return main.get_world_3d().direct_space_state.intersect_ray(q)

func _pick(screen: Vector2) -> String:
	var hit := _ray_hit(screen, PROBE_LAYER)
	if hit.is_empty():
		return ""
	var c: Node = hit["collider"]
	if c.has_meta("dmm_dial"):
		return "dial"
	return str(c.get_meta("probe", ""))

## Terminal más cercano al cursor en pantalla (snap magnético).
func _nearest_terminal(screen: Vector2) -> Dictionary:
	var best := {}
	var bd := SNAP_PX
	for tm in main._term_markers:
		var wp: Vector3 = tm["pos"]
		if main.camera.is_position_behind(wp):
			continue
		var dd: float = main.camera.unproject_position(wp).distance_to(screen)
		if dd < bd:
			bd = dd
			best = tm
	return best

## Punto libre bajo el cursor: superficie de una pieza o el suelo.
func _surface_point(screen: Vector2) -> Vector3:
	var hit := _ray_hit(screen, PartInstance.PICK_LAYER | 1)
	if not hit.is_empty():
		return (hit["position"] as Vector3) + (hit["normal"] as Vector3) * 0.0045
	var ray: Dictionary = main.camera.screen_ray(screen)
	var p = Plane(Vector3.UP, 0.0).intersects_ray(ray["origin"], ray["dir"])
	return (p as Vector3) + Vector3.UP * 0.0045 if p != null else _drag_tip

func handle_input(event: InputEvent) -> bool:
	if not active or not has_dmm():
		return false
	var d := _dmm()
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and mb.pressed:
			if _pick(mb.position) == "dial":
				d.set_mode(wrapi(d.mode + (1 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1), 0, 6))
				_mode_notice()
				return true
			return false
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var what := _pick(mb.position)
				if what == "dial":
					d.set_mode(wrapi(d.mode + 1, 0, 6))
					_mode_notice()
					return true
				if what in ["roja", "negra"]:
					_begin_drag(what, mb.position)
					return true
				var tm := _nearest_terminal(mb.position)
				if not tm.is_empty():
					attach(active_probe, main._key(tm["part_uid"], tm["term_id"]))
					active_probe = "negra" if active_probe == "roja" else "roja"
					return true
				return true
			elif dragging != "":
				_end_drag()
				return true
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if dragging != "":
				_cancel_drag()
				return true
			var what2 := _pick(mb.position)
			if what2 in ["roja", "negra"]:
				d.set_probe(what2, "")
				Config.notify("Sonda %s devuelta junto al multímetro." % what2)
				return true
			set_active(false)
			return true
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if dragging != "":
			_update_drag(mm.position)
			return true
		main._wire_hover(mm.position)
		_hover_status()
		return false
	return false

func attach(which: String, key: String) -> void:
	var d := _dmm()
	d.set_probe(which, key)
	Config.notify("Sonda %s en %s." % [which, describe_key(key)], 3.0)

func _begin_drag(which: String, screen: Vector2) -> void:
	var d := _dmm()
	dragging = which
	_drag_prev = (d.part.estado.get(which, {}) as Dictionary).duplicate(true)
	_drag_tip = d.probe_tip(which)
	_drag_key = ""
	_update_drag(screen)

func _update_drag(screen: Vector2) -> void:
	var tm := _nearest_terminal(screen)
	var target: Vector3
	if not tm.is_empty():
		_drag_key = main._key(tm["part_uid"], tm["term_id"])
		var lp = main._terminal_live_by_key(_drag_key)
		target = lp if lp != null else tm["pos"]
		# Imán suave: la punta se acerca al terminal en pocos pasos.
		_drag_tip = _drag_tip.lerp(target, 0.6)
		if _drag_tip.distance_to(target) < 0.0004:
			_drag_tip = target
		if main.status_label:
			main.status_label.text = "Sonda %s → %s   ·   suelta para enganchar" % [dragging, describe_key(_drag_key)]
	else:
		_drag_key = ""
		_drag_tip = _surface_point(screen)

func _end_drag() -> void:
	var d := _dmm()
	var which := dragging
	dragging = ""
	if _drag_key != "":
		attach(which, _drag_key)
	else:
		d.set_probe(which, "", _drag_tip)
	Config.project_dirty = true

func _cancel_drag() -> void:
	var d := _dmm()
	d.part.estado[dragging] = _drag_prev
	dragging = ""

func _mode_notice() -> void:
	var d := _dmm()
	Config.notify("Multímetro: %s" % DMMController.MODE_LONG[d.mode], 2.5)

func _hover_status() -> void:
	if main._hover_term.is_empty() or main.status_label == null:
		return
	var key: String = main._key(main._hover_term["part_uid"], main._hover_term["term_id"])
	var v: float = main.circuit_rt.voltage(key)
	var vt := "flotante" if is_nan(v) else "%.3f V respecto a GND" % v
	main.status_label.text = "📟 %s · %s   ·   clic: sonda %s" % [describe_key(key), vt, active_probe]

## Nombre legible de un terminal: "Protoboard c6", "LED 5 mm rojo · ánodo"…
func describe_key(key: String) -> String:
	var parts := key.split(":")
	if parts.size() < 2:
		return key
	var p: PartInstance = main._find_part(parts[0])
	if p == null:
		return key
	if p.is_breadboard():
		return "protoboard %s" % BreadboardSnap.hole_name(parts[1])
	return "%s · %s" % [p.def.get("nombre", p.def_id), parts[1]]

#endregion
