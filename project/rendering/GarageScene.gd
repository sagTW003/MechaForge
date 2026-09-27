class_name GarageScene
extends Node3D
## GarageScene — Cochera doméstica para probar las construcciones.
##
## Nave de 7 × 7 m y 2.8 m de alto con el portón (+Z) abierto hacia la entrada de
## coches; fuera se ve el HDRI real «Preller Drive» (Poly Haven, CC0). Dentro:
## banco de trabajo con panel de herramientas, estantería metálica con cajas,
## pila de neumáticos, gabinete de herramientas, lámparas fluorescentes y, en la
## zona de pruebas, una rampa, un tope de aparcamiento y conos.
##
## Todo lo sólido tiene colisión (capa del mundo): los vehículos y mecanismos
## simulados chocan con las paredes, suben la rampa o empujan los conos (fijos).
## Paredes y techo son de una sola cara vista desde dentro, así que la cámara
## puede alejarse y ver a través de ellos; las sombras sí son de doble cara, de
## modo que el sol solo entra por el portón.
##
## Texturas fotográficas ambientCG (CC0): hormigón, yeso pintado, madera, acero
## corrugado, metal desgastado, cartón y caucho.

const W := 7.0          # ancho (X)
const Z_BACK := -4.0    # pared del fondo
const Z_FRONT := 3.0    # pared del portón
const H := 2.8          # altura
const DOOR_W := 2.9
const DOOR_H := 2.3
const WORLD_LAYER := 1

var lamps: Array = []   # OmniLight3D del techo

func _ready() -> void:
	_build()

func _m(id: String, tint: Color, scale: float, extra: Dictionary = {}) -> Material:
	var o := {"tint": tint, "scale": scale}
	o.merge(extra, true)
	var m := TextureSets.material(id, o)
	if m == null:
		var f := StandardMaterial3D.new()
		f.albedo_color = tint
		return f
	return m

