class_name TransformGizmo
extends Node3D
## TransformGizmo — Gizmo 3D de 3 ejes para mover y rotar la pieza seleccionada.
##
## - Modo MOVER: flechas X (rojo), Y (verde), Z (azul). Arrastrar una flecha mueve
##   la pieza solo sobre ese eje, ajustado a la rejilla.
## - Modo ROTAR: anillos alrededor de cada eje. Arrastrar gira en incrementos del
##   paso de rotación (15°/45°/90°) si el snapping está activo.
## El gizmo se dibuja siempre encima (sin prueba de profundidad) y mantiene un
## tamaño constante en pantalla. La selección se resuelve en 2D (distancia del
## cursor a la proyección de cada eje/anillo), sin física.

signal drag_started
signal dragged(pos: Vector3, basis: Basis)
signal drag_finished(old_pos: Vector3, old_basis: Basis, new_pos: Vector3, new_basis: Basis)

enum Mode { MOVER, ROTAR }
const AXES := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
const COLORS := [Color(0.95, 0.25, 0.25), Color(0.35, 0.9, 0.3), Color(0.3, 0.55, 1.0)]
const HOVER_COLOR := Color(1.0, 0.85, 0.2)
const PICK_PX := 12.0
const SCREEN_SIZE := 0.16      # fracción de la distancia a la cámara

var mode: int = Mode.MOVER
var camera: Camera3D
var target: Node3D = null

var _handles: Array = []        # [modo][eje] -> Node3D
var _mats: Array = []           # [modo][eje] -> StandardMaterial3D
var _hover_axis: int = -1
var _drag_axis: int = -1
var _start_pos: Vector3
var _start_basis: Basis
var _start_param: float = 0.0
var _start_vec: Vector3

func _ready() -> void:
	top_level = true
	_build()
	visible = false

func _build() -> void:
	for m in range(2):
		var hs := []
		var ms := []
		for a in range(3):
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.no_depth_test = true
			mat.render_priority = 10
			mat.albedo_color = COLORS[a]
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			var h := _make_arrow(mat) if m == Mode.MOVER else _make_ring(mat)
			h.basis = _axis_basis(a)
			add_child(h)
			hs.append(h)
			ms.append(mat)
		_handles.append(hs)
		_mats.append(ms)
	# Esfera central.
	var c := MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = 0.06; sm.height = 0.12
	c.mesh = sm
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.no_depth_test = true
	cm.render_priority = 10
	cm.albedo_color = Color(0.9, 0.9, 0.9, 0.8)
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	c.material_override = cm
	add_child(c)
	set_mode(mode)

## Flecha a lo largo de +Y local (se orienta con _axis_basis). Longitud 1.
func _make_arrow(mat: Material) -> Node3D:
	var n := Node3D.new()
	var shaft := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.018; cm.bottom_radius = 0.018; cm.height = 0.8; cm.radial_segments = 8
	shaft.mesh = cm
	shaft.position = Vector3(0, 0.4 + 0.08, 0)
	shaft.material_override = mat
	n.add_child(shaft)
	var head := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.0; hm.bottom_radius = 0.07; hm.height = 0.22; hm.radial_segments = 12
	head.mesh = hm
	head.position = Vector3(0, 0.98, 0)
	head.material_override = mat
	n.add_child(head)
	return n

## Anillo en el plano XZ local (eje de giro = +Y local). Radio 0.85.
func _make_ring(mat: Material) -> Node3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.83
	tm.outer_radius = 0.87
	tm.rings = 48
	tm.ring_segments = 6
	mi.mesh = tm
	mi.material_override = mat
	return mi

## Base que lleva +Y local al eje "a" del mundo.
func _axis_basis(a: int) -> Basis:
	match a:
		0: return Basis(Vector3.BACK, -PI / 2.0)   # +Y -> +X
		2: return Basis(Vector3.RIGHT, PI / 2.0)   # +Y -> +Z
		_: return Basis.IDENTITY

func set_mode(m: int) -> void:
	mode = m
	for mm in range(2):
		for a in range(3):
			_handles[mm][a].visible = (mm == mode)

func toggle_mode() -> void:
	set_mode(Mode.ROTAR if mode == Mode.MOVER else Mode.MOVER)

func attach(node: Node3D) -> void:
	target = node
	visible = node != null
	_hover_axis = -1
	_drag_axis = -1
	_refresh_colors()

func is_dragging() -> bool:
	return _drag_axis >= 0

func _process(_delta: float) -> void:
	if target == null or not is_instance_valid(target) or camera == null:
		visible = false
		return
	visible = true
	global_position = target.global_position
	var s := camera.global_position.distance_to(global_position) * SCREEN_SIZE
	scale = Vector3.ONE * maxf(0.001, s)

