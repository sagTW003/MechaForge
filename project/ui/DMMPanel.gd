class_name DMMPanel
extends FloatingPanel
## DMMPanel — Panel del multímetro digital: lectura grande (espejo de la LCD),
## selector de modo, estado de las sondas, LED/pitido de continuidad, fusible y
## alimentación del circuito.

var main: Node
var _reading: Label
var _mode_buttons: Array = []
var _probe_labels: Dictionary = {}
var _status: Label
var _fuse_btn: Button
var _led: ColorRect
var _power_btn: Button
var _jack_btn: CheckButton
var _place_btns: Dictionary = {}

func _init() -> void:
	super("Multímetro digital")

func build(m: Node) -> void:
	main = m
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(318, 0)
	add_content(vb)
	# Lectura principal (pantalla).
	var lcd := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.62, 0.68, 0.6)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(6)
	sb.border_color = Color(0.05, 0.05, 0.06)
	sb.set_border_width_all(3)
	lcd.add_theme_stylebox_override("panel", sb)
	var lh := HBoxContainer.new()
	lcd.add_child(lh)
	_reading = Label.new()
	_reading.text = "0.000 V"
	_reading.add_theme_font_size_override("font_size", 30)
	_reading.add_theme_color_override("font_color", Color(0.06, 0.07, 0.06))
	_reading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reading.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lh.add_child(_reading)
	_led = ColorRect.new()
	_led.custom_minimum_size = Vector2(14, 14)
	_led.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_led.color = Color(0.1, 0.2, 0.1)
	_led.tooltip_text = "LED de continuidad"
	lh.add_child(_led)
	vb.add_child(lcd)
	# Selector de modo.
	var mh := HBoxContainer.new()
	mh.add_theme_constant_override("separation", 2)
	var group := ButtonGroup.new()
	for i in range(DMMController.MODE_NAMES.size()):
		var b := Button.new()
		b.text = DMMController.MODE_NAMES[i]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = DMMController.MODE_LONG[i]
		b.custom_minimum_size = Vector2(48, 0)
		var idx := i
		b.pressed.connect(func():
			if main.circuit_rt.dmm.part:
				main.circuit_rt.dmm.set_mode(idx)
				Config.project_dirty = true)
		mh.add_child(b)
		_mode_buttons.append(b)
	vb.add_child(mh)
	# Sondas.
	for which in ["roja", "negra"]:
		var h := HBoxContainer.new()
		var dot := Label.new()
		dot.text = "●"
		dot.add_theme_color_override("font_color", Color(0.9, 0.15, 0.1) if which == "roja" else Color(0.55, 0.57, 0.6))
		h.add_child(dot)
		var l := Label.new()
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		l.custom_minimum_size = Vector2(200, 0)
		h.add_child(l)
		_probe_labels[which] = l
		var pb := Button.new()
		pb.text = "Colocar"
		pb.focus_mode = Control.FOCUS_NONE
		pb.tooltip_text = "Entra en modo multímetro con la sonda %s activa: haz clic en un terminal." % which
		var w: String = which
		pb.pressed.connect(func():
			main.probes.active_probe = w
			if not main.probes.active:
				main._set_probe_mode(true))
		h.add_child(pb)
		_place_btns[which] = pb
		vb.add_child(h)
	var bh := HBoxContainer.new()
	var back := Button.new()
	back.text = "Recoger sondas"
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(func():
		var d: DMMController = main.circuit_rt.dmm
		if d.part:
			d.set_probe("roja", "")
			d.set_probe("negra", ""))
	bh.add_child(back)
	_fuse_btn = Button.new()
	_fuse_btn.text = "Reemplazar fusible"
	_fuse_btn.focus_mode = Control.FOCUS_NONE
	_fuse_btn.pressed.connect(func():
		main.circuit_rt.dmm.replace_fuse()
		Config.notify("Fusible de 10 A reemplazado.", 3.0))
	bh.add_child(_fuse_btn)
	vb.add_child(bh)
	_jack_btn = CheckButton.new()
	_jack_btn.text = "Sonda roja en el borne 10 A (corrientes grandes)"
	_jack_btn.focus_mode = Control.FOCUS_NONE
	_jack_btn.toggled.connect(func(v):
		main.circuit_rt.dmm.set_jack_10a(v)
		Config.notify("Sonda roja en el borne %s." % ("10 A (derivador 0.01 Ω, fusible 10 A)" if v else "VΩmA (derivador 1 Ω, fusible 400 mA)"), 3.0))
	vb.add_child(_jack_btn)
	_power_btn = Button.new()
	_power_btn.toggle_mode = true
	_power_btn.focus_mode = Control.FOCUS_NONE
	_power_btn.button_pressed = true
	_power_btn.toggled.connect(func(v):
		main.circuit_rt.power_on = v
		Config.notify("Alimentación del circuito: %s" % ("ENCENDIDA" if v else "APAGADA (para medir Ω y continuidad)"), 3.0))
	vb.add_child(_power_btn)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(310, 0)
	_status.add_theme_color_override("font_color", Color(0.7, 0.72, 0.76))
	vb.add_child(_status)

func refresh() -> void:
	if main == null or not visible or is_collapsed():
		return
	var d: DMMController = main.circuit_rt.dmm
	if d.part == null:
		_reading.text = "—"
		_status.text = "No hay multímetro en la escena: pulsa 📟 en la barra superior para añadirlo."
		return
	_reading.text = d.reading_text()
	for i in range(_mode_buttons.size()):
		(_mode_buttons[i] as Button).set_pressed_no_signal(i == d.mode)
	for which in ["roja", "negra"]:
		var k := d.probe_key(which)
		var txt: String = "suelta" if k == "" else main.probes.describe_key(k)
		if k != "":
			var v: float = main.circuit_rt.voltage(k)
			if not is_nan(v):
				txt += "  (%.2f V)" % v
		(_probe_labels[which] as Label).text = ("Roja (VΩmA): " if which == "roja" else "Negra (COM): ") + txt
		(_place_btns[which] as Button).modulate = Color(1.3, 1.3, 0.8) if (main.probes.active and main.probes.active_probe == which) else Color.WHITE
	_led.color = Color(0.2, 1.0, 0.3) if d.beeping else Color(0.1, 0.2, 0.1)
	_fuse_btn.disabled = d.fuse_ma_ok and d.fuse_10a_ok
	_fuse_btn.text = "Reemplazar fusibles" if _fuse_btn.disabled == false else "Fusibles OK"
	_jack_btn.set_pressed_no_signal(d.jack_10a)
	var rt: CircuitRuntime = main.circuit_rt
	_power_btn.set_pressed_no_signal(rt.power_on)
	_power_btn.text = "⏻ Alimentación del circuito: %s" % ("ENCENDIDA" if rt.power_on else "APAGADA")
	var st := d.status
	if st == "":
		match d.mode:
			DMMController.Mode.V_DC, DMMController.Mode.V_AC: st = "Voltímetro en PARALELO con lo que mides (10 MΩ)."
			DMMController.Mode.A_DC: st = "Amperímetro en SERIE: abre el circuito e intercala las sondas. ¡Nunca en paralelo con la fuente! (fusible de %s)" % ("10 A" if d.jack_10a else "400 mA")
			DMMController.Mode.OHM: st = "Óhmetro: solo con el circuito desenergizado."
			DMMController.Mode.CONT: st = "Continuidad: pita por debajo de 50 Ω."
	_status.text = st
