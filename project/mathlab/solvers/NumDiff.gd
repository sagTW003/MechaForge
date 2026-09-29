class_name NumDiff
extends RefCounted
## NumDiff — Derivación numérica 1D (primera y segunda derivada) para el Laboratorio.
##
## f es un Callable(float) -> float. Cada método devuelve {"valor", "evals",
## "puntos": [[x, f(x)], …]} y, según el método, «tabla» (Richardson).
## El paso complejo, la diferenciación automática y la derivada simbólica
## necesitan la fórmula y están en MathExpr (eval_cd, eval_jet, derivative).

## Plantillas de diferencias: [desplazamientos en h, coeficientes]; f′ ≈ Σ cᵢ f(x + kᵢh) / h.
const D1 := {
	"adelante": [[0, 1], [-1.0, 1.0]],
	"atras": [[-1, 0], [-1.0, 1.0]],
	"centrada": [[-1, 1], [-0.5, 0.5]],
	"adelante3": [[0, 1, 2], [-1.5, 2.0, -0.5]],
	"atras3": [[-2, -1, 0], [0.5, -2.0, 1.5]],
	"centrada5": [[-2, -1, 1, 2], [1.0 / 12.0, -2.0 / 3.0, 2.0 / 3.0, -1.0 / 12.0]],
	"centrada7": [[-3, -2, -1, 1, 2, 3], [-1.0 / 60.0, 3.0 / 20.0, -0.75, 0.75, -3.0 / 20.0, 1.0 / 60.0]],
}
## f″ ≈ Σ cᵢ f(x + kᵢh) / h².
const D2 := {
	"adelante": [[0, 1, 2], [1.0, -2.0, 1.0]],
	"atras": [[-2, -1, 0], [1.0, -2.0, 1.0]],
	"centrada": [[-1, 0, 1], [1.0, -2.0, 1.0]],
	"adelante3": [[0, 1, 2, 3], [2.0, -5.0, 4.0, -1.0]],
	"atras3": [[-3, -2, -1, 0], [-1.0, 4.0, -5.0, 2.0]],
	"centrada5": [[-2, -1, 0, 1, 2], [-1.0 / 12.0, 4.0 / 3.0, -2.5, 4.0 / 3.0, -1.0 / 12.0]],
	"centrada7": [[-3, -2, -1, 0, 1, 2, 3], [1.0 / 90.0, -3.0 / 20.0, 1.5, -49.0 / 18.0, 1.5, -3.0 / 20.0, 1.0 / 90.0]],
}

## Diferencia finita con la plantilla «name» (order 1: f′, 2: f″).
static func stencil(f: Callable, x: float, h: float, name: String, order: int = 1) -> Dictionary:
	var st: Array = (D1 if order == 1 else D2)[name]
	var ks: Array = st[0]
	var cs: Array = st[1]
	var s := 0.0
	var pts := []
	for i in range(ks.size()):
		var xi := x + float(ks[i]) * h
		var fx: float = f.call(xi)
		s += float(cs[i]) * fx
		pts.append([xi, fx])
	return {"valor": s / pow(h, order), "evals": pts.size(), "puntos": pts}

## Extrapolación de Richardson sobre la diferencia centrada con h, h/2, h/4…:
## R[k][j] = R[k][j−1] + (R[k][j−1] − R[k−1][j−1]) / (4ʲ − 1). Orden 2·levels.
static func richardson(f: Callable, x: float, h: float, levels: int, order: int = 1) -> Dictionary:
	levels = clampi(levels, 1, 10)
	var R := []
	var evals := 0
	var pts := []
	for k in range(levels):
		var d := stencil(f, x, h / pow(2.0, k), "centrada", order)
		evals += int(d["evals"])
		if k == 0:
			pts = d["puntos"]
		var row := [float(d["valor"])]
		for j in range(1, k + 1):
			row.append(float(row[j - 1]) + (float(row[j - 1]) - float(R[k - 1][j - 1])) / (pow(4.0, j) - 1.0))
		R.append(row)
	var last: Array = R[R.size() - 1]
	return {"valor": float(last[last.size() - 1]), "evals": evals, "tabla": R, "puntos": pts}

## Savitzky–Golay: polinomio de grado deg ajustado por mínimos cuadrados a 2m + 1
## muestras equiespaciadas centradas en x; la derivada es la del polinomio.
## Suaviza el ruido de las muestras a cambio de algo de sesgo.
static func savitzky_golay(f: Callable, x: float, h: float, m: int, deg: int, order: int = 1) -> Dictionary:
	m = maxi(1, m)
	deg = clampi(deg, order, mini(2 * m, 6))
	var q := deg + 1
	var A := []
	var rhs := []
	for i in range(q):
		var row := []
		for j in range(q):
			row.append(0.0)
		A.append(row)
		rhs.append(0.0)
	var pts := []
	for k in range(-m, m + 1):
		var fx: float = f.call(x + k * h)
		pts.append([x + k * h, fx])
		for i in range(q):
			rhs[i] = float(rhs[i]) + pow(float(k), i) * fx
			for j in range(q):
				A[i][j] = float(A[i][j]) + pow(float(k), i + j)
	var c := solve(A, rhs)
	var fact := 1.0 if order == 1 else 2.0
	return {"valor": float(c[order]) * fact / pow(h, order), "evals": pts.size(), "puntos": pts}

