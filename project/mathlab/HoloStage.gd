class_name HoloStage
extends Node3D
## HoloStage — Escenario del Laboratorio matemático ("holodeck").
##
## Sala oscura futurista: cielo procedural con franjas de luz que actúa como mapa
## de entorno (reflejos tipo HDRI), suelo negro brillante con rejilla luminosa y
## reflejos en espacio de pantalla, luz principal con sombras suaves, luces de
## contorno frías y post-procesado: bloom suave, oclusión ambiental (SSAO),
## reflejos (SSR), iluminación indirecta (SSIL), niebla volumétrica tenue,
## tonemapping AgX y profundidad de campo opcional ("efecto macro").

var world_env: WorldEnvironment
var env: Environment
var cam_attr: CameraAttributesPractical
var key_light: DirectionalLight3D
var floor_mat: ShaderMaterial

func _ready() -> void:
	name = "Holodeck"
	env = Environment.new()
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://mathlab/shaders/holo_sky.gdshader")
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 0.95
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.set_glow_level(1, 0.6)
	env.set_glow_level(3, 1.0)
	env.set_glow_level(5, 0.7)
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	env.ssao_intensity = 1.6
	env.ssr_enabled = true
	env.ssr_max_steps = 64
	env.ssr_fade_in = 0.1
	env.ssr_fade_out = 2.0
	env.ssil_enabled = true
	env.ssil_intensity = 0.6
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.008
	env.volumetric_fog_albedo = Color(0.35, 0.55, 0.8)
	env.volumetric_fog_emission = Color(0.0, 0.01, 0.02)
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.1
	world_env = WorldEnvironment.new()
	world_env.environment = env
	cam_attr = CameraAttributesPractical.new()
	cam_attr.dof_blur_far_enabled = false
	cam_attr.dof_blur_near_enabled = false
	cam_attr.dof_blur_amount = 0.08
	world_env.camera_attributes = cam_attr
	add_child(world_env)
	# Luz principal cálida con sombras suaves, contraluz frío y relleno.
	key_light = DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-52, 35, 0)
	key_light.light_energy = 1.3
	key_light.light_color = Color(1.0, 0.95, 0.88)
	key_light.shadow_enabled = true
	key_light.light_angular_distance = 1.5
	key_light.directional_shadow_max_distance = 30.0
	add_child(key_light)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, -150, 0)
	rim.light_energy = 0.9
	rim.light_color = Color(0.35, 0.65, 1.0)
	add_child(rim)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-5, 4, 5)
	fill.omni_range = 18.0
	fill.light_energy = 0.6
	fill.light_color = Color(0.6, 0.75, 1.0)
	add_child(fill)
	# Suelo con rejilla luminosa.
	var floor_mi := MeshInstance3D.new()
	floor_mi.name = "Suelo"
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	floor_mi.mesh = pm
	floor_mat = ShaderMaterial.new()
	floor_mat.shader = load("res://mathlab/shaders/holo_floor.gdshader")
	floor_mi.material_override = floor_mat
	floor_mi.position = Vector3(0, -1.6, 0)
	add_child(floor_mi)
	# Pedestal (disco oscuro con aro emisivo) bajo el objeto matemático.
	var ped := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 3.1
	cyl.bottom_radius = 3.25
	cyl.height = 0.12
	cyl.radial_segments = 96
	ped.mesh = cyl
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.03, 0.035, 0.045)
	pmat.metallic = 0.8
	pmat.roughness = 0.22
	ped.material_override = pmat
	ped.position = Vector3(0, -1.54, 0)
	add_child(ped)
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 3.12
	tor.outer_radius = 3.17
	tor.rings = 128
	ring.mesh = tor
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.1, 0.7, 1.0)
	rmat.emission_enabled = true
	rmat.emission = Color(0.1, 0.7, 1.0)
	rmat.emission_energy_multiplier = 1.4
	ring.material_override = rmat
	ring.position = Vector3(0, -1.48, 0)
	add_child(ring)

## Profundidad de campo tipo macro: enfoca a "focus" metros de la cámara.
func set_macro(on: bool, focus: float) -> void:
	cam_attr.dof_blur_far_enabled = on
	cam_attr.dof_blur_near_enabled = on
	cam_attr.dof_blur_far_distance = focus * 1.35
	cam_attr.dof_blur_far_transition = focus * 1.2
	cam_attr.dof_blur_near_distance = focus * 0.55
	cam_attr.dof_blur_near_transition = focus * 0.35

## Calidad: desactiva efectos caros en equipos modestos.
func set_quality(high: bool) -> void:
	env.ssil_enabled = high
	env.ssr_enabled = high
	env.volumetric_fog_enabled = high
	env.ssao_enabled = true
