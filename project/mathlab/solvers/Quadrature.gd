class_name Quadrature
extends RefCounted
## Quadrature — Cuadraturas 1D ∫ₐᵇ f(x) dx para el Laboratorio.
##
## f es un Callable(float) -> float. Cada método devuelve un Dictionary con
##   valor   aproximación de la integral
##   evals   evaluaciones de f
##   nodos   [[x, peso], …] de la suma Σ wᵢ f(xᵢ) (para dibujar)
## y, según el método, «paneles» (subintervalos con sus puntos), «tabla»
## (Romberg), «intervalos» (adaptativos), «error_est» o «sigma» (Monte Carlo).
##
## Intervalos infinitos: Gauss–Laguerre, Gauss–Hermite, tanh-sinh (con sus
## variantes exp-sinh y sinh-sinh) y Gauss–Kronrod adaptativa (cambio de variable).

# --- Utilidades --------------------------------------------------------------------

## Envuelve f para contar evaluaciones: {"f": Callable, "n": [contador]}.
static func counted(f: Callable) -> Dictionary:
	var n := [0]
	var g := func(x: float) -> float:
		n[0] += 1
		return float(f.call(x))
	return {"f": g, "n": n}

static func _res(valor: float, evals: int, nodos: Array, extra: Dictionary = {}) -> Dictionary:
	var d := {"valor": valor, "evals": evals, "nodos": nodos}
	d.merge(extra)
	return d

# --- Newton–Cotes compuestas ----------------------------------------------------------

## Fórmula compuesta genérica: n subintervalos agrupados en paneles de «pts» puntos
## con pesos «w» (sobre h), cada panel abarca (pts − 1) subintervalos.
static func _newton_cotes(f: Callable, a: float, b: float, n: int, w: Array, scale: float) -> Dictionary:
	var c := counted(f)
	var m := w.size() - 1
	n = maxi(m, n - n % m)
	var h := (b - a) / n
	var s := 0.0
	var nodos := []
	var paneles := []
	var cache := {}
	for p in range(n / m):
		var pts := []
		for k in range(m + 1):
			var i := p * m + k
			var x := a + i * h
			if not cache.has(i):
				cache[i] = c["f"].call(x)
			var fx: float = cache[i]
			s += float(w[k]) * fx
			pts.append([x, fx])
		paneles.append(pts)
	var tot := {}
	for p in range(n / m):
		for k in range(m + 1):
			var i2 := p * m + k
			tot[i2] = float(tot.get(i2, 0.0)) + float(w[k]) * h * scale
	for i3 in tot:
		nodos.append([a + int(i3) * h, tot[i3]])
	return _res(s * h * scale, c["n"][0], nodos, {"paneles": paneles, "n": n})

static func rect_left(f: Callable, a: float, b: float, n: int) -> Dictionary:
	var c := counted(f)
	var h := (b - a) / n
	var s := 0.0
	var nodos := []
	var paneles := []
	for i in range(n):
		var x := a + i * h
		var fx: float = c["f"].call(x)
		s += fx
		nodos.append([x, h])
		paneles.append([[x, fx], [x + h, fx]])
	return _res(s * h, c["n"][0], nodos, {"paneles": paneles, "tipo": "rect", "n": n})

static func rect_right(f: Callable, a: float, b: float, n: int) -> Dictionary:
	var c := counted(f)
	var h := (b - a) / n
	var s := 0.0
	var nodos := []
	var paneles := []
	for i in range(n):
		var x := a + (i + 1) * h
		var fx: float = c["f"].call(x)
		s += fx
		nodos.append([x, h])
		paneles.append([[x - h, fx], [x, fx]])
	return _res(s * h, c["n"][0], nodos, {"paneles": paneles, "tipo": "rect", "n": n})

