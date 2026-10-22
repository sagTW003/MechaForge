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
	elif forma == "esfera":
		var rs := float(def.get("dimensiones_mm", {}).get("radio", 10.0)) / 1000.0
		return Vector3.ONE * rs * 2.0
	elif forma == "engranaje":
		var ra := gear_tip_radius_m(def)
		var w := float(def.get("dimensiones_mm", {}).get("ancho", 8.0)) / 1000.0
		return Vector3(ra * 2.0, w * 1.6, ra * 2.0)
	elif forma == "lente":
		var lg := lens_geometry(def)
		return Vector3(lg["r"] * 2.0, lg["t"], lg["r"] * 2.0)
	else:
		var d: Dictionary = def.get("dimensiones_mm", {})
		return Vector3(float(d.get("x", 20)), float(d.get("y", 20)), float(d.get("z", 20))) / 1000.0

## Pieza importada con malla estanca: su volumen, centroide e inercia son los de
## la propia malla (MeshImporter.mass_properties) y no los de la caja envolvente.
static func has_mesh_mass(def: Dictionary) -> bool:
	if def.get("forma", "") != "custom":
		return false
	var m: Dictionary = def.get("_masa", {})
	return bool(m.get("cerrada", false)) and float(m.get("volumen", 0.0)) > 0.0

## Masa de la geometría real (densidad 1) para las piezas que no son una sola caja,
## cilindro o esfera: malla importada estanca o pieza hecha de varias cajas.
## {volumen, area, centroide (espacio de la pieza), inercia [Ixx, Iyy, Izz, Ixy, Ixz, Iyz]
## respecto al centroide}, o vacío si la pieza usa las fórmulas de su forma.
static func mass_model(def: Dictionary) -> Dictionary:
	if has_mesh_mass(def):
		return def["_masa"]
	if def.get("forma", "") == "cabeza":
		return ellipsoid_mass(dims_m(def) * 0.5)
	var boxes := compound_boxes(def)
	if boxes.is_empty():
		return {}
	return boxes_mass(boxes)

## Elipsoide de semiejes s (densidad 1): volumen, área (fórmula de Knud Thomsen,
## error < 1.1 %), centroide e inercia respecto al centro.
static func ellipsoid_mass(s: Vector3) -> Dictionary:
	var v := 4.0 / 3.0 * PI * s.x * s.y * s.z
	var p := 1.6075
	var ab := pow(s.x * s.y, p)
	var ac := pow(s.x * s.z, p)
	var bc := pow(s.y * s.z, p)
	var area := 4.0 * PI * pow((ab + ac + bc) / 3.0, 1.0 / p)
	return {"volumen": v, "area": area, "centroide": Vector3.ZERO, "cerrada": true,
		"inercia": [v * (s.y * s.y + s.z * s.z) / 5.0, v * (s.x * s.x + s.z * s.z) / 5.0, v * (s.x * s.x + s.y * s.y) / 5.0, 0.0, 0.0, 0.0]}

## Puntos de un elipsoide de semiejes s (colisión convexa y pruebas).
static func ellipsoid_points(s: Vector3, rings := 10, segs := 16) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in range(rings + 1):
		var th := PI * float(i) / rings
		for j in range(segs if i > 0 and i < rings else 1):
			var ph := TAU * float(j) / segs
			pts.append(Vector3(sin(th) * cos(ph) * s.x, cos(th) * s.y, sin(th) * sin(ph) * s.z))
	return pts

static func has_custom_mass(def: Dictionary) -> bool:
	return not mass_model(def).is_empty()

