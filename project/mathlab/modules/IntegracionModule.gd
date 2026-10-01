extends LabModule
## Integración y derivación numéricas en 2D sobre la misma f(x, y).
##
##   Integración doble ∬_R f dA en una región R: a ≤ x ≤ b, c(x) ≤ y ≤ d(x)
##   (rectángulo, triángulo, disco, entre dos curvas…). La región se lleva al
##   cuadrado unidad con x = a + u(b − a), y = c(x) + v(d(x) − c(x)) y el jacobiano
##   (b − a)(d(x) − c(x)); ahí se aplican 19 métodos: reglas producto compuestas
##   (rectángulo, punto medio, trapecio, Simpson 1/3 y 3/8, Boole, Gauss–Legendre y
##   Gauss–Lobatto con p nodos), Romberg y Clenshaw–Curtis producto, una cubatura de
##   7 puntos de grado 5, integración iterada adaptativa (Gauss–Kronrod, Simpson y
##   tanh-sinh), la cubatura adaptativa de Genz–Malik y Monte Carlo (simple,
##   estratificado, Halton y retícula de Fibonacci). Superficie sobre la región,
##   prismas con lo que suma cada celda, nodos de evaluación, tabla con error,
##   evaluaciones y orden observado, y gráfica del error frente a las evaluaciones.
##
##   Derivación parcial en (x₀, y₀): ∂f/∂x, ∂f/∂y, ∂²f/∂x², ∂²f/∂y², ∂²f/∂x∂y,
##   laplaciano, |∇f| y derivada direccional con 11 métodos: diferencias hacia
##   delante, atrás y centradas de 3, 5 y 7 puntos, Richardson, paso complejo,
##   diferenciación automática, derivada simbólica, plantilla de 9 puntos (Sobel y
##   laplaciano isótropo) y ajuste cuadrático por mínimos cuadrados. Plano tangente,
##   gradiente, cortes por P, puntos de la plantilla y error frente a h (con ruido
##   opcional en f).

const SIZE := 4.0
const HEIGHT := 1.6
const GRID := 90
const BUDGET := 600000          # evaluaciones máximas de un método (se corta y se avisa)
const ADAPTIVE_BUDGET := 250000 # por intento de las adaptativas (luego se relaja la tolerancia)

# --- Integración ---------------------------------------------------------------------------

const INT_METHODS := ["Rectángulo (esquina)", "Punto medio", "Trapecio", "Simpson 1/3", "Simpson 3/8", "Boole",
	"Romberg (iterada)", "Gauss–Legendre p × p", "Gauss–Lobatto p × p", "Clenshaw–Curtis (producto)",
	"Cubatura de 7 puntos (grado 5)", "Gauss–Kronrod adaptativa (iterada)", "Simpson adaptativa (iterada)",
	"Tanh-sinh (iterada)", "Genz–Malik adaptativa (2D)", "Monte Carlo", "Monte Carlo estratificado",
	"Cuasi-Monte Carlo (Halton)", "Retícula de Fibonacci"]
const INT_SHORT := ["Rectángulo", "Punto medio", "Trapecio", "Simpson 1/3", "Simpson 3/8", "Boole", "Romberg",
	"Gauss–Legendre", "Gauss–Lobatto", "Clenshaw–Curtis", "Cubatura 7 p.", "Gauss–Kronrod it.", "Simpson adapt. it.",
	"Tanh-sinh it.", "Genz–Malik", "Monte Carlo", "MC estratificado", "Halton", "Fibonacci"]
const INT_ORDER := ["1", "2", "2", "4", "4", "6", "2k", "2p", "2p − 2", "espectral", "6", "adaptativa", "adaptativa",
	"doble exp.", "adaptativa", "N^(−1/2)", "N^(−1)", "≈ N^(−1)", "≈ N^(−1)"]
const INT_FORMULAS := [
	"∬ ≈ Σᵢⱼ f(xᵢ, yⱼ) ΔxΔy (esquina inferior izquierda de cada celda)",
	"∬ ≈ Σᵢⱼ f(x̄ᵢ, ȳⱼ) ΔxΔy (centro de cada celda)",
	"∬ ≈ ΔxΔy/4 · Σ esquinas de cada celda (pesos ½ en los bordes)",
	"∬ ≈ ΔxΔy/9 · Σ wᵢwⱼ f,  w = 1, 4, 2, 4, …, 4, 1",
	"∬ ≈ 9ΔxΔy/64 · Σ wᵢwⱼ f,  w = 1, 3, 3, 2, 3, 3, …, 1",
	"∬ ≈ (2/45)² ΔxΔy · Σ wᵢwⱼ f,  w = 7, 32, 12, 32, 7",
	"Romberg en y dentro de Romberg en x (Richardson sobre trapecios)",
	"∬ ≈ Σᵢⱼ wᵢwⱼ f(xᵢ, yⱼ) con los p nodos de Gauss–Legendre en cada celda",
	"Gauss–Lobatto: incluye los bordes de cada celda; exacta hasta grado 2p − 3",
	"Producto de nodos de Chebyshev xₖ = −cos(kπ/N) con pesos de Clenshaw–Curtis",
	"7 nodos por celda: centro (8/7), (0, ±√(14/15)) (20/63), (±√(3/5), ±√(1/3)) (5/9)",
	"∫ₐᵇ [∫ f dy] dx, cada integral con Gauss–Kronrod 7–15 adaptativa",
	"∫ₐᵇ [∫ f dy] dx, cada integral con Simpson adaptativa",
	"∫ₐᵇ [∫ f dy] dx, cada integral con la regla doble exponencial tanh-sinh",
	"Regla de grado 7 (17 nodos) con una de grado 5 embebida; se parte la subregión con más error",
	"∬ ≈ área · (1/N) Σ f(pₖ), pₖ al azar;  σ ≈ área · s/√N",
	"Un punto al azar en cada una de las m × m celdas (N = m²)",
	"Puntos de Halton (van der Corput en bases 2 y 3): baja discrepancia",
	"Retícula de rango 1: pₖ = (k/F, {k·F′/F}) con F, F′ números de Fibonacci",
]
const INT_DESCS := [
	"Evalúa f en una esquina de cada celda: el error es de orden 1 (se divide solo entre 2 al duplicar n).",
	"Evalúa f en el centro de cada celda. Orden 2: el error se divide entre 4 al duplicar n.",
	"Media de las cuatro esquinas de cada celda. Orden 2, con el error de signo contrario al del punto medio.",
	"Producto de la regla de Simpson en x y en y: exacta para polinomios cúbicos en cada variable; orden 4.",
	"Simpson 3/8 en cada dirección: orden 4, con paneles de 3 subintervalos.",
	"Boole (Newton–Cotes de 5 puntos) en cada dirección: orden 6.",
	"Romberg 1D anidado: extrapola trapecios con h, h/2, h/4… Con funciones suaves, precisión altísima con pocos niveles.",
	"p × p nodos de Gauss–Legendre por celda: exacta para polinomios de grado 2p − 1 en cada variable; orden 2p.",
	"Como Gauss pero con los extremos de cada celda entre los nodos (se comparten con la celda vecina).",
	"Nodos de Chebyshev en todo el dominio: converge exponencialmente con funciones analíticas, sin celdas.",
	"Cubatura no producto: 7 nodos en lugar de los 9 de Gauss 3 × 3 con el mismo grado 5.",
	"Integral iterada: la integral en y de cada nodo x es a su vez adaptativa. Sigue bien los bordes curvos y las singularidades.",
	"Integral iterada con Simpson adaptativa en cada dirección.",
	"Tanh-sinh concentra los nodos en los bordes: la mejor opción con singularidades en el contorno (1/√x, esquinas).",
	"Cubatura adaptativa genuinamente 2D: parte en dos la subregión con más error estimado (|grado 7 − grado 5|).",
	"Monte Carlo: el error baja solo como 1/√N, pero no depende de la dimensión ni de la suavidad.",
	"Estratificado: un punto por celda reduce la varianza; en 2D el error baja como N^(−1).",
	"Halton: puntos repartidos sin huecos (baja discrepancia); error ≈ (log N)²/N.",
	"Retícula de Fibonacci: muy regular; con funciones periódicas converge aún más rápido.",
]
const PANEL_RULES := [0, 1, 2, 3, 4, 5, 7, 8]
const ADAPTIVE := [11, 12, 13, 14]
const SAMPLING := [15, 16, 17, 18]
const INT_PRESETS := [
	{"nombre": "Campana gaussiana", "f": "exp(-(x^2 + y^2))", "a": "-2", "b": "2", "c": "-2", "d": "2", "exacto": 3.112270319717472},
	{"nombre": "Seno por coseno + 1", "f": "sin x cos y + 1", "a": "0", "b": "pi", "c": "-pi/2", "d": "pi/2", "exacto": 13.869604401089358},
	{"nombre": "Paraboloide", "f": "4 - x^2 - y^2", "a": "-1.5", "b": "1.5", "c": "-1.5", "d": "1.5", "exacto": 22.5},
	{"nombre": "Oscilante", "f": "1 + 0.5 sin(3x) sin(3y)", "a": "-2", "b": "2", "c": "-2", "d": "2", "exacto": 16.0},
	{"nombre": "Pirámide 2 − |x| − |y|", "f": "2 - abs(x) - abs(y)", "a": "-1", "b": "1", "c": "-1", "d": "1", "exacto": 4.0},
	{"nombre": "Triángulo: x·y con 0 ≤ y ≤ x", "f": "x y", "a": "0", "b": "1", "c": "0", "d": "x", "exacto": 0.125},
	{"nombre": "Área del disco unidad (f = 1)", "f": "1", "a": "-1", "b": "1", "c": "-sqrt(1 - x^2)", "d": "sqrt(1 - x^2)", "exacto": PI},
	{"nombre": "Entre y = x² e y = √x", "f": "x + y", "a": "0", "b": "1", "c": "x^2", "d": "sqrt(x)", "exacto": 0.3},
	{"nombre": "Semiesfera sobre el disco", "f": "sqrt(max(0, 1 - x^2 - y^2))", "a": "-1", "b": "1", "c": "-sqrt(1 - x^2)", "d": "sqrt(1 - x^2)", "exacto": 2.0943951023931953},
	{"nombre": "Singular en el origen: 1/√(x² + y²)", "f": "1/sqrt(x^2 + y^2)", "a": "0", "b": "1", "c": "0", "d": "1", "exacto": 1.7627471740390859},
]
# Cubatura de 7 puntos de grado 5 en [−1, 1]² (Albrecht–Collatz): [ξ, η, peso].
const CUB7 := [[0.0, 0.0, 1.1428571428571428], [0.0, 0.9660917830792959, 0.31746031746031744],
	[0.0, -0.9660917830792959, 0.31746031746031744], [0.7745966692414834, 0.5773502691896257, 0.5555555555555556],
	[-0.7745966692414834, 0.5773502691896257, 0.5555555555555556], [0.7745966692414834, -0.5773502691896257, 0.5555555555555556],
	[-0.7745966692414834, -0.5773502691896257, 0.5555555555555556]]
