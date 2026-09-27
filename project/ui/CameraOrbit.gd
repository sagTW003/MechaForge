class_name CameraOrbit
extends Camera3D
## CameraOrbit — Cámara orbital de taller (estilo CAD).
##
## Controles:
##   - Rueda del ratón: acercar / alejar (zoom).
##   - Botón central (o Alt+Izquierdo): orbitar alrededor del punto de interés.
##   - Mayús + botón central (o botón central + Mayús): desplazamiento (pan).
##   - Tecla F: enfocar el origen.

@export var target: Vector3 = Vector3.ZERO
@export var distance: float = 1.2
@export var min_distance: float = 0.15
@export var max_distance: float = 20.0
@export var orbit_speed: float = 0.01
@export var pan_speed: float = 1.0
@export var zoom_step: float = 0.12

var _yaw: float = deg_to_rad(-35.0)
var _pitch: float = deg_to_rad(-28.0)
var _orbiting: bool = false
var _panning: bool = false

func _ready() -> void:
	fov = 55.0
	near = 0.01
	far = 2000.0
	_update_transform()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom(-zoom_step)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom(zoom_step)
			MOUSE_BUTTON_MIDDLE:
				if mb.shift_pressed:
					_panning = mb.pressed
				else:
					_orbiting = mb.pressed
			MOUSE_BUTTON_LEFT:
				if mb.alt_pressed:
					_orbiting = mb.pressed
	elif event is InputEventMouseMotion and (_orbiting or _panning):
		var mm := event as InputEventMouseMotion
		if _panning:
			_pan(mm.relative)
		else:
			_orbit(mm.relative)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F:
		target = Vector3.ZERO
		_update_transform()

func _zoom(amount: float) -> void:
	distance = clampf(distance * (1.0 + amount), min_distance, max_distance)
	_update_transform()

func _orbit(rel: Vector2) -> void:
	_yaw -= rel.x * orbit_speed
	_pitch = clampf(_pitch - rel.y * orbit_speed, deg_to_rad(-89.0), deg_to_rad(89.0))
	_update_transform()

func _pan(rel: Vector2) -> void:
	var right := global_transform.basis.x
	var up := global_transform.basis.y
	var factor := distance * pan_speed * 0.002
	target -= right * rel.x * factor
	target += up * rel.y * factor
	_update_transform()

func _update_transform() -> void:
	var dir := Vector3(
		cos(_pitch) * sin(_yaw),
		sin(_pitch),
		cos(_pitch) * cos(_yaw)
	)
	global_position = target - dir * distance
	look_at(target, Vector3.UP)
	_update_dof()

## Profundidad de campo con enfoque automático en el punto de interés: el fondo
## se desenfoca levemente y, al acercarse mucho a una pieza, también el primer plano.
var dof_enabled: bool = true

func _update_dof() -> void:
	var attr := attributes as CameraAttributesPractical
	if attr == null:
		return
	attr.dof_blur_far_enabled = dof_enabled
	attr.dof_blur_far_distance = distance * 1.8 + 0.2
	attr.dof_blur_far_transition = distance * 2.5 + 0.5
	attr.dof_blur_near_enabled = dof_enabled and distance < 0.6
	attr.dof_blur_near_distance = distance * 0.35
	attr.dof_blur_near_transition = distance * 0.25
	attr.dof_blur_amount = 0.06

## Devuelve un rayo (origen, dirección) desde la cámara a través de un punto de pantalla.
func screen_ray(screen_pos: Vector2) -> Dictionary:
	return {
		"origin": project_ray_origin(screen_pos),
		"dir": project_ray_normal(screen_pos),
	}