static func midpoint(f: Callable, a: float, b: float, n: int) -> Dictionary:
	var c := counted(f)
	var h := (b - a) / n
	var s := 0.0
	var nodos := []
	var paneles := []
	for i in range(n):
		var x := a + (i + 0.5) * h
		var fx: float = c["f"].call(x)
		s += fx
		nodos.append([x, h])
		paneles.append([[x - 0.5 * h, fx], [x + 0.5 * h, fx]])
	return _res(s * h, c["n"][0], nodos, {"paneles": paneles, "tipo": "rect", "n": n})

static func trapezoid(f: Callable, a: float, b: float, n: int) -> Dictionary:
	return _newton_cotes(f, a, b, n, [1.0, 1.0], 0.5)

static func simpson(f: Callable, a: float, b: float, n: int) -> Dictionary:
	return _newton_cotes(f, a, b, n + n % 2, [1.0, 4.0, 1.0], 1.0 / 3.0)

static func simpson38(f: Callable, a: float, b: float, n: int) -> Dictionary:
	return _newton_cotes(f, a, b, n + (3 - n % 3) % 3, [1.0, 3.0, 3.0, 1.0], 3.0 / 8.0)

static func boole(f: Callable, a: float, b: float, n: int) -> Dictionary:
	return _newton_cotes(f, a, b, n + (4 - n % 4) % 4, [7.0, 32.0, 12.0, 32.0, 7.0], 2.0 / 45.0)

## Romberg: trapecios con h, h/2, h/4… y extrapolación de Richardson.
## levels niveles (el más fino tiene 2^(levels−1) subintervalos).
static func romberg(f: Callable, a: float, b: float, levels: int) -> Dictionary:
	var c := counted(f)
	levels = clampi(levels, 1, 20)
	var R := []
	var h := b - a
	var fa: float = c["f"].call(a)
	var fb: float = c["f"].call(b)
	R.append([0.5 * h * (fa + fb)])
	var nodos := [[a, 0.0], [b, 0.0]]
	for k in range(1, levels):
		h *= 0.5
		var s := 0.0
		var m := 1 << (k - 1)
		for i in range(m):
			var x := a + (2 * i + 1) * h
			s += float(c["f"].call(x))
			nodos.append([x, 0.0])
		var row := [0.5 * float(R[k - 1][0]) + h * s]
		for j in range(1, k + 1):
			var p := pow(4.0, j)
			row.append(float(row[j - 1]) + (float(row[j - 1]) - float(R[k - 1][j - 1])) / (p - 1.0))
		R.append(row)
	var last: Array = R[R.size() - 1]
	return _res(float(last[last.size() - 1]), c["n"][0], nodos, {"tabla": R, "n": 1 << (levels - 1)})

# --- Nodos y pesos de Gauss --------------------------------------------------------------

static var _cache := {}

## Gauss–Legendre en [−1, 1] (Newton sobre Pₙ con la recurrencia de Bonnet).
static func gauss_legendre_nodes(n: int) -> Array:
	var key := "L%d" % n
	if _cache.has(key):
		return _cache[key]
	var xs := []
	var ws := []
	xs.resize(n)
	ws.resize(n)
	for i in range(1, (n + 1) / 2 + 1):
		var z := cos(PI * (i - 0.25) / (n + 0.5))
		var pp := 0.0
		for it in range(100):
			var p1 := 1.0
			var p2 := 0.0
			for j in range(1, n + 1):
				var p3 := p2
				p2 = p1
				p1 = ((2.0 * j - 1.0) * z * p2 - (j - 1.0) * p3) / j
			pp = n * (z * p1 - p2) / (z * z - 1.0)
			var z1 := z
			z = z1 - p1 / pp
			if absf(z - z1) < 1e-15:
				break
		xs[i - 1] = -z
		xs[n - i] = z
		ws[i - 1] = 2.0 / ((1.0 - z * z) * pp * pp)
		ws[n - i] = ws[i - 1]
	var r := [xs, ws]
	_cache[key] = r
	return r

## Legendre Pₙ y su derivada en x.
static func _legendre(n: int, x: float) -> Array:
	var p0 := 1.0
	var p1 := x
	if n == 0:
		return [1.0, 0.0]
	for k in range(2, n + 1):
		var p2 := ((2.0 * k - 1.0) * x * p1 - (k - 1.0) * p0) / k
		p0 = p1
		p1 = p2
	var dp := n * (x * p1 - p0) / (x * x - 1.0) if absf(x) < 1.0 else 0.5 * n * (n + 1.0) * pow(signf(x), n + 1)
	return [p1, dp]

