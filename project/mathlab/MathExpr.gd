class_name MathExpr
extends RefCounted
## MathExpr — Motor de expresiones matemáticas del Laboratorio.
##
## Un único analizador para todo el laboratorio: la expresión que escribe el
## usuario ("sin(x)*cos(y)", "z^3 - 1", "(z-i)/(z+i)", "-y/(x^2+y^2)"…) se
## convierte en un árbol sintáctico y desde ahí:
##   · se evalúa en CPU con números reales (eval_real) o complejos (eval_c);
##   · se compila a una Expression nativa de Godot para evaluaciones masivas
##     (líneas de corriente, integrales) — compile_fast / eval_fast;
##   · se traduce a GLSL real (to_glsl) o complejo (to_glsl_complex): la misma
##     fórmula se evalúa en la GPU en los shaders (superficies z = f(x, y),
##     coloreado de dominio, partículas del campo vectorial);
##   · se deriva simbólicamente (derivative) y se escribe en notación matemática
##     legible (to_pretty) o en texto que se puede volver a leer (to_text);
##   · se evalúa con diferenciación automática de 1.º y 2.º orden (eval_jet) y en
##     aritmética compleja de doble precisión (eval_cd, para el paso complejo).
##
## Notación cómoda (se escribe como en papel):
##   · multiplicación implícita: 2x, 3(x+1), x y, 2πx, 2 sin x;
##   · funciones sin paréntesis: sin x, ln x, sin 2x (= sin(2x)), sin x cos x;
##     potencias de funciones: sin^2 x, cos²x; inversas: sin^-1 x = asin x;
##   · nombres en español: sen, tg, arcsen, arctg, senh, raíz, sgn…;
##   · superíndices y símbolos: x², e⁻ˣ, x⁻¹, √x, ∛x, π, ½, ·, ×, ÷, −, ∞;
##   · palabras pegadas: sinx, xsinx, sen2x se separan solas;
##   · e^x, e^-x² y exp x son lo mismo que exp(x); exp^(−x) también se entiende;
##   · log_2 x, log2 x (base 2); log y ln son el logaritmo natural;
##   · coma decimal (0,5) si no hay funciones de dos argumentos;
##   · los paréntesis y barras | sin cerrar al final se cierran solos (aviso en notes).

const FUNCS_REAL := {
	"sin": 1, "cos": 1, "tan": 1, "asin": 1, "acos": 1, "atan": 1, "atan2": 2,
	"sinh": 1, "cosh": 1, "tanh": 1, "asinh": 1, "acosh": 1, "atanh": 1, "exp": 1, "log": 1, "ln": 1, "log10": 1,
	"sqrt": 1, "cbrt": 1, "abs": 1, "floor": 1, "ceil": 1, "sign": 1,
	"min": 2, "max": 2, "pow": 2, "mod": 2, "sec": 1, "csc": 1, "cot": 1,
}
const FUNCS_COMPLEX := {
	"sin": 1, "cos": 1, "tan": 1, "sinh": 1, "cosh": 1, "tanh": 1, "exp": 1,
	"log": 1, "ln": 1, "sqrt": 1, "abs": 1, "conj": 1, "re": 1, "im": 1, "arg": 1, "pow": 2,
}
## Otros nombres de las funciones (español y variantes habituales).
const ALIASES := {
	"sen": "sin", "tg": "tan", "tang": "tan", "senh": "sinh", "tgh": "tanh",
	"arcsen": "asin", "arcsin": "asin", "asen": "asin", "arccos": "acos", "arctan": "atan", "arctg": "atan", "atg": "atan",
	"arcsenh": "asinh", "arcsinh": "asinh", "asenh": "asinh", "argsenh": "asinh", "argsinh": "asinh",
	"arccosh": "acosh", "argcosh": "acosh", "arctanh": "atanh", "arctgh": "atanh", "argtanh": "atanh",
	"raiz": "sqrt", "raíz": "sqrt", "rcuad": "sqrt", "rcub": "cbrt", "sgn": "sign", "signo": "sign",
	"cosec": "csc", "cotg": "cot", "ctg": "cot", "cotan": "cot", "piso": "floor", "techo": "ceil", "abs": "abs",
}
const INVERSES := {"sin": "asin", "cos": "acos", "tan": "atan", "sinh": "asinh", "cosh": "acosh", "tanh": "atanh"}
const E_NUM := 2.718281828459045
const CONSTS := {"pi": PI, "π": PI, "e": E_NUM, "tau": TAU, "τ": TAU, "inf": INF}
const CONST_LABEL := {"pi": "π", "π": "π", "e": "e", "tau": "τ", "τ": "τ", "inf": "∞"}
const CONST_TEXT := {"π": "pi", "e": "e", "τ": "tau", "∞": "inf"}
const SUPERSCRIPTS := {"⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9",
	"⁻": "-", "⁺": "+", "⁽": "(", "⁾": ")", "ˣ": "x", "ʸ": "y", "ᶻ": "z", "ⁿ": "n", "ᵗ": "t", "ⁱ": "i", "ᵃ": "a", "ᵇ": "b", "ᵏ": "k"}
const TO_SUPER := {"0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
	"-": "⁻", "−": "⁻", "+": "⁺", "(": "⁽", ")": "⁾", "x": "ˣ", "y": "ʸ", "z": "ᶻ", "n": "ⁿ", "t": "ᵗ", "i": "ⁱ", "a": "ᵃ", "b": "ᵇ", "k": "ᵏ"}
const FRACTIONS := {"½": "(1/2)", "⅓": "(1/3)", "⅔": "(2/3)", "¼": "(1/4)", "¾": "(3/4)", "⅕": "(1/5)", "⅛": "(1/8)"}
const MULTI_ARG := ["atan2", "min", "max", "pow", "mod"]

var ast = null
var error: String = ""
var source: String = ""
var complex_mode: bool = false
var variables: Array = []
var notes: Array = []           # avisos de la lectura (paréntesis añadidos, coma decimal…)
var _tokens: Array = []
var _pos: int = 0
var _abs_depth: int = 0
var _fast: Expression
var _fast_names: PackedStringArray

## Analiza "text". "vars": nombres de variables permitidos (p. ej. ["x", "y"]).
## complex = true: modo complejo (i es la unidad imaginaria).
static func parse(text: String, vars: Array, complex := false) -> MathExpr:
	var m := MathExpr.new()
	m.source = text
	m.complex_mode = complex
	m.variables = vars
	m._run()
	return m

func ok() -> bool:
	return error == "" and ast != null

func _run() -> void:
	error = _tokenize(_normalize(source))
	if error != "":
		return
	if _tokens.is_empty():
		error = "La expresión está vacía."
		return
	_autoclose()
	_pos = 0
	ast = _expr()
	if error == "" and _pos < _tokens.size():
		var t = _tokens[_pos]
		error = "Sobra «%s»." % str(t[1]) if not _is_op(t, ")") else "Sobra un «)» (hay más paréntesis cerrados que abiertos)."
	if error != "":
		ast = null

# --- Normalización y analizador léxico ----------------------------------------------

## Símbolos de «papel» → texto que entiende el analizador.
func _normalize(s: String) -> String:
	s = s.replace("**", "^")
	for k in ["·", "⋅", "∙", "×"]:
		s = s.replace(k, "*")
	for k in ["−", "–", "—"]:
		s = s.replace(k, "-")
	s = s.replace("÷", "/").replace("∞", " inf ")
	for k in FRACTIONS:
		s = s.replace(k, FRACTIONS[k])
	# Superíndices: x² → x^(2), e⁻ˣ → e^(-x).
	var out := ""
	var i := 0
	while i < s.length():
		if SUPERSCRIPTS.has(s[i]):
			var run := ""
			while i < s.length() and SUPERSCRIPTS.has(s[i]):
				run += SUPERSCRIPTS[s[i]]
				i += 1
			out += "^(" + run + ")"
		else:
			out += s[i]
			i += 1
	s = out
	# Coma decimal (0,5) si no hay funciones cuyos argumentos se separen con comas.
	var multi := false
	for f in MULTI_ARG:
		if s.find(f + "(") >= 0 or s.find(f + " (") >= 0:
			multi = true
	if not multi:
		var re := RegEx.create_from_string("(\\d),(\\d)")
		if re.search(s) != null:
			s = re.sub(s, "$1.$2", true)
			notes.append("La coma se leyó como decimal (0,5 = 0.5).")
	return s