## Caja visible (y con colisión si "solid"). "inward": normal visible hacia dentro.
func _box(size: Vector3, pos: Vector3, mat: Material, solid := true, rot := Vector3.ZERO, one_sided := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	if one_sided:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	add_child(mi)
	if solid:
		_collider(BoxShape3D.new(), size, pos, rot)
	return mi

func _collider(shape: Shape3D, size: Vector3, pos: Vector3, rot := Vector3.ZERO) -> void:
	if shape is BoxShape3D:
		(shape as BoxShape3D).size = size
	var body := StaticBody3D.new()
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.position = pos
	body.rotation = rot
	var pm := PhysicsMaterial.new()
	pm.friction = 0.8
	body.physics_material_override = pm
	add_child(body)

## Plano de una cara (pared/techo) mirando en dirección "normal".
func _panel(size: Vector2, center: Vector3, normal: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	# PlaneMesh mira a +Y: se orienta hacia "normal".
	mi.basis = Basis(Quaternion(Vector3.UP, normal.normalized())) if absf(normal.normalized().dot(Vector3.UP)) < 0.999 else (Basis.IDENTITY if normal.y > 0 else Basis(Vector3.RIGHT, PI))
	mi.position = center
	add_child(mi)

func _build() -> void:
	var hw := W * 0.5
	var depth := Z_FRONT - Z_BACK
	var zc := (Z_FRONT + Z_BACK) * 0.5
	var plaster := _m("PaintedPlaster017", Color(0.93, 0.91, 0.86), 0.6)
	var ceiling := _m("Plaster003", Color(0.85, 0.85, 0.83), 0.5)
	# --- Paredes (una cara visible desde dentro) + colisión gruesa ---
	_panel(Vector2(W, H), Vector3(0, H * 0.5, Z_BACK), Vector3.BACK, plaster)
	# Al girar el plano hacia ±X su eje X local pasa a ser vertical: tamaño (alto, fondo).
	_panel(Vector2(H, depth), Vector3(-hw, H * 0.5, zc), Vector3.RIGHT, plaster)
	_panel(Vector2(H, depth), Vector3(hw, H * 0.5, zc), Vector3.LEFT, plaster)
	var side_w := (W - DOOR_W) * 0.5
	for sx: float in [-1.0, 1.0]:
		_panel(Vector2(side_w, H), Vector3(sx * (hw - side_w * 0.5), H * 0.5, Z_FRONT), Vector3.FORWARD, plaster)
	_panel(Vector2(DOOR_W, H - DOOR_H), Vector3(0, DOOR_H + (H - DOOR_H) * 0.5, Z_FRONT), Vector3.FORWARD, plaster)
	_panel(Vector2(W, depth), Vector3(0, H, zc), Vector3.DOWN, ceiling)
	for c in [[Vector3(W, H, 0.2), Vector3(0, H * 0.5, Z_BACK - 0.1)],
			[Vector3(0.2, H, depth), Vector3(-hw - 0.1, H * 0.5, zc)],
			[Vector3(0.2, H, depth), Vector3(hw + 0.1, H * 0.5, zc)],
			[Vector3(side_w, H, 0.2), Vector3(-(hw - side_w * 0.5), H * 0.5, Z_FRONT + 0.1)],
			[Vector3(side_w, H, 0.2), Vector3(hw - side_w * 0.5, H * 0.5, Z_FRONT + 0.1)]]:
		_collider(BoxShape3D.new(), c[0], c[1])
	# Rodapié y marco del portón.
	var trim := _m("Metal055A", Color(0.35, 0.36, 0.38), 3.0)
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(0.08, DOOR_H, 0.12), Vector3(sx * (DOOR_W * 0.5 + 0.04), DOOR_H * 0.5, Z_FRONT), trim, false)
	_box(Vector3(DOOR_W + 0.16, 0.08, 0.12), Vector3(0, DOOR_H + 0.04, Z_FRONT), trim, false)
	# Portón seccional enrollado bajo el techo (acero corrugado).
	var door := _m("CorrugatedSteel009", Color(0.9, 0.9, 0.92), 1.2)
	_box(Vector3(DOOR_W, 0.04, 2.2), Vector3(0, H - 0.2, Z_FRONT - 1.15), door, false)
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(0.05, 0.05, 2.4), Vector3(sx * (DOOR_W * 0.5 - 0.05), H - 0.12, Z_FRONT - 1.2), trim, false)

	_workbench(hw)
	_shelving(hw)
	_tool_cabinet(hw)
	_tires(hw)
	_test_props()
	_lamps(hw, zc)
	# Sonda de reflejos de la nave: los metales reflejan paredes, luces y portón
	# (sin ella solo "verían" el cielo, que aquí dentro está tapado).
	var probe := ReflectionProbe.new()
	probe.size = Vector3(W, H, Z_FRONT - Z_BACK) + Vector3(0.2, 0.2, 0.2)
	probe.position = Vector3(0, H * 0.5, zc)
	probe.box_projection = true
	probe.interior = false
	probe.enable_shadows = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.intensity = 1.0
	add_child(probe)