# Genz–Malik en 2D (pesos para el cuadrado [−1, 1]² normalizados a 1).
const GM_L2 := 0.3585685828003181       # √(9/70)
const GM_L3 := 0.9486832980505138       # √(9/10)
const GM_L5 := 0.6882472016116853       # √(9/19)
# (fracciones exactas: un solo dígito mal copiado deja un error fijo que no baja al refinar)
const GM_W := [-424.0 / 2187.0, 980.0 / 6561.0, 340.0 / 6561.0, 200.0 / 19683.0, 6859.0 / 78732.0]
const GM_V := [-971.0 / 729.0, 245.0 / 486.0, 65.0 / 1458.0, 25.0 / 729.0]

# --- Derivación ----------------------------------------------------------------------------

const TARGETS := ["∂f/∂x", "∂f/∂y", "∂²f/∂x²", "∂²f/∂y²", "∂²f/∂x∂y", "Laplaciano ∇²f", "|∇f| (módulo del gradiente)", "Derivada direccional D_u f"]
const TSYM := ["∂f/∂x", "∂f/∂y", "∂²f/∂x²", "∂²f/∂y²", "∂²f/∂x∂y", "∇²f", "|∇f|", "D_u f"]
const DIFF_METHODS := ["Diferencia hacia delante", "Diferencia hacia atrás", "Diferencia centrada", "Centrada de 5 puntos",
	"Centrada de 7 puntos", "Extrapolación de Richardson", "Paso complejo", "Diferenciación automática",
	"Derivada simbólica", "Plantilla de 9 puntos (Sobel / isótropa)", "Ajuste cuadrático (mínimos cuadrados 5 × 5)"]
const DIFF_SHORT := ["Adelante", "Atrás", "Centrada", "Centrada 5p", "Centrada 7p", "Richardson", "Paso complejo",
	"Automática", "Simbólica", "9 puntos", "Mín. cuadrados"]
const DIFF_ORDER := ["1", "1", "2", "4", "6", "2·niveles", "2", "exacta", "exacta", "2", "2"]
const EXACT_METHODS := [7, 8]
const STENCILS := ["adelante", "atras", "centrada", "centrada5", "centrada7"]
const DIFF_F1 := [
	"[f(x + h, y) − f(x, y)] / h",
	"[f(x, y) − f(x − h, y)] / h",
	"[f(x + h, y) − f(x − h, y)] / 2h",
	"[−f(x+2h) + 8f(x+h) − 8f(x−h) + f(x−2h)] / 12h",
	"[f(x+3h) − 9f(x+2h) + 45f(x+h) − 45f(x−h) + 9f(x−2h) − f(x−3h)] / 60h",
	"R(h/2) + [R(h/2) − R(h)] / (4ʲ − 1) sobre la centrada",
	"Im f(x + ih, y) / h",
	"exacta con números duales (a + bε, ε² = 0)",
	"de la fórmula derivada simbólicamente",
	"Sobel: [f(x+h, y+h) + 2f(x+h, y) + f(x+h, y−h) − (ídem en x − h)] / 8h",
	"z = a + bx + cy + dx² + exy + fy² ajustado en 5 × 5 puntos → b",
]
const DIFF_F2 := [
	"[f(x+2h) − 2f(x+h) + f(x)] / h²",
	"[f(x) − 2f(x−h) + f(x−2h)] / h²",
	"[f(x+h) − 2f(x) + f(x−h)] / h²",
	"[−f(x+2h) + 16f(x+h) − 30f(x) + 16f(x−h) − f(x−2h)] / 12h²",
	"plantilla de 7 puntos (orden 6) / 180h²",
	"R(h/2) + [R(h/2) − R(h)] / (4ʲ − 1) sobre la centrada",
	"2[f(x, y) − Re f(x + ih, y)] / h²",
	"exacta con duales de 2.º orden",
	"de la fórmula derivada simbólicamente",
	"[1 −2 1] en x suavizado en y con pesos 1, 10, 1 (/12h²)",
	"ajuste cuadrático → 2d",
]
const DIFF_DESCS := [
	"Un lado de la plantilla: error de orden 1. Sirve en un borde del dominio.",
	"Como hacia delante, con los puntos detrás.",
	"Simétrica: se cancelan los términos pares y el error es de orden 2 (÷4 al dividir h entre 2).",
	"Cinco puntos por dirección: orden 4. Con h muy pequeño domina el redondeo, que crece como ε/h.",
	"Siete puntos por dirección: orden 6.",
	"Combina la centrada con h, h/2, h/4…: cada nivel sube el orden en 2.",
	"Evalúa f con un número complejo: la primera derivada no resta números parecidos, así que h puede ser minúsculo (10⁻¹⁶) sin redondeo.",
	"Números duales de 2.º orden: la derivada exacta hasta el redondeo, sin ningún h.",
	"Deriva la fórmula (regla de la cadena, del producto…) y la evalúa en P. La mixta es la derivada de ∂f/∂x respecto de y.",
	"Usa la vecindad 3 × 3: Sobel suaviza la derivada en la otra dirección y el laplaciano isótropo trata igual todas las direcciones.",
	"Ajusta un paraboloide a 25 puntos por mínimos cuadrados: promedia el ruido de f a cambio de algo de sesgo (orden 2).",
]
const DIFF_PRESETS := [
	{"nombre": "Silla x² − y²", "f": "x^2 - y^2", "x0": 1.0, "y0": 0.5, "win": [-2.0, 2.0, -2.0, 2.0]},
	{"nombre": "Campana e^(−(x² + y²))", "f": "exp(-(x^2 + y^2))", "x0": 0.5, "y0": 0.3, "win": [-2.0, 2.0, -2.0, 2.0]},
	{"nombre": "sin x · cos y", "f": "sin x cos y", "x0": 0.7, "y0": 1.1, "win": [-3.2, 3.2, -3.2, 3.2]},
	{"nombre": "Polinomio x³y + y²", "f": "x^3 y + y^2", "x0": 1.0, "y0": 2.0, "win": [-2.0, 2.5, -1.0, 3.0]},
	{"nombre": "ln(1 + x² + y²)", "f": "ln(1 + x^2 + y^2)", "x0": 1.0, "y0": 1.0, "win": [-2.0, 2.0, -2.0, 2.0]},
	{"nombre": "Rosenbrock", "f": "(1 - x)^2 + 100(y - x^2)^2", "x0": 0.5, "y0": 0.5, "win": [-1.5, 1.5, -0.5, 2.0]},
	{"nombre": "Armónica e^x sin y (∇²f = 0)", "f": "exp(x) sin y", "x0": 0.3, "y0": 1.0, "win": [-1.5, 1.5, -1.0, 3.0]},
]

var mode: int = 0
var f_expr: MathExpr
var dx_e: MathExpr
var dy_e: MathExpr
var dxx_e: MathExpr
var dyy_e: MathExpr
var dxy_e: MathExpr
# Región
var ipreset: int = 0
var a: float = -2.0
var b: float = 2.0
var a_text: String = "-2"
var b_text: String = "2"
var c_text: String = "-2"
var d_text: String = "2"
var c_expr: MathExpr
var d_expr: MathExpr
var c_const: float = NAN          # c(x) constante (NAN si depende de x)
var d_const: float = NAN
var imethod: int = 7
var n: int = 8
var gp: int = 3
var tol_exp: float = -8.0
var mc_exp: float = 3.0
var exact: float = NAN
var reference: float = NAN
var ref_src: String = ""
var region_area: float = NAN
var flipped: bool = false        # d(x) < c(x) en parte de [a, b]
# Derivación
var dpreset: int = 0
var dmethod: int = 2
var target: int = 0
var x0: float = 1.0
var y0: float = 0.5
var theta_deg: float = 30.0
var h_exp: float = -3.0
var levels: int = 3
var noise_exp: float = -17.0
var wx := Vector2(-2, 2)
var wy := Vector2(-2, 2)
# Resultados
var compare: bool = false
var rows: Array = []
var sel: Dictionary = {}
var conv: Array = []              # [[método, [[x, log₁₀ error], …]], …]
var h_opt: float = NAN
var e_opt: float = NAN
# Evaluación
var _ev: int = 0
var _budget: int = BUDGET
var _over: bool = false
var _cache: Dictionary = {}
var _rec: Array = []
var _recording: bool = false
# Dibujo
var bx := Vector2(-2, 2)         # caja de la región (o ventana) en x e y
var by := Vector2(-2, 2)
var zr := Vector2(0, 1)
var surf: MeshInstance3D
var deco: Node3D
var prisms: MultiMeshInstance3D
var dots: MultiMeshInstance3D
var plot: Control
var _panel: VBoxContainer
var _ui := {}
var _desc: Label

func title() -> String: return "Integración y derivación (2D)"
func perturb_hint() -> String:
	return "clic: aumenta n (Mayús+clic: lo reduce)" if mode == 0 else "clic sobre la superficie: elige el punto P = (x₀, y₀)"
func view() -> Dictionary: return {"target": Vector3(0, 0.45, 0), "dist": 7.4, "yaw": -35.0, "pitch": -30.0}

func formula() -> String:
	if mode == 0:
		return INT_FORMULAS[imethod]
	var body: String
	if target in [0, 1, 6, 7]:
		body = DIFF_F1[dmethod]
	elif target in [2, 3]:
		body = DIFF_F2[dmethod]
	elif target == 4:
		body = "[f(x+h, y+h) − f(x+h, y−h) − f(x−h, y+h) + f(x−h, y−h)] / 4h²" if dmethod == 2 else \
			("(NE − NO − SE + SO) / 4h²" if dmethod == 9 else DIFF_F1[dmethod] + " (en x y luego en y)")
	else:
		body = "[f(x±h, y) + f(x, y±h) − 4f(x, y)] / h²" if dmethod == 2 else \
			("[4(N + S + E + O) + esquinas − 20f] / 6h²" if dmethod == 9 else "∂²f/∂x² + ∂²f/∂y², cada una con: " + DIFF_F2[dmethod])
	return "%s ≈ %s" % [TSYM[target], body]

func setup() -> void:
	surf = MeshInstance3D.new()
	add_child(surf)
	prisms = MultiMeshInstance3D.new()
	add_child(prisms)
	dots = MultiMeshInstance3D.new()
	add_child(dots)
	deco = Node3D.new()
	add_child(deco)
	_load_int(0)

# --- Función, región y derivadas -----------------------------------------------------------

func set_f(m: MathExpr, keep_exact: bool = false) -> void:
	f_expr = m
	f_expr.compile_fast()
	dx_e = f_expr.derivative("x")
	dy_e = f_expr.derivative("y")
	dxx_e = dx_e.derivative("x") if dx_e.ok() else dx_e
	dyy_e = dy_e.derivative("y") if dy_e.ok() else dy_e
	dxy_e = dx_e.derivative("y") if dx_e.ok() else dx_e
	for e in [dx_e, dy_e, dxx_e, dyy_e, dxy_e]:
		if e.ok():
			e.compile_fast()
	if not keep_exact:
		exact = NAN
	_region_changed()

func F(x: float, y: float) -> float:
	var v := f_expr.eval_fast([x, y])
	return v if not is_nan(v) else f_expr.eval_real({"x": x, "y": y})

