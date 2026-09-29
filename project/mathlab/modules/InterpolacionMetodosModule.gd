extends LabModule
## Métodos de interpolación en 1D, comparados sobre la misma función y los mismos
## nodos:
##   · polinómica global: Lagrange (fórmula baricéntrica) y Newton (diferencias
##     divididas, con sus polinomios parciales);
##   · por tramos: lineal, vecino más cercano, splines cúbicos (natural, sujeto,
##     not-a-knot), Hermite cúbico, PCHIP (Fritsch–Carlson) y Akima;
##   · otras: racional de Floater–Hormann, trigonométrica y mínimos cuadrados de
##     grado m.
## Nodos equiespaciados, de Chebyshev, de Chebyshev–Lobatto o aleatorios (fenómeno
## de Runge y constante de Lebesgue), error |f − p| a lo largo de x y un modo de
## datos libres para arrastrar los nodos.

const METHODS := [
	"Lagrange (baricéntrica)", "Newton (diferencias divididas)", "Lineal a trozos", "Vecino más cercano",
	"Spline cúbico natural", "Spline cúbico sujeto", "Spline cúbico not-a-knot", "Hermite cúbico (con f′)",
	"PCHIP (monótono, Fritsch–Carlson)", "Akima", "Racional de Floater–Hormann (d = 3)",
	"Trigonométrica (base de Fourier)", "Mínimos cuadrados (grado m)",
]
const SHORT := ["Lagrange", "Newton", "Lineal", "Vecino", "Spline natural", "Spline sujeto", "Not-a-knot",
	"Hermite", "PCHIP", "Akima", "Floater–Hormann", "Trigonométrica", "Mín. cuadrados"]
const COLORS := [
	Color(1.0, 0.35, 0.3), Color(1.0, 0.8, 0.95), Color(0.75, 0.78, 0.85), Color(0.6, 0.6, 0.65),
	Color(1.0, 0.6, 0.15), Color(1.0, 0.85, 0.3), Color(0.95, 0.45, 0.7), Color(0.55, 1.0, 0.45),
	Color(0.25, 0.9, 1.0), Color(0.45, 0.55, 1.0), Color(0.8, 0.45, 1.0), Color(0.3, 1.0, 0.75),
	Color(1.0, 1.0, 1.0),
]
const DESCS := [
	"Polinomio único de grado n − 1 que pasa por todos los nodos. La fórmula baricéntrica p(x) = Σ wⱼyⱼ/(x − xⱼ) / Σ wⱼ/(x − xⱼ) es estable. Con nodos equiespaciados oscila en los bordes (Runge); con Chebyshev converge.",
	"El mismo polinomio escrito como c₀ + c₁(x − x₀) + c₂(x − x₀)(x − x₁) + …, con cₖ = f[x₀,…,xₖ]. Añadir un nodo solo añade un término: se ven los polinomios parciales p₀, p₁, …",
	"Une los nodos con segmentos: continua pero con picos. Error O(h²).",
	"Toma el valor del nodo más próximo: escalonada y discontinua. Error O(h).",
	"Cúbicas por tramos con primera y segunda derivada continuas (C²) y S″ = 0 en los extremos. Minimiza la «energía de flexión» ∫S″². Error O(h⁴) en el interior.",
	"Spline C² con las pendientes de f en los extremos (S′(a) = f′(a), S′(b) = f′(b)): error O(h⁴) en todo el intervalo.",
	"Spline C² en el que la tercera derivada también es continua en x₁ y xₙ₋₂ (los dos primeros y los dos últimos tramos son la misma cúbica). Es el spline por defecto de MATLAB.",
	"Cúbicas por tramos que igualan el valor y la derivada f′ en cada nodo: C¹ y error O(h⁴). En datos libres las pendientes se estiman con diferencias centradas.",
	"Hermite con pendientes elegidas para conservar la monotonía (media armónica ponderada, 0 en los extremos locales): nunca se sale del rango de los datos.",
	"Pendientes por una media de las pendientes vecinas ponderada por sus diferencias: natural y sin oscilaciones grandes cerca de cambios bruscos.",
	"Mezcla de polinomios locales de grado d en forma baricéntrica: racional sin polos en el intervalo, sin fenómeno de Runge aun con nodos equiespaciados, y de orden h^(d+1).",
	"Combinación de 1, cos kθ y sen kθ con θ = π(x − a)/(b − a): ideal para datos periódicos; con datos no periódicos aparece el fenómeno de Gibbs.",
	"No interpola: ajusta un polinomio de grado m < n minimizando Σ(p(xᵢ) − yᵢ)² (base de Chebyshev). Útil con datos con ruido.",
]
const FUNCS := [
	{"nombre": "Runge  1/(1 + 25x²)", "f": "1/(1 + 25x^2)", "a": -1.0, "b": 1.0},
	{"nombre": "sin(πx)", "f": "sin(pi x)", "a": -1.0, "b": 1.0},
	{"nombre": "|x| (esquina)", "f": "abs(x)", "a": -1.0, "b": 1.0},
	{"nombre": "tanh(12x) (escalón suave)", "f": "tanh(12x)", "a": -1.0, "b": 1.0},
	{"nombre": "eˣ", "f": "exp(x)", "a": -1.0, "b": 1.0},
	{"nombre": "√(1 − x²) (semicírculo)", "f": "sqrt(1 - x^2)", "a": -1.0, "b": 1.0},
	{"nombre": "x·sin(6x)", "f": "x sin(6x)", "a": -1.0, "b": 1.0},
	{"nombre": "Datos libres (arrastra los nodos)", "f": "", "a": -1.0, "b": 1.0},
]
const NODE_KINDS := ["Equiespaciados", "Chebyshev (raíces de Tₙ)", "Chebyshev–Lobatto (extremos)", "Aleatorios"]
const W := 3.0
const HGT := 1.6
const LIFT := 0.9
const SAMPLES := 400