#region SELECCIÓN 2D -------------------------------------------------------------

func _gizmo_scale() -> float:
	return scale.x

## Eje bajo el cursor (-1 si ninguno).
func pick_axis(mouse: Vector2) -> int:
	if not visible or camera == null:
		return -1
	var best := -1
	var best_d := PICK_PX
	var o := global_position
	for a in range(3):
		var ax: Vector3 = AXES[a]
		var d := INF
		if mode == Mode.MOVER:
			var p0 := camera.unproject_position(o + ax * 0.08 * _gizmo_scale())
			var p1 := camera.unproject_position(o + ax * 1.1 * _gizmo_scale())
			d = _seg_dist(mouse, p0, p1)
		else:
			var u: Vector3 = AXES[(a + 1) % 3]
			var v: Vector3 = AXES[(a + 2) % 3]
			var prev := Vector2.ZERO
			for k in range(33):
				var ang := TAU * k / 32.0
				var wp := o + (u * cos(ang) + v * sin(ang)) * 0.85 * _gizmo_scale()
				if camera.is_position_behind(wp):
					continue
				var sp := camera.unproject_position(wp)
				if k > 0:
					d = minf(d, _seg_dist(mouse, prev, sp))
				prev = sp
		if d < best_d:
			best_d = d
			best = a
	return best

static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := 0.0
	if ab.length_squared() > 1e-6:
		t = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)

func hover(mouse: Vector2) -> void:
	if is_dragging():
		return
	var a := pick_axis(mouse)
	if a != _hover_axis:
		_hover_axis = a
		_refresh_colors()

func _refresh_colors() -> void:
	for mm in range(2):
		for a in range(3):
			var hot := (a == _hover_axis or a == _drag_axis) and mm == mode
			(_mats[mm][a] as StandardMaterial3D).albedo_color = HOVER_COLOR if hot else COLORS[a]

#endregion

#region ARRASTRE -----------------------------------------------------------------

## Intenta empezar un arrastre. Devuelve true si el cursor estaba sobre un eje.
func begin_drag(mouse: Vector2) -> bool:
	var a := pick_axis(mouse)
	if a < 0 or target == null:
		return false
	_drag_axis = a
	_start_pos = target.global_position
	_start_basis = target.global_transform.basis
	if mode == Mode.MOVER:
		_start_param = _axis_param(mouse, a)
	else:
		_start_vec = _plane_vec(mouse, a)
	_refresh_colors()
	drag_started.emit()
	return true

func update_drag(mouse: Vector2) -> void:
	if _drag_axis < 0 or target == null:
		return
	var ax: Vector3 = AXES[_drag_axis]
	if mode == Mode.MOVER:
		var d := _axis_param(mouse, _drag_axis) - _start_param
		d = Config.snap_scalar(d)
		var p := _start_pos + ax * d
		if _drag_axis == 1:
			p.y = maxf(0.0, p.y)
		dragged.emit(p, _start_basis)
	else:
		var v := _plane_vec(mouse, _drag_axis)
		if v.length_squared() < 1e-10 or _start_vec.length_squared() < 1e-10:
			return
		var ang := _start_vec.signed_angle_to(v, ax)
		if Config.snap_enabled:
			var step := deg_to_rad(Config.rotation_step_deg)
			ang = round(ang / step) * step
		dragged.emit(_start_pos, (Basis(ax, ang) * _start_basis).orthonormalized())

func end_drag() -> void:
	if _drag_axis < 0:
		return
	_drag_axis = -1
	_refresh_colors()
	if target and is_instance_valid(target):
		drag_finished.emit(_start_pos, _start_basis, target.global_position, target.global_transform.basis)

## Parámetro (m) del punto del eje más cercano al rayo del ratón.
func _axis_param(mouse: Vector2, a: int) -> float:
	var ro := camera.project_ray_origin(mouse)
	var rd := camera.project_ray_normal(mouse)
	var ax: Vector3 = AXES[a]
	# Mínima distancia entre dos rectas: origen+ax*t y ro+rd*s.
	var w0 := _start_pos - ro
	var b := ax.dot(rd)
	var denom := 1.0 - b * b
	if absf(denom) < 1e-6:
		return 0.0
	var d := ax.dot(w0)
	var e := rd.dot(w0)
	return (b * e - d) / denom

## Vector desde el centro hasta el punto del plano de giro bajo el ratón.
func _plane_vec(mouse: Vector2, a: int) -> Vector3:
	var ro := camera.project_ray_origin(mouse)
	var rd := camera.project_ray_normal(mouse)
	var plane := Plane(AXES[a], _start_pos.dot(AXES[a]))
	var hit = plane.intersects_ray(ro, rd)
	if hit == null:
		return Vector3.ZERO
	return (hit as Vector3) - _start_pos

#endregion
