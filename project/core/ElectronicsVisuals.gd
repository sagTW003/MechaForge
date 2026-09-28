class_name ElectronicsVisuals
extends RefCounted
## ElectronicsVisuals — Modelos 3D detallados de componentes insertables y del
## multímetro digital: resistencia axial con bandas de color calculadas a partir
## de su valor, LED de 5 mm con patas, integrado DIP (NE555), Arduino Nano,
## batería de 9 V y multímetro (carcasa de goma, LCD de 7 segmentos por shader,
## selector giratorio, bornes y serigrafía).
##
## Las patas terminan en la cara inferior de la pieza (y = −alto/2): al insertarla
## en la protoboard esa cota coincide con la superficie y entran en los agujeros.

const BAND_COLORS := [Color(0.03, 0.03, 0.03), Color(0.36, 0.2, 0.08), Color(0.8, 0.08, 0.06), Color(0.95, 0.42, 0.05),
	Color(0.95, 0.82, 0.08), Color(0.1, 0.55, 0.15), Color(0.1, 0.25, 0.8), Color(0.5, 0.15, 0.7),
	Color(0.5, 0.5, 0.52), Color(0.95, 0.95, 0.93)]

## Posiciones (mm, locales) de los bornes del multímetro y de su LCD/selector.
const DMM_JACK_COM := Vector3(0, 18, 62)
const DMM_JACK_V := Vector3(24, 18, 62)
const DMM_JACK_A := Vector3(-24, 18, 62)
const DMM_DIAL := Vector3(0, 18, 10)
const DMM_DIAL_ANGLES := [-75.0, -45.0, -15.0, 15.0, 45.0, 75.0]    # OFF, V⎓, V~, A⎓, Ω, continuidad
const DMM_DIAL_LABELS := ["OFF", "DCV", "ACV", "DCA", "Ω", "•)))"]

static func _m(c: Color, metallic := 0.0, rough := 0.5, emissive := false) -> StandardMaterial3D:
	return PartVisuals.mat(c, metallic, rough, emissive)

