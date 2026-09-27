class_name WorkEnvironment
extends Node3D
## WorkEnvironment — Entorno de trabajo 3D: cielo/HDRI, luces y suelo.
##
## Modos:
##   ESTUDIO  — "HDRI" procedural de estudio (softboxes) + suelo de epoxi. Ideal para
##              ver materiales: los metales reflejan las cajas de luz.
##   TALLER   — nave de taller procedural (ventanales, tubos fluorescentes, panel de
##              herramientas) + hormigón pulido con cinta de seguridad.
##   EXTERIOR — campo de pruebas con cielo físico y ciclo día/noche opcional.
##   HDRI de usuario — cualquier .hdr/.exr/.png/.jpg en res://assets/hdri o
##              user://hdri se ofrece como entorno adicional (PanoramaSkyMaterial).
##
## Mantiene un único Environment (los perfiles gráficos lo ajustan) y solo cambia
## el cielo, la exposición, las luces y el estilo del suelo.

enum Mode { ESTUDIO, TALLER, EXTERIOR }
const MODE_NAMES := ["Estudio", "Taller", "Exterior"]
const HDRI_DIRS := ["res://assets/hdri", "user://hdri"]

var world_env: WorldEnvironment
var sun: DirectionalLight3D
var fill_light: DirectionalLight3D
var floor_mesh: MeshInstance3D

var mode: int = Mode.ESTUDIO
var hdri_path: String = ""
var time_of_day: float = 15.5           # horas (exterior)
var day_cycle: bool = false
var cycle_hours_per_second: float = 0.1  # un día completo ≈ 4 minutos

var _studio_sky: ShaderMaterial
var _physical_sky: PhysicalSkyMaterial
var _floor_mat: ShaderMaterial

func _ready() -> void:
	_build()
	set_mode(mode)

func _build() -> void:
	world_env = WorldEnvironment.new()
	world_env.name = "Entorno"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.sky.process_mode = Sky.PROCESS_MODE_QUALITY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# Tonemapping fílmico (ACES).
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	# Oclusión ambiental, iluminación indirecta y reflejos en pantalla.
	env.ssao_enabled = true
	env.ssao_radius = 0.35
	env.ssao_intensity = 1.6
	env.ssao_detail = 0.8
	env.ssil_enabled = true
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.1
	env.ssr_fade_out = 2.0
	# Iluminación global en tiempo real.
	env.sdfgi_enabled = true
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.05
	# Bloom leve: solo lo que supera el umbral HDR (LEDs, pantallas, soldadura).
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.6
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	# Niebla volumetrica sutil.
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.004
	env.volumetric_fog_albedo = Color(0.7, 0.75, 0.8)
	# Ajuste de color fino.
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.05
	world_env.environment = env
	add_child(world_env)

	_studio_sky = ShaderMaterial.new()
	_studio_sky.shader = load("res://rendering/studio_sky.gdshader")
	_physical_sky = PhysicalSkyMaterial.new()
	_physical_sky.rayleigh_coefficient = 2.0
	_physical_sky.mie_coefficient = 0.005
	_physical_sky.turbidity = 6.0
	_physical_sky.sun_disk_scale = 1.0
	_physical_sky.energy_multiplier = 1.0

	sun = DirectionalLight3D.new()
	sun.name = "Sol"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 25.0
	sun.shadow_blur = 1.2
	sun.light_angular_distance = 0.5        # penumbra suave realista (PCSS): nítida en el contacto
	add_child(sun)

	fill_light = DirectionalLight3D.new()
	fill_light.name = "Relleno"
	fill_light.shadow_enabled = false
	fill_light.light_specular = 0.3
	add_child(fill_light)

	floor_mesh = MeshInstance3D.new()
	floor_mesh.name = "Suelo"
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	floor_mesh.mesh = plane
	_floor_mat = ShaderMaterial.new()
	_floor_mat.shader = load("res://rendering/floor_grid.gdshader")
	_floor_mat.set_shader_parameter("minor_step", Config.grid_size_m)
	floor_mesh.material_override = _floor_mat
	add_child(floor_mesh)
	Config.grid_settings_changed.connect(func(): _floor_mat.set_shader_parameter("minor_step", Config.grid_size_m))

## Lista de nombres de entornos disponibles (modos + HDRI encontrados).
func available() -> Array:
	var out: Array = MODE_NAMES.duplicate()
	for p in find_hdris():
		out.append("HDRI: %s" % p.get_file().get_basename())
	return out

func find_hdris() -> Array:
	var out := []
	for d in HDRI_DIRS:
		var dir := DirAccess.open(d)
		if dir == null:
			continue
		for f in dir.get_files():
			if f.get_extension().to_lower() in ["hdr", "exr", "png", "jpg", "jpeg", "webp"]:
				out.append(d.path_join(f))
	return out

## Selecciona por índice de available().
func select_index(i: int) -> void:
	if i < MODE_NAMES.size():
		hdri_path = ""
		set_mode(i)
	else:
		var list := find_hdris()
		var k := i - MODE_NAMES.size()
		if k >= 0 and k < list.size():
			load_hdri(list[k])

