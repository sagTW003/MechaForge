class_name Celeste
extends RefCounted
## Celeste — Los métodos numéricos del módulo «Mecánica celeste» (docs/PROYECTO_ORBITAS.md).
##
## Cinco preguntas sobre el movimiento de los astros, cada una resuelta con un método numérico:
##   1. ¿Dónde se estaciona el telescopio James Webb? Puntos de Lagrange por bisección, secante y
##      Newton; una nave en el problema restringido de tres cuerpos, con RK4.
##   2. ¿Cómo encontró Gauss a Ceres? Mínimos cuadrados: ecuaciones normales (Cholesky) y QR.
##   3. ¿Cuándo estará Marte más cerca? Ecuación de Kepler por Newton e interpolación de una tabla.
##   4. Si la Tierra se detuviera, ¿cuánto tardaría en caer al Sol? Integral impropia y EDO.
##   5. ¿Por qué gira la órbita de Mercurio? Euler, RK4 y Verlet; ajuste lineal y extrapolación.
## Funciones puras y deterministas: las pruebas las comparan con los valores exactos o reales.
## Unidades: UA, días y masas solares (GM☉ = k², k la constante gaussiana); el problema de tres
## cuerpos usa unidades canónicas (distancia entre los primarios = 1, movimiento medio = 1).
## Los números van en float de 64 bits y nunca en Vector2/Vector3, que son de 32.

const Raices := preload("res://mathlab/modules/RaicesModule.gd")
const Sistemas := preload("res://mathlab/modules/SistemasModule.gd")

const K := 0.01720209895                  # constante gaussiana: √(GM☉) en UA^{3/2}/día
const GM := K * K
const KM_UA := 149597870.7
const C_LUZ := 173.1446326846693          # velocidad de la luz en UA/día
const R_SOL := 0.00465047                 # radio del Sol en UA (695 700 km)
const ARCSEG := 206264.80624709636        # segundos de arco por radián
const SIGLO := 36525.0                    # días
const MESES := ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]

# --- Comunes ----------------------------------------------------------------------------------

## Ecuación de Kepler E − e·sen E = M por Newton desde E₀ = M + e·sen M (π si e > 0,8):
## [E, iteraciones].
static func kepler(M: float, e: float, tol: float = 1e-14) -> Array:
	M = fposmod(M + PI, TAU) - PI
	var E := M + e * sin(M) if e < 0.8 else (PI if M >= 0.0 else -PI)
	var it := 0
	while it < 50:
		var dE := (E - e * sin(E) - M) / (1.0 - e * cos(E))
		E -= dE
		it += 1
		if absf(dE) < tol:
			break
	return [E, it]

## Periodo (días) de una órbita de semieje a (UA) alrededor del Sol: T = 2π·a^{3/2}/k.
static func periodo(a: float) -> float:
	return TAU * pow(a, 1.5) / K

## Posición polar [r, θ] en el instante t (días) de la órbita plana {a, e, peri (longitud del
## perihelio, grados), M0 (anomalía media en t = 0, rad)}.
static func polar(orb: Dictionary, t: float) -> PackedFloat64Array:
	var a: float = orb["a"]
	var e: float = orb["e"]
	var E: float = kepler(float(orb["M0"]) + K / pow(a, 1.5) * t, e)[0]
	var f := 2.0 * atan2(sqrt(1.0 + e) * sin(0.5 * E), sqrt(1.0 - e) * cos(0.5 * E))
	return PackedFloat64Array([a * (1.0 - e * cos(E)), f + deg_to_rad(float(orb["peri"]))])

## Errores |xₖ − x*| de una sucesión de aproximaciones.
static func errores(xs: Array, x_ref: float) -> Array:
	var e := []
	for x in xs:
		e.append(absf(float(x) - x_ref))
	return e

## Orden de convergencia observado: el mismo cálculo que «Ecuaciones no lineales»; en la
## bisección, cuyo error no baja de forma regular, la pendiente de la recta de mínimos cuadrados
## de ln eₖ₊₁ frente a ln eₖ.
static func orden(xs: Array, x_ref: float, regresion: bool = false) -> float:
	var e := errores(xs, x_ref)
	if not regresion:
		return Raices.order_of(e)
	var pts := []
	for k in range(e.size() - 1):
		if e[k] > 1e-13 and e[k + 1] > 1e-13:
			pts.append([log(e[k]), log(e[k + 1])])
	return recta(pts)[0] if pts.size() >= 3 else NAN

## Recta de mínimos cuadrados y = m·x + c por los puntos [[x, y], …]: [m, c].
static func recta(pts: Array) -> PackedFloat64Array:
	var n := float(pts.size())
	var sx := 0.0
	var sy := 0.0
	for p in pts:
		sx += float(p[0])
		sy += float(p[1])
	var mx := sx / n
	var my := sy / n
	var sxy := 0.0
	var sxx := 0.0
	for p in pts:
		sxy += (float(p[0]) - mx) * (float(p[1]) - my)
		sxx += (float(p[0]) - mx) * (float(p[0]) - mx)
	var m := sxy / sxx if sxx > 0.0 else 0.0
	return PackedFloat64Array([m, my - m * mx])

## Fecha juliana (UT ≈ TT: la diferencia de un minuto no cambia nada aquí).
static func jd(y: int, m: int, d: float) -> float:
	var u := Time.get_unix_time_from_datetime_dict({"year": y, "month": m, "day": 1, "hour": 0, "minute": 0, "second": 0})
	return u / 86400.0 + 2440587.5 + d - 1.0

## «12 ene 2025 09:30» (o sin la hora).
static func fecha(j: float, con_hora: bool = true) -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(round((j - 2440587.5) * 86400.0)))
	var s := "%d %s %d" % [d["day"], MESES[int(d["month"]) - 1], d["year"]]
	return s + (" %02d:%02d" % [d["hour"], d["minute"]] if con_hora else "")