## Banco de trabajo de madera en la pared del fondo, con panel perforado y herramientas.
func _workbench(hw: float) -> void:
	var wood := _m("Wood066", Color.WHITE, 2.5)
	var steel := _m("Metal055A", Color(0.45, 0.47, 0.5), 3.0)
	var x0 := -0.6
	var z := Z_BACK + 0.38
	_box(Vector3(2.4, 0.05, 0.7), Vector3(x0, 0.9, z), wood)
	_box(Vector3(2.3, 0.03, 0.6), Vector3(x0, 0.25, z), wood)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_box(Vector3(0.05, 0.88, 0.05), Vector3(x0 + sx * 1.13, 0.44, z + sz * 0.3), steel)
	# Panel de herramientas (tablero perforado) y siluetas de herramientas.
	var peg := _m("Cardboard004", Color(0.75, 0.62, 0.45), 2.0)
	_box(Vector3(2.2, 1.0, 0.02), Vector3(x0, 1.55, Z_BACK + 0.02), peg, false)
	var tool := _m("Metal011", Color(0.7, 0.72, 0.75), 20.0, {"metallic": 1.0})
	var red := _m("Plastic013A", Color(0.75, 0.1, 0.08), 30.0)
	for i in range(7):
		var tx := x0 - 0.9 + i * 0.3
		_box(Vector3(0.03, 0.28 + (i % 3) * 0.06, 0.015), Vector3(tx, 1.5, Z_BACK + 0.04), tool, false, Vector3(0, 0, 0.15 * (i % 2)))
		_box(Vector3(0.05, 0.1, 0.03), Vector3(tx, 1.32, Z_BACK + 0.045), red if i % 2 == 0 else steel, false)
	# Tornillo de banco.
	_box(Vector3(0.18, 0.12, 0.2), Vector3(x0 + 1.0, 0.99, z + 0.22), steel, false)

## Estantería metálica con cajas de cartón (pared izquierda).
func _shelving(hw: float) -> void:
	var steel := _m("Metal055A", Color(0.55, 0.57, 0.6), 3.0)
	var card := _m("Cardboard004", Color.WHITE, 2.5)
	var x := -hw + 0.3
	var z0 := -2.4
	for sz: float in [-1.0, 1.0]:
		for sx: float in [-1.0, 1.0]:
			_box(Vector3(0.04, 1.9, 0.04), Vector3(x + sx * 0.25, 0.95, z0 + sz * 0.85), steel)
	for i in range(4):
		var y := 0.15 + i * 0.55
		_box(Vector3(0.52, 0.025, 1.74), Vector3(x, y, z0), steel)
		for k in range(3):
			if (i + k) % 4 == 3:
				continue
			var bs := Vector3(0.4, 0.22 + 0.06 * ((i + k) % 2), 0.45)
			_box(bs, Vector3(x + 0.02, y + 0.0125 + bs.y * 0.5, z0 - 0.55 + k * 0.55), card)

## Gabinete de herramientas rojo con cajones (pared derecha).
func _tool_cabinet(hw: float) -> void:
	var red := _m("Metal055A", Color(0.75, 0.12, 0.1), 3.0)
	var steel := _m("Metal011", Color(0.8, 0.8, 0.82), 20.0, {"metallic": 1.0})
	var x := hw - 0.3
	var z := -2.6
	_box(Vector3(0.55, 1.0, 0.9), Vector3(x, 0.5, z), red)
	for i in range(5):
		_box(Vector3(0.01, 0.015, 0.4), Vector3(x - 0.28, 0.2 + i * 0.17, z), steel, false)

## Pila de neumáticos junto a la estantería.
func _tires(hw: float) -> void:
	var rubber := _m("Rubber004", Color(0.8, 0.8, 0.82), 6.0)
	for i in range(3):
		var mi := MeshInstance3D.new()
		mi.mesh = MeshFactory.tube(0.32, 0.19, 0.2, 40)
		mi.material_override = rubber
		mi.position = Vector3(-hw + 0.45, 0.1 + i * 0.205, -0.7)
		add_child(mi)
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.32
	cyl.height = 0.62
	_collider(cyl, Vector3.ZERO, Vector3(-hw + 0.45, 0.31, -0.7))

