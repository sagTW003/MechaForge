extends LabModule
## Mecánica celeste — proyecto de métodos numéricos (docs/PROYECTO_ORBITAS.md): cinco preguntas
## sobre el movimiento de los astros, cada una resuelta con un método numérico que se ve dentro de
## la escena 3D del Sol, los planetas y sus órbitas:
##   1. Puntos de Lagrange: las iteraciones de bisección, secante y Newton sobre la curva f(x) cuyas
##      raíces son L1, L2 y L3, encima del potencial efectivo; una nave suelta en L1–L5 (RK4).
##   2. Ceres: las observaciones, sus residuos y la órbita ajustada por mínimos cuadrados
##      (Cholesky y QR), y dónde predice que reaparecerá.
##   3. Marte: la tabla de efemérides (ecuación de Kepler por Newton) como nodos sobre las órbitas
##      y en un tablero, con los interpolantes y el mínimo de cada método.
##   4. La caída al Sol: los nodos de cada cuadratura como barras del integrando sobre el camino de
##      la caída, y la Tierra cayendo con RK4.
##   5. Mercurio: Euler, RK4 y Verlet a la vez, la roseta de perihelios y la extrapolación a λ = 1.
## Los cálculos están en solvers/Celeste.gd (funciones puras, probadas en LabTests).

const PREGUNTAS := [
	"1 · ¿Dónde se estaciona el James Webb? (raíces)",
	"2 · ¿Cómo encontró Gauss a Ceres? (mínimos cuadrados)",
	"3 · ¿Cuándo estará Marte más cerca? (interpolación)",
	"4 · ¿Cuánto tardaría la Tierra en caer al Sol? (integración)",
	"5 · ¿Por qué gira la órbita de Mercurio? (EDO)",
]
const COL_RAIZ := [Color(1.0, 0.62, 0.2), Color(1.0, 0.4, 0.85), Color(0.3, 0.9, 1.0)]
const COL_INTEG := [Color(1.0, 0.4, 0.3), Color(0.3, 0.85, 1.0), Color(0.5, 1.0, 0.5)]
const COL_MIN := [Color(0.8, 0.8, 0.88), Color(1.0, 0.62, 0.2), Color(0.3, 0.9, 1.0)]
const COL_LS := [Color(1.0, 0.62, 0.2), Color(0.3, 0.9, 1.0)]
const ORO := Color(1.0, 0.85, 0.35)
const GRIS := Color(0.6, 0.68, 0.8)
const LP := ["L1", "L2", "L3", "L4", "L5"]
const SUB := ["₀", "₁", "₂", "₃", "₄", "₅", "₆", "₇", "₈", "₉"]
const PASOS_EDO := [1.0, 0.5, 0.1, 0.05, 0.01, 0.001]
const PASOS_ORB := [2.0, 1.0, 0.5, 0.25, 0.1, 0.05, 0.01]
## Aspecto de cada astro: paradas del degradado que colorea el ruido de su superficie.
const ASPECTO := {
	"Tierra": [[0.0, Color(0.04, 0.12, 0.4)], [0.5, Color(0.1, 0.33, 0.75)], [0.56, Color(0.22, 0.5, 0.24)], [0.78, Color(0.5, 0.42, 0.28)], [1.0, Color(0.95, 0.95, 0.97)]],
	"Marte": [[0.0, Color(0.42, 0.16, 0.07)], [0.6, Color(0.75, 0.35, 0.15)], [1.0, Color(0.95, 0.75, 0.55)]],
	"Mercurio": [[0.0, Color(0.3, 0.29, 0.28)], [1.0, Color(0.78, 0.75, 0.72)]],
	"Luna": [[0.0, Color(0.35, 0.35, 0.37)], [1.0, Color(0.86, 0.86, 0.86)]],
	"Ceres": [[0.0, Color(0.24, 0.23, 0.22)], [1.0, Color(0.62, 0.6, 0.57)]],
	"Júpiter": [[0.0, Color(0.55, 0.4, 0.28)], [0.5, Color(0.86, 0.76, 0.6)], [1.0, Color(0.96, 0.92, 0.84)]],
}
const ESC_CERES := 0.8          # mundo por UA en cada pregunta
const ESC_MARTE := 1.5
const ESC_CAIDA := 2.5
const ESC_MERC := 5.0
const BASE_POT := -1.08         # el potencial efectivo, debajo del plano de la órbita
const AMP_POT := 0.34
const ALTO_F := 0.62            # semialto de la cortina de f(x)
const H_CAIDA := 1.5            # alto de las barras del integrando

var pregunta := 0
# 1 · Lagrange
var sistema := 0
var punto := 1
var metodo_raiz := 3            # 0–2, o 3: los tres a la vez
var x0 := NAN                   # punto de partida de Newton (NAN: el extremo del intervalo)
var nave_lp := 1
var nave_km := 1000.0
var vista_todo := false
# 2 · Ceres
var n_obs := 22
var arco := 41.0
var ruido := 0.01               # % de error de cada posición
var hueco := 323.0
var semilla_obs := 1
var metodo_ls := 2              # 0 Cholesky, 1 QR, 2 los dos
# 3 · Marte
var acercamiento := 0
var paso_tabla := 20.0
var metodo_min := 3             # 0–2, o 3: todos
# 4 · Caída
var metodo_int := 2
var n_int := 16
var h_edo := 0.05
# 5 · Mercurio
var integrador := 2
var h_orb := 0.25
var lam_exp := 5.0
var tres := true
var vueltas := 5.0

var escena: Node3D              # lo de la pregunta actual (se rehace al cambiarla)
var dinamico: Node3D            # lo que se rehace al avanzar el método
var _q_box: VBoxContainer
var _opt_pregunta: OptionButton
var _info := ""
var _csv: Array = []
var _t := 0.0
var _rotulo: Label3D
var _cx := 0.0
var _lin: ImmediateMesh
# 1
var _mu := 0.0
var _L: Array = []
var _iters: Array = []
var _k := 0
var _f0 := 1.0
var _ventana := 1.0
var _zoom := false
var _pot := PackedFloat64Array([0.0, 1.0])
var _nave := PackedFloat64Array()
var _nave_c0 := 0.0
var _nave_t := 0.0
var _nave_mi: MeshInstance3D
var _traza := PackedVector3Array()
# 2
var _obs: Array = []
var _aj: Array = []
var _ceres_mi: MeshInstance3D
var _tierra_mi: MeshInstance3D
# 3
var _tb: Array = []
var _Mspl := PackedFloat64Array()
var _mins: Array = []
var _ref := PackedFloat64Array()
var _ei := PackedFloat64Array()
var _kep := 0.0
var _j := 0.0
var _marte_mi: MeshInstance3D
var _linea_tm: MeshInstance3D
var _lbl_tm: Label3D
var _cursor: MeshInstance3D
var _tab: Dictionary = {}
# 4
var _cuad: Dictionary = {}
var _conv: Array = []
var _todos: Array = []
var _edo: Dictionary = {}
var _caida := PackedFloat64Array([1.0, 0.0, 0.0])
var _impacto := -1.0
var _espera := 0.0
var _fantasma: MeshInstance3D
var _lbl4: Label3D
# 5
var _merc: Array = []
var _ext: Array = []
var _peris_root: Node3D

func title() -> String: return "Mecánica celeste"
func uses_time() -> bool: return true

func formula() -> String:
	match pregunta:
		0: return "f(x) = ∂Ω/∂x = x − (1−μ)(x+μ)/|x+μ|³ − μ(x−1+μ)/|x−1+μ|³ = 0   ·   Newton: xₖ₊₁ = xₖ − f(xₖ)/f′(xₖ)"
		1: return "1/r = A + B·cos θ + C·sen θ   ·   (MᵀM)c = Mᵀy por Cholesky   ·   M = QR → Rc = Qᵀy"
		2: return "E − e·sen E = M (Newton)   ·   d(t) = |r_Marte(t) − r_Tierra(t)|   ·   spline natural: S″(t₀) = S″(tₙ) = 0"
		3: return "t = ∫₀ᴿ dr / √(2GM(1/r − 1/R))   ·   r = R·sen²u   ·   exacto: T/(4√2)"
	return "r̈ = −GM·r/r³·(1 + 3λL²/(c²r²))   ·   P(λ) ≈ c₀ + c₁λ + c₂λ²   ·   la relatividad: c₁"

func perturb_hint() -> String:
	if pregunta == 0:
		return "clic sobre el eje Sol–planeta: el punto de partida de Newton"
	return "Este módulo no tiene perturbación directa: usa los controles de la pregunta."

func view() -> Dictionary:
	match pregunta:
		0: return {"target": Vector3(0, -0.3, 0), "dist": 8.4, "yaw": -18.0, "pitch": -27.0}
		2: return {"target": Vector3(0, 0.75, -0.6), "dist": 8.8, "yaw": 0.0, "pitch": -20.0}
		3: return {"target": Vector3(1.0, 0.45, 0), "dist": 6.6, "yaw": -12.0, "pitch": -24.0}
		4: return {"target": Vector3(0, 0.55, -0.6), "dist": 8.6, "yaw": 0.0, "pitch": -24.0}
	return {"target": Vector3(0, 0.2, 0), "dist": 7.4, "yaw": -20.0, "pitch": -34.0}

func setup() -> void:
	add_child(_estrellas())
	escena = Node3D.new()
	add_child(escena)
	_montar()

func reset() -> void:
	_montar()

## Rehace la escena y los cálculos de la pregunta actual.
func _montar() -> void:
	for c in escena.get_children():
		escena.remove_child(c)
		c.queue_free()
	dinamico = Node3D.new()
	escena.add_child(dinamico)
	_cx = 0.0
	scale_z = 1.0
	_t = 0.0
	_csv = []
	_rotulo = label3d("", Vector3(0, 1.9, 0), Color(0.85, 0.93, 1.0), 0.0045)
	escena.add_child(_rotulo)
	match pregunta:
		0: _montar_lagrange()
		1: _montar_ceres()
		2: _montar_marte()
		3: _montar_caida()
		_: _montar_mercurio()

func _encuadrar() -> void:
	if lab == null or lab.get("cam") == null:
		return
	var v := view()
	lab.cam.target = v["target"]
	lab.cam.distance = float(v["dist"])
	lab.cam.yaw = deg_to_rad(float(v["yaw"]))
	lab.cam.pitch = deg_to_rad(float(v["pitch"]))

#region Escena común ----------------------------------------------------------------------

## Del plano de la pregunta (x, y; en la 1, centrado en _cx) al mundo, a la altura h.
func _W(x: float, y: float, h: float = 0.0) -> Vector3:
	return Vector3((x - _cx) * scale_xy, h, -y * scale_xy)

## Posición 3D (x, y, z) de la eclíptica al mundo.
func _W3(p: PackedFloat64Array) -> Vector3:
	return Vector3(p[0] * scale_xy, p[2] * scale_xy, -p[1] * scale_xy)

func _M(w: Vector3) -> Array:
	return [w.x / scale_xy + _cx, -w.z / scale_xy]

## Cielo de estrellas alrededor de la escena (puntos de color tenue, fijos con la semilla 7).
func _estrellas() -> MeshInstance3D:
	var im := ImmediateMesh.new()
	var r := RandomNumberGenerator.new()
	r.seed = 7
	im.surface_begin(Mesh.PRIMITIVE_POINTS)
	for i in 2600:
		var d := Vector3(r.randfn(), r.randfn(), r.randfn()).normalized()
		if d.y < -0.12:
			continue
		var b := r.randf_range(0.3, 1.0)
		im.surface_set_color(Color(b, b * r.randf_range(0.9, 1.0), b * r.randf_range(0.9, 1.1)))
		im.surface_add_vertex(d * 26.0)
	im.surface_end()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.use_point_size = true
	m.point_size = 2.0
	var mi := MeshInstance3D.new()
	mi.name = "Estrellas"
	mi.mesh = im
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