## Gauss–Lobatto en [−1, 1]: extremos y raíces de P′ₙ₋₁; wᵢ = 2 / (n(n−1)Pₙ₋₁(xᵢ)²).
static func gauss_lobatto_nodes(n: int) -> Array:
	n = maxi(2, n)
	var key := "Lo%d" % n
	if _cache.has(key):
		return _cache[key]
	var N := n - 1
	var xs := []
	for i in range(n):
		# Arranque en los puntos de Chebyshev–Gauss–Lobatto y Newton sobre (1 − x²)P′_N.
		var z := -cos(PI * i / N)
		if i > 0 and i < N:
			for it in range(100):
				var L := _legendre(N, z)
				# f = P′_N ; f′ = (2z P′_N − N(N+1) P_N)/(1 − z²)
				var d2: float = (2.0 * z * float(L[1]) - N * (N + 1.0) * float(L[0])) / (1.0 - z * z)
				var dz: float = L[1] / d2
				z -= dz
				if absf(dz) < 1e-15:
					break
		xs.append(z)
	var ws := []
	for z in xs:
		var P: float = _legendre(N, z)[0]
		ws.append(2.0 / (N * (N + 1.0) * P * P))
	var r := [xs, ws]
	_cache[key] = r
	return r

## Gauss–Laguerre (peso e^(−x) en [0, ∞)), Numerical Recipes gaulag con α = 0.
static func gauss_laguerre_nodes(n: int) -> Array:
	var key := "La%d" % n
	if _cache.has(key):
		return _cache[key]
	var xs := []
	var ws := []
	xs.resize(n)
	ws.resize(n)
	var z := 0.0
	for i in range(n):
		if i == 0:
			z = 3.0 / (1.0 + 2.4 * n)
		elif i == 1:
			z += 15.0 / (1.0 + 2.5 * n)
		else:
			var ai := float(i - 1)
			z += ((1.0 + 2.55 * ai) / (1.9 * ai)) * (z - float(xs[i - 2]))
		var pp := 0.0
		var p2 := 0.0
		for it in range(200):
			var p1 := 1.0
			p2 = 0.0
			for j in range(1, n + 1):
				var p3 := p2
				p2 = p1
				p1 = ((2.0 * j - 1.0 - z) * p2 - (j - 1.0) * p3) / j
			pp = (n * p1 - n * p2) / z
			var z1 := z
			z = z1 - p1 / pp
			if absf(z - z1) <= 1e-14 * maxf(1.0, absf(z)):
				break
		xs[i] = z
		ws[i] = -1.0 / (pp * n * p2)
	var r := [xs, ws]
	_cache[key] = r
	return r

## Gauss–Hermite (peso e^(−x²) en ℝ), Numerical Recipes gauher.
static func gauss_hermite_nodes(n: int) -> Array:
	var key := "H%d" % n
	if _cache.has(key):
		return _cache[key]
	var xs := []
	var ws := []
	xs.resize(n)
	ws.resize(n)
	var PIM4 := 0.7511255444649425
	var z := 0.0
	for i in range(1, (n + 1) / 2 + 1):
		if i == 1:
			z = sqrt(2.0 * n + 1.0) - 1.85575 * pow(2.0 * n + 1.0, -0.16667)
		elif i == 2:
			z -= 1.14 * pow(float(n), 0.426) / z
		elif i == 3:
			z = 1.86 * z - 0.86 * float(xs[0])
		elif i == 4:
			z = 1.91 * z - 0.91 * float(xs[1])
		else:
			z = 2.0 * z - float(xs[i - 3])
		var pp := 0.0
		for it in range(200):
			var p1 := PIM4
			var p2 := 0.0
			for j in range(1, n + 1):
				var p3 := p2
				p2 = p1
				p1 = z * sqrt(2.0 / j) * p2 - sqrt((j - 1.0) / j) * p3
			pp = sqrt(2.0 * n) * p2
			var z1 := z
			z = z1 - p1 / pp
			if absf(z - z1) <= 1e-14:
				break
		xs[i - 1] = z
		xs[n - i] = -z
		ws[i - 1] = 2.0 / (pp * pp)
		ws[n - i] = ws[i - 1]
	var r := [xs, ws]
	_cache[key] = r
	return r

