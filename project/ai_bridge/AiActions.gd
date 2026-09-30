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
		# JSON.new().parse devuelve el error en lugar de escribirlo en la consola: una
		# respuesta en prosa (lo normal) no deja «ERROR: Parse JSON failed» en el registro.
		var s := str(c).strip_edges()
		if not (s.begins_with("{") or s.begins_with("[")):
			continue
		var j := JSON.new()
		if j.parse(s) != OK:
			continue
		var d = j.data
		if typeof(d) == TYPE_DICTIONARY and d.has("acciones") and typeof(d["acciones"]) == TYPE_ARRAY:
			return d["acciones"]
	return []

## El texto de la respuesta sin el bloque de acciones (para mostrarlo en el chat).
static func strip_block(text: String) -> String:
	var start := text.find("```")
	if start >= 0:
		var end := text.find("```", text.find("\n", start) + 1)
		if end > start:
			var out := (text.substr(0, start).strip_edges() + "\n" + text.substr(end + 3).strip_edges()).strip_edges()
			return out + ("\n" if out != "" else "") + "[acciones propuestas abajo]"
	return text

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
