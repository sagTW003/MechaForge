extends LabModule
## Ecuaciones no lineales f(x) = 0: quince métodos paso a paso sobre la gráfica 3D.
##   · De intervalo: bisección, falsa posición, Illinois, Ridders y Brent.
##   · Abiertos con derivadas: Newton, Newton para raíces múltiples, Halley y
##     Chebyshev.
##   · Sin derivadas: secante, Steffensen, Müller e interpolación cuadrática inversa.
##   · Punto fijo x = g(x), también acelerado con Aitken Δ².
## Dibuja el intervalo, la tangente, la secante, la parábola o la telaraña de cada
## paso. Muestra la tabla de iteraciones con el orden de convergencia observado y
## puede comparar todos los métodos desde los mismos datos iniciales.

const METHODS := [
	"Bisección", "Newton-Raphson", "Secante", "Punto fijo",
	"Falsa posición (regula falsi)", "Illinois (falsa posición modificada)", "Ridders", "Brent (Brent–Dekker)",
	"Newton para raíces múltiples", "Halley", "Chebyshev (orden 3)", "Steffensen",
	"Müller", "Interpolación cuadrática inversa", "Punto fijo + Aitken Δ²",
]
const SHORT := ["Bisección", "Newton", "Secante", "Punto fijo", "Regula falsi", "Illinois", "Ridders", "Brent",
	"Newton múltiple", "Halley", "Chebyshev", "Steffensen", "Müller", "Cuadrática inv.", "Aitken Δ²"]
const BRACKET := [0, 4, 5, 6, 7]
const USES_G := [3, 14]
const FORMULAS := [
	"f(a)·f(b) < 0 → c = (a + b)/2",
	"xₙ₊₁ = xₙ − f(xₙ)/f′(xₙ)",
	"xₙ₊₁ = xₙ − f(xₙ)(xₙ − xₙ₋₁)/(f(xₙ) − f(xₙ₋₁))",
	"xₙ₊₁ = g(xₙ)",
	"c = b − f(b)(b − a)/(f(b) − f(a)), conservando el cambio de signo",
	"regula falsi, pero si un extremo se repite: f(extremo) ← f(extremo)/2",
	"c = (a+b)/2,  x = c + (c − a)·sgn(f(a) − f(b))·f(c)/√(f(c)² − f(a)f(b))",
	"cuadrática inversa o secante, con bisección de seguridad",
	"xₙ₊₁ = xₙ − f·f′/(f′² − f·f″)",
	"xₙ₊₁ = xₙ − 2f·f′/(2f′² − f·f″)",
	"xₙ₊₁ = xₙ − f/f′ − f″·f²/(2f′³)",
	"xₙ₊₁ = xₙ − f(xₙ)²/(f(xₙ + f(xₙ)) − f(xₙ))",
	"raíz de la parábola que pasa por los tres últimos puntos",
	"x = Σ xᵢ·Πⱼ≠ᵢ fⱼ/(fᵢ − fⱼ)  (parábola x = P(y) evaluada en y = 0)",
	"x̂ = x − (g(x) − x)²/(g(g(x)) − 2g(x) + x)",
]
const ORDER_TH := ["1 (÷2)", "2", "1.618", "1", "1", "≈1.442", "2", "superlineal", "2", "3", "3", "2", "≈1.839", "≈1.839", "2"]
const EVALS := ["f", "f, f′", "f", "g", "f", "f", "2 f", "f", "f, f′, f″", "f, f′, f″", "f, f′, f″", "2 f", "f", "f", "2 g"]
const EVALS_N := [1, 2, 1, 1, 1, 1, 2, 1, 3, 3, 3, 2, 1, 1, 2]
const DESCS := [
	"Parte el intervalo por la mitad conservando el cambio de signo. Siempre converge si f(a)·f(b) < 0, pero despacio: gana un bit por paso.",
	"Sigue la tangente hasta el eje. Convergencia cuadrática (los dígitos correctos se duplican) cerca de una raíz simple; puede diverger u oscilar si x₀ está lejos o f′ ≈ 0.",
	"Newton sin derivada: la recta que pasa por los dos últimos puntos. Orden áureo φ ≈ 1.618 con una sola evaluación por paso.",
	"Itera x = g(x). Converge si |g′(x*)| < 1, con razón |g′(x*)|; si g′(x*) = 0 (p. ej. la g babilónica de √2) es cuadrático.",
	"Como la secante pero conservando el cambio de signo: siempre converge, aunque suele quedarse con un extremo fijo y se vuelve lineal.",
	"Falsa posición que divide a la mitad el valor del extremo que se repite: evita el estancamiento y alcanza orden ≈ 1.442.",
	"Ajusta una exponencial en el punto medio: dos evaluaciones por paso, orden 2 y la seguridad de un intervalo.",
	"El método «de biblioteca» (fzero, brentq): cuadrática inversa o secante cuando es seguro y bisección cuando no. Rápido y a prueba de fallos.",
	"Newton aplicado a u = f/f′, que tiene raíces simples: recupera la convergencia cuadrática en raíces múltiples, donde Newton es lineal.",
	"Usa también f″ (hipérbola tangente): orden 3, los dígitos correctos se triplican en cada paso.",
	"Parábola de Taylor de segundo orden: orden 3, como Halley, con una corrección de la curvatura.",
	"Sustituye f′ por (f(x + f(x)) − f(x))/f(x): cuadrático sin derivadas, con dos evaluaciones de f por paso.",
	"Parábola por los tres últimos puntos: orden ≈ 1.84. Puede encontrar raíces complejas (aquí se usa la parte real).",
	"Parábola «tumbada» x = P(y) por los tres últimos puntos y su valor en y = 0: orden ≈ 1.84. Es el corazón del método de Brent.",
	"Acelera una sucesión lineal de punto fijo extrapolando la razón geométrica: con dos evaluaciones de g se vuelve cuadrática (Steffensen para g).",
]
const COLORS := [
	Color(1.0, 0.75, 0.2), Color(0.3, 0.8, 1.0), Color(0.45, 1.0, 0.5), Color(1.0, 0.45, 0.85),
	Color(1.0, 0.5, 0.25), Color(0.95, 0.9, 0.35), Color(0.6, 0.55, 1.0), Color(1.0, 1.0, 1.0),
	Color(0.2, 1.0, 0.85), Color(1.0, 0.3, 0.35), Color(0.85, 0.5, 1.0), Color(0.55, 0.85, 0.35),
	Color(1.0, 0.65, 0.6), Color(0.4, 0.6, 1.0), Color(0.9, 0.7, 1.0),
]
const PRESETS := [
	{"nombre": "x³ − 2x − 5 (ejemplo de Wallis)", "f": "x^3 - 2x - 5", "g": "(2x + 5)^(1/3)", "a": 1.0, "b": 3.0, "x0": 3.0, "x1": 2.5, "dom": [-3.0, 3.0]},
	{"nombre": "cos x − x", "f": "cos(x) - x", "g": "cos(x)", "a": 0.0, "b": 1.5, "x0": 1.0, "x1": 0.5, "dom": [-1.0, 2.0]},
	{"nombre": "eˣ − 3x (dos raíces)", "f": "exp(x) - 3x", "g": "log(3x)", "a": 1.0, "b": 2.0, "x0": 2.0, "x1": 1.8, "dom": [-1.0, 2.5]},
	{"nombre": "(x − 1)³ (raíz triple)", "f": "(x - 1)^3", "g": "x - (x - 1)^3", "a": 0.0, "b": 2.5, "x0": 2.5, "x1": 2.2, "dom": [-1.0, 3.0]},
	{"nombre": "x² − 2 (√2, g babilónica)", "f": "x^2 - 2", "g": "(x + 2/x)/2", "a": 0.0, "b": 2.0, "x0": 2.0, "x1": 1.5, "dom": [-2.5, 2.5]},
	{"nombre": "Kepler: x − 0.8·sin x − 1", "f": "x - 0.8sin(x) - 1", "g": "1 + 0.8sin(x)", "a": 0.0, "b": 3.0, "x0": 1.0, "x1": 2.0, "dom": [-1.0, 4.0]},
	{"nombre": "x·eˣ − 1 (constante Ω)", "f": "x exp(x) - 1", "g": "exp(-x)", "a": 0.0, "b": 1.0, "x0": 1.0, "x1": 0.8, "dom": [-1.0, 1.5]},
	{"nombre": "arctan x (Newton diverge si |x₀| > 1.39)", "f": "atan(x)", "g": "x - atan(x)", "a": -2.0, "b": 3.0, "x0": 1.5, "x1": 1.0, "dom": [-5.0, 5.0]},
	{"nombre": "∛x (Newton diverge siempre)", "f": "cbrt(x)", "g": "x - cbrt(x)", "a": -1.0, "b": 2.0, "x0": 1.0, "x1": 0.5, "dom": [-3.0, 3.0]},
]
const W := 3.0          # semiancho del tablero (mundo)
const HGT := 2.0        # semialto del tablero
const MAX_IT := 100
const LIFT := 0.8

