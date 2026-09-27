extends Node
## PartLibrary — Catálogo de piezas definido por DATOS (autoload).
##
## Carga todas las definiciones de piezas desde archivos JSON en res://parts/**.
## Añadir una pieza nueva = añadir un .json, sin tocar código.
##
## Formato de una definición (JSON):
## {
##   "id": "perfil_2020_200",
##   "nombre": "Perfil aluminio 20x20 (200 mm)",
##   "categoria": "estructural",
##   "material": "aluminio",
##   "forma": "caja",                     # caja | cilindro | placa | tubo
##   "dimensiones_mm": {"x": 20, "y": 200, "z": 20},   # o {"radio","altura"} para cilindro
##   "anclajes": [ {"pos_mm": [0,100,0], "eje": [0,1,0]}, ... ]  # opcional
## }

var _defs: Dictionary = {}     # id -> Dictionary
var _by_category: Dictionary = {}

const PARTS_ROOT := "res://parts"

func _ready() -> void:
	_scan_dir(PARTS_ROOT)
	if _defs.is_empty():
		push_warning("PartLibrary: no se encontraron definiciones en %s" % PARTS_ROOT)

func _scan_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := path.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with("."):
				_scan_dir(full)
		elif name.get_extension().to_lower() == "json":
			_load_file(full)
		name = dir.get_next()
	dir.list_dir_end()

func _load_file(file_path: String) -> void:
	var txt := FileAccess.get_file_as_string(file_path)
	if txt.is_empty():
		return
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("PartLibrary: JSON inválido en %s" % file_path)
		return
	var entries := []
	# Un archivo puede contener una pieza (dict) o una lista de piezas.
	if parsed.has("piezas") and typeof(parsed["piezas"]) == TYPE_ARRAY:
		entries = parsed["piezas"]
	else:
		entries = [parsed]
	for e in entries:
		if typeof(e) == TYPE_DICTIONARY and e.has("id"):
			register(e)

func register(def: Dictionary) -> void:
	var id: String = def["id"]
	_defs[id] = def
	var cat: String = def.get("categoria", "otros")
	if not _by_category.has(cat):
		_by_category[cat] = []
	if not _by_category[cat].has(id):
		_by_category[cat].append(id)

func has_part(id: String) -> bool:
	return _defs.has(id)

func get_def(id: String) -> Dictionary:
	return _defs.get(id, {})

func categories() -> Array:
	var c := _by_category.keys()
	c.sort()
	return c

func parts_in(category: String) -> Array:
	var arr: Array = _by_category.get(category, [])
	arr.sort()
	return arr

func all_ids() -> Array:
	return _defs.keys()

## Dimensiones en metros (Vector3) a partir de la definición.
static func dims_m(def: Dictionary) -> Vector3:
	var forma: String = def.get("forma", "caja")
	if forma == "cilindro" or forma == "tubo":
		var d: Dictionary = def.get("dimensiones_mm", {})
		var r: float = float(d.get("radio", 10.0)) / 1000.0
		var h: float = float(d.get("altura", 100.0)) / 1000.0
		return Vector3(r * 2.0, h, r * 2.0)
	elif forma == "engranaje":
		var ra := gear_tip_radius_m(def)
		var w := float(def.get("dimensiones_mm", {}).get("ancho", 8.0)) / 1000.0
		return Vector3(ra * 2.0, w * 1.6, ra * 2.0)
	else:
		var d: Dictionary = def.get("dimensiones_mm", {})
		return Vector3(float(d.get("x", 20)), float(d.get("y", 20)), float(d.get("z", 20))) / 1000.0

## Volumen aproximado en m³ (para masa).
static func volume_m3(def: Dictionary) -> float:
	var forma: String = def.get("forma", "caja")
	var d: Dictionary = def.get("dimensiones_mm", {})
	match forma:
		"cilindro":
			var r := float(d.get("radio", 10.0)) / 1000.0
			var h := float(d.get("altura", 100.0)) / 1000.0
			return PI * r * r * h
		"tubo":
			var r := float(d.get("radio", 10.0)) / 1000.0
			var h := float(d.get("altura", 100.0)) / 1000.0
			var e := float(d.get("espesor", 2.0)) / 1000.0
			var ri := maxf(0.0, r - e)
			return PI * (r * r - ri * ri) * h
		"engranaje":
			var rp := gear_pitch_radius_m(def)
			var w := float(d.get("ancho", 8.0)) / 1000.0
			return PI * rp * rp * w * 0.95
		"placa", "caja", _:
			var v := dims_m(def)
			# Perfiles en T: fracción maciza de la sección (2020 ≈ 0.5 kg/m).
			var fill := float(def.get("relleno", 1.0))
			return v.x * v.y * v.z * fill

## Engranajes: número de dientes, módulo (mm) y radios en metros.
static func gear_teeth(def: Dictionary) -> int:
	return int(def.get("dimensiones_mm", {}).get("dientes", 20))

static func gear_module_m(def: Dictionary) -> float:
	return float(def.get("dimensiones_mm", {}).get("modulo", 1.0)) / 1000.0

static func gear_pitch_radius_m(def: Dictionary) -> float:
	return gear_module_m(def) * gear_teeth(def) * 0.5

static func gear_tip_radius_m(def: Dictionary) -> float:
	return gear_pitch_radius_m(def) + gear_module_m(def)

static func gear_root_radius_m(def: Dictionary) -> float:
	return gear_pitch_radius_m(def) - 1.25 * gear_module_m(def)
