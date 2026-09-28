extends LabModule
## Integración numérica doble ∬_R f(x, y) dA: la superficie (GPU) y los prismas
## de la regla elegida (punto medio, trapecio o Simpson) con n × n celdas. Tabla
## con el valor de cada regla, su error frente a una referencia de alta precisión
## y el orden de convergencia observado al duplicar n.

const SIZE := 4.0
const HEIGHT := 1.6
const PRESETS := [
	["Campana gaussiana", "exp(-(x^2 + y^2))", -2.0, 2.0, -2.0, 2.0],
	["Seno por coseno + 1", "sin(x) cos(y) + 1", 0.0, 3.14159265, -1.5707963, 1.5707963],
	["Paraboloide", "4 - x^2 - y^2", -1.5, 1.5, -1.5, 1.5],
	["Oscilante", "1 + 0.5 sin(3x) sin(3y)", -2.0, 2.0, -2.0, 2.0],
	["Pirámide |x| + |y|", "2 - abs(x) - abs(y)", -1.0, 1.0, -1.0, 1.0],
]
const RULES := ["Punto medio (prismas)", "Trapecio", "Simpson"]

var expr: MathExpr
var preset: int = 0
var dmin := Vector2(-2, -2)
var dmax := Vector2(2, 2)
var n: int = 8
var rule: int = 0
var zr := Vector2(0, 1)
var mesh: MeshInstance3D
var mat: ShaderMaterial
var prisms: MultiMeshInstance3D
var reference: float = 0.0
var results: Dictionary = {}

func title() -> String: return "Integración numérica"
func formula() -> String: return "∬_R f(x,y) dA ≈ Σᵢⱼ wᵢⱼ f(xᵢ, yⱼ) ΔxΔy"
func perturb_hint() -> String: return "clic: aumenta la resolución n (Mayús+clic: la reduce)"
func view() -> Dictionary: return {"target": Vector3(0, 0.3, 0), "dist": 7.2, "yaw": -35.0, "pitch": -30.0}

func setup() -> void:
	scale_xy = SIZE * 0.5
	mesh = MeshInstance3D.new()
	mesh.mesh = SurfaceShader.plane(SIZE, 200)
	add_child(mesh)
	prisms = MultiMeshInstance3D.new()
	add_child(prisms)
	_load(preset)

func _load(i: int) -> void:
	var p: Array = PRESETS[i]
	dmin = Vector2(p[2], p[4])
	dmax = Vector2(p[3], p[5])
	_set_expr(MathExpr.parse(p[1], ["x", "y"]))

func _set_expr(m: MathExpr) -> void:
	expr = m
	expr.compile_fast()
	zr = SurfaceShader.value_range(expr, dmin, dmax, 60)
	zr.x = minf(zr.x, 0.0)
	mat = ShaderMaterial.new()
	mat.shader = SurfaceShader.make(expr)
	mat.set_shader_parameter("dom_min", dmin)
	mat.set_shader_parameter("dom_max", dmax)
	mat.set_shader_parameter("world_size", SIZE)
	mat.set_shader_parameter("zmin", zr.x)
	mat.set_shader_parameter("zmax", zr.y)
	mat.set_shader_parameter("height", HEIGHT)
	mat.set_shader_parameter("pal", 2)
	mat.set_shader_parameter("contour_step", 0.0)
	mesh.material_override = mat
	clip_materials.clear()
	register_clip(mat)
	reference = simpson(400)
	_compute()

func F(x: float, y: float) -> float:
	return expr.eval_fast([x, y])

func midpoint(k: int) -> float:
	var hx := (dmax.x - dmin.x) / k
	var hy := (dmax.y - dmin.y) / k
	var s := 0.0
	for j in range(k):
		for i in range(k):
			s += F(dmin.x + (i + 0.5) * hx, dmin.y + (j + 0.5) * hy)
	return s * hx * hy

func trapezoid(k: int) -> float:
	var hx := (dmax.x - dmin.x) / k
	var hy := (dmax.y - dmin.y) / k
	var s := 0.0
	for j in range(k + 1):
		var wy := 0.5 if (j == 0 or j == k) else 1.0
		for i in range(k + 1):
			var wx := 0.5 if (i == 0 or i == k) else 1.0
			s += wx * wy * F(dmin.x + i * hx, dmin.y + j * hy)
	return s * hx * hy

func simpson(k: int) -> float:
	if k % 2 == 1: k += 1
	var hx := (dmax.x - dmin.x) / k
	var hy := (dmax.y - dmin.y) / k
	var s := 0.0
	for j in range(k + 1):
		var wy := 1.0 if (j == 0 or j == k) else (4.0 if j % 2 == 1 else 2.0)
		for i in range(k + 1):
			var wx := 1.0 if (i == 0 or i == k) else (4.0 if i % 2 == 1 else 2.0)
			s += wx * wy * F(dmin.x + i * hx, dmin.y + j * hy)
	return s * hx * hy / 9.0

