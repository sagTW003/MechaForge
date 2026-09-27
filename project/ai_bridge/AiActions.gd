class_name AiActions
extends RefCounted
## AiActions — Extrae acciones estructuradas (JSON) de la respuesta de OpenClaw.
##
## La IA puede proponer construcciones devolviendo un bloque JSON:
##   {"acciones":[ {"tipo":"add_part","def_id":"perfil_2020_200",
##                  "material":"aluminio","pos":[0,0.1,0],"rot_y_deg":0}, ... ]}
## Este parser es tolerante: busca el bloque en texto cercado o en el cuerpo.

static func parse(text: String) -> Array:
	for c in _candidates(text):
		var d = JSON.parse_string(c)
		if typeof(d) == TYPE_DICTIONARY and d.has("acciones") and typeof(d["acciones"]) == TYPE_ARRAY:
			return d["acciones"]
	return []

static func _candidates(text: String) -> Array:
	var out := []
	var fenced := _extract_fenced(text)
	if fenced != "":
		out.append(fenced)
	var i := text.find("{")
	var j := text.rfind("}")
	if i >= 0 and j > i:
		out.append(text.substr(i, j - i + 1))
	out.append(text)
	return out

static func _extract_fenced(text: String) -> String:
	var start := text.find("```")
	if start < 0:
		return ""
	var nl := text.find("\n", start)
	if nl < 0:
		return ""
	var end := text.find("```", nl)
	if end < 0:
		return ""
	return text.substr(nl + 1, end - nl - 1).strip_edges()