## Regla de nodos fijos en [−1, 1] aplicada en m subintervalos de [a, b].
static func _fixed_rule(f: Callable, a: float, b: float, rule: Array, m: int) -> Dictionary:
	var c := counted(f)
	var xs: Array = rule[0]
	var ws: Array = rule[1]
	var s := 0.0
	var nodos := []
	var hw := (b - a) / m
	var cache := {}
	for k in range(m):
		var lo := a + k * hw
		var mid := lo + 0.5 * hw
		for i in range(xs.size()):
			var x: float = mid + 0.5 * hw * float(xs[i])
			var w: float = 0.5 * hw * float(ws[i])
			var key := snappedf(x, 1e-13)
			var fx: float
			if cache.has(key):
				fx = cache[key]
			else:
				fx = c["f"].call(x)
				cache[key] = fx
			s += w * fx
			nodos.append([x, w])
	return _res(s, c["n"][0], nodos, {"n": xs.size() * m})

static func gauss_legendre(f: Callable, a: float, b: float, npts: int, m: int = 1) -> Dictionary:
	return _fixed_rule(f, a, b, gauss_legendre_nodes(clampi(npts, 1, 100)), maxi(1, m))

static func gauss_lobatto(f: Callable, a: float, b: float, npts: int, m: int = 1) -> Dictionary:
	return _fixed_rule(f, a, b, gauss_lobatto_nodes(clampi(npts, 2, 100)), maxi(1, m))

## Clenshaw–Curtis con n + 1 puntos de Chebyshev (pesos de Waldvogel en O(n²)).
static func clenshaw_curtis_nodes(n: int) -> Array:
	n = maxi(2, n)
	var key := "CC%d" % n
	if _cache.has(key):
		return _cache[key]
	var xs := []
	var ws := []
	for k in range(n + 1):
		var th := PI * k / n
		xs.append(-cos(th))
		var s := 0.0
		for j in range(1, n / 2 + 1):
			var bj := 1.0 if 2 * j == n else 2.0
			s += bj / (4.0 * j * j - 1.0) * cos(2.0 * j * th)
		var ck := 1.0 if k == 0 or k == n else 2.0
		ws.append(ck / n * (1.0 - s))
	var r := [xs, ws]
	_cache[key] = r
	return r

static func clenshaw_curtis(f: Callable, a: float, b: float, n: int) -> Dictionary:
	return _fixed_rule(f, a, b, clenshaw_curtis_nodes(n), 1)

# --- Adaptativas ---------------------------------------------------------------------------

const GK_X := [0.991455371120812639206854697526329, 0.949107912342758524526189684047851, 0.864864423359769072789712788640926,
	0.741531185599394439863864773280788, 0.586087235467691130294144845693013, 0.405845151377397166906606412076961,
	0.207784955007898467600689403773245, 0.0]
const GK_WK := [0.022935322010529224963732008058970, 0.063092092629978553290700663189204, 0.104790010322250183839876322541518,
	0.140653259715525918745189590510238, 0.169004726639267902826583426598550, 0.190350578064785409913256402421014,
	0.204432940075298892414161999234649, 0.209482141084727828012999174891714]
const GK_WG := [0.129484966168869693270611432679082, 0.279705391489276667901467771423780, 0.381830050505118944950369775488975,
	0.417959183673469387755102040816327]

