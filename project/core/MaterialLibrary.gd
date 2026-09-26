extends Node
## MaterialLibrary — Biblioteca de materiales con propiedades físicas y PBR (autoload).
##
## Cada material define densidad real (kg/m³), parámetros de fricción/restitución
## y un aspecto PBR (StandardMaterial3D) para el render Forward+.
## Los datos vienen de una tabla; se pueden añadir materiales sin tocar la UI.

var _materials: Dictionary = {}          # id -> Dictionary de propiedades
var _cache: Dictionary = {}              # id -> StandardMaterial3D (perezoso)

# Tabla de materiales: densidad en kg/m³, colores en sRGB.
const DATA := {
	"aluminio": {
		"nombre": "Aluminio 6063", "densidad": 2700.0, "friccion": 0.5, "restitucion": 0.1,
		"color": Color(0.82, 0.84, 0.86), "metalico": 0.9, "rugosidad": 0.35, "limite_mpa": 214.0,
	},
	"aluminio_anodizado": {
		"nombre": "Aluminio anodizado", "densidad": 2700.0, "friccion": 0.5, "restitucion": 0.1,
		"color": Color(0.18, 0.19, 0.22), "metalico": 0.85, "rugosidad": 0.45, "limite_mpa": 214.0,
	},
	"acero": {
		"nombre": "Acero estructural", "densidad": 7850.0, "friccion": 0.6, "restitucion": 0.15,
		"color": Color(0.58, 0.60, 0.63), "metalico": 1.0, "rugosidad": 0.4, "limite_mpa": 250.0,
	},
	"acero_inox": {
		"nombre": "Acero inoxidable", "densidad": 8000.0, "friccion": 0.55, "restitucion": 0.2,
		"color": Color(0.74, 0.76, 0.78), "metalico": 1.0, "rugosidad": 0.22, "limite_mpa": 520.0,
	},
	"cobre": {
		"nombre": "Cobre", "densidad": 8960.0, "friccion": 0.5, "restitucion": 0.1,
		"color": Color(0.85, 0.53, 0.36), "metalico": 1.0, "rugosidad": 0.3, "limite_mpa": 210.0,
	},
	"abs": {
		"nombre": "Plástico ABS", "densidad": 1050.0, "friccion": 0.4, "restitucion": 0.3,
		"color": Color(0.15, 0.16, 0.18), "metalico": 0.0, "rugosidad": 0.6, "limite_mpa": 40.0,
	},
	"caucho": {
		"nombre": "Caucho", "densidad": 1100.0, "friccion": 1.1, "restitucion": 0.6,
		"color": Color(0.05, 0.05, 0.06), "metalico": 0.0, "rugosidad": 0.9, "limite_mpa": 15.0,
	},
	"madera": {
		"nombre": "Madera (pino)", "densidad": 500.0, "friccion": 0.5, "restitucion": 0.2,
		"color": Color(0.62, 0.44, 0.26), "metalico": 0.0, "rugosidad": 0.75, "limite_mpa": 40.0,
	},
	"vidrio": {
		"nombre": "Vidrio", "densidad": 2500.0, "friccion": 0.4, "restitucion": 0.1,
		"color": Color(0.6, 0.75, 0.8, 0.35), "metalico": 0.0, "rugosidad": 0.05, "limite_mpa": 50.0,
	},
	"concreto": {
		"nombre": "Concreto", "densidad": 2400.0, "friccion": 0.7, "restitucion": 0.1,
		"color": Color(0.55, 0.55, 0.53), "metalico": 0.0, "rugosidad": 0.9, "limite_mpa": 30.0,
	},
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

func yield_strength_pa(id: String) -> float:
	return get_data(id).get("limite_mpa", 100.0) * 1.0e6

## Devuelve (y cachea) el StandardMaterial3D PBR para un material dado.
func get_visual(id: String) -> StandardMaterial3D:
	if _cache.has(id):
		return _cache[id]
	var d := get_data(id)
	var m := StandardMaterial3D.new()
	var col: Color = d.get("color", Color.GRAY)
	m.albedo_color = col
	m.metallic = d.get("metalico", 0.0)
	m.roughness = d.get("rugosidad", 0.5)
	m.metallic_specular = 0.5
	if col.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cache[id] = m
	return m

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
