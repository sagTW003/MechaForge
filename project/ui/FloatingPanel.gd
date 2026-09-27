class_name FloatingPanel
extends PanelContainer
## FloatingPanel — Panel flotante arrastrable y plegable (abatible).
##
## Tiene una barra de título con un botón de plegado (▾/▸) y se puede mover
## arrastrando esa barra. El contenido se añade con add_content().

signal moved

var content: VBoxContainer
var _title_label: Label
var _collapse_btn: Button
var _title_bar: PanelContainer
var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _collapsed: bool = false

func _init(title_text: String = "") -> void:
	# Estilo del marco.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.11, 0.13, 0.96)
	sb.border_color = Color(0.24, 0.26, 0.30)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(0)
	add_theme_stylebox_override("panel", sb)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	# Barra de título.
	_title_bar = PanelContainer.new()
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.14, 0.16, 0.19)
	tsb.set_corner_radius_all(5)
	tsb.set_content_margin_all(4)
	_title_bar.add_theme_stylebox_override("panel", tsb)
	_title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_title_bar.gui_input.connect(_on_title_input)
	root.add_child(_title_bar)

	var tb := HBoxContainer.new()
	_title_bar.add_child(tb)
	_collapse_btn = Button.new()
	_collapse_btn.text = "▾"
	_collapse_btn.flat = true
	_collapse_btn.focus_mode = Control.FOCUS_NONE
	_collapse_btn.custom_minimum_size = Vector2(22, 0)
	_collapse_btn.pressed.connect(toggle_collapsed)
	tb.add_child(_collapse_btn)
	_title_label = Label.new()
	_title_label.text = title_text
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tb.add_child(_title_label)
	var grip := Label.new()
	grip.text = "⠿"
	grip.add_theme_color_override("font_color", Color(0.5, 0.53, 0.58))
	grip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tb.add_child(grip)

	# Contenido.
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(margin)
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(content)
	_content_margin = margin

	# Tirador de redimensionado (esquina inferior derecha).
	var grip_row := HBoxContainer.new()
	var grow := Control.new()
	grow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grip_row.add_child(grow)
	_resize_grip = Label.new()
	_resize_grip.text = "◢"
	_resize_grip.add_theme_color_override("font_color", Color(0.5, 0.53, 0.58))
	_resize_grip.mouse_filter = Control.MOUSE_FILTER_STOP
	_resize_grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	_resize_grip.gui_input.connect(_on_grip_input)
	grip_row.add_child(_resize_grip)
	root.add_child(grip_row)

var _content_margin: MarginContainer
var _resize_grip: Label
var _resizing: bool = false
var _resize_start_min: Vector2 = Vector2.ZERO
var _resize_start_mouse: Vector2 = Vector2.ZERO

func set_title(t: String) -> void:
	_title_label.text = t

## Añade un control al cuerpo del panel.
func add_content(node: Control) -> void:
	content.add_child(node)

func toggle_collapsed() -> void:
	set_collapsed(not _collapsed)

func set_collapsed(v: bool) -> void:
	_collapsed = v
	_content_margin.visible = not v
	_collapse_btn.text = "▸" if v else "▾"
	# Deja que el contenedor se ajuste al nuevo tamaño.
	await get_tree().process_frame
	reset_size()

func is_collapsed() -> bool:
	return _collapsed

# --- Arrastre por la barra de título ---
func _on_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_offset = get_global_mouse_position() - global_position
			# Pasa a posicionamiento absoluto (desancla).
			set_anchors_preset(Control.PRESET_TOP_LEFT)
		else:
			_dragging = false

func _on_grip_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and not _collapsed:
			_resizing = true
			_resize_start_min = size
			_resize_start_mouse = get_global_mouse_position()
		else:
			_resizing = false

func _input(event: InputEvent) -> void:
	if _resizing:
		if event is InputEventMouseMotion:
			var d := get_global_mouse_position() - _resize_start_mouse
			custom_minimum_size = Vector2(
				maxf(200.0, _resize_start_min.x + d.x),
				maxf(120.0, _resize_start_min.y + d.y))
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_resizing = false
		return
	if not _dragging:
		return
	if event is InputEventMouseMotion:
		var vp := get_viewport_rect().size
		var pos := get_global_mouse_position() - _drag_offset
		pos.x = clampf(pos.x, 0.0, maxf(0.0, vp.x - size.x))
		pos.y = clampf(pos.y, 0.0, maxf(0.0, vp.y - 40.0))
		global_position = pos
		moved.emit()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