func _tokenize(s: String) -> String:
	_tokens = []
	var i := 0
	var n := s.length()
	while i < n:
		var ch := s[i]
		if ch == " " or ch == "\t":
			i += 1
			continue
		if ch.is_valid_int() or (ch == "." and i + 1 < n and s[i + 1].is_valid_int()):
			var j := i
			while j < n and (s[j].is_valid_int() or s[j] == "."):
				j += 1
			if j < n and (s[j] == "e" or s[j] == "E") and j + 1 < n and (s[j + 1].is_valid_int() or ((s[j + 1] == "-" or s[j + 1] == "+") and j + 2 < n and s[j + 2].is_valid_int())):
				j += 2
				while j < n and s[j].is_valid_int():
					j += 1
			var num := s.substr(i, j - i)
			if not num.is_valid_float():
				return "Número mal escrito: «%s»." % num
			_tokens.append(["num", float(num)])
			i = j
			continue
		if _is_ident_char(ch, true):
			var j2 := i
			while j2 < n and _is_ident_char(s[j2], false):
				j2 += 1
			var name := s.substr(i, j2 - i)
			if _known_name(name):
				_tokens.append(["id", name])
			else:
				# Palabras pegadas: «sinx» → sin x, «xsinx» → x sin x, «sen2x» → sen 2 x.
				var parts := _split_name(name)
				if parts.is_empty():
					_tokens.append(["id", name])
				else:
					var shown := []
					for p in parts:
						shown.append(_num_text(p[1]) if p[0] == "num" else str(p[1]))
					if parts.any(func(p): return p[0] == "id" and (_canon(str(p[1])) != "" or _log_base(str(p[1])) > 0.0)):
						notes.append("«%s» se leyó como «%s»." % [name, " ".join(PackedStringArray(shown))])
					_tokens.append_array(parts)
			i = j2
			continue
		if ch in ["+", "-", "*", "/", "^", "(", ")", ",", "|", "√", "∛"]:
			_tokens.append(["op", ch])
			i += 1
			continue
		return "Carácter no válido: «%s»." % ch
	return ""

static func _is_ident_char(c: String, first: bool) -> bool:
	if c in ["π", "τ", "_", "á", "é", "í", "ó", "ú", "ñ", "ü", "Á", "É", "Í", "Ó", "Ú", "Ñ"]:
		return true
	var u := c.unicode_at(0)
	var alpha := (u >= 65 and u <= 90) or (u >= 97 and u <= 122)
	return alpha or (not first and c.is_valid_int())

## Nombre canónico de una función (admite alias y mayúsculas) o "".
func _canon(name: String) -> String:
	var funcs: Dictionary = FUNCS_COMPLEX if complex_mode else FUNCS_REAL
	if funcs.has(name):
		return name
	var low := name.to_lower()
	if funcs.has(low):
		return low
	if ALIASES.has(low) and funcs.has(ALIASES[low]):
		return ALIASES[low]
	return ""

## Base de log2, log_2, log_10…; 0 si no es un logaritmo con base.
static func _log_base(name: String) -> float:
	if name == "log2":
		return 2.0
	if name.begins_with("log_"):
		var r := name.substr(4)
		if r.is_valid_float() and float(r) > 0.0 and float(r) != 1.0:
			return float(r)
	return 0.0

func _known_name(name: String) -> bool:
	return name in variables or _canon(name) != "" or _log_base(name) > 0.0 or CONSTS.has(name) or (complex_mode and name == "i")

## Separa un nombre desconocido en piezas conocidas (variables, funciones,
## constantes y números), prefiriendo las piezas más largas.
func _split_name(name: String) -> Array:
	var memo := {}
	var r = _split_from(name, 0, memo)
	return r if r != null else []

func _split_from(name: String, i: int, memo: Dictionary):
	if i == name.length():
		return []
	if memo.has(i):
		return memo[i]
	var best = null
	for j in range(name.length(), i, -1):
		var piece := name.substr(i, j - i)
		var tok = null
		if piece.is_valid_int():
			tok = ["num", float(piece)]
		elif _known_name(piece):
			tok = ["id", piece]
		if tok == null:
			continue
		var rest = _split_from(name, j, memo)
		if rest != null:
			best = [tok] + rest
			break
	memo[i] = best
	return best

## Cierra al final los paréntesis y barras | que quedaron abiertos.
func _autoclose() -> void:
	var depth := 0
	var bars := 0
	for t in _tokens:
		if _is_op(t, "("):
			depth += 1
		elif _is_op(t, ")"):
			depth -= 1
		elif _is_op(t, "|"):
			bars += 1
	if bars % 2 == 1:
		_tokens.append(["op", "|"])
		notes.append("Se añadió «|» al final.")
	if depth > 0:
		for k in range(depth):
			_tokens.append(["op", ")"])
		notes.append("Se añadió «)» al final." if depth == 1 else "Se añadieron %d «)» al final." % depth)

## Nombre conocido más parecido (para los mensajes de error).
func _suggest(name: String) -> String:
	var cands: Array = variables.duplicate()
	cands.append_array((FUNCS_COMPLEX if complex_mode else FUNCS_REAL).keys())
	cands.append_array(ALIASES.keys())
	cands.append_array(["pi", "e", "tau"])
	var best := ""
	var best_d := 2 if name.length() > 3 else 1
	for c in cands:
		var dd := _edit_distance(name.to_lower(), str(c))
		if dd <= best_d and (best == "" or dd < _edit_distance(name.to_lower(), best)):
			best = str(c)
	return best

static func _edit_distance(a: String, b: String) -> int:
	var prev := []
	for j in range(b.length() + 1):
		prev.append(j)
	for i in range(1, a.length() + 1):
		var cur := [i]
		for j in range(1, b.length() + 1):
			var cost := 0 if a[i - 1] == b[j - 1] else 1
			cur.append(mini(mini(int(prev[j]) + 1, int(cur[j - 1]) + 1), int(prev[j - 1]) + cost))
		prev = cur
	return int(prev[b.length()])

# --- Analizador sintáctico (descenso recursivo) ----------------------------------

func _peek():
	return _tokens[_pos] if _pos < _tokens.size() else null

func _is_op(t, o: String) -> bool:
	return t != null and t[0] == "op" and t[1] == o

func _is_fn_token(t) -> bool:
	return t != null and t[0] == "id" and (_canon(str(t[1])) != "" or _log_base(str(t[1])) > 0.0)

func _expr():
	var left = _term()
	while error == "":
		var t = _peek()
		if _is_op(t, "+") or _is_op(t, "-"):
			_pos += 1
			left = ["bin", t[1], left, _term()]
		else:
			break
	return left

## ¿El siguiente token empieza un factor (multiplicación implícita)?
func _starts_factor(t) -> bool:
	if t == null:
		return false
	if t[0] == "num" or t[0] == "id":
		return true
	# «|» abre un valor absoluto (2|x|, x|x|) salvo si cierra uno abierto.
	return _is_op(t, "(") or _is_op(t, "√") or _is_op(t, "∛") or (_is_op(t, "|") and _abs_depth == 0)

func _term():
	var left = _unary()
	while error == "":
		var t = _peek()
		if _is_op(t, "*") or _is_op(t, "/"):
			_pos += 1
			left = ["bin", t[1], left, _unary()]
		elif _starts_factor(t):
			left = ["bin", "*", left, _power()]
		else:
			break
	return left

func _unary():
	var t = _peek()
	if _is_op(t, "-"):
		_pos += 1
		return ["neg", _unary()]
	if _is_op(t, "+"):
		_pos += 1
		return _unary()
	return _power()

func _power():
	var base = _primary()
	if error != "":
		return base
	if _is_op(_peek(), "^"):
		_pos += 1
		return ["bin", "^", base, _unary()]
	return base

## Argumento de una función escrita sin paréntesis: el producto implícito que
## sigue («sin 2x» = sin(2x)), hasta un operador o el nombre de otra función
## («sin x cos x» = sin(x)·cos(x)).
func _fn_arg():
	if _is_op(_peek(), "-"):
		_pos += 1
		return ["neg", _fn_arg()]
	var node = _power()
	while error == "" and _starts_factor(_peek()) and not _is_fn_token(_peek()):
		node = ["bin", "*", node, _power()]
	return node