var f_expr: MathExpr
var g_expr: MathExpr
var method: int = 1
var preset: int = 0
var xa: float = -3.0
var xb: float = 3.0
var a0: float = 1.0
var b0: float = 3.0
var x0: float = 3.0
var x1: float = 2.5
var tol: float = 1e-10
var hist: Array = []           # [{x, fx, a, b, …}] según el método
var root_ref: float = NAN      # raíz a la que converge el método elegido
var roots: Array = []          # todas las raíces reales del dominio
var compare: bool = false
var cmp_rows: Array = []       # resultados de «Comparar todos»
var ky: float = 1.0
var curve_node: Node3D
var iter_node: Node3D
var plot: Control
var _auto: bool = false
var _auto_t: float = 0.0
var _table: String = ""
var _desc: Label
var _ui := {}

func title() -> String: return "Ecuaciones no lineales"
func formula() -> String: return FORMULAS[method]
func uses_time() -> bool: return true
func planar() -> bool: return true
func perturb_hint() -> String: return "clic sobre el eje x: fija el punto inicial (o el extremo más cercano del intervalo)"
func view() -> Dictionary: return {"target": Vector3(0, LIFT, 0), "dist": 8.5, "yaw": -8.0, "pitch": -8.0}

func setup() -> void:
	position = Vector3(0, LIFT, 0)
	f_expr = MathExpr.parse(PRESETS[0]["f"], ["x"])
	g_expr = MathExpr.parse(PRESETS[0]["g"], ["x"])
	# Tablero de vidrio oscuro y ejes.
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(W * 2.0 + 0.4, HGT * 2.0 + 0.4, 0.04)
	board.mesh = bm
	board.material_override = glass_mat(Color(0.05, 0.12, 0.2), 0.55)
	board.position = Vector3(0, 0, -0.12)
	add_child(board)
	curve_node = Node3D.new()
	add_child(curve_node)
	iter_node = Node3D.new()
	add_child(iter_node)
	_rebuild_curve()
	reset()

func _f(x: float) -> float:
	return f_expr.eval_real({"x": x})

func _g(x: float) -> float:
	return g_expr.eval_real({"x": x})

func _df(x: float) -> float:
	var h := 1e-5 * maxf(1.0, absf(x))
	return (_f(x + h) - _f(x - h)) / (2.0 * h)

func _d2f(x: float) -> float:
	var h := 1e-4 * maxf(1.0, absf(x))
	return (_f(x + h) - 2.0 * _f(x) + _f(x - h)) / (h * h)

func _X(x: float) -> float:
	return (x - (xa + xb) * 0.5) * (2.0 * W / (xb - xa))

func _Y(y: float) -> float:
	return clampf(y * ky, -HGT * 1.2, HGT * 1.2)

func _p(x: float, y: float) -> Vector3:
	return Vector3(_X(x), _Y(y), 0.0)

func _in_view(x: float) -> bool:
	return is_finite(x) and x >= xa - (xb - xa) * 0.1 and x <= xb + (xb - xa) * 0.1