## Gauss–Kronrod 7–15 en [lo, hi]: [K15, |K15 − G7|, nodos].
static func _gk15(g: Callable, lo: float, hi: float) -> Array:
	var c := 0.5 * (lo + hi)
	var hw := 0.5 * (hi - lo)
	var fc: float = g.call(c)
	var k := float(GK_WK[7]) * fc
	var gs := float(GK_WG[3]) * fc
	var nodos := [[c, hw * float(GK_WK[7])]]
	for i in range(7):
		var dx := hw * float(GK_X[i])
		var f1: float = g.call(c - dx)
		var f2: float = g.call(c + dx)
		k += float(GK_WK[i]) * (f1 + f2)
		if i % 2 == 1:
			gs += float(GK_WG[i / 2]) * (f1 + f2)
		nodos.append([c - dx, hw * float(GK_WK[i])])
		nodos.append([c + dx, hw * float(GK_WK[i])])
	return [k * hw, absf((k - gs) * hw), nodos]

## Cambio de variable para intervalos infinitos: devuelve [g(t), t_lo, t_hi, x(t)].
static func _map_infinite(f: Callable, a: float, b: float) -> Array:
	if is_inf(a) and is_inf(b):
		var g := func(t: float) -> float:
			var x := t / (1.0 - t * t)
			return float(f.call(x)) * (1.0 + t * t) / pow(1.0 - t * t, 2.0)
		return [g, -1.0, 1.0, func(t: float) -> float: return t / (1.0 - t * t)]
	if is_inf(b):
		var g2 := func(t: float) -> float:
			return float(f.call(a + t / (1.0 - t))) / pow(1.0 - t, 2.0)
		return [g2, 0.0, 1.0, func(t: float) -> float: return a + t / (1.0 - t)]
	if is_inf(a):
		var g3 := func(t: float) -> float:
			return float(f.call(b - t / (1.0 - t))) / pow(1.0 - t, 2.0)
		return [g3, 0.0, 1.0, func(t: float) -> float: return b - t / (1.0 - t)]
	return [f, a, b, func(t: float) -> float: return t]

## Gauss–Kronrod 7–15 adaptativa (como QUADPACK QAG): parte siempre el
## subintervalo con más error estimado hasta que el total baja de la tolerancia.
static func gauss_kronrod(f: Callable, a: float, b: float, tol: float, max_sub: int = 400) -> Dictionary:
	var c := counted(f)
	var mp := _map_infinite(c["f"], a, b)
	var g: Callable = mp[0]
	var xmap: Callable = mp[3]
	var parts := []
	var r := _gk15(g, mp[1], mp[2])
	parts.append([mp[1], mp[2], r[0], r[1], r[2]])
	var total: float = r[0]
	var err: float = r[1]
	while err > maxf(tol, tol * absf(total)) and parts.size() < max_sub:
		var worst := 0
		for i in range(parts.size()):
			if float(parts[i][3]) > float(parts[worst][3]):
				worst = i
		var p: Array = parts[worst]
		var m := 0.5 * (float(p[0]) + float(p[1]))
		var r1 := _gk15(g, p[0], m)
		var r2 := _gk15(g, m, p[1])
		parts[worst] = [p[0], m, r1[0], r1[1], r1[2]]
		parts.append([m, p[1], r2[0], r2[1], r2[2]])
		total = 0.0
		err = 0.0
		for q in parts:
			total += float(q[2])
			err += float(q[3])
	var intervalos := []
	var nodos := []
	for q in parts:
		intervalos.append([xmap.call(q[0]), xmap.call(q[1])])
		for nd in q[4]:
			nodos.append([xmap.call(nd[0]), nd[1]])
	intervalos.sort_custom(func(u, v): return u[0] < v[0])
	return _res(total, c["n"][0], nodos, {"intervalos": intervalos, "error_est": err})

