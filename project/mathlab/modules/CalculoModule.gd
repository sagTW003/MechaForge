extends LabModule
## Integración y derivación numérica en 1D sobre la misma f(x).
##
##   Integración (18 métodos): rectángulos, punto medio, trapecio, Simpson 1/3 y
##   3/8, Boole, Romberg, Gauss–Legendre, Gauss–Lobatto, Gauss–Kronrod
##   adaptativa, Simpson adaptativa, Clenshaw–Curtis, tanh-sinh, Monte Carlo,
##   cuasi-Monte Carlo, Gauss–Laguerre y Gauss–Hermite (intervalos infinitos).
##   Se dibuja lo que suma cada método: paneles con su polinomio, los
##   «rectángulos equivalentes» wᵢ × f(xᵢ) de las reglas de Gauss, las muestras
##   aleatorias… Tabla con valor, error, evaluaciones y orden observado, y la
##   gráfica del error frente al número de evaluaciones.
##
##   Derivación (14 métodos, primera y segunda derivada): diferencias hacia
##   delante, atrás y centradas de 2 a 7 puntos, Richardson, paso complejo,
##   diferenciación automática, derivada simbólica, Savitzky–Golay, Chebyshev y
##   spline. Tablero con f, la plantilla de puntos y las tangentes (exacta y
##   aproximada), y debajo f′ (o f″) exacta frente a la aproximada; gráfica del
##   error frente a h con la «V» de truncamiento y redondeo. Ruido opcional.

const W := 3.0
const HGT := 1.9
const LIFT := 0.9

const INT_METHODS := ["Rectángulo izquierdo", "Rectángulo derecho", "Punto medio", "Trapecio", "Simpson 1/3", "Simpson 3/8",
	"Boole (Newton–Cotes de 5 puntos)", "Romberg (Richardson)", "Gauss–Legendre", "Gauss–Lobatto", "Gauss–Kronrod 7–15 adaptativa",
	"Simpson adaptativa", "Clenshaw–Curtis", "Tanh-sinh (doble exponencial)", "Monte Carlo", "Cuasi-Monte Carlo (van der Corput)",
	"Gauss–Laguerre [a, ∞)", "Gauss–Hermite (−∞, ∞)"]
const INT_SHORT := ["Rect. izq.", "Rect. der.", "Punto medio", "Trapecio", "Simpson 1/3", "Simpson 3/8", "Boole", "Romberg",
	"Gauss–Legendre", "Gauss–Lobatto", "Gauss–Kronrod", "Simpson adapt.", "Clenshaw–Curtis", "Tanh-sinh", "Monte Carlo",
	"Cuasi-MC", "Gauss–Laguerre", "Gauss–Hermite"]
const INT_ORDER := ["1", "1", "2", "2", "4", "4", "6", "2k", "2n", "2n − 2", "adaptativa", "adaptativa", "espectral",
	"doble exp.", "N^(−1/2)", "≈ N^(−1)", "2n", "2n"]
## Métodos cuyo parámetro es n y que convergen como una potencia de h (para el orden observado).
const INT_POWER := [0, 1, 2, 3, 4, 5, 6]
const INT_INFINITE := [10, 13, 16, 17]
const INT_FORMULAS := [
	"∫ₐᵇ f ≈ h Σ f(xᵢ),  xᵢ = a + ih,  i = 0…n−1",
	"∫ₐᵇ f ≈ h Σ f(xᵢ),  i = 1…n",
	"∫ₐᵇ f ≈ h Σ f(a + (i + ½)h)",
	"∫ₐᵇ f ≈ h [f₀/2 + f₁ + … + fₙ₋₁ + fₙ/2]",
	"∫ₐᵇ f ≈ h/3 [f₀ + 4f₁ + 2f₂ + 4f₃ + … + fₙ]",
	"∫ₐᵇ f ≈ 3h/8 [f₀ + 3f₁ + 3f₂ + 2f₃ + … + fₙ]",
	"∫ₐᵇ f ≈ 2h/45 [7f₀ + 32f₁ + 12f₂ + 32f₃ + 7f₄ + …]",
	"R(k, j) = R(k, j−1) + [R(k, j−1) − R(k−1, j−1)] / (4ʲ − 1)",
	"∫₋₁¹ f ≈ Σ wᵢ f(xᵢ),  xᵢ = raíces de Pₙ  (exacta hasta grado 2n − 1)",
	"∫₋₁¹ f ≈ Σ wᵢ f(xᵢ),  xᵢ = ±1 y raíces de P′ₙ₋₁  (exacta hasta grado 2n − 3)",
	"error ≈ |K₁₅ − G₇|: se parte el subintervalo peor hasta error < tol",
	"S₂ + (S₂ − S₁)/15, recursiva hasta |S₂ − S₁| < 15·tol",
	"∫₋₁¹ f ≈ Σ wₖ f(cos kπ/n)  (interpola en los puntos de Chebyshev)",
	"x = tanh(π/2 · sinh t): trapecio en t, error ≈ e^(−c N / ln N)",
	"∫ₐᵇ f ≈ (b − a) · (1/N) Σ f(Uᵢ),  error ≈ σ/√N",
	"∫ₐᵇ f ≈ (b − a) · (1/N) Σ f(xᵢ),  xᵢ de van der Corput",
	"∫₀^∞ e^(−x) g(x) dx ≈ Σ wᵢ g(xᵢ),  g = eˣ f",
	"∫₋∞^∞ e^(−x²) g(x) dx ≈ Σ wᵢ g(xᵢ),  g = e^(x²) f",
]
const INT_DESCS := [
	"Suma de rectángulos con la altura del extremo izquierdo de cada subintervalo. Orden 1: al duplicar n el error se divide entre 2.",
	"Igual, con el extremo derecho. Si f crece, izquierdo y derecho quedan uno por debajo y otro por encima.",
	"Rectángulos con la altura del punto medio: los errores de cada mitad se compensan y es de orden 2, la mitad de error que el trapecio.",
	"Une los puntos con rectas. Orden 2 (÷4 al duplicar n); con funciones periódicas en un periodo completo es exponencialmente exacto.",
	"Parábolas por cada 3 puntos. Orden 4 (÷16 al duplicar n); exacta hasta cúbicas.",
	"Cúbicas por cada 4 puntos. Orden 4, con constante algo mayor que Simpson 1/3; útil cuando n es múltiplo de 3.",
	"Polinomios de grado 4 por cada 5 puntos. Orden 6 (÷64 al duplicar n).",
	"Trapecios con h, h/2, h/4… y extrapolación de Richardson: cada columna elimina un término del error (h², h⁴, h⁶…). Los niveles son log₂ n + 1.",
	"n nodos óptimos (raíces de Legendre) con sus pesos: exacta para polinomios de grado 2n − 1. Converge muy rápido si f es suave.",
	"Como Gauss pero incluyendo los extremos: exacta hasta grado 2n − 3. Los extremos se reutilizan al encadenar intervalos.",
	"Regla de 15 puntos con una de Gauss de 7 anidada: la diferencia estima el error y se subdivide donde hace falta (como QUADPACK). Admite intervalos infinitos con un cambio de variable.",
	"Simpson en cada mitad frente a Simpson en el todo: si difieren, se subdivide. Pone los puntos donde f cambia deprisa.",
	"Interpola f en los puntos de Chebyshev e integra el polinomio. Casi tan precisa como Gauss y los nodos se reaprovechan al doblar n.",
	"El cambio x = tanh(π/2 sinh t) amontona los nodos en los extremos: integra sin problema singularidades como ln x o 1/√x en un extremo. Variantes exp-sinh y sinh-sinh para intervalos infinitos.",
	"Media de f en N puntos al azar por (b − a). El error baja solo como 1/√N, pero no depende de la dimensión: por eso se usa en integrales de muchas variables.",
	"Puntos de baja discrepancia (van der Corput) en lugar de aleatorios: cubren el intervalo de forma uniforme y el error baja casi como 1/N.",
	"Nodos y pesos para ∫₀^∞ e^(−x) g(x) dx: exacta si g es un polinomio. Para intervalos [a, ∞) o (−∞, b].",
	"Nodos y pesos para ∫ e^(−x²) g(x) dx en ℝ. Muy precisa para funciones con cola gaussiana; mala para colas lentas como 1/(1 + x²).",
]
const INT_PRESETS := [
	{"nombre": "∫₀^π sin x dx = 2", "f": "sin x", "a": "0", "b": "pi", "exacto": "2"},
	{"nombre": "∫₀¹ eˣ dx = e − 1", "f": "e^x", "a": "0", "b": "1", "exacto": "e - 1"},
	{"nombre": "Runge 1/(1 + 25x²) en [−1, 1]", "f": "1/(1 + 25x²)", "a": "-1", "b": "1", "exacto": "0.4 atan 5"},
	{"nombre": "√x (derivada infinita en 0)", "f": "√x", "a": "0", "b": "1", "exacto": "2/3"},
	{"nombre": "ln x (singular en 0)", "f": "ln x", "a": "0", "b": "1", "exacto": "-1"},
	{"nombre": "1/√x (singular integrable)", "f": "1/√x", "a": "0", "b": "1", "exacto": "2"},
	{"nombre": "Periódica e^(cos x) en [0, 2π]", "f": "e^(cos x)", "a": "0", "b": "2π", "exacto": "7.954926521012845"},
	{"nombre": "Pico |x − 1| en [0, 3]", "f": "|x - 1|", "a": "0", "b": "3", "exacto": "2.5"},
	{"nombre": "Oscilante sin(x²) en [0, 5]", "f": "sin(x²)", "a": "0", "b": "5", "exacto": ""},
	{"nombre": "e^(−x) en [0, ∞)", "f": "e^-x", "a": "0", "b": "∞", "exacto": "1", "vista": [0.0, 8.0]},
	{"nombre": "Gaussiana e^(−x²) en ℝ", "f": "e^(-x²)", "a": "-∞", "b": "∞", "exacto": "√π", "vista": [-4.0, 4.0]},
	{"nombre": "Cauchy 1/(1 + x²) en ℝ", "f": "1/(1 + x²)", "a": "-∞", "b": "∞", "exacto": "π", "vista": [-8.0, 8.0]},
]

