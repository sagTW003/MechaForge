class_name PartVisuals
extends RefCounted
## PartVisuals — Construye el aspecto detallado de las piezas.
##
## En vez de una caja/cilindro plano, arma un pequeño conjunto de mallas con
## materiales realistas para que cada componente se reconozca (placa PCB con
## chip y pines, LED con cúpula y patas, motor con eje, protoboard, etc.).
## Devuelve un Node3D con las mallas, o null para usar la malla por defecto.

static func mat(color: Color, metallic := 0.0, roughness := 0.6, emissive := false) -> StandardMaterial3D:
	# Superficies opacas y no emisivas: textura fotográfica real (ambientCG, CC0)
	# teñida con el color de la pieza — plástico texturado o metal satinado.
	if not emissive and color.a >= 1.0:
		var tm: StandardMaterial3D
		if metallic > 0.5:
			tm = TextureSets.material("Metal011", {"tint": color.lightened(0.15), "scale": 30.0,
				"rough": clampf(roughness * 1.5, 0.1, 1.0), "metallic": 1.0, "normal": 0.5})
		else:
			tm = TextureSets.material("Plastic013A", {"tint": color, "scale": 40.0,
				"rough": clampf(roughness * 1.4, 0.08, 1.0), "metallic": metallic, "normal": 0.6})
		if tm:
			return tm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emissive:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 0.6
	return m

## Material fotográfico concreto (p. ej. "Rubber004"), con respaldo plano.
static func tex(id: String, tint: Color, scale: float = 30.0, extra: Dictionary = {}) -> StandardMaterial3D:
	var o := {"tint": tint, "scale": scale}
	o.merge(extra, true)
	var m := TextureSets.material(id, o)
	return m if m else mat(tint)

static func _box(size: Vector3, material: StandardMaterial3D, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new(); b.size = size
	mi.mesh = b
	mi.material_override = material
	mi.position = pos
	return mi

static func _cyl(radius: float, height: float, material: StandardMaterial3D, pos := Vector3.ZERO, segs := 20) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius; c.bottom_radius = radius; c.height = height; c.radial_segments = segs
	mi.mesh = c
	mi.material_override = material
	mi.position = pos
	return mi

## Punto de entrada. def = definición de la pieza; devuelve Node3D o null.
static func build(def: Dictionary) -> Node3D:
	var ap: String = def.get("apariencia", "")
	if ap == "":
		return null
	var d := PartLibrary.dims_m(def)
	match ap:
		"placa_pcb": return _pcb(d, def)
		"led": return ElectronicsVisuals.led(d, def)
		"motor": return _motor(d)
		"resistencia": return ElectronicsVisuals.resistor(d, def)
		"dip": return ElectronicsVisuals.dip(d, def)
		"nano": return ElectronicsVisuals.nano(d, def)
		"bateria_9v": return ElectronicsVisuals.battery_9v(d)
		"multimetro": return ElectronicsVisuals.multimeter(d)
		"servo": return _servo(d)
		"bateria_caja": return _battery_box(d)
		"bateria_cil": return _battery_cyl(d)
		"protoboard": return _protoboard(d)
		"sensor_ultra": return _sensor_ultra(d)
		"boton": return _button(d)
		"potenciometro": return _pot(d)
		"fin_carrera": return _limit_switch(d)
		"rueda": return _wheel(d)
		"sensor_linea": return _line_sensor(d)
		"fsr": return _fsr(d)
		"lidar": return _lidar(d)
		"pantalla": return _screen(d, def, false)
		"movil": return _screen(d, def, true)
		"esp32": return _esp32(d)
		"cabeza": return _head(d, def)
		_: return null

## Carta de ajuste lado a lado (un círculo, una cruz y una rejilla por ojo, y barras
## de color): lo que muestra la pantalla del visor hasta que haya render estéreo.
static var _sbs_pattern: ImageTexture

static func sbs_pattern() -> ImageTexture:
	if _sbs_pattern:
		return _sbs_pattern
	var w := 640
	var h := 360
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color(0.04, 0.05, 0.08))
	var half := w / 2
	for eye in range(2):
		var x0 := eye * half
		var cx := x0 + half / 2
		var cy := h / 2
		for y in range(h):
			for x in range(x0, x0 + half):
				var dx := float(x - cx)
				var dy := float(y - cy)
				var r := sqrt(dx * dx + dy * dy)
				var c := Color(-1, 0, 0)
				if (x - x0) % 40 == 0 or y % 40 == 0:
					c = Color(0.22, 0.25, 0.3)
				if absf(r - h * 0.16) < 1.2 or absf(r - h * 0.33) < 1.2:
					c = Color(0.35, 0.85, 1.0)
				if (absi(x - cx) < 1 and absf(dy) < h * 0.4) or (absi(y - cy) < 1 and absf(dx) < half * 0.4):
					c = Color(1, 1, 1)
				if x == x0 or x == x0 + half - 1 or y == 0 or y == h - 1:
					c = Color(0.9, 0.5, 0.15)
				if c.r >= 0.0:
					img.set_pixel(x, y, c)
		# Barras de color abajo.
		var bars := [Color(1, 0.15, 0.1), Color(0.2, 1, 0.3), Color(0.2, 0.4, 1), Color(1, 1, 1)]
		for i in range(4):
			img.fill_rect(Rect2i(cx - 60 + i * 30, h - 46, 26, 18), bars[i])
	img.generate_mipmaps()
	_sbs_pattern = ImageTexture.create_from_image(img)
	return _sbs_pattern

