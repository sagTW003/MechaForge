extends Node
## MaterialLibrary — Biblioteca de materiales con propiedades físicas y PBR (autoload).
##
## Cada material define densidad real (kg/m³), parámetros de fricción/restitución
## y un aspecto PBR (StandardMaterial3D) para el render Forward+.
## Los datos vienen de una tabla; se pueden añadir materiales sin tocar la UI.

var _materials: Dictionary = {}          # id -> Dictionary de propiedades
var _cache: Dictionary = {}              # id -> StandardMaterial3D (perezoso)
var _detail_normal: Texture2D            # microrelieve procedural compartido
var _pending_tasks: Array = []           # tareas de generación de texturas
var _textured: Dictionary = {}           # id -> true cuando tiene texturas

## Textura de normales procedural (ruido) para dar microrelieve realista.
func _get_detail_normal() -> Texture2D:
	if _detail_normal:
		return _detail_normal
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.05
	var nt := NoiseTexture2D.new()
	nt.width = 256; nt.height = 256
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 1.5
	nt.noise = noise
	_detail_normal = nt
	return _detail_normal

# Tabla de materiales: densidad en kg/m³, colores en sRGB.
const DATA := {
	"aluminio": {
		"nombre": "Aluminio 6063", "patron": "cepillado", "densidad": 2700.0, "friccion": 0.5, "restitucion": 0.1,
		"color": Color(0.82, 0.84, 0.86), "metalico": 0.9, "rugosidad": 0.35, "limite_mpa": 214.0,
	},
	"aluminio_anodizado": {
		"nombre": "Aluminio anodizado", "patron": "granallado", "densidad": 2700.0, "friccion": 0.5, "restitucion": 0.1,
		"color": Color(0.18, 0.19, 0.22), "metalico": 0.85, "rugosidad": 0.45, "limite_mpa": 214.0,
	},
	"acero": {
		"nombre": "Acero estructural", "patron": "laminado", "densidad": 7850.0, "friccion": 0.6, "restitucion": 0.15,
		"color": Color(0.58, 0.60, 0.63), "metalico": 1.0, "rugosidad": 0.4, "limite_mpa": 250.0,
	},
	"acero_inox": {
		"nombre": "Acero inoxidable", "patron": "cepillado", "densidad": 8000.0, "friccion": 0.55, "restitucion": 0.2,
		"color": Color(0.74, 0.76, 0.78), "metalico": 1.0, "rugosidad": 0.22, "limite_mpa": 520.0,
	},
	"cobre": {
		"nombre": "Cobre", "patron": "cobre", "densidad": 8960.0, "friccion": 0.5, "restitucion": 0.1,
		"color": Color(0.85, 0.53, 0.36), "metalico": 1.0, "rugosidad": 0.3, "limite_mpa": 210.0,
	},
	"abs": {
		"nombre": "Plástico ABS", "patron": "plastico", "densidad": 1050.0, "friccion": 0.4, "restitucion": 0.3,
		"color": Color(0.15, 0.16, 0.18), "metalico": 0.0, "rugosidad": 0.6, "limite_mpa": 40.0,
	},
	"caucho": {
		"nombre": "Caucho", "patron": "caucho", "densidad": 1100.0, "friccion": 1.1, "restitucion": 0.6,
		"color": Color(0.05, 0.05, 0.06), "metalico": 0.0, "rugosidad": 0.9, "limite_mpa": 15.0,
	},
	"madera": {
		"nombre": "Madera (pino)", "patron": "madera", "densidad": 500.0, "friccion": 0.5, "restitucion": 0.2,
		"color": Color(0.62, 0.44, 0.26), "metalico": 0.0, "rugosidad": 0.75, "limite_mpa": 40.0,
	},
	"vidrio": {
		"nombre": "Vidrio", "patron": "vidrio", "densidad": 2500.0, "friccion": 0.4, "restitucion": 0.1,
		"color": Color(0.6, 0.75, 0.8, 0.35), "metalico": 0.0, "rugosidad": 0.05, "limite_mpa": 50.0,
	},
	"concreto": {
		"nombre": "Concreto", "patron": "concreto", "densidad": 2400.0, "friccion": 0.7, "restitucion": 0.1,
		"color": Color(0.55, 0.55, 0.53), "metalico": 0.0, "rugosidad": 0.9, "limite_mpa": 30.0,
	},
	"estano": {
		"nombre": "Estaño (soldadura)", "patron": "estano", "densidad": 7300.0, "friccion": 0.4, "restitucion": 0.1,
		"color": Color(0.78, 0.79, 0.82), "metalico": 1.0, "rugosidad": 0.18, "limite_mpa": 15.0,
	},
	"baquelita": {
		"nombre": "Baquelita / PCB", "patron": "pcb", "densidad": 1400.0, "friccion": 0.5, "restitucion": 0.1,
		"color": Color(0.09, 0.32, 0.15), "metalico": 0.0, "rugosidad": 0.55, "limite_mpa": 80.0,
	},
	"fibra_carbono": {
		"nombre": "Fibra de carbono", "patron": "carbono", "densidad": 1600.0, "friccion": 0.5, "restitucion": 0.1,
		"color": Color(0.06, 0.06, 0.07), "metalico": 0.2, "rugosidad": 0.35, "limite_mpa": 600.0,
	},
	"ptfe": {
		"nombre": "Teflón (PTFE)", "patron": "plastico", "densidad": 2200.0, "friccion": 0.05, "restitucion": 0.1,
		"color": Color(0.9, 0.9, 0.88), "metalico": 0.0, "rugosidad": 0.45, "limite_mpa": 23.0,
	},
	"acrilico": {
		"nombre": "Acrílico", "patron": "vidrio", "densidad": 1180.0, "friccion": 0.4, "restitucion": 0.2,
		"color": Color(0.7, 0.85, 0.95, 0.4), "metalico": 0.0, "rugosidad": 0.05, "limite_mpa": 70.0,
	},
	# Filamentos de impresión 3D: la masa sigue el modelo de paredes + relleno
	# (PartInstance.mass_kg); el límite es el de la pieza impresa, no el del filamento.
	"pla": {
		"nombre": "PLA (impresión 3D)", "patron": "impreso", "densidad": 1240.0, "friccion": 0.35, "restitucion": 0.3,
		"color": Color(0.80, 0.81, 0.83), "metalico": 0.0, "rugosidad": 0.55, "limite_mpa": 50.0, "imprimible": true,
	},
	"petg": {
		"nombre": "PETG (impresión 3D)", "patron": "impreso", "densidad": 1270.0, "friccion": 0.4, "restitucion": 0.3,
		"color": Color(0.16, 0.36, 0.52), "metalico": 0.0, "rugosidad": 0.3, "limite_mpa": 50.0, "imprimible": true,
	},
	# Cartón corrugado de canal E (~1.5 mm, ~400 g/m²): densidad aparente de la plancha.
	"carton": {
		"nombre": "Cartón corrugado", "patron": "carton", "densidad": 250.0, "friccion": 0.5, "restitucion": 0.05,
		"color": Color(0.64, 0.49, 0.32), "metalico": 0.0, "rugosidad": 0.92, "limite_mpa": 5.0,
	},
}