func _set_limit(which: String, m: MathExpr) -> void:
	var k := MathExpr.parse(m.source, [])
	var cv := k.eval_real({}) if k.ok() else NAN
	m.compile_fast()
	if which == "c":
		c_expr = m
		c_text = m.source
		c_const = cv
	else:
		d_expr = m
		d_text = m.source
		d_const = cv

func C(x: float) -> float:
	return c_const if not is_nan(c_const) else c_expr.eval_fast([x])

func D(x: float) -> float:
	return d_const if not is_nan(d_const) else d_expr.eval_fast([x])

## Integrando en el cuadrado unidad: f(x(u), y(u, v)) · (b − a)(d(x) − c(x)).
func G(u: float, v: float) -> float:
	_ev += 1
	if _ev > _budget:
		_over = true
		return 0.0
	if _recording and _rec.size() < 12000:
		_rec.append(Vector2(u, v))
	var x := a + u * (b - a)
	var cy := C(x)
	var dd := D(x) - cy
	return F(x, cy + v * dd) * (b - a) * dd

func _Gc(u: float, v: float) -> float:
	var key := Vector2(u, v)
	if _cache.has(key):
		return _cache[key]
	var g := G(u, v)
	_cache[key] = g
	return g

func J(u: float) -> float:
	var x := a + u * (b - a)
	return (b - a) * (D(x) - C(x))

func _preset_region() -> bool:
	var p: Dictionary = INT_PRESETS[ipreset]
	return f_expr != null and f_expr.source == p["f"] and a_text == p["a"] and b_text == p["b"] and c_text == p["c"] and d_text == p["d"]

func _load_int(i: int) -> void:
	ipreset = clampi(i, 0, INT_PRESETS.size() - 1)
	var p: Dictionary = INT_PRESETS[ipreset]
	a_text = p["a"]
	b_text = p["b"]
	a = MathExpr.parse(a_text, []).eval_real({})
	b = MathExpr.parse(b_text, []).eval_real({})
	_set_limit("c", MathExpr.parse(p["c"], ["x"]))
	_set_limit("d", MathExpr.parse(p["d"], ["x"]))
	exact = float(p["exacto"])
	set_f(MathExpr.parse(p["f"], ["x", "y"]), true)
	if mode == 0 and _ui.has("a"):
		for k in [["f", p["f"]], ["a", a_text], ["b", b_text], ["c", p["c"]], ["d", p["d"]]]:
			var e: LineEdit = _ui[k[0]]
			e.text = k[1]
			e.text_changed.emit(k[1])

func _load_diff(i: int) -> void:
	dpreset = clampi(i, 0, DIFF_PRESETS.size() - 1)
	var p: Dictionary = DIFF_PRESETS[dpreset]
	x0 = p["x0"]
	y0 = p["y0"]
	wx = Vector2(p["win"][0], p["win"][1])
	wy = Vector2(p["win"][2], p["win"][3])
	set_f(MathExpr.parse(p["f"], ["x", "y"]))
	if mode == 1 and _panel:
		call_deferred("_rebuild_ui")

func set_mode(i: int) -> void:
	mode = clampi(i, 0, 1)
	if mode == 0:
		_load_int(ipreset)
	else:
		_load_diff(dpreset)
	if _panel:
		call_deferred("_rebuild_ui")
	if lab:
		lab._update_info(false)
		lab._status("%s — %s" % [title(), perturb_hint()])

func _rebuild_ui() -> void:
	if not is_instance_valid(_panel):
		return
	for k in range(_panel.get_child_count() - 1, 0, -1):
		var c := _panel.get_child(k)
		_panel.remove_child(c)
		c.queue_free()
	_ui.clear()
	build_ui(_panel)

## Cambió f o la región: caja, referencia y todo lo demás.
func _region_changed() -> void:
	if f_expr == null or not f_expr.ok():
		return
	if mode == 0:
		var lo := INF
		var hi := -INF
		flipped = false
		for k in range(201):
			var x := lerpf(a, b, k / 200.0)
			var cy := C(x)
			var dy := D(x)
			if is_finite(cy) and is_finite(dy):
				lo = minf(lo, minf(cy, dy))
				hi = maxf(hi, maxf(cy, dy))
				if dy < cy - 1e-12:
					flipped = true
		if not (is_finite(lo) and is_finite(hi)) or hi - lo < 1e-9:
			lo = -1.0 if not is_finite(lo) else lo - 0.5
			hi = lo + 1.0
		bx = Vector2(minf(a, b), maxf(a, b))
		by = Vector2(lo, hi)
		region_area = float(Quadrature.gauss_kronrod(func(x: float) -> float: return D(x) - C(x), a, b, 1e-12, 200)["valor"])
		_compute_reference()
	else:
		bx = wx
		by = wy
	_changed()

func _compute_reference() -> void:
	if not is_nan(exact) and _preset_region():
		reference = exact
		ref_src = "exacto"
		return
	var r := run_int(11, n, 1e-11, 1000)
	reference = float(r.get("valor", NAN))
	ref_src = "Gauss–Kronrod iterada, tol 10^%d" % int(round(log(float(r.get("tol_usada", 1e-11))) / log(10.0)))
	if str(r.get("estado", "ok")) != "ok":
		var r2 := run_int(14, n, 1e-10, 1000)
		reference = float(r2.get("valor", NAN))
		ref_src = "Genz–Malik, tol 10⁻¹⁰"

# --- Integración: métodos en el cuadrado unidad ----------------------------------------------

## Paneles de la regla compuesta «kind» con nn subintervalos en [0, 1]:
## [{lo, hi, pts: [[u, peso], …]}, …].
func _panels(kind: int, nn: int) -> Array:
	var out := []
	match kind:
		0, 1, 2:
			var h := 1.0 / nn
			for k in range(nn):
				var lo := k * h
				var pts: Array
				if kind == 0:
					pts = [[lo, h]]
				elif kind == 1:
					pts = [[lo + 0.5 * h, h]]
				else:
					pts = [[lo, 0.5 * h], [lo + h, 0.5 * h]]
				out.append({"lo": lo, "hi": lo + h, "pts": pts})
		3, 4, 5:
			var per: int = [2, 3, 4][kind - 3]
			var w: Array = [[1.0, 4.0, 1.0], [1.0, 3.0, 3.0, 1.0], [7.0, 32.0, 12.0, 32.0, 7.0]][kind - 3]
			var scale: float = [1.0 / 3.0, 3.0 / 8.0, 2.0 / 45.0][kind - 3]
			var m := int(ceil(float(nn) / per))
			var h := 1.0 / (m * per)
			for k in range(m):
				var lo := k * per * h
				var pts := []
				for i in range(per + 1):
					pts.append([lo + i * h, scale * h * float(w[i])])
				out.append({"lo": lo, "hi": lo + per * h, "pts": pts})
		7, 8:
			var g: Array = Quadrature.gauss_legendre_nodes(gp) if kind == 7 else Quadrature.gauss_lobatto_nodes(maxi(2, gp))
			var h := 1.0 / nn
			for k in range(nn):
				var lo := k * h
				var pts := []
				for i in range((g[0] as Array).size()):
					pts.append([lo + 0.5 * h * (1.0 + float(g[0][i])), 0.5 * h * float(g[1][i])])
				out.append({"lo": lo, "hi": lo + h, "pts": pts})
	return out

## Subintervalos efectivos por lado (Simpson necesita un número par, Boole múltiplo de 4…).
func effective_n(m: int, nn: int) -> int:
	match m:
		3: return int(ceil(nn / 2.0)) * 2
		4: return int(ceil(nn / 3.0)) * 3
		5: return int(ceil(nn / 4.0)) * 4
	return nn

func _tensor(kind: int, nn: int) -> Dictionary:
	var P := _panels(kind, nn)
	var per_dim := 0
	for pn in P:
		per_dim += (pn["pts"] as Array).size()
	if per_dim * per_dim > BUDGET:
		return {"estado": "demasiadas evaluaciones (baja n o p)"}
	var cells := []
	var total := 0.0
	for pu in P:
		for pv in P:
			var s := 0.0
			for q in pu["pts"]:
				for r in pv["pts"]:
					s += float(q[1]) * float(r[1]) * _Gc(q[0], r[0])
			total += s
			cells.append([pu["lo"], pu["hi"], pv["lo"], pv["hi"], s])
	return {"valor": total, "celdas": cells}

func _cub7(nn: int) -> Dictionary:
	var h := 1.0 / nn
	var cells := []
	var total := 0.0
	for j in range(nn):
		for i in range(nn):
			var s := 0.0
			for q in CUB7:
				s += float(q[2]) * G((i + 0.5 * (1.0 + float(q[0]))) * h, (j + 0.5 * (1.0 + float(q[1]))) * h)
			s *= h * h * 0.25
			total += s
			cells.append([i * h, (i + 1) * h, j * h, (j + 1) * h, s])
	return {"valor": total, "celdas": cells}

func _clenshaw(nn: int) -> Dictionary:
	var N := maxi(2, 2 * nn)
	var cc: Array = Quadrature.clenshaw_curtis_nodes(N)
	var total := 0.0
	for j in range(N + 1):
		for i in range(N + 1):
			total += 0.25 * float(cc[1][i]) * float(cc[1][j]) * G(0.5 * (1.0 + float(cc[0][i])), 0.5 * (1.0 + float(cc[0][j])))
	return {"valor": total, "N": N}

func romberg_levels(nn: int) -> int:
	return clampi(1 + int(ceil(log(maxf(1.0, nn)) / log(2.0))), 1, 8)

func _romberg(nn: int) -> Dictionary:
	var L := romberg_levels(nn)
	var inner := func(u: float) -> float:
		return float(Quadrature.romberg(func(v: float) -> float: return G(u, v), 0.0, 1.0, L)["valor"])
	return {"valor": float(Quadrature.romberg(inner, 0.0, 1.0, L)["valor"]), "niveles": L}

## Integral iterada con una regla 1D adaptativa en cada dirección.
func _iterated(kind: int, tol: float) -> Dictionary:
	var rule := func(f: Callable) -> float:
		match kind:
			11: return float(Quadrature.gauss_kronrod(f, 0.0, 1.0, tol, 60)["valor"])
			12: return float(Quadrature.simpson_adaptive(f, 0.0, 1.0, tol, 18)["valor"])
		return float(Quadrature.tanh_sinh(f, 0.0, 1.0, tol, 6)["valor"])
	var inner := func(u: float) -> float:
		return rule.call(func(v: float) -> float: return G(u, v))
	return {"valor": rule.call(inner)}

