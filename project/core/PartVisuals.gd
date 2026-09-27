class_name PartVisuals
extends RefCounted
## PartVisuals — Construye el aspecto detallado de las piezas.
##
## En vez de una caja/cilindro plano, arma un pequeño conjunto de mallas con
## materiales realistas para que cada componente se reconozca (placa PCB con
## chip y pines, LED con cúpula y patas, motor con eje, protoboard, etc.).
## Devuelve un Node3D con las mallas, o null para usar la malla por defecto.

static func mat(color: Color, metallic := 0.0, roughness := 0.6, emissive := false) -> StandardMaterial3D:
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
		"led": return _led(d)
		"motor": return _motor(d)
		"resistencia": return _resistor(d)
		"servo": return _servo(d)
		"bateria_caja": return _battery_box(d)
		"bateria_cil": return _battery_cyl(d)
		"protoboard": return _protoboard(d)
		"sensor_ultra": return _sensor_ultra(d)
		"boton": return _button(d)
		"potenciometro": return _pot(d)
		_: return null

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
	n.add_child(_box(d, mat(Color(0.12, 0.13, 0.16), 0.1, 0.55)))
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
	return n

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