## Pantalla LCD con su placa controladora detrás, o teléfono móvil. La cara activa
## mira a +Y: un plano con la carta de ajuste emisiva (meta "pantalla_luz"); el LCD
## se enciende cuando le llega alimentación (CircuitRuntime) y el móvil siempre.
static func _screen(d: Vector3, def: Dictionary, phone: bool) -> Node3D:
	var n := Node3D.new()
	var info: Dictionary = def.get("pantalla", {})
	var area: Array = info.get("area_mm", [d.x * 960.0, d.z * 940.0])
	var aw := float(area[0]) / 1000.0
	var ah := float(area[1]) / 1000.0
	if phone:
		var body := MeshInstance3D.new()
		body.mesh = MeshFactory.chamfer_box(d, minf(d.y * 0.4, 0.003))
		body.material_override = mat(Color(0.2, 0.21, 0.24), 0.85, 0.35)
		n.add_child(body)
		n.add_child(_box(Vector3(d.x - 0.004, 0.0004, d.z - 0.004), mat(Color(0.02, 0.02, 0.025), 0.0, 0.1), Vector3(0, d.y * 0.5 + 0.0002, 0)))
		n.add_child(_box(Vector3(0.028, 0.0015, 0.028), mat(Color(0.07, 0.07, 0.08), 0.4, 0.3), Vector3(d.x * 0.36, -d.y * 0.5 - 0.0007, d.z * 0.26)))
		n.add_child(_cyl(0.0055, 0.0018, mat(Color(0.01, 0.01, 0.02), 0.2, 0.05), Vector3(d.x * 0.36, -d.y * 0.5 - 0.0012, d.z * 0.26)))
	else:
		var panel_t := minf(0.003, d.y * 0.5)
		n.add_child(_box(Vector3(d.x, panel_t, d.z), mat(Color(0.06, 0.06, 0.065), 0.3, 0.4), Vector3(0, d.y * 0.5 - panel_t * 0.5, 0)))
		var pcb := MeshInstance3D.new()
		pcb.mesh = MeshFactory.chamfer_box(Vector3(d.x * 0.5, 0.0016, d.z * 0.62))
		pcb.material_override = MaterialLibrary.get_visual("baquelita")
		pcb.position = Vector3(d.x * 0.2, d.y * 0.5 - panel_t - 0.0012, -d.z * 0.08)
		n.add_child(pcb)
		var metal := mat(Color(0.75, 0.76, 0.78), 1.0, 0.3)
		n.add_child(_box(Vector3(0.011, 0.0045, 0.015), metal, Vector3(d.x * 0.4, -d.y * 0.5 + 0.00225, d.z * 0.12)))
		n.add_child(_box(Vector3(0.008, 0.0028, 0.012), metal, Vector3(d.x * 0.4, -d.y * 0.5 + 0.0014, -d.z * 0.12)))
		n.add_child(_box(Vector3(0.02, 0.0004, 0.03), mat(Color(0.75, 0.45, 0.1), 0.2, 0.5), Vector3(-d.x * 0.1, d.y * 0.5 - panel_t - 0.0002, 0)))
	var glass := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(aw, ah)
	glass.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.015, 0.015, 0.02)
	# Acabado antirreflejo: con mucho especular el estudio se reflejaba y lavaba la imagen.
	gm.roughness = 0.3
	gm.metallic_specular = 0.15
	gm.emission_enabled = true
	gm.emission = Color(1, 1, 1)
	# Color × textura (por defecto Godot los suma y la imagen salía lavada en blanco).
	gm.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	gm.emission_texture = sbs_pattern()
	gm.emission_energy_multiplier = 1.0 if phone else 0.0
	glass.material_override = gm
	# El PlaneMesh pone la u de la textura hacia +X y la v hacia +Z; para el espectador
	# (derecha en −X, arriba en +Z) la imagen saldría girada: medio giro sobre la normal.
	glass.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0, d.y * 0.5 + (0.0005 if phone else 0.0002), 0))
	glass.set_meta("pantalla_luz", true)
	n.add_child(glass)
	return n