func _rebuild_curve() -> void:
	for c in curve_node.get_children():
		c.queue_free()
	# Escala vertical: rango robusto de f en el dominio.
	var vals := []
	for i in range(201):
		var v := _f(lerpf(xa, xb, i / 200.0))
		if is_finite(v):
			vals.append(absf(v))
	vals.sort()
	var m: float = vals[int(vals.size() * 0.9)] if not vals.is_empty() else 1.0
	ky = HGT / maxf(1e-6, m)
	# Ejes.
	curve_node.add_child(arrow(Vector3(-W - 0.1, 0, 0), Vector3(W + 0.2, 0, 0), 0.01, glow_mat(Color(0.8, 0.85, 0.95), 1.0)))
	var x0w := _X(0.0)
	if absf(x0w) <= W:
		curve_node.add_child(arrow(Vector3(x0w, -HGT - 0.1, 0), Vector3(x0w, HGT + 0.2, 0), 0.01, glow_mat(Color(0.8, 0.85, 0.95), 1.0)))
	for k in range(int(ceil(xa)), int(floor(xb)) + 1):
		curve_node.add_child(label3d(str(k), Vector3(_X(k), -0.18, 0.02), Color(0.7, 0.75, 0.85), 0.0028))
	curve_node.add_child(label3d("f(x) = " + f_expr.source, Vector3(-W + 0.9, HGT + 0.05, 0.02), Color(0.35, 0.9, 1.0), 0.0035))
	_add_curve(func(x): return _f(x), Color(0.3, 0.85, 1.0), 0.022)
	if method in USES_G:
		_add_curve(func(x): return _g(x), Color(1.0, 0.45, 0.85), 0.016)
		var a := maxf(xa, -HGT / ky)
		var b := minf(xb, HGT / ky)
		if b > a:
			curve_node.add_child(rod(_p(a, a), _p(b, b), 0.008, glow_mat(Color(0.7, 0.7, 0.75), 0.8)))
	_find_roots(m)
	for r in roots:
		var s := sphere(0.045, glow_mat(Color(0.3, 1.0, 0.5), 2.2))
		s.position = _p(r, 0.0) + Vector3(0, 0, 0.03)
		curve_node.add_child(s)

func _add_curve(fn: Callable, col: Color, r: float) -> void:
	var pts := PackedVector3Array()
	var n := 400
	for i in range(n + 1):
		var x := lerpf(xa, xb, float(i) / n)
		var y: float = fn.call(x)
		if not is_finite(y) or absf(y * ky) > HGT * 1.2:
			if pts.size() >= 2:
				curve_node.add_child(tube(pts, r, glow_mat(col, 1.6)))
			pts = PackedVector3Array()
			continue
		pts.append(_p(x, y))
	if pts.size() >= 2:
		curve_node.add_child(tube(pts, r, glow_mat(col, 1.6)))

## Todas las raíces reales del dominio: cambios de signo refinados por bisección
## hasta la precisión de la máquina y mínimos de |f| (raíces de multiplicidad par)
## refinados con Newton para raíces múltiples. «scale» descarta los polos.
func _find_roots(scale: float) -> void:
	roots.clear()
	var n := 600
	var xs := []
	var fs := []
	for i in range(n + 1):
		var x := lerpf(xa, xb, float(i) / n)
		xs.append(x)
		fs.append(_f(x))
	var cands := []
	for i in range(n):
		var fa: float = fs[i]
		var fb: float = fs[i + 1]
		if not (is_finite(fa) and is_finite(fb)):
			continue
		if fa == 0.0:
			cands.append(xs[i])
		elif fa * fb < 0.0:
			var a: float = xs[i]
			var b: float = xs[i + 1]
			for k in range(200):
				var c := (a + b) * 0.5
				if c == a or c == b:
					break
				var fc := _f(c)
				if fc == 0.0:
					a = c
					b = c
					break
				if fa * fc < 0.0:
					b = c
				else:
					a = c
					fa = fc
			var r := (a + b) * 0.5
			if absf(_f(r)) < 1e-6 * maxf(1.0, scale):
				cands.append(r)
		elif i > 0 and is_finite(fs[i - 1]) and absf(fa) < absf(fs[i - 1]) and absf(fa) <= absf(fb) and absf(fa) < 1e-2 * maxf(1.0, scale):
			var x: float = xs[i]
			for k in range(40):
				var f := _f(x)
				var d := _df(x)
				var d2 := _d2f(x)
				var den := d * d - f * d2
				if f == 0.0 or den == 0.0 or not is_finite(den):
					break
				var dx := f * d / den
				x -= dx
				if absf(dx) < 1e-15 * maxf(1.0, absf(x)):
					break
			if is_finite(x) and absf(_f(x)) < 1e-12 * maxf(1.0, scale) and x >= xa and x <= xb:
				cands.append(x)
	for c in cands:
		var dup := false
		for r in roots:
			if absf(float(r) - float(c)) < 1e-7 * maxf(1.0, absf(float(c))):
				dup = true
		if not dup:
			roots.append(c)
	roots.sort()

# --- Iteraciones ---------------------------------------------------------------------

## Estado inicial del método m (lista de iterados).
func _init_hist(m: int) -> Array:
	var H := []
	if m in BRACKET:
		var a := a0
		var b := b0
		var fa := _f(a)
		var fb := _f(b)
		match m:
			0:
				H.append({"a": a, "b": b, "x": (a + b) * 0.5, "fx": _f((a + b) * 0.5)})
			7:
				if absf(fa) < absf(fb):
					var t := a
					a = b
					b = t
					var tf := fa
					fa = fb
					fb = tf
				H.append({"a": a, "b": b, "fa": fa, "fb": fb, "c": a, "fc": fa, "d": 0.0, "mflag": true, "x": b, "fx": fb, "tipo": "inicio"})
			_:
				var xb_ := b if absf(fb) < absf(fa) else a
				H.append({"a": a, "b": b, "fa": fa, "fb": fb, "x": xb_, "fx": _f(xb_), "side": 0})
	elif m == 2:
		H.append({"x": x0, "fx": _f(x0)})
		H.append({"x": x1, "fx": _f(x1)})
	elif m in [12, 13]:
		var x2 := (x0 + x1) * 0.5
		for x in [x0, x1, x2]:
			H.append({"x": x, "fx": _f(x)})
	else:
		H.append({"x": x0, "fx": _f(x0)})
	return H