const DIFF_METHODS := ["Diferencia hacia delante", "Diferencia hacia atrás", "Diferencia centrada", "Hacia delante de 3 puntos",
	"Hacia atrás de 3 puntos", "Centrada de 5 puntos", "Centrada de 7 puntos", "Extrapolación de Richardson", "Paso complejo",
	"Diferenciación automática (duales)", "Derivada simbólica", "Savitzky–Golay (ajuste local)", "Espectral de Chebyshev", "Spline cúbico"]
const DIFF_SHORT := ["Adelante", "Atrás", "Centrada", "Adelante 3p", "Atrás 3p", "Centrada 5p", "Centrada 7p", "Richardson",
	"Paso complejo", "Automática", "Simbólica", "Savitzky–Golay", "Chebyshev", "Spline"]
const STENCILS := ["adelante", "atras", "centrada", "adelante3", "atras3", "centrada5", "centrada7"]
const DIFF_ORDER1 := ["1", "1", "2", "2", "2", "4", "6", "8", "2", "exacta", "exacta", "4", "espectral", "4"]
const DIFF_ORDER2 := ["1", "1", "2", "2", "2", "4", "6", "8", "2", "exacta", "exacta", "3", "espectral", "2"]
## Métodos que dependen de h (para la gráfica error–h y el orden observado).
const H_METHODS := [0, 1, 2, 3, 4, 5, 6, 7, 8, 11, 13]
const DIFF_FORMULAS1 := [
	"f′(x) ≈ [f(x + h) − f(x)] / h",
	"f′(x) ≈ [f(x) − f(x − h)] / h",
	"f′(x) ≈ [f(x + h) − f(x − h)] / 2h",
	"f′(x) ≈ [−3f(x) + 4f(x + h) − f(x + 2h)] / 2h",
	"f′(x) ≈ [3f(x) − 4f(x − h) + f(x − 2h)] / 2h",
	"f′(x) ≈ [f(x − 2h) − 8f(x − h) + 8f(x + h) − f(x + 2h)] / 12h",
	"f′(x) ≈ [−f₋₃ + 9f₋₂ − 45f₋₁ + 45f₁ − 9f₂ + f₃] / 60h",
	"R(k, j) = R(k, j−1) + [R(k, j−1) − R(k−1, j−1)] / (4ʲ − 1),  con D(h/2ᵏ) centrada",
	"f′(x) ≈ Im f(x + ih) / h   (sin resta: vale h = 10⁻²⁰)",
	"(u, u′, u″) se propagan por cada operación con la regla de la cadena",
	"",
	"p(x) de grado 4 ajustado a 9 muestras por mínimos cuadrados; f′ ≈ p′(x₀)",
	"f ≈ Σ aₖ Tₖ(t) en N + 1 puntos de Chebyshev; f′ ≈ Σ bₖ Tₖ(t)",
	"spline cúbico (not-a-knot) por 13 muestras de paso h; f′ ≈ s′(x₀)",
]
const DIFF_FORMULAS2 := [
	"f″(x) ≈ [f(x + 2h) − 2f(x + h) + f(x)] / h²",
	"f″(x) ≈ [f(x) − 2f(x − h) + f(x − 2h)] / h²",
	"f″(x) ≈ [f(x + h) − 2f(x) + f(x − h)] / h²",
	"f″(x) ≈ [2f(x) − 5f(x + h) + 4f(x + 2h) − f(x + 3h)] / h²",
	"f″(x) ≈ [2f(x) − 5f(x − h) + 4f(x − 2h) − f(x − 3h)] / h²",
	"f″(x) ≈ [−f₋₂ + 16f₋₁ − 30f₀ + 16f₁ − f₂] / 12h²",
	"f″(x) ≈ [2f₋₃ − 27f₋₂ + 270f₋₁ − 490f₀ + 270f₁ − 27f₂ + 2f₃] / 180h²",
	"R(k, j) = R(k, j−1) + [R(k, j−1) − R(k−1, j−1)] / (4ʲ − 1),  con D₂(h/2ᵏ) centrada",
	"f″(x) ≈ 2[f(x) − Re f(x + ih)] / h²   (aquí sí hay resta)",
	"(u, u′, u″) se propagan por cada operación con la regla de la cadena",
	"",
	"p(x) de grado 4 ajustado a 9 muestras; f″ ≈ p″(x₀)",
	"f ≈ Σ aₖ Tₖ(t); se deriva dos veces la serie de Chebyshev",
	"spline cúbico (not-a-knot) por 13 muestras; f″ ≈ s″(x₀)",
]
const DIFF_DESCS := [
	"La pendiente de la secante hacia delante. Orden 1: el error de truncamiento es ≈ h·f″/2. Con h muy pequeño domina el redondeo (≈ ε/h): la «V» de la gráfica.",
	"La secante hacia atrás: el mismo orden, con el error de signo contrario.",
	"La secante simétrica: los términos pares se cancelan y es de orden 2. El mínimo del error está hacia h ≈ 10⁻⁵ (ε^(1/3)).",
	"Parábola por x, x + h, x + 2h: orden 2 usando solo un lado (útil en un borde).",
	"Parábola por x − 2h, x − h, x: orden 2 hacia atrás (útil en el borde derecho).",
	"Cinco puntos simétricos: orden 4. Con h ≈ 10⁻³ llega a unos 10⁻¹³.",
	"Siete puntos simétricos: orden 6.",
	"Diferencias centradas con h, h/2, h/4, h/8 combinadas para cancelar h², h⁴, h⁶: orden 8 con 4 niveles.",
	"Evalúa f en el número complejo x + ih: la parte imaginaria es h·f′(x) sin ninguna resta, así que no hay error de redondeo y se puede usar h = 10⁻²⁰. Necesita la fórmula (no sirve con datos medidos).",
	"Propaga a la vez el valor y las derivadas por cada operación de la fórmula (números duales / chorros de Taylor): exacta hasta el redondeo y sin elegir h.",
	"Deriva la fórmula con las reglas del cálculo y la simplifica. Exacta; además da la expresión de f′.",
	"Ajusta un polinomio a varias muestras y lo deriva: suaviza el ruido de los datos. Con ruido, las diferencias finitas estallan (≈ ruido/h) y este no tanto.",
	"Interpola f en todo el intervalo de la gráfica con N + 1 puntos de Chebyshev y deriva la serie. Si f es analítica, el error cae exponencialmente con N.",
	"Deriva el spline cúbico que pasa por las muestras: orden 4 en el centro para f′, 2 para f″.",
]
const DIFF_PRESETS := [
	{"nombre": "sin x en x₀ = 1", "f": "sin x", "x0": 1.0, "dom": [-3.2, 3.2]},
	{"nombre": "eˣ en x₀ = 0.5", "f": "e^x", "x0": 0.5, "dom": [-2.0, 2.0]},
	{"nombre": "Polinomio x³ − 2x", "f": "x³ - 2x", "x0": 1.2, "dom": [-2.0, 2.0]},
	{"nombre": "ln x cerca de 0", "f": "ln x", "x0": 0.3, "dom": [0.05, 3.0]},
	{"nombre": "e^(−x²) sin 3x", "f": "e^(-x²) sin 3x", "x0": 0.4, "dom": [-3.0, 3.0]},
	{"nombre": "Runge 1/(1 + 25x²)", "f": "1/(1 + 25x²)", "x0": 0.2, "dom": [-1.0, 1.0]},
	{"nombre": "tan x cerca del polo", "f": "tan x", "x0": 1.3, "dom": [-1.5, 1.5]},
	{"nombre": "x|x| (f″ salta en 0)", "f": "x|x|", "x0": 0.05, "dom": [-1.0, 1.0]},
]