## Piezas formadas por varias cajas (centro y tamaño en metros, espacio de la pieza,
## sin solaparse): la carcasa del visor y el soporte de lentes. Sirven para la malla,
## la colisión exacta (huecos incluidos) y la masa.
static func compound_boxes(def: Dictionary) -> Array:
	var d: Dictionary = def.get("dimensiones_mm", {})
	match def.get("forma", ""):
		"carcasa":
			# Abierta por −X (cara); pared frontal en +X; hueco de la nariz abajo en −X.
			var L := float(d.get("x", 65.0)) / 1000.0
			var H := float(d.get("y", 95.0)) / 1000.0
			var W := float(d.get("z", 160.0)) / 1000.0
			var t := clampf(float(d.get("espesor", 2.5)) / 1000.0, 0.0005, minf(L, minf(H, W)) * 0.3)
			var nz: Dictionary = def.get("nariz", {})
			var nw := clampf(float(nz.get("ancho", 0.0)) / 1000.0, 0.0, W - 4.0 * t)
			var nd := clampf(float(nz.get("fondo", 0.0)) / 1000.0, 0.0, L - 2.0 * t)
			var out := [
				{"c": Vector3(L / 2.0 - t / 2.0, 0, 0), "s": Vector3(t, H, W)},                      # frontal
				{"c": Vector3(-t / 2.0, 0, W / 2.0 - t / 2.0), "s": Vector3(L - t, H - 2.0 * t, t)}, # lateral +Z
				{"c": Vector3(-t / 2.0, 0, -W / 2.0 + t / 2.0), "s": Vector3(L - t, H - 2.0 * t, t)},
			]
			# Techo, con un pasacables junto a la pared frontal (encima de la pantalla).
			var y_t := H / 2.0 - t / 2.0
			var pc: Dictionary = def.get("pasacables", {})
			var pa := clampf(float(pc.get("ancho", 0.0)) / 1000.0, 0.0, W - 4.0 * t)
			var pf := clampf(float(pc.get("fondo", 0.0)) / 1000.0, 0.0, L - 2.0 * t)
			if pa > 0.0 and pf > 0.0:
				var pz := clampf(float(pc.get("z", 0.0)) / 1000.0, -W / 2.0 + t + pa / 2.0, W / 2.0 - t - pa / 2.0)
				var xa := -L / 2.0
				var xb := L / 2.0 - t - pf
				var xc := L / 2.0 - t
				out.append({"c": Vector3((xa + xb) / 2.0, y_t, 0), "s": Vector3(xb - xa, t, W)})
				var z_lo := pz - pa / 2.0
				var z_hi := pz + pa / 2.0
				out.append({"c": Vector3((xb + xc) / 2.0, y_t, (-W / 2.0 + z_lo) / 2.0), "s": Vector3(pf, t, z_lo + W / 2.0)})
				out.append({"c": Vector3((xb + xc) / 2.0, y_t, (z_hi + W / 2.0) / 2.0), "s": Vector3(pf, t, W / 2.0 - z_hi)})
			else:
				out.append({"c": Vector3(-t / 2.0, y_t, 0), "s": Vector3(L - t, t, W)})
			var y_b := -H / 2.0 + t / 2.0
			if nw > 0.0 and nd > 0.0:
				var side := (W - nw) / 2.0
				for sz in [-1.0, 1.0]:
					out.append({"c": Vector3(-t / 2.0, y_b, sz * (nw / 2.0 + side / 2.0)), "s": Vector3(L - t, t, side)})
				var x0 := -L / 2.0 + nd
				var x1 := L / 2.0 - t
				out.append({"c": Vector3((x0 + x1) / 2.0, y_b, 0), "s": Vector3(x1 - x0, t, nw)})
			else:
				out.append({"c": Vector3(-t / 2.0, y_b, 0), "s": Vector3(L - t, t, W)})
			return out
		"soporte_lentes":
			# Placa en XZ (grosor en Y) con dos ranuras horizontales centradas en ±sep/2.
			var X := float(d.get("x", 140.0)) / 1000.0
			var T := float(d.get("y", 3.0)) / 1000.0
			var Z := float(d.get("z", 50.0)) / 1000.0
			var rn: Dictionary = def.get("ranuras", {})
			var sw := float(rn.get("ancho", 56.0)) / 1000.0
			var sh := minf(float(rn.get("alto", 34.0)) / 1000.0, Z * 0.9)
			var sep := float(rn.get("separacion", 64.0)) / 1000.0
			sw = minf(sw, sep * 0.95)
			sep = minf(sep, X - sw - 0.004)
			var band := (Z - sh) / 2.0
			var out := [
				{"c": Vector3(0, 0, Z / 2.0 - band / 2.0), "s": Vector3(X, T, band)},
				{"c": Vector3(0, 0, -Z / 2.0 + band / 2.0), "s": Vector3(X, T, band)},
			]
			var xs := [-X / 2.0, -sep / 2.0 - sw / 2.0, -sep / 2.0 + sw / 2.0, sep / 2.0 - sw / 2.0, sep / 2.0 + sw / 2.0, X / 2.0]
			for k in [0, 2, 4]:
				var w: float = xs[k + 1] - xs[k]
				if w > 1e-5:
					out.append({"c": Vector3((xs[k] + xs[k + 1]) / 2.0, 0, 0), "s": Vector3(w, T, sh)})
			return out
	return []

## Masa (densidad 1) de un conjunto de cajas que no se solapan: volumen, área (suma de
## las caras de cada caja), centroide e inercia respecto al centroide (Steiner).
static func boxes_mass(boxes: Array) -> Dictionary:
	var V := 0.0
	var A := 0.0
	var m1 := Vector3.ZERO
	for b in boxes:
		var sz: Vector3 = b["s"]
		var v := sz.x * sz.y * sz.z
		V += v
		A += 2.0 * (sz.x * sz.y + sz.y * sz.z + sz.x * sz.z)
		m1 += (b["c"] as Vector3) * v
	var c := m1 / V if V > 0.0 else Vector3.ZERO
	var it := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	for b in boxes:
		var sz: Vector3 = b["s"]
		var v := sz.x * sz.y * sz.z
		var r: Vector3 = (b["c"] as Vector3) - c
		it[0] += v * (sz.y * sz.y + sz.z * sz.z) / 12.0 + v * (r.y * r.y + r.z * r.z)
		it[1] += v * (sz.x * sz.x + sz.z * sz.z) / 12.0 + v * (r.x * r.x + r.z * r.z)
		it[2] += v * (sz.x * sz.x + sz.y * sz.y) / 12.0 + v * (r.x * r.x + r.y * r.y)
		it[3] -= v * r.x * r.y
		it[4] -= v * r.x * r.z
		it[5] -= v * r.y * r.z
	return {"volumen": V, "area": A, "centroide": c, "inercia": it}