## ¿Hay cambio de signo en el intervalo inicial?
func bracket_ok() -> bool:
	var fa := _f(a0)
	var fb := _f(b0)
	return is_finite(fa) and is_finite(fb) and fa * fb <= 0.0

func _converged(m: int, H: Array) -> bool:
	if H.size() < 2:
		return false
	var last: Dictionary = H[H.size() - 1]
	var prev: Dictionary = H[H.size() - 2]
	if float(last["fx"]) == 0.0:
		return true
	if m == 0:
		return absf(float(last["b"]) - float(last["a"])) < tol
	if m == 7:
		return absf(float(last["b"]) - float(last["a"])) < tol * maxf(1.0, absf(float(last["x"])))
	return absf(float(last["x"]) - float(prev["x"])) <= tol * maxf(1.0, absf(float(last["x"])))

## Un paso del método m sobre la lista H. false si no puede avanzar.
func _advance(m: int, H: Array) -> bool:
	var last: Dictionary = H[H.size() - 1]
	var x: float = last["x"]
	var e := {}
	match m:
		0:
			var a: float = last["a"]
			var b: float = last["b"]
			if _f(a) * _f(x) <= 0.0:
				b = x
			else:
				a = x
			var mid := (a + b) * 0.5
			e = {"a": a, "b": b, "x": mid, "fx": _f(mid)}
		1:
			var d := _df(x)
			if d == 0.0:
				return false
			var xn := x - _f(x) / d
			e = {"x": xn, "fx": _f(xn), "desde": x}
		2:
			var p: Dictionary = H[H.size() - 2]
			var xp: float = p["x"]
			var den := float(last["fx"]) - float(p["fx"])
			if den == 0.0:
				return false
			var xn2 := x - float(last["fx"]) * (x - xp) / den
			e = {"x": xn2, "fx": _f(xn2)}
		3:
			var xg := _g(x)
			e = {"x": xg, "fx": _f(xg)}
		4, 5:
			var a: float = last["a"]
			var b: float = last["b"]
			var fa: float = last["fa"]
			var fb: float = last["fb"]
			if fb == fa:
				return false
			var c := b - fb * (b - a) / (fb - fa)
			var fc := _f(c)
			var side: int = last["side"]
			var ea := a
			var eb := b
			var efa := fa
			var efb := fb
			if fc * fb > 0.0:
				eb = c
				efb = fc
				if m == 5 and side == -1:
					efa *= 0.5
				side = -1
			elif fa * fc > 0.0:
				ea = c
				efa = fc
				if m == 5 and side == 1:
					efb *= 0.5
				side = 1
			else:
				ea = c
				eb = c
				efa = fc
				efb = fc
			e = {"a": ea, "b": eb, "fa": efa, "fb": efb, "x": c, "fx": fc, "side": side, "cuerda": [a, fa, b, fb]}
		6:
			var a: float = last["a"]
			var b: float = last["b"]
			var fa: float = last["fa"]
			var fb: float = last["fb"]
			var c := (a + b) * 0.5
			var fc := _f(c)
			var s := sqrt(fc * fc - fa * fb)
			if s == 0.0 or not is_finite(s):
				return false
			var xr := c + (c - a) * signf(fa - fb) * fc / s
			var fr := _f(xr)
			var na := a
			var nb := b
			var nfa := fa
			var nfb := fb
			if signf(fc) != signf(fr):
				na = c
				nfa = fc
				nb = xr
				nfb = fr
			elif signf(fa) != signf(fr):
				nb = xr
				nfb = fr
			else:
				na = xr
				nfa = fr
			e = {"a": na, "b": nb, "fa": nfa, "fb": nfb, "x": xr, "fx": fr, "medio": c}
		7:
			e = _brent_step(last)
			if e.is_empty():
				return false
		8, 9, 10:
			var f := _f(x)
			var d := _df(x)
			var d2 := _d2f(x)
			var xn := NAN
			match m:
				8:
					var den := d * d - f * d2
					if den == 0.0:
						return false
					xn = x - f * d / den
				9:
					var den2 := 2.0 * d * d - f * d2
					if den2 == 0.0:
						return false
					xn = x - 2.0 * f * d / den2
				10:
					if d == 0.0:
						return false
					xn = x - f / d - d2 * f * f / (2.0 * d * d * d)
			e = {"x": xn, "fx": _f(xn), "desde": x, "f": f, "d": d, "d2": d2}
		11:
			var f := float(last["fx"])
			var den := _f(x + f) - f
			if den == 0.0:
				return false
			var xs := x - f * f / den
			e = {"x": xs, "fx": _f(xs), "desde": x, "aux": x + f}
		12:
			var p0: Dictionary = H[H.size() - 3]
			var p1: Dictionary = H[H.size() - 2]
			var xa_: float = p0["x"]
			var xb_: float = p1["x"]
			var fa_: float = p0["fx"]
			var fb_: float = p1["fx"]
			var fc_: float = last["fx"]
			var h1 := xb_ - xa_
			var h2 := x - xb_
			if h1 == 0.0 or h2 == 0.0 or h1 + h2 == 0.0:
				return false
			var d1 := (fb_ - fa_) / h1
			var d2m := (fc_ - fb_) / h2
			var aa := (d2m - d1) / (h2 + h1)
			var bb := aa * h2 + d2m
			var disc := bb * bb - 4.0 * fc_ * aa
			var compleja := disc < 0.0
			var den := bb + (1.0 if bb >= 0.0 else -1.0) * sqrt(maxf(disc, 0.0))
			if den == 0.0:
				return false
			var xm := x - 2.0 * fc_ / den
			e = {"x": xm, "fx": _f(xm), "compleja": compleja}
		13:
			var q0: Dictionary = H[H.size() - 3]
			var q1: Dictionary = H[H.size() - 2]
			var xs3 := [float(q0["x"]), float(q1["x"]), x]
			var fs3 := [float(q0["fx"]), float(q1["fx"]), float(last["fx"])]
			if fs3[0] == fs3[1] or fs3[0] == fs3[2] or fs3[1] == fs3[2]:
				return false
			var xi := 0.0
			for i in range(3):
				var term: float = xs3[i]
				for j in range(3):
					if j != i:
						term *= fs3[j] / (fs3[i] - fs3[j])
				xi += term
			e = {"x": xi, "fx": _f(xi)}
		14:
			var g1 := _g(x)
			var g2 := _g(g1)
			var den := g2 - 2.0 * g1 + x
			var xa2 := g2 if den == 0.0 else x - (g1 - x) * (g1 - x) / den
			e = {"x": xa2, "fx": _f(xa2), "g1": g1, "g2": g2, "desde": x}
	if not is_finite(float(e.get("x", NAN))) or absf(float(e["x"])) > 1e12:
		return false
	H.append(e)
	return true

