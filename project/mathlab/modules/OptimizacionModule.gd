extends LabModule
## Optimización multivariable sobre z = f(x, y) (superficie evaluada en la GPU):
## gradiente descendente (con momento opcional) y método de Newton con la
## hessiana. Clic en la superficie para elegir el punto de partida: las dos
## trayectorias bajan a la vez y dos bolas ruedan por ellas.

const SIZE := 4.0
const HEIGHT := 2.0
const PRESETS := [
	["Cuenco elíptico", "x^2 + 3y^2", -2.0, 2.0, -2.0, 2.0, false, Vector2(1.8, 1.4)],
	["Rosenbrock (valle curvo)", "(1 - x)^2 + 100(y - x^2)^2", -2.0, 2.0, -1.0, 3.0, true, Vector2(-1.5, 2.0)],
	["Himmelblau (4 mínimos)", "(x^2 + y - 11)^2 + (x + y^2 - 7)^2", -5.0, 5.0, -5.0, 5.0, true, Vector2(0.3, 0.5)],
	["Punto de silla", "x^2 - y^2", -2.0, 2.0, -2.0, 2.0, false, Vector2(1.5, 0.05)],
	["Rastrigin (muchos mínimos locales)", "20 + x^2 + y^2 - 10(cos(2 pi x) + cos(2 pi y))", -3.0, 3.0, -3.0, 3.0, false, Vector2(2.3, 1.7)],
	["Gaussianas (dos pozos)", "-2exp(-((x-1)^2 + y^2)) - exp(-((x+1.2)^2 + (y-0.8)^2)/0.5)", -3.0, 3.0, -3.0, 3.0, false, Vector2(0.0, 1.8)],
]

var expr: MathExpr
var preset: int = 1
var dmin := Vector2(-2, -1)
var dmax := Vector2(2, 3)
var log_mode: bool = true
var zr := Vector2(0, 1)
var mesh: MeshInstance3D
var mat: ShaderMaterial
var start := Vector2(-1.5, 2.0)
var alpha: float = 0.0015
var beta: float = 0.0
var max_iter: int = 400
var gd_path: Array = []
var nt_path: Array = []
var paths_node: Node3D
var balls: Array = []
var _t: float = 0.0
var _ef: LineEdit

func title() -> String: return "Optimización multivariable"
func formula() -> String: return "GD: xₖ₊₁ = xₖ − α∇f + β(xₖ − xₖ₋₁)   ·   Newton: xₖ₊₁ = xₖ − H⁻¹∇f"
func uses_time() -> bool: return true
func perturb_hint() -> String: return "clic sobre la superficie: punto de partida de los dos métodos"
func view() -> Dictionary: return {"target": Vector3(0, 0.6, 0), "dist": 7.5, "yaw": -35.0, "pitch": -35.0}

func setup() -> void:
	scale_xy = SIZE * 0.5
	mesh = MeshInstance3D.new()
	mesh.mesh = SurfaceShader.plane(SIZE, 220)
	add_child(mesh)
	paths_node = Node3D.new()
	add_child(paths_node)
	for c in [Color(1.0, 0.55, 0.15), Color(0.3, 1.0, 0.5)]:
		var b := sphere(0.07, glow_mat(c, 3.0))
		add_child(b)
		balls.append(b)
	_load_preset(preset)

func _load_preset(i: int) -> void:
	var p: Array = PRESETS[i]
	dmin = Vector2(p[2], p[4])
	dmax = Vector2(p[3], p[5])
	log_mode = p[6]
	start = p[7]
	alpha = 0.0015 if i == 1 else (0.01 if i == 2 else 0.08)
	_set_expr(MathExpr.parse(p[1], ["x", "y"]))

func _set_expr(m: MathExpr) -> void:
	expr = m
	expr.compile_fast()
	zr = SurfaceShader.value_range(expr, dmin, dmax, 80)
	mat = ShaderMaterial.new()
	mat.shader = SurfaceShader.make(expr)
	mat.set_shader_parameter("dom_min", dmin)
	mat.set_shader_parameter("dom_max", dmax)
	mat.set_shader_parameter("world_size", SIZE)
	mat.set_shader_parameter("zmin", zr.x)
	mat.set_shader_parameter("zmax", zr.y)
	mat.set_shader_parameter("height", HEIGHT)
	mat.set_shader_parameter("log_mode", log_mode)
	mat.set_shader_parameter("pal", 0)
	mat.set_shader_parameter("contour_step", 0.04)
	mesh.material_override = mat
	clip_materials.clear()
	register_clip(mat)
	_run()

