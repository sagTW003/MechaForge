class_name HeadsetRig
extends Node
## HeadsetRig — Render estéreo del visor casero.
##
## Una cámara por ojo en la posición real del ojo: sobre el eje de su lente, a la
## distancia ojo–lente, mirando hacia la pantalla. Se mueven con la pantalla del visor
## (su transformación en vivo durante la simulación). Cada una renderiza la escena sin
## el propio visor (capa LAYER_VISOR) ni las ayudas del editor (LAYER_EDITOR), con un
## frustum asimétrico que cubre lo que ese ojo ve de su mitad de pantalla a través de
## la lente, recortado por el borde de la lente.
##
## Un shader compone la imagen lado a lado que muestra la pantalla: para cada píxel
## calcula la dirección con que lo verá el ojo (lente delgada, distorsión radial k1, k2
## y escala de cada color según el número de Abbe; ver Optics) y toma ese color del
## render del ojo. La imagen sale predistorsionada en barril y con el rojo y el azul
## desplazados, y la lente la devuelve recta.
##
## Coordenadas del espectador sobre la pantalla: x a su derecha (−X de la pantalla),
## y arriba (+Z), en metros desde el centro. Las de la textura: uv con origen arriba a
## la izquierda.

const LAYER_VISOR := 1 << 1        # capa 2: piezas del visor
const LAYER_EDITOR := 1 << 2       # capa 3: uniones, gizmo, terminales, vista previa de la IA
const EYE_CULL := 0xFFFFF & ~(LAYER_VISOR | LAYER_EDITOR)
const NEAR := 0.01
const FAR := 300.0
const MAX_SCREEN_W := 1600         # ancho máximo de la imagen lado a lado
const MAX_EYE_PX := 1600           # lado máximo del render de cada ojo
const HEADSET_REACH := 0.25        # piezas unidas al visor a más de esto no se ocultan
const QUALITY := [0.5, 0.75, 1.0]
const QUALITY_NAMES := ["Baja (½)", "Media (¾)", "Alta (1:1)"]

var main: Node
var forced := false                # render activo sin panel ni simulación (pruebas, capturas)
var predistort := true             # predistorsión de barril con k1, k2
var chroma := true                 # corrección de la aberración cromática lateral
var quality := 1
var layout: Dictionary = {}        # última disposición (compute_layout)
var screen_vp: SubViewport         # imagen lado a lado de la pantalla
var eyes: Array = []               # [{vp, cam}]: ojo izquierdo y derecho
var info_label: Label              # estado en el panel «Vista del visor»
var _rect: ColorRect
var _mat: ShaderMaterial
var _active := false
var _frame := 0
var _hidden: Dictionary = {}       # uid → true: piezas en LAYER_VISOR
var _glass_uid := ""               # pantalla que muestra el render
var _was_running := false

func _ready() -> void:
	for i in range(2):
		var vp := SubViewport.new()
		vp.name = "Ojo%d" % i
		vp.size = Vector2i(64, 64)
		vp.msaa_3d = Viewport.MSAA_2X
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_FRUSTUM
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		cam.near = NEAR
		cam.far = FAR
		cam.cull_mask = EYE_CULL
		vp.add_child(cam)
		add_child(vp)
		cam.current = true
		eyes.append({"vp": vp, "cam": cam})
	screen_vp = SubViewport.new()
	screen_vp.name = "PantallaVisor"
	screen_vp.disable_3d = true
	screen_vp.size = Vector2i(64, 36)
	screen_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_rect = ColorRect.new()
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	_mat.set_shader_parameter("eye_l", (eyes[0]["vp"] as SubViewport).get_texture())
	_mat.set_shader_parameter("eye_r", (eyes[1]["vp"] as SubViewport).get_texture())
	_rect.material = _mat
	screen_vp.add_child(_rect)
	add_child(screen_vp)

func is_active() -> bool:
	return _active

func _process(_delta: float) -> void:
	_frame += 1
	var running: bool = main.simulator != null and main.simulator.is_running()
	var panel := _panel_open()
	if not (forced or panel or running):
		if _active:
			_set_active(false)
		return
	if layout.is_empty() or _frame % 10 == 0 or running != _was_running:
		refresh()
	_was_running = running
	var go: bool = layout.get("ok", false) and (forced or panel or screen_lit())
	if go != _active:
		_set_active(go)
	if _active:
		update_cameras()

