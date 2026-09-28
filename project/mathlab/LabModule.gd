class_name LabModule
extends Node3D
## LabModule — Clase base de los módulos del Laboratorio matemático.
##
## Un módulo construye su escena 3D (setup), sus controles (build_ui), avanza en
## el tiempo (step), responde al ratón (pick / hover_text / perturb) y ofrece sus
## puntos críticos para el encuadre automático (critical_points).
##
## Convención de ejes: el espacio matemático (x, y, z) con z hacia arriba se
## dibuja en el mundo como X = x·s, Y = z·sz, Z = −y·s (derecha, arriba, fondo).

var lab: Node
var clip_materials: Array = []
var playing: bool = true
var scale_xy: float = 1.0
var scale_z: float = 1.0

func title() -> String: return "Módulo"
func description() -> String: return ""
## Fórmula principal (Unicode) para el panel de información.
func formula() -> String: return ""
func build_ui(_p: VBoxContainer) -> void: pass
func setup() -> void: pass
func step(_dt: float) -> void: pass
func reset() -> void: pass
## ¿Tiene evolución temporal (muestra ⏯ y la velocidad)?
func uses_time() -> bool: return false
## Qué hace la herramienta «Perturbar» en este módulo (para la barra de estado).
func perturb_hint() -> String: return "Este módulo no tiene perturbación directa."
## Punto 3D bajo el rayo (o null).
func pick(_origin: Vector3, _dir: Vector3): return null
## Texto del tooltip flotante para un punto de su superficie.
func hover_text(_hit: Vector3) -> String: return ""
## Perturbación con el ratón (first = primer clic; si no, arrastre).
func perturb(_hit: Vector3, _first: bool) -> void: pass
## [{pos: Vector3, nombre: String, dist: float}]
func critical_points() -> Array: return []
## Lecturas en vivo para el panel de información.
func info() -> String: return ""
## Vista inicial: {target, dist, yaw, pitch} (grados).
func view() -> Dictionary: return {"target": Vector3(0, 0, 0), "dist": 7.5, "yaw": -35.0, "pitch": -32.0}

func to_world(x: float, y: float, z: float) -> Vector3:
	return Vector3(x * scale_xy, z * scale_z, -y * scale_xy)

func to_math(w: Vector3) -> Vector3:
	return Vector3(w.x / scale_xy, -w.z / scale_xy, w.y / scale_z)

## Registra un material de shader para los planos de corte del laboratorio.
func register_clip(m: ShaderMaterial) -> void:
	if m and not clip_materials.has(m):
		clip_materials.append(m)
		if lab:
			lab.apply_clip_to(m)

## Intersección rayo–plano horizontal y = h.
static func ray_plane_y(origin: Vector3, dir: Vector3, h: float):
	if absf(dir.y) < 1e-6:
		return null
	var t := (h - origin.y) / dir.y
	if t < 0.0:
		return null
	return origin + dir * t

## Intersección rayo–superficie de altura height_fn(X, Z) (marcha + bisección).
static func ray_heightfield(origin: Vector3, dir: Vector3, height_fn: Callable, half: float, max_dist: float = 60.0):
	var steps := 240
	var prev_t := 0.0
	var prev_d := INF
	for i in range(steps + 1):
		var t := max_dist * float(i) / steps
		var p := origin + dir * t
		if absf(p.x) > half or absf(p.z) > half:
			prev_d = INF
			prev_t = t
			continue
		var d: float = p.y - float(height_fn.call(p.x, p.z))
		if prev_d != INF and prev_d > 0.0 and d <= 0.0:
			var a := prev_t
			var b := t
			for k in range(24):
				var m := (a + b) * 0.5
				var pm := origin + dir * m
				if pm.y - float(height_fn.call(pm.x, pm.z)) > 0.0:
					a = m
				else:
					b = m
			return origin + dir * ((a + b) * 0.5)
		prev_d = d
		prev_t = t
	return null

## Material estándar holográfico/emisivo para marcadores.
static func glow_mat(c: Color, energy: float = 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.roughness = 0.3
	return m

static func glass_mat(c: Color, alpha: float = 0.3) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.08
	m.metallic_specular = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.rim_enabled = true
	m.rim = 0.4
	return m

static func sphere(r: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 20
	s.rings = 10
	mi.mesh = s
	mi.material_override = m
	return mi

## Tubo por una polilínea (reutiliza el generador de cables de MechaForge).
static func tube(pts: PackedVector3Array, r: float, m: Material, ring: int = 8) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if pts.size() >= 2:
		mi.mesh = CableRenderer.tube_mesh(pts, r, ring)
	mi.material_override = m
	return mi

## Segmento recto (cilindro) entre dos puntos.
static func rod(a: Vector3, b: Vector3, r: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = maxf(1e-5, a.distance_to(b))
	c.radial_segments = 10
	c.rings = 1
	mi.mesh = c
	mi.material_override = m
	mi.position = (a + b) * 0.5
	var d := (b - a).normalized()
	if d.length() > 0.5 and absf(d.dot(Vector3.UP)) < 0.999:
		mi.basis = Basis(Quaternion(Vector3.UP, d))
	elif d.dot(Vector3.UP) < 0.0:
		mi.basis = Basis(Vector3.RIGHT, PI)
	return mi

## Flecha (cilindro + cono) de a hacia b.
static func arrow(a: Vector3, b: Vector3, r: float, m: Material) -> Node3D:
	var n := Node3D.new()
	var d := b - a
	var L := d.length()
	if L < 1e-6:
		return n
	var head := minf(L * 0.35, r * 6.0)
	n.add_child(rod(a, b - d.normalized() * head, r, m))
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = r * 2.6
	cm.height = head
	cm.radial_segments = 12
	cone.mesh = cm
	cone.material_override = m
	cone.position = b - d.normalized() * head * 0.5
	var dn := d.normalized()
	if absf(dn.dot(Vector3.UP)) < 0.999:
		cone.basis = Basis(Quaternion(Vector3.UP, dn))
	elif dn.y < 0.0:
		cone.basis = Basis(Vector3.RIGHT, PI)
	n.add_child(cone)
	return n

## Etiqueta 3D (billboard) para ejes y marcadores.
static func label3d(text: String, pos: Vector3, col: Color = Color(0.85, 0.92, 1.0), px: float = 0.004) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.pixel_size = px
	l.font_size = 40
	l.outline_size = 8
	l.modulate = col
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = false
	return l

## Ejes x (rojo), y (verde), z (azul) con etiquetas.
static func axes(length: float, r: float = 0.008) -> Node3D:
	var n := Node3D.new()
	n.name = "Ejes"
	var specs := [[Vector3(length, 0, 0), Color(1, 0.3, 0.3), "x"], [Vector3(0, 0, -length), Color(0.35, 1, 0.45), "y"], [Vector3(0, length, 0), Color(0.35, 0.6, 1), "z"]]
	for s in specs:
		n.add_child(arrow(-(s[0] as Vector3) * 0.0, s[0], r, glow_mat(s[1], 1.2)))
		n.add_child(label3d(s[2], (s[0] as Vector3) * 1.06, s[1]))
	return n
