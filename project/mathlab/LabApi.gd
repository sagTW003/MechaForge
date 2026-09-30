class_name LabApi
extends RefCounted
## LabApi — Control del Laboratorio matemático desde la API local (OpenClaw).
##
## Lee el estado del módulo abierto y maneja sus controles por nombre: cada
## control creado con LabUI queda marcado con la meta "lab_param" (su etiqueta) y
## se recorre el panel de parámetros en orden, así que funciona con todos los
## módulos sin código específico. Nada de esto toca el proyecto de MechaForge.

const _BBCODE := "\\[/?(color|font_size|b|i|u|s|code|center|right|left|url|img|table|cell|bgcolor|outline_size|outline_color)(=[^\\]]*)?\\]"

static var _bb: RegEx

## Texto del panel de información sin etiquetas BBCode (respeta intervalos como [0, 1]).
static func plain(t: String) -> String:
	if _bb == null:
		_bb = RegEx.create_from_string(_BBCODE)
	return _bb.sub(t, "", true).strip_edges()

static func modules() -> Dictionary:
	var out := []
	for m in MathLab.MODULES:
		out.append({"id": m["id"], "pilar": MathLab.PILLARS[int(m["pilar"])], "nombre": m["nombre"], "descripcion": m["desc"]})
	return {"pilares": MathLab.PILLARS, "modulos": out}

static func state(lab: MathLab) -> Dictionary:
	var m := lab.module
	if m == null:
		return {"abierto": true, "modulo": ""}
	var crit := []
	for p in m.critical_points():
		var q := m.to_math(m.to_local(p["pos"]))
		crit.append({"nombre": str(p["nombre"]), "x": snappedf(q.x, 1e-4), "y": snappedf(q.y, 1e-4), "z": snappedf(q.z, 1e-4)})
	var info := lab.module_info(lab.module_id)
	return {
		"abierto": true,
		"modulo": lab.module_id,
		"nombre": info.get("nombre", ""),
		"pilar": MathLab.PILLARS[lab.pillar],
		"formula": m.formula(),
		"info": plain(m.info()),
		"evoluciona_en_el_tiempo": m.uses_time(),
		"reproduciendo": lab.playing,
		"velocidad": lab.speed,
		"vista": ["perspectiva", "superior", "isometrica"][lab.cam.view_mode],
		"perturbar": m.perturb_hint(),
		"puntos_criticos": crit,
		"parametros": public_params(lab),
	}

## Controles del panel de parámetros: [{id, nombre, seccion, tipo, valor, ...}].
static func params(lab: MathLab) -> Array:
	var out := []
	var ctx := {"seccion": ""}
	_walk(lab.params_box, out, ctx)
	# Nombres únicos: el segundo «Amplitud» pasa a «Amplitud (2)».
	var seen := {}
	for d in out:
		var n: String = d["nombre"]
		seen[n] = int(seen.get(n, 0)) + 1
		if seen[n] > 1:
			d["nombre"] = "%s (%d)" % [n, seen[n]]
	return out

static func _walk(n: Node, out: Array, ctx: Dictionary) -> void:
	for c in n.get_children():
		if c.is_queued_for_deletion():
			continue
		if c is Label and c.has_meta("lab_section"):
			ctx["seccion"] = (c as Label).text
		if c.has_meta("lab_param"):
			var d := _describe(c)
			if not d.is_empty():
				d["id"] = "p%d" % out.size()
				d["nombre"] = str(c.get_meta("lab_param")).strip_edges().trim_suffix(":")
				d["seccion"] = ctx["seccion"]
				out.append(d)
		_walk(c, out, ctx)

static func _describe(c: Node) -> Dictionary:
	if c is HSlider:
		var s := c as HSlider
		return {"tipo": "deslizador", "valor": s.value, "min": s.min_value, "max": s.max_value, "paso": s.step, "_c": c}
	if c is SpinBox:
		var sp := c as SpinBox
		return {"tipo": "numero", "valor": sp.value, "min": sp.min_value, "max": sp.max_value, "paso": sp.step, "_c": c}
	if c is OptionButton:
		var o := c as OptionButton
		var items := []
		for i in range(o.item_count):
			items.append(o.get_item_text(i))
		return {"tipo": "opcion", "valor": o.selected, "texto": o.get_item_text(o.selected) if o.selected >= 0 else "", "opciones": items, "_c": c}
	if c is CheckBox:
		return {"tipo": "casilla", "valor": (c as CheckBox).button_pressed, "_c": c}
	if c is LineEdit and str(c.get_meta("lab_kind", "")) == "texto":
		return {"tipo": "texto", "valor": (c as LineEdit).text, "_c": c}
	if c is LineEdit:
		return {"tipo": "expresion", "valor": (c as LineEdit).text, "variables": c.get_meta("lab_vars", []), "compleja": c.get_meta("lab_complex", false), "_c": c}
	if c is Button:
		return {"tipo": "boton", "_c": c}
	return {}