## Cabeza de prueba: maniquí impreso (elipsoide) con la cara hacia +X, nariz,
## orejas y la posición de los ojos marcada (donde caen los ojos del visor).
static func _head(d: Vector3, def: Dictionary) -> Node3D:
	var n := Node3D.new()
	var skin := mat(Color(0.78, 0.76, 0.73), 0.0, 0.7)
	var skull := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 48
	sm.rings = 24
	skull.mesh = sm
	skull.scale = d
	skull.material_override = skin
	n.add_child(skull)
	var a := d * 0.5
	var eyes: Dictionary = def.get("ojos_mm", {"x": 84, "y": 10, "ipd": 63})
	var ex := float(eyes.get("x", 84)) / 1000.0
	var ey := float(eyes.get("y", 10)) / 1000.0
	var half_ipd := float(eyes.get("ipd", 63)) / 2000.0
	var dark := mat(Color(0.12, 0.12, 0.14), 0.0, 0.4)
	for z in [half_ipd, -half_ipd]:
		var eye := MeshInstance3D.new()
		var es := SphereMesh.new()
		es.radius = 0.011
		es.height = 0.022
		eye.mesh = es
		eye.material_override = dark
		eye.position = Vector3(ex, ey, z)
		n.add_child(eye)
	# Nariz: cuña bajo los ojos.
	var nose := _box(Vector3(0.026, 0.034, 0.02), skin, Vector3(a.x * 0.93, ey - 0.03, 0))
	nose.rotation = Vector3(0, 0, deg_to_rad(-18))
	n.add_child(nose)
	# Orejas.
	for z in [a.z, -a.z]:
		var ear := _cyl(0.022, 0.012, skin, Vector3(-0.01, ey - 0.01, z))
		ear.rotation = Vector3(PI / 2.0, 0, 0)
		ear.scale = Vector3(0.75, 1.0, 1.3)
		n.add_child(ear)
	return n