# --- 1. Puntos de Lagrange --------------------------------------------------------------------

## μ = m₂/(m₁ + m₂), la distancia entre los dos cuerpos y el periodo de su órbita.
const SISTEMAS := [
	{"nombre": "Sol–Tierra", "mu": 3.0404e-6, "d_km": 149597870.7, "periodo": 365.256, "p1": "Sol", "p2": "Tierra"},
	{"nombre": "Tierra–Luna", "mu": 0.0121505856, "d_km": 384400.0, "periodo": 27.3217, "p1": "Tierra", "p2": "Luna"},
	{"nombre": "Sol–Júpiter", "mu": 9.5388e-4, "d_km": 778.479e6, "periodo": 4332.59, "p1": "Sol", "p2": "Júpiter"},
]
const METODOS_RAIZ := ["Bisección", "Secante", "Newton"]
const ORDEN_RAIZ := ["1", "1,618", "2"]

## Potencial efectivo Ω en el marco que gira con los primarios (m₁ en x = −μ, m₂ en x = 1 − μ).
static func omega(x: float, y: float, mu: float) -> float:
	var r1 := sqrt((x + mu) * (x + mu) + y * y)
	var r2 := sqrt((x - 1.0 + mu) * (x - 1.0 + mu) + y * y)
	return 0.5 * (x * x + y * y) + (1.0 - mu) / r1 + mu / r2

## Sobre el eje (y = 0), L1, L2 y L3 anulan ∂Ω/∂x:
## f(x) = x − (1 − μ)(x + μ)/|x + μ|³ − μ(x − 1 + μ)/|x − 1 + μ|³.
static func f_lagrange(x: float, mu: float) -> float:
	var d1 := x + mu
	var d2 := x - 1.0 + mu
	return x - (1.0 - mu) * d1 / absf(d1 * d1 * d1) - mu * d2 / absf(d2 * d2 * d2)

## f′(x) = 1 + 2(1 − μ)/|x + μ|³ + 2μ/|x − 1 + μ|³ > 0: entre dos singularidades f crece,
## así que en cada tramo del eje hay una sola raíz.
static func df_lagrange(x: float, mu: float) -> float:
	var d1 := absf(x + mu)
	var d2 := absf(x - 1.0 + mu)
	return 1.0 + 2.0 * (1.0 - mu) / (d1 * d1 * d1) + 2.0 * mu / (d2 * d2 * d2)

## Radio de Hill r_H = (μ/3)^{1/3}: L1 y L2 están a ≈ r_H del cuerpo menor.
static func radio_hill(mu: float) -> float:
	return pow(mu / 3.0, 1.0 / 3.0)

## Intervalo [a, b] con f(a) < 0 < f(b) que encierra a L1 (0), L2 (1) o L3 (2).
static func intervalo(punto: int, mu: float) -> PackedFloat64Array:
	var rh := radio_hill(mu)
	var p := 1.0 - mu
	match punto:
		0:
			return PackedFloat64Array([p - minf(2.0 * rh, 0.9), p - 0.5 * rh])
		1:
			return PackedFloat64Array([p + 0.5 * rh, p + 2.0 * rh])
	return PackedFloat64Array([-1.5, -0.5])

## Newton parte del extremo del intervalo más lejano del cuerpo menor (o de L3, del más
## cercano al Sol): así se ven varias iteraciones.
static func x0_newton(punto: int, mu: float) -> float:
	var ab := intervalo(punto, mu)
	return ab[0] if punto == 0 else ab[1]

## Iteraciones de un método de raíces: bisección (0) y secante (1) parten del intervalo [a, b];
## Newton (2), de x0. Para cuando |xₖ − xₖ₋₁| ≤ tol·max(1, |xₖ|).
## Devuelve {xs: [x₁, x₂, …], intervalos: [[aₖ, bₖ], …] (bisección), evals, converge}.
static func raiz(metodo: int, f: Callable, df: Callable, a: float, b: float, x0: float, tol: float = 1e-15) -> Dictionary:
	var xs := []
	var ints := []
	var ok := false
	var evals := 0
	match metodo:
		0:
			var fa: float = f.call(a)
			evals = 1
			for i in 200:
				ints.append([a, b])
				var m := 0.5 * (a + b)
				xs.append(m)
				var fm: float = f.call(m)
				evals += 1
				if fm == 0.0 or 0.5 * (b - a) <= tol * maxf(1.0, absf(m)):
					ok = true
					break
				if (fm < 0.0) == (fa < 0.0):
					a = m
					fa = fm
				else:
					b = m
		1:
			var xp := a
			var fp: float = f.call(a)
			var x := b
			var fx: float = f.call(b)
			evals = 2
			for i in 100:
				if fx == fp:
					ok = fx == 0.0
					break
				var xn := x - fx * (x - xp) / (fx - fp)
				if not is_finite(xn):
					break
				xs.append(xn)
				xp = x
				fp = fx
				x = xn
				fx = f.call(x)
				evals += 1
				if absf(x - xp) <= tol * maxf(1.0, absf(x)) or fx == 0.0:
					ok = true
					break
		_:
			var x := x0
			for i in 100:
				var fx: float = f.call(x)
				var d: float = df.call(x)
				evals += 2
				if d == 0.0 or not is_finite(d) or not is_finite(fx):
					break
				var xn := x - fx / d
				if not is_finite(xn):
					break
				xs.append(xn)
				if absf(xn - x) <= tol * maxf(1.0, absf(xn)):
					ok = true
					break
				x = xn
	return {"xs": xs, "intervalos": ints, "evals": evals, "converge": ok}