var func_idx: int = 0
var f_expr: MathExpr
var a: float = -1.0
var b: float = 1.0
var n: int = 11
var node_kind: int = 0
var enabled: Array = [true, false, true, false, true, false, false, false, true, false, false, false, false]
var deg_ls: int = 4
var x_eval: float = 0.9
var show_partials: bool = false
var free_data: bool = false
var xs: Array = []
var ys: Array = []
var ds: Array = []                 # derivadas en los nodos (Hermite)
var free_ys: Array = []
var ylo: float = -0.2
var yhi: float = 1.2
var errs: Dictionary = {}          # método → {max, rms, xmax}
var lebesgue: float = NAN
var _w_lag: Array = []
var _w_fh: Array = []
var _newton_c: Array = []
var _spl: Dictionary = {}          # tipo → momentos M
var _slopes: Dictionary = {}       # "pchip"/"akima" → pendientes
var _trig: Array = []
var _ls: Array = []
var curve_node: Node3D
var nodes_node: Node3D
var eval_node: Node3D
var err_plot: Control
var _desc: Label
var _sel: int = -1
var _ui := {}

func title() -> String: return "Métodos de interpolación"
func planar() -> bool: return true
func formula() -> String: return "pₙ(xᵢ) = yᵢ,  i = 0 … n − 1   ·   error f(x) − p(x) = f⁽ⁿ⁾(ξ)/n! · Π(x − xᵢ)"
func perturb_hint() -> String: return "arrastra un nodo en vertical" if free_data else "clic: punto x* donde se evalúan los métodos"
func view() -> Dictionary: return {"target": Vector3(0, LIFT, 0), "dist": 8.0, "yaw": -6.0, "pitch": -6.0}

func setup() -> void:
	position = Vector3(0, LIFT, 0)
	f_expr = MathExpr.parse(FUNCS[0]["f"], ["x"])
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(W * 2.0 + 0.4, HGT * 2.0 + 0.5, 0.04)
	board.mesh = bm
	board.material_override = glass_mat(Color(0.05, 0.12, 0.2), 0.55)
	board.position = Vector3(0, 0, -0.12)
	add_child(board)
	curve_node = Node3D.new()
	add_child(curve_node)
	nodes_node = Node3D.new()
	add_child(nodes_node)
	eval_node = Node3D.new()
	add_child(eval_node)
	rebuild()

# --- Datos ---------------------------------------------------------------------------

func f(x: float) -> float:
	return f_expr.eval_real({"x": x}) if not free_data else eval_method(2, x)

func _df(x: float) -> float:
	var h := 1e-5 * maxf(1.0, absf(x))
	return (f_expr.eval_real({"x": x + h}) - f_expr.eval_real({"x": x - h})) / (2.0 * h)

func make_nodes() -> Array:
	var out := []
	match node_kind:
		0:
			for i in range(n):
				out.append(lerpf(a, b, float(i) / float(n - 1)))
		1:
			for i in range(n):
				out.append((a + b) * 0.5 + (b - a) * 0.5 * cos(PI * float(2 * i + 1) / float(2 * n)))
		2:
			for i in range(n):
				out.append((a + b) * 0.5 + (b - a) * 0.5 * cos(PI * float(i) / float(n - 1)))
		3:
			var rng := RandomNumberGenerator.new()
			rng.seed = 777 + n
			out.append(a)
			out.append(b)
			for i in range(n - 2):
				out.append(rng.randf_range(a, b))
	out.sort()
	return out