## Un paso de Brent (Wikipedia / Brent 1973): cuadrática inversa o secante si
## caen en zona segura; si no, bisección.
func _brent_step(s: Dictionary) -> Dictionary:
	var a: float = s["a"]
	var b: float = s["b"]
	var c: float = s["c"]
	var d: float = s["d"]
	var fa: float = s["fa"]
	var fb: float = s["fb"]
	var fc: float = s["fc"]
	var mflag: bool = s["mflag"]
	if fa == fb:
		return {}
	var x := 0.0
	var tipo := ""
	if fa != fc and fb != fc:
		x = a * fb * fc / ((fa - fb) * (fa - fc)) + b * fa * fc / ((fb - fa) * (fb - fc)) + c * fa * fb / ((fc - fa) * (fc - fb))
		tipo = "cuadrática inversa"
	else:
		x = b - fb * (b - a) / (fb - fa)
		tipo = "secante"
	var lo := minf((3.0 * a + b) / 4.0, b)
	var hi := maxf((3.0 * a + b) / 4.0, b)
	var eps := 1e-15 * maxf(1.0, absf(b))
	if x < lo or x > hi or (mflag and absf(x - b) >= absf(b - c) * 0.5) or (not mflag and absf(x - b) >= absf(c - d) * 0.5) \
			or (mflag and absf(b - c) < eps) or (not mflag and absf(c - d) < eps):
		x = (a + b) * 0.5
		tipo = "bisección"
		mflag = true
	else:
		mflag = false
	var fx := _f(x)
	d = c
	c = b
	fc = fb
	if fa * fx < 0.0:
		b = x
		fb = fx
	else:
		a = x
		fa = fx
	if absf(fa) < absf(fb):
		var t := a
		a = b
		b = t
		var tf := fa
		fa = fb
		fb = tf
	return {"a": a, "b": b, "fa": fa, "fb": fb, "c": c, "fc": fc, "d": d, "mflag": mflag, "x": b, "fx": fb, "tipo": tipo, "prueba": x}

## Ejecuta el método m hasta converger (o MAX_IT) desde los datos iniciales.
func run_full(m: int) -> Array:
	var H := _init_hist(m)
	var it := 0
	while it < MAX_IT and not _converged(m, H):
		if not _advance(m, H):
			break
		it += 1
	return H

## Raíz a la que llega una ejecución: la raíz conocida más cercana a su último iterado.
func _target(H: Array, m: int) -> float:
	if H.is_empty():
		return NAN
	var xf: float = H[H.size() - 1]["x"]
	var best := NAN
	var bd := INF
	for r in roots:
		var dd := absf(float(r) - xf)
		if dd < bd:
			bd = dd
			best = r
	if not is_nan(best) and bd < 1e-4 * maxf(1.0, absf(xf)):
		return best
	return xf if _converged(m, H) else NAN

func reset() -> void:
	_auto = false
	hist = _init_hist(method)
	root_ref = _target(run_full(method), method)
	if compare:
		_compare_all()
	_draw_iters()

func converged() -> bool:
	return _converged(method, hist)

func do_step() -> bool:
	if hist.is_empty() or converged() or hist.size() > MAX_IT:
		return false
	var ok := _advance(method, hist)
	_draw_iters()
	return ok

func step(dt: float) -> void:
	if not _auto:
		return
	_auto_t += dt
	if _auto_t >= 0.45:
		_auto_t = 0.0
		if not do_step():
			_auto = false

func _errors_of(H: Array, target: float) -> Array:
	var out := []
	for h in H:
		out.append(absf(float(h["x"]) - target) if not is_nan(target) else absf(float(h["fx"])))
	return out

func _errors() -> Array:
	return _errors_of(hist, root_ref)

## Orden de convergencia observado: p ≈ ln(eₙ₊₁/eₙ)/ln(eₙ/eₙ₋₁), mediana de las
## tres últimas estimaciones válidas (se descartan cocientes casi iguales a 1, que
## dan valores absurdos, y errores ya en el ruido de redondeo).
static func order_of(e: Array) -> float:
	var ps := []
	for i in range(2, e.size()):
		var e0: float = e[i - 2]
		var e1: float = e[i - 1]
		var e2: float = e[i]
		if e0 > 1e-13 and e1 > 1e-13 and e2 > 1e-13 and e1 < 0.95 * e0 and e2 < e1:
			var p := log(e2 / e1) / log(e1 / e0)
			if p > 0.0 and p < 10.0:
				ps.append(p)
	if ps.is_empty():
		return NAN
	var last := ps.slice(maxi(0, ps.size() - 3))
	last.sort()
	return last[last.size() / 2]

func _order() -> float:
	return order_of(_errors())

## Ejecuta los quince métodos desde los mismos datos y resume cada uno.
func _compare_all() -> void:
	cmp_rows.clear()
	var br := bracket_ok()
	for m in range(METHODS.size()):
		var row := {"m": m}
		if m in BRACKET and not br:
			row["estado"] = "sin cambio de signo en [a, b]"
			row["errores"] = []
			cmp_rows.append(row)
			continue
		var H := run_full(m)
		var tgt := _target(H, m)
		var errs := _errors_of(H, tgt)
		var conv := _converged(m, H)
		row["iter"] = H.size() - 1
		row["evals"] = (H.size() - 1) * int(EVALS_N[m])
		row["x"] = float(H[H.size() - 1]["x"])
		row["p"] = order_of(errs)
		row["errores"] = errs
		row["estado"] = "ok" if conv else ("diverge" if H.size() - 1 < MAX_IT else "no converge en %d iter." % MAX_IT)
		cmp_rows.append(row)

