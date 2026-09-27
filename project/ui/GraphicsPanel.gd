class_name GraphicsPanel
extends FloatingPanel
## GraphicsPanel — Panel "Entorno y gráficos".
##
## Entorno (Estudio / Taller / Exterior / HDRI de usuario), hora del día y ciclo
## día/noche, y post-procesado: antialiasing (TAA+MSAA / SMAA / FXAA), bloom,
## profundidad de campo con enfoque automático y exposición.

var _env: WorkEnvironment
var _camera: CameraOrbit
var _env_option: OptionButton
var _time_slider: HSlider
var _time_label: Label
var _cycle_check: CheckBox

func _init(env: WorkEnvironment, camera: CameraOrbit) -> void:
	super._init("Entorno y gráficos")
	_env = env
	_camera = camera
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(250, 0)
	add_content(vb)

	vb.add_child(_lbl("Entorno:"))
	_env_option = OptionButton.new()
	_env_option.focus_mode = Control.FOCUS_NONE
	_refresh_env_list()
	_env_option.item_selected.connect(func(i):
		_env.select_index(i)
		_sync_time_ui())
	vb.add_child(_env_option)

	var trow := HBoxContainer.new()
	trow.add_child(_lbl("Hora:"))
	_time_slider = HSlider.new()
	_time_slider.min_value = 0.0
	_time_slider.max_value = 24.0
	_time_slider.step = 0.25
	_time_slider.value = _env.time_of_day
	_time_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_slider.focus_mode = Control.FOCUS_NONE
	_time_slider.value_changed.connect(func(v):
		_env.set_time_of_day(v)
		_time_label.text = _fmt_hour(v))
	trow.add_child(_time_slider)
	_time_label = _lbl(_fmt_hour(_env.time_of_day))
	_time_label.custom_minimum_size = Vector2(44, 0)
	trow.add_child(_time_label)
	vb.add_child(trow)
	_cycle_check = CheckBox.new()
	_cycle_check.text = "Ciclo día/noche"
	_cycle_check.focus_mode = Control.FOCUS_NONE
	_cycle_check.toggled.connect(func(v): _env.day_cycle = v)
	vb.add_child(_cycle_check)

	vb.add_child(HSeparator.new())
	vb.add_child(_lbl("Antialiasing:"))
	var aa := OptionButton.new()
	aa.focus_mode = Control.FOCUS_NONE
	for n in GraphicsProfiles.AA_NAMES:
		aa.add_item(n)
	aa.select(GraphicsProfiles.aa_mode)
	aa.item_selected.connect(func(i): GraphicsProfiles.set_aa_mode(i))
	vb.add_child(aa)

	var bloom := CheckBox.new()
	bloom.text = "Bloom (LEDs, soldadura)"
	bloom.button_pressed = true
	bloom.focus_mode = Control.FOCUS_NONE
	bloom.toggled.connect(func(v): _env.world_env.environment.glow_enabled = v)
	vb.add_child(bloom)
	var dof := CheckBox.new()
	dof.text = "Profundidad de campo (autoenfoque)"
	dof.button_pressed = true
	dof.focus_mode = Control.FOCUS_NONE
	dof.toggled.connect(func(v):
		_camera.dof_enabled = v
		_camera._update_dof())
	vb.add_child(dof)

	var erow := HBoxContainer.new()
	erow.add_child(_lbl("Exposición:"))
	var exp := HSlider.new()
	exp.min_value = -1.5
	exp.max_value = 1.5
	exp.step = 0.05
	exp.value = 0.0
	exp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exp.focus_mode = Control.FOCUS_NONE
	exp.value_changed.connect(func(v):
		var attr := _camera.attributes as CameraAttributesPractical
		if attr:
			attr.exposure_multiplier = pow(2.0, v))
	erow.add_child(exp)
	vb.add_child(erow)

	var note := _lbl("Añade tus HDRI (.hdr/.exr/.png) en user://hdri o assets/hdri y pulsa ⟳.")
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", Color(0.6, 0.62, 0.66))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(240, 0)
	vb.add_child(note)
	var refresh := Button.new()
	refresh.text = "⟳ Buscar HDRI"
	refresh.focus_mode = Control.FOCUS_NONE
	refresh.pressed.connect(_refresh_env_list)
	vb.add_child(refresh)
	_sync_time_ui()

func _refresh_env_list() -> void:
	_env_option.clear()
	for n in _env.available():
		_env_option.add_item(n)
	_env_option.select(_env.current_index())

func _sync_time_ui() -> void:
	var ext := _env.mode == WorkEnvironment.Mode.COCHERA and _env.hdri_path == ""
	_time_slider.editable = ext
	_cycle_check.disabled = not ext

func _process(_delta: float) -> void:
	if _env and _env.day_cycle and _time_slider and not _time_slider.has_focus():
		_time_slider.set_value_no_signal(_env.time_of_day)
		_time_label.text = _fmt_hour(_env.time_of_day)

static func _fmt_hour(h: float) -> String:
	return "%02d:%02d" % [int(h) % 24, int(fposmod(h, 1.0) * 60.0)]

func _lbl(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l