## Eliminación gaussiana con pivoteo parcial (sistemas pequeños, doble precisión).
static func solve(A: Array, b: Array) -> Array:
	var n := b.size()
	var M := []
	for i in range(n):
		var row: Array = (A[i] as Array).duplicate()
		row.append(b[i])
		M.append(row)
	for col in range(n):
		var piv := col
		for r in range(col + 1, n):
			if absf(float(M[r][col])) > absf(float(M[piv][col])):
				piv = r
		var tmp = M[col]
		M[col] = M[piv]
		M[piv] = tmp
		var d: float = M[col][col]
		if d == 0.0:
			continue
		for r in range(col + 1, n):
			var fct: float = float(M[r][col]) / d
			for c in range(col, n + 1):
				M[r][c] = float(M[r][c]) - fct * float(M[col][c])
	var x := []
	x.resize(n)
	for i in range(n - 1, -1, -1):
		var s: float = M[i][n]
		for j in range(i + 1, n):
			s -= float(M[i][j]) * float(x[j])
		x[i] = s / float(M[i][i]) if float(M[i][i]) != 0.0 else 0.0
	return x

## Diferenciación espectral de Chebyshev: interpola f en N + 1 puntos de
## Chebyshev–Lobatto de [a, b], deriva la serie de Chebyshev (recurrencia de los
## coeficientes) y la evalúa en x. Error que decrece exponencialmente con N si f
## es analítica en [a, b].
static func chebyshev(f: Callable, a: float, b: float, N: int, x: float, order: int = 1) -> Dictionary:
	N = clampi(N, 2, 200)
	var fs := []
	var pts := []
	for j in range(N + 1):
		var t := cos(PI * j / N)
		var xj := 0.5 * (a + b) + 0.5 * (b - a) * t
		var fx: float = f.call(xj)
		fs.append(fx)
		pts.append([xj, fx])
	# Coeficientes aₖ de f(t) = Σ aₖ Tₖ(t) (DCT-I).
	var ak := []
	for k in range(N + 1):
		var s := 0.0
		for j in range(N + 1):
			var w := 0.5 if (j == 0 or j == N) else 1.0
			s += w * float(fs[j]) * cos(PI * k * j / N)
		var c := 2.0 / N * s
		if k == 0 or k == N:
			c *= 0.5
		ak.append(c)
	var coef := ak
	for o in range(order):
		coef = _cheb_deriv(coef)
	var t0 := clampf((2.0 * x - a - b) / (b - a), -1.0, 1.0)
	var th := acos(t0)
	var v := 0.0
	for k in range(coef.size()):
		v += float(coef[k]) * cos(k * th)
	return {"valor": v * pow(2.0 / (b - a), order), "evals": N + 1, "puntos": pts}

## Coeficientes de la derivada de una serie de Chebyshev.
static func _cheb_deriv(a: Array) -> Array:
	var N := a.size() - 1
	var bk := []
	bk.resize(N + 2)
	bk.fill(0.0)
	for k in range(N, 0, -1):
		bk[k - 1] = float(bk[k + 1]) + 2.0 * k * float(a[k])
	bk[0] = float(bk[0]) * 0.5
	bk.resize(maxi(1, N))
	return bk

## Derivada del spline cúbico (extremos «not-a-knot») que interpola 2m + 1
## muestras de paso h centradas en x (primera o segunda derivada en el nodo central).
static func spline(f: Callable, x: float, h: float, m: int, order: int = 1) -> Dictionary:
	m = maxi(2, m)
	var n := 2 * m + 1
	var ys := []
	var pts := []
	for k in range(-m, m + 1):
		var fx: float = f.call(x + k * h)
		ys.append(fx)
		pts.append([x + k * h, fx])
	# Momentos Mᵢ = s″(xᵢ): Mᵢ₋₁ + 4Mᵢ + Mᵢ₊₁ = 6Δ²yᵢ/h². Not-a-knot (s‴ continua en
	# x₁ y xₙ₋₂) en malla uniforme: M₀ = 2M₁ − M₂, así la primera y la última fila
	# quedan 6M₁ = r₁ y 6Mₙ₋₂ = rₙ₋₂.
	var k0 := 1
	var k1 := n - 2
	var sub := []
	var dia := []
	var sup := []
	var rhs := []
	for i in range(k0, k1 + 1):
		rhs.append(6.0 * (float(ys[i + 1]) - 2.0 * float(ys[i]) + float(ys[i - 1])) / (h * h))
		sub.append(0.0 if i == k0 else (0.0 if i == k1 else 1.0))
		sup.append(0.0 if i == k1 else (0.0 if i == k0 else 1.0))
		dia.append(6.0 if (i == k0 or i == k1) else 4.0)
	var mi := _thomas(sub, dia, sup, rhs)
	var M := [2.0 * float(mi[0]) - float(mi[1])]
	M.append_array(mi)
	M.append(2.0 * float(mi[mi.size() - 1]) - float(mi[mi.size() - 2]))
	var c := m
	var val: float
	if order == 1:
		val = (float(ys[c + 1]) - float(ys[c])) / h - h * (2.0 * float(M[c]) + float(M[c + 1])) / 6.0
	else:
		val = float(M[c])
	return {"valor": val, "evals": n, "puntos": pts}

## Sistema tridiagonal (algoritmo de Thomas).
static func _thomas(a: Array, b: Array, c: Array, d: Array) -> Array:
	var n := d.size()
	var cp := []
	var dp := []
	cp.resize(n)
	dp.resize(n)
	cp[0] = float(c[0]) / float(b[0])
	dp[0] = float(d[0]) / float(b[0])
	for i in range(1, n):
		var den: float = float(b[i]) - float(a[i]) * float(cp[i - 1])
		cp[i] = float(c[i]) / den
		dp[i] = (float(d[i]) - float(a[i]) * float(dp[i - 1])) / den
	var x := []
	x.resize(n)
	x[n - 1] = dp[n - 1]
	for i in range(n - 2, -1, -1):
		x[i] = float(dp[i]) - float(cp[i]) * float(x[i + 1])
	return x