## Las iteraciones del método m para el punto L1 (0), L2 (1) o L3 (2) del sistema con μ.
## x0 = NAN: Newton parte de x0_newton.
static func iterar_lagrange(m: int, punto: int, mu: float, x0: float = NAN) -> Dictionary:
	var ab := intervalo(punto, mu)
	var f := func(x: float) -> float: return f_lagrange(x, mu)
	var df := func(x: float) -> float: return df_lagrange(x, mu)
	return raiz(m, f, df, ab[0], ab[1], x0_newton(punto, mu) if is_nan(x0) else x0)

## Los cinco puntos de Lagrange [[x, y], …]: L1–L3 por bisección (la referencia: con un
## intervalo válido no puede fallar), L4 y L5 exactos (triángulos equiláteros con los dos cuerpos).
static func puntos_lagrange(mu: float) -> Array:
	var pts := []
	for p in 3:
		pts.append([float(iterar_lagrange(0, p, mu)["xs"][-1]), 0.0])
	pts.append([0.5 - mu, sqrt(3.0) / 2.0])
	pts.append([0.5 - mu, -sqrt(3.0) / 2.0])
	return pts

## Distancia (km) de L1/L2 al cuerpo menor y de L3 al mayor.
static func distancia_km(punto: int, x: float, mu: float, d_km: float) -> float:
	return absf(x + mu) * d_km if punto == 2 else absf(x - 1.0 + mu) * d_km

## Derivada del estado [x, y, vx, vy] de una nave en el marco rotante (con Coriolis):
## ẍ = 2ẏ + ∂Ω/∂x, ÿ = −2ẋ + ∂Ω/∂y.
static func _deriv3(s: PackedFloat64Array, mu: float) -> PackedFloat64Array:
	var dx1 := s[0] + mu
	var dx2 := s[0] - 1.0 + mu
	var y := s[1]
	var r1 := dx1 * dx1 + y * y
	var r2 := dx2 * dx2 + y * y
	r1 *= sqrt(r1)
	r2 *= sqrt(r2)
	return PackedFloat64Array([s[2], s[3],
		s[0] - (1.0 - mu) * dx1 / r1 - mu * dx2 / r2 + 2.0 * s[3],
		y - (1.0 - mu) * y / r1 - mu * y / r2 - 2.0 * s[2]])

static func _mas(s: PackedFloat64Array, h: float, k: PackedFloat64Array) -> PackedFloat64Array:
	var o := s.duplicate()
	for i in o.size():
		o[i] += h * k[i]
	return o

## Un paso de Runge–Kutta 4 de la nave.
static func rk4_nave(s: PackedFloat64Array, mu: float, h: float) -> PackedFloat64Array:
	var k1 := _deriv3(s, mu)
	var k2 := _deriv3(_mas(s, 0.5 * h, k1), mu)
	var k3 := _deriv3(_mas(s, 0.5 * h, k2), mu)
	var k4 := _deriv3(_mas(s, h, k3), mu)
	var o := s.duplicate()
	for i in 4:
		o[i] += h / 6.0 * (k1[i] + 2.0 * k2[i] + 2.0 * k3[i] + k4[i])
	return o

## Constante de Jacobi C = 2Ω − v²: se conserva; su deriva mide el error del integrador.
static func jacobi(s: PackedFloat64Array, mu: float) -> float:
	return 2.0 * omega(s[0], s[1], mu) - s[2] * s[2] - s[3] * s[3]

# --- 2. La órbita de Ceres --------------------------------------------------------------------

## Ceres en el plano de la eclíptica; el 1 de enero de 1801, cuando Piazzi la descubrió, estaba
## en oposición (longitud heliocéntrica ≈ la de la Tierra, 100,5°).
const CERES := {"a": 2.7675, "e": 0.0785, "peri": 153.9, "M0": -0.8193}
const TIERRA_1801 := 100.5               # longitud heliocéntrica de la Tierra el 1-ene-1801 (°)
const METODOS_LS := ["Ecuaciones normales + Cholesky", "QR (Gram–Schmidt modificado)"]

