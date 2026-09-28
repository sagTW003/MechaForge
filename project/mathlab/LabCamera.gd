class_name LabCamera
extends Camera3D
## LabCamera — Cámara orbital del Laboratorio con amortiguación suave.
##
##   · Órbita 360°, zoom y desplazamiento con inercia (los valores objetivo se
##     alcanzan exponencialmente: movimiento fluido).
##   · Modos: perspectiva 3D, vista superior ortográfica (mapa 2D / contornos) e
##     isométrica ortográfica (35.26°, 45°).
##   · Encuadre animado a puntos críticos (fuentes, pozos, crestas, nodos…).

enum ViewMode { PERSPECTIVA, SUPERIOR, ISOMETRICA }

var target: Vector3 = Vector3.ZERO
var yaw: float = deg_to_rad(-35.0)
var pitch: float = deg_to_rad(-32.0)
var distance: float = 7.5
var view_mode: int = ViewMode.PERSPECTIVA
var damping: float = 9.0

var _target: Vector3 = Vector3.ZERO
var _yaw: float = 0.0
var _pitch: float = 0.0
var _dist: float = 7.5
var _saved_persp: Array = []

func _ready() -> void:
	fov = 42.0
	near = 0.02
	far = 400.0
	_target = target
	_yaw = yaw
	_pitch = pitch
	_dist = distance
	_apply()

func _process(delta: float) -> void:
	var k := 1.0 - exp(-damping * delta)
	_target = _target.lerp(target, k)
	_yaw = lerp_angle(_yaw, yaw, k)
	_pitch = lerpf(_pitch, pitch, k)
	_dist = lerpf(_dist, distance, k)
	_apply()

func _apply() -> void:
	var dir := Vector3(cos(_pitch) * sin(_yaw), -sin(_pitch), cos(_pitch) * cos(_yaw))
	var pos := _target + dir * _dist
	var up := Vector3.UP
	if absf(dir.normalized().dot(Vector3.UP)) > 0.999:
		up = Vector3.FORWARD
	look_at_from_position(pos, _target, up)
	if projection == PROJECTION_ORTHOGONAL:
		size = _dist * 0.72

## Salta sin animación a los valores objetivo.
func snap() -> void:
	_target = target
	_yaw = yaw
	_pitch = pitch
	_dist = distance
	_apply()

func orbit(dx: float, dy: float) -> void:
	if view_mode == ViewMode.SUPERIOR:
		yaw -= dx * 0.006
		return
	yaw -= dx * 0.006
	pitch = clampf(pitch - dy * 0.005, deg_to_rad(-89.0), deg_to_rad(80.0))

func pan(dx: float, dy: float) -> void:
	var s := distance * 0.0011
	var right := global_transform.basis.x
	var up := global_transform.basis.y
	target += (-right * dx + up * dy) * s

func zoom(factor: float) -> void:
	distance = clampf(distance * factor, 0.4, 80.0)

func set_view(mode: int) -> void:
	if view_mode == ViewMode.PERSPECTIVA:
		_saved_persp = [yaw, pitch, distance]
	view_mode = mode
	match mode:
		ViewMode.PERSPECTIVA:
			projection = PROJECTION_PERSPECTIVE
			if _saved_persp.size() == 3:
				yaw = _saved_persp[0]; pitch = _saved_persp[1]; distance = _saved_persp[2]
		ViewMode.SUPERIOR:
			projection = PROJECTION_ORTHOGONAL
			pitch = deg_to_rad(-89.9)
			yaw = 0.0
		ViewMode.ISOMETRICA:
			projection = PROJECTION_ORTHOGONAL
			pitch = -atan(1.0 / sqrt(2.0))
			yaw = deg_to_rad(45.0)
	_apply()

## Encuadre animado de un punto.
func frame(p: Vector3, dist: float = -1.0) -> void:
	target = p
	if dist > 0.0:
		distance = dist

func screen_ray(screen_pos: Vector2) -> Dictionary:
	return {"origin": project_ray_origin(screen_pos), "dir": project_ray_normal(screen_pos)}