var mode: int = 0
var f_expr: MathExpr
var d1_expr: MathExpr
var d2_expr: MathExpr
var ipreset: int = 0
var dpreset: int = 0
var a: float = 0.0
var b: float = PI
var a_text: String = "0"
var b_text: String = "pi"
var exact: float = NAN
var reference: float = NAN
var ref_src: String = ""
var imethod: int = 3
var n: int = 8
var tol_exp: float = -8.0
var mc_exp: float = 3.0
var compare: bool = false
var x0: float = 1.0
var h_exp: float = -2.0
var order: int = 1
var dmethod: int = 2
var noise_exp: float = -17.0
var n_cheb: int = 24
var xa: float = -3.2
var xb: float = 3.2
var rows: Array = []
var sel: Dictionary = {}
var conv: Array = []            # [[método, [[log x, log error], …]], …]
var h_opt: float = NAN
var e_opt: float = NAN
var board_node: Node3D
var draw_node: Node3D
var plot: Control
var _panel: VBoxContainer
var _ui := {}
var _desc: Label
var _bd := {}                   # tableros: nombre → {cy, hh, lo, hi}
var _table: String = ""

func title() -> String: return "Integración y derivación (1D)"
func planar() -> bool: return true
func formula() -> String:
	if mode == 0:
		return INT_FORMULAS[imethod]
	if dmethod == 10:
		var d := d1_expr if order == 1 else d2_expr
		return ("f′(x) = " if order == 1 else "f″(x) = ") + (d.to_pretty() if d and d.ok() else "—")
	return (DIFF_FORMULAS1 if order == 1 else DIFF_FORMULAS2)[dmethod]
func perturb_hint() -> String:
	return "clic: mueve el extremo a o b más cercano" if mode == 0 else "clic: elige el punto x₀ donde se deriva"
func view() -> Dictionary: return {"target": Vector3(0, LIFT, 0), "dist": 8.6, "yaw": -6.0, "pitch": -6.0}

func setup() -> void:
	position = Vector3(0, LIFT, 0)
	board_node = Node3D.new()
	add_child(board_node)
	draw_node = Node3D.new()
	add_child(draw_node)
	_load_int(0)

# --- Función y derivadas ------------------------------------------------------------------

func set_f(m: MathExpr, keep_exact: bool = false) -> void:
	f_expr = m
	f_expr.compile_fast()
	d1_expr = f_expr.derivative("x")
	d2_expr = d1_expr.derivative("x") if d1_expr.ok() else d1_expr
	# El valor exacto del ejemplo solo vale mientras la función y los límites sean los suyos.
	if not keep_exact and not _preset_limits():
		exact = NAN
	_changed()

func F(x: float) -> float:
	var v := f_expr.eval_fast([x])
	return v if not is_nan(v) else f_expr.eval_real({"x": x})

## Ruido determinista de amplitud 10^noise_exp (a partir de los bits de x).
func _noise(x: float) -> float:
	if noise_exp < -16.5:
		return 0.0
	return pow(10.0, noise_exp) * (float(hash(x) % 20001) / 10000.0 - 1.0)

func FN(x: float) -> float:
	return F(x) + _noise(x)

## Derivada exacta de orden k en x (diferenciación automática).
func exact_d(x: float, k: int) -> float:
	return float(f_expr.eval_jet({"x": x}, "x")[k])

# --- Ejemplos y modo -----------------------------------------------------------------------

func _load_int(i: int) -> void:
	ipreset = clampi(i, 0, INT_PRESETS.size() - 1)
	var p: Dictionary = INT_PRESETS[ipreset]
	a_text = p["a"]
	b_text = p["b"]
	a = MathExpr.parse(a_text, []).eval_real({})
	b = MathExpr.parse(b_text, []).eval_real({})
	var ex := str(p["exacto"])
	exact = MathExpr.parse(ex, []).eval_real({}) if ex != "" else NAN
	set_f(MathExpr.parse(p["f"], ["x"]), true)
	if _ui.has("a") and mode == 0:
		(_ui["f"] as LineEdit).text = p["f"]
		(_ui["f"] as LineEdit).text_changed.emit(p["f"])
		(_ui["a"] as LineEdit).text = a_text
		(_ui["a"] as LineEdit).text_changed.emit(a_text)
		(_ui["b"] as LineEdit).text = b_text
		(_ui["b"] as LineEdit).text_changed.emit(b_text)

func _load_diff(i: int) -> void:
	dpreset = clampi(i, 0, DIFF_PRESETS.size() - 1)
	var p: Dictionary = DIFF_PRESETS[dpreset]
	x0 = p["x0"]
	xa = p["dom"][0]
	xb = p["dom"][1]
	set_f(MathExpr.parse(p["f"], ["x"]))
	if _ui.has("x0") and mode == 1:
		(_ui["f"] as LineEdit).text = p["f"]
		(_ui["f"] as LineEdit).text_changed.emit(p["f"])
		(_ui["x0"] as LineEdit).text = str(x0)
		(_ui["x0"] as LineEdit).text_changed.emit(str(x0))

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