## Lente: biconvexa simétrica con radio de curvatura R = 2(n − 1)f (lente delgada),
## casquetes de altura h = R − √(R² − r²) y un canto de "borde" mm; la Fresnel es una
## lámina plana de "borde" mm. "t" = grosor en el centro (m).
static func lens_geometry(def: Dictionary) -> Dictionary:
	var d: Dictionary = def.get("dimensiones_mm", {})
	var o: Dictionary = def.get("optica", {})
	var r := maxf(0.001, float(d.get("diametro", 37.0)) / 2000.0)
	var f := maxf(0.001, float(d.get("focal", 45.0)) / 1000.0)
	var n := float(o.get("indice", 1.49))
	var edge := maxf(0.0002, float(d.get("borde", 1.0)) / 1000.0)
	if str(o.get("tipo", "biconvexa")) == "fresnel":
		return {"r": r, "f": f, "R": 0.0, "h": 0.0, "edge": edge, "t": edge, "fresnel": true}
	var R := maxf(2.0 * (n - 1.0) * f, r * 1.0001)
	var h := R - sqrt(R * R - r * r)
	return {"r": r, "f": f, "R": R, "h": h, "edge": edge, "t": edge + 2.0 * h, "fresnel": false}

## Volumen (m³) de una lente: canto cilíndrico + dos casquetes esféricos.
static func lens_volume_m3(def: Dictionary) -> float:
	var lg := lens_geometry(def)
	var r: float = lg["r"]
	var h: float = lg["h"]
	var R: float = lg["R"]
	return PI * r * r * float(lg["edge"]) + 2.0 * PI * h * h * (3.0 * R - h) / 3.0

## Volumen aproximado en m³ (para masa).
static func volume_m3(def: Dictionary) -> float:
	var forma: String = def.get("forma", "caja")
	var d: Dictionary = def.get("dimensiones_mm", {})
	var mm := mass_model(def)
	if not mm.is_empty():
		return float(mm["volumen"])
	match forma:
		"lente":
			return lens_volume_m3(def)
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
		"esfera":
			var rs := float(d.get("radio", 10.0)) / 1000.0
			return 4.0 / 3.0 * PI * rs * rs * rs
		"engranaje":
			var rp := gear_pitch_radius_m(def)
			var w := float(d.get("ancho", 8.0)) / 1000.0
			return PI * rp * rp * w * 0.95
		"placa", "caja", _:
			var v := dims_m(def)
			# Perfiles en T: fracción maciza de la sección (2020 ≈ 0.5 kg/m).
			var fill := float(def.get("relleno", 1.0))
			return v.x * v.y * v.z * fill

## Área de la superficie en m² (para las paredes de una pieza impresa en 3D).
static func area_m2(def: Dictionary) -> float:
	var forma: String = def.get("forma", "caja")
	var d: Dictionary = def.get("dimensiones_mm", {})
	var mm := mass_model(def)
	if not mm.is_empty():
		return float(mm["area"])
	match forma:
		"lente":
			# Casquetes (2πRh cada uno) y canto.
			var lg := lens_geometry(def)
			var r: float = lg["r"]
			if lg["fresnel"]:
				return TAU * r * r + TAU * r * float(lg["t"])
			return 2.0 * TAU * float(lg["R"]) * float(lg["h"]) + TAU * r * float(lg["edge"])
		"cilindro":
			var r := float(d.get("radio", 10.0)) / 1000.0
			var h := float(d.get("altura", 100.0)) / 1000.0
			return TAU * r * r + TAU * r * h
		"tubo":
			var r := float(d.get("radio", 10.0)) / 1000.0
			var h := float(d.get("altura", 100.0)) / 1000.0
			var ri := maxf(0.0, r - float(d.get("espesor", 2.0)) / 1000.0)
			return TAU * (r + ri) * h + TAU * (r * r - ri * ri)
		"esfera":
			var rs := float(d.get("radio", 10.0)) / 1000.0
			return 2.0 * TAU * rs * rs
		"engranaje":
			# Flancos de los dientes: ~1.5 veces el canto de un disco primitivo.
			var rp := gear_pitch_radius_m(def)
			var w := float(d.get("ancho", 8.0)) / 1000.0
			return TAU * rp * rp + TAU * rp * w * 1.5
		_:
			var v := dims_m(def)
			return 2.0 * (v.x * v.y + v.y * v.z + v.x * v.z)

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