func _panel_open() -> bool:
	var p = main.get("visor_panel")
	return p != null and p.visible and not p.is_collapsed()

## Recalcula la disposición (lentes, ojos, frustums), los tamaños de los render, los
## parámetros del shader, las capas y la textura de la pantalla.
func refresh() -> void:
	layout = compute_layout(main.parts_root, Callable(main, "_part_live_xform"), QUALITY[quality])
	if info_label:
		info_label.text = status_text()
	if not layout.get("ok", false):
		if _active:
			_set_active(false)
		return
	var E: Array = layout["eyes"]
	for i in range(E.size()):
		var vp: SubViewport = eyes[i]["vp"]
		if vp.size != (E[i]["size"] as Vector2i):
			vp.size = E[i]["size"]
	var cs: Vector2i = layout["comp_size"]
	if screen_vp.size != cs:
		screen_vp.size = cs
	_rect.size = Vector2(cs)
	apply_settings()
	_update_layers()
	_update_glass()

## Pasa al shader la disposición y las opciones (predistorsión, color).
func apply_settings() -> void:
	if not layout.get("ok", false):
		return
	var E: Array = layout["eyes"]
	var l: Dictionary = E[0]
	var r: Dictionary = E[1] if E.size() > 1 else E[0]
	_mat.set_shader_parameter("area", layout["area"])
	_mat.set_shader_parameter("stereo", layout["estereo"])
	for pair in [["_l", l], ["_r", r]]:
		var e: Dictionary = pair[1]
		_mat.set_shader_parameter("center" + pair[0], e["centro"])
		_mat.set_shader_parameter("scale" + pair[0], e["escala"])
		_mat.set_shader_parameter("k" + pair[0], e["k"])
		_mat.set_shader_parameter("chroma" + pair[0], e["cromatica"])
		_mat.set_shader_parameter("tans" + pair[0], e["tans"])
	_mat.set_shader_parameter("predistort", predistort)
	_mat.set_shader_parameter("chroma", chroma)

## Coloca cada cámara en su ojo, orientada como la pantalla en vivo, con su frustum.
func update_cameras() -> void:
	var scr: PartInstance = main._find_part(str(layout.get("screen_uid", "")))
	if scr == null:
		return
	var sx: Transform3D = main._part_live_xform(scr)
	var cb := camera_basis(sx.basis)
	var E: Array = layout["eyes"]
	for i in range(E.size()):
		var e: Dictionary = E[i]
		var cam: Camera3D = eyes[i]["cam"]
		cam.global_transform = Transform3D(cb, sx * (e["pos_local"] as Vector3))
		var t: Vector4 = e["tans"]
		cam.size = NEAR * (t.w - t.z)
		cam.frustum_offset = Vector2(NEAR * (t.x + t.y) * 0.5, NEAR * (t.z + t.w) * 0.5)

## Base de las cámaras de los ojos a partir de la de la pantalla: miran a −Y de la
## pantalla (−Z de la cámara), arriba = +Z de la pantalla, derecha = −X.
static func camera_basis(screen_basis: Basis) -> Basis:
	var b := screen_basis.orthonormalized()
	return Basis(-b.x, b.z, b.y)

func _set_active(on: bool) -> void:
	_active = on
	var mode := SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	for e in eyes:
		(e["vp"] as SubViewport).render_target_update_mode = mode
	screen_vp.render_target_update_mode = mode
	if on:
		update_cameras()
	_update_glass()

## ¿Está encendida la pantalla del visor? (el móvil siempre; el LCD con 5 V).
func screen_lit() -> bool:
	var part: PartInstance = main._find_part(str(layout.get("screen_uid", "")))
	if part == null:
		return false
	if str(part.def.get("apariencia", "")) == "movil":
		return true
	return main.circuit_rt.screen_powered(part)

#region DISPOSICIÓN --------------------------------------------------------------