## Simpson adaptativa recursiva con la corrección de Richardson (S₂ + (S₂ − S₁)/15).
static func simpson_adaptive(f: Callable, a: float, b: float, tol: float, max_depth: int = 40) -> Dictionary:
	var c := counted(f)
	var g: Callable = c["f"]
	var fa: float = g.call(a)
	var fb: float = g.call(b)
	var m := 0.5 * (a + b)
	var fm: float = g.call(m)
	var whole := (b - a) / 6.0 * (fa + 4.0 * fm + fb)
	var intervalos := []
	var paneles := []
	var val := _asr(g, a, b, fa, fm, fb, whole, tol, max_depth, intervalos, paneles)
	intervalos.sort_custom(func(u, v): return u[0] < v[0])
	paneles.sort_custom(func(u, v): return u[0][0] < v[0][0])
	var nodos := []
	for p in paneles:
		for q in p:
			nodos.append([q[0], 0.0])
	return _res(val, c["n"][0], nodos, {"intervalos": intervalos, "paneles": paneles})

static func _asr(g: Callable, a: float, b: float, fa: float, fm: float, fb: float, whole: float, tol: float, depth: int, iv: Array, pn: Array) -> float:
	var m := 0.5 * (a + b)
	var lm := 0.5 * (a + m)
	var rm := 0.5 * (m + b)
	var flm: float = g.call(lm)
	var frm: float = g.call(rm)
	var left := (m - a) / 6.0 * (fa + 4.0 * flm + fm)
	var right := (b - m) / 6.0 * (fm + 4.0 * frm + fb)
	var delta := left + right - whole
	if depth <= 0 or absf(delta) <= 15.0 * tol or not is_finite(delta):
		iv.append([a, b])
		pn.append([[a, fa], [lm, flm], [m, fm]])
		pn.append([[m, fm], [rm, frm], [b, fb]])
		return left + right + delta / 15.0
	return _asr(g, a, m, fa, flm, fm, left, tol * 0.5, depth - 1, iv, pn) + _asr(g, m, b, fm, frm, fb, right, tol * 0.5, depth - 1, iv, pn)

# --- Doble exponencial ---------------------------------------------------------------------

## Tanh-sinh: x = φ(t) concentra los nodos en los extremos, donde suelen estar las
## singularidades; la regla del trapecio en t converge de forma doblemente
## exponencial. Intervalos infinitos: exp-sinh ([a, ∞)) y sinh-sinh (ℝ). Se
## reduce h a la mitad hasta que dos niveles coinciden (o max_level).
static func tanh_sinh(f: Callable, a: float, b: float, tol: float = 1e-12, max_level: int = 8) -> Dictionary:
	var c := counted(f)
	var g: Callable = c["f"]
	var kind := "tanh"
	if is_inf(a) and is_inf(b):
		kind = "sinh"
	elif is_inf(b) or is_inf(a):
		kind = "exp"
	var reflect := kind == "exp" and is_inf(a)   # ∫_{−∞}^b f(x) dx = ∫_0^∞ f(b − u) du
	var base := b if reflect else a
	var tmax := 4.0 if kind == "tanh" else (4.5 if kind == "exp" else 5.0)
	var h := 1.0
	var sum := 0.0
	var prev := NAN
	var total := 0.0
	var nodos := []
	var level := 0
	while true:
		# Nivel 0: todos los t = k·h; después, solo los nuevos (k impar).
		var K := int(floor(tmax / h))
		for k in range(-K, K + 1):
			if level > 0 and k % 2 == 0:
				continue
			var q := _de_point(kind, k * h, a, b)
			var x: float = q[0]
			var w: float = q[1]
			if w == 0.0 or not is_finite(x) or not is_finite(w):
				continue
			if kind == "exp":
				x = base - x if reflect else base + x
			elif kind == "tanh" and (x <= a or x >= b):
				continue
			var fx: float = g.call(x)
			if not is_finite(fx):
				continue
			sum += w * fx
			nodos.append([x, w * h])
		total = sum * h
		if (level >= 2 and absf(total - prev) <= maxf(tol, tol * absf(total))) or level >= max_level:
			break
		prev = total
		h *= 0.5
		level += 1
	return _res(total, c["n"][0], nodos, {"niveles": level + 1, "variante": kind})