## Regla de Genz–Malik en la subregión de centro (cx, cy) y semiejes (hx, hy):
## [grado 7, |grado 7 − grado 5|, eje por el que conviene partir].
func _gm(cx: float, cy: float, hx: float, hy: float) -> Array:
	var f0 := G(cx, cy)
	var a2 := [G(cx - GM_L2 * hx, cy), G(cx + GM_L2 * hx, cy), G(cx, cy - GM_L2 * hy), G(cx, cy + GM_L2 * hy)]
	var a3 := [G(cx - GM_L3 * hx, cy), G(cx + GM_L3 * hx, cy), G(cx, cy - GM_L3 * hy), G(cx, cy + GM_L3 * hy)]
	var s4 := G(cx - GM_L3 * hx, cy - GM_L3 * hy) + G(cx + GM_L3 * hx, cy - GM_L3 * hy) + G(cx - GM_L3 * hx, cy + GM_L3 * hy) + G(cx + GM_L3 * hx, cy + GM_L3 * hy)
	var s5 := G(cx - GM_L5 * hx, cy - GM_L5 * hy) + G(cx + GM_L5 * hx, cy - GM_L5 * hy) + G(cx - GM_L5 * hx, cy + GM_L5 * hy) + G(cx + GM_L5 * hx, cy + GM_L5 * hy)
	var s2: float = a2[0] + a2[1] + a2[2] + a2[3]
	var s3: float = a3[0] + a3[1] + a3[2] + a3[3]
	var vol := 4.0 * hx * hy
	var i7 := vol * (float(GM_W[0]) * f0 + float(GM_W[1]) * s2 + float(GM_W[2]) * s3 + float(GM_W[3]) * s4 + float(GM_W[4]) * s5)
	var i5 := vol * (float(GM_V[0]) * f0 + float(GM_V[1]) * s2 + float(GM_V[2]) * s3 + float(GM_V[3]) * s4)
	# Cuarta diferencia en cada eje (sin la parte cuadrática): dónde cambia más f.
	var ddx := absf(float(a2[0]) + float(a2[1]) - 2.0 * f0 - (float(a3[0]) + float(a3[1]) - 2.0 * f0) / 7.0)
	var ddy := absf(float(a2[2]) + float(a2[3]) - 2.0 * f0 - (float(a3[2]) + float(a3[3]) - 2.0 * f0) / 7.0)
	var axis := 0 if ddx > ddy or (ddx == ddy and hx >= hy) else 1
	return [i7, absf(i7 - i5), axis]

func _genz(tol: float) -> Dictionary:
	var r0 := _gm(0.5, 0.5, 0.5, 0.5)
	var regs := [[0.5, 0.5, 0.5, 0.5, r0[0], r0[1], r0[2]]]
	var total: float = r0[0]
	var err: float = r0[1]
	while err > tol * maxf(1.0, absf(total)) and regs.size() < 4000 and not _over:
		# Se parten a la vez todas las subregiones con al menos la mitad del error máximo
		# (elegirlas de una en una costaría O(regiones²)).
		var emax := 0.0
		for rg0 in regs:
			emax = maxf(emax, float(rg0[5]))
		var keep := []
		var split := []
		for rg1 in regs:
			(split if float(rg1[5]) >= 0.5 * emax else keep).append(rg1)
		regs = keep
		for rg in split:
			_split_gm(rg, regs)
		total = 0.0
		err = 0.0
		for rg2 in regs:
			total += float(rg2[4])
			err += float(rg2[5])
	var cells := []
	for rg in regs:
		cells.append([float(rg[0]) - float(rg[2]), float(rg[0]) + float(rg[2]), float(rg[1]) - float(rg[3]), float(rg[1]) + float(rg[3]), rg[4]])
	return {"valor": total, "error_est": maxf(0.0, err), "celdas": cells, "regiones": regs.size()}

## Parte la subregión rg [cx, cy, hx, hy, valor, error, eje] en dos mitades por su eje.
func _split_gm(rg: Array, regs: Array) -> void:
	for sgn in [-1.0, 1.0]:
		if int(rg[6]) == 0:
			var hx: float = float(rg[2]) * 0.5
			var cx: float = float(rg[0]) + sgn * hx
			var rr := _gm(cx, rg[1], hx, rg[3])
			regs.append([cx, rg[1], hx, rg[3], rr[0], rr[1], rr[2]])
		else:
			var hy: float = float(rg[3]) * 0.5
			var cy: float = float(rg[1]) + sgn * hy
			var rr2 := _gm(rg[0], cy, rg[2], hy)
			regs.append([rg[0], cy, rg[2], hy, rr2[0], rr2[1], rr2[2]])

## Monte Carlo y variantes: muestras en el cuadrado unidad.
func _sampling(kind: int, N: int, bins: int) -> Dictionary:
	var pts := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	match kind:
		15:
			for i in range(N):
				pts.append(Vector2(rng.randf(), rng.randf()))
		16:
			var m := maxi(1, int(round(sqrt(N))))
			for j in range(m):
				for i in range(m):
					pts.append(Vector2((i + rng.randf()) / m, (j + rng.randf()) / m))
		17:
			for i in range(N):
				pts.append(Vector2(Quadrature.van_der_corput(i + 1, 2), Quadrature.van_der_corput(i + 1, 3)))
		18:
			var fib := [1, 2]
			while fib[fib.size() - 1] + fib[fib.size() - 2] <= maxi(N, 8):
				fib.append(fib[fib.size() - 1] + fib[fib.size() - 2])
			var Fk: int = fib[fib.size() - 1]
			var Fp: int = fib[fib.size() - 2]
			# Desplazamiento fijo (½F en u, φ − 1 en v): el punto k = 0 no cae en la esquina
			# (0, 0), donde una singularidad le daría un peso enorme.
			for i in range(Fk):
				pts.append(Vector2((i + 0.5) / Fk, fposmod(float(i) * Fp / Fk + 0.6180339887498949, 1.0)))
	var s := 0.0
	var s2 := 0.0
	var sums := {}
	for p in pts:
		var g := G(p.x, p.y)
		s += g
		s2 += g * g
		var key := clampi(int(p.y * bins), 0, bins - 1) * bins + clampi(int(p.x * bins), 0, bins - 1)
		var acc: Array = sums.get(key, [0.0, 0])
		sums[key] = [float(acc[0]) + g, int(acc[1]) + 1]
	var M := pts.size()
	var mean := s / M
	var cells := []
	for key in sums:
		var ci: int = int(key) % bins
		var cj: int = int(key) / bins
		var cm: float = float(sums[key][0]) / int(sums[key][1])
		cells.append([float(ci) / bins, float(ci + 1) / bins, float(cj) / bins, float(cj + 1) / bins, cm / (bins * bins)])
	var out := {"valor": mean, "celdas": cells, "N": M}
	if kind == 15:
		out["sigma"] = sqrt(maxf(0.0, s2 / M - mean * mean) / M)
	return out

## Ejecuta el método m: {valor, evals, estado, …}. Los nodos se guardan si record.
func run_int(m: int, nn: int, tol: float = -1.0, N: int = -1, record: bool = false) -> Dictionary:
	if not (is_finite(a) and is_finite(b)) or a == b:
		return {"estado": "[a, b] no es válido"}
	if tol < 0.0:
		tol = pow(10.0, tol_exp)
	if N < 0:
		N = int(round(pow(10.0, mc_exp)))
	_ev = 0
	_over = false
	_cache.clear()
	_rec.clear()
	_recording = record
	var r: Dictionary
	if m in PANEL_RULES:
		r = _tensor(m, nn)
		if r.has("valor"):
			r["n"] = effective_n(m, nn)
			if record:
				_rec = _cache.keys()
	elif m == 6:
		r = _romberg(nn)
	elif m == 9:
		r = _clenshaw(nn)
	elif m == 10:
		r = _cub7(nn)
		r["n"] = nn
	elif m in ADAPTIVE:
		# Si la tolerancia pedida no cabe en el presupuesto, se relaja (×100) hasta que
		# quepa: mejor un valor correcto con menos cifras que ninguno.
		var tol_try := tol
		var limit := mini(_budget, ADAPTIVE_BUDGET)
		while true:
			_ev = 0
			_over = false
			_rec.clear()
			var saved := _budget
			_budget = limit
			r = _genz(tol_try) if m == 14 else _iterated(m, tol_try)
			_budget = saved
			if not _over or tol_try >= 1e-3:
				break
			tol_try *= 100.0
		if tol_try > tol and not _over:
			r["tol_usada"] = tol_try
	else:
		r = _sampling(m, N, clampi(nn, 1, 40))
	_recording = false
	r["evals"] = _cache.size() if m in PANEL_RULES else _ev
	if _over:
		r["estado"] = "se alcanzó el límite de %d evaluaciones" % _budget
	elif not r.has("estado"):
		r["estado"] = "ok" if is_finite(float(r.get("valor", NAN))) else "f no es finita en algún nodo (singularidad)"
	if r["estado"] == "ok" and is_finite(reference):
		r["error"] = absf(float(r["valor"]) - reference)
	return r

func _compute_int() -> void:
	sel = run_int(imethod, n, -1.0, -1, true)
	var nodes := _rec.duplicate()
	# Orden observado: n/2 frente a n (las adaptativas y Monte Carlo no tienen n).
	if sel.get("estado", "") == "ok" and not (imethod in ADAPTIVE or imethod in SAMPLING or imethod in [6, 9]) and n >= 2 and sel.has("error"):
		var r2 := run_int(imethod, n / 2)
		if r2.get("estado", "") == "ok" and r2.has("error"):
			var e1: float = r2["error"]
			var e2: float = sel["error"]
			var ratio := float(effective_n(imethod, n)) / effective_n(imethod, n / 2)
			if e1 > 1e-13 and e2 > 1e-13 and ratio > 1.0:
				sel["orden_obs"] = log(e1 / e2) / log(ratio)
	sel["nodos"] = nodes
	rows = []
	if compare:
		for m in range(INT_METHODS.size()):
			rows.append(sel if m == imethod else run_int(m, n))
	conv = []
	for m in (range(INT_METHODS.size()) if compare else [imethod]):
		conv.append([m, _int_series(m, 40000 if compare else 150000)])

## Error frente a evaluaciones: n = 1, 2, 4, …; tolerancias 10⁻², 10⁻⁴…; N = 10, 100…
func _int_series(m: int, budget: int) -> Array:
	var pts := []
	var params: Array
	if m in ADAPTIVE:
		params = [1e-2, 1e-3, 1e-4, 1e-6, 1e-8, 1e-10, 1e-12]
	elif m in SAMPLING:
		params = [10, 30, 100, 300, 1000, 3000, 10000, 30000]
	else:
		params = [1, 2, 3, 4, 6, 8, 12, 16, 24, 32]
	var spent := 0
	for q in params:
		_budget = clampi(budget - spent, 1000, BUDGET)
		var r: Dictionary
		if m in ADAPTIVE:
			r = run_int(m, n, float(q))
		elif m in SAMPLING:
			r = run_int(m, 8, -1.0, int(q))
		else:
			r = run_int(m, int(q))
		spent += int(r.get("evals", 0))
		if r.get("estado", "") == "ok" and r.has("error"):
			pts.append([log(maxf(1.0, float(r["evals"]))) / log(10.0), log(maxf(1e-17, float(r["error"]))) / log(10.0)])
		if spent > budget:
			break
	_budget = BUDGET
	return pts

# --- Derivación -------------------------------------------------------------------------------