## Juego de texturas real para cada material (si falta, se usa el procedural).
const TEXTURED := {
	"aluminio": {"set": "Metal009", "tint": Color(1.0, 1.0, 1.02), "opts": {"scale": 8.0, "metallic": 1.0}},
	"acero_inox": {"set": "Metal009", "tint": Color(0.92, 0.93, 0.95), "opts": {"scale": 12.0, "metallic": 1.0, "rough": 0.8}},
	"acero": {"set": "Metal055A", "tint": Color(0.95, 0.95, 0.95), "opts": {"scale": 4.0}},
	"abs": {"set": "Plastic013A", "tint": Color(0.16, 0.17, 0.19), "opts": {"scale": 30.0, "rough": 1.2}},
	"ptfe": {"set": "Plastic013A", "tint": Color(0.95, 0.95, 0.92), "opts": {"scale": 30.0}},
	"caucho": {"set": "Rubber004", "tint": Color(0.9, 0.9, 0.92), "opts": {"scale": 30.0}},
	"madera": {"set": "Wood066", "tint": Color.WHITE, "opts": {"scale": 3.0}},
	"concreto": {"set": "Concrete042A", "tint": Color.WHITE, "opts": {"scale": 1.5}},
}

func _ready() -> void:
	_materials = DATA.duplicate(true)

func ids() -> Array:
	return _materials.keys()

func has_material(id: String) -> bool:
	return _materials.has(id)

func get_data(id: String) -> Dictionary:
	return _materials.get(id, _materials["acero"])