func rebuild() -> void:
	free_data = func_idx == FUNCS.size() - 1
	xs = make_nodes()
	ys.clear()
	ds.clear()
	if free_data:
		if free_ys.size() != n:
			free_ys.clear()
			for x in xs:
				free_ys.append(1.0 if float(x) > 0.0 else 0.0)
		ys = free_ys.duplicate()
		for i in range(n):
			var i0 := maxi(0, i - 1)
			var i1 := mini(n - 1, i + 1)
			ds.append((float(ys[i1]) - float(ys[i0])) / maxf(1e-12, float(xs[i1]) - float(xs[i0])))
	else:
		for x in xs:
			ys.append(f_expr.eval_real({"x": x}))
			ds.append(_df(x))
	_prepare()
	_measure()
	_draw()

## Precalcula pesos, coeficientes y momentos de todos los métodos.
func _prepare() -> void:
	# Pesos baricéntricos de Lagrange.
	_w_lag.clear()
	for j in range(n):
		var w := 1.0
		for k in range(n):
			if k != j:
				w *= float(xs[j]) - float(xs[k])
		_w_lag.append(1.0 / w if w != 0.0 else 0.0)
	# Diferencias divididas de Newton.
	var c := ys.duplicate()
	for k in range(1, n):
		for i in range(n - 1, k - 1, -1):
			c[i] = (float(c[i]) - float(c[i - 1])) / (float(xs[i]) - float(xs[i - k]))
	_newton_c = c
	# Splines cúbicos por momentos.
	_spl = {"natural": _moments("natural"), "sujeto": _moments("sujeto"), "notaknot": _moments("notaknot")}
	_slopes = {"pchip": _pchip_slopes(), "akima": _akima_slopes()}
	_w_fh = _fh_weights(mini(3, n - 1))
	_trig = _trig_coefs()
	_ls = _ls_coefs(mini(deg_ls, n - 1))

## Momentos Mᵢ = S″(xᵢ) del spline cúbico con la condición de borde dada.
func _moments(bc: String) -> Array:
	if n < 3 or (bc == "notaknot" and n < 4):
		var z := []
		z.resize(n)
		z.fill(0.0)
		return z
	var h := []
	for i in range(n - 1):
		h.append(float(xs[i + 1]) - float(xs[i]))
	var A := []
	var r := []
	for i in range(n):
		var row := []
		row.resize(n)
		row.fill(0.0)
		A.append(row)
		r.append(0.0)
	for i in range(1, n - 1):
		A[i][i - 1] = h[i - 1]
		A[i][i] = 2.0 * (h[i - 1] + h[i])
		A[i][i + 1] = h[i]
		r[i] = 6.0 * ((float(ys[i + 1]) - float(ys[i])) / h[i] - (float(ys[i]) - float(ys[i - 1])) / h[i - 1])
	match bc:
		"natural":
			A[0][0] = 1.0
			A[n - 1][n - 1] = 1.0
		"sujeto":
			var da: float = ds[0]
			var db: float = ds[n - 1]
			A[0][0] = 2.0 * h[0]
			A[0][1] = h[0]
			r[0] = 6.0 * ((float(ys[1]) - float(ys[0])) / h[0] - da)
			A[n - 1][n - 2] = h[n - 2]
			A[n - 1][n - 1] = 2.0 * h[n - 2]
			r[n - 1] = 6.0 * (db - (float(ys[n - 1]) - float(ys[n - 2])) / h[n - 2])
		"notaknot":
			A[0][0] = h[1]
			A[0][1] = -(h[0] + h[1])
			A[0][2] = h[0]
			A[n - 1][n - 3] = h[n - 2]
			A[n - 1][n - 2] = -(h[n - 3] + h[n - 2])
			A[n - 1][n - 1] = h[n - 3]
	return solve_dense(A, r)

## Eliminación gaussiana con pivoteo parcial (sistemas pequeños y densos).
static func solve_dense(A: Array, r: Array) -> Array:
	var m := r.size()
	var M := []
	for i in range(m):
		M.append((A[i] as Array).duplicate() + [r[i]])
	for col in range(m):
		var piv := col
		for i in range(col + 1, m):
			if absf(M[i][col]) > absf(M[piv][col]):
				piv = i
		var t = M[col]
		M[col] = M[piv]
		M[piv] = t
		if absf(M[col][col]) < 1e-300:
			continue
		for i in range(col + 1, m):
			var fct: float = M[i][col] / M[col][col]
			if fct == 0.0:
				continue
			for k in range(col, m + 1):
				M[i][k] -= fct * M[col][k]
	var x := []
	x.resize(m)
	x.fill(0.0)
	for i in range(m - 1, -1, -1):
		var s: float = M[i][m]
		for k in range(i + 1, m):
			s -= M[i][k] * x[k]
		x[i] = s / M[i][i] if absf(M[i][i]) > 1e-300 else 0.0
	return x