# --- Cálculo ----------------------------------------------------------------------------------

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

func _window() -> Vector2:
	if mode == 1:
		return Vector2(xa, xb)
	if is_finite(a) and is_finite(b):
		var L := b - a
		if L <= 0.0:
			return Vector2(minf(a, b) - 1.0, maxf(a, b) + 1.0)
		return Vector2(a - 0.06 * L, b + 0.06 * L)
	var p: Dictionary = INT_PRESETS[ipreset]
	if p.has("vista") and p["a"] == a_text and p["b"] == b_text:
		return Vector2(p["vista"][0], p["vista"][1])
	if is_finite(a):
		return Vector2(a - 0.5, a + 10.0)
	if is_finite(b):
		return Vector2(b - 10.0, b + 0.5)
	return Vector2(-6.0, 6.0)

func run_int(m: int, nn: int, tol: float = -1.0, N: int = -1) -> Dictionary:
	var fin := is_finite(a) and is_finite(b)
	if not fin and not (m in INT_INFINITE):
		return {"estado": "necesita [a, b] finito"}
	if m == 16 and (fin or (is_inf(a) and is_inf(b))):
		return {"estado": "solo para [a, ∞) o (−∞, b]"}
	if m == 17 and not (is_inf(a) and is_inf(b)):
		return {"estado": "solo para (−∞, ∞)"}
	if fin and a >= b:
		return {"estado": "a debe ser menor que b"}
	var t := pow(10.0, tol_exp) if tol < 0.0 else tol
	var NN := int(round(pow(10.0, mc_exp))) if N < 0 else N
	var f := func(x: float) -> float: return F(x)
	var r: Dictionary
	match m:
		0: r = Quadrature.rect_left(f, a, b, nn)
		1: r = Quadrature.rect_right(f, a, b, nn)
		2: r = Quadrature.midpoint(f, a, b, nn)
		3: r = Quadrature.trapezoid(f, a, b, nn)
		4: r = Quadrature.simpson(f, a, b, nn)
		5: r = Quadrature.simpson38(f, a, b, nn)
		6: r = Quadrature.boole(f, a, b, nn)
		7: r = Quadrature.romberg(f, a, b, int(ceil(log(maxf(1.0, nn)) / log(2.0))) + 1)
		8: r = Quadrature.gauss_legendre(f, a, b, nn)
		9: r = Quadrature.gauss_lobatto(f, a, b, maxi(2, nn))
		10: r = Quadrature.gauss_kronrod(f, a, b, t)
		11: r = Quadrature.simpson_adaptive(f, a, b, t)
		12: r = Quadrature.clenshaw_curtis(f, a, b, maxi(2, nn))
		13: r = Quadrature.tanh_sinh(f, a, b, t)
		14: r = Quadrature.monte_carlo(f, a, b, NN)
		15: r = Quadrature.quasi_monte_carlo(f, a, b, NN)
		16: r = Quadrature.gauss_laguerre(f, a, b, nn)
		_: r = Quadrature.gauss_hermite(f, nn)
	var v: float = r["valor"]
	if not is_finite(v):
		r["estado"] = "f no es finita en algún nodo (p. ej. en un extremo)"
	else:
		r["estado"] = "ok"
		r["error"] = absf(v - reference) if is_finite(reference) else NAN
	return r

func _compute_int() -> void:
	if is_finite(exact):
		reference = exact
		ref_src = "valor exacto"
	else:
		var gk := Quadrature.gauss_kronrod(func(x: float) -> float: return F(x), a, b, 1e-13, 2000)
		reference = gk["valor"]
		ref_src = "Gauss–Kronrod adaptativa (tol 10⁻¹³)"
	rows.clear()
	for m in range(INT_METHODS.size()):
		var r := run_int(m, n)
		if r["estado"] == "ok" and m in INT_POWER:
			var r2 := run_int(m, 2 * n)
			var e1: float = r["error"]
			var e2: float = r2.get("error", NAN)
			r["orden_obs"] = log(e1 / e2) / log(2.0) if e1 > 1e-12 and e2 > 1e-12 else NAN
		rows.append(r)
	sel = rows[imethod]
	_convergence_int()

## Curvas error–evaluaciones: el método elegido (o todos al comparar).
func _convergence_int() -> void:
	conv.clear()
	var ms := range(INT_METHODS.size()) if compare else [imethod]
	for m in ms:
		var pts := []
		if m in [10, 11, 13]:
			for k in range(2, 14):
				var r := run_int(m, n, pow(10.0, -k))
				if r["estado"] == "ok":
					pts.append([log(float(r["evals"])) / log(10.0), log(maxf(float(r["error"]), 1e-17)) / log(10.0)])
		elif m in [14, 15]:
			for k in range(1, 9):
				var NN := int(pow(10.0, 1.0 + k * 0.4))
				var r2 := run_int(m, n, -1.0, NN)
				if r2["estado"] == "ok":
					pts.append([log(float(r2["evals"])) / log(10.0), log(maxf(float(r2["error"]), 1e-17)) / log(10.0)])
		else:
			var nn := 1
			while nn <= (64 if m in [8, 9, 12, 16, 17] else 512):
				var r3 := run_int(m, nn)
				if r3["estado"] == "ok":
					pts.append([log(float(r3["evals"])) / log(10.0), log(maxf(float(r3["error"]), 1e-17)) / log(10.0)])
				nn *= 2
		conv.append([m, pts])

func run_diff(m: int, x: float, h: float) -> Dictionary:
	var f := func(t: float) -> float: return FN(t)
	var r: Dictionary
	match m:
		0, 1, 2, 3, 4, 5, 6:
			r = NumDiff.stencil(f, x, h, STENCILS[m], order)
		7:
			r = NumDiff.richardson(f, x, h, 4, order)
		8:
			var z := f_expr.eval_cd({"x": [x, h]})
			var v: float = float(z[1]) / h if order == 1 else 2.0 * (F(x) - float(z[0])) / (h * h)
			r = {"valor": v, "evals": 1 if order == 1 else 2, "puntos": [[x, F(x)]]}
		9:
			r = {"valor": exact_d(x, order), "evals": 1, "puntos": [[x, F(x)]]}
		10:
			var d := d1_expr if order == 1 else d2_expr
			r = {"valor": d.eval_real({"x": x}) if d.ok() else NAN, "evals": 1, "puntos": [[x, F(x)]]}
		11:
			r = NumDiff.savitzky_golay(f, x, h, 4, 4, order)
		12:
			r = NumDiff.chebyshev(f, xa, xb, n_cheb, x, order)
		_:
			r = NumDiff.spline(f, x, h, 6, order)
	var v2: float = r["valor"]
	var ex := exact_d(x, order)
	r["estado"] = "ok" if is_finite(v2) else "no se puede evaluar"
	r["error"] = absf(v2 - ex) if is_finite(v2) and is_finite(ex) else NAN
	return r

