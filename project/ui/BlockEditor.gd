class_name BlockEditor
extends VBoxContainer
## BlockEditor — Programación del microcontrolador con BLOQUES visuales.
##
## Estilo Scratch: una pila de bloques de colores que se ejecuta de arriba abajo
## cada ciclo. Cada bloque tiene campos editables y botones ↑ ↓ ✖. La pila se
## compila al lenguaje de script del microcontrolador ("variable = expresión"),
## así ambos modos (bloques y script) producen el mismo programa.
##
## Bloques:
##   Fijar variable      nombre = expresión
##   Si / si no          nombre = (A) if (condición) else (B)
##   Onda senoidal       nombre = amplitud · sin(2π · f · t)
##   Escalón en t        nombre = valor si t ≥ t0, si no 0
##   Seguir sensor (P)   nombre = Kp · (referencia − sensor)
##   Limitar             nombre = clamp(nombre, mín, máx)
##   Motor n             mN = expresión   (consigna de la n-ésima unión con control)
##   Salida              consigna de la unión elegida (última línea)

signal changed

const KINDS := {
	"fijar": {"titulo": "Fijar", "color": Color(0.95, 0.6, 0.1), "campos": [["var", "v"], ["=", ""], ["expr", "0"]]},
	"si": {"titulo": "Si", "color": Color(0.3, 0.55, 0.95), "campos": [["var", "v"], ["= si", ""], ["cond", "x < 10"], ["entonces", ""], ["a", "1"], ["si no", ""], ["b", "0"]]},
	"onda": {"titulo": "Onda", "color": Color(0.6, 0.4, 0.9), "campos": [["var", "v"], ["= amplitud", ""], ["amp", "30"], ["· sin(2π·f·t), f (Hz)", ""], ["f", "0.5"]]},
	"escalon": {"titulo": "Escalón", "color": Color(0.6, 0.4, 0.9), "campos": [["var", "v"], ["= valor", ""], ["val", "45"], ["desde t ≥", ""], ["t0", "1"]]},
	"seguir": {"titulo": "Seguir sensor", "color": Color(0.2, 0.7, 0.45), "campos": [["var", "v"], ["= Kp", ""], ["kp", "2"], ["· (ref", ""], ["ref", "0.2"], ["− sensor", ""], ["sensor", "dist1"], [")", ""]]},
	"limitar": {"titulo": "Limitar", "color": Color(0.85, 0.35, 0.35), "campos": [["var", "v"], ["entre", ""], ["min", "-90"], ["y", ""], ["max", "90"]]},
	"motor": {"titulo": "Motor", "color": Color(0.9, 0.3, 0.6), "campos": [["n", "1"], ["consigna =", ""], ["expr", "v"]]},
	"salida": {"titulo": "Salida", "color": Color(0.35, 0.35, 0.4), "campos": [["consigna =", ""], ["expr", "v"]]},
}

var blocks: Array = []           # [{kind, vals: {campo: texto}}]
var variables: Array = []        # nombres sugeridos (t, x, sensores...)
var _stack: VBoxContainer

func _init() -> void:
	add_theme_constant_override("separation", 4)
	var pal := HFlowContainer.new()
	for k in KINDS:
		var b := Button.new()
		b.text = "+ " + KINDS[k]["titulo"]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_color_override("font_color", (KINDS[k]["color"] as Color).lightened(0.3))
		b.pressed.connect(add_block.bind(k))
		pal.add_child(b)
	add_child(pal)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(320, 150)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stack = VBoxContainer.new()
	_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_stack)
	add_child(sc)
	# Programa de ejemplo: onda senoidal hacia la consigna.
	blocks = [
		{"kind": "onda", "vals": {"var": "ang", "amp": "40", "f": "0.3"}},
		{"kind": "limitar", "vals": {"var": "ang", "min": "-90", "max": "90"}},
		{"kind": "salida", "vals": {"expr": "ang"}},
	]
	_rebuild()

