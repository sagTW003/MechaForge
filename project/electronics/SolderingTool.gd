class_name SolderingTool
extends Node3D
## SolderingTool — Cautín virtual y animación de soldadura.
##
## Secuencia al soldar un terminal:
##   1. El cautín se acerca desde el lado de la cámara (inclinado 40°) hasta que
##      la punta toca exactamente el punto de contacto (terminal detectado por
##      raycast contra su colisionador).
##   2. Calentamiento: el estaño aparece y crece en estado LÍQUIDO (espejo brillante
##      que ondula) mientras sube el humo del fundente.
##   3. Se retira el cautín y el estaño se SOLIDIFICA (pasa a gris satinado) en un
##      menisco realista alrededor del terminal.
## Emite "finished(key)" al terminar; la junta queda registrada en el cable.

signal finished(key: String)

const T_APPROACH := 0.35
const T_MELT := 1.1
const T_RETRACT := 0.3
const T_SOLIDIFY := 0.9

var camera: Camera3D
var busy: bool = false
var _iron: Node3D
var _smoke: GPUParticles3D
var _glow: OmniLight3D

func _ready() -> void:
	_iron = _build_iron()
	add_child(_iron)
	_iron.visible = false
	_smoke = _build_smoke()
	add_child(_smoke)
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.6, 0.3)
	_glow.light_energy = 0.0
	_glow.omni_range = 0.03
	add_child(_glow)

## Cautín orientado con la punta en -Y local y el origen en la punta.
func _build_iron() -> Node3D:
	var n := Node3D.new()
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.7, 0.71, 0.73); steel.metallic = 1.0; steel.roughness = 0.3
	var tip_mat := StandardMaterial3D.new()
	tip_mat.albedo_color = Color(0.85, 0.86, 0.9); tip_mat.metallic = 1.0; tip_mat.roughness = 0.12
	var grip := StandardMaterial3D.new()
	grip.albedo_color = Color(0.1, 0.28, 0.6); grip.roughness = 0.7
	var tip := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.0009; tm.bottom_radius = 0.0001; tm.height = 0.008; tm.radial_segments = 12
	tip.mesh = tm; tip.material_override = tip_mat; tip.position = Vector3(0, 0.004, 0)
	n.add_child(tip)
	var shaft := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.0022; sm.bottom_radius = 0.0012; sm.height = 0.035; sm.radial_segments = 16
	shaft.mesh = sm; shaft.material_override = steel; shaft.position = Vector3(0, 0.0255, 0)
	n.add_child(shaft)
	var handle := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.0055; hm.bottom_radius = 0.0045; hm.height = 0.07; hm.radial_segments = 20
	handle.mesh = hm; handle.material_override = grip; handle.position = Vector3(0, 0.078, 0)
	n.add_child(handle)
	return n

func _build_smoke() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 1.6
	p.emitting = false
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 18.0
	pm.initial_velocity_min = 0.01
	pm.initial_velocity_max = 0.025
	pm.gravity = Vector3(0, 0.012, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_scale = 0.8
	var fade := Gradient.new()
	fade.set_color(0, Color(0.85, 0.85, 0.85, 0.35))
	fade.set_color(1, Color(0.9, 0.9, 0.9, 0.0))
	var gt := GradientTexture1D.new(); gt.gradient = fade
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.006, 0.006)
	var qm := StandardMaterial3D.new()
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.vertex_color_use_as_albedo = true
	qm.albedo_texture = _soft_dot()
	quad.material = qm
	p.draw_pass_1 = quad
	return p

func _soft_dot() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 32; gt.height = 32
	return gt

## Suelda en el punto "p" (contacto exacto). "blob_parent" recibe la gota temporal.
func solder_at(p: Vector3, key: String, blob_parent: Node3D) -> void:
	if busy:
		return
	busy = true
	# Orientación: el cautín llega desde el lado de la cámara, inclinado 40°.
	var side := Vector3(1, 0, 0)
	if camera:
		side = camera.global_position - p
		side.y = 0.0
		if side.length() < 1e-4:
			side = Vector3(1, 0, 0)
		side = side.normalized()
	var up_dir := (Vector3.UP * cos(deg_to_rad(40.0)) + side * sin(deg_to_rad(40.0))).normalized()
	var contact := p + Vector3.UP * 0.0006
	var ib := Basis(Quaternion(Vector3.UP, up_dir))
	_iron.global_transform = Transform3D(ib, contact + up_dir * 0.05)
	_iron.visible = true
	_smoke.global_position = contact
	_glow.global_position = contact + Vector3.UP * 0.002
	var blob := CableRenderer.solder_joint(p, 0.0)
	var mat := blob.material_override as ShaderMaterial
	mat.set_shader_parameter("melt", 1.0)
	mat.set_shader_parameter("grow", 0.0)
	blob_parent.add_child(blob)

	var tw := create_tween()
	tw.tween_property(_iron, "global_position", contact, T_APPROACH).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		_smoke.emitting = true
		_glow.light_energy = 0.4)
	tw.tween_method(func(v: float): mat.set_shader_parameter("grow", v), 0.0, 1.0, T_MELT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_iron, "global_position", contact + up_dir * 0.05, T_RETRACT).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		_iron.visible = false
		_smoke.emitting = false
		_glow.light_energy = 0.0)
	tw.tween_method(func(v: float): mat.set_shader_parameter("melt", v), 1.0, 0.0, T_SOLIDIFY).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		blob.queue_free()
		busy = false
		finished.emit(key))
