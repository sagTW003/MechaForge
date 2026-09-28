class_name LabUI
extends RefCounted
## LabUI — Controles de parámetros del Laboratorio (estilo "Leva"): deslizadores
## con etiqueta y valor, desplegables, casillas, campos de expresión con
## validación en vivo y botones. Todos devuelven el control creado.

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
	for it in items:
		o.add_item(str(it))
	o.select(clampi(selected, 0, items.size() - 1))
	o.item_selected.connect(func(i): cb.call(i))
	row.add_child(o)
	parent.add_child(row)
	return o

static func check(parent: Control, label: String, value: bool, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = label
	c.button_pressed = value
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(func(v): cb.call(v))
	parent.add_child(c)
	return c

static func button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

static func row(parent: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	parent.add_child(h)
	return h

## Campo de expresión: valida en vivo con MathExpr y llama cb(expr) si es válida.
static func expr_field(parent: Control, label: String, text: String, vars: Array, complex: bool, cb: Callable) -> LineEdit:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 13)
	box.add_child(l)
	var e := LineEdit.new()
	e.text = text
	e.custom_minimum_size = Vector2(250, 0)
	e.add_theme_font_size_override("font_size", 14)
	box.add_child(e)
	var err := Label.new()
	err.add_theme_font_size_override("font_size", 11)
	err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	err.custom_minimum_size = Vector2(250, 0)
	box.add_child(err)
	var apply := func(t: String):
		var m := MathExpr.parse(t, vars, complex)
		if m.ok():
			err.text = "✓ válida"
			err.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))
			cb.call(m)
		else:
			err.text = "✖ " + m.error
			err.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	e.text_submitted.connect(func(t): apply.call(t))
	e.focus_exited.connect(func(): apply.call(e.text))
	parent.add_child(box)
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
	s.value_changed.connect(func(v): cb.call(v))
	r.add_child(s)
	parent.add_child(r)
	return s