static func _flat(size: Vector3, material: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new(); b.size = size
	mi.mesh = b
	mi.material_override = material
	mi.position = pos
	return mi

static func _cyl(r: float, h: float, material: Material, pos: Vector3, segs := 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r; c.bottom_radius = r; c.height = h; c.radial_segments = segs; c.rings = 1
	mi.mesh = c
	mi.material_override = material
	mi.position = pos
	return mi

## Varilla entre dos puntos (patas dobladas).
static func _rod(a: Vector3, b: Vector3, r: float, material: Material) -> MeshInstance3D:
	var mi := _cyl(r, maxf(0.00001, a.distance_to(b)), material, (a + b) * 0.5, 6)
	var dir := (b - a).normalized()
	if absf(dir.dot(Vector3.UP)) < 0.999:
		mi.basis = Basis(Quaternion(Vector3.UP, dir))
	return mi

static func _text(t: String, pos: Vector3, px: float, col: Color, font_size := 48) -> Label3D:
	var l := Label3D.new()
	l.text = t
	l.pixel_size = px
	l.font_size = font_size
	l.outline_size = 0
	l.modulate = col
	l.double_sided = false
	l.shaded = true
	l.position = pos
	l.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	return l

# --- Resistencia axial -------------------------------------------------------

## Bandas: dígito 1, dígito 2, multiplicador y tolerancia (oro, 5 %).
static func resistor_bands(ohm: float) -> Array:
	var e := int(floor(log(maxf(ohm, 1.0)) / log(10.0))) - 1
	var sig := int(round(ohm / pow(10.0, e)))
	if sig >= 100:
		sig /= 10
		e += 1
	e = clampi(e, 0, 9)
	return [BAND_COLORS[clampi(sig / 10, 0, 9)], BAND_COLORS[sig % 10], BAND_COLORS[e], Color(0.85, 0.68, 0.25)]

static func resistor(d: Vector3, def: Dictionary) -> Node3D:
	var n := Node3D.new()
	var ohm := float(def.get("electrico", {}).get("resistencia_ohm", 100.0))
	var y0 := -d.y * 0.5                       # superficie de la protoboard
	var cy := y0 + 0.0046                      # eje del cuerpo (2.4 mm sobre la placa)
	var body := _m(Color(0.84, 0.74, 0.55), 0.0, 0.45)
	var c := _cyl(0.00125, 0.0048, body, Vector3(0, cy, 0), 20)
	c.rotation_degrees = Vector3(0, 0, 90)
	c.set_meta("burn_tint", true)
	n.add_child(c)
	for s: float in [-1.0, 1.0]:
		var cap := MeshInstance3D.new()
		var sm := SphereMesh.new(); sm.radius = 0.00135; sm.height = 0.0027
		cap.mesh = sm
		cap.material_override = body
		cap.position = Vector3(s * 0.0024, cy, 0)
		cap.scale = Vector3(0.8, 1, 1)
		cap.set_meta("burn_tint", true)
		n.add_child(cap)
	var bands := resistor_bands(ohm)
	var bx := [-0.0019, -0.0009, 0.0001, 0.0019]
	for i in range(4):
		var band := _cyl(0.00129, 0.00055, _m(bands[i], 0.15 if i == 3 else 0.0, 0.4), Vector3(bx[i], cy, 0), 20)
		band.rotation_degrees = Vector3(0, 0, 90)
		band.set_meta("burn_tint", true)
		n.add_child(band)
	# Patas estañadas: salen del cuerpo, se doblan a 90° y entran en los agujeros.
	var leg := _m(Color(0.78, 0.78, 0.8), 1.0, 0.3)
	var px := 0.00508
	for s: float in [-1.0, 1.0]:
		n.add_child(_rod(Vector3(s * 0.0033, cy, 0), Vector3(s * (px - 0.0004), cy, 0), 0.0003, leg))
		n.add_child(_rod(Vector3(s * (px - 0.0004), cy, 0), Vector3(s * px, cy - 0.0004, 0), 0.0003, leg))
		n.add_child(_rod(Vector3(s * px, cy - 0.0004, 0), Vector3(s * px, y0 - 0.003, 0), 0.0003, leg))
	return n

# --- LED 5 mm ------------------------------------------------------------------

static func led(d: Vector3, def: Dictionary) -> Node3D:
	var n := Node3D.new()
	var dd: Dictionary = def.get("electrico", {}).get("diodo", {})
	var cols := {"rojo": Color(0.95, 0.12, 0.1), "verde": Color(0.15, 0.85, 0.2), "amarillo": Color(0.98, 0.8, 0.1),
		"azul": Color(0.2, 0.35, 1.0), "blanco": Color(0.95, 0.95, 1.0)}
	var col: Color = cols.get(str(dd.get("color", "rojo")), Color(0.95, 0.12, 0.1))
	var y0 := -d.y * 0.5
	var body := StandardMaterial3D.new()
	body.albedo_color = Color(col.r, col.g, col.b, 0.72)
	body.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	body.roughness = 0.08
	body.metallic_specular = 0.8
	body.emission_enabled = true
	body.emission = col
	body.emission_energy_multiplier = 0.05
	body.rim_enabled = true
	body.rim = 0.3
	var flange_y := y0 + 0.0036
	var fl := _cyl(0.0029, 0.001, body, Vector3(0, flange_y + 0.0005, 0), 24)
	fl.set_meta("led_glow", true); fl.set_meta("burn_tint", true)
	n.add_child(fl)
	var cyl := _cyl(0.0025, 0.0052, body, Vector3(0, flange_y + 0.001 + 0.0026, 0), 24)
	cyl.set_meta("led_glow", true); cyl.set_meta("burn_tint", true)
	n.add_child(cyl)
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = 0.0025; sm.height = 0.005; sm.radial_segments = 24; sm.rings = 12
	dome.mesh = sm
	dome.material_override = body
	dome.position = Vector3(0, flange_y + 0.0062, 0)
	dome.set_meta("led_glow", true); dome.set_meta("burn_tint", true)
	n.add_child(dome)
	# Yunque y poste internos (se ven a través de la resina).
	var metal := _m(Color(0.7, 0.7, 0.72), 1.0, 0.3)
	n.add_child(_flat(Vector3(0.0012, 0.0022, 0.0004), metal, Vector3(-0.0005, flange_y + 0.0022, 0)))
	n.add_child(_flat(Vector3(0.0005, 0.0026, 0.0004), metal, Vector3(0.0007, flange_y + 0.0024, 0)))
	# Patas: el ánodo (+X) es la larga.
	var leg := _m(Color(0.78, 0.78, 0.8), 1.0, 0.3)
	n.add_child(_rod(Vector3(0.00127, flange_y, 0), Vector3(0.00127, y0 - 0.003, 0), 0.00025, leg))
	n.add_child(_rod(Vector3(-0.00127, flange_y, 0), Vector3(-0.00127, y0 - 0.003, 0), 0.00025, leg))
	return n

# --- Integrado DIP (NE555) -------------------------------------------------------

static func dip(d: Vector3, def: Dictionary) -> Node3D:
	var n := Node3D.new()
	var y0 := -d.y * 0.5
	var dp: Dictionary = def.get("dip", {})
	var fila := float(dp.get("fila_mm", 7.62)) / 1000.0
	var npins := int(dp.get("pines", 8))
	var len_x := (npins / 2) * 0.00254 + 0.0001
	var body_w := fila - 0.0013
	var by0 := y0 + 0.0009
	var bh := 0.0033
	var epoxy := _m(Color(0.035, 0.035, 0.04), 0.0, 0.55)
	var body := MeshInstance3D.new()
	body.mesh = MeshFactory.chamfer_box(Vector3(len_x, bh, body_w), 0.0004)
	body.material_override = epoxy
	body.position = Vector3(0, by0 + bh * 0.5, 0)
	body.set_meta("burn_tint", true)
	n.add_child(body)
	# Muesca de la pata 1 y punto.
	var dark := _m(Color(0.015, 0.015, 0.018), 0.0, 0.7)
	var notch := _cyl(0.0008, 0.0002, dark, Vector3(-len_x * 0.5 + 0.0001, by0 + bh + 0.00005, 0), 16)
	n.add_child(notch)
	n.add_child(_cyl(0.0004, 0.0001, dark, Vector3(-len_x * 0.5 + 0.0011, by0 + bh + 0.00005, fila * 0.5 - 0.0015), 12))
	n.add_child(_text(str(dp.get("rotulo", "IC")), Vector3(0, by0 + bh + 0.0001, 0), 0.000028, Color(0.75, 0.75, 0.72), 40))
	# Patas: hombro ancho y punta estrecha que entra en el agujero.
	var tin := _m(Color(0.8, 0.8, 0.82), 1.0, 0.28)
	for p: Vector3 in PartInstance.dip_pin_positions(def):
		var pm := p / 1000.0
		var sz := signf(pm.z)
		n.add_child(_flat(Vector3(0.0005, 0.00025, 0.0009), tin, Vector3(pm.x, by0 + 0.0011, sz * (body_w * 0.5 + 0.00035))))
		n.add_child(_flat(Vector3(0.0014, 0.0016, 0.00025), tin, Vector3(pm.x, by0 + 0.0003, pm.z)))
		n.add_child(_flat(Vector3(0.0005, 0.0036, 0.00025), tin, Vector3(pm.x, y0 - 0.0012, pm.z)))
	return n

# --- Arduino Nano ----------------------------------------------------------------

static func nano(d: Vector3, def: Dictionary) -> Node3D:
	var n := Node3D.new()
	var y0 := -d.y * 0.5
	var hh := 0.0025                        # regleta de pines (plástico negro)
	var pcb_t := 0.0016
	var py := y0 + hh
	var pcb := MeshInstance3D.new()
	pcb.mesh = MeshFactory.chamfer_box(Vector3(d.x, pcb_t, 0.018), 0.0003)
	pcb.material_override = _m(Color(0.05, 0.25, 0.55), 0.1, 0.4)
	pcb.position = Vector3(0, py + pcb_t * 0.5, 0)
	pcb.set_meta("burn_tint", true)
	n.add_child(pcb)
	var top := py + pcb_t
	var black := _m(Color(0.03, 0.03, 0.035), 0.0, 0.6)
	var gold := _m(Color(0.85, 0.68, 0.25), 0.95, 0.3)
	var solder := MaterialLibrary.get_visual("estano")
	for sz: float in [1.0, -1.0]:
		n.add_child(_flat(Vector3(0.0381, hh, 0.0025), black, Vector3(0, y0 + hh * 0.5, sz * 0.00762)))
	for p: Vector3 in PartInstance.dip_pin_positions(def):
		var pm := p / 1000.0
		n.add_child(_flat(Vector3(0.00064, 0.0078, 0.00064), gold, Vector3(pm.x, y0 + 0.0009, pm.z)))
		var blob := MeshInstance3D.new()
		var sm := SphereMesh.new(); sm.radius = 0.00075; sm.height = 0.0008
		blob.mesh = sm
		blob.material_override = solder
		blob.position = Vector3(pm.x, top + 0.0002, pm.z)
		n.add_child(blob)
	# Microcontrolador TQFP-32 girado 45°, cristal, regulador y conector USB.
	var chip := _flat(Vector3(0.007, 0.001, 0.007), _m(Color(0.04, 0.04, 0.045), 0.0, 0.4), Vector3(0.003, top + 0.0005, 0))
	chip.rotation.y = PI / 4.0
	n.add_child(chip)
	var usb := _flat(Vector3(0.009, 0.004, 0.0078), _m(Color(0.78, 0.79, 0.8), 1.0, 0.25), Vector3(-d.x * 0.5 + 0.0035, top + 0.002, 0))
	n.add_child(usb)
	n.add_child(_flat(Vector3(0.0065, 0.0015, 0.0035), _m(Color(0.04, 0.04, 0.045), 0.0, 0.5), Vector3(-0.006, top + 0.00075, 0.004)))
	n.add_child(_flat(Vector3(0.004, 0.0012, 0.0018), _m(Color(0.8, 0.8, 0.82), 1.0, 0.3), Vector3(0.012, top + 0.0006, -0.004)))
	var btn := _flat(Vector3(0.003, 0.0012, 0.003), _m(Color(0.9, 0.9, 0.9), 0.0, 0.5), Vector3(0.014, top + 0.0006, 0.003))
	n.add_child(btn)
	# LED de encendido (PWR, verde) y LED "L" del pin 13 (naranja).
	for spec in [["PWR", Color(0.2, 1.0, 0.3), -0.0045], ["L", Color(1.0, 0.55, 0.1), -0.0025]]:
		var lm := _m(spec[1], 0.0, 0.3, true)
		lm.emission_energy_multiplier = 0.05
		var lmi := _flat(Vector3(0.0016, 0.0006, 0.0008), lm, Vector3(-0.012, top + 0.0003, float(spec[2])))
		lmi.set_meta("nano_led", spec[0])
		n.add_child(lmi)
	n.add_child(_text("NANO", Vector3(0.012, top + 0.00005, 0.0055), 0.00003, Color(0.9, 0.9, 0.9), 40))
	return n

# --- Batería 9 V -------------------------------------------------------------------

static func battery_9v(d: Vector3) -> Node3D:
	var n := Node3D.new()
	var can := MeshInstance3D.new()
	can.mesh = MeshFactory.chamfer_box(d, 0.0025)
	can.material_override = _m(Color(0.08, 0.08, 0.09), 0.3, 0.4)
	n.add_child(can)
	n.add_child(_flat(Vector3(d.x * 1.005, d.y * 1.005, d.z * 0.42), _m(Color(0.92, 0.5, 0.08), 0.2, 0.4), Vector3(0, 0, -d.z * 0.12)))
	var steel := _m(Color(0.8, 0.8, 0.82), 1.0, 0.25)
	var ez := d.z * 0.5
	var pos_stud := _cyl(0.0027, 0.0035, steel, Vector3(0.00635, 0, ez + 0.0017), 20)
	pos_stud.rotation_degrees = Vector3(90, 0, 0)
	n.add_child(pos_stud)
	var neg := _cyl(0.0042, 0.0035, steel, Vector3(-0.00635, 0, ez + 0.0017), 6)
	neg.rotation_degrees = Vector3(90, 0, 0)
	n.add_child(neg)
	var t := _text("9V", Vector3(0, d.y * 0.5 + 0.0001, -d.z * 0.12), 0.00012, Color(0.1, 0.1, 0.1), 64)
	n.add_child(t)
	n.add_child(_text("+", Vector3(0.00635, d.y * 0.5 + 0.0001, ez - 0.004), 0.0001, Color(0.9, 0.9, 0.9), 48))
	n.add_child(_text("−", Vector3(-0.00635, d.y * 0.5 + 0.0001, ez - 0.004), 0.0001, Color(0.9, 0.9, 0.9), 48))
	return n

# --- Multímetro digital ------------------------------------------------------------

static func multimeter(d: Vector3) -> Node3D:
	var n := Node3D.new()
	var mm := func(v: Vector3) -> Vector3: return v / 1000.0
	# Funda de goma (amarilla) y cuerpo.
	var holster := MeshInstance3D.new()
	holster.mesh = MeshFactory.chamfer_box(Vector3(d.x, d.y - 0.002, d.z), 0.008)
	holster.material_override = PartVisuals.tex("Rubber004", Color(0.95, 0.72, 0.12), 20.0, {"rough": 0.8})
	holster.position = Vector3(0, -0.001, 0)
	n.add_child(holster)
	var face := MeshInstance3D.new()
	face.mesh = MeshFactory.chamfer_box(Vector3(0.076, 0.002, 0.158), 0.001)
	face.material_override = _m(Color(0.16, 0.17, 0.19), 0.0, 0.5)
	face.position = mm.call(Vector3(0, 17, 0))
	n.add_child(face)
	# LCD con bisel.
	n.add_child(_flat(mm.call(Vector3(68, 0.6, 36)), _m(Color(0.05, 0.05, 0.06), 0.0, 0.3), mm.call(Vector3(0, 18.2, -52))))
	var lcd := MeshInstance3D.new()
	lcd.name = "LCD"
	var pm := PlaneMesh.new()
	pm.size = Vector2(0.064, 0.030)
	lcd.mesh = pm
	var sm := ShaderMaterial.new()
	sm.shader = load("res://rendering/lcd7seg.gdshader")
	lcd.material_override = sm
	lcd.position = mm.call(Vector3(0, 18.55, -52))
	n.add_child(lcd)
	var unit := _text("V", mm.call(Vector3(27.5, 18.6, -45)), 0.00008, Color(0.07, 0.08, 0.07), 64)
	unit.name = "UnitLabel"
	n.add_child(unit)
	var auto_l := _text("AUTO", mm.call(Vector3(0, 18.6, -64.5)), 0.00004, Color(0.1, 0.11, 0.1), 48)
	n.add_child(auto_l)
	# LED de continuidad.
	var led_m := _m(Color(0.2, 1.0, 0.3), 0.0, 0.3, true)
	led_m.emission_energy_multiplier = 0.05
	var led_mi := _cyl(0.0018, 0.0012, led_m, mm.call(Vector3(29, 18.3, -28)), 16)
	led_mi.name = "ContLED"
	n.add_child(led_mi)
	# Botones HOLD / RANGE / SEL.
	var btn_m := _m(Color(0.55, 0.56, 0.6), 0.0, 0.5)
	var names := ["HOLD", "RANGE", "SEL"]
	for i in range(3):
		var bx := -20.0 + i * 16.0
		var b := MeshInstance3D.new()
		b.mesh = MeshFactory.chamfer_box(mm.call(Vector3(11, 2, 6)), 0.001)
		b.material_override = btn_m
		b.position = mm.call(Vector3(bx, 18.6, -27))
		n.add_child(b)
		n.add_child(_text(names[i], mm.call(Vector3(bx, 19.7, -27)), 0.00003, Color(0.1, 0.1, 0.12), 40))
	# Selector giratorio: base, anillo y mando con puntero (gira con el modo).
	var dial := Node3D.new()
	dial.name = "Dial"
	dial.position = mm.call(DMM_DIAL)
	n.add_child(dial)
	var base := _cyl(0.024, 0.0015, _m(Color(0.1, 0.1, 0.11), 0.0, 0.5), Vector3(0, 0.00075, 0), 48)
	n.add_child(base)
	base.position = mm.call(DMM_DIAL + Vector3(0, 0.75, 0))
	var knob_m := _m(Color(0.08, 0.08, 0.09), 0.1, 0.45)
	var knob := _cyl(0.019, 0.004, knob_m, Vector3(0, 0.0035, 0), 48)
	dial.add_child(knob)
	var bar := MeshInstance3D.new()
	bar.mesh = MeshFactory.chamfer_box(Vector3(0.009, 0.006, 0.042), 0.0015)
	bar.material_override = knob_m
	bar.position = Vector3(0, 0.0065, 0)
	dial.add_child(bar)
	var pointer := _flat(Vector3(0.0016, 0.0004, 0.014), _m(Color(0.95, 0.95, 0.95), 0.0, 0.4), Vector3(0, 0.0097, -0.013))
	dial.add_child(pointer)
	for i in range(DMM_DIAL_ANGLES.size()):
		var a := deg_to_rad(float(DMM_DIAL_ANGLES[i]))
		var lp := DMM_DIAL + Vector3(sin(a) * 30.0, 0.6, -cos(a) * 30.0)
		var col := Color(0.95, 0.95, 0.95) if i != 3 else Color(1.0, 0.35, 0.25)
		var lab := _text(DMM_DIAL_LABELS[i], mm.call(lp), 0.00005, col, 48)
		n.add_child(lab)
		var tick := _flat(Vector3(0.0008, 0.0003, 0.003), _m(col, 0.0, 0.5), mm.call(DMM_DIAL + Vector3(sin(a) * 24.5, 0.3, -cos(a) * 24.5)))
		tick.rotation.y = -a
		n.add_child(tick)
	# Bornes: 10A, COM y VΩmA.
	var jacks := [[DMM_JACK_A, Color(0.85, 0.12, 0.1), "10A"], [DMM_JACK_COM, Color(0.05, 0.05, 0.05), "COM"], [DMM_JACK_V, Color(0.85, 0.12, 0.1), "VΩmA"]]
	for j in jacks:
		var jp: Vector3 = j[0]
		n.add_child(_cyl(0.0052, 0.0014, _m(j[1], 0.0, 0.4), mm.call(jp + Vector3(0, 0.3, 0)), 24))
		n.add_child(_cyl(0.0022, 0.0016, _m(Color(0.01, 0.01, 0.01), 0.0, 0.9), mm.call(jp + Vector3(0, 0.45, 0)), 16))
		n.add_child(_text(j[2], mm.call(jp + Vector3(0, 0.2, -9.5)), 0.00004, Color(0.9, 0.9, 0.9), 44))
	n.add_child(_text("MF-17B", mm.call(Vector3(0, 18.2, 78)), 0.00007, Color(0.9, 0.9, 0.92), 56))
	n.add_child(_text("CAT III 600V   F10A", mm.call(Vector3(0, 18.2, 51)), 0.000032, Color(0.8, 0.8, 0.82), 40))
	return n

## Actualiza la pantalla, el selector y el LED de continuidad de un modelo de
## multímetro (en edición o su copia en simulación) con el estado del DMM.
static func update_multimeter(root: Node, dmm: DMMController, beep_blink: bool) -> void:
	if root == null or dmm == null:
		return
	var lcd := root.find_child("LCD", true, false) as MeshInstance3D
	if lcd and lcd.material_override is ShaderMaterial:
		var sm := lcd.material_override as ShaderMaterial
		var enc := DMMController.lcd_encode(dmm.display)
		for i in range(4):
			sm.set_shader_parameter("seg%d" % i, int(enc["seg"][i]))
		sm.set_shader_parameter("dp", int(enc["dp"]))
		sm.set_shader_parameter("minus_sign", bool(enc["minus"]))
		var on := dmm.mode != DMMController.Mode.OFF
		sm.set_shader_parameter("powered", on)
		sm.set_shader_parameter("icon_dc", dmm.mode in [DMMController.Mode.V_DC, DMMController.Mode.A_DC])
		sm.set_shader_parameter("icon_ac", dmm.mode == DMMController.Mode.V_AC)
		sm.set_shader_parameter("icon_cont", dmm.mode == DMMController.Mode.CONT and (not dmm.beeping or beep_blink))
		sm.set_shader_parameter("icon_battery", on)
		sm.set_shader_parameter("backlight", 0.12 if on else 0.0)
	var ul := root.find_child("UnitLabel", true, false) as Label3D
	if ul:
		ul.text = dmm.unit if dmm.mode != DMMController.Mode.OFF else ""
	var dial := root.find_child("Dial", true, false) as Node3D
	if dial:
		var target := -deg_to_rad(float(DMM_DIAL_ANGLES[dmm.mode]))
		dial.rotation.y = lerp_angle(dial.rotation.y, target, 0.35)
	var led := root.find_child("ContLED", true, false) as MeshInstance3D
	if led and led.material_override is StandardMaterial3D:
		(led.material_override as StandardMaterial3D).emission_energy_multiplier = 6.0 if dmm.beeping else 0.05