func _primary():
	var t = _peek()
	if t == null:
		error = "Falta un operando al final."
		return null
	if t[0] == "num":
		_pos += 1
		return ["num", t[1]]
	if _is_op(t, "("):
		_pos += 1
		if _is_op(_peek(), ")"):
			error = "Paréntesis vacíos «()»."
			return null
		var e = _expr()
		if not _is_op(_peek(), ")"):
			if error == "": error = "Falta cerrar un paréntesis «)»."
			return e
		_pos += 1
		return e
	if _is_op(t, "|"):
		_pos += 1
		_abs_depth += 1
		var e2 = _expr()
		_abs_depth -= 1
		if not _is_op(_peek(), "|"):
			if error == "": error = "Falta cerrar el valor absoluto «|»."
			return e2
		_pos += 1
		return ["call", "abs", [e2]]
	if _is_op(t, "√") or _is_op(t, "∛"):
		_pos += 1
		if _peek() == null:
			error = "Falta lo que va dentro de %s." % t[1]
			return null
		var inner = _unary()
		return ["call", "sqrt" if t[1] == "√" else "cbrt", [inner]]
	if t[0] == "id":
		_pos += 1
		var name: String = t[1]
		var canon := _canon(name)
		var base := _log_base(name)
		if canon != "" or base > 0.0:
			return _function(name, canon, base)
		if name in variables:
			return ["var", name]
		if complex_mode and name == "i":
			return ["cnum", Vector2(0, 1)]
		if CONSTS.has(name):
			return ["num", CONSTS[name], CONST_LABEL[name]]
		var sug := _suggest(name)
		error = "No conozco «%s».%s Variables: %s." % [name, " ¿Quisiste decir «%s»?" % sug if sug != "" else "", ", ".join(PackedStringArray(variables))]
		return null
	error = "Símbolo inesperado: «%s»." % str(t[1])
	return null

## Llamada a función, con o sin paréntesis, con potencia (sin^2 x) o inversa (sin^-1 x).
func _function(name: String, canon: String, base: float):
	var funcs: Dictionary = FUNCS_COMPLEX if complex_mode else FUNCS_REAL
	# «exp^(…)» se entiende como e^(…).
	if canon == "exp" and _is_op(_peek(), "^"):
		_pos += 1
		notes.append("«exp^…» se leyó como e^….")
		return ["bin", "^", ["num", E_NUM, "e"], _unary()]
	var power = null
	if _is_op(_peek(), "^"):
		_pos += 1
		var neg := false
		if _is_op(_peek(), "-"):
			_pos += 1
			neg = true
		var ex0 = _primary()
		if error != "" or ex0 == null:
			return null
		var ex: Array = ex0
		if neg and ex[0] == "num" and float(ex[1]) == 1.0 and INVERSES.has(canon) and funcs.has(INVERSES[canon]):
			canon = INVERSES[canon]
		else:
			power = ["neg", ex] if neg else ex
	var arity := 1 if base > 0.0 else int(funcs[canon])
	var shown := canon if canon != "" else name
	var args := []
	if _is_op(_peek(), "("):
		_pos += 1
		if not _is_op(_peek(), ")"):
			args.append(_expr())
			while error == "" and _is_op(_peek(), ","):
				_pos += 1
				args.append(_expr())
		if not _is_op(_peek(), ")"):
			if error == "": error = "Falta «)» en la llamada a %s." % shown
			return null
		_pos += 1
		if args.size() != arity:
			error = "%s necesita %d argumento(s)." % [shown, arity]
			return null
	else:
		if arity != 1:
			error = "%s necesita paréntesis: %s(a, b)." % [shown, shown]
			return null
		var nx = _peek()
		if not (_starts_factor(nx) or _is_op(nx, "-") or (_is_op(nx, "|") and _abs_depth == 0)):
			error = "Falta el argumento de %s: escribe %s x o %s(x)." % [name, name, name]
			return null
		args.append(_fn_arg())
		if error != "":
			return null
	var node
	if base > 0.0:
		node = ["bin", "/", ["call", "ln", [args[0]]], ["num", log(base), "ln(%s)" % _num_text(base)]]
	else:
		node = ["call", canon, args]
	if power != null:
		node = ["bin", "^", node, power]
	return node

# --- Evaluación real ---------------------------------------------------------------

func eval_real(vars: Dictionary) -> float:
	return _er(ast, vars) if ast != null else NAN

func _er(n, v: Dictionary) -> float:
	match n[0]:
		"num": return n[1]
		"cnum": return NAN
		"var": return float(v.get(n[1], 0.0))
		"neg": return -_er(n[1], v)
		"bin":
			var a := _er(n[2], v)
			var b := _er(n[3], v)
			match n[1]:
				"+": return a + b
				"-": return a - b
				"*": return a * b
				"/": return a / b if b != 0.0 else (INF if a >= 0.0 else -INF)
				"^": return _rpow(a, b)
		"call":
			var args: Array = n[2]
			var x := _er(args[0], v)
			match n[1]:
				"sin": return sin(x)
				"cos": return cos(x)
				"tan": return tan(x)
				"asin": return asin(x)
				"acos": return acos(x)
				"atan": return atan(x)
				"atan2": return atan2(x, _er(args[1], v))
				"sinh": return sinh(x)
				"cosh": return cosh(x)
				"tanh": return tanh(x)
				"asinh": return log(x + sqrt(x * x + 1.0))
				"acosh": return log(x + sqrt(x * x - 1.0))
				"atanh": return 0.5 * log((1.0 + x) / (1.0 - x))
				"exp": return exp(x)
				"log", "ln": return log(x)
				"log10": return log(x) / log(10.0)
				"sqrt": return sqrt(x)
				"cbrt": return signf(x) * pow(absf(x), 1.0 / 3.0)
				"abs": return absf(x)
				"floor": return floor(x)
				"ceil": return ceil(x)
				"sign": return signf(x)
				"min": return minf(x, _er(args[1], v))
				"max": return maxf(x, _er(args[1], v))
				"pow": return _rpow(x, _er(args[1], v))
				"mod": return fmod(x, _er(args[1], v))
				"sec": return 1.0 / cos(x)
				"csc": return 1.0 / sin(x)
				"cot": return 1.0 / tan(x)
	return NAN

static func _rpow(a: float, b: float) -> float:
	if a < 0.0 and b == floor(b):
		var r := pow(-a, b)
		return -r if int(absf(b)) % 2 == 1 else r
	return pow(a, b)

# --- Evaluación compleja (Vector2 = re + i·im) --------------------------------------

func eval_c(vars: Dictionary) -> Vector2:
	return _ec(ast, vars) if ast != null else Vector2(NAN, NAN)

static func cmul(a: Vector2, b: Vector2) -> Vector2:
	return Vector2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x)

static func cdiv(a: Vector2, b: Vector2) -> Vector2:
	var d := b.dot(b)
	if d == 0.0:
		return Vector2(INF, INF)
	return Vector2(a.x * b.x + a.y * b.y, a.y * b.x - a.x * b.y) / d

static func cexp(z: Vector2) -> Vector2:
	return exp(z.x) * Vector2(cos(z.y), sin(z.y))

static func clog(z: Vector2) -> Vector2:
	return Vector2(log(z.length()), atan2(z.y, z.x))

static func cpow(a: Vector2, b: Vector2) -> Vector2:
	if b.y == 0.0 and b.x == floor(b.x) and absf(b.x) <= 16.0:
		var n := int(b.x)
		var r := Vector2(1, 0)
		for k in range(absi(n)):
			r = cmul(r, a)
		return cdiv(Vector2(1, 0), r) if n < 0 else r
	if a.length() == 0.0:
		return Vector2.ZERO
	return cexp(cmul(b, clog(a)))

static func csin(z: Vector2) -> Vector2:
	return Vector2(sin(z.x) * cosh(z.y), cos(z.x) * sinh(z.y))

static func ccos(z: Vector2) -> Vector2:
	return Vector2(cos(z.x) * cosh(z.y), -sin(z.x) * sinh(z.y))

static func csqrt(z: Vector2) -> Vector2:
	var r := z.length()
	var s := 1.0 if z.y >= 0.0 else -1.0
	return Vector2(sqrt(maxf(0.0, 0.5 * (r + z.x))), s * sqrt(maxf(0.0, 0.5 * (r - z.x))))

func _ec(n, v: Dictionary) -> Vector2:
	match n[0]:
		"num": return Vector2(n[1], 0)
		"cnum": return n[1]
		"var":
			var val = v.get(n[1], Vector2.ZERO)
			return val if val is Vector2 else Vector2(float(val), 0)
		"neg": return -_ec(n[1], v)
		"bin":
			var a := _ec(n[2], v)
			var b := _ec(n[3], v)
			match n[1]:
				"+": return a + b
				"-": return a - b
				"*": return cmul(a, b)
				"/": return cdiv(a, b)
				"^": return cpow(a, b)
		"call":
			var args: Array = n[2]
			var z := _ec(args[0], v)
			match n[1]:
				"sin": return csin(z)
				"cos": return ccos(z)
				"tan": return cdiv(csin(z), ccos(z))
				"sinh": return Vector2(sinh(z.x) * cos(z.y), cosh(z.x) * sin(z.y))
				"cosh": return Vector2(cosh(z.x) * cos(z.y), sinh(z.x) * sin(z.y))
				"tanh": return cdiv(Vector2(sinh(z.x) * cos(z.y), cosh(z.x) * sin(z.y)), Vector2(cosh(z.x) * cos(z.y), sinh(z.x) * sin(z.y)))
				"exp": return cexp(z)
				"log", "ln": return clog(z)
				"sqrt": return csqrt(z)
				"abs": return Vector2(z.length(), 0)
				"conj": return Vector2(z.x, -z.y)
				"re": return Vector2(z.x, 0)
				"im": return Vector2(z.y, 0)
				"arg": return Vector2(atan2(z.y, z.x), 0)
				"pow": return cpow(z, _ec(args[1], v))
	return Vector2(NAN, NAN)