func _noise(x: float, y: float) -> float:
	if noise_exp < -16.5:
		return 0.0
	return pow(10.0, noise_exp) * (float(hash([x, y]) % 20001) / 10000.0 - 1.0)

func FN(x: float, y: float) -> float:
	return F(x, y) + _noise(x, y)

## Dirección u de D_u f para dibujar (Vector2 es float32: los cálculos usan _u()).
func _dir() -> Vector2:
	return Vector2(cos(deg_to_rad(theta_deg)), sin(deg_to_rad(theta_deg)))

## [cos θ, sin θ] en doble precisión.
func _u() -> Array:
	return [cos(deg_to_rad(theta_deg)), sin(deg_to_rad(theta_deg))]

func _line(ddx: float, ddy: float) -> Callable:
	var px := x0
	var py := y0
	return func(t: float) -> float: return FN(px + t * ddx, py + t * ddy)

## Derivadas exactas en P (diferenciación automática; la mixta, de la simbólica).
func exact_all() -> Dictionary:
	var vars := {"x": x0, "y": y0}
	var jx := f_expr.eval_jet(vars, "x")
	var jy := f_expr.eval_jet(vars, "y")
	var fxy := NAN
	if dxy_e != null and dxy_e.ok():
		fxy = dxy_e.eval_real(vars)
	var fx: float = jx[1]
	var fy: float = jy[1]
	var u := _u()
	return {"f": float(jx[0]), "fx": fx, "fy": fy, "fxx": float(jx[2]), "fyy": float(jy[2]), "fxy": fxy,
		"lap": float(jx[2]) + float(jy[2]), "grad": sqrt(fx * fx + fy * fy), "du": fx * float(u[0]) + fy * float(u[1])}

func exact_target(tg: int) -> float:
	var e := exact_all()
	return float(e[["fx", "fy", "fxx", "fyy", "fxy", "lap", "grad", "du"][tg]])

## Diferencia mixta con el producto de dos plantillas de primera derivada.
func _mixed(name: String, h: float) -> Array:
	var st: Array = NumDiff.D1[name]
	var s := 0.0
	var pts := []
	for i in range((st[0] as Array).size()):
		for j in range((st[0] as Array).size()):
			var px := x0 + float(st[0][i]) * h
			var py := y0 + float(st[0][j]) * h
			s += float(st[1][i]) * float(st[1][j]) * FN(px, py)
			pts.append(Vector2(px, py))
	return [s / (h * h), pts]

func _richardson_h(fn: Callable, h: float, lv: int) -> float:
	var R := []
	for k in range(lv):
		var row := [float(fn.call(h / pow(2.0, k)))]
		for j in range(1, k + 1):
			row.append(float(row[j - 1]) + (float(row[j - 1]) - float(R[k - 1][j - 1])) / (pow(4.0, j) - 1.0))
		R.append(row)
	var last: Array = R[R.size() - 1]
	return float(last[last.size() - 1])