func F(x: float, y: float) -> float:
	return expr.eval_fast([x, y])

func grad(x: float, y: float) -> Vector2:
	var h := 1e-5 * maxf(1.0, maxf(absf(x), absf(y)))
	return Vector2((F(x + h, y) - F(x - h, y)) / (2 * h), (F(x, y + h) - F(x, y - h)) / (2 * h))

func hessian(x: float, y: float) -> Array:
	var h := 1e-4 * maxf(1.0, maxf(absf(x), absf(y)))
	var fxx := (F(x + h, y) - 2 * F(x, y) + F(x - h, y)) / (h * h)
	var fyy := (F(x, y + h) - 2 * F(x, y) + F(x, y - h)) / (h * h)
	var fxy := (F(x + h, y + h) - F(x + h, y - h) - F(x - h, y + h) + F(x - h, y - h)) / (4 * h * h)
	return [fxx, fxy, fyy]

func hnorm(f: float) -> float:
	var v := log(1.0 + maxf(f - zr.x, 0.0)) / log(1.0 + zr.y - zr.x) if log_mode else (f - zr.x) / maxf(1e-6, zr.y - zr.x)
	return clampf(v, -0.05, 1.05)

func surf(x: float, y: float) -> Vector3:
	var u := (x - dmin.x) / (dmax.x - dmin.x)
	var v := (y - dmin.y) / (dmax.y - dmin.y)
	return Vector3((u - 0.5) * SIZE, hnorm(F(x, y)) * HEIGHT + 0.025, -(v - 0.5) * SIZE)

func _run() -> void:
	gd_path = [start]
	var x := start
	var prev := start
	for k in range(max_iter):
		var g := grad(x.x, x.y)
		var xn := x - alpha * g + beta * (x - prev)
		prev = x
		x = xn
		if not x.is_finite() or x.x < dmin.x - 1 or x.x > dmax.x + 1 or x.y < dmin.y - 1 or x.y > dmax.y + 1:
			break
		gd_path.append(x)
		if g.length() < 1e-6 or (x - prev).length() < 1e-9:
			break
	nt_path = [start]
	x = start
	for k in range(60):
		var g2 := grad(x.x, x.y)
		var H := hessian(x.x, x.y)
		var det: float = H[0] * H[2] - H[1] * H[1]
		if absf(det) < 1e-12:
			break
		var dx := Vector2((H[2] * g2.x - H[1] * g2.y) / det, (-H[1] * g2.x + H[0] * g2.y) / det)
		var xn2 := x - dx
		if not xn2.is_finite():
			break
		x = xn2
		nt_path.append(x)
		if dx.length() < 1e-10:
			break
	_draw_paths()
	_t = 0.0

func _draw_paths() -> void:
	for c in paths_node.get_children():
		c.queue_free()
	for spec in [[gd_path, Color(1.0, 0.55, 0.15)], [nt_path, Color(0.3, 1.0, 0.5)]]:
		var pts := PackedVector3Array()
		for q in spec[0]:
			var v: Vector2 = q
			if v.x < dmin.x or v.x > dmax.x or v.y < dmin.y or v.y > dmax.y:
				continue
			pts.append(surf(v.x, v.y))
		var m := glow_mat(spec[1], 2.0)
		if pts.size() >= 2:
			paths_node.add_child(tube(pts, 0.014, m, 6))
		var stride := maxi(1, pts.size() / 25)
		for i in range(0, pts.size(), stride):
			var s := sphere(0.022, m)
			s.position = pts[i]
			paths_node.add_child(s)
	var st := sphere(0.05, glow_mat(Color(1, 1, 1), 3.0))
	st.position = surf(start.x, start.y)
	paths_node.add_child(st)

func step(dt: float) -> void:
	_t += dt
	var paths := [gd_path, nt_path]
	var speeds := [maxf(1.0, gd_path.size() / 5.0), 2.5]
	for i in range(2):
		var path: Array = paths[i]
		if path.is_empty():
			continue
		var f := fmod(_t * float(speeds[i]), float(path.size()) + 8.0)
		var k := mini(int(f), path.size() - 1)
		var k2 := mini(k + 1, path.size() - 1)
		var a: Vector2 = path[k]
		var b: Vector2 = path[k2]
		var p := a.lerp(b, clampf(f - k, 0.0, 1.0))
		(balls[i] as Node3D).position = surf(p.x, p.y) + Vector3(0, 0.05, 0)

func reset() -> void:
	_load_preset(preset)