func _compute() -> void:
	results.clear()
	var fns := [midpoint, trapezoid, simpson]
	for r in range(3):
		var k := n if r < 2 or n % 2 == 0 else n + 1
		var v: float = fns[r].call(k)
		var v2: float = fns[r].call(k * 2)
		var e1 := absf(v - reference)
		var e2 := absf(v2 - reference)
		var order := log(e1 / e2) / log(2.0) if e1 > 1e-14 and e2 > 1e-14 else NAN
		results[r] = {"valor": v, "error": e1, "orden": order, "n": k}
	_draw_prisms()

func _hnorm(f: float) -> float:
	return (f - zr.x) / maxf(1e-6, zr.y - zr.x)

func _draw_prisms() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(1, 1, 1)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = box
	mm.instance_count = n * n
	var hx := (dmax.x - dmin.x) / n
	var hy := (dmax.y - dmin.y) / n
	var cw := SIZE / n
	var y0 := _hnorm(0.0) * HEIGHT
	for j in range(n):
		for i in range(n):
			var x := dmin.x + (i + 0.5) * hx
			var y := dmin.y + (j + 0.5) * hy
			var f: float
			match rule:
				0: f = F(x, y)
				1: f = 0.25 * (F(x - hx * 0.5, y - hy * 0.5) + F(x + hx * 0.5, y - hy * 0.5) + F(x - hx * 0.5, y + hy * 0.5) + F(x + hx * 0.5, y + hy * 0.5))
				_: f = (F(x - hx * 0.5, y - hy * 0.5) + F(x + hx * 0.5, y - hy * 0.5) + F(x - hx * 0.5, y + hy * 0.5) + F(x + hx * 0.5, y + hy * 0.5) + 16.0 * F(x, y) + 4.0 * (F(x - hx * 0.5, y) + F(x + hx * 0.5, y) + F(x, y - hy * 0.5) + F(x, y + hy * 0.5))) / 36.0
			var top := _hnorm(f) * HEIGHT
			var h := top - y0
			var X := (float(i) + 0.5) / n * SIZE - SIZE * 0.5
			var Z := -((float(j) + 0.5) / n * SIZE - SIZE * 0.5)
			var xf := Transform3D(Basis.from_scale(Vector3(cw * 0.94, maxf(0.002, absf(h)), cw * 0.94)), Vector3(X, y0 + h * 0.5, Z))
			mm.set_instance_transform(j * n + i, xf)
			var t := clampf(_hnorm(f), 0.0, 1.0)
			mm.set_instance_color(j * n + i, Color.from_hsv(0.62 - t * 0.5, 0.75, 1.0, 0.55) if f >= 0.0 else Color(1.0, 0.3, 0.3, 0.55))
	prisms.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.2
	m.metallic_specular = 0.8
	m.emission_enabled = true
	m.emission = Color(0.1, 0.3, 0.5)
	m.emission_energy_multiplier = 0.4
	prisms.material_override = m

func build_ui(p: VBoxContainer) -> void:
	var names := []
	for q in PRESETS: names.append(q[0])
	LabUI.option(p, "Función:", names, preset, func(i):
		preset = i
		_load(i))
	LabUI.expr_field(p, "f(x, y) =", PRESETS[preset][1], ["x", "y"], false, func(m): _set_expr(m))
	LabUI.option(p, "Prismas de la regla:", RULES, rule, func(i):
		rule = i
		_draw_prisms())
	LabUI.slider(p, "Celdas por lado n", 1, 64, 1, n, func(v):
		n = int(v)
		_compute(), "%.0f")
	LabUI.note(p, "Punto medio y trapecio son de orden 2 (el error ÷4 al duplicar n); Simpson es de orden 4 (÷16). El prisma de Simpson usa la media ponderada 1-4-1 × 1-4-1 de su celda.")

func pick(origin: Vector3, dir: Vector3):
	var hf := func(X: float, Z: float) -> float:
		var x := lerpf(dmin.x, dmax.x, X / SIZE + 0.5)
		var y := lerpf(dmin.y, dmax.y, 0.5 - Z / SIZE)
		return _hnorm(F(x, y)) * HEIGHT
	return ray_heightfield(origin, dir, hf, SIZE * 0.5)

func hover_text(hit: Vector3) -> String:
	var x := lerpf(dmin.x, dmax.x, hit.x / SIZE + 0.5)
	var y := lerpf(dmin.y, dmax.y, 0.5 - hit.z / SIZE)
	return "x = %.3f   y = %.3f\nf(x, y) = %.5f" % [x, y, F(x, y)]

func perturb(_hit: Vector3, first: bool) -> void:
	if first:
		n = clampi(n + (-2 if Input.is_key_pressed(KEY_SHIFT) else 2), 1, 64)
		_compute()

func info() -> String:
	var t := "Referencia (Simpson n = 400): [color=#ffcc55]%.10f[/color]\n" % reference
	for r in range(3):
		if not results.has(r):
			continue
		var d: Dictionary = results[r]
		t += "%s  n=%d: %.8f · error %s%s\n" % [RULES[r].split(" (")[0], d["n"], d["valor"], LabUI.sci(d["error"], 2),
			" · orden ≈ %.2f" % d["orden"] if not is_nan(float(d["orden"])) else ""]
	return t.strip_edges()