## ESP32 DevKitC: placa negra, módulo ESP-WROOM-32 con blindaje y antena, dos tiras
## de pines a lo largo, micro USB, botones EN/BOOT y LED rojo de encendido.
static func _esp32(d: Vector3) -> Node3D:
	var n := Node3D.new()
	var t := 0.0016
	var y0 := -d.y * 0.5
	var board := MeshInstance3D.new()
	board.mesh = MeshFactory.chamfer_box(Vector3(d.x, t, d.z), t * 0.3)
	board.material_override = mat(Color(0.05, 0.05, 0.06), 0.0, 0.5)
	board.position = Vector3(0, y0 + t * 0.5 + 0.0025, 0)
	n.add_child(board)
	var top := y0 + t + 0.0025
	var metal := mat(Color(0.78, 0.79, 0.81), 1.0, 0.25)
	n.add_child(_box(Vector3(0.018, 0.0032, 0.016), metal, Vector3(d.x * 0.5 - 0.0155, top + 0.0016, 0)))
	n.add_child(_box(Vector3(0.0065, 0.0008, 0.018), mat(Color(0.08, 0.2, 0.12), 0.0, 0.5), Vector3(d.x * 0.5 - 0.0032, top + 0.0004, 0)))
	n.add_child(_box(Vector3(0.006, 0.003, 0.008), metal, Vector3(-d.x * 0.5 + 0.0028, top + 0.0015, 0)))
	var black := mat(Color(0.03, 0.03, 0.035), 0.0, 0.6)
	var gold := mat(Color(0.85, 0.68, 0.25), 0.95, 0.3)
	for sz: float in [-1.0, 1.0]:
		n.add_child(_box(Vector3(0.00254 * 19, 0.0025, 0.0025), black, Vector3(0, y0 + 0.00125, sz * 0.0127)))
		for i in range(19):
			n.add_child(_box(Vector3(0.00064, 0.0085, 0.00064), gold, Vector3(-0.02286 + 0.00254 * i, y0 + 0.00425, sz * 0.0127)))
	for bx: float in [-0.012, -0.004]:
		n.add_child(_box(Vector3(0.004, 0.0015, 0.003), black, Vector3(bx - d.x * 0.25, top + 0.00075, d.z * 0.3)))
	var led := mat(Color(1.0, 0.15, 0.1), 0.0, 0.3, true)
	led.emission_energy_multiplier = 3.0
	n.add_child(_box(Vector3(0.0016, 0.0008, 0.0008), led, Vector3(-d.x * 0.3, top + 0.0004, -d.z * 0.3)))
	return n

static func _pcb(d: Vector3, def: Dictionary) -> Node3D:
	var n := Node3D.new()
	# Placa FR4 de 1.6 mm apoyada abajo (el resto de la altura son componentes).
	var t := minf(0.0016, d.y * 0.5)
	var y0 := -d.y * 0.5
	var board := MeshInstance3D.new()
	board.mesh = MeshFactory.chamfer_box(Vector3(d.x, t, d.z), t * 0.3)
	board.material_override = MaterialLibrary.get_visual("baquelita")
	board.position = Vector3(0, y0 + t * 0.5, 0)
	n.add_child(board)
	var top := y0 + t
	# Chip (QFP/DIP) con patas.
	var chip := mat(Color(0.04, 0.04, 0.045), 0.1, 0.35)
	var ch := Vector3(d.x * 0.3, minf(0.003, d.y * 0.3), d.z * 0.3)
	n.add_child(_box(ch, chip, Vector3(-d.x * 0.05, top + ch.y * 0.5, 0)))
	var tin := MaterialLibrary.get_visual("estano")
	for i in range(8):
		var z := -ch.z * 0.4 + ch.z * 0.8 * i / 7.0
		for sx: float in [-1.0, 1.0]:
			n.add_child(_box(Vector3(0.0012, 0.0006, 0.0005), tin, Vector3(-d.x * 0.05 + sx * (ch.x * 0.5 + 0.0005), top + 0.0003, z)))
	# Tira de pines macho: plástico negro + pines dorados verticales hasta arriba.
	var gold := mat(Color(0.85, 0.68, 0.25), 0.95, 0.3)
	var black := mat(Color(0.03, 0.03, 0.035), 0.0, 0.6)
	var pins: int = int(clamp(d.z / 0.00254, 4, 20))
	var hx := d.x * 0.5 - 0.003
	n.add_child(_box(Vector3(0.0025, 0.0025, 0.00254 * pins), black, Vector3(hx, top + 0.00125, 0)))
	var pin_h := maxf(0.004, (d.y * 0.5) - top)
	var solder := MaterialLibrary.get_visual("estano")
	for i in range(pins):
		var z := -0.00254 * (pins - 1) * 0.5 + 0.00254 * i
		n.add_child(_box(Vector3(0.00064, pin_h, 0.00064), gold, Vector3(hx, top + pin_h * 0.5, z)))
		# Punto de soldadura brillante en la cara inferior.
		var blob := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.0009; sm.height = 0.0011
		blob.mesh = sm
		blob.material_override = solder
		blob.position = Vector3(hx, y0 - 0.0002, z)
		n.add_child(blob)
	# Condensador electrolítico y cristal.
	var cap := mat(Color(0.1, 0.14, 0.4), 0.3, 0.35)
	var cap_h := minf(0.008, d.y - t)
	n.add_child(_cyl(minf(0.0035, d.x * 0.06), cap_h, cap, Vector3(-d.x * 0.32, top + cap_h * 0.5, d.z * 0.25)))
	n.add_child(_box(Vector3(0.004, 0.0015, 0.0018), mat(Color(0.75, 0.76, 0.78), 1.0, 0.25), Vector3(-d.x * 0.3, top + 0.00075, -d.z * 0.25)))
	# LED de encendido (emisivo: produce bloom).
	var led := mat(Color(0.2, 1.0, 0.3), 0.0, 0.3, true)
	led.emission_energy_multiplier = 4.0
	n.add_child(_box(Vector3(0.0016, 0.0008, 0.0008), led, Vector3(d.x * 0.2, top + 0.0004, -d.z * 0.35)))
	return n