## Derivadas numéricas en P con el método m y el paso h: {valor, evals, puntos, estado}.
func run_diff(m: int, tg: int, h: float) -> Dictionary:
	var u := _u()
	var ux: float = u[0]
	var uy: float = u[1]
	var pts := {}
	var v := NAN
	var P := Vector2(x0, y0)
	match m:
		0, 1, 2, 3, 4:
			var name: String = STENCILS[m]
			var line := func(ddx: float, ddy: float, order: int) -> float:
				var r := NumDiff.stencil(_line(ddx, ddy), 0.0, h, name, order)
				for q in r["puntos"]:
					pts[P + Vector2(ddx, ddy) * float(q[0])] = true
				return float(r["valor"])
			match tg:
				0: v = line.call(1.0, 0.0, 1)
				1: v = line.call(0.0, 1.0, 1)
				2: v = line.call(1.0, 0.0, 2)
				3: v = line.call(0.0, 1.0, 2)
				4:
					var mx := _mixed(name, h)
					v = mx[0]
					for q in mx[1]:
						pts[q] = true
				5: v = line.call(1.0, 0.0, 2) + line.call(0.0, 1.0, 2)
				6:
					var gx: float = line.call(1.0, 0.0, 1)
					var gy: float = line.call(0.0, 1.0, 1)
					v = sqrt(gx * gx + gy * gy)
				7: v = line.call(ux, uy, 1)
		5:
			var rich := func(ddx: float, ddy: float, order: int) -> float:
				var r := NumDiff.richardson(_line(ddx, ddy), 0.0, h, levels, order)
				for q in r["puntos"]:
					pts[P + Vector2(ddx, ddy) * float(q[0])] = true
				return float(r["valor"])
			match tg:
				0: v = rich.call(1.0, 0.0, 1)
				1: v = rich.call(0.0, 1.0, 1)
				2: v = rich.call(1.0, 0.0, 2)
				3: v = rich.call(0.0, 1.0, 2)
				4:
					v = _richardson_h(func(hh: float) -> float: return float(_mixed("centrada", hh)[0]), h, levels)
					for q in _mixed("centrada", h)[1]:
						pts[q] = true
				5: v = rich.call(1.0, 0.0, 2) + rich.call(0.0, 1.0, 2)
				6:
					var rx: float = rich.call(1.0, 0.0, 1)
					var ry: float = rich.call(0.0, 1.0, 1)
					v = sqrt(rx * rx + ry * ry)
				7: v = rich.call(ux, uy, 1)
			var nlev := levels
			return {"valor": v, "evals": _count_rich(tg, nlev), "puntos": pts.keys(), "estado": "ok" if is_finite(v) else "no finita"}
		6:
			var cs1 := func(ddx: float, ddy: float) -> float:
				return float(f_expr.eval_cd({"x": [x0, h * ddx], "y": [y0, h * ddy]})[1]) / h
			var cs2 := func(ddx: float, ddy: float) -> float:
				return 2.0 * (F(x0, y0) - float(f_expr.eval_cd({"x": [x0, h * ddx], "y": [y0, h * ddy]})[0])) / (h * h)
			pts[P] = true
			match tg:
				0: v = cs1.call(1.0, 0.0)
				1: v = cs1.call(0.0, 1.0)
				2: v = cs2.call(1.0, 0.0)
				3: v = cs2.call(0.0, 1.0)
				4:
					var up := float(f_expr.eval_cd({"x": [x0, h], "y": [y0 + h, 0.0]})[1])
					var dn := float(f_expr.eval_cd({"x": [x0, h], "y": [y0 - h, 0.0]})[1])
					v = (up - dn) / (2.0 * h * h)
					pts[P + Vector2(0, h)] = true
					pts[P - Vector2(0, h)] = true
				5: v = cs2.call(1.0, 0.0) + cs2.call(0.0, 1.0)
				6:
					var cx: float = cs1.call(1.0, 0.0)
					var cy: float = cs1.call(0.0, 1.0)
					v = sqrt(cx * cx + cy * cy)
				7: v = cs1.call(ux, uy)
			return {"valor": v, "evals": [1, 1, 2, 2, 2, 3, 2, 1][tg], "puntos": pts.keys(), "estado": "ok" if is_finite(v) else "no finita"}
		7:
			v = exact_target(tg)
			pts[P] = true
			return {"valor": v, "evals": 1, "puntos": pts.keys(), "estado": "ok" if is_finite(v) else "sin derivada automática"}
		8:
			var vars := {"x": x0, "y": y0}
			var ev := func(e: MathExpr) -> float: return e.eval_real(vars) if e != null and e.ok() else NAN
			match tg:
				0: v = ev.call(dx_e)
				1: v = ev.call(dy_e)
				2: v = ev.call(dxx_e)
				3: v = ev.call(dyy_e)
				4: v = ev.call(dxy_e)
				5: v = ev.call(dxx_e) + ev.call(dyy_e)
				6:
					var sx0: float = ev.call(dx_e)
					var sy0: float = ev.call(dy_e)
					v = sqrt(sx0 * sx0 + sy0 * sy0)
				7: v = float(ev.call(dx_e)) * ux + float(ev.call(dy_e)) * uy
			pts[P] = true
			return {"valor": v, "evals": 1, "puntos": pts.keys(), "estado": "ok" if is_finite(v) else "sin derivada simbólica"}
		9:
			var fv := {}
			for j in [-1, 0, 1]:
				for i in [-1, 0, 1]:
					fv[Vector2i(i, j)] = FN(x0 + i * h, y0 + j * h)
					pts[P + Vector2(i, j) * h] = true
			var q := func(i: int, j: int) -> float: return float(fv[Vector2i(i, j)])
			var sx: float = (q.call(1, 1) + 2.0 * q.call(1, 0) + q.call(1, -1) - q.call(-1, 1) - 2.0 * q.call(-1, 0) - q.call(-1, -1)) / (8.0 * h)
			var sy: float = (q.call(1, 1) + 2.0 * q.call(0, 1) + q.call(-1, 1) - q.call(1, -1) - 2.0 * q.call(0, -1) - q.call(-1, -1)) / (8.0 * h)
			var rowxx := func(j: int) -> float: return q.call(1, j) - 2.0 * q.call(0, j) + q.call(-1, j)
			var colyy := func(i: int) -> float: return q.call(i, 1) - 2.0 * q.call(i, 0) + q.call(i, -1)
			match tg:
				0: v = sx
				1: v = sy
				2: v = (rowxx.call(1) + 10.0 * rowxx.call(0) + rowxx.call(-1)) / (12.0 * h * h)
				3: v = (colyy.call(1) + 10.0 * colyy.call(0) + colyy.call(-1)) / (12.0 * h * h)
				4: v = (q.call(1, 1) - q.call(-1, 1) - q.call(1, -1) + q.call(-1, -1)) / (4.0 * h * h)
				5: v = (4.0 * (q.call(1, 0) + q.call(-1, 0) + q.call(0, 1) + q.call(0, -1)) + q.call(1, 1) + q.call(-1, 1) + q.call(1, -1) + q.call(-1, -1) - 20.0 * q.call(0, 0)) / (6.0 * h * h)
				6: v = sqrt(sx * sx + sy * sy)
				7: v = sx * ux + sy * uy
		10:
			var A := []
			var rhs := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
			for r in range(6):
				A.append([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
			for j in range(-2, 3):
				for i in range(-2, 3):
					var fq := FN(x0 + i * h, y0 + j * h)
					pts[P + Vector2(i, j) * h] = true
					var basis := [1.0, float(i), float(j), float(i * i), float(i * j), float(j * j)]
					for r in range(6):
						rhs[r] = float(rhs[r]) + float(basis[r]) * fq
						for c in range(6):
							A[r][c] = float(A[r][c]) + float(basis[r]) * float(basis[c])
			var cf := NumDiff.solve(A, rhs)
			var fx: float = float(cf[1]) / h
			var fy: float = float(cf[2]) / h
			match tg:
				0: v = fx
				1: v = fy
				2: v = 2.0 * float(cf[3]) / (h * h)
				3: v = 2.0 * float(cf[5]) / (h * h)
				4: v = float(cf[4]) / (h * h)
				5: v = 2.0 * (float(cf[3]) + float(cf[5])) / (h * h)
				6: v = sqrt(fx * fx + fy * fy)
				7: v = fx * ux + fy * uy
	return {"valor": v, "evals": pts.size(), "puntos": pts.keys(), "estado": "ok" if is_finite(v) else "no finita"}

func _count_rich(tg: int, lv: int) -> int:
	var per := 2 if tg in [0, 1, 7] else (3 if tg in [2, 3] else (4 if tg == 4 else (5 if tg == 5 else 4)))
	return per * lv

func _compute_diff() -> void:
	var h := pow(10.0, h_exp)
	var ex := exact_target(target)
	sel = run_diff(dmethod, target, h)
	if sel["estado"] == "ok":
		sel["error"] = absf(float(sel["valor"]) - ex)
		if not (dmethod in EXACT_METHODS):
			var r2 := run_diff(dmethod, target, h * 0.5)
			var e2 := absf(float(r2["valor"]) - ex)
			if sel["error"] > 1e-13 and e2 > 1e-13:
				sel["orden_obs"] = log(float(sel["error"]) / e2) / log(2.0)
	rows = []
	if compare:
		for m in range(DIFF_METHODS.size()):
			var r := sel if m == dmethod else run_diff(m, target, h)
			if r["estado"] == "ok" and not r.has("error"):
				r["error"] = absf(float(r["valor"]) - ex)
			rows.append(r)
	conv = []
	h_opt = NAN
	e_opt = NAN
	for m in (range(DIFF_METHODS.size()) if compare else [dmethod]):
		var ser := []
		for k in range(0, 65):
			var lh := -16.0 + k * 0.25
			var r3 := run_diff(m, target, pow(10.0, lh))
			if r3["estado"] != "ok":
				continue
			var e := absf(float(r3["valor"]) - ex)
			ser.append([lh, log(maxf(1e-17, e)) / log(10.0)])
			if m == dmethod and not (m in EXACT_METHODS) and (is_nan(e_opt) or e < e_opt):
				e_opt = e
				h_opt = pow(10.0, lh)
		conv.append([m, ser])

# --- Cálculo y dibujo ----------------------------------------------------------------------------

func _changed() -> void:
	if f_expr == null or not f_expr.ok():
		return
	if mode == 0:
		_compute_int()
	else:
		_compute_diff()
	_draw()
	if plot:
		plot.queue_redraw()
	if lab:
		lab._update_info(false)

func _grid_xy(u: float, v: float) -> Vector2:
	if mode == 0:
		var x := a + u * (b - a)
		var cy := C(x)
		return Vector2(x, cy + v * (D(x) - cy))
	return Vector2(lerpf(wx.x, wx.y, u), lerpf(wy.x, wy.y, v))

func _hn(f: float) -> float:
	if not is_finite(f):
		return 1.08 * HEIGHT if f > 0.0 or is_nan(f) else -0.05 * HEIGHT
	return clampf((f - zr.x) / maxf(1e-9, zr.y - zr.x), -0.05, 1.08) * HEIGHT

func W(x: float, y: float, f: float) -> Vector3:
	return Vector3(((x - bx.x) / maxf(1e-12, bx.y - bx.x) - 0.5) * SIZE, _hn(f), -((y - by.x) / maxf(1e-12, by.y - by.x) - 0.5) * SIZE)

## Coordenadas matemáticas del punto del mundo (X, Z).
func _xy_of(p: Vector3) -> Vector2:
	return Vector2(lerpf(bx.x, bx.y, p.x / SIZE + 0.5), lerpf(by.x, by.y, 0.5 - p.z / SIZE))

func _inside(x: float, y: float) -> bool:
	if mode == 1:
		return x >= wx.x and x <= wx.y and y >= wy.x and y <= wy.y
	if x < bx.x or x > bx.y:
		return false
	var cy := C(x)
	var dy := D(x)
	return y >= minf(cy, dy) - 1e-12 and y <= maxf(cy, dy) + 1e-12

func _draw() -> void:
	for c in deco.get_children():
		c.queue_free()
	# Rango robusto de f (una singularidad no aplasta la superficie).
	var vals := []
	var grid := []
	for j in range(GRID + 1):
		var row := []
		for i in range(GRID + 1):
			var q := _grid_xy(float(i) / GRID, float(j) / GRID)
			var f := F(q.x, q.y)
			row.append([q, f])
			if is_finite(f):
				vals.append(f)
		grid.append(row)
	vals.sort()
	if vals.is_empty():
		zr = Vector2(0, 1)
	else:
		var hi: float = vals[mini(vals.size() - 1, int(vals.size() * 0.985))]
		zr = Vector2(float(vals[0]), hi)
		if mode == 0:
			zr = Vector2(minf(zr.x, 0.0), maxf(zr.y, 0.0))
		if zr.y - zr.x < 1e-9:
			zr.y = zr.x + 1.0
	_draw_surface(grid)
	if mode == 0:
		_draw_region_outline()
		_draw_cells(sel.get("celdas", []))
		_draw_nodes(sel.get("nodos", []), true)
		deco.add_child(label3d("x ∈ [%s, %s]" % [a_text, b_text], Vector3(0, 0.05, SIZE * 0.5 + 0.35), Color(0.75, 0.8, 0.9), 0.003))
		deco.add_child(label3d("c(x) = %s ≤ y ≤ d(x) = %s" % [c_expr.to_pretty() if c_expr else c_text, d_expr.to_pretty() if d_expr else d_text], Vector3(SIZE * 0.5 + 0.45, 0.05, 0), Color(0.75, 0.8, 0.9), 0.003))
	else:
		prisms.multimesh = null
		_draw_nodes(sel.get("puntos", []), false)
		_draw_diff_deco()

func _draw_surface(grid: Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(GRID + 1):
		for i in range(GRID + 1):
			var q: Vector2 = grid[j][i][0]
			var f: float = grid[j][i][1]
			var t := clampf(_hn(f) / HEIGHT, 0.0, 1.0)
			st.set_color(Color.from_hsv(0.62 - 0.52 * t, 0.8, 0.88))
			st.add_vertex(W(q.x, q.y, f))
	for j in range(GRID):
		for i in range(GRID):
			var k := j * (GRID + 1) + i
			st.add_index(k)
			st.add_index(k + 1)
			st.add_index(k + GRID + 1)
			st.add_index(k + 1)
			st.add_index(k + GRID + 2)
			st.add_index(k + GRID + 1)
	st.generate_normals()
	surf.mesh = st.commit()
	surf.material_override = vcolor_mat(0.82 if mode == 0 else 0.9, 0.22)

func _draw_region_outline() -> void:
	var edge := []
	for k in range(121):
		edge.append(Vector2(k / 120.0, 0.0))
	for k in range(1, 61):
		edge.append(Vector2(1.0, k / 60.0))
	for k in range(1, 121):
		edge.append(Vector2(1.0 - k / 120.0, 1.0))
	for k in range(1, 61):
		edge.append(Vector2(0.0, 1.0 - k / 60.0))
	var floor_pts := PackedVector3Array()
	var top_pts := PackedVector3Array()
	for e in edge:
		var q := _grid_xy(e.x, e.y)
		floor_pts.append(W(q.x, q.y, 0.0))
		top_pts.append(W(q.x, q.y, F(q.x, q.y)))
	deco.add_child(tube(floor_pts, 0.012, glow_mat(Color(0.85, 0.9, 1.0), 1.2)))
	deco.add_child(tube(top_pts, 0.012, glow_mat(Color(0.3, 0.9, 1.0), 1.6)))

## Prismas: cada celda [u0, u1, v0, v1, integral] con la altura media de f que le da el
## método. Una celda ancha en x se dibuja en franjas estrechas: la anchura en y de la
## región cambia con x (disco, triángulo) y una sola caja recta se saldría del borde.
func _draw_cells(cells: Array) -> void:
	if cells.is_empty() or cells.size() > 6000:
		prisms.multimesh = null
		return
	var boxes := []                 # [centro, tamaño, f media]
	for c in cells:
		var u0: float = c[0]
		var u1: float = c[1]
		var v0: float = c[2]
		var v1: float = c[3]
		var area_uv := (u1 - u0) * (v1 - v0)
		var jac := J((u0 + u1) * 0.5)
		var fm: float = float(c[4]) / (jac * area_uv) if absf(jac * area_uv) > 1e-15 else 0.0
		var slices := clampi(int(ceil((u1 - u0) * 32.0)), 1, 32)
		for k in range(slices):
			var us0 := lerpf(u0, u1, float(k) / slices)
			var us1 := lerpf(u0, u1, float(k + 1) / slices)
			var uc := (us0 + us1) * 0.5
			var x_c := a + uc * (b - a)
			var cy := C(x_c)
			var span_y := D(x_c) - cy
			var q := Vector2(x_c, cy + (v0 + v1) * 0.5 * span_y)
			var wxw := (us1 - us0) * absf(b - a) / maxf(1e-12, bx.y - bx.x) * SIZE
			var wzw := (v1 - v0) * absf(span_y) / maxf(1e-12, by.y - by.x) * SIZE
			boxes.append([q, Vector2(wxw, wzw), fm])
		if boxes.size() > 12000:
			break
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = box
	mm.instance_count = boxes.size()
	var y_base := _hn(0.0)
	for k in range(boxes.size()):
		var bxd: Array = boxes[k]
		var q2: Vector2 = bxd[0]
		var sz: Vector2 = bxd[1]
		var fm2: float = bxd[2]
		var hgt := _hn(fm2) - y_base
		var center := W(q2.x, q2.y, 0.0)
		center.y = y_base + hgt * 0.5
		mm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3(maxf(0.002, sz.x * 0.94), maxf(0.002, absf(hgt)), maxf(0.002, sz.y * 0.94))), center))
		var t := clampf(_hn(fm2) / HEIGHT, 0.0, 1.0)
		mm.set_instance_color(k, Color.from_hsv(0.62 - t * 0.5, 0.75, 1.0, 0.5) if fm2 >= 0.0 else Color(1.0, 0.3, 0.3, 0.5))
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

## Nodos de evaluación (integración: en el cuadrado unidad; derivación: puntos (x, y)).
func _draw_nodes(nodes: Array, unit: bool) -> void:
	if nodes.is_empty():
		dots.multimesh = null
		return
	var step := maxi(1, nodes.size() / 6000)
	var count := int(ceil(float(nodes.size()) / step))
	var sph := SphereMesh.new()
	var r := clampf(0.55 / sqrt(float(count)), 0.008, 0.03) if unit else 0.03
	sph.radius = r
	sph.height = r * 2.0
	sph.radial_segments = 8
	sph.rings = 4
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sph
	mm.instance_count = count
	var k := 0
	for i in range(0, nodes.size(), step):
		var p: Vector2 = nodes[i]
		var q := _grid_xy(p.x, p.y) if unit else p
		mm.set_instance_transform(k, Transform3D(Basis(), W(q.x, q.y, F(q.x, q.y)) + Vector3(0, r, 0)))
		k += 1
	mm.instance_count = k
	dots.multimesh = mm
	dots.material_override = glow_mat(Color(1.0, 0.85, 0.3) if unit else Color(1.0, 0.55, 0.2), 2.4)