func _compute_diff() -> void:
	var h := pow(10.0, h_exp)
	rows.clear()
	for m in range(DIFF_METHODS.size()):
		var r := run_diff(m, x0, h)
		if r["estado"] == "ok" and m in H_METHODS:
			var r2 := run_diff(m, x0, h * 0.5)
			var e1: float = r["error"]
			var e2: float = r2["error"]
			r["orden_obs"] = log(e1 / e2) / log(2.0) if e1 > 1e-12 and e2 > 1e-12 else NAN
		rows.append(r)
	sel = rows[dmethod]
	# Curvas error–h (la «V»).
	conv.clear()
	h_opt = NAN
	e_opt = INF
	var ms := range(DIFF_METHODS.size()) if compare else [dmethod]
	for m in ms:
		var pts := []
		var k := -16.0
		while k <= 0.001:
			var hh := pow(10.0, k)
			var r3 = run_diff(m, x0, hh) if m in H_METHODS or k == -16.0 else null
			if r3 == null:
				pts.append([k, pts[pts.size() - 1][1]] if not pts.is_empty() else [k, -17.0])
			elif r3["estado"] == "ok":
				var e3: float = r3["error"]
				pts.append([k, log(maxf(e3, 1e-17)) / log(10.0)])
				if m == dmethod and m in H_METHODS and e3 < e_opt:
					e_opt = e3
					h_opt = hh
			k += 0.25
		conv.append([m, pts])

# --- Dibujo -------------------------------------------------------------------------------------

func _X(x: float) -> float:
	var w := _window()
	return (x - (w.x + w.y) * 0.5) * (2.0 * W / (w.y - w.x))

func _xw(wx: float) -> float:
	var w := _window()
	return wx / (2.0 * W / (w.y - w.x)) + (w.x + w.y) * 0.5

func _Y(y: float, bd: String) -> float:
	var q: Dictionary = _bd[bd]
	var t := (y - float(q["lo"])) / maxf(1e-12, float(q["hi"]) - float(q["lo"]))
	return float(q["cy"]) + clampf(t * 2.0 - 1.0, -1.15, 1.15) * float(q["hh"])

func _p(x: float, y: float, bd: String = "f") -> Vector3:
	return Vector3(_X(x), _Y(y, bd), 0.0)

## Rango vertical robusto (percentiles 4–96 %, incluido el 0) de fn en la ventana.
func _range(fn: Callable) -> Vector2:
	var w := _window()
	var vals := []
	for i in range(241):
		var v: float = fn.call(lerpf(w.x, w.y, i / 240.0))
		if is_finite(v):
			vals.append(v)
	if vals.is_empty():
		return Vector2(-1, 1)
	vals.sort()
	var lo: float = minf(0.0, float(vals[int(vals.size() * 0.04)]))
	var hi: float = maxf(0.0, float(vals[int(vals.size() * 0.96) - 1 if vals.size() > 1 else 0]))
	if hi - lo < 1e-9:
		hi = lo + 1.0
	var pad := (hi - lo) * 0.08
	return Vector2(lo - pad, hi + pad)

func _board(cy: float, hh: float) -> void:
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(W * 2.0 + 0.4, hh * 2.0 + 0.3, 0.04)
	board.mesh = bm
	board.material_override = glass_mat(Color(0.05, 0.12, 0.2), 0.55)
	board.position = Vector3(0, cy, -0.12)
	board_node.add_child(board)

func _axes(bd: String, label: String, col: Color) -> void:
	var w := _window()
	var q: Dictionary = _bd[bd]
	var y0 := _Y(0.0, bd)
	board_node.add_child(arrow(Vector3(-W - 0.1, y0, 0), Vector3(W + 0.2, y0, 0), 0.008, glow_mat(Color(0.8, 0.85, 0.95), 1.0)))
	var x0w := _X(0.0)
	if absf(x0w) <= W:
		board_node.add_child(rod(Vector3(x0w, float(q["cy"]) - float(q["hh"]), 0), Vector3(x0w, float(q["cy"]) + float(q["hh"]), 0), 0.006, glow_mat(Color(0.6, 0.65, 0.75), 0.8)))
	var span := w.y - w.x
	var step := pow(10.0, floor(log(span) / log(10.0)))
	if span / step < 4.0:
		step *= 0.5
	var t: float = ceilf(w.x / step) * step
	while t <= w.y:
		board_node.add_child(label3d(MathExpr._num_text(snappedf(t, step * 0.01)), Vector3(_X(t), y0 - 0.13, 0.02), Color(0.7, 0.75, 0.85), 0.0024))
		t += step
	board_node.add_child(label3d(label, Vector3(-W + 0.2, float(q["cy"]) + float(q["hh"]) + 0.02, 0.02), col, 0.0032))

func _curve(fn: Callable, bd: String, col: Color, r: float, parent: Node3D) -> void:
	var w := _window()
	var q: Dictionary = _bd[bd]
	var pts := PackedVector3Array()
	var N := 360
	for i in range(N + 1):
		var x := lerpf(w.x, w.y, float(i) / N)
		var y: float = fn.call(x)
		var tt := (y - float(q["lo"])) / (float(q["hi"]) - float(q["lo"]))
		if not is_finite(y) or tt < -0.08 or tt > 1.08:
			if pts.size() >= 2:
				parent.add_child(tube(pts, r, glow_mat(col, 1.6)))
			pts = PackedVector3Array()
			continue
		pts.append(_p(x, y, bd))
	if pts.size() >= 2:
		parent.add_child(tube(pts, r, glow_mat(col, 1.6)))

func _draw() -> void:
	for c in board_node.get_children():
		c.queue_free()
	for c in draw_node.get_children():
		c.queue_free()
	var fcol := Color(0.3, 0.85, 1.0)
	if mode == 0:
		var rg := _range(func(x: float) -> float: return F(x))
		_bd = {"f": {"cy": 0.0, "hh": HGT, "lo": rg.x, "hi": rg.y}}
		_board(0.0, HGT)
		_axes("f", "f(x) = " + f_expr.to_pretty(), fcol)
		_curve(func(x: float) -> float: return F(x), "f", fcol, 0.02, board_node)
		_draw_int()
	else:
		var rg1 := _range(func(x: float) -> float: return F(x))
		var rg2 := _range(func(x: float) -> float: return exact_d(x, order))
		_bd = {"f": {"cy": 1.0, "hh": 0.85, "lo": rg1.x, "hi": rg1.y}, "d": {"cy": -1.05, "hh": 0.85, "lo": rg2.x, "hi": rg2.y}}
		_board(1.0, 0.85)
		_board(-1.05, 0.85)
		_axes("f", "f(x) = " + f_expr.to_pretty(), fcol)
		var dname := "f′(x)" if order == 1 else "f″(x)"
		_axes("d", "%s: exacta (verde) y %s (naranja)" % [dname, DIFF_SHORT[dmethod]], Color(0.5, 1.0, 0.6))
		_curve(func(x: float) -> float: return F(x), "f", fcol, 0.02, board_node)
		_draw_diff()

## Malla de áreas bajo polígonos [[[x, y], …], color] (entre y = 0 y la curva).
func _areas(polys: Array, bd: String = "f") -> void:
	if polys.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y0 := _Y(0.0, bd)
	for pg in polys:
		var pts: Array = pg[0]
		var col: Color = pg[1]
		for i in range(pts.size() - 1):
			var p0: Array = pts[i]
			var p1: Array = pts[i + 1]
			if not (is_finite(float(p0[1])) and is_finite(float(p1[1]))):
				continue
			var c := col if float(p0[1]) + float(p1[1]) >= 0.0 else Color(1.0, 0.35, 0.35, col.a)
			var v00 := Vector3(_X(p0[0]), y0, 0.01)
			var v01 := Vector3(_X(p0[0]), _Y(p0[1], bd), 0.01)
			var v10 := Vector3(_X(p1[0]), y0, 0.01)
			var v11 := Vector3(_X(p1[0]), _Y(p1[1], bd), 0.01)
			for v in [v00, v01, v11, v00, v11, v10]:
				st.set_color(c)
				st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = vcolor_mat(0.42, 0.55)
	draw_node.add_child(mi)