## Disposición del visor: para cada ojo (izquierdo primero) su posición en el sistema
## de la pantalla, el eje de su lente sobre la pantalla, la escala y la distorsión de
## la lente, la escala de cada color, el frustum (tangentes izquierda, derecha, abajo,
## arriba) y el tamaño de su render. q escala la resolución.
static func compute_layout(parts_root: Node, xf: Callable, q: float = 1.0) -> Dictionary:
	var r := Optics.analyze(parts_root, xf)
	if not r.get("ok", false):
		return {"ok": false, "motivo": str(r.get("motivo", ""))}
	var scr: PartInstance = null
	for c in parts_root.get_children():
		if c is PartInstance and (c as PartInstance).uid == str(r["pantalla"]["uid"]):
			scr = c
	var area: Array = r["pantalla"]["area_mm"]
	var res: Array = r["pantalla"]["res"]
	var aw := float(area[0]) / 1000.0
	var ah := float(area[1]) / 1000.0
	var cw := mini(int(res[0]), MAX_SCREEN_W)
	var ch := maxi(16, int(round(cw * ah / aw)))
	var front := PartLibrary.dims_m(scr.def).y * 0.5
	var px_m := float(cw) / aw
	var out := []
	for it in r["lentes"]:
		var u: float = it["u_m"]
		var w: float = it["w_m"]
		var d: float = it["d_m"]
		var e: float = it["e_m"]
		var f: float = it["f_m"]
		var k := Vector2(float(it["k1"]), float(it["k2"]))
		var s := Optics.tan_scale(d, f, e)
		var dl := Optics.chroma_shift(d, f, e, float(it["abbe"]))
		var cv := Vector2(-u, w)
		# Su mitad de pantalla: del borde a la línea central (o toda si hay una lente).
		var x0 := -float(it["u1_m"])
		var x1 := -float(it["u0_m"])
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		var n := 48
		for j in range(n + 1):
			var a := float(j) / n
			for pt in [Vector2(lerpf(x0, x1, a), -ah / 2.0), Vector2(lerpf(x0, x1, a), ah / 2.0),
					Vector2(x0, lerpf(-ah / 2.0, ah / 2.0, a)), Vector2(x1, lerpf(-ah / 2.0, ah / 2.0, a))]:
				for cs in [1.0 - dl, 1.0 + dl]:
					var t := Optics.distort(((pt as Vector2) - cv) * s * float(cs), k.x, k.y)
					lo = lo.min(t)
					hi = hi.max(t)
		# Más allá del borde de la lente el ojo no ve la pantalla.
		var ta := float(it["r_m"]) / e
		lo = lo.max(Vector2(-ta, -ta))
		hi = hi.min(Vector2(ta, ta))
		if hi.x - lo.x < 1e-3 or hi.y - lo.y < 1e-3:
			continue
		# Resolución: la misma densidad que la pantalla en el centro (píxeles por tangente).
		var ppt := px_m / s * q
		var wpx := (hi.x - lo.x) * ppt
		var hpx := (hi.y - lo.y) * ppt
		var kk := minf(1.0, MAX_EYE_PX / maxf(wpx, hpx))
		var size := Vector2i(maxi(16, int(ceil(wpx * kk))), maxi(16, int(ceil(hpx * kk))))
		# La cámara fija el alto; el ancho angular sale del tamaño entero del render.
		var span := (hi.y - lo.y) * float(size.x) / float(size.y)
		var cx := (lo.x + hi.x) * 0.5
		var tans := Vector4(cx - span * 0.5, cx + span * 0.5, lo.y, hi.y)
		out.append({
			"uid": it["uid"], "lado": it["lado"], "pos_local": Vector3(u, front + d + e, w),
			"centro": cv, "escala": s, "k": k, "cromatica": Vector3(1.0 - dl, 1.0, 1.0 + dl),
			"tans": tans, "size": size,
			"fov_h": rad_to_deg(atan(tans.y) - atan(tans.x)), "fov_v": rad_to_deg(atan(tans.w) - atan(tans.z)),
		})
	if out.is_empty():
		return {"ok": false, "motivo": "Las lentes no dejan ver la pantalla."}
	out.sort_custom(func(a, b): return str(a["lado"]) == "izquierda" and str(b["lado"]) != "izquierda")
	if out.size() > 2:
		out = out.slice(0, 2)
	var stereo: bool = r["estereo"] and out.size() == 2
	if not stereo:
		out = out.slice(0, 1)
	var lay := {"ok": true, "screen_uid": scr.uid, "area": Vector2(aw, ah), "comp_size": Vector2i(cw, ch),
		"res": Vector2i(int(res[0]), int(res[1])), "estereo": stereo, "eyes": out, "avisos": r.get("avisos", [])}
	if stereo:
		lay["ipd_m"] = ((out[0]["pos_local"] as Vector3) - (out[1]["pos_local"] as Vector3)).length()
	return lay