# --- Complejos en doble precisión ([re, im]) — para el paso complejo ---------------

## Evalúa con números complejos de doble precisión (Vector2 es de 32 bits). Los
## valores de vars son floats o [re, im]. Devuelve [re, im].
func eval_cd(vars: Dictionary) -> Array:
	return _cd(ast, vars) if ast != null else [NAN, NAN]

static func _zm(a: Array, b: Array) -> Array:
	return [a[0] * b[0] - a[1] * b[1], a[0] * b[1] + a[1] * b[0]]

static func _zd(a: Array, b: Array) -> Array:
	var d: float = b[0] * b[0] + b[1] * b[1]
	if d == 0.0:
		return [INF, INF]
	return [(a[0] * b[0] + a[1] * b[1]) / d, (a[1] * b[0] - a[0] * b[1]) / d]

static func _zexp(z: Array) -> Array:
	var r := exp(float(z[0]))
	return [r * cos(float(z[1])), r * sin(float(z[1]))]

static func _zlog(z: Array) -> Array:
	return [log(sqrt(z[0] * z[0] + z[1] * z[1])), atan2(float(z[1]), float(z[0]))]

## Raíz principal estable: la parte imaginaria diminuta (paso complejo) no se pierde.
static func _zsqrt(z: Array) -> Array:
	var a: float = z[0]
	var b: float = z[1]
	if a == 0.0 and b == 0.0:
		return [0.0, 0.0]
	var t := sqrt(0.5 * (absf(a) + sqrt(a * a + b * b)))
	if a >= 0.0:
		return [t, b / (2.0 * t)]
	return [absf(b) / (2.0 * t), t if b >= 0.0 else -t]

static func _log1p(x: float) -> float:
	if absf(x) < 1e-4:
		return x - x * x / 2.0 + x * x * x / 3.0
	return log(1.0 + x)

static func _asinh_r(t: float) -> float:
	var at := absf(t)
	return signf(t) * _log1p(at + at * at / (1.0 + sqrt(1.0 + at * at)))

## atan compleja precisa (también con parte imaginaria diminuta).
static func _zatan(z: Array) -> Array:
	var a: float = z[0]
	var b: float = z[1]
	var re := 0.5 * atan2(2.0 * a, 1.0 - a * a - b * b)
	var im := 0.25 * _log1p(4.0 * b / (a * a + (1.0 - b) * (1.0 - b)))
	return [re, im]

## asin y acos complejas (fórmulas de Kahan).
static func _zasin(z: Array) -> Array:
	var s1 := _zsqrt([1.0 - z[0], -z[1]])
	var s2 := _zsqrt([1.0 + z[0], z[1]])
	return [atan2(float(z[0]), s1[0] * s2[0] - s1[1] * s2[1]), _asinh_r(s1[0] * s2[1] - s1[1] * s2[0])]

static func _zacos(z: Array) -> Array:
	var s1 := _zsqrt([1.0 - z[0], -z[1]])
	var s2 := _zsqrt([1.0 + z[0], z[1]])
	return [2.0 * atan2(float(s1[0]), float(s2[0])), _asinh_r(s2[0] * s1[1] - s2[1] * s1[0])]

static func _zsin(z: Array) -> Array:
	return [sin(float(z[0])) * cosh(float(z[1])), cos(float(z[0])) * sinh(float(z[1]))]

static func _zcos(z: Array) -> Array:
	return [cos(float(z[0])) * cosh(float(z[1])), -sin(float(z[0])) * sinh(float(z[1]))]

static func _zsinh(z: Array) -> Array:
	return [sinh(float(z[0])) * cos(float(z[1])), cosh(float(z[0])) * sin(float(z[1]))]

static func _zcosh(z: Array) -> Array:
	return [cosh(float(z[0])) * cos(float(z[1])), sinh(float(z[0])) * sin(float(z[1]))]

static func _zpow(a: Array, b: Array) -> Array:
	if float(b[1]) == 0.0 and float(b[0]) == floor(float(b[0])) and absf(float(b[0])) <= 64.0:
		var n := int(b[0])
		var r := [1.0, 0.0]
		for k in range(absi(n)):
			r = _zm(r, a)
		return _zd([1.0, 0.0], r) if n < 0 else r
	if float(a[0]) == 0.0 and float(a[1]) == 0.0:
		return [0.0, 0.0]
	return _zexp(_zm(b, _zlog(a)))

func _cd(n, v: Dictionary) -> Array:
	match n[0]:
		"num": return [float(n[1]), 0.0]
		"cnum": return [(n[1] as Vector2).x, (n[1] as Vector2).y]
		"var":
			var val = v.get(n[1], 0.0)
			return [float(val[0]), float(val[1])] if val is Array else [float(val), 0.0]
		"neg":
			var a := _cd(n[1], v)
			return [-a[0], -a[1]]
		"bin":
			var a := _cd(n[2], v)
			var b := _cd(n[3], v)
			match n[1]:
				"+": return [a[0] + b[0], a[1] + b[1]]
				"-": return [a[0] - b[0], a[1] - b[1]]
				"*": return _zm(a, b)
				"/": return _zd(a, b)
				"^": return _zpow(a, b)
		"call":
			var args: Array = n[2]
			var z := _cd(args[0], v)
			var one := [1.0, 0.0]
			match n[1]:
				"sin": return _zsin(z)
				"cos": return _zcos(z)
				"tan": return _zd(_zsin(z), _zcos(z))
				"sinh": return _zsinh(z)
				"cosh": return _zcosh(z)
				"tanh": return _zd(_zsinh(z), _zcosh(z))
				"exp": return _zexp(z)
				"log", "ln": return _zlog(z)
				"log10":
					var l := _zlog(z)
					return [l[0] / log(10.0), l[1] / log(10.0)]
				"sqrt": return _zsqrt(z)
				"cbrt":
					var s := 1.0 if float(z[0]) >= 0.0 else -1.0
					var w := _zexp(_zm([1.0 / 3.0, 0.0], _zlog([s * z[0], s * z[1]])))
					return [s * w[0], s * w[1]]
				"abs":
					var sg := 1.0 if float(z[0]) >= 0.0 else -1.0
					return [sg * z[0], sg * z[1]]
				"sign": return [signf(float(z[0])), 0.0]
				"floor": return [floor(float(z[0])), 0.0]
				"ceil": return [ceil(float(z[0])), 0.0]
				"asin": return _zasin(z)
				"acos": return _zacos(z)
				"atan": return _zatan(z)
				"asinh":
					# asinh z = −i·asin(iz)
					var w := _zasin([-z[1], z[0]])
					return [w[1], -w[0]]
				"acosh":
					var q1 := _zsqrt([z[0] - 1.0, z[1]])
					var q2 := _zsqrt([z[0] + 1.0, z[1]])
					var q := _zm(q1, q2)
					return _zlog([z[0] + q[0], z[1] + q[1]])
				"atanh":
					# atanh z = −i·atan(iz)
					var w2 := _zatan([-z[1], z[0]])
					return [w2[1], -w2[0]]
				"sec": return _zd(one, _zcos(z))
				"csc": return _zd(one, _zsin(z))
				"cot": return _zd(_zcos(z), _zsin(z))
				"atan2":
					var x := _cd(args[1], v)
					var q := _cd(["call", "atan", [["bin", "/", args[0], args[1]]]], v)
					return [atan2(float(z[0]), float(x[0])), q[1]]
				"min", "max":
					var w2 := _cd(args[1], v)
					var take_z: bool = (float(z[0]) <= float(w2[0])) == (n[1] == "min")
					return z if take_z else w2
				"pow": return _zpow(z, _cd(args[1], v))
				"mod":
					var w3 := _cd(args[1], v)
					var k := floorf(float(z[0]) / float(w3[0]))
					return [z[0] - k * w3[0], z[1] - k * w3[1]]
	return [NAN, NAN]

# --- Diferenciación automática (chorros de 2.º orden, doble precisión) --------------

## Valor, primera y segunda derivada respecto de «var_name» en el punto vars:
## [f, f′, f″], exactas hasta el redondeo (aritmética de chorros de Taylor).
func eval_jet(vars: Dictionary, var_name: String) -> Array:
	return _jet(ast, vars, var_name) if ast != null else [NAN, NAN, NAN]