static func _led(d: Vector3) -> Node3D:
	var n := Node3D.new()
	var r := d.x * 0.5
	var col := Color(0.95, 0.2, 0.2, 0.7)
	var body := mat(col, 0.0, 0.15, true)
	body.emission_energy_multiplier = 3.0
	# Cuerpo cilíndrico + cúpula.
	n.add_child(_cyl(r, d.y * 0.6, body, Vector3(0, -d.y * 0.1, 0)))
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = r; sm.height = r * 2.0
	dome.mesh = sm; dome.material_override = body
	dome.position = Vector3(0, d.y * 0.2, 0); dome.scale.y = 0.8
	n.add_child(dome)
	# Patas.
	var leg := mat(Color(0.75, 0.75, 0.78), 1.0, 0.3)
	n.add_child(_cyl(r * 0.12, d.y * 1.2, leg, Vector3(r * 0.4, -d.y * 0.7, 0), 6))
	n.add_child(_cyl(r * 0.12, d.y * 0.9, leg, Vector3(-r * 0.4, -d.y * 0.55, 0), 6))
	return n

static func _motor(d: Vector3) -> Node3D:
	var n := Node3D.new()
	var r := d.x * 0.5
	var steel := MaterialLibrary.get_visual("acero_inox")
	n.add_child(_cyl(r, d.y, steel, Vector3.ZERO, 32))
	# Tapa frontal.
	var cap := mat(Color(0.3, 0.31, 0.34), 0.8, 0.4)
	n.add_child(_cyl(r * 1.02, d.y * 0.12, cap, Vector3(0, d.y * 0.5, 0)))
	# Eje.
	var shaft := mat(Color(0.8, 0.8, 0.82), 1.0, 0.2)
	n.add_child(_cyl(r * 0.14, d.y * 0.5, shaft, Vector3(0, d.y * 0.72, 0), 10))
	return n

static func _resistor(d: Vector3) -> Node3D:
	var n := Node3D.new()
	# Cuerpo beige a lo largo de X.
	var body := mat(Color(0.82, 0.72, 0.5), 0.0, 0.5)
	var c := _cyl(d.y * 0.42, d.x * 0.6, body, Vector3.ZERO)
	c.rotation_degrees = Vector3(0, 0, 90)
	n.add_child(c)
	# Bandas de color.
	var bands := [Color(0.4, 0.25, 0.1), Color(0.1, 0.1, 0.1), Color(0.8, 0.1, 0.1), Color(0.85, 0.68, 0.25)]
	for i in range(bands.size()):
		var bx := -d.x * 0.18 + i * d.x * 0.12
		var band := _cyl(d.y * 0.45, d.x * 0.04, mat(bands[i], 0.1, 0.4), Vector3(bx, 0, 0))
		band.rotation_degrees = Vector3(0, 0, 90)
		n.add_child(band)
	# Patas metálicas.
	var leg := mat(Color(0.75, 0.75, 0.78), 1.0, 0.3)
	n.add_child(_leg_x(d, leg, 1))
	n.add_child(_leg_x(d, leg, -1))
	return n

