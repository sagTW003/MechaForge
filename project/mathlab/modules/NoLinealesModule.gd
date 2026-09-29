extends LabModule
## Sistemas de ecuaciones no lineales F(x, y) = 0 (dos ecuaciones, dos incógnitas).
## Las soluciones son los cruces de las curvas f₁ = 0 (roja) y f₂ = 0 (azul),
## calculadas por marching squares. Siete métodos dibujan su trayectoria desde el
## mismo punto: Newton, Newton amortiguado (búsqueda lineal), Broyden
## (cuasi-Newton), punto fijo, Gauss-Seidel no lineal, descenso de gradiente sobre
## ½‖F‖² y Levenberg–Marquardt. El plano se colorea en la GPU con las cuencas de
## atracción de Newton (a qué solución converge cada punto de partida).

const METHODS := ["Newton-Raphson", "Newton amortiguado (búsqueda lineal)", "Broyden (cuasi-Newton)", "Punto fijo x = G(x)",
	"Gauss-Seidel no lineal", "Descenso de gradiente sobre ½‖F‖²", "Levenberg–Marquardt"]
const SHORT := ["Newton", "Newton amortiguado", "Broyden", "Punto fijo", "Gauss-Seidel NL", "Descenso", "Levenberg–Marquardt"]
const COLORS := [Color(1.0, 1.0, 1.0), Color(0.3, 1.0, 0.6), Color(1.0, 0.8, 0.25), Color(1.0, 0.45, 0.85),
	Color(0.4, 0.75, 1.0), Color(1.0, 0.45, 0.3), Color(0.75, 0.55, 1.0)]
const ORDER_TH := ["2", "2 (cerca de x*)", "superlineal", "1", "1", "1", "2 (λ → 0)"]
const PRESETS := [
	{"nombre": "Círculo x² + y² = 4 y parábola y = x² − 1", "f1": "x^2 + y^2 - 4", "f2": "y - x^2 + 1", "g1": "sqrt(y + 1)", "g2": "sqrt(4 - x^2)", "x0": [1.0, 1.0], "R": 3.0},
	{"nombre": "Burden–Faires (punto fijo converge a (1, 1))", "f1": "x^2 - 10x + y^2 + 8", "f2": "x y^2 + x - 10y + 8", "g1": "(x^2 + y^2 + 8)/10", "g2": "(x y^2 + x + 8)/10", "x0": [0.0, 0.0], "R": 4.0},
	{"nombre": "z³ = 1 en forma real (cuencas fractales)", "f1": "x^3 - 3x y^2 - 1", "f2": "3x^2 y - y^3", "g1": "x - (x^3 - 3x y^2 - 1)/3", "g2": "y - (3x^2 y - y^3)/3", "x0": [-0.5, 0.6], "R": 2.0},
	{"nombre": "Elipse e hipérbola (4 soluciones)", "f1": "x^2/4 + y^2 - 1", "f2": "x^2 - y^2 - 1", "g1": "sqrt(1 + y^2)", "g2": "sqrt(1 - x^2/4)", "x0": [1.5, 0.8], "R": 2.5},
	{"nombre": "∇ Himmelblau = 0 (9 puntos críticos)", "f1": "4x(x^2 + y - 11) + 2(x + y^2 - 7)", "f2": "2(x^2 + y - 11) + 4y(x + y^2 - 7)", "g1": "x - 0.01(4x(x^2 + y - 11) + 2(x + y^2 - 7))", "g2": "y - 0.01(2(x^2 + y - 11) + 4y(x + y^2 - 7))", "x0": [0.5, 0.5], "R": 5.0},
	{"nombre": "∇ Rosenbrock = 0 (valle curvo)", "f1": "-2(1 - x) - 400x(y - x^2)", "f2": "200(y - x^2)", "g1": "x - 0.001(-2(1 - x) - 400x(y - x^2))", "g2": "y - 0.001(200(y - x^2))", "x0": [-1.2, 1.0], "R": 2.0},
]
const SIZE := 5.0
const TOL := 1e-11