func _draw_iters() -> void:
	for c in iter_node.get_children():
		c.queue_free()
	var col_pt := glow_mat(Color(1.0, 0.8, 0.25), 3.0)
	var col_line := glow_mat(Color(1.0, 0.55, 0.2), 1.6)
	var col_aux := glow_mat(Color(0.8, 0.8, 0.85), 0.8)
	var n := hist.size()
	for i in range(n):
		var h: Dictionary = hist[i]
		var x: float = h["x"]
		if not _in_view(x):
			continue
		var fade := 0.35 + 0.65 * float(i + 1) / n
		var s := sphere(0.035 if i < n - 1 else 0.06, col_pt)
		s.position = _p(x, 0.0)
		s.scale = Vector3.ONE * fade
		iter_node.add_child(s)
		var recent := i >= n - 3
		match method:
			0, 4, 5, 6, 7:
				if i == n - 1 and h.has("a"):
					_slab(float(h["a"]), float(h["b"]))
					for e in ["a", "b"]:
						var xe: float = h[e]
						iter_node.add_child(rod(_p(xe, 0.0), _p(xe, _f(xe)), 0.008, col_line))
				if method in [4, 5] and recent and h.has("cuerda"):
					var cd: Array = h["cuerda"]
					iter_node.add_child(rod(_p(cd[0], cd[1]), _p(cd[2], cd[3]), 0.007, glow_mat(COLORS[method], 1.8)))
				if method == 6 and recent and h.has("medio"):
					var cm := sphere(0.03, glow_mat(Color(0.6, 0.55, 1.0), 2.5))
					cm.position = _p(float(h["medio"]), _f(float(h["medio"])))
					iter_node.add_child(cm)
				if method == 7 and i == n - 1 and h.has("tipo"):
					iter_node.add_child(label3d(str(h["tipo"]), _p(x, 0.0) + Vector3(0, -0.35, 0.03), Color(1, 1, 1), 0.0028))
			1, 8, 9, 10:
				if h.has("desde"):
					var xp: float = h["desde"]
					iter_node.add_child(rod(_p(xp, 0.0), _p(xp, _f(xp)), 0.006, col_aux))
					iter_node.add_child(rod(_p(xp, _f(xp)), _p(x, 0.0), 0.009, col_line))
					if method in [9, 10] and recent:
						_model_curve(h)
			2:
				if i >= 1:
					var hp: Dictionary = hist[i - 1]
					var xp2: float = hp["x"]
					iter_node.add_child(rod(_p(xp2, _f(xp2)), _p(x, _f(x)), 0.007, col_line))
					if i + 1 < n:
						var xn: float = hist[i + 1]["x"]
						iter_node.add_child(rod(_p(x, _f(x)), _p(xn, 0.0), 0.005, col_aux))
			3:
				if i + 1 < n:
					var xn2: float = hist[i + 1]["x"]
					iter_node.add_child(rod(_p(x, x), _p(x, xn2), 0.008, col_line))
					iter_node.add_child(rod(_p(x, xn2), _p(xn2, xn2), 0.008, col_line))
			11:
				if h.has("aux") and recent:
					var xp3: float = h["desde"]
					var xq: float = h["aux"]
					iter_node.add_child(rod(_p(xp3, 0.0), _p(xp3, _f(xp3)), 0.006, col_aux))
					iter_node.add_child(rod(_p(xq, _f(xq)), _p(x, 0.0), 0.008, col_line))
					iter_node.add_child(rod(_p(xp3, _f(xp3)), _p(xq, _f(xq)), 0.006, glow_mat(COLORS[11], 1.8)))
			12, 13:
				if i >= 3 and i == n - 1:
					_parabola(hist[i - 3], hist[i - 2], hist[i - 1], method == 13)
			14:
				if h.has("g1"):
					var xs0: float = h["desde"]
					var g1: float = h["g1"]
					var g2: float = h["g2"]
					iter_node.add_child(rod(_p(xs0, xs0), _p(xs0, g1), 0.006, col_aux))
					iter_node.add_child(rod(_p(xs0, g1), _p(g1, g1), 0.006, col_aux))
					iter_node.add_child(rod(_p(g1, g1), _p(g1, g2), 0.006, col_aux))
					iter_node.add_child(rod(_p(xs0, 0.0), _p(x, 0.0), 0.012, glow_mat(COLORS[14], 2.2)))
	if not is_nan(root_ref) and _in_view(root_ref):
		var r := sphere(0.06, glow_mat(Color(0.3, 1.0, 0.5), 2.8))
		r.position = _p(root_ref, 0.0) + Vector3(0, 0, 0.03)
		iter_node.add_child(r)
	_update_table()
	if plot:
		plot.queue_redraw()

func _slab(a: float, b: float) -> void:
	var slab := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var wa := _X(minf(a, b))
	var wb := _X(maxf(a, b))
	bm.size = Vector3(maxf(0.004, wb - wa), HGT * 2.0, 0.02)
	slab.mesh = bm
	slab.material_override = glass_mat(COLORS[method], 0.16)
	slab.position = Vector3((wa + wb) * 0.5, 0, -0.02)
	iter_node.add_child(slab)

## Modelo local de Halley (hipérbola tangente) o Chebyshev (parábola de Taylor).
func _model_curve(h: Dictionary) -> void:
	var xp: float = h["desde"]
	var f: float = h["f"]
	var d: float = h["d"]
	var d2: float = h["d2"]
	var span: float = (float(h["x"]) - xp) * 1.4
	var pts := PackedVector3Array()
	for k in range(41):
		var t := span * float(k) / 40.0
		var y := 0.0
		if method == 10:
			y = f + d * t + 0.5 * d2 * t * t
		else:
			var q := 1.0 - d2 * t / (2.0 * d) if d != 0.0 else 1.0
			y = f + d * t / q if q != 0.0 else INF
		if is_finite(y) and absf(y * ky) < HGT * 1.2:
			pts.append(_p(xp + t, y))
	if pts.size() >= 2:
		iter_node.add_child(tube(pts, 0.008, glow_mat(COLORS[method], 2.0), 6))