func _draw_diff_deco() -> void:
	var e := exact_all()
	var f0: float = e["f"]
	var lift := Vector3(0, 0.025, 0)          # por encima de la superficie, que no lo tape
	var P := W(x0, y0, f0) + lift
	var ps := sphere(0.06, glow_mat(Color(1, 1, 1), 3.0))
	ps.position = P
	deco.add_child(ps)
	var lx := (wx.y - wx.x) * 0.2
	var ly := (wy.y - wy.x) * 0.2
	var fx: float = e["fx"]
	var fy: float = e["fy"]
	# Plano tangente z = f + fx·Δx + fy·Δy.
	if is_finite(fx) and is_finite(fy):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
		var vs := []
		for cn in corners:
			var dxv: float = cn.x * lx
			var dyv: float = cn.y * ly
			vs.append(W(x0 + dxv, y0 + dyv, f0 + fx * dxv + fy * dyv) + lift * 0.5)
		for idx in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(vs[idx])
		st.generate_normals()
		var pl := MeshInstance3D.new()
		pl.mesh = st.commit()
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(1.0, 0.62, 0.2, 0.42)
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pm.cull_mode = BaseMaterial3D.CULL_DISABLED
		pm.emission_enabled = true
		pm.emission = Color(1.0, 0.5, 0.15)
		pm.emission_energy_multiplier = 0.6
		pl.material_override = pm
		deco.add_child(pl)
		# Borde del plano tangente, para que se lea aunque la superficie lo corte.
		var rim := PackedVector3Array([vs[0], vs[1], vs[2], vs[3], vs[0]])
		deco.add_child(tube(rim, 0.007, glow_mat(Color(1.0, 0.7, 0.3), 1.8)))
		# Gradiente sobre el plano tangente (naranja) y dirección u de D_u f (verde).
		var g := Vector2(fx, fy)
		if g.length() > 1e-12:
			var gd := g.normalized()
			var tip := W(x0 + gd.x * lx, y0 + gd.y * ly, f0 + fx * gd.x * lx + fy * gd.y * ly) + lift
			deco.add_child(arrow(P, tip, 0.022, glow_mat(Color(1.0, 0.45, 0.1), 3.0)))
			var gl := label3d("∇f", tip + Vector3(0, 0.12, 0), Color(1.0, 0.75, 0.35), 0.0036)
			gl.no_depth_test = true
			deco.add_child(gl)
		if target == 7:
			var u := _dir()
			var tip2 := W(x0 + u.x * lx, y0 + u.y * ly, f0 + fx * u.x * lx + fy * u.y * ly) + lift
			deco.add_child(arrow(P, tip2, 0.02, glow_mat(Color(0.3, 1.0, 0.45), 3.0)))
			var ul := label3d("u", tip2 + Vector3(0, 0.12, 0), Color(0.5, 1.0, 0.6), 0.0036)
			ul.no_depth_test = true
			deco.add_child(ul)
	# Cortes por P: y = y₀ (cian, su pendiente es ∂f/∂x) y x = x₀ (magenta, ∂f/∂y).
	for spec in [[Vector2(1, 0), Color(0.3, 0.9, 1.0)], [Vector2(0, 1), Color(1.0, 0.45, 0.85)]]:
		var d: Vector2 = spec[0]
		var line := PackedVector3Array()
		for k in range(161):
			var t := float(k) / 160.0
			var x := lerpf(wx.x, wx.y, t) if d.x > 0.0 else x0
			var y := y0 if d.x > 0.0 else lerpf(wy.x, wy.y, t)
			line.append(W(x, y, F(x, y)) + Vector3(0, 0.012, 0))
		deco.add_child(tube(line, 0.01, glow_mat(spec[1], 1.6)))
	var plbl := label3d("P = (%s, %s)" % [_short(x0), _short(y0)], P + Vector3(0.1, 0.22, 0), Color(1, 1, 1), 0.0034)
	plbl.no_depth_test = true
	deco.add_child(plbl)

static func _short(v: float) -> String:
	return MathExpr._num_text(snappedf(v, 0.0001))

# --- Interfaz -------------------------------------------------------------------------------------

func build_ui(p: VBoxContainer) -> void:
	_panel = p
	LabUI.option(p, "Modo:", ["Integración doble ∬ f dA", "Derivación parcial ∂f/∂x, ∂f/∂y…"], mode, func(i): set_mode(i))
	if mode == 0:
		LabUI.option(p, "Ejemplo:", INT_PRESETS.map(func(q): return q["nombre"]), ipreset, func(i): _load_int(i))
		_ui["f"] = LabUI.expr_field(p, "f(x, y) =", f_expr.source, ["x", "y"], false, func(m): set_f(m))
		LabUI.section(p, "Región R: a ≤ x ≤ b, c(x) ≤ y ≤ d(x)")
		var r := LabUI.row(p)
		_ui["a"] = LabUI.value_field(r, "a =", a_text, func(v, t):
			a = v
			a_text = t
			_region_changed())
		_ui["b"] = LabUI.value_field(r, "b =", b_text, func(v, t):
			b = v
			b_text = t
			_region_changed())
		_ui["c"] = LabUI.expr_field(p, "c(x) =", c_text, ["x"], false, func(m):
			_set_limit("c", m)
			_region_changed())
		_ui["d"] = LabUI.expr_field(p, "d(x) =", d_text, ["x"], false, func(m):
			_set_limit("d", m)
			_region_changed())
		LabUI.note(p, "Límites de y constantes (rectángulo) o que dependen de x: 0 y x (triángulo), ±√(1 − x²) (disco), x² y √x…")
		LabUI.section(p, "Método")
		LabUI.option(p, "Método:", INT_METHODS, imethod, func(i): set_int_method(i))
		LabUI.slider(p, "n (subintervalos por lado)", 1, 40, 1, n, func(v):
			n = int(v)
			_changed(), "%.0f")
		LabUI.slider(p, "Nodos de Gauss p", 2, 8, 1, gp, func(v):
			gp = int(v)
			_changed(), "%.0f")
		LabUI.slider(p, "Tolerancia 10ᵏ (adaptativas)", -12, -2, 1, tol_exp, func(v):
			tol_exp = v
			_changed(), "%.0f")
		LabUI.slider(p, "Muestras N = 10ᵏ (Monte Carlo)", 1, 5, 0.25, mc_exp, func(v):
			mc_exp = v
			_changed(), "%.2f")
	else:
		LabUI.option(p, "Ejemplo:", DIFF_PRESETS.map(func(q): return q["nombre"]), dpreset, func(i): _load_diff(i))
		_ui["f"] = LabUI.expr_field(p, "f(x, y) =", f_expr.source, ["x", "y"], false, func(m): set_f(m))
		LabUI.option(p, "Derivada:", TARGETS, target, func(i):
			target = i
			_changed())
		LabUI.option(p, "Método:", DIFF_METHODS, dmethod, func(i): set_diff_method(i))
		var r2 := LabUI.row(p)
		_ui["x0"] = LabUI.value_field(r2, "x₀ =", _short(x0), func(v, _t):
			x0 = v
			_changed())
		_ui["y0"] = LabUI.value_field(r2, "y₀ =", _short(y0), func(v, _t):
			y0 = v
			_changed())
		LabUI.slider(p, "Dirección θ de D_u f (°)", 0, 360, 1, theta_deg, func(v):
			theta_deg = v
			_changed(), "%.0f")
		LabUI.slider(p, "Paso h = 10ᵏ", -16, 0, 0.25, h_exp, func(v):
			h_exp = v
			_changed(), "%.2f")
		LabUI.slider(p, "Niveles de Richardson", 1, 6, 1, levels, func(v):
			levels = int(v)
			_changed(), "%.0f")
		LabUI.slider(p, "Ruido en f: 10ᵏ (−17 = sin ruido)", -17, -1, 1, noise_exp, func(v):
			noise_exp = v
			_changed(), "%.0f")
		LabUI.section(p, "Intervalo de la gráfica")
		var r3 := LabUI.row(p)
		LabUI.value_field(r3, "x mín. =", _short(wx.x), func(v, _t): _set_window(Vector2(v, wx.y), wy))
		LabUI.value_field(r3, "x máx. =", _short(wx.y), func(v, _t): _set_window(Vector2(wx.x, v), wy))
		var r4 := LabUI.row(p)
		LabUI.value_field(r4, "y mín. =", _short(wy.x), func(v, _t): _set_window(wx, Vector2(v, wy.y)))
		LabUI.value_field(r4, "y máx. =", _short(wy.y), func(v, _t): _set_window(wx, Vector2(wy.x, v)))
	LabUI.check(p, "Comparar todos los métodos", compare, func(v):
		compare = v
		_changed())
	LabUI.section(p, "Error: log₁₀|error| frente a %s" % ("log₁₀ evaluaciones" if mode == 0 else "log₁₀ h"))
	plot = ErrPlot.new()
	plot.module = self
	plot.custom_minimum_size = Vector2(260, 150)
	p.add_child(plot)
	_desc = LabUI.note(p, INT_DESCS[imethod] if mode == 0 else DIFF_DESCS[dmethod])
	if mode == 0:
		LabUI.note(p, "Prismas: la altura media que el método da a cada celda (o subregión, en Genz–Malik). Puntos amarillos: dónde evalúa f. La región se lleva al cuadrado unidad, así que las celdas siguen los bordes curvos.")
	else:
		LabUI.note(p, "Plano tangente en P, ∇f en naranja y los cortes por P: cian (y = y₀, su pendiente es ∂f/∂x) y magenta (x = x₀, ∂f/∂y). Puntos naranjas: dónde evalúa f la plantilla con este h.")

func _set_window(nx: Vector2, ny: Vector2) -> void:
	if nx.y <= nx.x or ny.y <= ny.x:
		return
	wx = nx
	wy = ny
	bx = wx
	by = wy
	_changed()

func set_int_method(i: int) -> void:
	imethod = clampi(i, 0, INT_METHODS.size() - 1)
	if _desc:
		_desc.text = INT_DESCS[imethod]
	_changed()

func set_diff_method(i: int) -> void:
	dmethod = clampi(i, 0, DIFF_METHODS.size() - 1)
	if _desc:
		_desc.text = DIFF_DESCS[dmethod]
	_changed()

func _mcolor(m: int) -> Color:
	var total := INT_METHODS.size() if mode == 0 else DIFF_METHODS.size()
	return Color.from_hsv(float(m) / total, 0.7, 1.0)

static func _fmt_err(e) -> String:
	if e == null or is_nan(float(e)):
		return "—"
	return "0" if float(e) == 0.0 else LabUI.sci(float(e), 2)

# --- Ratón y API ---------------------------------------------------------------------------------

func pick(origin: Vector3, dir: Vector3):
	var hf := func(X: float, Z: float) -> float:
		var q := _xy_of(Vector3(X, 0, Z))
		if not _inside(q.x, q.y):
			return -100.0
		return _hn(F(q.x, q.y))
	return ray_heightfield(origin, dir, hf, SIZE * 0.5)

func api_points(x: float, y: float) -> Array:
	return [to_global(W(x, y, 0.0) * Vector3(1, 0, 1))]

