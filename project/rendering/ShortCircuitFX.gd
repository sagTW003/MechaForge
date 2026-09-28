class_name ShortCircuitFX
extends Node3D
## ShortCircuitFX — Efectos 3D de fallas eléctricas.
##
##   · Chispas: partículas GPU incandescentes (HDR → bloom), alineadas con su
##     velocidad, con gravedad y un destello de luz breve.
##   · Humo: emisor continuo de partículas con textura suave, flotabilidad,
##     turbulencia y crecimiento (cables recalentados, resistencias sobrecargadas).
##   · Bocanada: humo instantáneo (LED o resistencia que se queman, fusible).
## La incandescencia de los cables la pinta el shader rendering/hot_wire.gdshader.

var _smokes: Dictionary = {}          # clave -> GPUParticles3D
static var _smoke_tex: Texture2D
static var _spark_mesh: Mesh
static var _spark_ramp: GradientTexture1D

func sparks_at(pos, amount: int = 60) -> void:
	if not (pos is Vector3) or not is_inside_tree():
		return
	var p := GPUParticles3D.new()
	p.name = "Chispas"
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.5
	p.explosiveness = 0.92
	p.randomness = 0.6
	p.fixed_fps = 0
	p.visibility_aabb = AABB(Vector3(-0.3, -0.3, -0.3), Vector3(0.6, 0.6, 0.6))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 85.0
	pm.initial_velocity_min = 0.25
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0, -9.8, 0)
	pm.damping_min = 0.2
	pm.damping_max = 0.8
	pm.particle_flag_align_y = true
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	pm.color_ramp = _ramp()
	p.process_material = pm
	p.draw_pass_1 = _spark()
	add_child(p)
	p.global_position = pos
	p.emitting = true
	p.restart()
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)

func flash_at(pos) -> void:
	if not (pos is Vector3) or not is_inside_tree():
		return
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.75, 0.4)
	l.light_energy = 5.0
	l.omni_range = 0.35
	l.shadow_enabled = false
	add_child(l)
	l.global_position = pos + Vector3(0, 0.01, 0)
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, 0.3)
	tw.tween_callback(l.queue_free)

## Humo continuo con clave (se actualiza posición e intensidad 0..1).
func smoke_on(key: String, pos: Vector3, intensity: float = 1.0) -> void:
	if not is_inside_tree():
		return
	var s: GPUParticles3D = _smokes.get(key)
	if s == null or not is_instance_valid(s):
		s = _make_smoke(40, 2.4, false)
		s.name = "Humo_%s" % key.replace(":", "_")
		add_child(s)
		_smokes[key] = s
	s.global_position = pos
	s.amount_ratio = clampf(intensity, 0.1, 1.0)
	s.emitting = true

func smoke_off(key: String) -> void:
	var s: GPUParticles3D = _smokes.get(key)
	if s and is_instance_valid(s):
		s.emitting = false
		_smokes.erase(key)
		get_tree().create_timer(3.0).timeout.connect(s.queue_free)

func is_smoking(key: String) -> bool:
	return _smokes.has(key)

func smoking_count() -> int:
	return _smokes.size()

func puff_at(pos) -> void:
	if not (pos is Vector3) or not is_inside_tree():
		return
	var s := _make_smoke(18, 2.0, true)
	s.name = "Bocanada"
	add_child(s)
	s.global_position = pos
	s.emitting = true
	s.restart()
	get_tree().create_timer(3.5).timeout.connect(s.queue_free)

func clear_all() -> void:
	for c in get_children():
		c.queue_free()
	_smokes.clear()

func _make_smoke(amount: int, life: float, burst: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = burst
	p.explosiveness = 0.85 if burst else 0.0
	p.randomness = 0.4
	p.visibility_aabb = AABB(Vector3(-0.3, -0.05, -0.3), Vector3(0.6, 0.6, 0.6))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.015
	pm.initial_velocity_max = 0.05
	pm.gravity = Vector3(0, 0.035, 0)          # flotabilidad del aire caliente
	pm.damping_min = 0.01
	pm.damping_max = 0.03
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.02
	pm.turbulence_influence_max = 0.06
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -30.0
	pm.angular_velocity_max = 30.0
	pm.scale_min = 0.6
	pm.scale_max = 1.0
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.35))
	sc.add_point(Vector2(1.0, 1.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(0.32, 0.31, 0.3, 0.0))
	g.set_color(1, Color(0.55, 0.55, 0.56, 0.0))
	g.add_point(0.12, Color(0.28, 0.27, 0.26, 0.55))
	g.add_point(0.55, Color(0.45, 0.45, 0.46, 0.3))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.03, 0.03)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _smoke_texture()
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	q.material = m
	p.draw_pass_1 = q
	return p

static func _spark() -> Mesh:
	if _spark_mesh:
		return _spark_mesh
	var b := BoxMesh.new()
	b.size = Vector3(0.00035, 0.0045, 0.00035)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	b.material = m
	_spark_mesh = b
	return b

static func _ramp() -> GradientTexture1D:
	if _spark_ramp:
		return _spark_ramp
	var g := Gradient.new()
	g.set_color(0, Color(6.0, 5.2, 3.5, 1.0))          # blanco-amarillo incandescente (HDR)
	g.set_color(1, Color(1.2, 0.15, 0.02, 0.0))
	g.add_point(0.35, Color(4.0, 2.0, 0.4, 1.0))
	g.add_point(0.7, Color(2.2, 0.6, 0.08, 0.8))
	var t := GradientTexture1D.new()
	t.gradient = g
	t.use_hdr = true
	_spark_ramp = t
	return t

## Textura de humo: mancha suave con ruido (generada, sin archivos).
static func _smoke_texture() -> Texture2D:
	if _smoke_tex:
		return _smoke_tex
	var n := FastNoiseLite.new()
	n.seed = 7
	n.frequency = 0.08
	n.fractal_octaves = 4
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var d := Vector2(x - 31.5, y - 31.5).length() / 32.0
			var fall := clampf(1.0 - d, 0.0, 1.0)
			fall = fall * fall * (3.0 - 2.0 * fall)
			var v := 0.6 + 0.4 * (n.get_noise_2d(x, y) * 0.5 + 0.5)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(fall * v, 0.0, 1.0)))
	_smoke_tex = ImageTexture.create_from_image(img)
	return _smoke_tex

## Color de incandescencia (cuerpo negro) para una temperatura en °C.
static func blackbody(t_c: float) -> Color:
	var k := t_c + 273.15
	var g := pow(clampf((k - 700.0) / 1500.0, 0.0, 1.0), 1.2) * 0.85
	var b := pow(clampf((k - 1100.0) / 2200.0, 0.0, 1.0), 1.5) * 0.7
	return Color(1.0, g, b)
