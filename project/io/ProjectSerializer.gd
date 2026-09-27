class_name ProjectSerializer
extends RefCounted
## ProjectSerializer — Guardado/carga de proyectos en JSON legible (.mforge).
##
## Formato de archivo (versión 1):
## {
##   "formato": "mechaforge",
##   "version": 1,
##   "creado": "<ISO8601>",
##   "grid_mm": 10.0,
##   "piezas": [ {uid, def_id, material, pos:[x,y,z], rot:[x,y,z]}, ... ]
## }

const FORMAT_ID := "mechaforge"
const FORMAT_VERSION := 3

## Construye el diccionario del proyecto (piezas, uniones y cables).
static func build_document(parts_root: Node3D, connections: Array = [], wires: Array = []) -> Dictionary:
	var piezas := []
	for child in parts_root.get_children():
		if child is PartInstance:
			piezas.append((child as PartInstance).to_dict())
	var uniones := []
	for c in connections:
		uniones.append((c as Connection).to_dict())
	return {
		"formato": FORMAT_ID,
		"version": FORMAT_VERSION,
		"creado": Time.get_datetime_string_from_system(true),
		"app_version": Config.APP_VERSION,
		"grid_mm": Config.grid_size_mm(),
		"bateria": {"voltaje": Config.battery_voltage, "capacidad_mah": Config.battery_capacity_mah},
		"piezas": piezas,
		"uniones": uniones,
		"cables": wires,
	}

## Reconstruye las uniones de un documento como Array[Connection].
static func parse_connections(doc: Dictionary) -> Array:
	var out := []
	for u in doc.get("uniones", []):
		if typeof(u) == TYPE_DICTIONARY:
			out.append(Connection.from_dict(u))
	return out

## Devuelve los cables del documento (lista de diccionarios).
static func parse_wires(doc: Dictionary) -> Array:
	var out := []
	for w in doc.get("cables", []):
		if typeof(w) == TYPE_DICTIONARY:
			out.append(w)
	return out

## Guarda a disco. Devuelve OK o un código de error de Godot.
static func save(parts_root: Node3D, path: String, connections: Array = [], wires: Array = []) -> int:
	var doc := build_document(parts_root, connections, wires)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(doc, "\t"))
	f.close()
	return OK

## Carga un documento desde disco. Devuelve el Dictionary o {} si falla.
static func load_document(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	if parsed.get("formato", "") != FORMAT_ID:
		push_warning("ProjectSerializer: formato no reconocido en %s" % path)
		return {}
	return parsed

## Reconstruye las piezas de un documento dentro de parts_root.
## Devuelve el número de piezas instanciadas.
static func apply_document(doc: Dictionary, parts_root: Node3D) -> int:
	for child in parts_root.get_children():
		parts_root.remove_child(child)   # fuera del árbol ya, no al final del frame
		child.queue_free()
	if doc.has("grid_mm"):
		Config.set_grid_size_mm(float(doc["grid_mm"]))
	var count := 0
	for p in doc.get("piezas", []):
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var def := PartLibrary.get_def(p.get("def_id", ""))
		if def.is_empty():
			push_warning("Pieza desconocida al cargar: %s" % p.get("def_id", "?"))
			continue
		var inst := PartInstance.new()
		parts_root.add_child(inst)
		inst.setup(def, p.get("uid", ""))
		inst.material_id = p.get("material", def.get("material", "aluminio"))
		# Dimensiones personalizadas guardadas.
		var dm = p.get("dims_mm", null)
		if typeof(dm) == TYPE_DICTIONARY and not dm.is_empty():
			inst.def["dimensiones_mm"] = dm
		inst.rebuild()
		var pos: Array = p.get("pos", [0, 0, 0])
		var rot: Array = p.get("rot", [0, 0, 0])
		inst.position = Vector3(pos[0], pos[1], pos[2])
		inst.rotation = Vector3(rot[0], rot[1], rot[2])
		count += 1
	return count
