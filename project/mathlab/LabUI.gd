class_name LabUI
extends RefCounted
## LabUI — Controles de parámetros del Laboratorio (estilo "Leva"): deslizadores
## con etiqueta y valor, desplegables, casillas, campos de expresión con
## validación en vivo y botones. Todos devuelven el control creado y lo marcan
## con la meta "lab_param" (su etiqueta) para que LabApi pueda manejarlo.

## Notación científica legible: 1.11e-4 → "1.11×10⁻⁴" (GDScript no admite %e).
static func sci(v: float, digits: int = 2) -> String:
	if v == 0.0 or is_nan(v) or is_inf(v):
		return str(v)
	var e := int(floor(log(absf(v)) / log(10.0)))
	var m := v / pow(10.0, e)
	if e == 0:
		return ("%." + str(digits) + "f") % v
	var sup := {"-": "⁻", "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹"}
	var es := ""
	for ch in str(e):
		es += sup.get(ch, ch)
	return ("%." + str(digits) + "f×10%s") % [m, es]

static func section(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.35, 0.85, 1.0))
	l.add_theme_font_size_override("font_size", 15)
	l.set_meta("lab_section", true)
	parent.add_child(l)
	return l

static func note(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(250, 0)
	l.add_theme_color_override("font_color", Color(0.62, 0.66, 0.72))
	l.add_theme_font_size_override("font_size", 12)
	parent.add_child(l)
	return l

## Deslizador con etiqueta y valor. cb(valor).
static func slider(parent: Control, label: String, lo: float, hi: float, step: float, value: float, cb: Callable, fmt: String = "%.2f") -> HSlider:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	var top := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 13)
	top.add_child(l)
	var v := Label.new()
	v.text = fmt % value
	v.add_theme_color_override("font_color", Color(0.96, 0.75, 0.3))
	v.add_theme_font_size_override("font_size", 13)
	top.add_child(v)
	row.add_child(top)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.focus_mode = Control.FOCUS_NONE
	s.custom_minimum_size = Vector2(240, 16)
	s.set_meta("lab_param", label)
	s.value_changed.connect(func(x):
		v.text = fmt % x
		cb.call(x))
	row.add_child(s)
	parent.add_child(row)
	return s

static func option(parent: Control, label: String, items: Array, selected: int, cb: Callable) -> OptionButton:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 13)
	row.add_child(l)
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# El ancho no lo marca la opción más larga (listas de métodos con nombres largos).
	o.fit_to_longest_item = false
	o.clip_text = true
	o.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	o.custom_minimum_size = Vector2(120, 0)
	for it in items:
		o.add_item(str(it))
	o.select(clampi(selected, 0, items.size() - 1))
	o.set_meta("lab_param", label)
	o.item_selected.connect(func(i): cb.call(i))
	row.add_child(o)
	parent.add_child(row)
	return o

