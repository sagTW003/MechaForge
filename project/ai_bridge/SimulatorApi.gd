class_name SimulatorApi
extends RefCounted
## SimulatorApi — Herramientas que OpenClaw puede usar sobre el simulador.
##
## Lectura (se ejecutan al momento):
##   get_scene_state, get_telemetry, analyze_design, list_parts, get_proposal_status
## Control de la simulación (reversible, se ejecuta al momento):
##   run_simulation, stop_simulation
## Cambios en la escena (requieren confirmación del usuario — vista previa fantasma):
##   add_part, connect_parts, set_property, remove_part, write_controller_script
##
## "host" es el controlador principal (ui/Main.gd); aquí solo se valida y traduce.

const TOOLS := [
	{"name": "get_scene_state", "description": "Piezas (uid, tipo, material, posición, rotación, masa), uniones, cables y estado de la simulación.",
		"input_schema": {"type": "object", "properties": {}}},
	{"name": "list_parts", "description": "Catálogo de piezas disponibles (def_id, nombre, categoría, dimensiones) y materiales.",
		"input_schema": {"type": "object", "properties": {"categoria": {"type": "string"}}}},
	{"name": "get_telemetry", "description": "Telemetría en vivo (posición, velocidad, velocidad angular, masa) de una pieza o de todas, más consumo eléctrico y medidas de control.",
		"input_schema": {"type": "object", "properties": {"uid": {"type": "string"}}}},
	{"name": "analyze_design", "description": "Análisis: masa total, centro de masa, estabilidad/vuelco, esfuerzo estimado por pieza, consumo y autonomía.",
		"input_schema": {"type": "object", "properties": {}}},
	{"name": "add_part", "description": "Propone añadir una pieza (vista previa; el usuario confirma). Posición en metros; el suelo es y=0.",
		"input_schema": {"type": "object", "required": ["def_id", "pos"], "properties": {
			"def_id": {"type": "string"}, "material": {"type": "string"},
			"pos": {"type": "array", "items": {"type": "number"}, "minItems": 3, "maxItems": 3},
			"rot_deg": {"type": "array", "items": {"type": "number"}, "minItems": 3, "maxItems": 3}}}},
	{"name": "connect_parts", "description": "Propone una unión entre dos piezas: fija, bisagra, deslizadera, rotula o engranaje; opcionalmente con motor.",
		"input_schema": {"type": "object", "required": ["a", "b", "union"], "properties": {
			"a": {"type": "string"}, "b": {"type": "string"},
			"union": {"type": "string", "enum": ["fija", "bisagra", "deslizadera", "rotula", "engranaje"]},
			"eje": {"type": "string", "enum": ["X", "Y", "Z"]}, "motor": {"type": "boolean"},
			"velocidad": {"type": "number"}, "torque": {"type": "number"},
			"z1": {"type": "integer"}, "z2": {"type": "integer"}}}},
	{"name": "set_property", "description": "Propone cambiar material, dimensiones (mm) o posición de una pieza.",
		"input_schema": {"type": "object", "required": ["uid"], "properties": {
			"uid": {"type": "string"}, "material": {"type": "string"},
			"dims_mm": {"type": "object"}, "pos": {"type": "array", "items": {"type": "number"}}}}},
	{"name": "remove_part", "description": "Propone eliminar una pieza.",
		"input_schema": {"type": "object", "required": ["uid"], "properties": {"uid": {"type": "string"}}}},
	{"name": "write_controller_script", "description": "Propone el programa del microcontrolador (líneas 'variable = expresión'; la última es la consigna). Variables: t, x, dt y sensores.",
		"input_schema": {"type": "object", "required": ["script"], "properties": {"script": {"type": "string"}}}},
	{"name": "run_simulation", "description": "Inicia la simulación física.", "input_schema": {"type": "object", "properties": {}}},
	{"name": "stop_simulation", "description": "Detiene la simulación y restaura el estado inicial.", "input_schema": {"type": "object", "properties": {}}},
	{"name": "get_proposal_status", "description": "Estado de una propuesta: pending, applied o discarded.",
		"input_schema": {"type": "object", "required": ["id"], "properties": {"id": {"type": "integer"}}}},
]