## n observaciones (t, r, θ) repartidas en «arco» días desde el descubrimiento, con un error
## gaussiano de σ relativo en r y de σ radianes en θ (la misma semilla da los mismos datos).
static func observar(orb: Dictionary, n: int, arco: float, sigma: float, semilla: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = semilla
	var obs := []
	for i in n:
		var t := arco * i / maxf(1.0, n - 1.0)
		var p := polar(orb, t)
		obs.append([t, p[0] * (1.0 + sigma * rng.randfn()), p[1] + sigma * rng.randfn()])
	return obs

## Cholesky de una matriz 3×3 simétrica definida positiva y solución de A·x = b (vacío si A no
## es definida positiva).
static func cholesky3(A: Array, b: Array) -> PackedFloat64Array:
	var L := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	for i in 3:
		for j in i + 1:
			var s: float = A[i][j]
			for k in j:
				s -= L[i][k] * L[j][k]
			if i == j:
				if s <= 0.0:
					return PackedFloat64Array()
				L[i][i] = sqrt(s)
			else:
				L[i][j] = s / L[j][j]
	var z := PackedFloat64Array([0.0, 0.0, 0.0])
	for i in 3:
		var s: float = b[i]
		for k in i:
			s -= L[i][k] * z[k]
		z[i] = s / L[i][i]
	var x := PackedFloat64Array([0.0, 0.0, 0.0])
	for i in range(2, -1, -1):
		var s: float = z[i]
		for k in range(i + 1, 3):
			s -= L[k][i] * x[k]
		x[i] = s / L[i][i]
	return x

## Mínimos cuadrados de 1/r = A + B·cos θ + C·sen θ (una cónica con el Sol en un foco).
## metodo 0: ecuaciones normales (MᵀM)c = Mᵀy por Cholesky; 1: QR de M por Gram–Schmidt
## modificado y R·c = Qᵀy, que no eleva al cuadrado el número de condición.
## Devuelve {c, N (MᵀM), kappa (de MᵀM), kappa_M, rms, a, e, peri (°), valido}.
static func ajustar(obs: Array, metodo: int) -> Dictionary:
	var n := obs.size()
	var q := PackedFloat64Array()          # columnas de M, una tras otra: q[j·n + i]
	q.resize(3 * n)
	var y := PackedFloat64Array()
	y.resize(n)
	for i in n:
		var th: float = obs[i][2]
		q[i] = 1.0
		q[n + i] = cos(th)
		q[2 * n + i] = sin(th)
		y[i] = 1.0 / float(obs[i][1])
	var N := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	var rhs := [0.0, 0.0, 0.0]
	for j in 3:
		for k in 3:
			var s := 0.0
			for i in n:
				s += q[j * n + i] * q[k * n + i]
			N[j][k] = s
		var sy := 0.0
		for i in n:
			sy += q[j * n + i] * y[i]
		rhs[j] = sy
	var c := PackedFloat64Array()
	if metodo == 0:
		c = cholesky3(N, rhs)
	else:
		var R := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
		for j in 3:
			for k in j:
				var rkj := 0.0
				for i in n:
					rkj += q[k * n + i] * q[j * n + i]
				R[k][j] = rkj
				for i in n:
					q[j * n + i] -= rkj * q[k * n + i]
			var nrm := 0.0
			for i in n:
				nrm += q[j * n + i] * q[j * n + i]
			nrm = sqrt(nrm)
			R[j][j] = nrm
			if nrm > 0.0:
				for i in n:
					q[j * n + i] /= nrm
		var z := [0.0, 0.0, 0.0]
		for j in 3:
			for i in n:
				z[j] += q[j * n + i] * y[i]
		if R[0][0] != 0.0 and R[1][1] != 0.0 and R[2][2] != 0.0:
			c = PackedFloat64Array([0.0, 0.0, 0.0])
			for j in range(2, -1, -1):
				var s: float = z[j]
				for k in range(j + 1, 3):
					s -= R[j][k] * c[k]
				c[j] = s / R[j][j]
	var ev: Array = Sistemas.sym_eigenvalues(N)
	var kappa: float = float(ev[2]) / float(ev[0]) if float(ev[0]) > 0.0 else INF
	var res := {"c": c, "N": N, "kappa": kappa, "kappa_M": sqrt(kappa), "valido": false, "metodo": metodo}
	if c.size() != 3 or not (c[0] > 0.0):
		return res
	var rms := 0.0
	for i in n:
		var th: float = obs[i][2]
		rms += pow(c[0] + c[1] * cos(th) + c[2] * sin(th) - y[i], 2)
	res["rms"] = sqrt(rms / n)
	var e := sqrt(c[1] * c[1] + c[2] * c[2]) / c[0]
	res["e"] = e
	res["peri"] = rad_to_deg(atan2(c[2], c[1]))
	res["p"] = 1.0 / c[0]
	res["a"] = 1.0 / c[0] / (1.0 - e * e) if e < 1.0 else INF
	res["valido"] = e < 1.0
	return res

## Posición [r, θ] predicha en t con la órbita ajustada; la época (anomalía media en t = 0) es
## la media circular de Mᵢ − n·tᵢ de las observaciones. Vacío si la cónica no es una elipse.
static func predecir(aj: Dictionary, obs: Array, t: float) -> PackedFloat64Array:
	if not aj.get("valido", false):
		return PackedFloat64Array()
	var a: float = aj["a"]
	var e: float = aj["e"]
	var n := K / pow(a, 1.5)
	var peri := deg_to_rad(float(aj["peri"]))
	var sx := 0.0
	var sy := 0.0
	for o in obs:
		var f: float = float(o[2]) - peri
		var E := 2.0 * atan2(sqrt(1.0 - e) * sin(0.5 * f), sqrt(1.0 + e) * cos(0.5 * f))
		var M0: float = E - e * sin(E) - n * float(o[0])
		sx += cos(M0)
		sy += sin(M0)
	return polar({"a": a, "e": e, "peri": aj["peri"], "M0": atan2(sy, sx)}, t)

## Error de una predicción [r, θ] frente a la posición real: [ángulo visto desde el Sol (°),
## distancia (UA)].
static func error_prediccion(pred: PackedFloat64Array, real: PackedFloat64Array) -> PackedFloat64Array:
	if pred.size() < 2:
		return PackedFloat64Array([INF, INF])
	var dth := fposmod(pred[1] - real[1] + PI, TAU) - PI
	var dx := pred[0] * cos(pred[1]) - real[0] * cos(real[1])
	var dy := pred[0] * sin(pred[1]) - real[0] * sin(real[1])
	return PackedFloat64Array([absf(rad_to_deg(dth)), sqrt(dx * dx + dy * dy)])

# --- 3. El acercamiento de Marte --------------------------------------------------------------

## Elementos keplerianos medios de JPL (E. M. Standish, tabla 1, válidos de 1800 a 2050):
## [valores en J2000, ritmos por siglo] de a (UA), e, I, L, ϖ, Ω (grados).
const TIERRA_JPL := [[1.00000261, 0.01671123, -0.00001531, 100.46457166, 102.93768193, 0.0],
	[0.00000562, -0.00004392, -0.01294668, 35999.37244981, 0.32327364, 0.0]]
const MARTE_JPL := [[1.52371034, 0.09339410, 1.84969142, -4.55343205, -23.94362959, 49.55953891],
	[0.00001847, 0.00007882, -0.00813131, 19140.30268499, 0.44441088, -0.29257343]]
## Los acercamientos que publica la NASA: [año, mes, día, distancia en millones de km] y la
## ventana de la tabla de efemérides, [año, mes] → [año, mes]: empieza el día 1 a las 0 h, sin
## alinear los nodos con el mínimo.
const ACERCAMIENTOS := [[2025, 1, 12, 96.08, [2024, 9], [2025, 5]], [2027, 2, 20, 101.41, [2026, 10], [2027, 6]]]

## Ventana [jd0, jd1] de la tabla del acercamiento i.
static func ventana(i: int) -> PackedFloat64Array:
	var ac: Array = ACERCAMIENTOS[i]
	return PackedFloat64Array([jd(ac[4][0], ac[4][1], 1.0), jd(ac[5][0], ac[5][1], 1.0)])
const METODOS_MIN := ["Menor valor de la tabla", "Parábola por 3 nodos (Lagrange)", "Spline cúbico natural"]

## Posición heliocéntrica [x, y, z] (UA, eclíptica J2000) en la fecha juliana j, más las
## iteraciones de Newton que necesitó la ecuación de Kepler.
static func posicion(el: Array, j: float) -> PackedFloat64Array:
	var T := (j - 2451545.0) / 36525.0
	var v: Array = el[0]
	var dv: Array = el[1]
	var a: float = v[0] + dv[0] * T
	var e: float = v[1] + dv[1] * T
	var I := deg_to_rad(v[2] + dv[2] * T)
	var L: float = v[3] + dv[3] * T
	var wbar: float = v[4] + dv[4] * T
	var Om: float = v[5] + dv[5] * T
	var w := deg_to_rad(wbar - Om)
	var O := deg_to_rad(Om)
	var k := kepler(deg_to_rad(L - wbar), e)
	var E: float = k[0]
	var xp := a * (cos(E) - e)
	var yp := a * sqrt(1.0 - e * e) * sin(E)
	var cw := cos(w)
	var sw := sin(w)
	var cO := cos(O)
	var sO := sin(O)
	var cI := cos(I)
	var sI := sin(I)
	return PackedFloat64Array([(cw * cO - sw * sO * cI) * xp + (-sw * cO - cw * sO * cI) * yp,
		(cw * sO + sw * cO * cI) * xp + (-sw * sO + cw * cO * cI) * yp,
		sw * sI * xp + cw * sI * yp, k[1]])

## Distancia Tierra–Marte (UA) en la fecha juliana j.
static func distancia_tm(j: float) -> float:
	var t := posicion(TIERRA_JPL, j)
	var m := posicion(MARTE_JPL, j)
	return sqrt((m[0] - t[0]) ** 2 + (m[1] - t[1]) ** 2 + (m[2] - t[2]) ** 2)

## La tabla de efemérides: [fechas, distancias] cada «paso» días desde j0 hasta pasar j1.
static func tabla(j0: float, j1: float, paso: float) -> Array:
	var ts := PackedFloat64Array()
	var ds := PackedFloat64Array()
	var j := j0
	while j <= j1 + 1e-9:
		ts.append(j)
		ds.append(distancia_tm(j))
		j += paso
	return [ts, ds]

## Spline cúbico natural: las segundas derivadas Mᵢ en los nodos, del sistema tridiagonal
## hᵢ₋₁Mᵢ₋₁ + 2(hᵢ₋₁ + hᵢ)Mᵢ + hᵢMᵢ₊₁ = 6(Δᵢ − Δᵢ₋₁), con M₀ = Mₙ = 0 (algoritmo de Thomas).
static func spline(xs: PackedFloat64Array, ys: PackedFloat64Array) -> PackedFloat64Array:
	var n := xs.size()
	var M := PackedFloat64Array()
	M.resize(n)
	M.fill(0.0)
	var m := n - 2
	if m < 1:
		return M
	var lo := PackedFloat64Array()
	var di := PackedFloat64Array()
	var up := PackedFloat64Array()
	var rhs := PackedFloat64Array()
	for i in range(1, n - 1):
		var h0 := xs[i] - xs[i - 1]
		var h1 := xs[i + 1] - xs[i]
		lo.append(h0)
		di.append(2.0 * (h0 + h1))
		up.append(h1)
		rhs.append(6.0 * ((ys[i + 1] - ys[i]) / h1 - (ys[i] - ys[i - 1]) / h0))
	for i in range(1, m):
		var w := lo[i] / di[i - 1]
		di[i] -= w * up[i - 1]
		rhs[i] -= w * rhs[i - 1]
	M[m] = rhs[m - 1] / di[m - 1]
	for i in range(m - 2, -1, -1):
		M[i + 1] = (rhs[i] - up[i] * M[i + 2]) / di[i]
	return M

static func _tramo(xs: PackedFloat64Array, x: float) -> int:
	return clampi(xs.bsearch(x) - 1, 0, xs.size() - 2)

## Valor (der = 0) o derivada (der = 1) del spline en x.
static func spline_en(xs: PackedFloat64Array, ys: PackedFloat64Array, M: PackedFloat64Array, x: float, der: int = 0) -> float:
	var i := _tramo(xs, x)
	var h := xs[i + 1] - xs[i]
	var A := xs[i + 1] - x
	var B := x - xs[i]
	var ca := ys[i] / h - M[i] * h / 6.0
	var cb := ys[i + 1] / h - M[i + 1] * h / 6.0
	if der == 1:
		return -M[i] * A * A / (2.0 * h) + M[i + 1] * B * B / (2.0 * h) - ca + cb
	return M[i] * A * A * A / (6.0 * h) + M[i + 1] * B * B * B / (6.0 * h) + ca * A + cb * B

## Interpolación lineal de la tabla en x.
static func lineal_en(xs: PackedFloat64Array, ys: PackedFloat64Array, x: float) -> float:
	var i := _tramo(xs, x)
	return lerpf(ys[i], ys[i + 1], (x - xs[i]) / (xs[i + 1] - xs[i]))

## Mínimo [t, d] de la tabla con un método: 0 el menor nodo; 1 el vértice de la parábola por
## los tres nodos de alrededor; 2 el del spline natural (raíz de S′ por bisección). Los nodos
## están equiespaciados.
static func minimo(ts: PackedFloat64Array, ds: PackedFloat64Array, metodo: int, M: PackedFloat64Array = PackedFloat64Array()) -> PackedFloat64Array:
	var i := 1
	for k in range(1, ds.size() - 1):
		if ds[k] < ds[i]:
			i = k
	if metodo == 0:
		return PackedFloat64Array([ts[i], ds[i]])
	var h := ts[i + 1] - ts[i]
	if metodo == 1:
		var den := ds[i - 1] - 2.0 * ds[i] + ds[i + 1]
		var num := ds[i - 1] - ds[i + 1]
		return PackedFloat64Array([ts[i] + 0.5 * h * num / den, ds[i] - num * num / (8.0 * den)])
	if M.size() != ts.size():
		M = spline(ts, ds)
	var a := ts[i - 1]
	var b := ts[i + 1]
	for k in 60:
		var c := 0.5 * (a + b)
		if spline_en(ts, ds, M, c, 1) < 0.0:
			a = c
		else:
			b = c
	var t := 0.5 * (a + b)
	return PackedFloat64Array([t, spline_en(ts, ds, M, t)])

## Referencia sin tabla: sección áurea sobre la efeméride en [a, b] hasta 10⁻⁶ días.
static func minimo_referencia(a: float, b: float) -> PackedFloat64Array:
	var g := (sqrt(5.0) - 1.0) / 2.0
	var c := b - g * (b - a)
	var d := a + g * (b - a)
	var fc := distancia_tm(c)
	var fd := distancia_tm(d)
	while b - a > 1e-6:
		if fc < fd:
			b = d
			d = c
			fd = fc
			c = b - g * (b - a)
			fc = distancia_tm(c)
		else:
			a = c
			c = d
			fc = fd
			d = a + g * (b - a)
			fd = distancia_tm(d)
	var t := 0.5 * (a + b)
	return PackedFloat64Array([t, distancia_tm(t)])

## Error máximo (UA) de la interpolación lineal y del spline entre los nodos de la tabla.
static func error_interpolacion(ts: PackedFloat64Array, ds: PackedFloat64Array, M: PackedFloat64Array, muestras: int = 400) -> PackedFloat64Array:
	var el := 0.0
	var es := 0.0
	for k in muestras + 1:
		var x := lerpf(ts[0], ts[-1], float(k) / muestras)
		var d := distancia_tm(x)
		el = maxf(el, absf(lineal_en(ts, ds, x) - d))
		es = maxf(es, absf(spline_en(ts, ds, M, x) - d))
	return PackedFloat64Array([el, es])

# --- 4. La caída al Sol -----------------------------------------------------------------------

const METODOS_INT := ["Trapecio", "Simpson", "Punto medio", "Gauss–Legendre", "Tanh-sinh",
	"r = R·sen²u + trapecio", "r = R·sen²u + Simpson"]

## Integrando del tiempo de caída desde el reposo en r = R: dt/dr = 1/√(2GM(1/r − 1/R)) en
## días/UA (1/r − 1/R se escribe (R − r)/(rR), sin cancelación). Diverge como 1/√(R − r) en
## r = R: la integral es impropia.
static func f_caida(r: float, R: float) -> float:
	if r >= R:
		return INF
	if r <= 0.0:
		return 0.0
	return sqrt(r * R / (2.0 * GM * (R - r)))

## Con r = R·sen²u el integrando queda suave: dt/du = 2R^{3/2}·sen²u/√(2GM), u ∈ [0, π/2].
static func g_caida(u: float, R: float) -> float:
	return 2.0 * pow(R, 1.5) * sin(u) * sin(u) / sqrt(2.0 * GM)

## Tiempo exacto (días) de caer de R a r: √(R³/2GM)·(√(x(1 − x)) + arccos √x), x = r/R.
## Hasta el centro, T/(4√2) con T el periodo de la órbita circular de radio R.
static func t_caida(R: float, r: float = 0.0) -> float:
	var x := clampf(r / R, 0.0, 1.0)
	return sqrt(R * R * R / (2.0 * GM)) * (sqrt(x * (1.0 - x)) + acos(sqrt(x)))

## La integral con el método m y n subintervalos (n puntos en Gauss–Legendre; en tanh-sinh, n
## fija los niveles de refinamiento). Lo que devuelve Quadrature más «variable»: "r", "u" o "w".
## Tanh-sinh integra en w = R − r: sus nodos se acercan a 10⁻³⁰ del extremo singular y, escritos
## como r = R − w, se redondearían a R.
static func cuadratura(m: int, n: int, R: float) -> Dictionary:
	var f := func(r: float) -> float: return f_caida(r, R)
	var g := func(u: float) -> float: return g_caida(u, R)
	var fw := func(w: float) -> float: return INF if w <= 0.0 else sqrt((R - w) * R / (2.0 * GM * w))
	var d: Dictionary
	match m:
		0:
			d = Quadrature.trapezoid(f, 0.0, R, n)
		1:
			d = Quadrature.simpson(f, 0.0, R, n)
		2:
			d = Quadrature.midpoint(f, 0.0, R, n)
		3:
			d = Quadrature.gauss_legendre(f, 0.0, R, n)
		4:
			d = Quadrature.tanh_sinh(fw, 0.0, R, 1e-15, clampi(int(round(log(float(n)) / log(2.0))) - 2, 1, 8))
			d["variable"] = "w"
			return d
		5:
			d = Quadrature.trapezoid(g, 0.0, PI / 2.0, n)
		_:
			d = Quadrature.simpson(g, 0.0, PI / 2.0, n)
	d["variable"] = "u" if m >= 5 else "r"
	return d

## Tabla de convergencia del método m: [[n, valor, error, orden observado], …] con
## p = log₂(e(n/2)/e(n)).
static func convergencia(m: int, R: float, ns: Array = [4, 8, 16, 32, 64]) -> Array:
	var exacto := t_caida(R)
	var filas := []
	var e_prev := NAN
	for n in ns:
		var v: float = cuadratura(m, n, R)["valor"]
		var err := absf(v - exacto)
		var p := NAN
		if is_finite(err) and is_finite(e_prev) and err > 1e-14 and e_prev > 1e-14:
			p = log(e_prev / err) / log(2.0)
		filas.append([n, v, err, p])
		e_prev = err
	return filas

## Un paso de RK4 de la caída radial: r̈ = −GM/r². [r, v].
static func rk4_radial(r: float, v: float, h: float) -> PackedFloat64Array:
	var k1v := -GM / (r * r)
	var r2 := r + 0.5 * h * v
	var k2v := -GM / (r2 * r2)
	var v2 := v + 0.5 * h * k1v
	var r3 := r + 0.5 * h * v2
	var k3v := -GM / (r3 * r3)
	var v3 := v + 0.5 * h * k2v
	var r4 := r + h * v3
	var k4v := -GM / (r4 * r4)
	var v4 := v + h * k3v
	return PackedFloat64Array([r + h / 6.0 * (v + 2.0 * v2 + 2.0 * v3 + v4), v + h / 6.0 * (k1v + 2.0 * k2v + 2.0 * k3v + k4v)])

## La caída con RK4 de paso fijo h (días) desde el reposo en R hasta la superficie del Sol; el
## instante del impacto se interpola linealmente en el último paso.
static func caida_edo(R: float, h: float) -> Dictionary:
	var r := R
	var v := 0.0
	var t := 0.0
	var pasos := 0
	while pasos < 2000000:
		var s := rk4_radial(r, v, h)
		pasos += 1
		if s[0] <= R_SOL or not is_finite(s[0]):
			var frac := clampf((r - R_SOL) / (r - s[0]), 0.0, 1.0) if is_finite(s[0]) else 0.5
			t += h * frac
			v += (s[1] - v) * frac if is_finite(s[1]) else 0.0
			break
		r = s[0]
		v = s[1]
		t += h
	return {"t": t, "pasos": pasos, "v_kms": absf(v) * KM_UA / 86400.0, "exacto": t_caida(R, R_SOL)}

# --- 5. La precesión de Mercurio --------------------------------------------------------------

const MERCURIO := {"a": 0.387098, "e": 0.205630}
const INTEGRADORES := ["Euler explícito", "Runge–Kutta 4", "Verlet (simpléctico)"]
const ORDEN_INTEG := [1, 4, 2]
## Exageraciones de la corrección relativista para extrapolar a λ = 1.
const LAMBDAS := [0.0, 1.0e4, 2.0e4, 3.0e4, 4.0e4]

## Lo que predice la relatividad general (″ por siglo): Δϖ = 6πGM/(c²a(1 − e²)) por vuelta.
static func precesion_teorica() -> float:
	var a: float = MERCURIO["a"]
	var e: float = MERCURIO["e"]
	return 6.0 * PI * GM / (C_LUZ * C_LUZ * a * (1.0 - e * e)) * SIGLO / periodo(a) * ARCSEG

## Estado inicial [x, y, vx, vy] de Mercurio en el perihelio (UA, UA/día).
static func mercurio_inicial() -> PackedFloat64Array:
	var a: float = MERCURIO["a"]
	var e: float = MERCURIO["e"]
	var q := a * (1.0 - e)
	return PackedFloat64Array([q, 0.0, 0.0, sqrt(GM * (1.0 + e) / q)])

## β = 3λL²/c²: la aceleración es −GM·r/r³·(1 + β/r²), la corrección de Schwarzschild a primer
## orden exagerada λ veces. L (momento angular por unidad de masa) se conserva en una fuerza
## central, así que se toma del estado inicial y la fuerza depende solo de la posición.
static func beta(lam: float, s: PackedFloat64Array) -> float:
	var L := s[0] * s[3] - s[1] * s[2]
	return 3.0 * lam * L * L / (C_LUZ * C_LUZ)

## Energía por unidad de masa con el potencial de esa fuerza: v²/2 − GM/r − GMβ/(3r³).
static func energia(s: PackedFloat64Array, b: float) -> float:
	var r := sqrt(s[0] * s[0] + s[1] * s[1])
	return 0.5 * (s[2] * s[2] + s[3] * s[3]) - GM / r - GM * b / (3.0 * r * r * r)

## Factor de la aceleración: a = factor·r (vector).
static func _fac(x: float, y: float, b: float) -> float:
	var r2 := x * x + y * y
	return -GM * (1.0 + b / r2) / (r2 * sqrt(r2))

## Un paso del integrador: 0 Euler explícito, 1 RK4, 2 Verlet de velocidad.
static func paso(s: PackedFloat64Array, h: float, b: float, integ: int) -> PackedFloat64Array:
	var x := s[0]
	var y := s[1]
	var vx := s[2]
	var vy := s[3]
	var f := _fac(x, y, b)
	match integ:
		0:
			return PackedFloat64Array([x + h * vx, y + h * vy, vx + h * f * x, vy + h * f * y])
		2:
			var vxh := vx + 0.5 * h * f * x
			var vyh := vy + 0.5 * h * f * y
			var xn := x + h * vxh
			var yn := y + h * vyh
			var fn := _fac(xn, yn, b)
			return PackedFloat64Array([xn, yn, vxh + 0.5 * h * fn * xn, vyh + 0.5 * h * fn * yn])
	var x2 := x + 0.5 * h * vx
	var y2 := y + 0.5 * h * vy
	var vx2 := vx + 0.5 * h * f * x
	var vy2 := vy + 0.5 * h * f * y
	var f2 := _fac(x2, y2, b)
	var x3 := x + 0.5 * h * vx2
	var y3 := y + 0.5 * h * vy2
	var vx3 := vx + 0.5 * h * f2 * x2
	var vy3 := vy + 0.5 * h * f2 * y2
	var f3 := _fac(x3, y3, b)
	var x4 := x + h * vx3
	var y4 := y + h * vy3
	var vx4 := vx + h * f3 * x3
	var vy4 := vy + h * f3 * y3
	var f4 := _fac(x4, y4, b)
	return PackedFloat64Array([x + h / 6.0 * (vx + 2.0 * vx2 + 2.0 * vx3 + vx4),
		y + h / 6.0 * (vy + 2.0 * vy2 + 2.0 * vy3 + vy4),
		vx + h / 6.0 * (f * x + 2.0 * f2 * x2 + 2.0 * f3 * x3 + f4 * x4),
		vy + h / 6.0 * (f * y + 2.0 * f2 * y2 + 2.0 * f3 * y3 + f4 * y4)])

## Perihelio entre tres pasos con r₀ > r₁ ≤ r₂ (pasos de h): el vértice de la parábola por
## (−h, r₀), (0, r₁), (h, r₂) da el instante τ y el ángulo se interpola en τ con la parábola por
## θ₀, θ₁, θ₂ (Lagrange cuadrática). [τ, θ(τ)].
static func perihelio(h: float, r0: float, r1: float, r2: float, th0: float, th1: float, th2: float) -> PackedFloat64Array:
	var den := r0 - 2.0 * r1 + r2
	var tau := 0.5 * h * (r0 - r2) / den if den > 0.0 else 0.0
	return PackedFloat64Array([tau, th1 + tau * (th2 - th0) / (2.0 * h) + tau * tau * (th2 - 2.0 * th1 + th0) / (2.0 * h * h)])

## Integra «vueltas» órbitas y mide la longitud ϖ de cada perihelio. La precesión (″/siglo) es la
## pendiente de la recta de mínimos cuadrados de ϖ(t). También la deriva máxima de energía.
static func medir_precesion(integ: int, h: float, lam: float, vueltas: float) -> Dictionary:
	var s := mercurio_inicial()
	var b := beta(lam, s)
	var e0 := energia(s, b)
	var n := int(vueltas * periodo(MERCURIO["a"]) / h)
	var r0 := sqrt(s[0] * s[0] + s[1] * s[1])
	var r1 := r0
	var th0 := 0.0
	var th1 := 0.0
	var vueltas_th := 0.0
	var peris := []
	var deriva := 0.0
	for k in n:
		s = paso(s, h, b, integ)
		var r2 := sqrt(s[0] * s[0] + s[1] * s[1])
		var th := atan2(s[1], s[0]) + vueltas_th
		if th < th1 - PI:
			vueltas_th += TAU
			th += TAU
		if r1 < r0 and r1 <= r2:
			var p := perihelio(h, r0, r1, r2, th0, th1, th)
			peris.append([k * h + p[0], p[1] - TAU * (peris.size() + 1)])   # r₁ es el estado en t = k·h
		if k % 16 == 0:
			deriva = maxf(deriva, absf((energia(s, b) - e0) / e0))
		r0 = r1
		r1 = r2
		th0 = th1
		th1 = th
		if not is_finite(r2):
			break
	var prec := NAN
	if peris.size() >= 2:
		prec = recta(peris)[0] * SIGLO * ARCSEG
	return {"perihelios": peris, "precesion": prec, "deriva": deriva}

## La precesión con λ = 1, de la precesión medida con varios λ: P(λ) ≈ c₀ + c₁λ + c₂λ². El término
## c₁ es la predicción (″/siglo por unidad de λ); c₀, la precesión que inventa el propio
## integrador (con λ = 0), queda descontada, y c₂ absorbe la no linealidad de exagerar tanto.
## Ajuste por mínimos cuadrados (ecuaciones normales 3×3 por Cholesky, con λ en unidades de 10⁴);
## también la recta, para ver cuánto la sesga esa curvatura.
static func extrapolar(integ: int, h: float, vueltas: float, lams: Array = LAMBDAS) -> Dictionary:
	var pts := []
	var ok := true
	for lam in lams:
		var p := float(medir_precesion(integ, h, float(lam), vueltas)["precesion"])
		ok = ok and is_finite(p)
		pts.append([float(lam), p])
	var res := {"puntos": pts, "teorico": precesion_teorica(), "resultado": NAN, "recta": NAN, "ordenada": NAN}
	if not ok or pts.size() < 3:
		return res
	var N := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	var b := [0.0, 0.0, 0.0]
	for p in pts:
		var x := float(p[0]) / 1e4
		var fila := [1.0, x, x * x]
		for i in 3:
			for j in 3:
				N[i][j] += fila[i] * fila[j]
			b[i] += fila[i] * float(p[1])
	var c := cholesky3(N, b)
	if c.size() == 3:
		res["resultado"] = c[1] / 1e4
		res["ordenada"] = c[0]
		res["c2"] = c[2] / 1e8
	res["recta"] = recta(pts)[0]
	return res