func _pchip_slopes() -> Array:
	var d := []
	d.resize(n)
	d.fill(0.0)
	if n < 2:
		return d
	var h := []
	var dl := []
	for i in range(n - 1):
		h.append(float(xs[i + 1]) - float(xs[i]))
		dl.append((float(ys[i + 1]) - float(ys[i])) / h[i])
	if n == 2:
		d[0] = dl[0]
		d[1] = dl[0]
		return d
	for k in range(1, n - 1):
		if dl[k - 1] * dl[k] <= 0.0:
			d[k] = 0.0
		else:
			var w1: float = 2.0 * h[k] + h[k - 1]
			var w2: float = h[k] + 2.0 * h[k - 1]
			d[k] = (w1 + w2) / (w1 / dl[k - 1] + w2 / dl[k])
	d[0] = _pchip_end(h[0], h[1], dl[0], dl[1])
	d[n - 1] = _pchip_end(h[n - 2], h[n - 3], dl[n - 2], dl[n - 3])
	return d

static func _pchip_end(h0: float, h1: float, d0: float, d1: float) -> float:
	var dd := ((2.0 * h0 + h1) * d0 - h0 * d1) / (h0 + h1)
	if signf(dd) != signf(d0):
		return 0.0
	if signf(d0) != signf(d1) and absf(dd) > 3.0 * absf(d0):
		return 3.0 * d0
	return dd

func _akima_slopes() -> Array:
	var d := []
	d.resize(n)
	d.fill(0.0)
	if n < 3:
		var s0 := (float(ys[n - 1]) - float(ys[0])) / maxf(1e-12, float(xs[n - 1]) - float(xs[0]))
		d.fill(s0)
		return d
	var m := []
	for i in range(n - 1):
		m.append((float(ys[i + 1]) - float(ys[i])) / (float(xs[i + 1]) - float(xs[i])))
	# Pendientes ficticias a cada lado (extrapolación lineal de Akima).
	var mm := [0.0, 0.0] + m + [0.0, 0.0]
	var L := m.size()
	mm[1] = 2.0 * m[0] - m[1]
	mm[0] = 2.0 * mm[1] - m[0]
	mm[L + 2] = 2.0 * m[L - 1] - m[L - 2]
	mm[L + 3] = 2.0 * mm[L + 2] - m[L - 1]
	for i in range(n):
		var m1: float = mm[i]
		var m2: float = mm[i + 1]
		var m3: float = mm[i + 2]
		var m4: float = mm[i + 3]
		var w1 := absf(m4 - m3)
		var w2 := absf(m2 - m1)
		d[i] = (m2 + m3) * 0.5 if w1 + w2 < 1e-14 else (w1 * m2 + w2 * m3) / (w1 + w2)
	return d

## Pesos baricéntricos de Floater–Hormann de grado d.
func _fh_weights(d: int) -> Array:
	var w := []
	for k in range(n):
		var s := 0.0
		for i in range(maxi(0, k - d), mini(k, n - 1 - d) + 1):
			var prod := 1.0
			for j in range(i, i + d + 1):
				if j != k:
					prod /= absf(float(xs[k]) - float(xs[j]))
			s += prod
		w.append(s * (1.0 if (k - d) % 2 == 0 else -1.0))
	return w

func _theta(x: float) -> float:
	return PI * (x - a) / (b - a)

func _trig_basis(x: float) -> Array:
	var th := _theta(x)
	var out := [1.0]
	var k := 1
	while out.size() < n:
		out.append(cos(k * th))
		if out.size() < n:
			out.append(sin(k * th))
		k += 1
	return out

func _trig_coefs() -> Array:
	var A := []
	for x in xs:
		A.append(_trig_basis(x))
	return solve_dense(A, ys.duplicate())

func _cheb(x: float, deg: int) -> Array:
	var s := (2.0 * x - a - b) / (b - a)
	var t := [1.0]
	if deg >= 1:
		t.append(s)
	for k in range(2, deg + 1):
		t.append(2.0 * s * float(t[k - 1]) - float(t[k - 2]))
	return t

func _ls_coefs(deg: int) -> Array:
	var m := deg + 1
	var ata := []
	var atb := []
	for i in range(m):
		var row := []
		row.resize(m)
		row.fill(0.0)
		ata.append(row)
		atb.append(0.0)
	for q in range(n):
		var phi := _cheb(xs[q], deg)
		for i in range(m):
			atb[i] += phi[i] * float(ys[q])
			for j in range(m):
				ata[i][j] += phi[i] * phi[j]
	return solve_dense(ata, atb)

# --- Evaluación ----------------------------------------------------------------------

func _interval(x: float) -> int:
	var lo := 0
	var hi := n - 2
	if x <= float(xs[0]):
		return 0
	if x >= float(xs[n - 1]):
		return n - 2
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if float(xs[mid]) <= x:
			lo = mid
		else:
			hi = mid - 1
	return lo

