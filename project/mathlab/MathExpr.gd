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
##     coloreado de dominio, partículas del campo vectorial).
## Admite multiplicación implícita (2x, 3(x+1), x y), potencias con ^ o **, |x|,
## constantes pi/π, e, tau e i (imaginaria) y funciones habituales.

const FUNCS_REAL := {
	"sin": 1, "cos": 1, "tan": 1, "asin": 1, "acos": 1, "atan": 1, "atan2": 2,
	"sinh": 1, "cosh": 1, "tanh": 1, "exp": 1, "log": 1, "ln": 1, "log10": 1,
	"sqrt": 1, "cbrt": 1, "abs": 1, "floor": 1, "ceil": 1, "sign": 1,
	"min": 2, "max": 2, "pow": 2, "mod": 2, "sec": 1, "csc": 1, "cot": 1,
}
const FUNCS_COMPLEX := {
	"sin": 1, "cos": 1, "tan": 1, "sinh": 1, "cosh": 1, "tanh": 1, "exp": 1,
	"log": 1, "ln": 1, "sqrt": 1, "abs": 1, "conj": 1, "re": 1, "im": 1, "arg": 1, "pow": 2,
}
const CONSTS := {"pi": PI, "π": PI, "e": 2.718281828459045, "tau": TAU}

var ast = null
var error: String = ""
var source: String = ""
var complex_mode: bool = false
var variables: Array = []
var _tokens: Array = []
var _pos: int = 0
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
	error = _tokenize(source)
	if error != "":
		return
	if _tokens.is_empty():
		error = "La expresión está vacía."
		return
	_pos = 0
	ast = _expr()
	if error == "" and _pos < _tokens.size():
		error = "Sobra «%s» al final." % str(_tokens[_pos][1])
	if error != "":
		ast = null

# --- Analizador léxico -----------------------------------------------------------

func _tokenize(s: String) -> String:
	_tokens = []
	s = s.replace("**", "^").replace("·", "*").replace("×", "*").replace("−", "-").replace("÷", "/")
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
			_tokens.append(["id", s.substr(i, j2 - i)])
			i = j2
			continue
		if ch in ["+", "-", "*", "/", "^", "(", ")", ",", "|"]:
			_tokens.append(["op", ch])
			i += 1
			continue
		return "Carácter no válido: «%s»." % ch
	return ""

static func _is_ident_char(c: String, first: bool) -> bool:
	if c == "π" or c == "_":
		return true
	var u := c.unicode_at(0)
	var alpha := (u >= 65 and u <= 90) or (u >= 97 and u <= 122)
	return alpha or (not first and c.is_valid_int())

# --- Analizador sintáctico (descenso recursivo) ----------------------------------

func _peek():
	return _tokens[_pos] if _pos < _tokens.size() else null

func _is_op(t, o: String) -> bool:
	return t != null and t[0] == "op" and t[1] == o

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
	return _is_op(t, "(")

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
		var e = _expr()
		if not _is_op(_peek(), ")"):
			if error == "": error = "Falta cerrar un paréntesis «)»."
			return e
		_pos += 1
		return e
	if _is_op(t, "|"):
		_pos += 1
		var e2 = _expr()
		if not _is_op(_peek(), "|"):
			if error == "": error = "Falta cerrar el valor absoluto «|»."
			return e2
		_pos += 1
		return ["call", "abs", [e2]]
	if t[0] == "id":
		_pos += 1
		var name: String = t[1]
		var funcs: Dictionary = FUNCS_COMPLEX if complex_mode else FUNCS_REAL
		if _is_op(_peek(), "(") and funcs.has(name):
			_pos += 1
			var args := []
			if not _is_op(_peek(), ")"):
				args.append(_expr())
				while error == "" and _is_op(_peek(), ","):
					_pos += 1
					args.append(_expr())
			if not _is_op(_peek(), ")"):
				if error == "": error = "Falta «)» en la llamada a %s." % name
				return null
			_pos += 1
			if args.size() != int(funcs[name]):
				error = "%s necesita %d argumento(s)." % [name, int(funcs[name])]
				return null
			return ["call", name, args]
		if name in variables:
			return ["var", name]
		if complex_mode and name == "i":
			return ["cnum", Vector2(0, 1)]
		if CONSTS.has(name):
			return ["num", CONSTS[name]]
		if funcs.has(name):
			error = "La función %s necesita paréntesis: %s(…)." % [name, name]
			return null
		# Multiplicación implícita de variables pegadas: "xy" → x*y.
		if name.length() > 1:
			var parts := []
			for ch in name:
				if ch in variables:
					parts.append(["var", ch])
				else:
					parts = []
					break
			if parts.size() == name.length():
				var node = parts[0]
				for k in range(1, parts.size()):
					node = ["bin", "*", node, parts[k]]
				return node
		error = "Nombre desconocido: «%s». Variables: %s." % [name, ", ".join(PackedStringArray(variables))]
		return null
	error = "Símbolo inesperado: «%s»." % str(t[1])
	return null

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