func add_block(kind: String) -> void:
	var vals := {}
	for c in KINDS[kind]["campos"]:
		if c[1] != "" or c[0] in ["var", "expr", "cond", "a", "b", "amp", "f", "val", "t0", "kp", "ref", "sensor", "min", "max", "n"]:
			vals[c[0]] = c[1]
	blocks.append({"kind": kind, "vals": vals})
	_rebuild()
	changed.emit()

func _move(i: int, d: int) -> void:
	var j := i + d
	if j < 0 or j >= blocks.size():
		return
	var t = blocks[i]; blocks[i] = blocks[j]; blocks[j] = t
	_rebuild()
	changed.emit()

func _remove(i: int) -> void:
	blocks.remove_at(i)
	_rebuild()
	changed.emit()

func _rebuild() -> void:
	for c in _stack.get_children():
		c.queue_free()
	for i in range(blocks.size()):
		_stack.add_child(_block_ui(i))

func _block_ui(i: int) -> Control:
	var blk: Dictionary = blocks[i]
	var spec: Dictionary = KINDS[blk["kind"]]
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = (spec["color"] as Color).darkened(0.35)
	sb.border_color = spec["color"]
	sb.border_width_left = 5
	sb.set_corner_radius_all(5)
	sb.set_content_margin_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	var row := HFlowContainer.new()
	panel.add_child(row)
	var title := Label.new()
	title.text = spec["titulo"]
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	row.add_child(title)
	for c in spec["campos"]:
		var key: String = c[0]
		if blk["vals"].has(key):
			var le := LineEdit.new()
			le.text = str(blk["vals"][key])
			le.custom_minimum_size = Vector2(46 if key in ["n", "f", "t0", "kp", "min", "max", "amp", "val", "ref"] else 78, 0)
			le.expand_to_text_length = true
			le.tooltip_text = "Variables: " + ", ".join(variables)
			le.text_changed.connect(func(tx): blk["vals"][key] = tx; changed.emit())
			row.add_child(le)
		else:
			var l := Label.new()
			l.text = key
			l.add_theme_color_override("font_color", Color(0.92, 0.92, 0.95))
			row.add_child(l)
	for pair in [["↑", -1], ["↓", 1]]:
		var b := Button.new()
		b.text = pair[0]
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_move.bind(i, pair[1]))
		row.add_child(b)
	var x := Button.new()
	x.text = "✖"
	x.flat = true
	x.focus_mode = Control.FOCUS_NONE
	x.pressed.connect(_remove.bind(i))
	row.add_child(x)
	return panel

## Compila la pila de bloques al script del microcontrolador.
func to_script() -> String:
	var lines := ["# Generado por el editor de bloques."]
	var out_expr := ""
	for blk in blocks:
		var v: Dictionary = blk["vals"]
		var name := str(v.get("var", "v")).strip_edges()
		match blk["kind"]:
			"fijar": lines.append("%s = %s" % [name, v.get("expr", "0")])
			"si": lines.append("%s = (%s) if (%s) else (%s)" % [name, v.get("a", "1"), v.get("cond", "true"), v.get("b", "0")])
			"onda": lines.append("%s = (%s) * sin(2 * pi * (%s) * t)" % [name, v.get("amp", "1"), v.get("f", "1")])
			"escalon": lines.append("%s = (%s) if t >= (%s) else 0" % [name, v.get("val", "1"), v.get("t0", "0")])
			"seguir": lines.append("%s = (%s) * ((%s) - (%s))" % [name, v.get("kp", "1"), v.get("ref", "0"), v.get("sensor", "0")])
			"limitar": lines.append("%s = clamp(%s, %s, %s)" % [name, name, v.get("min", "-1"), v.get("max", "1")])
			"motor": lines.append("m%d = %s" % [int(str(v.get("n", "1"))), v.get("expr", "0")])
			"salida": out_expr = str(v.get("expr", "0"))
	if out_expr != "":
		lines.append("output = %s" % out_expr)
	return "\n".join(lines)

func set_variables(names: Array) -> void:
	variables = names