func _bary(x: float, w: Array) -> float:
	var num := 0.0
	var den := 0.0
	for j in range(n):
		var dx := x - float(xs[j])
		if dx == 0.0:
			return ys[j]
		var t: float = float(w[j]) / dx
		num += t * float(ys[j])
		den += t
	return num / den

func _hermite(x: float, d: Array) -> float:
	var i := _interval(x)
	var x0: float = xs[i]
	var x1: float = xs[i + 1]
	var h := x1 - x0
	var t := (x - x0) / h
	var t2 := t * t
	var t3 := t2 * t
	return (2 * t3 - 3 * t2 + 1) * float(ys[i]) + (t3 - 2 * t2 + t) * h * float(d[i]) + (-2 * t3 + 3 * t2) * float(ys[i + 1]) + (t3 - t2) * h * float(d[i + 1])

func _spline_eval(x: float, M: Array) -> float:
	var i := _interval(x)
	var x0: float = xs[i]
	var x1: float = xs[i + 1]
	var h := x1 - x0
	var m0: float = M[i]
	var m1: float = M[i + 1]
	return m0 * pow(x1 - x, 3) / (6 * h) + m1 * pow(x - x0, 3) / (6 * h) + (float(ys[i]) / h - m0 * h / 6.0) * (x1 - x) + (float(ys[i + 1]) / h - m1 * h / 6.0) * (x - x0)

## Valor del interpolante del método m en x.
func eval_method(m: int, x: float) -> float:
	if n == 0:
		return NAN
	if n == 1:
		return ys[0]
	match m:
		0: return _bary(x, _w_lag)
		1:
			var p: float = _newton_c[n - 1]
			for k in range(n - 2, -1, -1):
				p = p * (x - float(xs[k])) + float(_newton_c[k])
			return p
		2:
			var i := _interval(x)
			var t := (x - float(xs[i])) / (float(xs[i + 1]) - float(xs[i]))
			return lerpf(ys[i], ys[i + 1], t)
		3:
			var i2 := _interval(x)
			return ys[i2] if x - float(xs[i2]) <= float(xs[i2 + 1]) - x else ys[i2 + 1]
		4: return _spline_eval(x, _spl["natural"])
		5: return _spline_eval(x, _spl["sujeto"])
		6:
			if n < 4:
				return _bary(x, _w_lag)
			return _spline_eval(x, _spl["notaknot"])
		7: return _hermite(x, ds)
		8: return _hermite(x, _slopes["pchip"])
		9: return _hermite(x, _slopes["akima"])
		10: return _bary(x, _w_fh)
		11:
			var phi := _trig_basis(x)
			var s := 0.0
			for k in range(mini(phi.size(), _trig.size())):
				s += float(phi[k]) * float(_trig[k])
			return s
		12:
			var ch := _cheb(x, _ls.size() - 1)
			var s2 := 0.0
			for k in range(_ls.size()):
				s2 += float(ch[k]) * float(_ls[k])
			return s2
	return NAN

## Polinomio parcial de Newton pₖ (primeros k + 1 términos).
func newton_partial(k: int, x: float) -> float:
	var p: float = _newton_c[k]
	for j in range(k - 1, -1, -1):
		p = p * (x - float(xs[j])) + float(_newton_c[j])
	return p

func _measure() -> void:
	errs.clear()
	if free_data:
		lebesgue = _lebesgue()
		return
	for m in range(METHODS.size()):
		var mx := 0.0
		var xm := a
		var ss := 0.0
		for i in range(SAMPLES + 1):
			var x := lerpf(a, b, float(i) / SAMPLES)
			var e := absf(f(x) - eval_method(m, x))
			if not is_finite(e):
				e = 1e30
			ss += e * e
			if e > mx:
				mx = e
				xm = x
		errs[m] = {"max": mx, "rms": sqrt(ss / (SAMPLES + 1)), "xmax": xm}
	lebesgue = _lebesgue()

## Constante de Lebesgue Λ = máx Σ|ℓⱼ(x)| de los nodos (cuánto amplifica la interpolación polinómica los errores).
func _lebesgue() -> float:
	var best := 0.0
	for i in range(SAMPLES + 1):
		var x := lerpf(a, b, float(i) / SAMPLES)
		var den := 0.0
		var terms := []
		var exact := false
		for j in range(n):
			var dx := x - float(xs[j])
			if dx == 0.0:
				exact = true
				break
			var t: float = float(_w_lag[j]) / dx
			terms.append(t)
			den += t
		if exact:
			best = maxf(best, 1.0)
			continue
		var s := 0.0
		for t in terms:
			s += absf(float(t))
		best = maxf(best, s / absf(den))
	return best