## Quita las referencias internas a los controles antes de devolver JSON.
static func public_params(lab: MathLab) -> Array:
	var out := []
	for d in params(lab):
		var e: Dictionary = d.duplicate()
		e.erase("_c")
		out.append(e)
	return out

## Símbolos decorativos de los botones que no hace falta escribir («🚀 Lanzar paquete» = «lanzar paquete»).
const _DECOR := ["▶", "⏩", "🚀", "⟲", "✋", "🎯"]

static func _norm(t: String) -> String:
	var s := t.strip_edges().to_lower().trim_suffix(":")
	for c in _DECOR:
		s = s.replace(c, "")
	return s.strip_edges()

## Busca por id (p3), nombre exacto, «Sección/Nombre» o prefijo del nombre.
static func _find(lab: MathLab, key: String) -> Dictionary:
	var k := _norm(key)
	if k == "":
		return {}
	var ps := params(lab)
	for d in ps:
		if str(d["id"]) == k:
			return d
	for d in ps:
		if _norm(d["nombre"]) == k or _norm("%s/%s" % [d["seccion"], d["nombre"]]) == k:
			return d
	for d in ps:
		var n := _norm(d["nombre"])
		if n != "" and n.begins_with(k):
			return d
	return {}

## Cambia un control como si lo hiciera el usuario (dispara su señal).
static func set_param(lab: MathLab, key: String, value) -> Dictionary:
	var d := _find(lab, key)
	if d.is_empty():
		var names := []
		for q in params(lab):
			names.append("%s (%s)" % [q["nombre"], q["id"]])
		return {"error": "parámetro «%s» no encontrado; disponibles: %s" % [key, ", ".join(names)]}
	var c: Node = d["_c"]
	var shown = null
	match str(d["tipo"]):
		"deslizador", "numero":
			if not (typeof(value) in [TYPE_INT, TYPE_FLOAT]) and not str(value).is_valid_float():
				return {"error": "«%s» espera un número entre %s y %s" % [d["nombre"], d["min"], d["max"]]}
			var r := c as Range
			r.value = clampf(float(value), r.min_value, r.max_value)
			shown = r.value
		"opcion":
			var o := c as OptionButton
			var idx := -1
			if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
				idx = int(value)
			else:
				var v := str(value).strip_edges().to_lower()
				for i in range(o.item_count):
					if o.get_item_text(i).to_lower() == v:
						idx = i
				if idx < 0:
					for i in range(o.item_count):
						if o.get_item_text(i).to_lower().contains(v):
							idx = i
							break
			if idx < 0 or idx >= o.item_count:
				return {"error": "opción no válida para «%s»; opciones: %s" % [d["nombre"], ", ".join(d["opciones"])]}
			o.select(idx)
			o.item_selected.emit(idx)
			shown = o.get_item_text(idx)
		"casilla":
			var on := bool(value) if typeof(value) == TYPE_BOOL else str(value).to_lower() in ["1", "true", "si", "sí", "on"]
			(c as CheckBox).button_pressed = on
			shown = on
		"expresion":
			var e := c as LineEdit
			var t := str(value) if value != null else ""
			if t.strip_edges() == "" and e.get_meta("lab_optional", false):
				e.text = ""
				e.text_submitted.emit("")
				shown = "(vacío)"
			else:
				var m := MathExpr.parse(t, e.get_meta("lab_vars", []), e.get_meta("lab_complex", false))
				if not m.ok():
					return {"error": "expresión no válida: %s" % m.error}
				e.text = t
				e.text_submitted.emit(t)
				shown = t
		"texto":
			var te := c as LineEdit
			te.text = str(value) if value != null else ""
			te.text_submitted.emit(te.text)
			shown = te.text
		"boton":
			(c as Button).pressed.emit()
			shown = "pulsado"
	lab.notify_ai("%s → %s" % [d["nombre"], str(shown)])
	return {"ok": true, "parametro": d["nombre"], "valor": shown}