static func _leg_x(d: Vector3, material: StandardMaterial3D, sign: int) -> MeshInstance3D:
	var leg := _cyl(d.y * 0.06, d.x * 0.35, material, Vector3(sign * d.x * 0.42, 0, 0), 6)
	leg.rotation_degrees = Vector3(0, 0, 90)
	return leg

static func _servo(d: Vector3) -> Node3D:
	var n := Node3D.new()
	var blue := mat(Color(0.12, 0.28, 0.65), 0.1, 0.5)
	n.add_child(_box(d, blue))
	# Horn.
	var white := mat(Color(0.9, 0.9, 0.92), 0.0, 0.5)
	n.add_child(_cyl(d.x * 0.18, d.y * 0.1, white, Vector3(0, d.y * 0.55, d.z * 0.25)))
	return n

static func _battery_box(d: Vector3) -> Node3D:
	var n := Node3D.new()
	n.add_child(_box(d, tex("Plastic006", Color(0.55, 0.57, 0.62), 25.0)))
	# Etiqueta.
	n.add_child(_box(Vector3(d.x * 0.9, d.y * 0.02, d.z * 0.5), mat(Color(0.85, 0.75, 0.1), 0.0, 0.5), Vector3(0, d.y * 0.51, 0)))
	# Cables + / -.
	n.add_child(_cyl(d.z * 0.03, d.z * 0.4, mat(Color(0.8, 0.1, 0.1), 0, 0.5), Vector3(d.x * 0.5, d.y * 0.2, d.z * 0.2), 6))
	n.add_child(_cyl(d.z * 0.03, d.z * 0.4, mat(Color(0.05, 0.05, 0.06), 0, 0.5), Vector3(d.x * 0.5, d.y * 0.2, -d.z * 0.2), 6))
	return n

static func _battery_cyl(d: Vector3) -> Node3D:
	var n := Node3D.new()
	var r := d.x * 0.5
	n.add_child(_cyl(r, d.y, mat(Color(0.15, 0.4, 0.7), 0.2, 0.45)))
	# Terminal positivo.
	n.add_child(_cyl(r * 0.35, d.y * 0.06, mat(Color(0.8, 0.8, 0.82), 1.0, 0.3), Vector3(0, d.y * 0.52, 0)))
	return n

static func _protoboard(d: Vector3) -> Node3D:
	var n := Node3D.new()
	var board := MeshInstance3D.new()
	var b := BoxMesh.new(); b.size = d
	board.mesh = b
	var shader := load("res://rendering/protoboard.gdshader")
	if shader:
		var sm := ShaderMaterial.new(); sm.shader = shader
		sm.set_shader_parameter("half_xz", Vector2(d.x * 0.5, d.z * 0.5))
		board.material_override = sm
	else:
		board.material_override = mat(Color(0.9, 0.9, 0.88), 0.0, 0.6)
	n.add_child(board)
	# Serigrafía: números de columna (1, 5, 10… 60) y letras de fila a–j.
	var yt := d.y * 0.5 + 0.00005
	var lbl_col := Color(0.35, 0.35, 0.38)
	var cols := [0]
	for c in range(4, PartInstance.BB_COLS, 5):
		cols.append(c)
	for c in cols:
		var x := PartInstance.bb_column_x(c) / 1000.0
		for zs: float in [1.0, -1.0]:
			n.add_child(_flat_label(str(c + 1), Vector3(x, yt, zs * 0.0163), lbl_col, zs < 0.0))
	var letters := ["e", "d", "c", "b", "a"]
	var letters_b := ["f", "g", "h", "i", "j"]
	for r in range(5):
		for xs: float in [-1.0, 1.0]:
			var x := xs * (PartInstance.bb_column_x(62) / 1000.0 + 0.0028)
			n.add_child(_flat_label(letters[r], Vector3(x, yt, PartInstance.bb_row_z(true, r) / 1000.0), lbl_col, false))
			n.add_child(_flat_label(letters_b[r], Vector3(x, yt, PartInstance.bb_row_z(false, r) / 1000.0), lbl_col, false))
	return n

