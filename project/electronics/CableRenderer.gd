class_name CableRenderer
extends RefCounted
## CableRenderer — Construye la malla de un cable a partir de sus puntos.
##
## Tubo suave con aislamiento PVC (color por función: VCC rojo, GND negro, señal
## azul, o el elegido por el usuario), conectores tipo Dupont (carcasa negra y
## pin metálico) y, si el extremo está soldado, un menisco de estaño brillante.

const WIRE_COLORS := {
	"auto": Color(0, 0, 0, 0),
	"rojo": Color(0.8, 0.1, 0.08), "negro": Color(0.03, 0.03, 0.035), "azul": Color(0.1, 0.35, 0.85),
	"amarillo": Color(0.95, 0.75, 0.08), "verde": Color(0.1, 0.6, 0.2), "blanco": Color(0.88, 0.88, 0.86),
	"naranja": Color(0.95, 0.42, 0.06),
}

static var _insulation: Dictionary = {}
static var _housing: StandardMaterial3D
static var _pin: StandardMaterial3D

static func color_for(tipo: String, choice: String = "auto") -> Color:
	if choice != "auto" and WIRE_COLORS.has(choice):
		return WIRE_COLORS[choice]
	match tipo:
		"power": return WIRE_COLORS["rojo"]
		"gnd": return WIRE_COLORS["negro"]
		_: return WIRE_COLORS["azul"]

static func insulation(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if _insulation.has(key):
		return _insulation[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.38
	m.metallic = 0.0
	m.clearcoat_enabled = true           # brillo del PVC
	m.clearcoat = 0.3
	m.clearcoat_roughness = 0.25
	_insulation[key] = m
	return m

## Nodo del cable. solder_a/b: dibujar soldadura en ese extremo.
static func build(points: PackedVector3Array, color: Color, solder_a: bool = false, solder_b: bool = false) -> Node3D:
	var holder := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = tube_mesh(points, CableSim.RADIUS, 8)
	mi.material_override = insulation(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	holder.add_child(mi)
	if _housing == null:
		_housing = StandardMaterial3D.new()
		_housing.albedo_color = Color(0.04, 0.04, 0.045)
		_housing.roughness = 0.55
		_pin = StandardMaterial3D.new()
		_pin.albedo_color = Color(0.86, 0.7, 0.35)   # pin dorado
		_pin.metallic = 1.0
		_pin.roughness = 0.25
	var ends := [[points[0], solder_a], [points[points.size() - 1], solder_b]]
	for e in ends:
		var p: Vector3 = e[0]
		if e[1]:
			holder.add_child(solder_joint(p, 1.0))
		else:
			# Conector Dupont: carcasa sobre el terminal y pin que entra en él.
			var hc := MeshInstance3D.new()
			# Carcasa fina (1.6 mm) para que en la protoboard se vea en qué agujero entra.
			var hm := BoxMesh.new(); hm.size = Vector3(0.0016, 0.0045, 0.0016)
			hc.mesh = hm
			hc.material_override = _housing
			hc.position = p + Vector3(0, 0.0028, 0)
			holder.add_child(hc)
			var pc := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0003; cm.bottom_radius = 0.0003; cm.height = 0.0016; cm.radial_segments = 6
			pc.mesh = cm
			pc.material_override = _pin
			pc.position = p
			holder.add_child(pc)
	return holder

## Menisco de soldadura (estaño solidificado) en un punto.
static func solder_joint(p: Vector3, melt_done: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Soldadura"
	mi.mesh = MeshFactory.solder_fillet(0.0013, CableSim.RADIUS * 0.9, 0.0022)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://rendering/solder.gdshader")
	sm.set_shader_parameter("melt", 0.0)
	sm.set_shader_parameter("grow", melt_done)
	mi.material_override = sm
	mi.position = p
	return mi

## Tubo suave (normales por anillo) a lo largo de una polilínea.
static func tube_mesh(points: PackedVector3Array, radius: float, ring: int = 8) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n1_prev := Vector3.ZERO
	var rings := []
	var norms := []
	for i in range(points.size()):
		var tangent: Vector3
		if i == 0:
			tangent = points[1] - points[0]
		elif i == points.size() - 1:
			tangent = points[i] - points[i - 1]
		else:
			tangent = points[i + 1] - points[i - 1]
		tangent = tangent.normalized()
		# Marco con transporte paralelo (sin giros bruscos del tubo).
		var n1: Vector3
		if n1_prev == Vector3.ZERO:
			n1 = Vector3.UP.cross(tangent)
			if n1.length() < 0.01:
				n1 = Vector3.RIGHT.cross(tangent)
		else:
			n1 = n1_prev - tangent * n1_prev.dot(tangent)
		n1 = n1.normalized()
		n1_prev = n1
		var n2 := tangent.cross(n1).normalized()
		var r := []
		var nn := []
		for k in range(ring):
			var ang := TAU * float(k) / float(ring)
			var dir := n1 * cos(ang) + n2 * sin(ang)
			r.append(points[i] + dir * radius)
			nn.append(dir)
		rings.append(r)
		norms.append(nn)
	for i in range(rings.size() - 1):
		for k in range(ring):
			var k2 := (k + 1) % ring
			var quad := [[i, k], [i, k2], [i + 1, k2], [i, k], [i + 1, k2], [i + 1, k]]
			# Orientación: normal hacia fuera = frente (Godot: sentido horario).
			var a: Vector3 = rings[i][k]
			var b: Vector3 = rings[i][k2]
			var c: Vector3 = rings[i + 1][k2]
			var flip: bool = (b - a).cross(c - a).dot(norms[i][k]) > 0.0
			for t in [0, 3]:
				var idx := [t, t + 2, t + 1] if flip else [t, t + 1, t + 2]
				for j in idx:
					var q: Array = quad[j]
					st.set_normal(norms[q[0]][q[1]])
					st.add_vertex(rings[q[0]][q[1]])
	return st.commit()