func display_name(id: String) -> String:
	return get_data(id).get("nombre", id)

func density(id: String) -> float:
	return get_data(id).get("densidad", 1000.0)

func friction(id: String) -> float:
	return get_data(id).get("friccion", 0.5)

func restitution(id: String) -> float:
	return get_data(id).get("restitucion", 0.1)

func yield_strength_pa(id: String) -> float:
	return get_data(id).get("limite_mpa", 100.0) * 1.0e6

## Filamento de impresión 3D: la pieza lleva paredes y relleno (no es maciza).
func is_printable(id: String) -> bool:
	return bool(get_data(id).get("imprimible", false))

## Devuelve (y cachea) el StandardMaterial3D PBR para un material dado.
## Las texturas procedurales (albedo/rugosidad/normales) se generan en un hilo de
## trabajo y se asignan al terminar; mientras tanto se usa el color plano.
func get_visual(id: String) -> StandardMaterial3D:
	if _cache.has(id):
		return _cache[id]
	var d := get_data(id)
	# Materiales con textura fotográfica real disponible (ambientCG, CC0).
	if TEXTURED.has(id):
		var t: Dictionary = TEXTURED[id]
		var opts: Dictionary = t["opts"].duplicate()
		opts["tint"] = t.get("tint", Color.WHITE)
		var tm := TextureSets.material(t["set"], opts)
		if tm:
			_cache[id] = tm
			_textured[id] = true
			return tm
	var m := StandardMaterial3D.new()
	var col: Color = d.get("color", Color.GRAY)
	m.albedo_color = col
	m.metallic = d.get("metalico", 0.0)
	m.roughness = d.get("rugosidad", 0.5)
	m.metallic_specular = 0.5
	if col.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Mapeo triplanar en espacio local: la textura mantiene su escala real (m)
	# sea cual sea el tamaño de la pieza.
	var pat: String = d.get("patron", "")
	m.uv1_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3.ONE * ProceduralTextures.scale_for(pat)
	m.normal_enabled = true
	m.normal_texture = _get_detail_normal()
	m.normal_scale = 0.35 if d.get("metalico", 0.0) > 0.5 else 0.15
	# Laca brillante sobre fibra de carbono y anodizado.
	if pat == "carbono" or pat == "granallado":
		m.clearcoat_enabled = true
		m.clearcoat = 0.6 if pat == "carbono" else 0.25
		m.clearcoat_roughness = 0.12
	_cache[id] = m
	if pat != "":
		_request_textures(id, pat, col, m.roughness)
	return m

## Lanza la generación de texturas de un material en el WorkerThreadPool.
func _request_textures(id: String, pat: String, col: Color, rough: float) -> void:
	var seed := absi(id.hash()) % 10000
	var task := func():
		var imgs := ProceduralTextures.generate(pat, Color(col.r, col.g, col.b), rough, seed)
		call_deferred("_on_textures_ready", id, imgs)
	_pending_tasks.append(WorkerThreadPool.add_task(task, false, "Texturas %s" % id))

func _on_textures_ready(id: String, imgs: Dictionary) -> void:
	var m: StandardMaterial3D = _cache.get(id)
	if m == null:
		return
	var a: Color = m.albedo_color
	m.albedo_texture = ImageTexture.create_from_image(imgs["albedo"])
	m.albedo_color = Color(1, 1, 1, a.a)
	m.roughness_texture = ImageTexture.create_from_image(imgs["rough"])
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.roughness = 1.0
	m.normal_texture = ImageTexture.create_from_image(imgs["normal"])
	m.normal_scale = 0.6
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_textured[id] = true

## True cuando las texturas procedurales del material ya están aplicadas.
func is_textured(id: String) -> bool:
	return _textured.has(id)

## Genera ya (de forma síncrona) las texturas de todos los materiales en uso.
func wait_textures() -> void:
	for t in _pending_tasks:
		WorkerThreadPool.wait_for_task_completion(t)
	_pending_tasks.clear()

func _exit_tree() -> void:
	wait_textures()

## Material semitransparente para vistas previas "fantasma" (IA / colocación).
func get_ghost(base_id: String, valid: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = (Color(0.35, 0.8, 1.0, 0.45) if valid else Color(1.0, 0.35, 0.35, 0.45))
	m.metallic = 0.0
	m.roughness = 0.5
	m.emission_enabled = true
	m.emission = m.albedo_color
	m.emission_energy_multiplier = 0.4
	return m