## Polinomio de Lagrange por los puntos [[x, y], …] muestreado en k puntos.
static func _lagrange(pts: Array, k: int) -> Array:
	var out := []
	var x_0: float = pts[0][0]
	var x_1: float = pts[pts.size() - 1][0]
	for s in range(k + 1):
		var t := lerpf(x_0, x_1, float(s) / k)
		var v := 0.0
		for j in range(pts.size()):
			var l := 1.0
			for q in range(pts.size()):
				if q != j:
					l *= (t - float(pts[q][0])) / (float(pts[j][0]) - float(pts[q][0]))
			v += l * float(pts[j][1])
		out.append([t, v])
	return out

func _mcolor(m: int) -> Color:
	return Color.from_hsv(float(m) / 18.0 * 0.92, 0.6, 1.0)

func _draw_int() -> void:
	if str(sel.get("estado", "")) != "ok":
		return
	var col := _mcolor(imethod)
	var alt := col.darkened(0.35)
	var polys := []
	var edge := glow_mat(col, 1.8)
	var pt_mat := glow_mat(Color(1.0, 0.85, 0.3), 2.6)
	match imethod:
		0, 1, 2, 3, 4, 5, 6, 7, 11:
			var paneles: Array = sel.get("paneles", [])
			if imethod == 7:
				paneles = Quadrature.trapezoid(func(x: float) -> float: return F(x), a, b, int(sel["n"]))["paneles"]
			var many := paneles.size() > 70
			for i in range(paneles.size()):
				var pn: Array = paneles[i]
				var curve: Array = pn if pn.size() == 2 and float(pn[0][1]) == float(pn[1][1]) else _lagrange(pn, 10 if pn.size() > 2 else 1)
				polys.append([curve, col if i % 2 == 0 else alt])
				if not many:
					var tp := PackedVector3Array()
					for q in curve:
						tp.append(_p(q[0], q[1]) + Vector3(0, 0, 0.02))
					draw_node.add_child(tube(tp, 0.007, edge, 5))
					for q2 in pn:
						if imethod >= 3:
							var s := sphere(0.028, pt_mat)
							s.position = _p(q2[0], q2[1]) + Vector3(0, 0, 0.03)
							draw_node.add_child(s)
			if imethod <= 2 and not many:
				for nd in sel["nodos"]:
					var s2 := sphere(0.028, pt_mat)
					s2.position = _p(nd[0], F(nd[0])) + Vector3(0, 0, 0.03)
					draw_node.add_child(s2)
			if imethod == 11:
				for iv in sel.get("intervalos", []):
					draw_node.add_child(rod(_p(iv[0], 0.0) + Vector3(0, 0, 0.02), _p(iv[0], F(iv[0])) + Vector3(0, 0, 0.02), 0.004, glow_mat(Color(1, 1, 1), 0.8)))
		8, 9, 10, 12, 13:
			# Rectángulos equivalentes: anchura wᵢ y altura f(xᵢ), uno tras otro desde a.
			var nodos: Array = (sel["nodos"] as Array).duplicate()
			nodos.sort_custom(func(p, q): return float(p[0]) < float(q[0]))
			var fin := is_finite(a) and is_finite(b)
			var x_l := a if fin else float(nodos[0][0])
			for i in range(nodos.size()):
				var nd: Array = nodos[i]
				var fx := F(nd[0])
				var wdt: float = nd[1]
				if fin:
					polys.append([[[x_l, fx], [x_l + wdt, fx]], col if i % 2 == 0 else alt])
					x_l += wdt
				if nodos.size() <= 160:
					var s3 := sphere(0.026, pt_mat)
					s3.position = _p(nd[0], fx) + Vector3(0, 0, 0.03)
					draw_node.add_child(s3)
			if imethod == 10:
				for iv in sel.get("intervalos", []):
					if is_finite(float(iv[0])):
						draw_node.add_child(rod(_p(iv[0], 0.0) + Vector3(0, 0, 0.02), _p(iv[0], F(iv[0])) + Vector3(0, 0, 0.02), 0.004, glow_mat(Color(1, 1, 1), 0.8)))
		14, 15:
			var mean: float = sel.get("media", 0.0)
			polys.append([[[a, mean], [b, mean]], Color(col.r, col.g, col.b, 0.5)])
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			var sm := SphereMesh.new()
			sm.radius = 0.018
			sm.height = 0.036
			mm.mesh = sm
			var nod: Array = sel["nodos"]
			mm.instance_count = mini(nod.size(), 400)
			for i in range(mm.instance_count):
				mm.set_instance_transform(i, Transform3D(Basis(), _p(nod[i][0], nod[i][1]) + Vector3(0, 0, 0.03)))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = pt_mat
			draw_node.add_child(mmi)
		16, 17:
			var w := _window()
			for nd in sel["nodos"]:
				var x: float = nd[0]
				if x < w.x or x > w.y:
					continue
				var fx2 := F(x)
				draw_node.add_child(rod(_p(x, 0.0) + Vector3(0, 0, 0.02), _p(x, fx2) + Vector3(0, 0, 0.02), clampf(0.004 + 0.02 * float(nd[1]), 0.004, 0.03), edge))
				var s4 := sphere(0.03, pt_mat)
				s4.position = _p(x, fx2) + Vector3(0, 0, 0.03)
				draw_node.add_child(s4)
	_areas(polys)
	# Extremos de integración.
	for lim in [a, b]:
		if is_finite(lim):
			var q: Dictionary = _bd["f"]
			draw_node.add_child(rod(Vector3(_X(lim), float(q["cy"]) - float(q["hh"]), 0.015), Vector3(_X(lim), float(q["cy"]) + float(q["hh"]), 0.015), 0.006, glow_mat(Color(1.0, 0.5, 0.8), 1.2)))