## Lo mismo que el shader: el píxel uv (0..1, origen arriba a la izquierda) de la imagen
## lado a lado lo ve el ojo «ojo» en la dirección «t» (tangentes, x a la derecha, y
## arriba) en el canal c (0 rojo, 1 verde, 2 azul).
static func screen_to_eye(lay: Dictionary, uv: Vector2, c: int = 1, predist := true, chrom := true) -> Dictionary:
	var a: Vector2 = lay["area"]
	var p := Vector2((uv.x - 0.5) * a.x, (0.5 - uv.y) * a.y)
	var i := 0 if (not lay["estereo"] or uv.x < 0.5) else 1
	var e: Dictionary = lay["eyes"][i]
	var cs: float = (e["cromatica"] as Vector3)[c] if chrom else 1.0
	var t: Vector2 = (p - (e["centro"] as Vector2)) * float(e["escala"]) * cs
	if predist:
		t = Optics.distort(t, e["k"].x, e["k"].y)
	return {"ojo": i, "t": t}

## Inversa: píxel uv de la pantalla donde se dibuja lo que el ojo i ve en la dirección t.
static func eye_to_screen(lay: Dictionary, i: int, t: Vector2, c: int = 1, predist := true, chrom := true) -> Vector2:
	var a: Vector2 = lay["area"]
	var e: Dictionary = lay["eyes"][i]
	var cs: float = (e["cromatica"] as Vector3)[c] if chrom else 1.0
	var tl := Optics.undistort(t, e["k"].x, e["k"].y) if predist else t
	var p: Vector2 = (e["centro"] as Vector2) + tl / (float(e["escala"]) * cs)
	return Vector2(p.x / a.x + 0.5, 0.5 - p.y / a.y)

## Posición en el mundo del ojo i.
func eye_world(i: int) -> Vector3:
	var scr: PartInstance = main._find_part(str(layout.get("screen_uid", "")))
	if scr == null or i >= (layout.get("eyes", []) as Array).size():
		return Vector3.ZERO
	return main._part_live_xform(scr) * (layout["eyes"][i]["pos_local"] as Vector3)

#endregion

#region CAPAS Y PANTALLA ---------------------------------------------------------

## Piezas que forman el visor y que los ojos no deben ver: la pantalla, las lentes, lo
## unido a ellas con uniones fijas o deslizaderas (sin pasar de HEADSET_REACH), lo
## insertado en esas piezas y cualquier pieza que envuelva un ojo (una carcasa suelta).
static func hidden_parts(main_node: Node, lay: Dictionary) -> Dictionary:
	var hid := {}
	if not lay.get("ok", false):
		return hid
	var scr: PartInstance = main_node._find_part(str(lay["screen_uid"]))
	if scr == null:
		return hid
	var sx: Transform3D = main_node._part_live_xform(scr)
	var queue := [scr.uid]
	for e in lay["eyes"]:
		queue.append(str(e["uid"]))
	for u in queue:
		hid[u] = true
	var i := 0
	while i < queue.size():
		var cur: String = queue[i]
		i += 1
		for c in main_node.connections:
			var conn := c as Connection
			if conn.tipo != Connection.Tipo.FIJA and conn.tipo != Connection.Tipo.DESLIZADERA:
				continue
			var other := conn.b_uid if conn.a_uid == cur else (conn.a_uid if conn.b_uid == cur else "")
			if other == "" or hid.has(other):
				continue
			var op: PartInstance = main_node._find_part(other)
			if op and main_node._part_live_xform(op).origin.distance_to(sx.origin) <= HEADSET_REACH:
				hid[other] = true
				queue.append(other)
	var eyes_w := []
	for e in lay["eyes"]:
		eyes_w.append(sx * (e["pos_local"] as Vector3))
	for c in main_node.parts_root.get_children():
		if not c is PartInstance:
			continue
		var p := c as PartInstance
		if hid.has(p.uid):
			continue
		if p.inserted_in != "" and hid.has(p.inserted_in):
			hid[p.uid] = true
			continue
		var x: Transform3D = main_node._part_live_xform(p)
		var half := PartLibrary.dims_m(p.def) * 0.5 + Vector3.ONE * 0.003
		for ew in eyes_w:
			var l: Vector3 = x.affine_inverse() * (ew as Vector3)
			if absf(l.x) <= half.x and absf(l.y) <= half.y and absf(l.z) <= half.z:
				hid[p.uid] = true
				break
	return hid