const BASIN_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
#include "res://mathlab/shaders/common.gdshaderinc"
/*PRELUDE*/
uniform float R = 3.0;
uniform float half_size = 2.5;
uniform vec2 roots[12];
uniform int nroots = 0;
uniform int max_iter = 40;
uniform float strength = 1.0;
varying vec2 P;
varying vec3 wpos;

vec2 F(vec2 p) {
	float x = p.x;
	float y = p.y;
	return vec2(/*F1*/, /*F2*/);
}

void vertex() {
	P = vec2(VERTEX.x, -VERTEX.z) / half_size * R;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (clipped(wpos)) discard;
	vec2 p = P;
	int hit = -1;
	int it = max_iter;
	float tol = 2e-3 * max(1.0, R);
	for (int k = 0; k < max_iter; k++) {
		vec2 f = F(p);
		float h = 1e-3 * max(1.0, length(p));
		vec2 fx = (F(p + vec2(h, 0.0)) - F(p - vec2(h, 0.0))) / (2.0 * h);
		vec2 fy = (F(p + vec2(0.0, h)) - F(p - vec2(0.0, h))) / (2.0 * h);
		float det = fx.x * fy.y - fy.x * fx.y;
		if (abs(det) < 1e-20) break;
		p -= vec2(fy.y * f.x - fy.x * f.y, -fx.y * f.x + fx.x * f.y) / det;
		for (int r = 0; r < 12; r++) {
			if (r < nroots && distance(p, roots[r]) < tol) { hit = r; it = k; break; }
		}
		if (hit >= 0) break;
	}
	vec3 col = vec3(0.015, 0.02, 0.03);
	if (hit >= 0) {
		col = hue_color(6.2831853 * (float(hit) + 0.15) / float(max(nroots, 1))) * 0.8 + 0.1;
		col *= 1.0 - 0.75 * clamp(float(it) / 18.0, 0.0, 1.0);
	}
	float g = grid_lines(P, max(0.5, floor(R / 2.0 + 0.5)), 0.6);
	col = mix(col * strength, vec3(0.75, 0.85, 1.0), g * 0.18);
	ALBEDO = col;
}
"""

var preset: int = 0
var R: float = 3.0
var f1: MathExpr
var f2: MathExpr
var g1: MathExpr
var g2: MathExpr
var start := [1.0, 1.0]
var n_iter: int = 30
var shown: Array = [true, true, true, true, false, false, true]
var show_basins: bool = true
var roots: Array = []          # [[x, y], …]
var paths: Array = []          # por método: [[x, y], …]
var basin: MeshInstance3D
var basin_mat: ShaderMaterial
var curves_node: Node3D
var paths_node: Node3D
var plot: Control
var _ui := {}

func title() -> String: return "Sistemas no lineales"
func formula() -> String: return "F(x) = 0   ·   Newton: J(xₖ)·Δ = −F(xₖ)   ·   Broyden: Bₖ₊₁ = Bₖ + (y − BₖΔ)Δᵀ/ΔᵀΔ"
func perturb_hint() -> String: return "clic en el plano: nuevo punto de partida (x₀, y₀)"
func view() -> Dictionary: return {"target": Vector3(0, 0, 0), "dist": 7.0, "yaw": -20.0, "pitch": -55.0}

func setup() -> void:
	basin = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(SIZE, SIZE)
	basin.mesh = pm
	basin.position = Vector3(0, 0.01, 0)
	add_child(basin)
	curves_node = Node3D.new()
	add_child(curves_node)
	paths_node = Node3D.new()
	add_child(paths_node)
	load_preset(0)

func _s() -> float:
	return SIZE * 0.5 / R

func _w(x: float, y: float, h: float = 0.03) -> Vector3:
	return Vector3(x * _s(), h, -y * _s())

func F(x: float, y: float) -> Array:
	return [f1.eval_fast([x, y]), f2.eval_fast([x, y])]

func norm_F(x: float, y: float) -> float:
	var f := F(x, y)
	return sqrt(float(f[0]) * float(f[0]) + float(f[1]) * float(f[1]))

## Jacobiano por diferencias centradas: [[∂f₁/∂x, ∂f₁/∂y], [∂f₂/∂x, ∂f₂/∂y]].
func J(x: float, y: float) -> Array:
	var h := 1e-7 * maxf(1.0, maxf(absf(x), absf(y)))
	var fxp := F(x + h, y)
	var fxm := F(x - h, y)
	var fyp := F(x, y + h)
	var fym := F(x, y - h)
	return [[(float(fxp[0]) - float(fxm[0])) / (2 * h), (float(fyp[0]) - float(fym[0])) / (2 * h)],
		[(float(fxp[1]) - float(fxm[1])) / (2 * h), (float(fyp[1]) - float(fym[1])) / (2 * h)]]

static func solve2(M: Array, r: Array) -> Array:
	var det: float = M[0][0] * M[1][1] - M[0][1] * M[1][0]
	if absf(det) < 1e-300 or not is_finite(det):
		return []
	return [(M[1][1] * r[0] - M[0][1] * r[1]) / det, (-M[1][0] * r[0] + M[0][0] * r[1]) / det]

func load_preset(i: int) -> void:
	preset = clampi(i, 0, PRESETS.size() - 1)
	var q: Dictionary = PRESETS[preset]
	R = q["R"]
	start = (q["x0"] as Array).duplicate()
	_set_exprs(MathExpr.parse(q["f1"], ["x", "y"]), MathExpr.parse(q["f2"], ["x", "y"]), MathExpr.parse(q["g1"], ["x", "y"]), MathExpr.parse(q["g2"], ["x", "y"]))
	if not _ui.is_empty():
		for k in ["f1", "f2", "g1", "g2"]:
			(_ui[k] as LineEdit).text = q[k]
		(_ui["R"] as HSlider).set_value_no_signal(R)
		_sync_start()
	if lab:
		lab._update_info(false)

func _set_exprs(a: MathExpr, b: MathExpr, c: MathExpr, d: MathExpr) -> void:
	f1 = a
	f2 = b
	g1 = c
	g2 = d
	for e in [f1, f2, g1, g2]:
		e.compile_fast()
	rebuild()

func rebuild() -> void:
	_find_roots()
	_build_basin_shader()
	_draw_curves()
	_compute_paths()

## Soluciones: Newton desde una rejilla de puntos iniciales, sin duplicados.
func _find_roots() -> void:
	roots.clear()
	var g := 14
	for j in range(g):
		for i in range(g):
			var x := lerpf(-R, R, (i + 0.5) / g)
			var y := lerpf(-R, R, (j + 0.5) / g)
			for k in range(60):
				var d := solve2(J(x, y), F(x, y))
				if d.is_empty():
					break
				x -= float(d[0])
				y -= float(d[1])
				if not (is_finite(x) and is_finite(y)) or absf(x) > 10.0 * R or absf(y) > 10.0 * R:
					break
				if absf(float(d[0])) + absf(float(d[1])) < 1e-14 * maxf(1.0, absf(x) + absf(y)):
					break
			if is_finite(x) and is_finite(y) and absf(x) <= R * 1.05 and absf(y) <= R * 1.05 and norm_F(x, y) < 1e-8:
				var dup := false
				for r in roots:
					if absf(float(r[0]) - x) + absf(float(r[1]) - y) < 1e-6:
						dup = true
				if not dup and roots.size() < 12:
					roots.append([x, y])
	roots.sort_custom(func(p, q): return atan2(float(p[1]), float(p[0])) < atan2(float(q[1]), float(q[0])))

func _build_basin_shader() -> void:
	var sh := Shader.new()
	sh.code = BASIN_SHADER.replace("/*PRELUDE*/", MathExpr.GLSL_PRELUDE).replace("/*F1*/", f1.to_glsl({"x": "x", "y": "y"})).replace("/*F2*/", f2.to_glsl({"x": "x", "y": "y"}))
	basin_mat = ShaderMaterial.new()
	basin_mat.shader = sh
	basin_mat.set_shader_parameter("R", R)
	basin_mat.set_shader_parameter("half_size", SIZE * 0.5)
	var rp := PackedVector2Array()
	for r in roots:
		rp.append(Vector2(float(r[0]), float(r[1])))
	while rp.size() < 12:
		rp.append(Vector2(1e6, 1e6))
	basin_mat.set_shader_parameter("roots", rp)
	basin_mat.set_shader_parameter("nroots", roots.size())
	basin_mat.set_shader_parameter("strength", 1.0 if show_basins else 0.0)
	basin.material_override = basin_mat
	clip_materials.clear()
	register_clip(basin_mat)

## Curvas f = 0 por marching squares, dibujadas como cintas sobre el plano.
func _zero_curve(e: MathExpr, col: Color, h: float) -> MeshInstance3D:
	var N := 150
	var vals := []
	for j in range(N + 1):
		var row := PackedFloat64Array()
		row.resize(N + 1)
		for i in range(N + 1):
			row[i] = e.eval_fast([lerpf(-R, R, float(i) / N), lerpf(-R, R, float(j) / N)])
		vals.append(row)
	var verts := PackedVector3Array()
	var width := 0.022
	for j in range(N):
		for i in range(N):
			var v00: float = vals[j][i]
			var v10: float = vals[j][i + 1]
			var v01: float = vals[j + 1][i]
			var v11: float = vals[j + 1][i + 1]
			if not (is_finite(v00) and is_finite(v10) and is_finite(v01) and is_finite(v11)):
				continue
			var x0 := lerpf(-R, R, float(i) / N)
			var x1 := lerpf(-R, R, float(i + 1) / N)
			var y0 := lerpf(-R, R, float(j) / N)
			var y1 := lerpf(-R, R, float(j + 1) / N)
			var pts := []
			if (v00 < 0.0) != (v10 < 0.0):
				pts.append(Vector2(lerpf(x0, x1, v00 / (v00 - v10)), y0))
			if (v10 < 0.0) != (v11 < 0.0):
				pts.append(Vector2(x1, lerpf(y0, y1, v10 / (v10 - v11))))
			if (v01 < 0.0) != (v11 < 0.0):
				pts.append(Vector2(lerpf(x0, x1, v01 / (v01 - v11)), y1))
			if (v00 < 0.0) != (v01 < 0.0):
				pts.append(Vector2(x0, lerpf(y0, y1, v00 / (v00 - v01))))
			# Descarta polos: saltos de signo con valores enormes.
			var big := maxf(maxf(absf(v00), absf(v10)), maxf(absf(v01), absf(v11)))
			if big > 1e6:
				continue
			for k in range(0, pts.size() - 1, 2):
				var a := _w(pts[k].x, pts[k].y, h)
				var b := _w(pts[k + 1].x, pts[k + 1].y, h)
				var d := b - a
				if d.length() < 1e-9:
					continue
				var nrm := Vector3(-d.z, 0, d.x).normalized() * width * 0.5
				verts.append_array(PackedVector3Array([a - nrm, a + nrm, b + nrm, a - nrm, b + nrm, b - nrm]))
	var mi := MeshInstance3D.new()
	if verts.size() > 0:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mi.mesh = am
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	return mi

func _draw_curves() -> void:
	for c in curves_node.get_children():
		c.queue_free()
	curves_node.add_child(_zero_curve(f1, Color(1.0, 0.35, 0.3), 0.02))
	curves_node.add_child(_zero_curve(f2, Color(0.35, 0.65, 1.0), 0.021))
	var ax := glow_mat(Color(0.8, 0.85, 0.95), 1.0)
	curves_node.add_child(arrow(_w(-R, 0, 0.015), _w(R * 1.08, 0, 0.015), 0.008, ax))
	curves_node.add_child(arrow(_w(0, -R, 0.015), _w(0, R * 1.08, 0.015), 0.008, ax))
	curves_node.add_child(label3d("x", _w(R * 1.14, 0, 0.1), Color(1, 0.5, 0.5), 0.003))
	curves_node.add_child(label3d("y", _w(0, R * 1.14, 0.1), Color(0.5, 1, 0.6), 0.003))
	curves_node.add_child(label3d("f₁ = " + f1.source + " = 0", _w(-R * 0.25, R * 1.12, 0.1), Color(1.0, 0.45, 0.4), 0.0028))
	curves_node.add_child(label3d("f₂ = " + f2.source + " = 0", _w(-R * 0.25, R * 1.24, 0.1), Color(0.45, 0.7, 1.0), 0.0028))
	for k in range(roots.size()):
		var r: Array = roots[k]
		var s := sphere(0.06, glow_mat(Color(1, 1, 1), 3.5))
		s.position = _w(r[0], r[1], 0.06)
		curves_node.add_child(s)
		curves_node.add_child(label3d("x*%d" % (k + 1), _w(r[0], r[1], 0.25), Color(1, 1, 1), 0.0026))

# --- Métodos ---------------------------------------------------------------------------

func _stop(x: float, y: float) -> bool:
	return norm_F(x, y) < TOL

func run_method(m: int) -> Array:
	var x: float = start[0]
	var y: float = start[1]
	var out := [[x, y]]
	var B: Array = J(x, y)
	var lam := 1e-3
	for k in range(n_iter):
		if _stop(x, y):
			break
		var f := F(x, y)
		var nx := x
		var ny := y
		match m:
			0, 1:
				var d := solve2(J(x, y), f)
				if d.is_empty():
					break
				var t := 1.0
				if m == 1:
					var n0 := norm_F(x, y)
					while t > 1e-4 and norm_F(x - t * float(d[0]), y - t * float(d[1])) > (1.0 - 1e-4 * t) * n0:
						t *= 0.5
				nx = x - t * float(d[0])
				ny = y - t * float(d[1])
			2:
				var d2 := solve2(B, f)
				if d2.is_empty():
					break
				nx = x - float(d2[0])
				ny = y - float(d2[1])
				var dx := nx - x
				var dy := ny - y
				var fn := F(nx, ny)
				var yv := [float(fn[0]) - float(f[0]), float(fn[1]) - float(f[1])]
				var bd := [B[0][0] * dx + B[0][1] * dy, B[1][0] * dx + B[1][1] * dy]
				var dd := dx * dx + dy * dy
				if dd > 0.0:
					for r in range(2):
						var c := (float(yv[r]) - float(bd[r])) / dd
						B[r][0] += c * dx
						B[r][1] += c * dy
			3:
				nx = g1.eval_fast([x, y])
				ny = g2.eval_fast([x, y])
			4:
				var jj := J(x, y)
				if absf(jj[0][0]) > 1e-300:
					nx = x - float(f[0]) / float(jj[0][0])
				var j2 := J(nx, y)
				var f2n: float = F(nx, y)[1]
				if absf(j2[1][1]) > 1e-300:
					ny = y - f2n / float(j2[1][1])
			5:
				var jg := J(x, y)
				var gx: float = jg[0][0] * f[0] + jg[1][0] * f[1]
				var gy: float = jg[0][1] * f[0] + jg[1][1] * f[1]
				var phi0 := 0.5 * norm_F(x, y) * norm_F(x, y)
				var gg := gx * gx + gy * gy
				if gg < 1e-300:
					break
				var t2 := 1.0
				while t2 > 1e-12 and 0.5 * pow(norm_F(x - t2 * gx, y - t2 * gy), 2) > phi0 - 1e-4 * t2 * gg:
					t2 *= 0.5
				nx = x - t2 * gx
				ny = y - t2 * gy
			6:
				var jl := J(x, y)
				var jtj := [[jl[0][0] * jl[0][0] + jl[1][0] * jl[1][0], jl[0][0] * jl[0][1] + jl[1][0] * jl[1][1]],
					[jl[0][1] * jl[0][0] + jl[1][1] * jl[1][0], jl[0][1] * jl[0][1] + jl[1][1] * jl[1][1]]]
				var jtf := [jl[0][0] * f[0] + jl[1][0] * f[1], jl[0][1] * f[0] + jl[1][1] * f[1]]
				var n0 := norm_F(x, y)
				var accepted := false
				for tries in range(12):
					var Mm := [[jtj[0][0] * (1.0 + lam), jtj[0][1]], [jtj[1][0], jtj[1][1] * (1.0 + lam)]]
					var d3 := solve2(Mm, jtf)
					if d3.is_empty():
						lam *= 4.0
						continue
					if norm_F(x - float(d3[0]), y - float(d3[1])) < n0:
						nx = x - float(d3[0])
						ny = y - float(d3[1])
						lam = maxf(lam / 3.0, 1e-12)
						accepted = true
						break
					lam *= 4.0
				if not accepted:
					break
		if not (is_finite(nx) and is_finite(ny)) or absf(nx) > 1e6 or absf(ny) > 1e6:
			break
		x = nx
		y = ny
		out.append([x, y])
	return out

func _compute_paths() -> void:
	paths.clear()
	for m in range(METHODS.size()):
		paths.append(run_method(m))
	_draw_paths()

func _draw_paths() -> void:
	for c in paths_node.get_children():
		c.queue_free()
	var st := sphere(0.07, glow_mat(Color(1.0, 0.85, 0.3), 4.0))
	st.position = _w(start[0], start[1], 0.07)
	paths_node.add_child(st)
	for m in range(METHODS.size()):
		if not shown[m]:
			continue
		var mat := glow_mat(COLORS[m], 2.4)
		var pts := PackedVector3Array()
		var h := 0.05 + 0.012 * m
		for p in paths[m]:
			if absf(float(p[0])) > R * 1.6 or absf(float(p[1])) > R * 1.6:
				break
			pts.append(_w(p[0], p[1], h))
		for q in pts:
			var s := sphere(0.028, mat)
			s.position = q
			paths_node.add_child(s)
		if pts.size() >= 2:
			paths_node.add_child(tube(pts, 0.011, mat, 6))
	if plot:
		plot.queue_redraw()

## Solución más cercana al último iterado (si ha convergido).
func target_of(path: Array) -> Array:
	var last: Array = path[path.size() - 1]
	if norm_F(last[0], last[1]) > 1e-8:
		return []
	var best := []
	var bd := INF
	for r in roots:
		var d := absf(float(r[0]) - float(last[0])) + absf(float(r[1]) - float(last[1]))
		if d < bd:
			bd = d
			best = r
	return best if bd < 1e-5 else last

func order_of(path: Array) -> float:
	var t := target_of(path)
	if t.is_empty():
		return NAN
	var e := []
	for p in path:
		e.append(Vector2(float(p[0]) - float(t[0]), float(p[1]) - float(t[1])).length())
	var best := NAN
	for i in range(2, e.size()):
		var e0: float = e[i - 2]
		var e1: float = e[i - 1]
		var e2: float = e[i]
		if e0 > 1e-12 and e1 > 1e-12 and e2 > 1e-12 and e2 < e1 and e0 != e1:
			best = log(e2 / e1) / log(e1 / e0)
	return best

func info() -> String:
	var t := "[font_size=12]"
	var rs := []
	for k in range(roots.size()):
		rs.append("x*%d = (%.5f, %.5f)" % [k + 1, float(roots[k][0]), float(roots[k][1])])
	t += "Soluciones en [−R, R]²: %s\n" % (", ".join(rs) if not rs.is_empty() else "ninguna")
	t += "[color=#8fa3b8]Método                │ iter. │ ‖F‖ final │ p obs. (teórico) │ llega a[/color]\n"
	for m in range(METHODS.size()):
		if not shown[m]:
			continue
		var path: Array = paths[m]
		var last: Array = path[path.size() - 1]
		var nf := norm_F(last[0], last[1])
		var tg := target_of(path)
		var dest := "—"
		for k in range(roots.size()):
			if not tg.is_empty() and absf(float(roots[k][0]) - float(tg[0])) + absf(float(roots[k][1]) - float(tg[1])) < 1e-9:
				dest = "x*%d" % (k + 1)
		var p := order_of(path)
		t += "[color=#%s]■[/color] %s │ %d │ %s │ %s (%s) │ %s\n" % [COLORS[m].to_html(false), SHORT[m], path.size() - 1, LabUI.sci(nf, 1), "%.2f" % p if not is_nan(p) else "—", ORDER_TH[m], dest if nf < 1e-8 else "[color=#ff7766]no converge[/color]"]
	var j0 := J(start[0], start[1])
	t += "[/font_size]J(x₀) = [[%.3f, %.3f], [%.3f, %.3f]] · det = %.4f" % [j0[0][0], j0[0][1], j0[1][0], j0[1][1], j0[0][0] * j0[1][1] - j0[0][1] * j0[1][0]]
	return t

func build_ui(p: VBoxContainer) -> void:
	LabUI.option(p, "Ejemplo:", PRESETS.map(func(q): return q["nombre"]), preset, func(i): load_preset(i))
	_ui["f1"] = LabUI.expr_field(p, "f₁(x, y) =", f1.source, ["x", "y"], false, func(m): _set_exprs(m, f2, g1, g2))
	_ui["f2"] = LabUI.expr_field(p, "f₂(x, y) =", f2.source, ["x", "y"], false, func(m): _set_exprs(f1, m, g1, g2))
	_ui["g1"] = LabUI.expr_field(p, "g₁(x, y) = (punto fijo: x = g₁)", g1.source, ["x", "y"], false, func(m): _set_exprs(f1, f2, m, g2))
	_ui["g2"] = LabUI.expr_field(p, "g₂(x, y) = (punto fijo: y = g₂)", g2.source, ["x", "y"], false, func(m): _set_exprs(f1, f2, g1, m))
	_ui["R"] = LabUI.slider(p, "Región |x|, |y| ≤ R", 0.5, 10.0, 0.1, R, func(v):
		R = v
		rebuild()
		lab._update_info(false))
	var r := LabUI.row(p)
	_ui["x0"] = LabUI.spin(r, "x₀", -50, 50, 0.05, start[0], func(v):
		start[0] = v
		_compute_paths()
		lab._update_info(false))
	_ui["y0"] = LabUI.spin(r, "y₀", -50, 50, 0.05, start[1], func(v):
		start[1] = v
		_compute_paths()
		lab._update_info(false))
	LabUI.slider(p, "Iteraciones máx.", 1, 200, 1, n_iter, func(v):
		n_iter = int(v)
		_compute_paths()
		lab._update_info(false), "%.0f")
	LabUI.section(p, "Métodos")
	for m in range(METHODS.size()):
		var mm := m
		var chk := LabUI.check(p, METHODS[m], shown[m], func(v):
			shown[mm] = v
			_draw_paths()
			lab._update_info(false))
		chk.add_theme_color_override("font_color", COLORS[m].lerp(Color.WHITE, 0.25))
		chk.add_theme_color_override("font_pressed_color", COLORS[m].lerp(Color.WHITE, 0.25))
	LabUI.check(p, "Cuencas de atracción de Newton (GPU)", show_basins, func(v):
		show_basins = v
		basin_mat.set_shader_parameter("strength", 1.0 if v else 0.0))
	LabUI.section(p, "log₁₀ ‖F(xₖ)‖ por iteración")
	plot = NormPlot.new()
	plot.module = self
	plot.custom_minimum_size = Vector2(260, 120)
	p.add_child(plot)
	LabUI.note(p, "Cada color del plano es la solución a la que llega Newton desde ese punto (más oscuro = más iteraciones; negro = no converge). Las fronteras entre cuencas pueden ser fractales. Broyden solo calcula el jacobiano al principio y luego lo corrige con actualizaciones de rango 1.")

func pick(origin: Vector3, dir: Vector3):
	var hit = ray_plane_y(origin, dir, 0.02)
	if hit == null or absf(hit.x) > SIZE * 0.5 or absf(hit.z) > SIZE * 0.5:
		return null
	return hit

func hover_text(hit: Vector3) -> String:
	var x := hit.x / _s()
	var y := -hit.z / _s()
	var f := F(x, y)
	var jj := J(x, y)
	var det: float = jj[0][0] * jj[1][1] - jj[0][1] * jj[1][0]
	# ¿A qué solución llega Newton desde aquí?
	var px := x
	var py := y
	var dest := "no converge"
	for k in range(50):
		var d := solve2(J(px, py), F(px, py))
		if d.is_empty():
			break
		px -= float(d[0])
		py -= float(d[1])
		if not (is_finite(px) and is_finite(py)):
			break
		for i in range(roots.size()):
			if absf(float(roots[i][0]) - px) + absf(float(roots[i][1]) - py) < 1e-6:
				dest = "x*%d en %d iter." % [i + 1, k + 1]
				break
		if dest != "no converge":
			break
	return "(x, y) = (%.3f, %.3f)\nf₁ = %.4f   f₂ = %.4f\ndet J = %.3f\nNewton → %s" % [x, y, f[0], f[1], det, dest]

## (x, y) directamente sobre el plano de las cuencas.
func api_points(x: float, y: float) -> Array:
	return [to_global(_w(x, y, 0.0))]

func _sync_start() -> void:
	if _ui.has("x0"):
		(_ui["x0"] as SpinBox).set_value_no_signal(start[0])
		(_ui["y0"] as SpinBox).set_value_no_signal(start[1])

func perturb(hit: Vector3, first: bool) -> void:
	start = [hit.x / _s(), -hit.z / _s()]
	_sync_start()
	_compute_paths()
	if lab:
		lab._update_info(false)

func critical_points() -> Array:
	var out := []
	for k in range(roots.size()):
		out.append({"pos": to_global(_w(roots[k][0], roots[k][1], 0.05)), "nombre": "Solución x*%d = (%.5f, %.5f)" % [k + 1, float(roots[k][0]), float(roots[k][1])], "dist": 2.0})
	out.append({"pos": to_global(_w(start[0], start[1], 0.05)), "nombre": "Punto de partida", "dist": 2.5})
	return out

func demo(_extra: Array) -> void:
	if "fractal" in _extra:
		load_preset(2)

class NormPlot extends Control:
	var module
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.03, 0.05, 0.08, 0.9))
		for k in range(0, 17, 4):
			var y := r.size.y * float(k) / 16.0
			draw_line(Vector2(0, y), Vector2(r.size.x, y), Color(0.2, 0.3, 0.4, 0.5))
		if module == null:
			return
		var nmax := 10
		for m in range(module.METHODS.size()):
			if module.shown[m]:
				nmax = maxi(nmax, (module.paths[m] as Array).size() - 1)
		nmax = mini(nmax, 60)
		for m in range(module.METHODS.size()):
			if not module.shown[m]:
				continue
			var path: Array = module.paths[m]
			var pts := PackedVector2Array()
			for i in range(mini(path.size(), 61)):
				var nf: float = module.norm_F(path[i][0], path[i][1])
				var le: float = log(maxf(nf, 1e-16)) / log(10.0) if is_finite(nf) else 3.0
				pts.append(Vector2(r.size.x * float(i) / float(nmax), r.size.y * clampf((3.0 - le) / 19.0, 0.0, 1.0)))
			if pts.size() >= 2:
				draw_polyline(pts, module.COLORS[m], 1.8, true)
		draw_string(ThemeDB.fallback_font, Vector2(4, 12), "10³", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.7, 0.8))
		draw_string(ThemeDB.fallback_font, Vector2(4, r.size.y - 4), "10⁻¹⁶", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.7, 0.8))