## Texto impreso plano sobre la cara superior de una pieza.
static func _flat_label(t: String, pos: Vector3, col: Color, flip: bool) -> Label3D:
	var l := Label3D.new()
	l.text = t
	l.pixel_size = 0.00006
	l.font_size = 24
	l.outline_size = 0
	l.modulate = col
	l.double_sided = false
	l.shaded = true
	l.position = pos
	l.rotation = Vector3(-PI / 2.0, PI if flip else 0.0, 0.0)
	return l

static func _sensor_ultra(d: Vector3) -> Node3D:
	var n := Node3D.new()
	n.add_child(_box(d, mat(Color(0.1, 0.1, 0.12), 0.1, 0.5)))
	# Dos "ojos".
	var eye := mat(Color(0.5, 0.5, 0.55), 0.6, 0.3)
	n.add_child(_eye(d, eye, 1))
	n.add_child(_eye(d, eye, -1))
	return n

static func _eye(d: Vector3, material: StandardMaterial3D, sign: int) -> MeshInstance3D:
	var e := _cyl(d.z * 0.32, d.x * 0.2, material, Vector3(d.x * 0.5, 0, sign * d.z * 0.28))
	e.rotation_degrees = Vector3(0, 0, 90)
	return e

static func _button(d: Vector3) -> Node3D:
	var n := Node3D.new()
	n.add_child(_box(d, mat(Color(0.15, 0.16, 0.18), 0.2, 0.45)))
	n.add_child(_cyl(d.x * 0.22, d.y * 0.5, mat(Color(0.85, 0.2, 0.2), 0.1, 0.4), Vector3(0, d.y * 0.6, 0)))
	return n

static func _pot(d: Vector3) -> Node3D:
	var n := Node3D.new()
	n.add_child(_box(Vector3(d.x, d.y * 0.5, d.z), mat(Color(0.15, 0.16, 0.2), 0.3, 0.4), Vector3(0, -d.y * 0.25, 0)))
	n.add_child(_cyl(d.x * 0.28, d.y * 0.6, mat(Color(0.75, 0.76, 0.8), 0.9, 0.3), Vector3(0, d.y * 0.2, 0)))
	n.add_child(_cyl(d.x * 0.08, d.y * 0.3, mat(Color(0.1, 0.1, 0.1), 0.2, 0.5), Vector3(0, d.y * 0.6, 0), 8))
	return n

static func _limit_switch(d: Vector3) -> Node3D:
	var n := Node3D.new()
	n.add_child(_box(d, mat(Color(0.08, 0.08, 0.09), 0.1, 0.5)))
	# Palanca metálica con rodillo.
	var steel := MaterialLibrary.get_visual("acero_inox")
	var lever := _box(Vector3(d.x * 0.9, d.y * 0.08, d.z * 0.5), steel, Vector3(d.x * 0.05, d.y * 0.62, 0))
	lever.rotation_degrees = Vector3(0, 0, 8)
	n.add_child(lever)
	var roll := _cyl(d.y * 0.15, d.z * 0.5, mat(Color(0.85, 0.85, 0.86), 0.2, 0.4), Vector3(d.x * 0.48, d.y * 0.72, 0))
	roll.rotation_degrees = Vector3(90, 0, 0)
	n.add_child(roll)
	n.add_child(_box(Vector3(d.x * 0.12, d.y * 0.1, d.z * 0.3), mat(Color(0.8, 0.1, 0.1), 0.1, 0.4), Vector3(-d.x * 0.3, d.y * 0.55, 0)))
	return n