## Zona de pruebas: rampa de madera, tope de aparcamiento y conos.
func _test_props() -> void:
	var wood := _m("Wood066", Color(0.9, 0.85, 0.8), 3.0)
	# Rampa de 12° (1.0 m de largo, 0.6 m de ancho) con colisión convexa.
	var ang := deg_to_rad(12.0)
	var L := 1.0
	var hgt := L * tan(ang)
	var pts := PackedVector3Array([
		Vector3(-0.3, 0, 0), Vector3(0.3, 0, 0), Vector3(-0.3, 0, -L), Vector3(0.3, 0, -L),
		Vector3(-0.3, hgt, -L), Vector3(0.3, hgt, -L)])
	var ramp_pos := Vector3(1.8, 0, 1.6)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := [[0, 1, 5, 4], [2, 3, 5, 4], [0, 2, 3, 1]]
	for f in faces:
		var a: Vector3 = pts[f[0]]; var b: Vector3 = pts[f[1]]; var c: Vector3 = pts[f[2]]; var d: Vector3 = pts[f[3]]
		for tri in [[a, b, c], [a, c, d]]:
			var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
			for v in tri:
				st.set_normal(-n)
				st.add_vertex(v)
	for side in [[[0, 2, 4], Vector3.LEFT], [[1, 3, 5], Vector3.RIGHT]]:
		for v in side[0]:
			st.set_normal(side[1])
			st.add_vertex(pts[v])
	var ramp := MeshInstance3D.new()
	ramp.mesh = st.commit()
	if wood is BaseMaterial3D:
		(wood as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	ramp.material_override = wood
	ramp.position = ramp_pos
	add_child(ramp)
	var conv := ConvexPolygonShape3D.new()
	conv.points = pts
	_collider(conv, Vector3.ZERO, ramp_pos)
	# Tope de aparcamiento (caucho) al fondo de la zona de pruebas.
	var rubber := _m("Rubber004", Color(0.95, 0.85, 0.2), 8.0)
	_box(Vector3(1.2, 0.08, 0.14), Vector3(0, 0.04, -2.6), rubber)
	# Conos de tráfico (anclados, con colisión).
	var orange := _m("Plastic013A", Color(0.95, 0.35, 0.05), 20.0)
	for p in [Vector3(-1.4, 0, 1.4), Vector3(-1.9, 0, 0.6), Vector3(-1.4, 0, -0.2)]:
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.02
		cm.bottom_radius = 0.11
		cm.height = 0.45
		cone.mesh = cm
		cone.material_override = orange
		cone.position = p + Vector3(0, 0.245, 0)
		add_child(cone)
		_box(Vector3(0.3, 0.02, 0.3), p + Vector3(0, 0.01, 0), orange, false)
		var cs := CylinderShape3D.new()
		cs.radius = 0.08
		cs.height = 0.45
		_collider(cs, Vector3.ZERO, p + Vector3(0, 0.245, 0))

## Lámparas fluorescentes del techo (tubo emisivo + luz omni con sombras).
func _lamps(hw: float, zc: float) -> void:
	var housing := _m("Metal055A", Color(0.85, 0.85, 0.85), 4.0)
	var tube := StandardMaterial3D.new()
	tube.albedo_color = Color(1, 1, 0.97)
	tube.emission_enabled = true
	tube.emission = Color(1.0, 0.98, 0.93)
	tube.emission_energy_multiplier = 6.0
	for z in [-1.8, 0.6]:
		_box(Vector3(0.25, 0.06, 1.3), Vector3(0, H - 0.05, z), housing, false)
		_box(Vector3(0.06, 0.03, 1.22), Vector3(0, H - 0.09, z), tube, false)
		var l := OmniLight3D.new()
		l.position = Vector3(0, H - 0.3, z)
		l.omni_range = 6.0
		l.light_energy = 1.2
		l.light_color = Color(1.0, 0.97, 0.9)
		l.shadow_enabled = true
		l.omni_shadow_mode = OmniLight3D.SHADOW_CUBE
		add_child(l)
		lamps.append(l)

## Intensidad de las luces interiores (0 apagadas … 1 normal).
func set_lamps(k: float) -> void:
	for l in lamps:
		(l as OmniLight3D).light_energy = 1.2 * k
		(l as OmniLight3D).visible = k > 0.01