# --- Dibujo --------------------------------------------------------------------------

func _X(x: float) -> float:
	return (x - (a + b) * 0.5) * (2.0 * W / (b - a))

func _Y(y: float) -> float:
	return clampf(lerpf(-HGT, HGT, (y - ylo) / maxf(1e-9, yhi - ylo)), -HGT * 1.25, HGT * 1.25)

func _p(x: float, y: float) -> Vector3:
	return Vector3(_X(x), _Y(y), 0.0)

func _draw() -> void:
	for node in [curve_node, nodes_node, eval_node]:
		for c in node.get_children():
			c.queue_free()
	# Rango vertical a partir de los datos (con margen).
	var lo := INF
	var hi := -INF
	for y in ys:
		lo = minf(lo, float(y))
		hi = maxf(hi, float(y))
	if not free_data:
		for i in range(101):
			var v := f(lerpf(a, b, i / 100.0))
			if is_finite(v):
				lo = minf(lo, v)
				hi = maxf(hi, v)
	var pad := maxf(0.15 * (hi - lo), 0.1)
	ylo = lo - pad
	yhi = hi + pad
	var axis := glow_mat(Color(0.8, 0.85, 0.95), 1.0)
	curve_node.add_child(arrow(Vector3(-W - 0.1, _Y(0.0), 0), Vector3(W + 0.2, _Y(0.0), 0), 0.009, axis))
	for k in range(5):
		var xv := lerpf(a, b, k / 4.0)
		curve_node.add_child(label3d("%.2f" % xv, Vector3(_X(xv), _Y(0.0) - 0.16, 0.02), Color(0.7, 0.75, 0.85), 0.0026))
	var title_txt := "f(x) = " + f_expr.source if not free_data else "datos libres"
	curve_node.add_child(label3d("%s · %d nodos %s" % [title_txt, n, NODE_KINDS[node_kind].to_lower()], Vector3(-W + 1.3, HGT + 0.12, 0.02), Color(0.35, 0.9, 1.0), 0.0032))
	if not free_data:
		_curve(func(x): return f(x), Color(0.85, 0.88, 0.95), 0.01, 0.9)
	for m in range(METHODS.size()):
		if enabled[m]:
			_curve(func(x): return eval_method(m, x), COLORS[m], 0.018 if m != 1 else 0.012, 1.9)
	if show_partials and enabled[1]:
		for k in range(0, mini(n - 1, 8)):
			_curve(func(x): return newton_partial(k, x), Color(1.0, 0.8, 0.95).darkened(0.35), 0.005, 0.8)
	var nm := glow_mat(Color(1.0, 0.85, 0.3), 3.0)
	for i in range(n):
		var s := sphere(0.05 if i != _sel else 0.075, nm if i != _sel else glow_mat(Color(1, 1, 1), 4.0))
		s.position = _p(xs[i], ys[i]) + Vector3(0, 0, 0.02)
		nodes_node.add_child(s)
	_draw_eval()
	if err_plot:
		err_plot.queue_redraw()

func _curve(fn: Callable, col: Color, r: float, energy: float) -> void:
	var pts := PackedVector3Array()
	var cnt := 300
	for i in range(cnt + 1):
		var x := lerpf(a, b, float(i) / cnt)
		var y: float = fn.call(x)
		var inside := is_finite(y) and y > ylo - (yhi - ylo) * 0.12 and y < yhi + (yhi - ylo) * 0.12
		if not inside:
			if pts.size() >= 2:
				curve_node.add_child(tube(pts, r, glow_mat(col, energy), 6))
			pts = PackedVector3Array()
			continue
		pts.append(_p(x, y))
	if pts.size() >= 2:
		curve_node.add_child(tube(pts, r, glow_mat(col, energy), 6))

func _draw_eval() -> void:
	for c in eval_node.get_children():
		c.queue_free()
	var xe := clampf(x_eval, a, b)
	eval_node.add_child(rod(_p(xe, ylo), _p(xe, yhi), 0.004, glow_mat(Color(0.7, 0.75, 0.8), 0.7)))
	var pad := (yhi - ylo) * 0.12
	for m in range(METHODS.size()):
		if enabled[m]:
			var v := eval_method(m, xe)
			if not is_finite(v) or v < ylo - pad or v > yhi + pad:
				continue
			var s := sphere(0.035, glow_mat(COLORS[m], 3.0))
			s.position = _p(xe, v) + Vector3(0, 0, 0.03)
			eval_node.add_child(s)

# --- Interfaz ------------------------------------------------------------------------