static func set_layers(root: Node, mask: int) -> void:
	if root == null:
		return
	if root is VisualInstance3D:
		(root as VisualInstance3D).layers = mask
	for n in root.find_children("*", "VisualInstance3D", true, false):
		(n as VisualInstance3D).layers = mask

func _update_layers() -> void:
	var hid := hidden_parts(main, layout)
	for uid in _hidden:
		if not hid.has(uid):
			_set_part_layers(str(uid), 1)
	for uid in hid:
		_set_part_layers(str(uid), LAYER_VISOR)
	_hidden = hid
	# Cables entre piezas del visor.
	for w in main.wires:
		var node: Node = main._wire_nodes.get(str(w.get("uid", "")))
		if node:
			var a := str(w["a_key"]).split(":")[0]
			var b := str(w["b_key"]).split(":")[0]
			set_layers(node, LAYER_VISOR if hid.has(a) and hid.has(b) else 1)
	# Ayudas del editor: los ojos no las ven.
	for n in [main.connections_root, main.terminals_root, main.gizmo, main.ai_ghost_root]:
		set_layers(n, LAYER_EDITOR)
	var sel: PartInstance = main.selected_part
	if sel and is_instance_valid(sel) and sel.get("_selection_box"):
		set_layers(sel.get("_selection_box"), LAYER_EDITOR)
	if main.simulator and is_instance_valid(main.simulator._com_marker):
		set_layers(main.simulator._com_marker, LAYER_EDITOR)

func _set_part_layers(uid: String, mask: int) -> void:
	var part: PartInstance = main._find_part(uid)
	if part:
		for root in main.circuit_rt._visual_roots(part):
			set_layers(root, mask)

## La pantalla del visor muestra la imagen lado a lado mientras el render está activo;
## si no, su carta de ajuste.
func _update_glass() -> void:
	var uid := str(layout.get("screen_uid", "")) if _active else ""
	if _glass_uid != "" and _glass_uid != uid:
		_set_glass(_glass_uid, null)
	if uid != "":
		_set_glass(uid, screen_vp.get_texture())
	_glass_uid = uid

func _set_glass(uid: String, tex: Texture2D) -> void:
	var part: PartInstance = main._find_part(uid)
	if part == null:
		return
	for root in main.circuit_rt._visual_roots(part):
		for mi in (root as Node).find_children("*", "MeshInstance3D", true, false):
			if mi.has_meta("pantalla_luz"):
				var m := (mi as MeshInstance3D).material_override as StandardMaterial3D
				if m:
					m.emission_texture = tex if tex else PartVisuals.sbs_pattern()

## Textura que muestra ahora la pantalla del visor (para las pruebas).
func glass_texture() -> Texture2D:
	var part: PartInstance = main._find_part(str(layout.get("screen_uid", "")))
	if part == null:
		return null
	for mi in part.find_children("*", "MeshInstance3D", true, false):
		if mi.has_meta("pantalla_luz"):
			return ((mi as MeshInstance3D).material_override as StandardMaterial3D).emission_texture
	return null

#endregion

#region ESTADO -------------------------------------------------------------------

func status_text() -> String:
	if not layout.get("ok", false):
		return "Sin visor: %s" % str(layout.get("motivo", "hace falta una pantalla y sus lentes."))
	var E: Array = layout["eyes"]
	var res: Vector2i = layout["res"]
	var cs: Vector2i = layout["comp_size"]
	var e0: Dictionary = E[0]
	var t := "Pantalla %d×%d (imagen de %d×%d)" % [res.x, res.y, cs.x, cs.y]
	if layout["estereo"]:
		t += " · cámaras a %.1f mm" % (float(layout["ipd_m"]) * 1000.0)
	else:
		t += " · una sola lente: imagen única"
	t += "\nCampo de cada ojo %.0f° × %.0f° · render de %d×%d px" % [e0["fov_h"], e0["fov_v"], e0["size"].x, e0["size"].y]
	var running: bool = main.simulator != null and main.simulator.is_running()
	if not running:
		t += "\nPulsa ▶ Simular para encender la pantalla (se ve aquí lo que mostraría)."
	elif screen_lit():
		t += "\nPantalla encendida."
	else:
		t += "\nPantalla apagada: le faltan los 5 V (aquí se ve lo que mostraría)."
	return t