## Nodo y peso de la transformación doble exponencial en t (para exp-sinh, el
## desplazamiento desde el extremo finito).
static func _de_point(kind: String, t: float, lo: float, hi: float) -> Array:
	var u := 0.5 * PI * sinh(t)
	match kind:
		"tanh":
			var ch := cosh(u)
			if ch > 1e150:
				return [NAN, 0.0]
			# Distancia al extremo más cercano sin cancelación: half·(1 − tanh|u|) = half·2/(e^{2|u|} + 1),
			# así un nodo a 10⁻³⁰ de un extremo singular (ln x en 0) se evalúa bien.
			var half := 0.5 * (hi - lo)
			var dist := half * 2.0 / (exp(2.0 * absf(u)) + 1.0)
			var x := (hi - dist) if u >= 0.0 else (lo + dist)
			return [x, half * 0.5 * PI * cosh(t) / (ch * ch)]
		"exp":
			var e := exp(u)
			return [e, 0.5 * PI * cosh(t) * e]
		_:
			return [sinh(u), 0.5 * PI * cosh(t) * cosh(u)]

# --- Aleatorias --------------------------------------------------------------------------------

## Monte Carlo: media de f en N puntos uniformes × (b − a); σ estimada = error típico.
static func monte_carlo(f: Callable, a: float, b: float, N: int, seed: int = 12345) -> Dictionary:
	var c := counted(f)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var s := 0.0
	var s2 := 0.0
	var nodos := []
	for i in range(N):
		var x := a + (b - a) * rng.randf()
		var fx: float = c["f"].call(x)
		s += fx
		s2 += fx * fx
		if i < 600:
			nodos.append([x, fx])
	var mean := s / N
	var var_ := maxf(0.0, s2 / N - mean * mean)
	return _res(mean * (b - a), c["n"][0], nodos, {"sigma": (b - a) * sqrt(var_ / N), "media": mean})

## Cuasi-Monte Carlo con la sucesión de van der Corput (base 2): puntos de baja
## discrepancia, error ≈ O(log N / N) para f de variación acotada.
static func quasi_monte_carlo(f: Callable, a: float, b: float, N: int) -> Dictionary:
	var c := counted(f)
	var s := 0.0
	var nodos := []
	for i in range(1, N + 1):
		var x := a + (b - a) * van_der_corput(i, 2)
		var fx: float = c["f"].call(x)
		s += fx
		if i <= 600:
			nodos.append([x, fx])
	return _res(s / N * (b - a), c["n"][0], nodos, {"media": s / N})

static func van_der_corput(i: int, base: int) -> float:
	var q := 0.0
	var bk := 1.0 / base
	while i > 0:
		q += (i % base) * bk
		i /= base
		bk /= base
	return q

# --- Intervalos infinitos con peso ----------------------------------------------------------

## Gauss–Laguerre para [a, ∞) (o (−∞, b]): ∫ f = Σ wᵢ e^{xᵢ} f(a + xᵢ).
static func gauss_laguerre(f: Callable, a: float, b: float, npts: int) -> Dictionary:
	var c := counted(f)
	var rule := gauss_laguerre_nodes(clampi(npts, 1, 60))
	var s := 0.0
	var nodos := []
	var left := is_inf(a) and not is_inf(b)
	for i in range((rule[0] as Array).size()):
		var t: float = rule[0][i]
		var w: float = float(rule[1][i]) * exp(t)
		var x := b - t if left else a + t
		s += w * float(c["f"].call(x))
		nodos.append([x, w])
	return _res(s, c["n"][0], nodos, {"n": npts})

## Gauss–Hermite para (−∞, ∞): ∫ f = Σ wᵢ e^{xᵢ²} f(xᵢ).
static func gauss_hermite(f: Callable, npts: int) -> Dictionary:
	var c := counted(f)
	var rule := gauss_hermite_nodes(clampi(npts, 1, 60))
	var s := 0.0
	var nodos := []
	for i in range((rule[0] as Array).size()):
		var x: float = rule[0][i]
		var w: float = float(rule[1][i]) * exp(x * x)
		s += w * float(c["f"].call(x))
		nodos.append([x, w])
	return _res(s, c["n"][0], nodos, {"n": npts})