static var TOOL_NAMES: Array = TOOLS.map(func(t): return t["name"])

var host: Node

func _init(h: Node) -> void:
	host = h

func call_tool(name: String, p: Dictionary) -> Dictionary:
	match name:
		"get_scene_state": return host.api_scene_state()
		"list_parts": return _list_parts(str(p.get("categoria", "")))
		"get_telemetry": return host.api_telemetry(str(p.get("uid", "")))
		"analyze_design": return host.api_analyze()
		"run_simulation": return host.api_run(true)
		"stop_simulation": return host.api_run(false)
		"get_proposal_status": return host.api_proposal_status(int(p.get("id", -1)))
		"add_part": return _add_part(p)
		"connect_parts": return _connect(p)
		"set_property": return _set_property(p)
		"remove_part": return _remove(p)
		"write_controller_script": return _script(p)
	return {"error": "herramienta desconocida: %s" % name}

func _list_parts(cat: String) -> Dictionary:
	var parts := []
	for id in PartLibrary.all_ids():
		var d := PartLibrary.get_def(id)
		if cat != "" and d.get("categoria", "") != cat:
			continue
		parts.append({"def_id": id, "nombre": d.get("nombre", id), "categoria": d.get("categoria", ""),
			"dimensiones_mm": d.get("dimensiones_mm", {}), "material": d.get("material", "")})
	return {"piezas": parts, "materiales": MaterialLibrary.ids()}

static func _vec3(v, fallback = Vector3.ZERO) -> Variant:
	if typeof(v) != TYPE_ARRAY or v.size() < 3:
		return fallback
	return Vector3(float(v[0]), float(v[1]), float(v[2]))

func _add_part(p: Dictionary) -> Dictionary:
	var def_id := str(p.get("def_id", ""))
	if not PartLibrary.has_part(def_id):
		return {"error": "def_id inexistente: %s (usa list_parts)" % def_id}
	var mat := str(p.get("material", PartLibrary.get_def(def_id).get("material", "aluminio")))
	if not MaterialLibrary.has_material(mat):
		return {"error": "material inexistente: %s" % mat}
	var pos = _vec3(p.get("pos"), null)
	if pos == null:
		return {"error": "pos debe ser [x, y, z] en metros"}
	var rot: Vector3 = _vec3(p.get("rot_deg"), Vector3.ZERO)
	return host.api_propose([{"tipo": "add_part", "def_id": def_id, "material": mat,
		"pos": [pos.x, pos.y, pos.z], "rot_deg": [rot.x, rot.y, rot.z]}])

func _connect(p: Dictionary) -> Dictionary:
	for k in ["a", "b"]:
		if host._find_part(str(p.get(k, ""))) == null:
			return {"error": "pieza '%s' no encontrada" % str(p.get(k, ""))}
	var union := str(p.get("union", "fija")).to_lower()
	if not union in ["fija", "bisagra", "deslizadera", "rotula", "engranaje"]:
		return {"error": "union no válida: %s" % union}
	var a := p.duplicate()
	a["tipo"] = "connect"
	return host.api_propose([a])

func _set_property(p: Dictionary) -> Dictionary:
	if host._find_part(str(p.get("uid", ""))) == null:
		return {"error": "pieza no encontrada"}
	if p.has("material") and not MaterialLibrary.has_material(str(p["material"])):
		return {"error": "material inexistente"}
	var a := p.duplicate()
	a["tipo"] = "set_property"
	return host.api_propose([a])

func _remove(p: Dictionary) -> Dictionary:
	if host._find_part(str(p.get("uid", ""))) == null:
		return {"error": "pieza no encontrada"}
	return host.api_propose([{"tipo": "remove", "uid": str(p["uid"])}])

func _script(p: Dictionary) -> Dictionary:
	var s := str(p.get("script", ""))
	if s.strip_edges() == "":
		return {"error": "script vacío"}
	if is_nan(host._mcu_run(s.split("\n"), 0.0, 0.0, 1.0 / 120.0)):
		return {"error": "el script no es válido (usa 'variable = expresión')"}
	return host.api_propose([{"tipo": "script", "script": s}])