static func _jmul(a: Array, b: Array) -> Array:
	return [a[0] * b[0], a[1] * b[0] + a[0] * b[1], a[2] * b[0] + 2.0 * a[1] * b[1] + a[0] * b[2]]

## Regla de la cadena: g(u) con g, g′, g″ evaluadas en u₀.
static func _japply(u: Array, g0: float, g1: float, g2: float) -> Array:
	return [g0, g1 * u[1], g2 * u[1] * u[1] + g1 * u[2]]

static func _jinv(b: Array) -> Array:
	var b0: float = b[0]
	return _japply(b, 1.0 / b0, -1.0 / (b0 * b0), 2.0 / (b0 * b0 * b0))

static func _jexp(u: Array) -> Array:
	var e := exp(float(u[0]))
	return _japply(u, e, e, e)

static func _jlog(u: Array) -> Array:
	var u0: float = u[0]
	return _japply(u, log(u0), 1.0 / u0, -1.0 / (u0 * u0))

func _jet(n, v: Dictionary, x: String) -> Array:
	match n[0]:
		"num": return [float(n[1]), 0.0, 0.0]
		"cnum": return [NAN, NAN, NAN]
		"var": return [float(v.get(n[1], 0.0)), 1.0 if n[1] == x else 0.0, 0.0]
		"neg":
			var a := _jet(n[1], v, x)
			return [-a[0], -a[1], -a[2]]
		"bin":
			var a := _jet(n[2], v, x)
			var b := _jet(n[3], v, x)
			match n[1]:
				"+": return [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
				"-": return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
				"*": return _jmul(a, b)
				"/": return _jmul(a, _jinv(b))
				"^": return _jpow(a, b)
		"call":
			var args: Array = n[2]
			var u := _jet(args[0], v, x)
			var u0: float = u[0]
			match n[1]:
				"sin": return _japply(u, sin(u0), cos(u0), -sin(u0))
				"cos": return _japply(u, cos(u0), -sin(u0), -cos(u0))
				"tan":
					var t := tan(u0)
					return _japply(u, t, 1.0 + t * t, 2.0 * t * (1.0 + t * t))
				"asin":
					var q := 1.0 - u0 * u0
					return _japply(u, asin(u0), 1.0 / sqrt(q), u0 / pow(q, 1.5))
				"acos":
					var q2 := 1.0 - u0 * u0
					return _japply(u, acos(u0), -1.0 / sqrt(q2), -u0 / pow(q2, 1.5))
				"atan":
					var q3 := 1.0 + u0 * u0
					return _japply(u, atan(u0), 1.0 / q3, -2.0 * u0 / (q3 * q3))
				"sinh": return _japply(u, sinh(u0), cosh(u0), sinh(u0))
				"cosh": return _japply(u, cosh(u0), sinh(u0), cosh(u0))
				"tanh":
					var th := tanh(u0)
					return _japply(u, th, 1.0 - th * th, -2.0 * th * (1.0 - th * th))
				"asinh":
					var q4 := u0 * u0 + 1.0
					return _japply(u, log(u0 + sqrt(q4)), 1.0 / sqrt(q4), -u0 / pow(q4, 1.5))
				"acosh":
					var q5 := u0 * u0 - 1.0
					return _japply(u, log(u0 + sqrt(q5)), 1.0 / sqrt(q5), -u0 / pow(q5, 1.5))
				"atanh":
					var q6 := 1.0 - u0 * u0
					return _japply(u, 0.5 * log((1.0 + u0) / (1.0 - u0)), 1.0 / q6, 2.0 * u0 / (q6 * q6))
				"exp": return _jexp(u)
				"log", "ln": return _jlog(u)
				"log10":
					var l := _jlog(u)
					return [l[0] / log(10.0), l[1] / log(10.0), l[2] / log(10.0)]
				"sqrt":
					var r := sqrt(u0)
					return _japply(u, r, 0.5 / r, -0.25 / (r * r * r))
				"cbrt":
					var c := signf(u0) * pow(absf(u0), 1.0 / 3.0)
					return _japply(u, c, 1.0 / (3.0 * c * c), -2.0 / (9.0 * pow(c, 5.0)))
				"abs": return _japply(u, absf(u0), signf(u0), 0.0)
				"sign": return [signf(u0), 0.0, 0.0]
				"floor": return [floor(u0), 0.0, 0.0]
				"ceil": return [ceil(u0), 0.0, 0.0]
				"sec":
					var sc := 1.0 / cos(u0)
					var t2 := tan(u0)
					return _japply(u, sc, sc * t2, sc * (t2 * t2 + sc * sc))
				"csc":
					var cs := 1.0 / sin(u0)
					var ct := 1.0 / tan(u0)
					return _japply(u, cs, -cs * ct, cs * (ct * ct + cs * cs))
				"cot":
					var ct2 := 1.0 / tan(u0)
					var cs2 := 1.0 / sin(u0)
					return _japply(u, ct2, -cs2 * cs2, 2.0 * cs2 * cs2 * ct2)
				"atan2":
					var xw := _jet(args[1], v, x)
					var q7 := _jmul(u, _jinv(xw))
					var q0: float = q7[0]
					var r7 := _japply(q7, atan(q0), 1.0 / (1.0 + q0 * q0), -2.0 * q0 / pow(1.0 + q0 * q0, 2.0))
					return [atan2(u0, float(xw[0])), r7[1], r7[2]]
				"min", "max":
					var w := _jet(args[1], v, x)
					var take_u: bool = (u0 <= float(w[0])) == (n[1] == "min")
					return u if take_u else w
				"pow": return _jpow(u, _jet(args[1], v, x))
				"mod":
					var w2 := _jet(args[1], v, x)
					var k := floorf(u0 / float(w2[0]))
					return [u0 - k * w2[0], u[1] - k * w2[1], u[2] - k * w2[2]]
	return [NAN, NAN, NAN]

static func _jpow(a: Array, b: Array) -> Array:
	if float(b[1]) == 0.0 and float(b[2]) == 0.0:
		var p: float = b[0]
		var u0: float = a[0]
		return _japply(a, _rpow(u0, p), p * _rpow(u0, p - 1.0) if p != 0.0 else 0.0, p * (p - 1.0) * _rpow(u0, p - 2.0) if p != 0.0 and p != 1.0 else 0.0)
	return _jexp(_jmul(b, _jlog(a)))

# --- Derivada simbólica ---------------------------------------------------------------

## Derivada simbólica respecto de var (simplificada). Si no es derivable (funciones
## solo complejas como conj o re), el resultado trae error.
func derivative(var_name: String) -> MathExpr:
	var m := MathExpr.new()
	m.variables = variables
	m.complex_mode = complex_mode
	if ast == null:
		m.error = error if error != "" else "Expresión vacía."
		return m
	var d = _d(ast, var_name)
	if d == null:
		m.error = "No se puede derivar simbólicamente (función no derivable)."
		return m
	m.ast = simplify(d)
	m.source = m.to_text()
	return m

static func _nm(v: float) -> Array:
	return ["num", v]

static func _isn(n, v = null) -> bool:
	return n[0] == "num" and n.size() == 2 and (v == null or float(n[1]) == float(v))

static func _isnum(n) -> bool:
	return n[0] == "num"

static func _add(a, b):
	if _isn(a, 0.0): return b
	if _isn(b, 0.0): return a
	if _isn(a) and _isn(b): return _nm(a[1] + b[1])
	return ["bin", "+", a, b]

static func _sub(a, b):
	if _isn(b, 0.0): return a
	if _isn(a, 0.0): return _neg(b)
	if _isn(a) and _isn(b): return _nm(a[1] - b[1])
	return ["bin", "-", a, b]

static func _mul(a, b):
	if _isn(a, 0.0) or _isn(b, 0.0): return _nm(0.0)
	if _isn(a, 1.0): return b
	if _isn(b, 1.0): return a
	if _isn(a, -1.0): return _neg(b)
	if _isn(b, -1.0): return _neg(a)
	if _isn(a) and _isn(b): return _nm(a[1] * b[1])
	return ["bin", "*", a, b]

static func _div(a, b):
	if _isn(a, 0.0): return _nm(0.0)
	if _isn(b, 1.0): return a
	if _isn(a) and _isn(b) and float(b[1]) != 0.0: return _nm(a[1] / b[1])
	return ["bin", "/", a, b]

static func _pw(a, b):
	if _isn(b, 0.0): return _nm(1.0)
	if _isn(b, 1.0): return a
	if _isn(a) and _isn(b): return _nm(_rpow(a[1], b[1]))
	return ["bin", "^", a, b]

static func _neg(a):
	if _isn(a): return _nm(-float(a[1]))
	if a[0] == "neg": return a[1]
	return ["neg", a]

static func _fn(name: String, a) -> Array:
	return ["call", name, [a]]

static func _depends(n, v: String) -> bool:
	match n[0]:
		"var": return n[1] == v
		"neg": return _depends(n[1], v)
		"bin": return _depends(n[2], v) or _depends(n[3], v)
		"call":
			for a in n[2]:
				if _depends(a, v):
					return true
	return false

func _d(n, v: String):
	match n[0]:
		"num", "cnum": return _nm(0.0)
		"var": return _nm(1.0 if n[1] == v else 0.0)
		"neg":
			var d = _d(n[1], v)
			return null if d == null else _neg(d)
		"bin":
			var a = n[2]
			var b = n[3]
			var da = _d(a, v)
			var db = _d(b, v)
			if da == null or db == null:
				return null
			match n[1]:
				"+": return _add(da, db)
				"-": return _sub(da, db)
				"*": return _add(_mul(da, b), _mul(a, db))
				"/": return _div(_sub(_mul(da, b), _mul(a, db)), _pw(b, _nm(2.0)))
				"^": return _dpow(a, b, da, db, v)
		"call":
			var args: Array = n[2]
			var u = args[0]
			var du = _d(u, v)
			if du == null:
				return null
			var g = null
			match n[1]:
				"sin": g = _fn("cos", u)
				"cos": g = _neg(_fn("sin", u))
				"tan": g = _div(_nm(1.0), _pw(_fn("cos", u), _nm(2.0)))
				"asin": g = _div(_nm(1.0), _fn("sqrt", _sub(_nm(1.0), _pw(u, _nm(2.0)))))
				"acos": g = _neg(_div(_nm(1.0), _fn("sqrt", _sub(_nm(1.0), _pw(u, _nm(2.0))))))
				"atan": g = _div(_nm(1.0), _add(_nm(1.0), _pw(u, _nm(2.0))))
				"sinh": g = _fn("cosh", u)
				"cosh": g = _fn("sinh", u)
				"tanh": g = _sub(_nm(1.0), _pw(_fn("tanh", u), _nm(2.0)))
				"asinh": g = _div(_nm(1.0), _fn("sqrt", _add(_pw(u, _nm(2.0)), _nm(1.0))))
				"acosh": g = _div(_nm(1.0), _fn("sqrt", _sub(_pw(u, _nm(2.0)), _nm(1.0))))
				"atanh": g = _div(_nm(1.0), _sub(_nm(1.0), _pw(u, _nm(2.0))))
				"exp": g = n
				"log", "ln": g = _div(_nm(1.0), u)
				"log10": g = _div(_nm(1.0), _mul(u, ["num", log(10.0), "ln(10)"]))
				"sqrt": g = _div(_nm(1.0), _mul(_nm(2.0), n))
				"cbrt": g = _div(_nm(1.0), _mul(_nm(3.0), _pw(n, _nm(2.0))))
				"abs": g = _fn("sign", u)
				"sign", "floor", "ceil": return _nm(0.0)
				"sec": g = _mul(n, _fn("tan", u))
				"csc": g = _neg(_mul(n, _fn("cot", u)))
				"cot": g = _neg(_div(_nm(1.0), _pw(_fn("sin", u), _nm(2.0))))
				"atan2":
					var xw = args[1]
					var dx = _d(xw, v)
					if dx == null:
						return null
					return _div(_sub(_mul(xw, du), _mul(u, dx)), _add(_pw(xw, _nm(2.0)), _pw(u, _nm(2.0))))
				"min", "max":
					var w = args[1]
					var dw = _d(w, v)
					if dw == null:
						return null
					var s := _fn("sign", _sub(u, w))
					var half = _mul(_nm(0.5), _add(du, dw))
					var diff = _mul(_nm(0.5 if n[1] == "max" else -0.5), _mul(s, _sub(du, dw)))
					return _add(half, diff)
				"pow":
					var e2 = args[1]
					var de = _d(e2, v)
					if de == null:
						return null
					return _dpow(u, e2, du, de, v)
				"mod":
					var w2 = args[1]
					var dw2 = _d(w2, v)
					if dw2 == null:
						return null
					return _sub(du, _mul(_fn("floor", _div(u, w2)), dw2))
				_:
					return null
			return _mul(g, du)
	return null

func _dpow(a, b, da, db, v: String):
	if not _depends(b, v):
		return _mul(_mul(b, _pw(a, _sub(b, _nm(1.0)))), da)
	if not _depends(a, v):
		return _mul(_mul(["bin", "^", a, b], _fn("ln", a)), db)
	return _mul(["bin", "^", a, b], _add(_mul(db, _fn("ln", a)), _div(_mul(b, da), a)))

## Simplificación algebraica ligera: constantes, neutros, signos, x·x = x², (xᵃ)ᵇ…
func simplify(n):
	var cur = n
	for k in range(8):
		var nxt = _simp(cur)
		if _tx(nxt) == _tx(cur):
			return nxt
		cur = nxt
	return cur

func _same(a, b) -> bool:
	return _tx(a) == _tx(b)

## Descompone un producto/cociente en coeficiente, factores del numerador y del denominador.
func _flatten(n, num: Array, den: Array, coef: Array, inv: bool) -> void:
	if n[0] == "neg":
		coef[0] = -float(coef[0])
		_flatten(n[1], num, den, coef, inv)
	elif _isn(n):
		var v: float = n[1]
		if inv:
			coef[1] = float(coef[1]) * v
		else:
			coef[0] = float(coef[0]) * v
	elif n[0] == "bin" and n[1] == "*":
		_flatten(n[2], num, den, coef, inv)
		_flatten(n[3], num, den, coef, inv)
	elif n[0] == "bin" and n[1] == "/":
		_flatten(n[2], num, den, coef, inv)
		_flatten(n[3], num, den, coef, not inv)
	else:
		(den if inv else num).append(n)

## Orden de los factores: constantes con nombre, variables, potencias, lo demás.
static func _rank(n) -> int:
	if n[0] == "num": return 0
	if n[0] == "var": return 1
	if n[0] == "bin" and n[1] == "^" and n[2][0] == "var": return 2
	if n[0] == "bin" and n[1] == "^": return 4
	return 3

## Junta bases iguales (x·x² = x³) en una lista de factores.
func _merge_powers(fs: Array) -> Array:
	var out := []
	for f in fs:
		var be := _base_exp(f)
		var merged := false
		for k in range(out.size()):
			var bo := _base_exp(out[k])
			if _isn(be[1]) and _isn(bo[1]) and _same(be[0], bo[0]):
				out[k] = _pw(bo[0], _nm(float(bo[1][1]) + float(be[1][1])))
				merged = true
				break
		if not merged:
			out.append(f)
	return out

func _product(n):
	var num := []
	var den := []
	var coef := [1.0, 1.0]
	_flatten(n, num, den, coef, false)
	num = _merge_powers(num)
	den = _merge_powers(den)
	# Cancelación numerador/denominador con exponentes numéricos.
	for i in range(num.size()):
		for j in range(den.size()):
			if num[i] == null or den[j] == null:
				continue
			var bn := _base_exp(num[i])
			var bd := _base_exp(den[j])
			if _isn(bn[1]) and _isn(bd[1]) and _same(bn[0], bd[0]):
				var e := float(bn[1][1]) - float(bd[1][1])
				num[i] = _pw(bn[0], _nm(e)) if e > 0.0 else null
				den[j] = _pw(bd[0], _nm(-e)) if e < 0.0 else null
	num = num.filter(func(q): return q != null and not _isn(q, 1.0))
	den = den.filter(func(q): return q != null and not _isn(q, 1.0))
	num.sort_custom(func(p, q): return _rank(p) < _rank(q))
	den.sort_custom(func(p, q): return _rank(p) < _rank(q))
	var c0: float = coef[0]
	var c1: float = coef[1]
	var negative := c0 < 0.0
	c0 = absf(c0)
	# Coeficiente racional sencillo: se simplifica la fracción.
	if c1 != 1.0 and c0 == floor(c0) and c1 == floor(c1) and c0 < 1e9 and c1 < 1e9:
		var g := _gcd(int(c0), int(c1))
		c0 /= g
		c1 /= g
	elif c1 != 1.0:
		c0 /= c1
		c1 = 1.0
	var top = _nm(c0) if c0 != 1.0 or num.is_empty() else null
	for f in num:
		top = f if top == null else ["bin", "*", top, f]
	var bottom = _nm(c1) if c1 != 1.0 else null
	for f in den:
		bottom = f if bottom == null else ["bin", "*", bottom, f]
	if _isn(top, 0.0):
		return _nm(0.0)
	var res = top if bottom == null else ["bin", "/", top, bottom]
	return _neg(res) if negative else res

static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t := a % b
		a = b
		b = t
	return maxi(1, absi(a))

static func _base_exp(n) -> Array:
	if n[0] == "bin" and n[1] == "^":
		return [n[2], n[3]]
	return [n, _nm(1.0)]

func _simp(n):
	match n[0]:
		"neg":
			var a = _simp(n[1])
			if a[0] == "bin" and a[1] == "-":
				return _sub(a[3], a[2])
			return _neg(a)
		"bin":
			var a = _simp(n[2])
			var b = _simp(n[3])
			match n[1]:
				"+":
					if b[0] == "neg": return _sub(a, b[1])
					if a[0] == "neg": return _sub(b, a[1])
					if _same(a, b): return _mul(_nm(2.0), a)
					return _add(a, b)
				"-":
					if b[0] == "neg": return _add(a, b[1])
					if _same(a, b): return _nm(0.0)
					return _sub(a, b)
				"*", "/":
					return _product(["bin", n[1], a, b])
				"^":
					if _isn(b) and a[0] == "bin" and a[1] == "^" and _isn(a[3]):
						return _pw(a[2], _nm(a[3][1] * b[1]))
					return _pw(a, b)
		"call":
			var args := []
			var all_num := true
			for q in n[2]:
				var s = _simp(q)
				args.append(s)
				all_num = all_num and _isnum(s)
			var c := ["call", n[1], args]
			if all_num:
				var val := _er(c, {})
				if is_finite(val) and absf(val - round(val)) < 1e-12:
					return _nm(round(val))
			return c
	return n

# --- Escritura: texto legible y texto que se vuelve a leer ----------------------------

static func _num_text(v: float) -> String:
	if is_inf(v):
		return "∞" if v > 0.0 else "−∞"
	if v == floor(v) and absf(v) < 1e15:
		return str(int(v))
	var s := String.num(v, 10)
	if s.length() > 12:
		s = String.num(v, 6)
	return s

## Notación matemática para mostrar: e^(−(x² + y²)), 2x·cos(x²), √(x + 1), |x|…
func to_pretty() -> String:
	return str(_pp(ast)[0]).replace("-", "−") if ast != null else ""

static func _wrap(p: Array, min_prec: int) -> String:
	return str(p[0]) if int(p[1]) >= min_prec else "(" + str(p[0]) + ")"

static func _sup(t: String) -> String:
	if t.length() > 6:
		return ""
	var out := ""
	for ch in t:
		if not TO_SUPER.has(ch):
			return ""
		out += TO_SUPER[ch]
	return out

func _pow_text(base: Array, ex: Array) -> String:
	var b := _wrap(base, 5)
	var s := _sup(str(ex[0]))
	if s != "":
		return b + s
	if int(ex[1]) >= 5:
		return b + "^" + str(ex[0])
	return b + "^(" + str(ex[0]) + ")"

func _pp(n) -> Array:
	match n[0]:
		"num":
			if n.size() > 2:
				return [str(n[2]), 5]
			var v: float = n[1]
			return [("−" if v < 0.0 else "") + _num_text(absf(v)), 3 if v < 0.0 else 5]
		"cnum":
			var c: Vector2 = n[1]
			if c == Vector2(0, 1):
				return ["i", 5]
			return ["(%s + %si)" % [_num_text(c.x), _num_text(c.y)], 5]
		"var": return [str(n[1]), 5]
		"neg":
			# −a/b y −2x se leen sin paréntesis; −(a + b) los necesita.
			return ["−" + _wrap(_pp(n[1]), 2), 3]
		"bin":
			var a := _pp(n[2])
			var b := _pp(n[3])
			match n[1]:
				"+":
					if int(b[1]) == 3 and str(b[0]).begins_with("−"):
						return [str(a[0]) + " − " + str(b[0]).substr(1), 1]
					return [str(a[0]) + " + " + str(b[0]), 1]
				"-":
					return [str(a[0]) + " − " + _wrap(b, 2 if int(b[1]) != 3 else 4), 1]
				"*":
					return [_mul_text(n[2], n[3], a, b), 2]
				"/":
					return [_wrap(a, 2) + "/" + _wrap(b, 4), 2]
				"^":
					return [_pow_text(a, b), 4]
		"call":
			var args: Array = n[2]
			var ps := []
			for q in args:
				ps.append(_pp(q))
			var x: Array = ps[0]
			match n[1]:
				"sqrt": return ["√" + _wrap(x, 5), 5]
				"cbrt": return ["∛" + _wrap(x, 5), 5]
				"abs": return ["|" + str(x[0]) + "|", 5]
				"exp": return [_pow_text(["e", 5], x), 4]
				"log", "ln": return ["ln(" + str(x[0]) + ")", 5]
				"log10": return ["log₁₀(" + str(x[0]) + ")", 5]
				"pow": return [_pow_text(x, ps[1]), 4]
			var txts := []
			for p in ps:
				txts.append(str(p[0]))
			return [str(n[1]) + "(" + ", ".join(PackedStringArray(txts)) + ")", 5]
	return ["?", 5]

## Producto: yuxtaposición cuando se lee sin ambigüedad (2x, 2x², 2(x + 1), xy,
## 2 sin(x)); si no, con «·».
func _mul_text(ln_, rn, a: Array, b: Array) -> String:
	var L := _wrap(a, 2)
	var R := _wrap(b, 4) if int(b[1]) != 3 else "(" + str(b[0]) + ")"
	var r0 := R.substr(0, 1)
	var starts_digit := r0.is_valid_int()
	var l_plain_num: bool = ln_[0] == "num" and ln_.size() == 2 and float(ln_[1]) >= 0.0
	var r_word: bool = rn[0] == "call" and not (str(rn[1]) in ["sqrt", "cbrt", "abs", "exp", "pow"])
	if l_plain_num and not starts_digit:
		return L + (" " if r_word else "") + R
	var l_sym: bool = ln_[0] == "var" or (ln_[0] == "num" and ln_.size() > 2) or (ln_[0] == "bin" and ln_[1] == "^" and ln_[2][0] == "var")
	var r_sym: bool = rn[0] == "var" or (rn[0] == "num" and rn.size() > 2 and str(rn[2]).length() == 1) or (rn[0] == "bin" and rn[1] == "^" and rn[2][0] == "var")
	# Un producto que acaba en número, variable o constante sigue pegado: 2πx, 3xy.
	var l_chain: bool = ln_[0] == "bin" and ln_[1] == "*" and not L.ends_with(")") and not L.ends_with("|")
	if r_sym and (l_sym or l_chain):
		return L + R
	return L + "·" + R

## Texto que MathExpr vuelve a leer igual (para guardar o enviar la fórmula).
func to_text() -> String:
	return str(_tx_p(ast)[0]) if ast != null else ""

func _tx(n) -> String:
	return str(_tx_p(n)[0])

func _tx_p(n) -> Array:
	match n[0]:
		"num":
			if n.size() > 2:
				return [str(CONST_TEXT.get(str(n[2]), str(n[2]))), 5]
			var v: float = n[1]
			if is_inf(v):
				return ["inf" if v > 0.0 else "(-inf)", 5]
			var s := str(v)
			if s.ends_with(".0"):
				s = s.substr(0, s.length() - 2)
			return ["(" + s + ")" if v < 0.0 else s, 5]
		"cnum":
			var c: Vector2 = n[1]
			return ["i" if c == Vector2(0, 1) else "(%s+%s*i)" % [str(c.x), str(c.y)], 5]
		"var": return [str(n[1]), 5]
		"neg":
			var a := _tx_p(n[1])
			return ["-" + (str(a[0]) if int(a[1]) >= 4 else "(" + str(a[0]) + ")"), 3]
		"bin":
			var a := _tx_p(n[2])
			var b := _tx_p(n[3])
			match n[1]:
				"+": return [str(a[0]) + " + " + (str(b[0]) if int(b[1]) != 3 else "(" + str(b[0]) + ")"), 1]
				"-": return [str(a[0]) + " - " + (str(b[0]) if int(b[1]) >= 2 and int(b[1]) != 3 else "(" + str(b[0]) + ")"), 1]
				"*": return [(str(a[0]) if int(a[1]) >= 2 else "(" + str(a[0]) + ")") + "*" + (str(b[0]) if int(b[1]) >= 4 else "(" + str(b[0]) + ")"), 2]
				"/": return [(str(a[0]) if int(a[1]) >= 2 else "(" + str(a[0]) + ")") + "/" + (str(b[0]) if int(b[1]) >= 4 else "(" + str(b[0]) + ")"), 2]
				"^": return [(str(a[0]) if int(a[1]) >= 5 else "(" + str(a[0]) + ")") + "^" + (str(b[0]) if int(b[1]) >= 5 else "(" + str(b[0]) + ")"), 4]
		"call":
			var txts := []
			for q in n[2]:
				txts.append(_tx(q))
			return [str(n[1]) + "(" + ", ".join(PackedStringArray(txts)) + ")", 5]
	return ["0", 5]

# --- Evaluación rápida (Expression nativa de Godot) --------------------------------

## Compila la expresión real a una Expression de Godot (C++): mucho más rápida
## para millones de evaluaciones (líneas de corriente, cuadraturas).
func compile_fast() -> bool:
	if ast == null:
		return false
	_fast = Expression.new()
	_fast_names = PackedStringArray(variables)
	return _fast.parse(_gd(ast), _fast_names) == OK

## values: en el mismo orden que "variables".
func eval_fast(values: Array) -> float:
	if _fast == null and not compile_fast():
		return NAN
	var r = _fast.execute(values, null, false)
	if _fast.has_execute_failed():
		return NAN
	return float(r)

func _gd(n) -> String:
	match n[0]:
		"num": return _flt(n[1])
		"var": return str(n[1])
		"neg": return "(-%s)" % _gd(n[1])
		"bin":
			if n[1] == "^":
				return "pow(%s, %s)" % [_gd(n[2]), _gd(n[3])]
			return "(%s %s %s)" % [_gd(n[2]), n[1], _gd(n[3])]
		"call":
			var a: Array = n[2]
			var x := _gd(a[0])
			match n[1]:
				"ln", "log": return "log(%s)" % x
				"log10": return "(log(%s) / 2.302585092994046)" % x
				"cbrt": return "(sign(%s) * pow(abs(%s), 1.0 / 3.0))" % [x, x]
				"mod": return "fmod(%s, %s)" % [x, _gd(a[1])]
				"sec": return "(1.0 / cos(%s))" % x
				"csc": return "(1.0 / sin(%s))" % x
				"cot": return "(1.0 / tan(%s))" % x
				"sign": return "sign(%s)" % x
				"asinh": return "log(%s + sqrt(%s * %s + 1.0))" % [x, x, x]
				"acosh": return "log(%s + sqrt(%s * %s - 1.0))" % [x, x, x]
				"atanh": return "(0.5 * log((1.0 + %s) / (1.0 - %s)))" % [x, x]
				"atan2", "min", "max", "pow":
					return "%s(%s, %s)" % [n[1], x, _gd(a[1])]
				_: return "%s(%s)" % [n[1], x]
	return "0.0"

static func _flt(v: float) -> String:
	if is_inf(v):
		return "1e30" if v > 0 else "-1e30"
	# str() da la representación más corta y exacta (GDScript no admite %g).
	var s := str(v)
	if not ("." in s or "e" in s):
		s += ".0"
	return s

# --- Traducción a GLSL --------------------------------------------------------------

## GLSL real. "names": mapa variable → expresión GLSL (p. ej. {"x": "p.x"}).
func to_glsl(names: Dictionary = {}) -> String:
	return _gl(ast, names) if ast != null else "0.0"

func _gl(n, m: Dictionary) -> String:
	match n[0]:
		"num": return _flt(n[1])
		"var": return str(m.get(n[1], n[1]))
		"neg": return "(-%s)" % _gl(n[1], m)
		"bin":
			var a := _gl(n[2], m)
			var b := _gl(n[3], m)
			if n[1] == "^":
				if n[3][0] == "num" and float(n[3][1]) == 2.0:
					return "(%s * %s)" % [a, a]
				return "mx_pow(%s, %s)" % [a, b]
			return "(%s %s %s)" % [a, n[1], b]
		"call":
			var args: Array = n[2]
			var x := _gl(args[0], m)
			match n[1]:
				"ln", "log": return "log(%s)" % x
				"log10": return "(log(%s) / 2.302585)" % x
				"cbrt": return "(sign(%s) * pow(abs(%s), 1.0 / 3.0))" % [x, x]
				"atan2": return "atan(%s, %s)" % [x, _gl(args[1], m)]
				"mod": return "mod(%s, %s)" % [x, _gl(args[1], m)]
				"pow": return "mx_pow(%s, %s)" % [x, _gl(args[1], m)]
				"min", "max": return "%s(%s, %s)" % [n[1], x, _gl(args[1], m)]
				"sec": return "(1.0 / cos(%s))" % x
				"csc": return "(1.0 / sin(%s))" % x
				"cot": return "(1.0 / tan(%s))" % x
				_: return "%s(%s)" % [n[1], x]
	return "0.0"

## GLSL complejo (vec2). "names": variable → expresión vec2 (p. ej. {"z": "z"}).
func to_glsl_complex(names: Dictionary = {}) -> String:
	return _glc(ast, names) if ast != null else "vec2(0.0)"

func _glc(n, m: Dictionary) -> String:
	match n[0]:
		"num": return "vec2(%s, 0.0)" % _flt(n[1])
		"cnum": return "vec2(%s, %s)" % [_flt((n[1] as Vector2).x), _flt((n[1] as Vector2).y)]
		"var": return str(m.get(n[1], n[1]))
		"neg": return "(-%s)" % _glc(n[1], m)
		"bin":
			var a := _glc(n[2], m)
			var b := _glc(n[3], m)
			match n[1]:
				"+", "-": return "(%s %s %s)" % [a, n[1], b]
				"*": return "cx_mul(%s, %s)" % [a, b]
				"/": return "cx_div(%s, %s)" % [a, b]
				"^":
					if n[3][0] == "num" and float(n[3][1]) == floor(float(n[3][1])) and absf(float(n[3][1])) <= 16.0:
						return "cx_powi(%s, %d)" % [a, int(n[3][1])]
					return "cx_pow(%s, %s)" % [a, b]
		"call":
			var args: Array = n[2]
			var z := _glc(args[0], m)
			match n[1]:
				"log", "ln": return "cx_log(%s)" % z
				"abs": return "vec2(length(%s), 0.0)" % z
				"conj": return "cx_conj(%s)" % z
				"re": return "vec2((%s).x, 0.0)" % z
				"im": return "vec2((%s).y, 0.0)" % z
				"arg": return "vec2(atan((%s).y, (%s).x), 0.0)" % [z, z]
				"pow": return "cx_pow(%s, %s)" % [z, _glc(args[1], m)]
				_: return "cx_%s(%s)" % [n[1], z]
	return "vec2(0.0)"

## Funciones GLSL auxiliares para el código generado (real y complejo).
const GLSL_PRELUDE := """
float mx_pow(float a, float b) {
	if (b == floor(b)) {
		float r = pow(abs(a), b);
		return (a < 0.0 && mod(abs(b), 2.0) == 1.0) ? -r : r;
	}
	return pow(a, b);
}
vec2 cx_mul(vec2 a, vec2 b) { return vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x); }
vec2 cx_div(vec2 a, vec2 b) { float d = dot(b, b) + 1e-30; return vec2(a.x * b.x + a.y * b.y, a.y * b.x - a.x * b.y) / d; }
vec2 cx_conj(vec2 z) { return vec2(z.x, -z.y); }
vec2 cx_exp(vec2 z) { return exp(min(z.x, 80.0)) * vec2(cos(z.y), sin(z.y)); }
vec2 cx_log(vec2 z) { return vec2(log(length(z) + 1e-30), atan(z.y, z.x)); }
vec2 cx_pow(vec2 a, vec2 b) { if (length(a) < 1e-30) return vec2(0.0); return cx_exp(cx_mul(b, cx_log(a))); }
vec2 cx_powi(vec2 a, int n) {
	vec2 r = vec2(1.0, 0.0);
	int k = abs(n);
	for (int i = 0; i < k; i++) { r = cx_mul(r, a); }
	return n < 0 ? cx_div(vec2(1.0, 0.0), r) : r;
}
vec2 cx_sin(vec2 z) { return vec2(sin(z.x) * cosh(z.y), cos(z.x) * sinh(z.y)); }
vec2 cx_cos(vec2 z) { return vec2(cos(z.x) * cosh(z.y), -sin(z.x) * sinh(z.y)); }
vec2 cx_tan(vec2 z) { return cx_div(cx_sin(z), cx_cos(z)); }
vec2 cx_sinh(vec2 z) { return vec2(sinh(z.x) * cos(z.y), cosh(z.x) * sin(z.y)); }
vec2 cx_cosh(vec2 z) { return vec2(cosh(z.x) * cos(z.y), sinh(z.x) * sin(z.y)); }
vec2 cx_tanh(vec2 z) { return cx_div(cx_sinh(z), cx_cosh(z)); }
vec2 cx_sqrt(vec2 z) { float r = length(z); float s = z.y >= 0.0 ? 1.0 : -1.0; return vec2(sqrt(max(0.0, 0.5 * (r + z.x))), s * sqrt(max(0.0, 0.5 * (r - z.x)))); }
"""