## Parábola por tres iterados: y = P(x) (Müller) o x = P(y) (cuadrática inversa).
func _parabola(h0: Dictionary, h1: Dictionary, h2: Dictionary, inverse: bool) -> void:
	var xs := [float(h0["x"]), float(h1["x"]), float(h2["x"])]
	var ys := [float(h0["fx"]), float(h1["fx"]), float(h2["fx"])]
	var pts := PackedVector3Array()
	var u := xs if not inverse else ys
	var v := ys if not inverse else xs
	var lo: float = minf(minf(u[0], u[1]), minf(u[2], 0.0 if inverse else u[2]))
	var hi: float = maxf(maxf(u[0], u[1]), maxf(u[2], 0.0 if inverse else u[2]))
	var pad := (hi - lo) * 0.25
	for k in range(61):
		var t := lerpf(lo - pad, hi + pad, float(k) / 60.0)
		var val := 0.0
		for i in range(3):
			var term: float = v[i]
			for j in range(3):
				if j != i:
					if u[i] == u[j]:
						return
					term *= (t - u[j]) / (u[i] - u[j])
			val += term
		var px := val if inverse else t
		var py := t if inverse else val
		if _in_view(px) and absf(py * ky) < HGT * 1.2:
			pts.append(_p(px, py))
	if pts.size() >= 2:
		iter_node.add_child(tube(pts, 0.008, glow_mat(COLORS[method], 2.0), 6))
	for i in range(3):
		var s := sphere(0.028, glow_mat(COLORS[method], 2.5))
		s.position = _p(xs[i], ys[i])
		iter_node.add_child(s)

func _update_table() -> void:
	if compare:
		_table = _compare_table()
		return
	var e := _errors()
	var lines := ["[font_size=12][color=#8fa3b8] n │ xₙ                  │ f(xₙ)          │ |error|[/color]"]
	var start := maxi(0, hist.size() - 9)
	for i in range(start, hist.size()):
		var h: Dictionary = hist[i]
		var extra := ""
		if method == 7 and h.has("tipo"):
			extra = "  · " + str(h["tipo"])
		elif method == 12 and h.get("compleja", false):
			extra = "  · raíz compleja (parte real)"
		lines.append("%2d │ %+.14f │ %s │ %s%s" % [i, float(h["x"]), LabUI.sci(float(h["fx"]), 2), LabUI.sci(float(e[i]), 2), extra])
	var p := _order()
	var status := ""
	if converged():
		status = "   ·   ✔ convergido"
	elif method in BRACKET and not bracket_ok():
		status = "   ·   [color=#ff7766]✖ f(a)·f(b) > 0: el intervalo no encierra una raíz[/color]"
	elif hist.size() > 1 and not _in_view(float(hist[hist.size() - 1]["x"])):
		status = "   ·   [color=#ff7766]✖ se sale del dominio (diverge)[/color]"
	lines.append("[/font_size]Iteraciones: %d · evaluaciones: %d (%s por paso)%s%s" % [hist.size() - 1, (hist.size() - 1) * int(EVALS_N[method]), EVALS[method], "   ·   orden observado p ≈ %.2f (teórico %s)" % [p, ORDER_TH[method]] if not is_nan(p) else "", status])
	_table = "\n".join(lines)

func _compare_table() -> String:
	var lines := ["[font_size=12][color=#8fa3b8]Todos desde a = %s, b = %s, x₀ = %s, x₁ = %s · tolerancia %s[/color]" % [str(a0), str(b0), str(x0), str(x1), LabUI.sci(tol, 0)]]
	lines.append("[color=#8fa3b8]  Método             │ iter │ eval │ p teórico │ p obs. │ x final[/color]")
	var best := -1
	var best_ev := 1 << 30
	for r in cmp_rows:
		if str(r["estado"]) == "ok" and int(r["evals"]) < best_ev:
			best_ev = int(r["evals"])
			best = int(r["m"])
	for r in cmp_rows:
		var m: int = r["m"]
		var sq := "[color=#%s]■[/color]" % COLORS[m].to_html(false)
		var name: String = SHORT[m]
		if m == method:
			name = "[b]%s[/b]" % name
		if str(r["estado"]) == "ok":
			lines.append("%s %s │ %d │ %d │ %s │ %s │ %.12f%s" % [sq, name, int(r["iter"]), int(r["evals"]), ORDER_TH[m], "%.2f" % float(r["p"]) if not is_nan(float(r["p"])) else "—", float(r["x"]), "  ★ menos evaluaciones" if m == best else ""])
		else:
			lines.append("%s %s │ [color=#ff7766]%s[/color]" % [sq, name, r["estado"]])
	lines.append("[/font_size]")
	return "\n".join(lines)

func info() -> String:
	return _table