## Resumen para la API (analyze_headset).
func describe() -> Dictionary:
	var lay := layout if layout.get("ok", false) else compute_layout(main.parts_root, Callable(main, "_part_live_xform"), QUALITY[quality])
	if not lay.get("ok", false):
		return {"activo": false, "motivo": str(lay.get("motivo", ""))}
	var scr: PartInstance = main._find_part(str(lay["screen_uid"]))
	var sx: Transform3D = main._part_live_xform(scr)
	var ojos := []
	for e in lay["eyes"]:
		var p: Vector3 = sx * (e["pos_local"] as Vector3)
		var t: Vector4 = e["tans"]
		ojos.append({"lado": e["lado"], "posicion": [p.x, p.y, p.z], "fov_h": e["fov_h"], "fov_v": e["fov_v"],
			"resolucion": [e["size"].x, e["size"].y], "tangentes": [t.x, t.y, t.z, t.w]})
	var cs: Vector2i = lay["comp_size"]
	var out := {"activo": _active, "imagen_px": [cs.x, cs.y], "estereo": lay["estereo"],
		"predistorsion": predistort, "cromatica": chroma, "ojos": ojos}
	if lay.has("ipd_m"):
		out["ipd_camaras_mm"] = float(lay["ipd_m"]) * 1000.0
	return out

#endregion

const SHADER := """
shader_type canvas_item;
render_mode unshaded;

// Imagen lado a lado de la pantalla del visor (HeadsetRig). Para cada píxel: posición
// sobre la pantalla (m, x a la derecha del espectador, y arriba), desplazamiento al eje
// de la lente de su ojo, dirección con que lo verá el ojo (escala de la lente por
// color y distorsión radial) y color del render de ese ojo en esa dirección.
uniform sampler2D eye_l : filter_linear, repeat_disable;
uniform sampler2D eye_r : filter_linear, repeat_disable;
uniform vec2 area = vec2(0.1218, 0.0685);
uniform bool stereo = true;
uniform vec2 center_l;
uniform vec2 center_r;
uniform float scale_l = 24.0;
uniform float scale_r = 24.0;
uniform vec2 k_l;
uniform vec2 k_r;
uniform vec3 chroma_l = vec3(1.0);
uniform vec3 chroma_r = vec3(1.0);
uniform vec4 tans_l = vec4(-1.0, 1.0, -1.0, 1.0);
uniform vec4 tans_r = vec4(-1.0, 1.0, -1.0, 1.0);
uniform bool predistort = true;
uniform bool chroma = true;

vec2 eye_dir(vec2 t, vec2 k) {
	if (!predistort) {
		return t;
	}
	float r2 = dot(t, t);
	return t * (1.0 + k.x * r2 + k.y * r2 * r2);
}

vec2 eye_uv(vec2 t, vec4 tans) {
	return vec2((t.x - tans.x) / (tans.y - tans.x), (tans.w - t.y) / (tans.w - tans.z));
}

float inside(vec2 uv) {
	return step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
}

void fragment() {
	vec2 p = vec2((UV.x - 0.5) * area.x, (0.5 - UV.y) * area.y);
	bool left = !stereo || UV.x < 0.5;
	vec2 c = left ? center_l : center_r;
	float s = left ? scale_l : scale_r;
	vec2 k = left ? k_l : k_r;
	vec3 cs = chroma ? (left ? chroma_l : chroma_r) : vec3(1.0);
	vec4 tans = left ? tans_l : tans_r;
	vec2 t = (p - c) * s;
	vec2 ur = eye_uv(eye_dir(t * cs.r, k), tans);
	vec2 ug = eye_uv(eye_dir(t * cs.g, k), tans);
	vec2 ub = eye_uv(eye_dir(t * cs.b, k), tans);
	vec3 col;
	if (left) {
		col = vec3(textureLod(eye_l, ur, 0.0).r * inside(ur), textureLod(eye_l, ug, 0.0).g * inside(ug), textureLod(eye_l, ub, 0.0).b * inside(ub));
	} else {
		col = vec3(textureLod(eye_r, ur, 0.0).r * inside(ur), textureLod(eye_r, ug, 0.0).g * inside(ug), textureLod(eye_r, ub, 0.0).b * inside(ub));
	}
	COLOR = vec4(col, 1.0);
}
"""