static func check(parent: Control, label: String, value: bool, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = label
	c.button_pressed = value
	c.focus_mode = Control.FOCUS_NONE
	c.set_meta("lab_param", label)
	c.toggled.connect(func(v): cb.call(v))
	parent.add_child(c)
	return c

static func button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.set_meta("lab_param", text)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

static func row(parent: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	parent.add_child(h)
	return h

## Teclas del teclado de símbolos: [etiqueta, texto que se inserta, retroceso del cursor].
const KEYS := [["x²", "^2", 0], ["xⁿ", "^", 0], ["√", "√()", 1], ["∛", "∛()", 1], ["eˣ", "e^()", 1], ["ln", "ln()", 1],
	["log₁₀", "log10()", 1], ["|x|", "||", 1], ["π", "π", 0], ["( )", "()", 1], ["sin", "sin()", 1], ["cos", "cos()", 1],
	["tan", "tan()", 1], ["asin", "asin()", 1], ["atan", "atan()", 1], ["sinh", "sinh()", 1], ["·", "·", 0], ["÷", "/", 0]]
const SYNTAX_HELP := "Se escribe como en papel: 2x, 3(x+1), sin x, sen 2x, x², e^-x, √x, ln|x|, sin^2 x, arcsen x, log_2 x, π, 0,5. Los paréntesis que falten al final se cierran solos. Debajo se ve cómo se ha entendido."

## Campo de expresión con notación cómoda: mientras se escribe muestra la fórmula
## en notación matemática (o el error), los avisos de la lectura y, con ⌨, un
## teclado de símbolos. Al confirmar (Intro o al salir del campo) llama cb(expr).
static func expr_field(parent: Control, label: String, text: String, vars: Array, complex: bool, cb: Callable) -> LineEdit:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	var head := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 13)
	head.add_child(l)
	var kb_btn := Button.new()
	kb_btn.text = "⌨"
	kb_btn.flat = true
	kb_btn.toggle_mode = true
	kb_btn.focus_mode = Control.FOCUS_NONE
	kb_btn.tooltip_text = "Teclado de símbolos.\n" + SYNTAX_HELP
	head.add_child(kb_btn)
	box.add_child(head)
	var e := LineEdit.new()
	e.text = text
	e.custom_minimum_size = Vector2(250, 0)
	e.add_theme_font_size_override("font_size", 14)
	e.placeholder_text = "p. ej. sin x + x²"
	e.tooltip_text = SYNTAX_HELP
	e.set_meta("lab_param", label)
	e.set_meta("lab_vars", vars)
	e.set_meta("lab_complex", complex)
	box.add_child(e)
	var kb := GridContainer.new()
	kb.columns = 9
	kb.visible = false
	kb.add_theme_constant_override("h_separation", 2)
	kb.add_theme_constant_override("v_separation", 2)
	box.add_child(kb)
	var err := Label.new()
	err.add_theme_font_size_override("font_size", 12)
	err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	err.custom_minimum_size = Vector2(250, 0)
	box.add_child(err)
	var show := func(t: String, final: bool) -> MathExpr:
		var m := MathExpr.parse(t, vars, complex)
		if m.ok():
			var txt := "= " + m.to_pretty()
			if not m.notes.is_empty():
				txt += "\n" + " ".join(PackedStringArray(m.notes))
			err.text = txt
			err.add_theme_color_override("font_color", Color(0.55, 0.95, 0.65))
		else:
			err.text = "✖ " + m.error
			err.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35) if final else Color(1.0, 0.72, 0.35))
		return m
	var apply := func(t: String):
		var m: MathExpr = show.call(t, true)
		if m.ok():
			cb.call(m)
	var keys: Array = KEYS.duplicate()
	for v in vars:
		keys.append([str(v), str(v), 0])
	if complex:
		keys.append(["i", "i", 0])
	for k in keys:
		var b := Button.new()
		b.text = str(k[0])
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(28, 22)
		b.add_theme_font_size_override("font_size", 12)
		var ins: String = k[1]
		var back: int = k[2]
		b.pressed.connect(func():
			e.insert_text_at_caret(ins)
			e.caret_column = maxi(0, e.caret_column - back)
			show.call(e.text, false))
		kb.add_child(b)
	e.text_changed.connect(func(t): show.call(t, false))
	e.text_submitted.connect(func(t): apply.call(t))
	e.focus_exited.connect(func(): apply.call(e.text))
	kb_btn.toggled.connect(func(on): kb.visible = on)
	show.call(text, true)
	parent.add_child(box)
	return e

## Campo para un número escrito como expresión constante (pi/2, 2e-3, -inf, ∞…).
## cb(valor, texto) al confirmar.
static func value_field(parent: Control, label: String, text: String, cb: Callable) -> LineEdit:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 13)
	row.add_child(l)
	var e := LineEdit.new()
	e.text = text
	e.custom_minimum_size = Vector2(70, 0)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.add_theme_font_size_override("font_size", 13)
	e.tooltip_text = "Un número o una expresión: pi/2, 2e-3, √2, inf, -inf, ∞"
	e.set_meta("lab_param", label)
	e.set_meta("lab_vars", [])
	e.set_meta("lab_complex", false)
	row.add_child(e)
	var val := Label.new()
	val.add_theme_font_size_override("font_size", 11)
	val.custom_minimum_size = Vector2(56, 0)
	row.add_child(val)
	var read := func(t: String) -> float:
		var m := MathExpr.parse(t, [])
		var v := m.eval_real({}) if m.ok() else NAN
		if is_nan(v):
			val.text = "✖"
			val.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
		else:
			val.text = "= " + (MathExpr._num_text(v) if absf(v) >= 1e6 or v == floor(v) or is_inf(v) else "%.4f" % v)
			val.add_theme_color_override("font_color", Color(0.62, 0.7, 0.78))
		return v
	var apply := func(t: String):
		var v: float = read.call(t)
		if not is_nan(v):
			cb.call(v, t)
	e.text_changed.connect(func(t): read.call(t))
	e.text_submitted.connect(func(t): apply.call(t))
	e.focus_exited.connect(func(): apply.call(e.text))
	read.call(text)
	parent.add_child(row)
	return e

static func spin(parent: Control, label: String, lo: float, hi: float, step: float, value: float, cb: Callable) -> SpinBox:
	var r := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 13)
	r.add_child(l)
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(70, 0)
	s.set_meta("lab_param", label)
	s.value_changed.connect(func(v): cb.call(v))
	r.add_child(s)
	parent.add_child(r)
	return s