func build_ui(p: VBoxContainer) -> void:
	var names := []
	for q in PRESETS:
		names.append(q[0])
	LabUI.option(p, "Función:", names, preset, func(i):
		preset = i
		_load_preset(i)
		if _ef: _ef.text = PRESETS[i][1])
	_ef = LabUI.expr_field(p, "f(x, y) =", PRESETS[preset][1], ["x", "y"], false, func(m): _set_expr(m))
	LabUI.check(p, "Altura logarítmica (gran rango de valores)", log_mode, func(v):
		log_mode = v
		mat.set_shader_parameter("log_mode", v)
		_draw_paths())
	LabUI.section(p, "Gradiente descendente (naranja)")
	LabUI.slider(p, "Paso α", 0.0001, 0.3, 0.0001, alpha, func(v):
		alpha = v
		_run(), "%.4f")
	LabUI.slider(p, "Momento β", 0.0, 0.95, 0.01, beta, func(v):
		beta = v
		_run())
	LabUI.slider(p, "Iteraciones máx.", 10, 3000, 10, max_iter, func(v):
		max_iter = int(v)
		_run(), "%.0f")
	LabUI.note(p, "Newton (verde) usa la curvatura (hessiana): converge en muy pocos pasos cerca de un mínimo, pero también puede ir a un punto de silla o a un máximo. El gradiente descendente necesita un α pequeño en valles estrechos (Rosenbrock) y el momento lo acelera.")

func pick(origin: Vector3, dir: Vector3):
	var hf := func(X: float, Z: float) -> float:
		var x := lerpf(dmin.x, dmax.x, X / SIZE + 0.5)
		var y := lerpf(dmin.y, dmax.y, 0.5 - Z / SIZE)
		return hnorm(F(x, y)) * HEIGHT
	return ray_heightfield(origin, dir, hf, SIZE * 0.5)

func _xy(hit: Vector3) -> Vector2:
	return Vector2(lerpf(dmin.x, dmax.x, hit.x / SIZE + 0.5), lerpf(dmin.y, dmax.y, 0.5 - hit.z / SIZE))

## (x, y) dentro de la región [dmin, dmax] del dominio, como el tooltip.
func api_points(x: float, y: float) -> Array:
	var u := (x - dmin.x) / (dmax.x - dmin.x) - 0.5
	var v := 0.5 - (y - dmin.y) / (dmax.y - dmin.y)
	return [to_global(Vector3(u * SIZE, 0.0, v * SIZE))]

func hover_text(hit: Vector3) -> String:
	var q := _xy(hit)
	var g := grad(q.x, q.y)
	return "x = %.3f   y = %.3f\nf = %.5f\n‖∇f‖ = %.4f" % [q.x, q.y, F(q.x, q.y), g.length()]

func perturb(hit: Vector3, first: bool) -> void:
	if first:
		start = _xy(hit)
		_run()

func critical_points() -> Array:
	var out := []
	if gd_path.size() > 0:
		var e: Vector2 = gd_path[gd_path.size() - 1]
		out.append({"pos": surf(e.x, e.y), "nombre": "Final del gradiente (%.3f, %.3f)" % [e.x, e.y], "dist": 2.2})
	if nt_path.size() > 0:
		var n: Vector2 = nt_path[nt_path.size() - 1]
		out.append({"pos": surf(n.x, n.y), "nombre": "Final de Newton (%.3f, %.3f)" % [n.x, n.y], "dist": 2.2})
	out.append({"pos": surf(start.x, start.y), "nombre": "Punto de partida", "dist": 2.8})
	return out

func info() -> String:
	var t := ""
	if gd_path.size() > 0:
		var e: Vector2 = gd_path[gd_path.size() - 1]
		t += "[color=#ff9a40]Gradiente[/color]: %d iter. → (%.4f, %.4f), f = %.6f, ‖∇f‖ = %s\n" % [gd_path.size() - 1, e.x, e.y, F(e.x, e.y), LabUI.sci(grad(e.x, e.y).length(), 1)]
	if nt_path.size() > 0:
		var n: Vector2 = nt_path[nt_path.size() - 1]
		var H := hessian(n.x, n.y)
		var det: float = H[0] * H[2] - H[1] * H[1]
		var kind := "mínimo" if det > 0 and H[0] > 0 else ("máximo" if det > 0 else "punto de silla")
		t += "[color=#55ff88]Newton[/color]: %d iter. → (%.4f, %.4f), f = %.6f (%s)" % [nt_path.size() - 1, n.x, n.y, F(n.x, n.y), kind]
	return t