static func control(lab: MathLab, action: String, value = null) -> Dictionary:
	match action:
		"pausar":
			if lab.playing: lab.toggle_play()
		"reanudar":
			if not lab.playing: lab.toggle_play()
		"reiniciar":
			lab.reset_module()
		"encuadrar":
			lab.frame_next()
		"vista_perspectiva":
			lab.set_view(LabCamera.ViewMode.PERSPECTIVA)
		"vista_superior":
			lab.set_view(LabCamera.ViewMode.SUPERIOR)
		"vista_isometrica":
			lab.set_view(LabCamera.ViewMode.ISOMETRICA)
		"velocidad":
			var speeds := [0.25, 0.5, 1.0, 2.0, 4.0, 8.0]
			var want := float(value) if value != null else 1.0
			var best := 1.0
			for s in speeds:
				if absf(s - want) < absf(best - want):
					best = s
			lab.set_speed(best)
		_:
			return {"error": "acción desconocida: %s (pausar, reanudar, reiniciar, encuadrar, vista_perspectiva, vista_superior, vista_isometrica, velocidad)" % action}
	lab.notify_ai(action.replace("_", " "))
	return {"ok": true, "accion": action, "reproduciendo": lab.playing, "velocidad": lab.speed}

## Puntos de la escena bajo las coordenadas (x, y) del tooltip del módulo:
## rayo vertical (superficies) y, si no acierta, rayo frontal (gráficas en plano vertical).
static func _hits(lab: MathLab, x: float, y: float) -> Array:
	var m := lab.module
	var out := []
	if m == null:
		return out
	for w in m.api_points(x, y):
		var hit = m.pick(w + Vector3(0, 20, 0), Vector3.DOWN)
		if hit == null:
			hit = m.pick(w + Vector3(0, 0, 20), Vector3.FORWARD)
		if hit != null:
			out.append(hit)
	return out

## Valor en un punto (el mismo texto que el tooltip flotante). Solo lectura.
static func sample(lab: MathLab, x: float, y: float) -> Dictionary:
	var hits := _hits(lab, x, y)
	if hits.is_empty():
		return {"error": "(%s, %s) está fuera de la superficie visible del módulo «%s»" % [x, y, lab.module_id]}
	var m := lab.module
	# El tooltip de Mandelbrot puede mover la c de Julia («seguir al cursor»): aquí no.
	var follow = m.get("follow")
	if follow != null:
		m.set("follow", false)
	var texts := []
	for h in hits:
		var t := m.hover_text(h)
		if t != "":
			texts.append(t)
	if follow != null:
		m.set("follow", follow)
	return {"x": x, "y": y, "lectura": "\n—\n".join(texts) if not texts.is_empty() else "(sin lectura en este módulo)"}

## Equivale a un clic con la herramienta «Perturbar» en (x, y).
static func perturb(lab: MathLab, x: float, y: float) -> Dictionary:
	var hits := _hits(lab, x, y)
	if hits.is_empty():
		return {"error": "(%s, %s) está fuera de la superficie visible del módulo «%s»" % [x, y, lab.module_id]}
	var hit: Vector3 = hits[0]
	lab.module.perturb(hit, true)
	lab.notify_ai("perturbación en (%.2f, %.2f)" % [x, y])
	return {"ok": true, "x": x, "y": y, "efecto": lab.module.perturb_hint()}

## Captura de la ventana del laboratorio en user:// (para agentes con visión).
static func capture(lab: MathLab) -> Dictionary:
	if DisplayServer.get_name() == "headless":
		return {"error": "sin ventana (modo headless): no hay imagen que capturar"}
	var tex := lab.get_viewport().get_texture()
	var img: Image = tex.get_image() if tex else null
	if img == null or img.is_empty():
		return {"error": "no se pudo leer la imagen de la ventana"}
	var path := "user://lab_captura.png"
	if img.save_png(path) != OK:
		return {"error": "no se pudo guardar la captura"}
	return {"ok": true, "archivo": ProjectSettings.globalize_path(path), "ancho": img.get_width(), "alto": img.get_height()}