func info() -> String:
	var t := "[font_size=12]"
	if not free_data:
		t += "[color=#8fa3b8]Método             │ ‖f − p‖∞ │ RMS │ p(x*) en x* = %.3f (f = %.6f)[/color]\n" % [x_eval, f(x_eval)]
	else:
		t += "[color=#8fa3b8]Método             │ p(x*) en x* = %.3f[/color]\n" % x_eval
	for m in range(METHODS.size()):
		if not enabled[m]:
			continue
		var sq := "[color=#%s]■[/color]" % COLORS[m].to_html(false)
		if free_data:
			t += "%s %s │ %+.6f\n" % [sq, SHORT[m], eval_method(m, x_eval)]
		else:
			var e: Dictionary = errs.get(m, {})
			t += "%s %s │ %s │ %s │ %+.6f\n" % [sq, SHORT[m], LabUI.sci(float(e.get("max", NAN)), 2), LabUI.sci(float(e.get("rms", NAN)), 2), eval_method(m, x_eval)]
	t += "[/font_size]Constante de Lebesgue de los nodos Λ = [color=#ffcc55]%s[/color]" % ("%.2f" % lebesgue if lebesgue < 1e4 else LabUI.sci(lebesgue, 1))
	if enabled[1] and n <= 8:
		var cs := []
		for k in range(n):
			cs.append("c%d = %s" % [k, LabUI.sci(float(_newton_c[k]), 3)])
		t += "\nNewton: " + " · ".join(cs)
	return t

func build_ui(p: VBoxContainer) -> void:
	LabUI.option(p, "Función:", FUNCS.map(func(q): return q["nombre"]), func_idx, func(i): load_function(i))
	_ui["f"] = LabUI.expr_field(p, "f(x) =", f_expr.source, ["x"], false, func(m):
		f_expr = m
		if free_data:
			func_idx = 0
		rebuild()
		lab._update_info(false))
	var r := LabUI.row(p)
	_ui["a"] = LabUI.spin(r, "a", -20, 20, 0.1, a, func(v):
		if v < b:
			a = v
			rebuild())
	_ui["a"].set_meta("lab_param", "intervalo a")
	_ui["b"] = LabUI.spin(r, "b", -20, 20, 0.1, b, func(v):
		if v > a:
			b = v
			rebuild())
	_ui["b"].set_meta("lab_param", "intervalo b")
	LabUI.option(p, "Nodos:", NODE_KINDS, node_kind, func(i):
		node_kind = i
		free_ys.clear()
		rebuild()
		lab._update_info(false))
	LabUI.slider(p, "Número de nodos n", 2, 40, 1, n, func(v):
		n = int(v)
		rebuild()
		lab._update_info(false), "%.0f")
	LabUI.slider(p, "x* (evaluar)", -1.0, 1.0, 0.005, x_eval, func(v):
		x_eval = lerpf(a, b, (v + 1.0) * 0.5)
		_draw_eval()
		lab._update_info(false), "%.3f").set_meta("lab_param", "x* (−1 = a, 1 = b)")
	LabUI.section(p, "Métodos")
	for m in range(METHODS.size()):
		var mm := m
		var chk := LabUI.check(p, METHODS[m], enabled[m], func(v):
			enabled[mm] = v
			if _desc and v:
				_desc.text = DESCS[mm]
			_draw()
			lab._update_info(false))
		chk.add_theme_color_override("font_color", COLORS[m].lerp(Color.WHITE, 0.25))
		chk.add_theme_color_override("font_pressed_color", COLORS[m].lerp(Color.WHITE, 0.25))
	LabUI.slider(p, "Grado m (mínimos cuadrados)", 0, 15, 1, deg_ls, func(v):
		deg_ls = int(v)
		rebuild()
		lab._update_info(false), "%.0f")
	LabUI.check(p, "Newton: polinomios parciales p₀…p₇", show_partials, func(v):
		show_partials = v
		_draw())
	var rr := LabUI.row(p)
	LabUI.button(rr, "Solo polinómicos", func(): _enable_only([0, 10, 12]))
	LabUI.button(rr, "Solo splines", func(): _enable_only([4, 5, 6, 8, 9]))
	LabUI.button(rr, "Todos", func(): _enable_only(range(METHODS.size())))
	LabUI.section(p, "Error log₁₀ |f(x) − p(x)| a lo largo de [a, b]")
	err_plot = ErrPlot.new()
	err_plot.module = self
	err_plot.custom_minimum_size = Vector2(260, 130)
	p.add_child(err_plot)
	_desc = LabUI.note(p, DESCS[0])
	LabUI.note(p, "Prueba Runge con 15 nodos equiespaciados y luego Chebyshev; o «Datos libres» con los splines frente a PCHIP y Akima (sin sobreoscilación).")