func _draw_diff() -> void:
	var h := pow(10.0, h_exp)
	var fx0 := F(x0)
	var ex1 := exact_d(x0, 1)
	var ex2 := exact_d(x0, 2)
	var ap: float = sel.get("valor", NAN)
	var w := _window()
	var span := (w.y - w.x) * 0.3
	var green := glow_mat(Color(0.4, 1.0, 0.5), 1.8)
	var orange := glow_mat(Color(1.0, 0.6, 0.2), 2.0)
	# Tangente (f′) u osculatriz (f″): exacta y aproximada.
	for pair in [[true, green], [false, orange]]:
		var is_exact: bool = pair[0]
		var pts := PackedVector3Array()
		for k in range(41):
			var dx := span * (float(k) / 20.0 - 1.0)
			var y: float
			if order == 1:
				y = fx0 + (ex1 if is_exact else ap) * dx
			else:
				y = fx0 + ex1 * dx + 0.5 * (ex2 if is_exact else ap) * dx * dx
			if not is_finite(y):
				continue
			var q: Dictionary = _bd["f"]
			var tt := (y - float(q["lo"])) / (float(q["hi"]) - float(q["lo"]))
			if tt < -0.1 or tt > 1.1:
				continue
			pts.append(_p(x0 + dx, y) + Vector3(0, 0, 0.02 if is_exact else 0.03))
		if pts.size() >= 2 and (is_exact or is_finite(ap)):
			draw_node.add_child(tube(pts, 0.009, pair[1], 5))
	var s := sphere(0.045, glow_mat(Color(1.0, 1.0, 1.0), 2.5))
	s.position = _p(x0, fx0) + Vector3(0, 0, 0.04)
	draw_node.add_child(s)
	# Puntos que usa el método.
	var pmat := glow_mat(Color(1.0, 0.8, 0.25), 2.6)
	var pts2: Array = sel.get("puntos", [])
	var visible_h := absf(_X(x0 + h) - _X(x0)) > 0.02
	if dmethod in H_METHODS and not visible_h:
		draw_node.add_child(label3d("h = %s: los puntos de la plantilla están demasiado juntos para verse" % LabUI.sci(h, 1), _p(x0, fx0) + Vector3(0.1, 0.18, 0.05), Color(1.0, 0.8, 0.4), 0.0024))
	for q2 in pts2:
		if dmethod in [8, 9, 10] or pts2.size() > 60:
			break
		var sp := sphere(0.03, pmat)
		sp.position = _p(q2[0], q2[1]) + Vector3(0, 0, 0.05)
		draw_node.add_child(sp)
	# Secante de los métodos de 2 puntos.
	if dmethod in [0, 1, 2] and order == 1 and pts2.size() == 2 and visible_h:
		draw_node.add_child(rod(_p(pts2[0][0], pts2[0][1]) + Vector3(0, 0, 0.04), _p(pts2[1][0], pts2[1][1]) + Vector3(0, 0, 0.04), 0.006, orange))
	# Abajo: derivada exacta y aproximada en toda la ventana.
	_curve(func(x: float) -> float: return exact_d(x, order), "d", Color(0.4, 1.0, 0.5), 0.016, draw_node)
	var approx := func(x: float) -> float:
		return float(run_diff(dmethod, x, h)["valor"])
	_curve(approx, "d", Color(1.0, 0.6, 0.2), 0.012, draw_node)
	var qd: Dictionary = _bd["d"]
	draw_node.add_child(rod(Vector3(_X(x0), float(qd["cy"]) - float(qd["hh"]), 0.02), Vector3(_X(x0), float(qd["cy"]) + float(qd["hh"]), 0.02), 0.005, glow_mat(Color(1, 1, 1), 1.0)))

# --- Tabla ------------------------------------------------------------------------------------

func _fmt_err(e) -> String:
	var v := float(e)
	if is_nan(v):
		return "—"
	if v < 1e-16:
		return "< 10⁻¹⁶"
	return LabUI.sci(v, 2)

func info() -> String:
	if rows.is_empty():
		return ""
	var t := ""
	if mode == 0:
		var lim := "∫ de %s a %s" % [a_text, b_text]
		t += "[font_size=12][color=#8fa3b8]%s · referencia (%s): [/color][color=#ffcc55]%.15f[/color]\n" % [lim, ref_src, reference]
		if compare:
			t += "[color=#8fa3b8]método · error · evaluaciones · orden (observado)[/color]\n"
			for m in range(rows.size()):
				var r: Dictionary = rows[m]
				var name: String = INT_SHORT[m] if m != imethod else "[b]%s[/b]" % INT_SHORT[m]
				var sq := "[color=#%s]■[/color]" % _mcolor(m).to_html(false)
				if str(r["estado"]) != "ok":
					t += "%s %s · [color=#ff9977]%s[/color]\n" % [sq, name, r["estado"]]
				else:
					t += "%s %s · %s · %d ev · %s%s\n" % [sq, name, _fmt_err(r["error"]), int(r["evals"]), INT_ORDER[m],
						" (%.2f)" % float(r["orden_obs"]) if r.has("orden_obs") and not is_nan(float(r["orden_obs"])) else ""]
		else:
			var r2: Dictionary = sel
			t += "[b]%s[/b]" % INT_METHODS[imethod]
			if str(r2["estado"]) != "ok":
				t += ": [color=#ff9977]%s[/color]\n" % r2["estado"]
			else:
				t += ": [color=#ffcc55]%.15f[/color] · error %s · %d evaluaciones · orden %s%s\n" % [float(r2["valor"]), _fmt_err(r2["error"]), int(r2["evals"]), INT_ORDER[imethod],
					" (observado %.2f al duplicar n)" % float(r2["orden_obs"]) if r2.has("orden_obs") and not is_nan(float(r2["orden_obs"])) else ""]
				if r2.has("tabla"):
					var tab: Array = r2["tabla"]
					t += "[color=#8fa3b8]Tabla de Romberg (últimas filas):[/color]\n"
					for k in range(maxi(0, tab.size() - 4), tab.size()):
						var cells := []
						for v in tab[k]:
							cells.append("%.10f" % float(v))
						t += "  " + "  ".join(PackedStringArray(cells)) + "\n"
				if r2.has("sigma"):
					t += "Error estimado σ/√N = %s (el real queda dentro de ±2σ el 95 %% de las veces)\n" % LabUI.sci(float(r2["sigma"]), 2)
				if r2.has("error_est"):
					t += "Error estimado |K₁₅ − G₇| = %s en %d subintervalos\n" % [LabUI.sci(float(r2["error_est"]), 2), (r2["intervalos"] as Array).size()]
				elif r2.has("intervalos"):
					t += "%d subintervalos adaptativos\n" % (r2["intervalos"] as Array).size()
				if r2.has("niveles"):
					t += "%d niveles (h = 2⁻ᵏ), variante %s\n" % [int(r2["niveles"]), str(r2["variante"])]
		t += "[/font_size]"
		return t.strip_edges()
	var dn := "f′" if order == 1 else "f″"
	var d := d1_expr if order == 1 else d2_expr
	var ex := exact_d(x0, order)
	t += "[font_size=12][color=#8fa3b8]%s(x) = [/color]%s\n" % [dn, d.to_pretty() if d and d.ok() else "—"]
	t += "[color=#8fa3b8]x₀ = %s · h = %s · exacta %s(x₀) = [/color][color=#ffcc55]%.15f[/color]%s\n" % [str(x0), LabUI.sci(pow(10.0, h_exp), 2), dn, ex, "  · ruido 10^%d" % int(noise_exp) if noise_exp > -16.5 else ""]
	if compare:
		t += "[color=#8fa3b8]método · error · evaluaciones · orden (observado)[/color]\n"
		for m in range(rows.size()):
			var r3: Dictionary = rows[m]
			var name2: String = DIFF_SHORT[m] if m != dmethod else "[b]%s[/b]" % DIFF_SHORT[m]
			var sq2 := "[color=#%s]■[/color]" % _mcolor(m).to_html(false)
			var ot: String = (DIFF_ORDER1 if order == 1 else DIFF_ORDER2)[m]
			t += "%s %s · %s · %d ev · %s%s\n" % [sq2, name2, _fmt_err(r3["error"]), int(r3["evals"]), ot,
				" (%.2f)" % float(r3["orden_obs"]) if r3.has("orden_obs") and not is_nan(float(r3["orden_obs"])) else ""]
	else:
		var r4: Dictionary = sel
		var ot2: String = (DIFF_ORDER1 if order == 1 else DIFF_ORDER2)[dmethod]
		t += "[b]%s[/b]: [color=#ffcc55]%.15f[/color] · error %s · %d evaluaciones · orden %s%s\n" % [DIFF_METHODS[dmethod], float(r4["valor"]), _fmt_err(r4["error"]), int(r4["evals"]), ot2,
			" (observado %.2f)" % float(r4["orden_obs"]) if r4.has("orden_obs") and not is_nan(float(r4["orden_obs"])) else ""]
		if is_finite(h_opt):
			t += "h óptimo ≈ %s (error mínimo %s); con h menor domina el redondeo\n" % [LabUI.sci(h_opt, 1), _fmt_err(e_opt)]
		if r4.has("tabla"):
			var tab2: Array = r4["tabla"]
			t += "[color=#8fa3b8]Tabla de Richardson:[/color]\n"
			for row in tab2:
				var cells2 := []
				for v in row:
					cells2.append("%.12f" % float(v))
				t += "  " + "  ".join(PackedStringArray(cells2)) + "\n"
	t += "[/font_size]"
	return t.strip_edges()