## Un planeta: esfera con ruido coloreado según ASPECTO.
func _cuerpo(nombre: String, r: float, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = 2.0 * r
	sm.radial_segments = 40
	sm.rings = 20
	mi.mesh = sm
	var paradas: Array = ASPECTO.get(nombre, ASPECTO["Luna"])
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for p in paradas:
		offs.append(p[0])
		cols.append(p[1])
	g.offsets = offs
	g.colors = cols
	var nz := FastNoiseLite.new()
	nz.seed = nombre.hash() & 0xffff
	nz.frequency = 0.02
	nz.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 128
	tex.seamless = true
	tex.noise = nz
	tex.color_ramp = g
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = 0.9
	m.rim_enabled = true
	m.rim = 0.25
	mi.material_override = m
	mi.position = pos
	return mi

static var _halo_sh: Shader
## Corona del Sol: brillo aditivo que se apaga hacia el borde.
static func _halo_mat(c: Color) -> ShaderMaterial:
	if _halo_sh == null:
		_halo_sh = Shader.new()
		_halo_sh.code = """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
uniform vec4 col : source_color;
void fragment() {
	float f = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = col.rgb * pow(f, 2.5) * col.a;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _halo_sh
	m.set_shader_parameter("col", c)
	return m

## El Sol: núcleo emisivo, corona y la luz que ilumina a los planetas.
func _sol(r: float, pos: Vector3 = Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.add_child(sphere(r, glow_mat(Color(1.0, 0.68, 0.26), 5.0)))
	n.add_child(sphere(r * 1.9, _halo_mat(Color(1.0, 0.55, 0.18, 0.9))))
	var luz := OmniLight3D.new()
	luz.light_color = Color(1.0, 0.93, 0.82)
	luz.light_energy = 3.0
	luz.omni_range = 30.0
	luz.omni_attenuation = 0.5
	n.add_child(luz)
	return n

## Malla de líneas (estelas, rejillas) con color por vértice.
func _lineas(padre: Node3D = null) -> ImmediateMesh:
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(padre if padre else escena).add_child(mi)
	return im

static func _polilinea(im: ImmediateMesh, pts: PackedVector3Array, c: Color, desvanecer: bool = false) -> void:
	if pts.size() < 2:
		return
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in pts.size():
		var a := c.a * (0.15 + 0.85 * float(i + 1) / pts.size() if desvanecer else 1.0)
		im.surface_set_color(Color(c.r * 1.6, c.g * 1.6, c.b * 1.6, a))
		im.surface_add_vertex(pts[i])
	im.surface_end()

## Línea discontinua (para lo «real» que el método no ve).
func _discontinua(pts: PackedVector3Array, c: Color) -> void:
	var im := _lineas()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(0, pts.size() - 1, 2):
		im.surface_set_color(c)
		im.surface_add_vertex(pts[i])
		im.surface_set_color(c)
		im.surface_add_vertex(pts[i + 1])
	im.surface_end()

## Circunferencia de radio r (en las unidades de la pregunta) alrededor de (0, 0).
func _circulo(r: float, n: int = 160) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in n + 1:
		var a := TAU * i / n
		pts.append(_W(r * cos(a), r * sin(a)))
	return pts

## Rejilla polar tenue del plano de la órbita (círculos cada «paso» y 12 radios).
func _rejilla(rmax: float, paso: float) -> void:
	var im := _lineas()
	var c := Color(0.45, 0.65, 1.0, 0.13)
	var r := paso
	while r <= rmax + 1e-9:
		_polilinea(im, _circulo(r, 120), c)
		r += paso
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for k in 12:
		var a := TAU * k / 12.0
		im.surface_set_color(c)
		im.surface_add_vertex(_W(0.0, 0.0))
		im.surface_set_color(c)
		im.surface_add_vertex(_W(rmax * cos(a), rmax * sin(a)))
	im.surface_end()

## Un cilindro de alto 1 colocado entre a y b (para líneas que se mueven cada fotograma).
static func _barra(r: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = 1.0
	c.radial_segments = 8
	c.rings = 1
	mi.mesh = c
	mi.material_override = m
	return mi

static func _alinear(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var L := d.length()
	mi.visible = L > 1e-5
	if not mi.visible:
		return
	var y := d / L
	var x := y.cross(Vector3.UP if absf(y.y) < 0.99 else Vector3.RIGHT).normalized()
	mi.transform = Transform3D(Basis(x, y * L, x.cross(y)), (a + b) * 0.5)

## Tablero holográfico vertical que mira a +Z: {c, w, h, x: [x0, x1], y: [y0, y1]}.
func _tablero(c: Vector3, w: float, h: float, xr: Array, yr: Array, titulo: String, padre: Node3D = null) -> Dictionary:
	if padre == null:
		padre = escena
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(w * 1.1, h * 1.32)
	q.mesh = qm
	q.position = c + Vector3(0, h * 0.06, -0.02)
	q.material_override = glass_mat(Color(0.3, 0.55, 1.0), 0.08)
	padre.add_child(q)
	var tab := {"c": c, "w": w, "h": h, "x": xr, "y": yr}
	var fm := glow_mat(Color(0.45, 0.7, 1.0), 0.9)
	padre.add_child(rod(_tp(tab, xr[0], yr[0]), _tp(tab, xr[1], yr[0]), 0.005, fm))
	padre.add_child(rod(_tp(tab, xr[0], yr[0]), _tp(tab, xr[0], yr[1]), 0.005, fm))
	padre.add_child(label3d(titulo, c + Vector3(0, h * 0.62, 0), Color(0.78, 0.9, 1.0), 0.0034))
	return tab

static func _tp(tab: Dictionary, x: float, y: float) -> Vector3:
	var u := inverse_lerp(float(tab["x"][0]), float(tab["x"][1]), x) - 0.5
	var v := inverse_lerp(float(tab["y"][0]), float(tab["y"][1]), y) - 0.5
	return tab["c"] + Vector3(u * float(tab["w"]), v * float(tab["h"]), 0.0)

## Curva en el tablero por los puntos [[x, y], …] (los que caen fuera se recortan).
func _curva_tab(tab: Dictionary, xy: Array, c: Color, r: float = 0.007, padre: Node3D = null) -> void:
	var pts := PackedVector3Array()
	for p in xy:
		var y := clampf(float(p[1]), float(tab["y"][0]), float(tab["y"][1]))
		pts.append(_tp(tab, float(p[0]), y))
	if pts.size() >= 2:
		(padre if padre else escena).add_child(tube(pts, r, glow_mat(c, 1.6)))

## Esfera de radio r en pos, hija de padre.
static func _bola(padre: Node, r: float, m: Material, pos: Vector3) -> MeshInstance3D:
	var b := sphere(r, m)
	b.position = pos
	padre.add_child(b)
	return b

static func _sub(n: int) -> String:
	var s := ""
	for ch in str(n):
		s += SUB[int(ch)]
	return s

## 1507679 → «1 507 679».
static func _miles(v: float) -> String:
	var s := str(int(round(absf(v))))
	var o := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			o += " "
		o += s[i]
	return ("−" if v < 0.0 else "") + o

static func _num(v: float) -> String:
	return str(v).replace(".", ",")

#endregion

#region 1 · Puntos de Lagrange ---------------------------------------------------------------

func _montar_lagrange() -> void:
	var S: Dictionary = Celeste.SISTEMAS[sistema]
	_mu = S["mu"]
	_L = Celeste.puntos_lagrange(_mu)
	_iters = []
	for m in 3:
		_iters.append(Celeste.iterar_lagrange(m, punto, _mu, x0 if m == 2 else NAN))
	_zoom = _mu < 1e-4 and punto <= 1 and not vista_todo
	_ventana = 3.2 * Celeste.radio_hill(_mu) if _zoom else 1.45
	_cx = 1.0 - _mu if _zoom else 0.0
	scale_xy = 2.6 / _ventana
	_f0 = 0.9 * _ventana
	_k = 0
	_nave = PackedFloat64Array()
	_traza.clear()
	_superficie_potencial()
	_curva_f()
	_cuerpos_lagrange(S)
	_marcas_lagrange()
	_nave_mi = sphere(0.035, glow_mat(Color(0.85, 1.0, 1.0), 3.0))
	_nave_mi.visible = false
	escena.add_child(_nave_mi)
	_lin = _lineas()
	_rotulo.position = Vector3(0, 1.25, 0)
	_tabla_lagrange(S)
	_dibujar_iter()

func _altura_pot(x: float, y: float) -> float:
	return BASE_POT + AMP_POT * tanh((_pot[0] - Celeste.omega(x, y, _mu)) / _pot[1])

## El potencial efectivo Ω (marco que gira con los dos cuerpos) como superficie bajo el plano:
## pozos en los cuerpos, sillas en L1–L3 y colinas en L4 y L5 (altura ∝ tanh, para que quepa).
func _superficie_potencial() -> void:
	var oref := Celeste.omega(_L[0][0], 0.0, _mu)
	var otro := Celeste.omega(1.0 - _mu, 3.0 * Celeste.radio_hill(_mu), _mu) if _zoom else Celeste.omega(_L[3][0], _L[3][1], _mu)
	_pot = PackedFloat64Array([oref, maxf(1e-300, oref - otro)])
	var n := 96
	var yv := _ventana * (1.0 if _zoom else 0.85)
	var hs := PackedFloat64Array()
	for j in n + 1:
		for i in n + 1:
			hs.append(_altura_pot(_cx + lerpf(-_ventana, _ventana, float(i) / n), lerpf(-yv, yv, float(j) / n)))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in n:
		for i in n:
			for q in [[0, 0], [1, 0], [1, 1], [0, 0], [1, 1], [0, 1]]:
				var ii: int = i + q[0]
				var jj: int = j + q[1]
				var h := hs[jj * (n + 1) + ii]
				var t := (h - BASE_POT) / AMP_POT
				var c := Color(0.01, 0.02, 0.1).lerp(Color(0.04, 0.22, 0.36), t + 1.0) if t < 0.0 else Color(0.04, 0.22, 0.36).lerp(Color(0.62, 0.42, 0.14), t)
				st.set_color(c)
				st.add_vertex(_W(_cx + lerpf(-_ventana, _ventana, float(ii) / n), lerpf(-yv, yv, float(jj) / n), h))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	# Sin iluminar: los reflejos del holodeck lavaban los colores. La forma la dan las líneas.
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0.82)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	escena.add_child(mi)
	var im := _lineas()
	for linea in 2:
		for k in range(0, n + 1, 6):
			var pts := PackedVector3Array()
			for q in n + 1:
				var ii := k if linea == 0 else q
				var jj := q if linea == 0 else k
				pts.append(_W(_cx + lerpf(-_ventana, _ventana, float(ii) / n), lerpf(-yv, yv, float(jj) / n), hs[jj * (n + 1) + ii] + 0.004))
			_polilinea(im, pts, Color(0.35, 0.75, 1.0, 0.22))
	escena.add_child(label3d("potencial efectivo Ω (pozos en los cuerpos, sillas en L1–L3)", _W(_cx, -yv * 0.95, BASE_POT + AMP_POT + 0.08), Color(0.6, 0.8, 1.0), 0.0024))

## Altura en el mundo de f(x), comprimida con atan para que las asíntotas quepan.
func _F(x: float) -> float:
	return ALTO_F * 2.0 / PI * atan(Celeste.f_lagrange(x, _mu) / _f0)

## La función cuyas raíces son L1–L3, como una cortina vertical sobre el eje Sol–planeta: cada
## raíz es donde la curva atraviesa el plano de la órbita.
func _curva_f() -> void:
	var a := _cx - _ventana
	var b := _cx + _ventana
	var cortes := [a]
	for s in [-_mu, 1.0 - _mu]:
		if s > a and s < b:
			cortes.append(s)
	cortes.append(b)
	var eps := 1e-5 * _ventana
	for k in cortes.size() - 1:
		var lo: float = cortes[k] + (eps if k > 0 else 0.0)
		var hi: float = cortes[k + 1] - (eps if k + 1 < cortes.size() - 1 else 0.0)
		var pts := PackedVector3Array()
		for i in 301:
			# Más puntos cerca de los extremos, donde la curva se dispara.
			var u := 0.5 - 0.5 * cos(PI * i / 300.0)
			var x := lerpf(lo, hi, u)
			pts.append(_W(x, 0.0, _F(x)))
		escena.add_child(tube(pts, 0.008, glow_mat(Color(0.85, 0.95, 1.0), 1.5)))
	escena.add_child(rod(_W(a, 0.0), _W(b, 0.0), 0.004, glow_mat(GRIS, 0.8)))
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2.0 * _ventana * scale_xy, 2.0 * ALTO_F)
	q.mesh = qm
	q.material_override = glass_mat(Color(0.4, 0.7, 1.0), 0.05)
	escena.add_child(q)
	escena.add_child(label3d("f(x) = ∂Ω/∂x: sus raíces son L1, L2 y L3", _W(a, 0.0, ALTO_F + 0.1) + Vector3(0.9, 0, 0), Color(0.8, 0.92, 1.0), 0.0026))

func _cuerpos_lagrange(S: Dictionary) -> void:
	var n1: String = S["p1"]
	var n2: String = S["p2"]
	if _zoom:
		escena.add_child(_cuerpo(n2, 0.14, _W(1.0 - _mu, 0.0)))
		var borde := _W(_cx - _ventana, 0.0, 0.35)
		escena.add_child(arrow(borde + Vector3(0.55, 0, 0), borde, 0.012, glow_mat(Color(1.0, 0.75, 0.3), 2.0)))
		escena.add_child(label3d("%s a %s km" % [n1, _miles(S["d_km"])], borde + Vector3(0.3, 0.12, 0), Color(1.0, 0.85, 0.55), 0.0025))
		var luz := DirectionalLight3D.new()       # el Sol está lejos: sus rayos llegan paralelos
		luz.rotation = Vector3(0.0, -PI / 2.0, 0.0)
		luz.light_energy = 1.4
		luz.light_color = Color(1.0, 0.93, 0.82)
		escena.add_child(luz)
		return
	var p1 := _W(-_mu, 0.0)
	if n1 == "Sol":
		escena.add_child(_sol(0.16, p1))
	else:
		escena.add_child(_cuerpo(n1, 0.13, p1))
		var luz := OmniLight3D.new()
		luz.position = Vector3(-7.0, 2.0, 3.0)
		luz.omni_range = 40.0
		luz.light_energy = 5.0
		escena.add_child(luz)
	escena.add_child(_cuerpo(n2, 0.09 if n2 == "Júpiter" else 0.065, _W(1.0 - _mu, 0.0)))
	escena.add_child(tube(_circulo(1.0 - _mu), 0.004, glow_mat(GRIS, 0.6)))

## Los cinco puntos de Lagrange: anillo, nombre y una línea hasta su silla o colina del potencial.
func _marcas_lagrange() -> void:
	var yv := _ventana * (1.0 if _zoom else 0.85)
	for i in 5:
		var x: float = _L[i][0]
		var y: float = _L[i][1]
		if absf(x - _cx) > _ventana or absf(y) > yv:
			continue
		var p := _W(x, y)
		var anillo := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.045
		tm.outer_radius = 0.062
		anillo.mesh = tm
		anillo.material_override = glow_mat(ORO if i == punto else Color(0.7, 0.75, 0.88), 2.5 if i == punto else 1.0)
		anillo.position = p
		escena.add_child(anillo)
		escena.add_child(label3d(LP[i], p + Vector3(0, 0.13, -0.05), ORO if i == punto else Color(0.8, 0.85, 0.95), 0.004))
		escena.add_child(rod(p, Vector3(p.x, _altura_pot(x, y), p.z), 0.003, glow_mat(GRIS, 0.5)))

func _metodos_visibles() -> Array:
	return [0, 1, 2] if metodo_raiz == 3 else [metodo_raiz]

func _iter_total() -> int:
	var n := 0
	for m in _metodos_visibles():
		n = maxi(n, (_iters[m]["xs"] as Array).size())
	return n

## Las primeras _k iteraciones de cada método visible: los xₖ sobre el eje (cada método en su
## carril), su punto en la curva y, para la última, la tangente de Newton, las dos secantes o el
## intervalo de la bisección.
func _dibujar_iter() -> void:
	for c in dinamico.get_children():
		dinamico.remove_child(c)
		c.queue_free()
	var vis := _metodos_visibles()
	var ab := Celeste.intervalo(punto, _mu)
	for idx in vis.size():
		var m: int = vis[idx]
		var xs: Array = _iters[m]["xs"]
		var dz := (idx - (vis.size() - 1) * 0.5) * 0.09
		var col: Color = COL_RAIZ[m]
		var mat := glow_mat(col, 2.2)
		var tenue := glow_mat(col.darkened(0.3), 0.9)
		var n := mini(_k, xs.size())
		if m == 2:
			var xi: float = x0 if not is_nan(x0) else Celeste.x0_newton(punto, _mu)
			if absf(xi - _cx) <= _ventana:
				_bola(dinamico, 0.022, tenue, _W(xi, 0.0) + Vector3(0, 0, dz))
				if vis.size() == 1:
					dinamico.add_child(label3d("x" + SUB[0], _W(xi, 0.0, -0.1) + Vector3(0, 0, dz), col, 0.0032))
		for j in n:
			var x: float = xs[j]
			if absf(x - _cx) > _ventana:
				continue
			var ult := j == n - 1
			var pe := _W(x, 0.0) + Vector3(0, 0, dz)
			var pc := _W(x, 0.0, _F(x))
			var s := sphere(0.034 if ult else 0.018, mat if ult else tenue)
			s.position = pe
			dinamico.add_child(s)
			dinamico.add_child(rod(pe, pc, 0.0025, tenue))
			var sc := sphere(0.016, mat)
			sc.position = pc
			dinamico.add_child(sc)
			if not ult:
				continue
			match m:
				0:
					var it: Array = _iters[0]["intervalos"][j]
					dinamico.add_child(rod(_W(clampf(it[0], _cx - _ventana, _cx + _ventana), 0.0, 0.03) + Vector3(0, 0, dz),
						_W(clampf(it[1], _cx - _ventana, _cx + _ventana), 0.0, 0.03) + Vector3(0, 0, dz), 0.012, glass_mat(col, 0.55)))
				1:
					var prev := [ab[0], ab[1]]
					prev.append_array(xs.slice(0, j))
					for xp in [prev[-2], prev[-1]]:
						if absf(float(xp) - _cx) <= _ventana:
							dinamico.add_child(rod(_W(xp, 0.0, _F(xp)), pe, 0.003, mat))
				2:
					var xp: float = xs[j - 1] if j > 0 else (x0 if not is_nan(x0) else Celeste.x0_newton(punto, _mu))
					if absf(xp - _cx) <= _ventana:
						dinamico.add_child(rod(_W(xp, 0.0, _F(xp)), pe, 0.003, mat))
			var nombre: String = Celeste.METODOS_RAIZ[m].substr(0, 1)
			dinamico.add_child(label3d(("x" if vis.size() == 1 else nombre) + _sub(j + 1), pe + Vector3(0, 0.1, 0), col, 0.0032))
	if _k >= _iter_total():
		var S: Dictionary = Celeste.SISTEMAS[sistema]
		var xr: float = _L[punto][0]
		dinamico.add_child(label3d("%s: %s km de %s" % [LP[punto], _miles(Celeste.distancia_km(punto, xr, _mu, S["d_km"])), S["p1"] if punto == 2 else S["p2"]],
			_W(xr, 0.0, 0.32), ORO, 0.004))

func _tabla_lagrange(S: Dictionary) -> void:
	var xr: float = _L[punto][0]
	var dkm := Celeste.distancia_km(punto, xr, _mu, S["d_km"])
	var t := "[b]%s del sistema %s[/b] (μ = %s): x* = %.12f → [color=#ffd966]%s km[/color] de %s" % [
		LP[punto], S["nombre"], LabUI.sci(_mu, 4), xr, _miles(dkm), S["p1"] if punto == 2 else S["p2"]]
	if sistema == 0 and punto == 1:
		t += "\n[color=#8fa3b8]El James Webb gira alrededor de L2, a unos 1,5 millones de km de la Tierra.[/color]"
	t += "\n[font_size=12][color=#8fa3b8]  Método      │ iter │ evals f │ p teórico │ p obs. │ |xₙ − x*|[/color]"
	_csv = [["metodo", "k", "x_k", "error"]]
	for m in 3:
		var r: Dictionary = _iters[m]
		var xs: Array = r["xs"]
		var sq := "[color=#%s]■[/color]" % (COL_RAIZ[m] as Color).to_html(false)
		if xs.is_empty() or not r["converge"]:
			t += "\n%s %s │ [color=#ff7766]no converge desde ese punto: Newton saltó una singularidad[/color]" % [sq, Celeste.METODOS_RAIZ[m]]
			continue
		var p := Celeste.orden(xs, xr, m == 0)
		t += "\n%s %s │ %d │ %d │ %s │ %s │ %s" % [sq, Celeste.METODOS_RAIZ[m], xs.size(), int(r["evals"]), Celeste.ORDEN_RAIZ[m],
			"%.2f" % p if is_finite(p) else "—", LabUI.sci(absf(float(xs[-1]) - xr), 1)]
		for k in xs.size():
			_csv.append([Celeste.METODOS_RAIZ[m], k + 1, xs[k], absf(float(xs[k]) - xr)])
	t += "[/font_size]"
	_info = t

## Suelta la nave en el punto elegido, desplazada nave_km hacia fuera, en reposo en el marco que gira.
func _soltar_nave() -> void:
	if _zoom and nave_lp >= 2:
		vista_todo = true          # L3–L5 quedan fuera del zoom de la Tierra
		_montar()
		_controles()
	var S: Dictionary = Celeste.SISTEMAS[sistema]
	var d := nave_km / float(S["d_km"])
	_nave = PackedFloat64Array([float(_L[nave_lp][0]) + d, _L[nave_lp][1], 0.0, 0.0])
	_nave_c0 = Celeste.jacobi(_nave, _mu)
	_nave_t = 0.0
	_traza.clear()
	_nave_mi.visible = true

func _paso_nave(dt: float) -> void:
	if _nave.size() != 4:
		return
	var h := 0.002 if _zoom else 0.01
	var n := mini(int(ceil(dt * (0.15 if _zoom else 2.5) / h)), 3000)
	for i in n:
		_nave = Celeste.rk4_nave(_nave, _mu, h)
		_nave_t += h
		if absf(_nave[0] - _cx) > 4.0 * _ventana or absf(_nave[1]) > 4.0 * _ventana:
			break
	var p := _W(_nave[0], _nave[1], 0.02)
	_nave_mi.position = p
	_nave_mi.visible = absf(_nave[0] - _cx) <= _ventana * 1.2 and absf(_nave[1]) <= _ventana * 1.2
	if _traza.is_empty() or _traza[-1].distance_to(p) > 0.01:
		_traza.append(p)
		if _traza.size() > 5000:
			_traza = _traza.slice(_traza.size() - 5000)
	_lin.clear_surfaces()
	_polilinea(_lin, _traza, Color(0.4, 0.95, 1.0, 0.9), true)

func _info_lagrange() -> String:
	var s := _info + "\nIteración que se ve: k = %d de %d (▶ avanza una cada 0,55 s)" % [mini(_k, _iter_total()), _iter_total()]
	if _nave.size() == 4:
		var S: Dictionary = Celeste.SISTEMAS[sistema]
		var dl := sqrt(pow(_nave[0] - float(_L[nave_lp][0]), 2) + pow(_nave[1] - float(_L[nave_lp][1]), 2)) * float(S["d_km"])
		s += "\nNave en %s: t = %.1f días · a %s km del punto · deriva de la constante de Jacobi %s (RK4)" % [
			LP[nave_lp], _nave_t / TAU * float(S["periodo"]), _miles(dl), LabUI.sci(absf(Celeste.jacobi(_nave, _mu) - _nave_c0), 1)]
	return s

#endregion

#region 2 · Ceres ----------------------------------------------------------------------------

func _orbita_conica(c: PackedFloat64Array) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in 241:
		var th := TAU * i / 240.0
		var den := c[0] + c[1] * cos(th) + c[2] * sin(th)
		if den <= 0.05:
			continue
		var r := 1.0 / den
		pts.append(_W(r * cos(th), r * sin(th)))
	return pts

func _montar_ceres() -> void:
	scale_xy = ESC_CERES
	_obs = Celeste.observar(Celeste.CERES, n_obs, arco, ruido / 100.0, semilla_obs)
	_aj = [Celeste.ajustar(_obs, 0), Celeste.ajustar(_obs, 1)]
	escena.add_child(_sol(0.14))
	_rejilla(3.0, 1.0)
	escena.add_child(tube(_circulo(1.0), 0.004, glow_mat(Color(0.3, 0.55, 1.0), 0.8)))
	escena.add_child(tube(_circulo(1.524), 0.003, glow_mat(Color(0.9, 0.4, 0.25), 0.5)))
	escena.add_child(label3d("Marte", _W(0.0, -1.6, 0.06), Color(0.95, 0.6, 0.45), 0.003))
	var real := PackedVector3Array()
	var per := Celeste.periodo(Celeste.CERES["a"])
	for i in 241:
		var p := Celeste.polar(Celeste.CERES, per * i / 240.0)
		real.append(_W(p[0] * cos(p[1]), p[0] * sin(p[1])))
	_discontinua(real, Color(1, 1, 1, 0.35))
	var arc := PackedVector3Array()
	for i in 41:
		var p := Celeste.polar(Celeste.CERES, arco * i / 40.0)
		arc.append(_W(p[0] * cos(p[1]), p[0] * sin(p[1]), 0.005))
	escena.add_child(tube(arc, 0.012, glow_mat(Color(0.4, 1.0, 0.9), 1.6)))
	# Observaciones y residuos (exagerados para que se vean).
	var aj: Dictionary = _aj[1 if metodo_ls == 1 else 0]
	var c: PackedFloat64Array = aj["c"]
	var res_max := 0.0
	if c.size() == 3:
		for o in _obs:
			res_max = maxf(res_max, absf(1.0 / (c[0] + c[1] * cos(o[2]) + c[2] * sin(o[2])) - float(o[1])))
	var factor := 1.0
	if res_max > 0.0:
		factor = clampf(0.25 / (res_max * scale_xy), 1.0, 1e7)
		factor = pow(10.0, floor(log(factor) / log(10.0)))
	var mo := glow_mat(Color(1.0, 1.0, 0.85), 2.0)
	var mr := glow_mat(Color(1.0, 0.3, 0.3), 1.6)
	for o in _obs:
		var r: float = o[1]
		var th: float = o[2]
		var po := _W(r * cos(th), r * sin(th), 0.01)
		_bola(dinamico, 0.02, mo, po)
		if c.size() == 3:
			var rf := 1.0 / (c[0] + c[1] * cos(th) + c[2] * sin(th))
			var re := r + (rf - r) * factor
			dinamico.add_child(rod(po, _W(re * cos(th), re * sin(th), 0.01), 0.004, mr))
	if res_max > 0.0:
		var o0: Array = _obs[_obs.size() / 2]
		dinamico.add_child(label3d("residuos × %s" % _miles(factor), _W(float(o0[1]) * cos(o0[2]), float(o0[1]) * sin(o0[2]), 0.18), Color(1.0, 0.55, 0.5), 0.0032))
	var t_pred := arco + hueco
	var pr := Celeste.polar(Celeste.CERES, t_pred)
	var preal := _W(pr[0] * cos(pr[1]), pr[0] * sin(pr[1]), 0.02)
	_bola(dinamico, 0.03, glow_mat(Color.WHITE, 2.0), preal)
	dinamico.add_child(label3d("Ceres real (día %d)" % int(t_pred), preal + Vector3(0, 0.24, 0), Color.WHITE, 0.0032))
	for m in ([0, 1] if metodo_ls == 2 else [metodo_ls]):
		var a: Dictionary = _aj[m]
		if not a["valido"]:
			continue
		escena.add_child(tube(_orbita_conica(a["c"]), 0.006 if m == 0 else 0.0045, glow_mat(COL_LS[m], 1.8)))
		var pp := Celeste.predecir(a, _obs, t_pred)
		var wp := _W(pp[0] * cos(pp[1]), pp[0] * sin(pp[1]), 0.02)
		_bola(dinamico, 0.028, glow_mat(COL_LS[m], 2.5), wp)
		dinamico.add_child(rod(wp, preal, 0.004, glow_mat(Color(1.0, 0.35, 0.3), 2.0)))
		if m == (1 if metodo_ls == 1 else 0):
			var err := Celeste.error_prediccion(pp, pr)
			dinamico.add_child(label3d("predicción: error %.2f°" % err[0], wp + Vector3(0, -0.2, 0.12), COL_LS[m], 0.0032))
	_tierra_mi = _cuerpo("Tierra", 0.05, Vector3.ZERO)
	escena.add_child(_tierra_mi)
	_ceres_mi = _cuerpo("Ceres", 0.04, Vector3.ZERO)
	escena.add_child(_ceres_mi)
	_lin = _lineas()
	_rotulo.position = Vector3(0, 1.4, 0)
	_tabla_ceres(pr, t_pred)
	_paso_ceres()

func _tabla_ceres(pr: PackedFloat64Array, t_pred: float) -> void:
	var a0: Dictionary = _aj[0]
	var dth := rad_to_deg(float(_obs[-1][2]) - float(_obs[0][2]))
	var N: Array = a0["N"]
	var t := "[b]%d observaciones en %d días[/b] (arco de %.1f° visto desde el Sol) · error de cada posición %s %% · semilla %d" % [n_obs, int(arco), dth, str(ruido), semilla_obs]
	t += "\n[font_size=12]MᵀM = [%s; %s; %s]" % [_fila(N[0]), _fila(N[1]), _fila(N[2])]
	t += "\nκ(MᵀM) = %s = κ(M)² → las ecuaciones normales pierden ≈ %d dígitos de 16; QR, ≈ %d" % [
		LabUI.sci(a0["kappa"], 2), int(round(log(maxf(1.0, a0["kappa"])) / log(10.0))), int(round(log(maxf(1.0, a0["kappa_M"])) / log(10.0)))]
	t += "\n[color=#8fa3b8]  Método    │ A │ B │ C │ a (UA) │ e │ ϖ (°) │ error al reaparecer[/color]"
	for m in 2:
		var a: Dictionary = _aj[m]
		var sq := "[color=#%s]■[/color]" % (COL_LS[m] as Color).to_html(false)
		var c: PackedFloat64Array = a["c"]
		if c.size() != 3:
			t += "\n%s %s │ [color=#ff7766]la matriz no es definida positiva (en coma flotante)[/color]" % [sq, Celeste.METODOS_LS[m]]
			continue
		var fila := "\n%s %s │ %.9f │ %.9f │ %.9f" % [sq, ["Cholesky", "QR"][m], c[0], c[1], c[2]]
		if a["valido"]:
			var err := Celeste.error_prediccion(Celeste.predecir(a, _obs, t_pred), pr)
			fila += " │ %.4f │ %.4f │ %.2f │ %.3f° (%s km)" % [a["a"], a["e"], a["peri"], err[0], _miles(err[1] * Celeste.KM_UA)]
		else:
			fila += " │ [color=#ff7766]e = %.2f ≥ 1: no es una elipse (arco corto o mucho ruido)[/color]" % a.get("e", INF)
		t += fila
	t += "\n[color=#8fa3b8]  Ceres real │ │ │ │ %.4f │ %.4f │ %.2f │[/color]" % [Celeste.CERES["a"], Celeste.CERES["e"], Celeste.CERES["peri"]]
	var c0: PackedFloat64Array = _aj[0]["c"]
	var c1: PackedFloat64Array = _aj[1]["c"]
	if c0.size() == 3 and c1.size() == 3:
		var dif := sqrt(pow(c0[0] - c1[0], 2) + pow(c0[1] - c1[1], 2) + pow(c0[2] - c1[2], 2)) / sqrt(c1[0] * c1[0] + c1[1] * c1[1] + c1[2] * c1[2])
		t += "\nDiferencia Cholesky–QR: |Δc|/|c| = %s · rms de los residuos de 1/r: %s UA⁻¹" % [LabUI.sci(dif, 1), LabUI.sci(_aj[1].get("rms", NAN), 2)]
	t += "[/font_size]"
	_info = t
	_csv = [["t_dias", "r_obs_UA", "theta_obs_rad", "r_ajustada_UA", "residuo_UA"]]
	for o in _obs:
		var rf := NAN
		if c1.size() == 3:
			rf = 1.0 / (c1[0] + c1[1] * cos(o[2]) + c1[2] * sin(o[2]))
		_csv.append([o[0], o[1], o[2], rf, rf - float(o[1])])

static func _fila(f: Array) -> String:
	return "%.4f %.4f %.4f" % [f[0], f[1], f[2]]

## Ceres y la Tierra en su sitio en el día de la animación, y la visual de Piazzi desde la Tierra.
func _paso_ceres() -> void:
	var t_fin := arco + hueco + 150.0
	var t := fmod(_t * 30.0, t_fin)
	var pc := Celeste.polar(Celeste.CERES, t)
	var wc := _W(pc[0] * cos(pc[1]), pc[0] * sin(pc[1]), 0.02)
	_ceres_mi.position = wc
	var th := deg_to_rad(Celeste.TIERRA_1801 + 360.0 * t / 365.256)
	var wt := _W(cos(th), sin(th), 0.02)
	_tierra_mi.position = wt
	_ceres_mi.rotate_y(0.02)
	_tierra_mi.rotate_y(0.05)
	_lin.clear_surfaces()
	_polilinea(_lin, PackedVector3Array([wt, wc]), Color(0.7, 0.85, 1.0, 0.35 if t <= arco else 0.12))
	var fase := "observando" if t <= arco else ("perdida tras el Sol" if t < arco + hueco else "reaparece")
	_rotulo.text = "%s · día %d · %s" % [Celeste.fecha(Celeste.jd(1801, 1, 1.0) + t, false), int(t), fase]

#endregion

#region 3 · Marte ----------------------------------------------------------------------------

func _montar_marte() -> void:
	scale_xy = ESC_MARTE
	var ac: Array = Celeste.ACERCAMIENTOS[acercamiento]
	var w := Celeste.ventana(acercamiento)
	_tb = Celeste.tabla(w[0], w[1], paso_tabla)
	var ts: PackedFloat64Array = _tb[0]
	var ds: PackedFloat64Array = _tb[1]
	_Mspl = Celeste.spline(ts, ds)
	_mins = []
	for m in 3:
		_mins.append(Celeste.minimo(ts, ds, m, _Mspl))
	var jn := Celeste.jd(ac[0], ac[1], float(ac[2]))
	_ref = Celeste.minimo_referencia(jn - 10.0, jn + 10.0)
	_ei = Celeste.error_interpolacion(ts, ds, _Mspl, 300)
	var it := 0.0
	for j in ts:
		it += Celeste.posicion(Celeste.TIERRA_JPL, j)[3] + Celeste.posicion(Celeste.MARTE_JPL, j)[3]
	_kep = it / (2.0 * ts.size())
	escena.add_child(_sol(0.14))
	_rejilla(1.75, 0.5)
	for el in [[Celeste.TIERRA_JPL, 365.256, Color(0.3, 0.55, 1.0)], [Celeste.MARTE_JPL, 686.98, Color(1.0, 0.45, 0.25)]]:
		var pts := PackedVector3Array()
		for i in 241:
			pts.append(_W3(Celeste.posicion(el[0], _ref[0] + float(el[1]) * i / 240.0)))
		escena.add_child(tube(pts, 0.005, glow_mat(el[2], 1.0)))
	# La tabla de efemérides en la escena: Tierra y Marte en cada fecha de la tabla, unidos.
	var im := _lineas()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var mt := glow_mat(Color(0.7, 0.85, 1.0), 1.5)
	var mm := glow_mat(Color(1.0, 0.7, 0.5), 1.5)
	for j in ts:
		if absf(j - _ref[0]) > 75.0:
			continue
		var a := _W3(Celeste.posicion(Celeste.TIERRA_JPL, j))
		var b := _W3(Celeste.posicion(Celeste.MARTE_JPL, j))
		_bola(escena, 0.014, mt, a)
		_bola(escena, 0.014, mm, b)
		im.surface_set_color(Color(0.8, 0.85, 1.0, 0.18))
		im.surface_add_vertex(a)
		im.surface_set_color(Color(0.8, 0.85, 1.0, 0.18))
		im.surface_add_vertex(b)
	im.surface_add_vertex(Vector3.ZERO)
	im.surface_add_vertex(Vector3.ZERO)
	im.surface_end()
	_tierra_mi = _cuerpo("Tierra", 0.07, Vector3.ZERO)
	escena.add_child(_tierra_mi)
	_marte_mi = _cuerpo("Marte", 0.055, Vector3.ZERO)
	escena.add_child(_marte_mi)
	_linea_tm = _barra(0.005, glow_mat(Color(1.0, 0.9, 0.6), 1.6))
	escena.add_child(_linea_tm)
	_lbl_tm = label3d("", Vector3.ZERO, Color(1.0, 0.92, 0.7), 0.0034)
	escena.add_child(_lbl_tm)
	_tablero_marte()
	_rotulo.position = Vector3(0, 2.75, -3.0)
	_tabla_marte(ac)
	_j = _ref[0] - 70.0
	_paso_marte()

func _tablero_marte() -> void:
	var t0 := _ref[0] - 70.0
	var t1 := _ref[0] + 70.0
	var dmin := INF
	var dmax := -INF
	var real := []
	for i in 201:
		var j := lerpf(t0, t1, i / 200.0)
		var d := Celeste.distancia_tm(j) * Celeste.KM_UA / 1e6
		real.append([j, d])
		dmin = minf(dmin, d)
		dmax = maxf(dmax, d)
	var pad := (dmax - dmin) * 0.12
	_tab = _tablero(Vector3(0, 1.3, -3.0), 5.4, 1.9, [t0, t1], [dmin - pad, dmax + pad], "Distancia Tierra–Marte (millones de km): la tabla cada %d días y lo que interpola cada método" % int(paso_tabla))
	_curva_tab(_tab, real, Color(1, 1, 1, 0.6), 0.004)
	var ts: PackedFloat64Array = _tb[0]
	var ds: PackedFloat64Array = _tb[1]
	var k := 1.0e-6 * Celeste.KM_UA
	var nodos := []
	for i in ts.size():
		if ts[i] >= t0 and ts[i] <= t1:
			nodos.append([ts[i], ds[i] * k])
			_bola(escena, 0.03, glow_mat(Color.WHITE, 2.0), _tp(_tab, ts[i], ds[i] * k))
	if metodo_min in [0, 3]:
		_curva_tab(_tab, nodos, COL_MIN[0], 0.006)
	if metodo_min in [1, 3]:
		var i := ts.bsearch(_mins[0][0])
		if i >= 1 and i < ts.size() - 1:
			var par := []
			for q in 41:
				var x := lerpf(ts[i - 1], ts[i + 1], q / 40.0)
				var l0 := (x - ts[i]) * (x - ts[i + 1]) / ((ts[i - 1] - ts[i]) * (ts[i - 1] - ts[i + 1]))
				var l1 := (x - ts[i - 1]) * (x - ts[i + 1]) / ((ts[i] - ts[i - 1]) * (ts[i] - ts[i + 1]))
				var l2 := (x - ts[i - 1]) * (x - ts[i]) / ((ts[i + 1] - ts[i - 1]) * (ts[i + 1] - ts[i]))
				par.append([x, (l0 * ds[i - 1] + l1 * ds[i] + l2 * ds[i + 1]) * k])
			_curva_tab(_tab, par, COL_MIN[1], 0.007)
	if metodo_min in [2, 3]:
		var spl := []
		for q in 241:
			var x := lerpf(maxf(t0, ts[0]), minf(t1, ts[-1]), q / 240.0)
			spl.append([x, Celeste.spline_en(ts, ds, _Mspl, x) * k])
		_curva_tab(_tab, spl, COL_MIN[2], 0.006)
	var y0: float = _tab["y"][0]
	for m in 3:
		if metodo_min != 3 and metodo_min != m:
			continue
		var mn: PackedFloat64Array = _mins[m]
		var p := _tp(_tab, mn[0], mn[1] * k)
		_bola(escena, 0.04, glow_mat(COL_MIN[m], 2.6), p + Vector3(0, 0, 0.02))
		escena.add_child(rod(p, _tp(_tab, mn[0], y0), 0.003, glow_mat(COL_MIN[m], 1.2)))
		escena.add_child(label3d("%+.1f h" % ((mn[0] - _ref[0]) * 24.0), _tp(_tab, mn[0], y0) + Vector3(0.32 * (m - 1), -0.1, 0.02), COL_MIN[m], 0.0028))
	var pr := _tp(_tab, _ref[0], _ref[1] * k)
	_bola(escena, 0.026, glow_mat(Color.WHITE, 2.2), pr + Vector3(0, 0, 0.03))
	escena.add_child(label3d("mínimo: %s" % Celeste.fecha(_ref[0]), pr + Vector3(0, 0.16, 0.03), Color.WHITE, 0.0032))
	for d in range(0, 141, 35):
		escena.add_child(label3d(Celeste.fecha(t0 + d, false), _tp(_tab, t0 + d, y0) + Vector3(0, -0.26, 0), Color(0.7, 0.8, 0.95), 0.0026))
	escena.add_child(label3d("%.0f" % (dmax + pad), _tp(_tab, t0, _tab["y"][1]) + Vector3(-0.25, 0, 0), Color(0.7, 0.8, 0.95), 0.0028))
	escena.add_child(label3d("%.0f" % (dmin - pad), _tp(_tab, t0, y0) + Vector3(-0.25, 0, 0), Color(0.7, 0.8, 0.95), 0.0028))
	_cursor = _barra(0.006, glow_mat(Color(1.0, 0.9, 0.5), 2.0))
	escena.add_child(_cursor)

func _tabla_marte(ac: Array) -> void:
	var k := Celeste.KM_UA
	var t := "[b]Acercamiento de %d[/b] · tabla cada %d días (%d nodos) · Kepler por Newton: %.1f iteraciones en promedio por posición" % [ac[0], int(paso_tabla), (_tb[0] as PackedFloat64Array).size(), _kep]
	t += "\n[font_size=12][color=#8fa3b8]  Método                         │ fecha del mínimo (UT) │ distancia (km) │ error en tiempo │ en distancia[/color]"
	_csv = [["metodo", "jd", "fecha", "distancia_km", "error_horas", "error_km"]]
	for m in 3:
		var mn: PackedFloat64Array = _mins[m]
		var sq := "[color=#%s]■[/color]" % (COL_MIN[m] as Color).to_html(false)
		t += "\n%s %s │ %s │ %s │ %+.2f h │ %s km" % [sq, Celeste.METODOS_MIN[m], Celeste.fecha(mn[0]), _miles(mn[1] * k), (mn[0] - _ref[0]) * 24.0, _miles((mn[1] - _ref[1]) * k)]
		_csv.append([Celeste.METODOS_MIN[m], mn[0], Celeste.fecha(mn[0]), mn[1] * k, (mn[0] - _ref[0]) * 24.0, (mn[1] - _ref[1]) * k])
	t += "\n[color=#ffffff]★[/color] Referencia (sección áurea sobre la efeméride, sin tabla) │ %s │ %s │" % [Celeste.fecha(_ref[0]), _miles(_ref[1] * k)]
	t += "\n[color=#8fa3b8]  NASA: %d %s %d, %s millones de km[/color]" % [ac[2], Celeste.MESES[int(ac[1]) - 1], ac[0], str(ac[3])]
	t += "\nError máximo de interpolación entre nodos: lineal %s km · spline %s km (orden h² frente a h⁴)[/font_size]" % [_miles(_ei[0] * k), _miles(_ei[1] * k)]
	_info = t
	var ts: PackedFloat64Array = _tb[0]
	var ds: PackedFloat64Array = _tb[1]
	_csv.append([])
	_csv.append(["jd_nodo", "fecha", "distancia_km"])
	for i in ts.size():
		_csv.append([ts[i], Celeste.fecha(ts[i]), ds[i] * k])

func _paso_marte() -> void:
	var a := Celeste.posicion(Celeste.TIERRA_JPL, _j)
	var b := Celeste.posicion(Celeste.MARTE_JPL, _j)
	var wa := _W3(a)
	var wb := _W3(b)
	_tierra_mi.position = wa
	_marte_mi.position = wb
	_tierra_mi.rotate_y(0.05)
	_marte_mi.rotate_y(0.05)
	_alinear(_linea_tm, wa, wb)
	var d := sqrt(pow(a[0] - b[0], 2) + pow(a[1] - b[1], 2) + pow(a[2] - b[2], 2)) * Celeste.KM_UA / 1e6
	_lbl_tm.position = (wa + wb) * 0.5 + Vector3(0, 0.15, 0)
	_lbl_tm.text = "%.2f millones de km" % d
	_alinear(_cursor, _tp(_tab, _j, _tab["y"][0]), _tp(_tab, _j, _tab["y"][1]))
	_rotulo.text = Celeste.fecha(_j)

#endregion

#region 4 · La caída al Sol ------------------------------------------------------------------

## Altura de una barra: el integrando comprimido (f/(f + f(R/2))), que tiende a H en la asíntota.
func _h_f(f: float) -> float:
	if not is_finite(f):
		return H_CAIDA * 1.15
	var fm := Celeste.f_caida(0.5, 1.0)
	return H_CAIDA * f / (f + fm)

func _montar_caida() -> void:
	scale_xy = ESC_CAIDA
	_cuad = Celeste.cuadratura(metodo_int, n_int, 1.0)
	_conv = Celeste.convergencia(metodo_int, 1.0)
	_todos = []
	for m in Celeste.METODOS_INT.size():
		_todos.append(Celeste.cuadratura(m, n_int, 1.0))
	_edo = Celeste.caida_edo(1.0, h_edo)
	escena.add_child(_sol(0.16))
	_rejilla(1.0, 0.25)
	escena.add_child(tube(_circulo(1.0), 0.004, glow_mat(Color(0.3, 0.55, 1.0), 0.8)))
	escena.add_child(rod(_W(0.0, 0.0), _W(1.0, 0.0), 0.004, glow_mat(GRIS, 0.8)))
	escena.add_child(label3d("R = 1 UA", _W(1.0, 0.0, -0.12), GRIS, 0.0032))
	# El integrando sobre el camino de la caída (y, con el cambio de variable, el nuevo).
	var pts := PackedVector3Array()
	for i in 301:
		var r := minf(1.0 - pow(1.0 - i / 300.0, 3.0), 1.0 - 1e-4)
		pts.append(_W(r, 0.0, _h_f(Celeste.f_caida(r, 1.0))))
	escena.add_child(tube(pts, 0.007, glow_mat(Color(0.9, 0.95, 1.0), 1.4)))
	escena.add_child(label3d("dt/dr → ∞ en r = R (integral impropia)", _W(1.0, 0.0, H_CAIDA + 0.15), Color(1.0, 0.6, 0.55), 0.0034))
	var var_u := str(_cuad["variable"]) == "u"
	var gmax := Celeste.g_caida(PI / 2.0, 1.0)
	if var_u:
		var pu := PackedVector3Array()
		for i in 201:
			var u := PI / 2.0 * i / 200.0
			pu.append(_W(sin(u) * sin(u), 0.0, 0.9 * H_CAIDA * Celeste.g_caida(u, 1.0) / gmax))
		escena.add_child(tube(pu, 0.007, glow_mat(Color(0.5, 1.0, 0.55), 1.6)))
		escena.add_child(label3d("dt/du con r = R·sen²u: suave", _W(0.55, 0.0, 0.9 * H_CAIDA + 0.15), Color(0.6, 1.0, 0.6), 0.0032))
	# Los nodos de la cuadratura como barras.
	var col := Color(0.5, 1.0, 0.55) if var_u else Color(1.0, 0.62, 0.25)
	var mb := glow_mat(col, 1.8)
	var minf_mat := glow_mat(Color(1.0, 0.25, 0.25), 3.0)
	var nodos: Array = _cuad["nodos"]
	var infinito := false
	for i in mini(nodos.size(), 400):
		var x: float = nodos[i][0]
		var r := x
		var h := 0.0
		match str(_cuad["variable"]):
			"u":
				r = sin(x) * sin(x)
				h = 0.9 * H_CAIDA * Celeste.g_caida(x, 1.0) / gmax
			"w":
				r = 1.0 - x
				h = _h_f(Celeste.f_caida(r, 1.0) if x > 0.0 else INF)
			_:
				h = _h_f(Celeste.f_caida(r, 1.0))
		var inf := h > H_CAIDA * 1.1
		infinito = infinito or inf
		dinamico.add_child(rod(_W(r, 0.0, 0.0), _W(r, 0.0, h), 0.005 if nodos.size() < 80 else 0.003, minf_mat if inf else mb))
		_bola(dinamico, 0.014, minf_mat if inf else mb, _W(r, 0.0, h))
	if infinito:
		dinamico.add_child(label3d("f(R) = ∞: el método no puede evaluarla", _W(1.0, 0.0, H_CAIDA * 1.3), Color(1.0, 0.4, 0.4), 0.0034))
	_tierra_mi = _cuerpo("Tierra", 0.07, _W(1.0, 0.0))
	escena.add_child(_tierra_mi)
	_fantasma = sphere(0.05, glass_mat(Color(0.4, 0.6, 1.0), 0.25))
	escena.add_child(_fantasma)
	_lbl4 = label3d("", _W(1.0, 0.0, 0.25), Color(0.85, 0.93, 1.0), 0.0034)
	escena.add_child(_lbl4)
	_caida = PackedFloat64Array([1.0, 0.0, 0.0])
	_impacto = -1.0
	_espera = 0.0
	_rotulo.position = Vector3(1.2, 2.3, 0)
	_rotulo.text = "Si la Tierra se detuviera… cae en línea recta al Sol"
	_tabla_caida()

func _tabla_caida() -> void:
	var ex := Celeste.t_caida(1.0)
	var t := "[b]t = ∫₀ᴿ dr/√(2GM(1/r − 1/R))[/b] · exacto: %.6f días (T/(4√2), T = %.3f días) · n = %d" % [ex, Celeste.periodo(1.0), n_int]
	t += "\n[font_size=12][color=#8fa3b8]  Método                   │ resultado (días) │ error │ evaluaciones de f[/color]"
	_csv = [["metodo", "n", "resultado_dias", "error_dias", "evaluaciones"]]
	for m in _todos.size():
		var d: Dictionary = _todos[m]
		var v: float = d["valor"]
		var mark := "[b]" if m == metodo_int else ""
		var fin := "[/b]" if m == metodo_int else ""
		t += "\n%s%s │ %s │ %s │ %d%s" % [mark, Celeste.METODOS_INT[m], "%.8f" % v if is_finite(v) else "[color=#ff7766]∞ (f(R) = ∞)[/color]",
			LabUI.sci(absf(v - ex), 1) if is_finite(v) else "—", int(d["evals"]), fin]
		_csv.append([Celeste.METODOS_INT[m], n_int, v, absf(v - ex), d["evals"]])
	t += "\n[color=#8fa3b8]Convergencia de %s: [/color]" % Celeste.METODOS_INT[metodo_int]
	for f in _conv:
		var p: float = f[3]
		t += " n=%d: %s%s ·" % [f[0], LabUI.sci(f[2], 1) if is_finite(float(f[2])) else "∞", " (p=%.2f)" % p if is_finite(p) and float(f[2]) > 1e-12 else ""]
	t += "\nEDO con RK4 (h = %s días): impacto con la superficie del Sol en el día %.5f (exacto %.5f) · %d pasos · llega a %s km/s[/font_size]" % [
		str(h_edo), _edo["t"], _edo["exacto"], int(_edo["pasos"]), _miles(_edo["v_kms"])]
	_info = t
	_csv.append([])
	_csv.append(["metodo", "n", "error", "orden_observado"])
	for f in _conv:
		_csv.append([Celeste.METODOS_INT[metodo_int], f[0], f[2], f[3]])

## La Tierra cae con RK4 de paso h_edo; al chocar se queda un momento y vuelve a empezar.
func _paso_caida(dt: float) -> void:
	var dias := dt * 6.0
	if _impacto >= 0.0:
		_espera += dt
		if _espera > 3.0:
			_caida = PackedFloat64Array([1.0, 0.0, 0.0])
			_impacto = -1.0
			_espera = 0.0
	else:
		var objetivo := _caida[2] + dias
		var guard := 0
		while _caida[2] < objetivo and guard < 20000:
			guard += 1
			var h := minf(h_edo, objetivo - _caida[2] + 1e-12)
			var s := Celeste.rk4_radial(_caida[0], _caida[1], h)
			if s[0] <= Celeste.R_SOL or not is_finite(s[0]):
				var frac := clampf((_caida[0] - Celeste.R_SOL) / (_caida[0] - s[0]), 0.0, 1.0) if is_finite(s[0]) else 0.5
				_impacto = _caida[2] + h * frac
				_caida = PackedFloat64Array([Celeste.R_SOL, s[1] if is_finite(s[1]) else _caida[1], _impacto])
				break
			_caida = PackedFloat64Array([s[0], s[1], _caida[2] + h])
	_tierra_mi.position = _W(_caida[0], 0.0)
	_tierra_mi.rotate_y(0.04)
	var th := TAU * _caida[2] / 365.256
	_fantasma.position = _W(cos(th), sin(th))
	_lbl4.position = _tierra_mi.position + Vector3(0, 0.22, 0)
	if _impacto >= 0.0:
		_lbl4.text = "¡Impacto! día %.2f (exacto %.2f)" % [_impacto, Celeste.t_caida(1.0, Celeste.R_SOL)]
	else:
		_lbl4.text = "día %.1f · %s km/s" % [_caida[2], _miles(absf(_caida[1]) * Celeste.KM_UA / 86400.0)]

#endregion

#region 5 · Mercurio -------------------------------------------------------------------------

func _integradores_visibles() -> Array:
	return [0, 1, 2] if tres else [integrador]

func _montar_mercurio() -> void:
	scale_xy = ESC_MERC
	escena.add_child(_sol(0.15))
	_rejilla(0.5, 0.1)
	var a: float = Celeste.MERCURIO["a"]
	var e: float = Celeste.MERCURIO["e"]
	var kep := PackedVector3Array()
	for i in 241:
		var f := TAU * i / 240.0
		var r := a * (1.0 - e * e) / (1.0 + e * cos(f))
		kep.append(_W(r * cos(f), r * sin(f)))
	_discontinua(kep, Color(1, 1, 1, 0.35))
	_merc = []
	var lam := pow(10.0, lam_exp)
	for integ in _integradores_visibles():
		var s := Celeste.mercurio_inicial()
		var b := Celeste.beta(lam, s)
		var mi := _cuerpo("Mercurio", 0.045, _W(s[0], s[1]))
		mi.add_child(sphere(0.07, _halo_mat(COL_INTEG[integ])))
		escena.add_child(mi)
		var r0 := sqrt(s[0] * s[0] + s[1] * s[1])
		_merc.append({"integ": integ, "s": s, "b": b, "e0": Celeste.energia(s, b), "mi": mi, "t": 0.0, "r0": r0, "r1": r0,
			"th0": 0.0, "th1": 0.0, "vth": 0.0, "peris": [], "traza": PackedVector3Array(), "fuera": false, "deriva": 0.0})
	_peris_root = Node3D.new()
	escena.add_child(_peris_root)
	_lin = _lineas()
	_rotulo.position = Vector3(0, 1.0, 0)
	_ext = []
	if vueltas * Celeste.periodo(a) / h_orb * Celeste.LAMBDAS.size() * _integradores_visibles().size() < 400000:
		_medir()
	else:
		_tabla_mercurio()

## Mide la precesión con cada λ de Celeste.LAMBDAS y la extrapola a λ = 1 (pregunta 5).
func _medir() -> void:
	_ext = []
	for integ in _integradores_visibles():
		_ext.append([integ, Celeste.extrapolar(integ, h_orb, vueltas)])
	for c in dinamico.get_children():
		dinamico.remove_child(c)
		c.queue_free()
	var ymax := 0.0
	for ex in _ext:
		for p in ex[1]["puntos"]:
			if is_finite(float(p[1])):
				ymax = maxf(ymax, absf(float(p[1])))
	ymax = maxf(ymax, 1.0) * 1.1 / 1e6
	var lmax: float = Celeste.LAMBDAS[-1]
	var tab := _tablero(Vector3(0, 1.75, -3.0), 4.2, 1.5, [0.0, lmax], [-0.1 * ymax, ymax], "Precesión medida P(λ) (millones de ″/siglo) frente a la exageración λ: parábola de mínimos cuadrados", dinamico)
	for ex in _ext:
		var integ: int = ex[0]
		var r: Dictionary = ex[1]
		for p in r["puntos"]:
			if is_finite(float(p[1])):
				_bola(dinamico, 0.035, glow_mat(COL_INTEG[integ], 2.4), _tp(tab, p[0], clampf(float(p[1]) / 1e6, -0.1 * ymax, ymax)))
		if is_finite(float(r["resultado"])):
			var c0: float = r["ordenada"]
			var c1: float = r["resultado"]
			var c2: float = r["c2"]
			var pts := []
			for q in 41:
				var l := lmax * q / 40.0
				pts.append([l, (c0 + c1 * l + c2 * l * l) / 1e6])
			_curva_tab(tab, pts, COL_INTEG[integ], 0.005, dinamico)
	dinamico.add_child(label3d("λ = 4·10⁴", _tp(tab, lmax, -0.1 * ymax) + Vector3(0, -0.12, 0), Color(0.7, 0.8, 0.95), 0.0028))
	_tabla_mercurio()

func _tabla_mercurio() -> void:
	var teo := Celeste.precesion_teorica()
	var lam := pow(10.0, lam_exp)
	var t := "[b]Relatividad general: %.3f″ por siglo[/b] (Einstein, 1915) · en la escena λ = %s → %.3f° por vuelta · h = %s días" % [
		teo, LabUI.sci(lam, 1), rad_to_deg(teo / Celeste.ARCSEG * Celeste.periodo(Celeste.MERCURIO["a"]) / Celeste.SIGLO * lam), str(h_orb)]
	_csv = [["integrador", "lambda", "precesion_arcsec_siglo"]]
	if _ext.is_empty():
		t += "\n[color=#8fa3b8]Pulsa «📐 Medir y extrapolar» (con este paso tarda unos segundos).[/color]"
	else:
		t += "\n[font_size=12][color=#8fa3b8]  Integrador            │ precesión numérica (λ = 0) │ parábola: c₁ │ recta (sesgada) │ error de c₁[/color]"
		for ex in _ext:
			var integ: int = ex[0]
			var r: Dictionary = ex[1]
			var sq := "[color=#%s]■[/color]" % (COL_INTEG[integ] as Color).to_html(false)
			var c1: float = r["resultado"]
			if not is_finite(c1):
				t += "\n%s %s │ [color=#ff7766]la órbita se desarma: el paso es demasiado grande[/color]" % [sq, Celeste.INTEGRADORES[integ]]
				continue
			t += "\n%s %s │ %s″ │ [b]%.3f″[/b] │ %.3f″ │ %+.3f″" % [sq, Celeste.INTEGRADORES[integ], _miles(r["ordenada"]), c1, r["recta"], c1 - teo]
			for p in r["puntos"]:
				_csv.append([Celeste.INTEGRADORES[integ], p[0], p[1]])
		t += "[/font_size]"
	_info = t

## Avanza cada Mercurio; en cada perihelio (r₀ > r₁ ≤ r₂) deja una marca y anota su longitud.
func _paso_mercurio(dt: float) -> void:
	var dias := dt * 20.0
	var n := mini(int(ceil(dias / h_orb)), 6000)
	_lin.clear_surfaces()
	for c in _merc:
		var integ: int = c["integ"]
		if not c["fuera"]:
			var s: PackedFloat64Array = c["s"]
			for i in n:
				s = Celeste.paso(s, h_orb, c["b"], integ)
				c["t"] = float(c["t"]) + h_orb
				var r2 := sqrt(s[0] * s[0] + s[1] * s[1])
				if not is_finite(r2) or r2 > 3.0 or r2 < 0.01:
					c["fuera"] = true
					break
				var th := atan2(s[1], s[0]) + float(c["vth"])
				if th < float(c["th1"]) - PI:
					c["vth"] = float(c["vth"]) + TAU
					th += TAU
				if float(c["r1"]) < float(c["r0"]) and float(c["r1"]) <= r2:
					var p := Celeste.perihelio(h_orb, c["r0"], c["r1"], r2, c["th0"], c["th1"], th)
					var peris: Array = c["peris"]
					peris.append([float(c["t"]) - h_orb + p[0], p[1] - TAU * (peris.size() + 1)])
					_marca_perihelio(float(c["r1"]), p[1], integ)
				c["r0"] = c["r1"]
				c["r1"] = r2
				c["th0"] = c["th1"]
				c["th1"] = th
				var w := _W(s[0], s[1], 0.004)
				var tr: PackedVector3Array = c["traza"]
				if tr.is_empty() or tr[-1].distance_to(w) > 0.015:
					tr.append(w)
					if tr.size() > 4000:
						tr = tr.slice(tr.size() - 4000)
					c["traza"] = tr
			c["s"] = s
			c["deriva"] = absf((Celeste.energia(s, c["b"]) - float(c["e0"])) / float(c["e0"]))
			(c["mi"] as Node3D).position = _W(s[0], s[1])
			(c["mi"] as Node3D).rotate_y(0.03)
		_polilinea(_lin, c["traza"], COL_INTEG[integ], true)
	if not _merc.is_empty():
		_rotulo.text = "día %d · %.1f vueltas" % [int(_merc[0]["t"]), float(_merc[0]["t"]) / Celeste.periodo(Celeste.MERCURIO["a"])]

func _marca_perihelio(r: float, th: float, integ: int) -> void:
	if _peris_root.get_child_count() > 240:
		var viejo := _peris_root.get_child(0)
		_peris_root.remove_child(viejo)
		viejo.queue_free()
	var p := _W(r * cos(th), r * sin(th), 0.006)
	var n := Node3D.new()
	n.add_child(rod(_W(0.0, 0.0, 0.006), p, 0.0025, glow_mat(COL_INTEG[integ].darkened(0.2), 0.9)))
	_bola(n, 0.018, glow_mat(COL_INTEG[integ], 2.6), p)
	_peris_root.add_child(n)

func _info_mercurio() -> String:
	var s := _info
	var por_vuelta := rad_to_deg(6.0 * PI * Celeste.GM * pow(10.0, lam_exp) / (Celeste.C_LUZ * Celeste.C_LUZ * Celeste.MERCURIO["a"] * (1.0 - pow(Celeste.MERCURIO["e"], 2))))
	for c in _merc:
		var peris: Array = c["peris"]
		var med := "—"
		if peris.size() >= 2:
			var m := Celeste.recta(peris)[0] * Celeste.periodo(Celeste.MERCURIO["a"])
			med = "%.3f° por vuelta" % rad_to_deg(m)
		s += "\n[color=#%s]●[/color] %s: %d perihelios · avance medido %s (teoría con λ: %.3f°) · deriva de energía %s%s" % [
			(COL_INTEG[c["integ"]] as Color).to_html(false), Celeste.INTEGRADORES[c["integ"]], peris.size(), med, por_vuelta,
			LabUI.sci(c["deriva"], 1), " · [color=#ff7766]se salió de la órbita[/color]" if c["fuera"] else ""]
	return s

#endregion

#region Controles, información y estado -----------------------------------------------------

func build_ui(p: VBoxContainer) -> void:
	_opt_pregunta = LabUI.option(p, "Pregunta", PREGUNTAS, pregunta, func(i):
		remember()
		pregunta = i
		_montar()
		_controles()
		_encuadrar())
	_q_box = VBoxContainer.new()
	p.add_child(_q_box)
	_controles()
	LabUI.button(p, "💾 Exportar la tabla (CSV)", _exportar)

## Los controles de la pregunta actual (se rehacen al cambiarla o al cargar un estado).
func _controles() -> void:
	if _q_box == null:
		return
	_opt_pregunta.select(pregunta)
	for c in _q_box.get_children():
		_q_box.remove_child(c)
		c.queue_free()
	var p := _q_box
	match pregunta:
		0:
			LabUI.option(p, "Sistema", ["Sol–Tierra (James Webb)", "Tierra–Luna", "Sol–Júpiter (troyanos)"], sistema, func(i): _cambiar("sistema", i))
			LabUI.option(p, "Punto buscado", ["L1", "L2", "L3"], punto, func(i): _cambiar("punto", i))
			LabUI.option(p, "Método", Celeste.METODOS_RAIZ + ["Los tres a la vez"], metodo_raiz, func(i): _cambiar("metodo_raiz", i))
			LabUI.check(p, "Ver todo el sistema (sin zoom en la Tierra)", vista_todo, func(v): _cambiar("vista_todo", v))
			LabUI.button(p, "⟲ Repetir las iteraciones", func():
				x0 = NAN
				_montar())
			LabUI.section(p, "Una nave en un punto de Lagrange")
			LabUI.option(p, "Soltarla en", LP, nave_lp, func(i): nave_lp = i)
			LabUI.slider(p, "Desvío inicial (km)", 10, 50000, 10, nave_km, func(v): nave_km = v, "%.0f")
			LabUI.button(p, "🚀 Soltar la nave (RK4)", _soltar_nave)
			LabUI.note(p, "Las raíces de f(x) = ∂Ω/∂x son los puntos de equilibrio sobre el eje Sol–planeta. Cada método se ve en su carril: el intervalo de la bisección, las dos secantes o la tangente de Newton. Clic sobre el eje: Newton empieza ahí (si cruza un cuerpo, salta a otra raíz o diverge). En L1–L3 la nave se escapa (equilibrio inestable); en L4 y L5 oscila (estable si μ < 0,0385).")
		1:
			LabUI.slider(p, "Observaciones", 3, 60, 1, n_obs, func(v): _cambiar("n_obs", int(v)), "%d")
			LabUI.slider(p, "Arco observado (días)", 2, 1680, 1, arco, func(v): _cambiar("arco", v), "%.0f")
			LabUI.slider(p, "Error de cada posición (%)", 0.0, 1.0, 0.005, ruido, func(v): _cambiar("ruido", v), "%.3f")
			LabUI.slider(p, "Días hasta que reaparece", 0, 1000, 1, hueco, func(v): _cambiar("hueco", v), "%.0f")
			LabUI.option(p, "Mínimos cuadrados con", ["Ecuaciones normales + Cholesky", "QR (Gram–Schmidt modificado)", "Los dos"], metodo_ls, func(i): _cambiar("metodo_ls", i))
			LabUI.button(p, "🎲 Otras observaciones (nueva semilla)", func(): _cambiar("semilla_obs", semilla_obs + 1))
			LabUI.note(p, "Piazzi siguió a Ceres 41 días (unos 9° de su órbita) y la perdió tras el Sol. Gauss ajustó una órbita por mínimos cuadrados y predijo dónde reaparecería: la encontraron a medio grado. Acorta el arco o sube el error: κ(MᵀM) crece como κ(M)² y la predicción se desvía. Los residuos (rojo) se dibujan aumentados.")
		2:
			LabUI.option(p, "Acercamiento", ["12 ene 2025 (96 millones de km)", "20 feb 2027 (101 millones de km)"], acercamiento, func(i): _cambiar("acercamiento", i))
			LabUI.slider(p, "Paso de la tabla (días)", 1, 60, 1, paso_tabla, func(v): _cambiar("paso_tabla", v), "%.0f")
			LabUI.option(p, "Ver", Celeste.METODOS_MIN + ["Todos"], metodo_min, func(i): _cambiar("metodo_min", i))
			LabUI.note(p, "Como un anuario astronómico: las posiciones salen de la ecuación de Kepler (Newton) cada tantos días; entre nodos se interpola y el mínimo se busca en el interpolante. Las líneas tenues de la escena unen la Tierra y Marte en cada fecha de la tabla.")
		3:
			LabUI.option(p, "Método", Celeste.METODOS_INT, metodo_int, func(i): _cambiar("metodo_int", i))
			LabUI.slider(p, "n (subintervalos o puntos)", 2, 128, 2, n_int, func(v): _cambiar("n_int", int(v)), "%d")
			LabUI.option(p, "Paso de la EDO (RK4)", PASOS_EDO.map(func(h): return "%s días" % _num(h)), _indice(PASOS_EDO, h_edo), func(i): _cambiar("h_edo", PASOS_EDO[i]))
			LabUI.button(p, "⟲ Soltar la Tierra otra vez", func():
				_caida = PackedFloat64Array([1.0, 0.0, 0.0])
				_impacto = -1.0)
			LabUI.note(p, "Cada barra es un nodo de la cuadratura sobre el camino de la caída; su alto, el integrando. Trapecio y Simpson necesitan f(R) = ∞; punto medio y Gauss la esquivan pero convergen despacio (p ≈ ½ y 1). Tanh-sinh amontona nodos junto a la singularidad; el cambio r = R·sen²u la elimina y el integrando queda suave.")
		_:
			LabUI.option(p, "Integrador", Celeste.INTEGRADORES, integrador, func(i): _cambiar("integrador", i))
			LabUI.check(p, "Los tres a la vez", tres, func(v): _cambiar("tres", v))
			LabUI.option(p, "Paso h", PASOS_ORB.map(func(h): return "%s días" % _num(h)), _indice(PASOS_ORB, h_orb), func(i): _cambiar("h_orb", PASOS_ORB[i]))
			LabUI.slider(p, "Exageración en la escena: log₁₀ λ", 0.0, 6.0, 0.25, lam_exp, func(v): _cambiar("lam_exp", v), "%.2f")
			LabUI.slider(p, "Vueltas para medir", 2, 20, 1, vueltas, func(v): vueltas = v, "%.0f")
			LabUI.button(p, "📐 Medir y extrapolar a λ = 1", _medir)
			LabUI.note(p, "La relatividad añade a la gravedad un término 3L²/(c²r²): el perihelio avanza 43″ por siglo, demasiado poco para verlo. Se exagera λ veces, se mide la precesión con varios λ (vértice de la parábola por los tres pasos junto a cada mínimo de r) y se ajusta P(λ) = c₀ + c₁λ + c₂λ²: c₁ es la predicción para λ = 1 y c₀ el error del propio integrador. Euler se sale en espiral; Verlet conserva la energía.")

static func _indice(lista: Array, v: float) -> int:
	var best := 0
	for i in lista.size():
		if absf(float(lista[i]) - v) < absf(float(lista[best]) - v):
			best = i
	return best

## Cambio desde un control: se puede deshacer y rehace la pregunta.
func _cambiar(campo: String, v: Variant) -> void:
	remember()
	set(campo, v)
	if campo == "sistema" or campo == "punto":
		x0 = NAN
	_montar()
	if campo == "vista_todo" or campo == "tres":
		_encuadrar()

func _exportar() -> void:
	if _csv.is_empty():
		return
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS).path_join("MechaForge")
	DirAccess.make_dir_recursive_absolute(dir)
	var ruta := dir.path_join("orbitas_pregunta%d.csv" % (pregunta + 1))
	var f := FileAccess.open(ruta, FileAccess.WRITE)
	if f == null:
		if lab:
			lab._status("⚠ No se pudo guardar %s" % ruta)
		return
	# Punto y coma y coma decimal: así lo abre Excel en español.
	for fila in _csv:
		var celdas := []
		for v in fila:
			celdas.append(_num(v) if typeof(v) == TYPE_FLOAT else str(v))
		f.store_line(";".join(celdas))
	f.close()
	if lab:
		lab._status("Tabla guardada en %s" % ruta)

func step(dt: float) -> void:
	_t += dt
	match pregunta:
		0:
			var k := mini(int(_t / 0.55) + 1, _iter_total())
			if k != _k:
				_k = k
				_dibujar_iter()
			_paso_nave(dt)
		1:
			_paso_ceres()
		2:
			_j += dt * 6.0
			if _j > _ref[0] + 70.0:
				_j = _ref[0] - 70.0
			_paso_marte()
		3:
			_paso_caida(dt)
		_:
			_paso_mercurio(dt)

## Para las capturas (mflabshot <png> celeste p3 [nave]): la pregunta y, en la 1, la nave.
func demo(extra: PackedStringArray) -> void:
	for q in 5:
		if "p%d" % (q + 1) in extra:
			pregunta = q
			_montar()
			_controles()
			_encuadrar()
	if "nave" in extra:
		_soltar_nave()
	if lab:
		lab.cam.snap()

func info() -> String:
	match pregunta:
		0: return _info_lagrange()
		4: return _info_mercurio()
	return _info

func pick(origin: Vector3, dir: Vector3):
	var hit = ray_plane_y(origin, dir, 0.0)
	return hit if hit != null and (hit as Vector3).length() < 3.6 else null

func hover_text(hit: Vector3) -> String:
	var q := _M(hit)
	var x: float = q[0]
	var y: float = q[1]
	if pregunta == 0:
		return "x = %.6f, y = %.6f (distancia %s = 1)\nΩ = %.6f · f(x) = %s" % [x, y, Celeste.SISTEMAS[sistema]["nombre"], Celeste.omega(x, y, _mu), LabUI.sci(Celeste.f_lagrange(x, _mu), 3)]
	var r := sqrt(x * x + y * y)
	return "x = %.3f UA, y = %.3f UA\nr = %.3f UA = %s millones de km" % [x, y, r, "%.1f" % (r * Celeste.KM_UA / 1e6)]

func api_points(x: float, y: float) -> Array:
	return [to_global(_W(x, y))]

func perturb(hit: Vector3, first: bool) -> void:
	if pregunta != 0 or not first:
		return
	var x: float = _M(hit)[0]
	if absf(x - _cx) > _ventana:
		return
	remember()
	x0 = x
	if metodo_raiz == 0 or metodo_raiz == 1:
		metodo_raiz = 2
		_controles()
	_montar()

func critical_points() -> Array:
	var pts := [{"pos": to_global(Vector3.ZERO), "nombre": "Sol", "dist": 5.0}]
	match pregunta:
		0:
			pts = []
			for i in 5:
				if absf(float(_L[i][0]) - _cx) <= _ventana and absf(float(_L[i][1])) <= _ventana:
					pts.append({"pos": to_global(_W(_L[i][0], _L[i][1])), "nombre": LP[i], "dist": 3.0})
		1:
			pts.append({"pos": to_global(_ceres_mi.position), "nombre": "Ceres", "dist": 3.0})
		2:
			pts.append({"pos": to_global(_marte_mi.position), "nombre": "Marte", "dist": 3.0})
			pts.append({"pos": to_global(_tab["c"]), "nombre": "Tablero de la interpolación", "dist": 5.0})
		3:
			pts.append({"pos": to_global(_W(0.97, 0.0, H_CAIDA * 0.6)), "nombre": "La singularidad en r = R", "dist": 2.5})
	return pts

func metricas() -> Dictionary:
	match pregunta:
		0: return {"entidades": _iter_total()}
		1: return {"entidades": _obs.size()}
		2: return {"entidades": _tb[0].size() if _tb.size() == 2 else 0}
		3: return {"entidades": _cuad.get("nodos", []).size()}
	return {"entidades": _merc.size()}

func finito() -> bool:
	for v in _nave:
		if not is_finite(v):
			return false
	for v in _caida:
		if not is_finite(v):
			return false
	return true

const CAMPOS := ["pregunta", "sistema", "punto", "metodo_raiz", "nave_lp", "nave_km", "vista_todo", "n_obs", "arco", "ruido", "hueco",
	"semilla_obs", "metodo_ls", "acercamiento", "paso_tabla", "metodo_min", "metodo_int", "n_int", "h_edo", "integrador", "h_orb",
	"lam_exp", "tres", "vueltas"]
const RANGOS := {"pregunta": [0, 4], "sistema": [0, 2], "punto": [0, 2], "metodo_raiz": [0, 3], "nave_lp": [0, 4], "nave_km": [1.0, 1e6],
	"n_obs": [3, 60], "arco": [1.0, 5000.0], "ruido": [0.0, 5.0], "hueco": [0.0, 5000.0], "semilla_obs": [0, 1 << 30], "metodo_ls": [0, 2],
	"acercamiento": [0, 1], "paso_tabla": [1.0, 60.0], "metodo_min": [0, 3], "metodo_int": [0, 6], "n_int": [2, 128],
	"h_edo": [0.0001, 2.0], "integrador": [0, 2], "h_orb": [0.001, 5.0], "lam_exp": [0.0, 7.0], "vueltas": [2.0, 50.0]}

func estado() -> Dictionary:
	var d := {}
	for k in CAMPOS:
		d[k] = get(k)
	if is_finite(x0):
		d["x0"] = x0
	return d

func cargar(d: Dictionary) -> String:
	for k in CAMPOS:
		if not d.has(k):
			return "falta «%s»" % k
		var tipo := typeof(d[k])
		if k in ["vista_todo", "tres"]:
			if tipo != TYPE_BOOL:
				return "«%s» debe ser verdadero o falso" % k
		elif not tipo in [TYPE_INT, TYPE_FLOAT]:
			return "«%s» debe ser un número" % k
	for k in CAMPOS:
		var v = d[k]
		if RANGOS.has(k):
			var lo = RANGOS[k][0]
			var hi = RANGOS[k][1]
			if float(v) < float(lo) or float(v) > float(hi):
				return "«%s» = %s fuera de [%s, %s]" % [k, str(v), str(lo), str(hi)]
			v = int(v) if typeof(lo) == TYPE_INT else float(v)
		set(k, v)
	x0 = float(d["x0"]) if typeof(d.get("x0")) in [TYPE_INT, TYPE_FLOAT] else NAN
	_montar()
	_controles()
	return ""

func fidelidad() -> Array:
	return [
		{"subsistema": "1 · Puntos de Lagrange y la nave", "nivel": "exacto",
			"modelo": "Problema restringido circular de tres cuerpos en el plano: la nave no perturba a los dos cuerpos, que giran en círculos. Las raíces de ∂Ω/∂x se buscan en doble precisión; la nave se integra con RK4 de paso fijo (la deriva de la constante de Jacobi mide su error)",
			"ecuaciones": "Ω = (x²+y²)/2 + (1−μ)/r₁ + μ/r₂; f(x) = ∂Ω/∂x|_{y=0} = 0; ẍ − 2ẏ = ∂Ω/∂x, ÿ + 2ẋ = ∂Ω/∂y",
			"unidades": "canónicas: distancia entre los dos cuerpos = 1, periodo = 2π; km con la distancia real",
			"referencias": "Murray y Dermott, Solar System Dynamics, cap. 3; NASA: el JWST orbita en torno a L2, a unos 1,5 millones de km"},
		{"subsistema": "2 · La órbita de Ceres", "nivel": "aproximado",
			"modelo": "Simplificación del problema de Gauss: él solo tenía ángulos medidos desde la Tierra; aquí se ajustan posiciones heliocéntricas (r, θ) con ruido gaussiano en el plano de la eclíptica (Ceres está inclinada 10,6°). La órbita de Ceres es la kepleriana con a = 2,7675 UA, e = 0,0785",
			"ecuaciones": "1/r = A + B cos θ + C sen θ; e = √(B²+C²)/A, a = 1/(A(1−e²)); (MᵀM)c = Mᵀy o M = QR",
			"unidades": "UA, días, grados", "referencias": "Gauss, Theoria motus (1809); Teets y Whitehead, The discovery of Ceres, Math. Magazine 72 (1999)"},
		{"subsistema": "3 · Efemérides de Marte", "nivel": "aproximado",
			"modelo": "Elementos keplerianos medios de JPL (E. M. Standish, tabla 1, válidos de 1800 a 2050) con la ecuación de Kepler por Newton: errores de minutos de arco, así que el mínimo sale a horas de la fecha publicada. Sin perturbaciones entre planetas",
			"ecuaciones": "M = L − ϖ; E − e sen E = M; d(t) = |r_Marte − r_Tierra|",
			"unidades": "UA, km, fechas en UT (≈ TT)", "referencias": "ssd.jpl.nasa.gov/planets/approx_pos.html; NASA: acercamientos del 12-ene-2025 y el 20-feb-2027"},
		{"subsistema": "4 · La caída al Sol", "nivel": "exacto",
			"modelo": "Problema radial de dos cuerpos: la Tierra como partícula, el Sol fijo y puntual hasta su superficie (radio 695 700 km). Tiempo hasta el centro y hasta la superficie en forma cerrada",
			"ecuaciones": "t(r) = √(R³/2GM)(√(x(1−x)) + arccos √x), x = r/R; r̈ = −GM/r²",
			"unidades": "UA, días; GM del Sol = k² con k = 0,01720209895", "referencias": "Danby, Fundamentals of Celestial Mechanics, §6"},
		{"subsistema": "5 · La precesión de Mercurio", "nivel": "aproximado",
			"modelo": "Corrección de Schwarzschild a primer orden (1PN) para una partícula de prueba, exagerada λ veces para medirla; L se toma constante (la fuerza es central). Sin los demás planetas, que añaden otros 532″ por siglo",
			"ecuaciones": "r̈ = −GM r/r³ (1 + 3λL²/(c²r²)); Δϖ = 6πGM/(c²a(1−e²)) por vuelta",
			"unidades": "UA, días, segundos de arco por siglo", "referencias": "Einstein (1915); Weinberg, Gravitation and Cosmology, §8.6"},
		{"subsistema": "Escena 3D", "nivel": "ilustrativo",
			"modelo": "Los tamaños del Sol y de los planetas no están a escala (a escala no se verían); las órbitas y las distancias sí. El potencial efectivo y f(x) se comprimen con tanh y atan para que quepan",
			"ecuaciones": "", "unidades": "las de cada pregunta", "referencias": ""},
	]

#endregion