func _enable_only(list) -> void:
	for m in range(METHODS.size()):
		enabled[m] = m in list
	# Sincroniza las casillas sin reconstruir el panel.
	for c in lab.params_box.find_children("*", "CheckBox", true, false):
		var cb := c as CheckBox
		var idx := METHODS.find(cb.text)
		if idx >= 0:
			cb.set_pressed_no_signal(enabled[idx])
	_draw()
	lab._update_info(false)

func load_function(i: int) -> void:
	func_idx = clampi(i, 0, FUNCS.size() - 1)
	var q: Dictionary = FUNCS[func_idx]
	if str(q["f"]) != "":
		f_expr = MathExpr.parse(q["f"], ["x"])
		if _ui.has("f"):
			(_ui["f"] as LineEdit).text = q["f"]
	a = q["a"]
	b = q["b"]
	if _ui.has("a"):
		(_ui["a"] as SpinBox).set_value_no_signal(a)
		(_ui["b"] as SpinBox).set_value_no_signal(b)
	x_eval = clampf(x_eval, a, b)
	rebuild()
	if lab:
		lab._update_info(false)

func pick(origin: Vector3, dir: Vector3):
	if absf(dir.z) < 1e-6:
		return null
	var t := -origin.z / dir.z
	if t < 0.0:
		return null
	var pt := origin + dir * t
	if absf(pt.x) > W or absf(pt.y - LIFT) > HGT * 1.3:
		return null
	return pt

func _xw(wx: float) -> float:
	return wx / (2.0 * W / (b - a)) + (a + b) * 0.5

func _yw(wy: float) -> float:
	return lerpf(ylo, yhi, (wy + HGT) / (2.0 * HGT))

## (x, y) en las coordenadas de la gráfica: la API los lleva al tablero.
func api_points(x: float, y: float) -> Array:
	return [to_global(Vector3(_X(x), _Y(y), 0.0))]

func hover_text(hit: Vector3) -> String:
	var lp := to_local(hit)
	var x := _xw(lp.x)
	var t := "x = %.4f" % x
	if not free_data:
		t += "   f(x) = %.5f" % f(x)
	var k := 0
	for m in range(METHODS.size()):
		if enabled[m] and k < 5:
			t += "\n%s: %.5f" % [SHORT[m], eval_method(m, x)]
			k += 1
	return t

func perturb(hit: Vector3, first: bool) -> void:
	var lp := to_local(hit)
	var x := _xw(lp.x)
	if free_data:
		if first:
			_sel = -1
			var bd := INF
			for i in range(n):
				var d := absf(_X(xs[i]) - lp.x)
				if d < bd and d < 0.35:
					bd = d
					_sel = i
		if _sel >= 0:
			free_ys[_sel] = _yw(lp.y)
			ys = free_ys.duplicate()
			rebuild()
		return
	if first:
		x_eval = clampf(x, a, b)
		_draw_eval()

func critical_points() -> Array:
	var out := []
	for m in range(METHODS.size()):
		if enabled[m] and errs.has(m):
			var e: Dictionary = errs[m]
			var xm: float = e["xmax"]
			out.append({"pos": to_global(_p(xm, eval_method(m, xm))), "nombre": "Error máximo de %s: %s en x = %.3f" % [SHORT[m], LabUI.sci(float(e["max"]), 2), xm], "dist": 2.2})
	return out

func demo(extra: Array) -> void:
	if "datos" in extra:
		load_function(FUNCS.size() - 1)
		_enable_only([0, 4, 8, 9])
		return
	n = 13
	rebuild()
	_enable_only([0, 4, 8, 10])

class ErrPlot extends Control:
	var module
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.03, 0.05, 0.08, 0.9))
		for k in range(0, 17, 4):
			var y := r.size.y * float(k) / 16.0
			draw_line(Vector2(0, y), Vector2(r.size.x, y), Color(0.2, 0.3, 0.4, 0.5))
		if module == null or module.free_data:
			draw_string(ThemeDB.fallback_font, Vector2(8, 20), "sin función de referencia", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.7, 0.8))
			return
		for m in range(module.METHODS.size()):
			if not module.enabled[m]:
				continue
			var pts := PackedVector2Array()
			var cnt := 200
			for i in range(cnt + 1):
				var x: float = lerpf(module.a, module.b, float(i) / cnt)
				var e := absf(float(module.f(x)) - float(module.eval_method(m, x)))
				var le: float = log(maxf(e, 1e-16)) / log(10.0) if is_finite(e) else 2.0
				pts.append(Vector2(r.size.x * float(i) / cnt, r.size.y * clampf((2.0 - le) / 18.0, 0.0, 1.0)))
			draw_polyline(pts, module.COLORS[m], 1.6, true)
		draw_string(ThemeDB.fallback_font, Vector2(4, 12), "10²", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.7, 0.8))
		draw_string(ThemeDB.fallback_font, Vector2(4, r.size.y - 4), "10⁻¹⁶", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.7, 0.8))