func hover_text(hit: Vector3) -> String:
	var q := _xy_of(hit)
	var t := "x = %.4f   y = %.4f\nf(x, y) = %.6f" % [q.x, q.y, F(q.x, q.y)]
	if mode == 0:
		if not _inside(q.x, q.y):
			t += "\n(fuera de la región R)"
	else:
		var vars := {"x": q.x, "y": q.y}
		t += "\n∂f/∂x = %.6f\n∂f/∂y = %.6f" % [float(f_expr.eval_jet(vars, "x")[1]), float(f_expr.eval_jet(vars, "y")[1])]
	return t

func perturb(hit: Vector3, first: bool) -> void:
	if not first:
		return
	if mode == 0:
		n = clampi(n + (-2 if Input.is_key_pressed(KEY_SHIFT) else 2), 1, 40)
		_changed()
		return
	var q := _xy_of(hit)
	x0 = snappedf(q.x, 0.001)
	y0 = snappedf(q.y, 0.001)
	for k in [["x0", x0], ["y0", y0]]:
		if _ui.has(k[0]):
			var e: LineEdit = _ui[k[0]]
			e.text = _short(k[1])
			e.text_changed.emit(e.text)
	_changed()

func critical_points() -> Array:
	if mode == 1:
		return [{"pos": to_global(W(x0, y0, F(x0, y0))), "nombre": "P = (%s, %s)" % [_short(x0), _short(y0)], "dist": 2.6}]
	var out := []
	for uv in [Vector2(0.5, 0.5), Vector2(0.0, 0.0), Vector2(1.0, 1.0)]:
		var q := _grid_xy(uv.x, uv.y)
		out.append({"pos": to_global(W(q.x, q.y, F(q.x, q.y))), "nombre": "(%s, %s)" % [_short(q.x), _short(q.y)], "dist": 3.0})
	return out

func info() -> String:
	if sel.is_empty():
		return ""
	var t := "[font_size=12]"
	if mode == 0:
		t += "[color=#8fa3b8]área de R = %s · referencia (%s): [/color][color=#ffcc55]%.15f[/color]\n" % [_short(region_area), ref_src, reference]
		if flipped:
			t += "[color=#ff9977]d(x) < c(x) en parte de [a, b]: esa parte cuenta con signo negativo.[/color]\n"
		if compare:
			t += "[color=#8fa3b8]método · error · evaluaciones · orden (observado)[/color]\n"
			for m in range(rows.size()):
				var r: Dictionary = rows[m]
				var name: String = INT_SHORT[m] if m != imethod else "[b]%s[/b]" % INT_SHORT[m]
				var sq := "[color=#%s]■[/color]" % _mcolor(m).to_html(false)
				if str(r.get("estado", "")) != "ok":
					t += "%s %s · [color=#ff9977]%s[/color]\n" % [sq, name, r.get("estado", "")]
				else:
					t += "%s %s · %s · %d ev · %s%s\n" % [sq, name, _fmt_err(r.get("error")), int(r["evals"]), INT_ORDER[m],
						" (%.2f)" % float(r["orden_obs"]) if r.has("orden_obs") else ""]
		else:
			t += "[b]%s[/b]" % INT_METHODS[imethod]
			if str(sel.get("estado", "")) != "ok":
				t += ": [color=#ff9977]%s[/color]\n" % sel.get("estado", "")
			else:
				t += ": [color=#ffcc55]%.15f[/color] · error %s · %d evaluaciones · orden %s%s\n" % [float(sel["valor"]), _fmt_err(sel.get("error")), int(sel["evals"]), INT_ORDER[imethod],
					" (observado %.2f de n/2 a n)" % float(sel["orden_obs"]) if sel.has("orden_obs") else ""]
				if sel.has("sigma"):
					t += "Error estimado σ/√N = %s con N = %d\n" % [LabUI.sci(float(sel["sigma"]), 2), int(sel["N"])]
				elif sel.has("N"):
					t += "N = %d %s\n" % [int(sel["N"]), "nodos por lado" if imethod == 9 else "muestras"]
				if sel.has("error_est"):
					t += "Error estimado |grado 7 − grado 5| = %s en %d subregiones\n" % [LabUI.sci(float(sel["error_est"]), 2), int(sel["regiones"])]
				if sel.has("tol_usada"):
					t += "[color=#ffbb66]La tolerancia 10^%d no cabe en %d evaluaciones: resultado con 10^%d.[/color]\n" % [int(round(tol_exp)), ADAPTIVE_BUDGET, int(round(log(float(sel["tol_usada"])) / log(10.0)))]
				if sel.has("niveles"):
					t += "%d niveles de Romberg por dirección\n" % int(sel["niveles"])
				if sel.has("n") and imethod in PANEL_RULES:
					t += "n = %d subintervalos por lado%s\n" % [int(sel["n"]), (" · p = %d nodos por celda y lado" % gp) if imethod in [7, 8] else ""]
		t += "[/font_size]"
		return t.strip_edges()
	var e := exact_all()
	var ex := exact_target(target)
	t += "[color=#8fa3b8]P = (%s, %s) · f(P) = %s · h = %s%s[/color]\n" % [_short(x0), _short(y0), _short(e["f"]), LabUI.sci(pow(10.0, h_exp), 2), "  · ruido 10^%d" % int(noise_exp) if noise_exp > -16.5 else ""]
	var sym: MathExpr = [dx_e, dy_e, dxx_e, dyy_e, dxy_e, null, null, null][target]
	if sym != null and sym.ok():
		t += "[color=#8fa3b8]%s = [/color]%s\n" % [TSYM[target], sym.to_pretty()]
	t += "[color=#8fa3b8]exacta %s(P) = [/color][color=#ffcc55]%.15f[/color]\n" % [TSYM[target], ex]
	if compare:
		t += "[color=#8fa3b8]método · error · evaluaciones · orden (observado)[/color]\n"
		for m in range(rows.size()):
			var r3: Dictionary = rows[m]
			var name2: String = DIFF_SHORT[m] if m != dmethod else "[b]%s[/b]" % DIFF_SHORT[m]
			var sq2 := "[color=#%s]■[/color]" % _mcolor(m).to_html(false)
			if str(r3.get("estado", "")) != "ok":
				t += "%s %s · [color=#ff9977]%s[/color]\n" % [sq2, name2, r3.get("estado", "")]
			else:
				t += "%s %s · %s · %d ev · %s\n" % [sq2, name2, _fmt_err(r3.get("error")), int(r3["evals"]), DIFF_ORDER[m]]
	else:
		if str(sel.get("estado", "")) != "ok":
			t += "[b]%s[/b]: [color=#ff9977]%s[/color]\n" % [DIFF_METHODS[dmethod], sel.get("estado", "")]
		else:
			t += "[b]%s[/b]: [color=#ffcc55]%.15f[/color] · error %s · %d evaluaciones · orden %s%s\n" % [DIFF_METHODS[dmethod], float(sel["valor"]), _fmt_err(sel.get("error")), int(sel["evals"]), DIFF_ORDER[dmethod],
				" (observado %.2f)" % float(sel["orden_obs"]) if sel.has("orden_obs") else ""]
		if is_finite(h_opt):
			t += "h óptimo ≈ %s (error mínimo %s); con h menor domina el redondeo\n" % [LabUI.sci(h_opt, 1), _fmt_err(e_opt)]
	var det: float = float(e["fxx"]) * float(e["fyy"]) - float(e["fxy"]) * float(e["fxy"])
	var kind := "—"
	if is_finite(det):
		if Vector2(e["fx"], e["fy"]).length() < 1e-8:
			kind = "punto crítico: " + ("mínimo" if det > 0.0 and float(e["fxx"]) > 0.0 else ("máximo" if det > 0.0 else ("silla" if det < 0.0 else "dudoso")))
		else:
			kind = "curvatura " + ("elíptica" if det > 0.0 else ("hiperbólica (silla)" if det < 0.0 else "parabólica"))
	t += "[color=#8fa3b8]∇f = (%s, %s) · ∇²f = %s · hessiana: det = %s (%s)[/color]" % [_short(e["fx"]), _short(e["fy"]), _short(e["lap"]), _short(det), kind]
	t += "[/font_size]"
	return t.strip_edges()

## Capturas: «derivar», «comparar», «disco», «genz», «montecarlo», «singular», «mixta».
func demo(extra: Array) -> void:
	if "derivar" in extra:
		set_mode(1)
		if "mixta" in extra:
			_load_diff(3)
			target = 4
		if "ruido" in extra:
			noise_exp = -8.0
			h_exp = -2.0
			set_diff_method(10)
	if "disco" in extra:
		_load_int(8)
	elif "singular" in extra:
		_load_int(9)
		imethod = 13
	if "genz" in extra:
		imethod = 14
		tol_exp = -6.0
	elif "montecarlo" in extra:
		imethod = 15
	if "comparar" in extra:
		compare = true
	_changed()
	if _panel:
		_rebuild_ui()

# --- Gráfica del error ---------------------------------------------------------------------------

class ErrPlot extends Control:
	var module

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.03, 0.05, 0.08, 0.9))
		if module == null:
			return
		var font := ThemeDB.fallback_font
		var diff: bool = module.mode == 1
		var x_lo := -16.0 if diff else 0.0
		var x_hi := 0.0 if diff else 5.5
		var y_lo := -17.0
		var y_hi := 1.0
		for k in range(-16, 1, 4):
			var y := r.size.y * (y_hi - k) / (y_hi - y_lo)
			draw_line(Vector2(0, y), Vector2(r.size.x, y), Color(0.2, 0.3, 0.4, 0.5))
			draw_string(font, Vector2(3, y - 2), "10^%d" % k, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.55, 0.65, 0.75))
		var ticks := range(-16, 1, 4) if diff else range(0, 6)
		for k2 in ticks:
			var x := r.size.x * (float(k2) - x_lo) / (x_hi - x_lo)
			draw_line(Vector2(x, 0), Vector2(x, r.size.y), Color(0.2, 0.3, 0.4, 0.35))
			draw_string(font, Vector2(x + 2, r.size.y - 3), ("h=10^%d" if diff else "10^%d") % k2, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.55, 0.65, 0.75))
		var cur: int = module.dmethod if diff else module.imethod
		for s in module.conv:
			var m: int = s[0]
			var pts := PackedVector2Array()
			for q in s[1]:
				var px := r.size.x * (float(q[0]) - x_lo) / (x_hi - x_lo)
				var py := r.size.y * clampf((y_hi - float(q[1])) / (y_hi - y_lo), 0.0, 1.0)
				pts.append(Vector2(px, py))
			var col: Color = module._mcolor(m) if module.compare else Color(1.0, 0.6, 0.2)
			if pts.size() >= 2:
				draw_polyline(pts, col, 2.4 if m == cur else 1.2, true)
			if m == cur:
				for pt in pts:
					draw_circle(pt, 2.2, col)
		if diff:
			var hx := r.size.x * (float(module.h_exp) - x_lo) / (x_hi - x_lo)
			draw_line(Vector2(hx, 0), Vector2(hx, r.size.y), Color(1, 1, 1, 0.7), 1.0)