func build_ui(p: VBoxContainer) -> void:
	LabUI.option(p, "Ejemplo:", PRESETS.map(func(q): return q["nombre"]), preset, func(i): load_preset(i))
	LabUI.option(p, "Método:", METHODS, method, func(i): set_method(i))
	_ui["f"] = LabUI.expr_field(p, "f(x) =", f_expr.source, ["x"], false, func(m):
		f_expr = m
		_rebuild_curve()
		reset())
	_ui["g"] = LabUI.expr_field(p, "g(x) = (punto fijo: x = g(x))", g_expr.source, ["x"], false, func(m):
		g_expr = m
		_rebuild_curve()
		reset())
	var r := LabUI.row(p)
	_ui["a"] = LabUI.spin(r, "a", -50, 50, 0.1, a0, func(v): a0 = v; reset())
	_ui["b"] = LabUI.spin(r, "b", -50, 50, 0.1, b0, func(v): b0 = v; reset())
	var r2 := LabUI.row(p)
	_ui["x0"] = LabUI.spin(r2, "x₀", -50, 50, 0.1, x0, func(v): x0 = v; reset())
	_ui["x1"] = LabUI.spin(r2, "x₁", -50, 50, 0.1, x1, func(v): x1 = v; reset())
	var r3 := LabUI.row(p)
	_ui["xa"] = LabUI.spin(r3, "dominio", -100, 0, 0.5, xa, func(v): xa = v; _rebuild_curve(); reset())
	_ui["xa"].set_meta("lab_param", "dominio desde")
	_ui["xb"] = LabUI.spin(r3, "a", 0, 100, 0.5, xb, func(v): xb = v; _rebuild_curve(); reset())
	_ui["xb"].set_meta("lab_param", "dominio hasta")
	LabUI.slider(p, "Tolerancia 10ᵏ", -14, -2, 1, round(log(tol) / log(10.0)), func(v):
		tol = pow(10.0, v)
		reset(), "%.0f")
	var r4 := LabUI.row(p)
	LabUI.button(r4, "▶ Paso", func(): do_step())
	LabUI.button(r4, "⏩ Resolver", func(): _auto = true)
	LabUI.button(r4, "⟲", reset)
	LabUI.check(p, "Comparar todos los métodos", compare, func(v):
		compare = v
		reset()
		lab._update_info(false))
	LabUI.section(p, "Convergencia: log₁₀ |error| por iteración")
	plot = ConvPlot.new()
	plot.module = self
	plot.custom_minimum_size = Vector2(260, 140)
	p.add_child(plot)
	_desc = LabUI.note(p, DESCS[method])
	LabUI.note(p, "x₂ de Müller y de la cuadrática inversa = (x₀ + x₁)/2. Las derivadas se calculan por diferencias centradas.")

func set_method(i: int) -> void:
	method = clampi(i, 0, METHODS.size() - 1)
	if _desc:
		_desc.text = DESCS[method]
	_rebuild_curve()
	reset()
	if lab:
		lab._update_info(false)

func load_preset(i: int) -> void:
	preset = clampi(i, 0, PRESETS.size() - 1)
	var q: Dictionary = PRESETS[preset]
	f_expr = MathExpr.parse(q["f"], ["x"])
	g_expr = MathExpr.parse(q["g"], ["x"])
	a0 = q["a"]
	b0 = q["b"]
	x0 = q["x0"]
	x1 = q["x1"]
	xa = q["dom"][0]
	xb = q["dom"][1]
	if not _ui.is_empty():
		(_ui["f"] as LineEdit).text = q["f"]
		(_ui["g"] as LineEdit).text = q["g"]
		for k in ["a", "b", "x0", "x1", "xa", "xb"]:
			var val: float = {"a": a0, "b": b0, "x0": x0, "x1": x1, "xa": xa, "xb": xb}[k]
			(_ui[k] as SpinBox).set_value_no_signal(val)
	_rebuild_curve()
	reset()
	if lab:
		lab._update_info(false)

func pick(origin: Vector3, dir: Vector3):
	if absf(dir.z) < 1e-6:
		return null
	var t := -origin.z / dir.z
	if t < 0.0:
		return null
	var p := origin + dir * t
	if absf(p.x) > W or absf(p.y - LIFT) > HGT:
		return null
	return p

func _xw(wx: float) -> float:
	return wx / (2.0 * W / (xb - xa)) + (xa + xb) * 0.5

func hover_text(hit: Vector3) -> String:
	var x := _xw(hit.x)
	return "x = %.4f\nf(x) = %.5f\nf′(x) ≈ %.4f" % [x, _f(x), _df(x)]

func perturb(hit: Vector3, first: bool) -> void:
	if not first:
		return
	var x := _xw(hit.x)
	if method in BRACKET:
		if absf(x - a0) < absf(x - b0): a0 = x
		else: b0 = x
	elif method in [2, 12, 13]:
		x1 = x0
		x0 = x
	else:
		x0 = x
	for k in ["a", "b", "x0", "x1"]:
		if _ui.has(k):
			(_ui[k] as SpinBox).set_value_no_signal({"a": a0, "b": b0, "x0": x0, "x1": x1}[k])
	reset()

func critical_points() -> Array:
	var out := []
	for r in roots:
		out.append({"pos": to_global(_p(r, 0.0)), "nombre": "Raíz x* = %.12f" % r, "dist": 2.0})
	if not hist.is_empty() and _in_view(float(hist[0]["x"])):
		out.append({"pos": to_global(_p(float(hist[0]["x"]), 0.0)), "nombre": "Punto inicial", "dist": 3.0})
	return out

func demo(extra: Array) -> void:
	if "comparar" in extra:
		compare = true
		set_method(9)
		for i in range(3):
			do_step()
		return
	for i in range(4):
		do_step()

class ConvPlot extends Control:
	var module
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.03, 0.05, 0.08, 0.9))
		for k in range(0, 17, 4):
			var y := r.size.y * float(k) / 16.0
			draw_line(Vector2(0, y), Vector2(r.size.x, y), Color(0.2, 0.3, 0.4, 0.5))
		if module == null:
			return
		var series := []
		if module.compare:
			var nmax := 10
			for row in module.cmp_rows:
				nmax = maxi(nmax, (row["errores"] as Array).size() - 1)
			for row in module.cmp_rows:
				series.append([row["errores"], module.COLORS[int(row["m"])], int(row["m"]) == module.method, nmax])
		else:
			var e: Array = module._errors()
			series.append([e, Color(1.0, 0.6, 0.2), true, maxi(10, e.size() - 1)])
		for s in series:
			var e: Array = s[0]
			if e.is_empty():
				continue
			var pts := PackedVector2Array()
			var cap := mini(e.size(), 60)
			for i in range(cap):
				var le: float = log(maxf(float(e[i]), 1e-16)) / log(10.0)
				var x := r.size.x * float(i) / float(mini(int(s[3]), 59))
				var y := r.size.y * clampf((2.0 - le) / 18.0, 0.0, 1.0)
				pts.append(Vector2(x, y))
				if s[2]:
					draw_circle(Vector2(x, y), 2.5, s[1])
			if pts.size() >= 2:
				draw_polyline(pts, s[1], 2.4 if s[2] else 1.3, true)
		draw_string(ThemeDB.fallback_font, Vector2(4, 12), "10²", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.7, 0.8))
		draw_string(ThemeDB.fallback_font, Vector2(4, r.size.y - 4), "10⁻¹⁶", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.7, 0.8))