static func _fsr(d: Vector3) -> Node3D:
	var n := Node3D.new()
	var r := d.x * 0.5
	n.add_child(_cyl(r, d.y, mat(Color(0.12, 0.12, 0.14), 0.1, 0.35)))
	n.add_child(_cyl(r * 0.8, d.y * 1.05, mat(Color(0.75, 0.6, 0.3), 0.6, 0.35)))
	var tail := _box(Vector3(r * 0.5, d.y * 0.6, r * 1.6), mat(Color(0.75, 0.6, 0.3), 0.6, 0.35), Vector3(0, 0, -r * 1.2))
	n.add_child(tail)
	return n

static func _lidar(d: Vector3) -> Node3D:
	var n := Node3D.new()
	var r := d.x * 0.5
	n.add_child(_cyl(r, d.y * 0.45, mat(Color(0.1, 0.1, 0.11), 0.2, 0.45), Vector3(0, -d.y * 0.275, 0), 32))
	n.add_child(_cyl(r * 0.78, d.y * 0.5, mat(Color(0.15, 0.15, 0.17), 0.3, 0.3), Vector3(0, d.y * 0.2, 0), 32))
	# Ventana óptica (negra brillante) y emisor rojo tenue.
	var win := _box(Vector3(r * 0.25, d.y * 0.22, r * 0.9), mat(Color(0.02, 0.02, 0.03), 0.0, 0.05), Vector3(r * 0.72, d.y * 0.2, 0))
	n.add_child(win)
	var emit := mat(Color(1.0, 0.15, 0.1), 0.0, 0.3, true)
	emit.emission_energy_multiplier = 2.5
	n.add_child(_box(Vector3(r * 0.05, d.y * 0.04, r * 0.1), emit, Vector3(r * 0.86, d.y * 0.2, 0)))
	return n

static func _wheel(d: Vector3) -> Node3D:
	var n := Node3D.new()
	var r := d.x * 0.5
	# Neumático de caucho con banda de rodadura, llanta de aluminio y cubo.
	var tire := MeshInstance3D.new()
	tire.mesh = MeshFactory.tube(r, r * 0.68, d.y, 48)
	tire.material_override = MaterialLibrary.get_visual("caucho")
	n.add_child(tire)
	for k in range(24):
		var ang := TAU * k / 24.0
		var tread := _box(Vector3(r * 0.08, d.y * 0.9, r * 0.05), MaterialLibrary.get_visual("caucho"),
			Vector3(cos(ang) * r * 0.99, 0, sin(ang) * r * 0.99))
		tread.rotation.y = -ang
		n.add_child(tread)
	var rim := MeshInstance3D.new()
	rim.mesh = MeshFactory.tube(r * 0.69, r * 0.22, d.y * 0.7, 40)
	rim.material_override = MaterialLibrary.get_visual("aluminio")
	n.add_child(rim)
	n.add_child(_cyl(r * 0.22, d.y * 0.95, tex("Metal009", Color(0.55, 0.55, 0.58), 30.0, {"metallic": 1.0}), Vector3.ZERO, 16))
	return n

static func _line_sensor(d: Vector3) -> Node3D:
	var n := Node3D.new()
	var board := _box(Vector3(d.x, d.y * 0.25, d.z), null, Vector3(0, d.y * 0.3, 0))
	board.material_override = MaterialLibrary.get_visual("baquelita")
	n.add_child(board)
	# Emisor (azul) y receptor (negro) del TCRT5000 mirando al suelo.
	n.add_child(_cyl(d.z * 0.2, d.y * 0.6, mat(Color(0.2, 0.3, 0.8), 0.0, 0.2), Vector3(-d.x * 0.15, -d.y * 0.15, 0)))
	n.add_child(_cyl(d.z * 0.2, d.y * 0.6, mat(Color(0.03, 0.03, 0.04), 0.0, 0.2), Vector3(d.x * 0.15, -d.y * 0.15, 0)))
	var led := mat(Color(1.0, 0.2, 0.1), 0.0, 0.3, true)
	led.emission_energy_multiplier = 3.0
	n.add_child(_box(Vector3(d.x * 0.08, d.y * 0.1, d.z * 0.12), led, Vector3(d.x * 0.35, d.y * 0.45, 0)))
	return n