func current_index() -> int:
	if hdri_path != "":
		return MODE_NAMES.size() + maxi(0, find_hdris().find(hdri_path))
	return mode

func set_mode(m: int) -> void:
	mode = m
	hdri_path = ""
	var env := world_env.environment
	match mode:
		Mode.ESTUDIO:
			_studio_sky.set_shader_parameter("mode", 0)
			env.sky.sky_material = _studio_sky
			env.tonemap_exposure = 1.0
			env.ambient_light_energy = 1.0
			env.volumetric_fog_density = 0.002
			_set_light(sun, 60.0, 40.0, 1.8, Color(1.0, 0.97, 0.92))
			_set_light(fill_light, -120.0, 18.0, 0.25, Color(0.85, 0.9, 1.0))
			_floor_style(0, 80.0)
		Mode.TALLER:
			_studio_sky.set_shader_parameter("mode", 1)
			env.sky.sky_material = _studio_sky
			env.tonemap_exposure = 0.85
			env.ambient_light_energy = 1.0
			env.volumetric_fog_density = 0.006
			# Luz de los ventanales (+X) y relleno cálido de los tubos del techo.
			_set_light(sun, 90.0, 38.0, 1.3, Color(1.0, 0.96, 0.9))
			_set_light(fill_light, -80.0, 70.0, 0.35, Color(1.0, 0.95, 0.85))
			_floor_style(1, 80.0)
		Mode.EXTERIOR:
			env.sky.sky_material = _physical_sky
			env.volumetric_fog_density = 0.004
			_floor_style(2, 600.0)
			_apply_time_of_day()
	Config.notify("Entorno: %s" % MODE_NAMES[mode], 3.0)

## Carga un HDRI equirrectangular del usuario como cielo.
func load_hdri(path: String) -> bool:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		Config.notify("No se pudo cargar el HDRI: %s" % path.get_file(), 5.0)
		return false
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = ImageTexture.create_from_image(img)
	pano.energy_multiplier = 1.0
	var env := world_env.environment
	env.sky.sky_material = pano
	env.tonemap_exposure = 1.0
	_set_light(sun, -40.0, 40.0, 1.0, Color(1, 0.98, 0.95))
	_set_light(fill_light, 130.0, 20.0, 0.15, Color(0.9, 0.95, 1.0))
	_floor_style(0, 80.0)
	hdri_path = path
	Config.notify("Entorno HDRI: %s" % path.get_file(), 4.0)
	return true

func set_time_of_day(h: float) -> void:
	time_of_day = fposmod(h, 24.0)
	if mode == Mode.EXTERIOR and hdri_path == "":
		_apply_time_of_day()

func _process(delta: float) -> void:
	if day_cycle and mode == Mode.EXTERIOR and hdri_path == "":
		set_time_of_day(time_of_day + delta * cycle_hours_per_second)

## Posición del sol según la hora: sale a las 6 h por el este, cenit a las 13 h.
func sun_elevation_deg(h: float) -> float:
	return 62.0 * sin((h - 6.5) / 13.0 * PI) if h > 6.5 and h < 19.5 else -12.0 * sin(fposmod(h - 19.5, 24.0) / 11.0 * PI)

func _apply_time_of_day() -> void:
	var env := world_env.environment
	var h := time_of_day
	var el := sun_elevation_deg(h)
	var az := -90.0 + (h - 6.5) / 13.0 * 180.0
	var day := clampf((el + 4.0) / 14.0, 0.0, 1.0)         # 0 noche ... 1 día pleno
	var golden := clampf(1.0 - absf(el - 6.0) / 12.0, 0.0, 1.0)
	var sun_col := Color(1.0, 0.97, 0.9).lerp(Color(1.0, 0.62, 0.32), golden)
	_set_light(sun, az, maxf(el, 2.0), 1.5 * day, sun_col)
	sun.visible = day > 0.01
	# Luna/cielo nocturno como relleno azulado.
	_set_light(fill_light, az + 180.0, 35.0, lerpf(0.12, 0.2, day), Color(0.6, 0.7, 1.0).lerp(Color(0.8, 0.88, 1.0), day))
	env.tonemap_exposure = lerpf(2.4, 0.85, day)
	env.ambient_light_energy = lerpf(0.35, 1.0, day)
	_physical_sky.energy_multiplier = lerpf(0.15, 1.0, day)

## Orienta una luz direccional: acimut (desde +Z hacia +X) y elevación en grados.
func _set_light(l: DirectionalLight3D, az_deg: float, el_deg: float, energy: float, col: Color) -> void:
	var az := deg_to_rad(az_deg)
	var el := deg_to_rad(el_deg)
	# Dirección DESDE la que llega la luz.
	var from := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el))
	l.basis = Basis.looking_at(-from, Vector3.UP if absf(from.y) < 0.99 else Vector3.BACK)
	l.light_energy = energy
	l.light_color = col
	l.visible = energy > 0.0

func _floor_style(s: int, size: float) -> void:
	_floor_mat.set_shader_parameter("style", s)
	(floor_mesh.mesh as PlaneMesh).size = Vector2(size, size)