# --- Interfaz ---------------------------------------------------------------------------------

func build_ui(p: VBoxContainer) -> void:
	_panel = p
	LabUI.option(p, "Modo:", ["Integración ∫ f(x) dx", "Derivación f′(x), f″(x)"], mode, func(i): set_mode(i))
	if mode == 0:
		LabUI.option(p, "Ejemplo:", INT_PRESETS.map(func(q): return q["nombre"]), ipreset, func(i): _load_int(i))
		_ui["f"] = LabUI.expr_field(p, "f(x) =", f_expr.source, ["x"], false, func(m): set_f(m))
		var r := LabUI.row(p)
		_ui["a"] = LabUI.value_field(r, "a =", a_text, func(v, t):
			a = v
			a_text = t
			exact = NAN if not _preset_limits() else exact
			_changed())
		_ui["b"] = LabUI.value_field(r, "b =", b_text, func(v, t):
			b = v
			b_text = t
			exact = NAN if not _preset_limits() else exact
			_changed())
		LabUI.option(p, "Método:", INT_METHODS, imethod, func(i): set_int_method(i))
		LabUI.slider(p, "n (subintervalos o nodos)", 1, 128, 1, n, func(v):
			n = int(v)
			_changed(), "%.0f")
		LabUI.slider(p, "Tolerancia 10ᵏ (adaptativas y tanh-sinh)", -14, -2, 1, tol_exp, func(v):
			tol_exp = v
			_changed(), "%.0f")
		LabUI.slider(p, "Muestras N = 10ᵏ (Monte Carlo)", 1, 5, 0.25, mc_exp, func(v):
			mc_exp = v
			_changed(), "%.2f")
	else:
		LabUI.option(p, "Ejemplo:", DIFF_PRESETS.map(func(q): return q["nombre"]), dpreset, func(i): _load_diff(i))
		_ui["f"] = LabUI.expr_field(p, "f(x) =", f_expr.source, ["x"], false, func(m): set_f(m))
		LabUI.option(p, "Derivada:", ["Primera f′(x₀)", "Segunda f″(x₀)"], order - 1, func(i):
			order = i + 1
			_changed())
		LabUI.option(p, "Método:", DIFF_METHODS, dmethod, func(i): set_diff_method(i))
		_ui["x0"] = LabUI.value_field(p, "x₀ =", str(x0), func(v, _t):
			x0 = v
			_changed())
		LabUI.slider(p, "Paso h = 10ᵏ", -16, 0, 0.25, h_exp, func(v):
			h_exp = v
			_changed(), "%.2f")
		LabUI.slider(p, "Ruido en f: 10ᵏ (−17 = sin ruido)", -17, -1, 1, noise_exp, func(v):
			noise_exp = v
			_changed(), "%.0f")
		LabUI.slider(p, "N de Chebyshev", 4, 64, 1, n_cheb, func(v):
			n_cheb = int(v)
			_changed(), "%.0f")
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
		LabUI.note(p, "Rectángulos de colores: lo que suma el método. En las reglas de Gauss, cada rectángulo tiene la anchura del peso wᵢ y la altura f(xᵢ). En rojo, el área bajo el eje (negativa).")
	else:
		LabUI.note(p, "Verde: exacta (diferenciación automática). Naranja: el método con este h. El ruido solo afecta a los métodos que usan muestras de f.")

func _preset_limits() -> bool:
	var p: Dictionary = INT_PRESETS[ipreset]
	return p["a"] == a_text and p["b"] == b_text and f_expr != null and f_expr.source == p["f"]

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

# --- Ratón y API ---------------------------------------------------------------------------

func pick(origin: Vector3, dir: Vector3):
	if absf(dir.z) < 1e-6:
		return null
	var t := -origin.z / dir.z
	if t < 0.0:
		return null
	var p := origin + dir * t
	var lp := p - Vector3(0, LIFT, 0)
	if absf(lp.x) > W or absf(lp.y) > HGT + 0.2:
		return null
	return p

func hover_text(hit: Vector3) -> String:
	var x := _xw(hit.x)
	var j := f_expr.eval_jet({"x": x}, "x")
	return "x = %.5f\nf(x) = %.6f\nf′(x) = %.6f\nf″(x) = %.6f" % [x, float(j[0]), float(j[1]), float(j[2])]

func perturb(hit: Vector3, first: bool) -> void:
	if not first:
		return
	var x := _xw(hit.x)
	if mode == 1:
		x0 = snappedf(x, 0.001)
		if _ui.has("x0"):
			(_ui["x0"] as LineEdit).text = str(x0)
			(_ui["x0"] as LineEdit).text_changed.emit(str(x0))
	else:
		var s := snappedf(x, 0.01)
		if is_finite(a) and (not is_finite(b) or absf(x - a) <= absf(x - b)):
			a = minf(s, b - 0.01) if is_finite(b) else s
			a_text = str(a)
			if _ui.has("a"):
				(_ui["a"] as LineEdit).text = a_text
				(_ui["a"] as LineEdit).text_changed.emit(a_text)
		elif is_finite(b):
			b = maxf(s, a + 0.01) if is_finite(a) else s
			b_text = str(b)
			if _ui.has("b"):
				(_ui["b"] as LineEdit).text = b_text
				(_ui["b"] as LineEdit).text_changed.emit(b_text)
		exact = NAN
	_changed()

func api_points(x: float, y: float) -> Array:
	return [to_global(_p(x, y))]

func critical_points() -> Array:
	var out := []
	if mode == 1:
		out.append({"pos": to_global(_p(x0, F(x0))), "nombre": "x₀ = %s" % str(x0), "dist": 3.0})
	else:
		if is_finite(a):
			out.append({"pos": to_global(_p(a, 0.0)), "nombre": "a = %s" % a_text, "dist": 3.0})
		if is_finite(b):
			out.append({"pos": to_global(_p(b, 0.0)), "nombre": "b = %s" % b_text, "dist": 3.0})
	return out

## Capturas: «derivar», «comparar», «gauss», «montecarlo», «tanh», «simpson», «ruido».
func demo(extra: Array) -> void:
	if "derivar" in extra:
		set_mode(1)
		if "ruido" in extra:
			noise_exp = -8.0
			h_exp = -3.0
			set_diff_method(11)
	if "comparar" in extra:
		compare = true
	if "gauss" in extra:
		n = 5
		set_int_method(8)
	elif "montecarlo" in extra:
		mc_exp = 2.5
		set_int_method(14)
	elif "tanh" in extra:
		_load_int(4)
		set_int_method(13)
	elif "simpson" in extra:
		n = 6
		set_int_method(4)
	_changed()
	if _panel:
		_rebuild_ui()

# --- Gráfica del error ----------------------------------------------------------------------

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
		var x_hi := 0.0 if diff else 4.5
		var y_lo := -17.0
		var y_hi := 1.0
		for k in range(-16, 1, 4):
			var y := r.size.y * (y_hi - k) / (y_hi - y_lo)
			draw_line(Vector2(0, y), Vector2(r.size.x, y), Color(0.2, 0.3, 0.4, 0.5))
			draw_string(font, Vector2(3, y - 2), "10^%d" % k, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.55, 0.65, 0.75))
		var ticks := range(-16, 1, 4) if diff else range(0, 5)
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
