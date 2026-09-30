extends LabModule
## Gráficas: la calculadora gráfica del laboratorio.
##
##   · Funciones y = f(x): hasta cuatro a la vez, con sus raíces, extremos y los
##     cortes entre ellas marcados y listados.
##   · Curvas paramétricas (x(t), y(t)) y polares r(θ), con la misma escala en
##     los dos ejes.
##   · Superficies z = f(x, y) (evaluadas en la GPU).
##   · Puntos (una tabla de datos) sobre el tablero; con «Perturbar», clic = punto.
##
## Es el destino de «grafica esto» desde el chat de OpenClaw (acción «grafica»)
## y desde la API local (lab_plot): load_spec() lo configura todo de una vez.

const W := 3.2
const HGT := 1.9
const LIFT := 0.9
const SIZE := 4.0
const HEIGHT := 2.0
const NF := 4
const COLORS := [Color(0.3, 0.85, 1.0), Color(1.0, 0.62, 0.2), Color(0.45, 1.0, 0.5), Color(1.0, 0.45, 0.85)]
const SUB := ["₁", "₂", "₃", "₄"]
const TIPOS := ["Funciones y = f(x)", "Paramétrica (x(t), y(t))", "Polar r(θ)", "Superficie z = f(x, y)"]
const MAX_MARKS := 12           # marcas por función (o par de funciones) y tipo
const PRESETS := [
	{"nombre": "Parábola y seno", "funciones": ["x^2 - 2", "sin x"], "x": ["-3", "3"]},
	{"nombre": "Polinomio cúbico", "funciones": ["x^3 - 3x + 1"], "x": ["-2.5", "2.5"]},
	{"nombre": "Exponencial y logaritmo", "funciones": ["e^x", "ln x", "x"], "x": ["-3", "4"], "y": ["-3", "5"]},
	{"nombre": "Tangente (asíntotas)", "funciones": ["tan x"], "x": ["-2pi", "2pi"], "y": ["-4", "4"]},
	{"nombre": "Oscilación amortiguada", "funciones": ["e^(-x/4) cos(2x)", "e^(-x/4)", "-e^(-x/4)"], "x": ["0", "12"]},
	{"nombre": "Curva de Lissajous", "parametrica": {"x": "sin(3t)", "y": "sin(2t)", "t": ["0", "2pi"]}},
	{"nombre": "Cardioide (polar)", "polar": {"r": "1 + cos t", "t": ["0", "2pi"]}},
	{"nombre": "Rosa de 4 pétalos (polar)", "polar": {"r": "cos(2t)", "t": ["0", "2pi"]}},
	{"nombre": "Silla de montar", "superficie": "x^2 - y^2", "x": ["-2", "2"], "y": ["-2", "2"]},
	{"nombre": "Onda radial", "superficie": "sin(sqrt(x^2 + y^2) * 2) / (1 + 0.3(x^2 + y^2))", "x": ["-6", "6"], "y": ["-6", "6"]},
]

var tipo: int = 0
var preset: int = 0
var f_text: Array = ["", "", "", ""]
var f_expr: Array = [null, null, null, null]
var x_text: Array = ["-3", "3"]
var xr := Vector2(-3, 3)
var y_auto: bool = true
var y_text: Array = ["-3", "3"]
var yr := Vector2(-3, 3)
var px_text: String = "sin(3t)"
var py_text: String = "sin(2t)"
var r_text: String = "1 + cos t"
var t_text: Array = ["0", "2pi"]
var tr := Vector2(0, TAU)
var px_expr: MathExpr
var py_expr: MathExpr
var r_expr: MathExpr
var z_text: String = "x^2 - y^2"
var z_expr: MathExpr
var zr := Vector2(0, 1)
var puntos: Array = []          # [Vector2]
var marcar: bool = true
var titulo: String = ""
var marks: Array = []           # [{x, y, tipo, nombre, col, f}]
var win := {"x0": -3.0, "x1": 3.0, "y0": -3.0, "y1": 3.0}
var board_node: Node3D
var draw_node: Node3D
var surf_mesh: MeshInstance3D
var surf_mat: ShaderMaterial
var _panel: VBoxContainer

func title() -> String: return "Gráficas"
func planar() -> bool: return tipo != 3
func perturb_hint() -> String:
	return "clic sobre la superficie: lectura de f(x, y)" if tipo == 3 else "clic en el tablero: añade el punto (x, y)"
func view() -> Dictionary:
	if tipo == 3:
		return {"target": Vector3(0, 0.6, 0), "dist": 7.5, "yaw": -35.0, "pitch": -35.0}
	return {"target": Vector3(0, LIFT, 0), "dist": 8.6, "yaw": -5.0, "pitch": -5.0}

func formula() -> String:
	match tipo:
		1: return "x(t) = %s,  y(t) = %s" % [_pretty(px_expr), _pretty(py_expr)]
		2: return "r(θ) = %s" % _theta(_pretty(r_expr))
		3: return "z = %s" % _pretty(z_expr)
	var parts := []
	for i in range(NF):
		if f_expr[i] != null:
			parts.append("f%s(x) = %s" % [SUB[i], (f_expr[i] as MathExpr).to_pretty()])
	return "   ".join(parts) if not parts.is_empty() else "Escribe una función f(x)"

static func _pretty(m: MathExpr) -> String:
	return m.to_pretty() if m != null and m.ok() else "—"

## La variable t de las polares se muestra como θ (sin tocar «tan», «sqrt»…).
static var _t_re: RegEx
static func _theta(s: String) -> String:
	if _t_re == null:
		_t_re = RegEx.create_from_string("(?<![A-Za-z])t(?![A-Za-z])")
	return _t_re.sub(s, "θ", true)

func setup() -> void:
	board_node = Node3D.new()
	add_child(board_node)
	draw_node = Node3D.new()
	add_child(draw_node)
	surf_mesh = MeshInstance3D.new()
	surf_mesh.mesh = SurfaceShader.plane(SIZE, 200)
	add_child(surf_mesh)
	load_preset(0)

# --- Configuración ---------------------------------------------------------------------------

static func _num(v) -> float:
	if typeof(v) in [TYPE_INT, TYPE_FLOAT]:
		return float(v)
	var m := MathExpr.parse(str(v), [])
	return m.eval_real({}) if m.ok() else NAN

func _range2(v, texts: Array, fallback: Vector2) -> Dictionary:
	if typeof(v) != TYPE_ARRAY or v.size() < 2:
		return {"ok": false, "r": fallback, "t": texts}
	var a := _num(v[0])
	var b := _num(v[1])
	if not (is_finite(a) and is_finite(b)) or a == b:
		return {"ok": false, "r": fallback, "t": texts}
	return {"ok": true, "r": Vector2(minf(a, b), maxf(a, b)), "t": [str(v[0]), str(v[1])] if a < b else [str(v[1]), str(v[0])]}

func load_preset(i: int) -> void:
	preset = clampi(i, 0, PRESETS.size() - 1)
	var spec: Dictionary = PRESETS[preset].duplicate(true)
	spec.erase("nombre")
	load_spec(spec)

## Configura la gráfica de una vez (chat de OpenClaw, API lab_plot y ejemplos):
##   {"funciones": ["x^2 - 2", "sin x"], "x": [-3, 3], "y": [-4, 4],
##    "parametrica": {"x": "cos t", "y": "sin t", "t": [0, "2pi"]},
##    "polar": {"r": "1 + cos θ", "t": [0, "2pi"]},
##    "superficie": "sin x cos y", "puntos": [[1, 2], [3, 4]],
##    "titulo": "Ejercicio 3", "marcar": true}
## Devuelve {ok, tipo, errores: [...]}; lo que no se entiende se omite y se avisa.
func load_spec(spec: Dictionary) -> Dictionary:
	var errs := []
	var new_tipo := 0
	if spec.has("superficie") or spec.has("z"):
		new_tipo = 3
	elif spec.has("polar"):
		new_tipo = 2
	elif spec.has("parametrica"):
		new_tipo = 1
	titulo = str(spec.get("titulo", ""))
	marcar = bool(spec.get("marcar", true))
	puntos = []
	var pts = spec.get("puntos", [])
	if typeof(pts) == TYPE_STRING:
		puntos = parse_points(pts)
	elif typeof(pts) == TYPE_ARRAY:
		for q in pts:
			if typeof(q) == TYPE_ARRAY and q.size() >= 2 and is_finite(_num(q[0])) and is_finite(_num(q[1])):
				puntos.append(Vector2(_num(q[0]), _num(q[1])))
			elif typeof(q) == TYPE_DICTIONARY and q.has("x") and q.has("y"):
				puntos.append(Vector2(_num(q["x"]), _num(q["y"])))
			else:
				errs.append("punto no válido: %s" % str(q))
	var rx := _range2(spec.get("x", null), x_text, xr)
	if spec.has("x") and not rx["ok"]:
		errs.append("intervalo x no válido: %s" % str(spec["x"]))
	var ry := _range2(spec.get("y", null), y_text, yr)
	if spec.has("y") and not ry["ok"]:
		errs.append("intervalo y no válido: %s" % str(spec["y"]))
	match new_tipo:
		0:
			var fs = spec.get("funciones", spec.get("f", []))
			if typeof(fs) == TYPE_STRING:
				fs = [fs]
			if typeof(fs) != TYPE_ARRAY:
				fs = []
			var n := 0
			f_text = ["", "", "", ""]
			f_expr = [null, null, null, null]
			for s in fs:
				var t := str(s).strip_edges()
				for pre in ["y =", "y=", "f(x) =", "f(x)="]:
					if t.begins_with(pre):
						t = t.substr(pre.length()).strip_edges()
				if n >= NF:
					errs.append("solo caben %d funciones: se omite «%s»" % [NF, t])
					continue
				var m := MathExpr.parse(t, ["x"])
				if not m.ok():
					errs.append("«%s»: %s" % [t, m.error])
					continue
				m.compile_fast()
				f_text[n] = t
				f_expr[n] = m
				n += 1
			if n == 0 and puntos.is_empty():
				errs.append("no hay ninguna función válida que dibujar")
			if rx["ok"]:
				xr = rx["r"]
				x_text = rx["t"]
			elif n == 0 and not puntos.is_empty():
				# Solo datos: la ventana los abarca.
				var lo := INF
				var hi := -INF
				for q in puntos:
					lo = minf(lo, q.x)
					hi = maxf(hi, q.x)
				var pad := maxf(0.5, (hi - lo) * 0.1)
				xr = Vector2(lo - pad, hi + pad)
				x_text = [_short(xr.x), _short(xr.y)]
			else:
				xr = Vector2(-5, 5)
				x_text = ["-5", "5"]
			y_auto = not ry["ok"]
			if ry["ok"]:
				yr = ry["r"]
				y_text = ry["t"]
		1:
			var p = spec.get("parametrica", {})
			if typeof(p) != TYPE_DICTIONARY:
				p = {}
			px_text = str(p.get("x", px_text))
			py_text = str(p.get("y", py_text))
			var rt := _range2(p.get("t", null), t_text, Vector2(0, TAU))
			tr = rt["r"] if rt["ok"] else Vector2(0, TAU)
			t_text = rt["t"] if rt["ok"] else ["0", "2pi"]
			px_expr = _parse_or_err(px_text, ["t"], "x(t)", errs)
			py_expr = _parse_or_err(py_text, ["t"], "y(t)", errs)
		2:
			var q = spec.get("polar", {})
			if typeof(q) == TYPE_STRING:
				q = {"r": q}
			if typeof(q) != TYPE_DICTIONARY:
				q = {}
			r_text = str(q.get("r", r_text)).replace("θ", "t").replace("theta", "t")
			var rt2 := _range2(q.get("t", q.get("theta", null)), t_text, Vector2(0, TAU))
			tr = rt2["r"] if rt2["ok"] else Vector2(0, TAU)
			t_text = rt2["t"] if rt2["ok"] else ["0", "2pi"]
			r_expr = _parse_or_err(r_text, ["t"], "r(θ)", errs)
		3:
			z_text = str(spec.get("superficie", spec.get("z", z_text)))
			for pre in ["z =", "z=", "f(x, y) =", "f(x,y) ="]:
				if z_text.begins_with(pre):
					z_text = z_text.substr(pre.length()).strip_edges()
			z_expr = _parse_or_err(z_text, ["x", "y"], "z", errs)
			xr = rx["r"] if rx["ok"] else Vector2(-2, 2)
			x_text = rx["t"] if rx["ok"] else ["-2", "2"]
			yr = ry["r"] if ry["ok"] else Vector2(-2, 2)
			y_text = ry["t"] if ry["ok"] else ["-2", "2"]
	var changed_kind := planar() != (new_tipo != 3)
	tipo = new_tipo
	_redraw()
	if _panel:
		call_deferred("_rebuild_ui")
	if lab:
		lab._update_info(false)
		if changed_kind:
			lab.reset_view()
	return {"ok": errs.is_empty(), "tipo": TIPOS[tipo], "errores": errs}

func _parse_or_err(t: String, vars: Array, what: String, errs: Array) -> MathExpr:
	var m := MathExpr.parse(t, vars)
	if not m.ok():
		errs.append("%s = «%s»: %s" % [what, t, m.error])
		return null
	m.compile_fast()
	return m

## «(1, 2); (3, 4)», «1 2, 3 4» o una línea por punto → [Vector2].
static func parse_points(s: String) -> Array:
	var out := []
	var clean := s.replace("(", " ").replace(")", " ").replace("[", " ").replace("]", " ")
	for chunk in clean.replace("\n", ";").split(";", false):
		var nums := []
		for tok in chunk.replace(",", " ").replace("\t", " ").split(" ", false):
			var v := _num(tok)
			if is_finite(v):
				nums.append(v)
		var k := 0
		while k + 1 < nums.size():
			out.append(Vector2(nums[k], nums[k + 1]))
			k += 2
	return out

func points_text() -> String:
	var parts := []
	for p in puntos:
		parts.append("(%s, %s)" % [_short(p.x), _short(p.y)])
	return "; ".join(parts)

static func _short(v: float) -> String:
	return MathExpr._num_text(snappedf(v, 0.0001))

func set_tipo(i: int) -> void:
	var was_planar := planar()
	tipo = clampi(i, 0, TIPOS.size() - 1)
	match tipo:
		1:
			if px_expr == null: px_expr = _parse_or_err(px_text, ["t"], "x(t)", [])
			if py_expr == null: py_expr = _parse_or_err(py_text, ["t"], "y(t)", [])
		2:
			if r_expr == null: r_expr = _parse_or_err(r_text, ["t"], "r(θ)", [])
		3:
			if z_expr == null: z_expr = _parse_or_err(z_text, ["x", "y"], "z", [])
	_redraw()
	if _panel:
		call_deferred("_rebuild_ui")
	if lab:
		lab._update_info(false)
		if was_planar != planar():
			lab.reset_view()
		lab._status("%s — %s" % [TIPOS[tipo], perturb_hint()])

func F(i: int, x: float) -> float:
	var m: MathExpr = f_expr[i]
	if m == null:
		return NAN
	var v := m.eval_fast([x])
	return v if not is_nan(v) else m.eval_real({"x": x})

func _curve_point(t: float) -> Vector2:
	if tipo == 1:
		if px_expr == null or py_expr == null:
			return Vector2(NAN, NAN)
		return Vector2(px_expr.eval_fast([t]), py_expr.eval_fast([t]))
	if r_expr == null:
		return Vector2(NAN, NAN)
	var r := r_expr.eval_fast([t])
	return Vector2(r * cos(t), r * sin(t))

# --- Marcas: raíces, extremos y cortes ----------------------------------------------------

func _bisect(fn: Callable, a: float, b: float) -> float:
	var fa: float = fn.call(a)
	for k in range(60):
		var m := (a + b) * 0.5
		var fm: float = fn.call(m)
		if fm == 0.0:
			return m
		if (fa < 0.0) == (fm < 0.0):
			a = m
			fa = fm
		else:
			b = m
	return (a + b) * 0.5

## Máximo (sgn = 1) o mínimo (sgn = −1) de fn en [a, b] por sección áurea.
func _golden(fn: Callable, a: float, b: float, sgn: float) -> float:
	var g := (sqrt(5.0) - 1.0) * 0.5
	var c := b - g * (b - a)
	var d := a + g * (b - a)
	for k in range(60):
		if sgn * float(fn.call(c)) > sgn * float(fn.call(d)):
			b = d
		else:
			a = c
		c = b - g * (b - a)
		d = a + g * (b - a)
	return (a + b) * 0.5

## Ceros de fn en la ventana: cambios de signo afinados por bisección (se descartan
## los saltos de las asíntotas, donde |fn| no se hace pequeño) y muestras que ya
## son cero (también en los bordes de la ventana, como tan x en ±2π).
func _zeros(fn: Callable, x0: float, x1: float, scale: float) -> Array:
	var out := []
	var N := 1200
	var tiny := 1e-12 * maxf(1.0, scale)
	var sep := (x1 - x0) * 1e-6
	var pa := x0
	var va: float = fn.call(pa)
	for i in range(1, N + 1):
		var pb := lerpf(x0, x1, float(i) / N)
		var vb: float = fn.call(pb)
		if is_finite(va) and is_finite(vb):
			var root := NAN
			if absf(va) <= tiny:
				root = pa
			elif (va < 0.0) != (vb < 0.0) and absf(vb) > tiny:
				var r := _bisect(fn, pa, pb)
				if absf(float(fn.call(r))) < 1e-6 * maxf(1.0, scale):
					root = r
			if not is_nan(root) and (out.is_empty() or absf(float(out[-1]) - root) > sep):
				out.append(root)
		pa = pb
		va = vb
		if out.size() > MAX_MARKS:
			return out
	if is_finite(va) and absf(va) <= tiny and (out.is_empty() or absf(float(out[-1]) - pa) > sep):
		out.append(pa)
	return out

func _extrema(i: int, x0: float, x1: float) -> Array:
	var out := []
	var N := 1200
	# Cerca de un extremo de verdad la función apenas cambia entre muestras; en una
	# asíntota (tan x) salta de +∞ a −∞ y eso no es un máximo.
	var jump := 0.25 * absf(float(win["y1"]) - float(win["y0"]))
	var fn := func(x: float) -> float: return F(i, x)
	var v := []
	for k in range(N + 1):
		v.append(fn.call(lerpf(x0, x1, float(k) / N)))
	for k in range(1, N):
		var a: float = v[k - 1]
		var b: float = v[k]
		var c: float = v[k + 1]
		if not (is_finite(a) and is_finite(b) and is_finite(c)):
			continue
		if absf(a - b) > jump or absf(c - b) > jump:
			continue
		var sgn := 0.0
		if b > a and b >= c:
			sgn = 1.0
		elif b < a and b <= c:
			sgn = -1.0
		if sgn == 0.0:
			continue
		var x := _golden(fn, lerpf(x0, x1, float(k - 1) / N), lerpf(x0, x1, float(k + 1) / N), sgn)
		out.append([x, fn.call(x), "máximo" if sgn > 0.0 else "mínimo"])
		if out.size() > MAX_MARKS:
			break
	return out

func _compute_marks() -> void:
	marks = []
	if tipo != 0 or not marcar:
		return
	var x0 := float(win["x0"])
	var x1 := float(win["x1"])
	var scale := maxf(absf(float(win["y0"])), absf(float(win["y1"])))
	for i in range(NF):
		if f_expr[i] == null:
			continue
		var fn := func(x: float) -> float: return F(i, x)
		var zs := _zeros(fn, x0, x1, scale)
		for x in zs.slice(0, MAX_MARKS):
			marks.append({"x": x, "y": 0.0, "tipo": "raíz", "f": i, "col": COLORS[i],
				"nombre": "Raíz de f%s: x = %s" % [SUB[i], _short(x)]})
		for e in _extrema(i, x0, x1).slice(0, MAX_MARKS):
			marks.append({"x": e[0], "y": e[1], "tipo": e[2], "f": i, "col": COLORS[i],
				"nombre": "%s de f%s: (%s, %s)" % [str(e[2]).capitalize(), SUB[i], _short(e[0]), _short(e[1])]})
	for i in range(NF):
		for j in range(i + 1, NF):
			if f_expr[i] == null or f_expr[j] == null:
				continue
			var d := func(x: float) -> float: return F(i, x) - F(j, x)
			for x in _zeros(d, x0, x1, scale).slice(0, MAX_MARKS):
				marks.append({"x": x, "y": F(i, x), "tipo": "corte", "f": i, "col": Color(1, 1, 1),
					"nombre": "Corte f%s = f%s: (%s, %s)" % [SUB[i], SUB[j], _short(x), _short(F(i, x))]})

# --- Ventana y escala ------------------------------------------------------------------------

func _auto_window() -> void:
	if tipo == 0:
		win = {"x0": xr.x, "x1": xr.y, "y0": yr.x, "y1": yr.y}
		if y_auto:
			var vals := []
			for i in range(NF):
				if f_expr[i] == null:
					continue
				for k in range(301):
					var v := F(i, lerpf(xr.x, xr.y, k / 300.0))
					if is_finite(v):
						vals.append(v)
			for p in puntos:
				if p.x >= xr.x and p.x <= xr.y:
					vals.append(p.y)
			if vals.is_empty():
				win["y0"] = -1.0
				win["y1"] = 1.0
			else:
				vals.sort()
				# Rango completo, salvo que unos pocos valores disparados (asíntotas) lo
				# multipliquen: entonces percentiles 3–97 % para no aplastar la gráfica.
				var lo: float = vals[0]
				var hi: float = vals[vals.size() - 1]
				var plo: float = vals[int(vals.size() * 0.03)]
				var phi: float = vals[mini(vals.size() - 1, int(vals.size() * 0.97))]
				if hi - lo > 3.0 * maxf(phi - plo, 1e-9):
					lo = plo
					hi = phi
				for p in puntos:
					lo = minf(lo, p.y)
					hi = maxf(hi, p.y)
				if hi - lo < 1e-9:
					lo -= 1.0
					hi += 1.0
				var pad := (hi - lo) * 0.1
				win["y0"] = lo - pad
				win["y1"] = hi + pad
		return
	# Paramétrica y polar: caja de la curva, misma escala en los dos ejes.
	var lo2 := Vector2(INF, INF)
	var hi2 := Vector2(-INF, -INF)
	for k in range(601):
		var q := _curve_point(lerpf(tr.x, tr.y, k / 600.0))
		if q.is_finite():
			lo2 = lo2.min(q)
			hi2 = hi2.max(q)
	for p in puntos:
		lo2 = lo2.min(p)
		hi2 = hi2.max(p)
	if not (lo2.is_finite() and hi2.is_finite()):
		lo2 = Vector2(-1, -1)
		hi2 = Vector2(1, 1)
	if tipo == 2:
		# El polo siempre a la vista.
		lo2 = lo2.min(Vector2.ZERO)
		hi2 = hi2.max(Vector2.ZERO)
	var c := (lo2 + hi2) * 0.5
	var half := (hi2 - lo2) * 0.5 * 1.12 + Vector2(1e-6, 1e-6)
	var k2 := maxf(half.x / W, half.y / HGT)
	win = {"x0": c.x - W * k2, "x1": c.x + W * k2, "y0": c.y - HGT * k2, "y1": c.y + HGT * k2}

func _X(x: float) -> float:
	return (x - (float(win["x0"]) + float(win["x1"])) * 0.5) * (2.0 * W / (float(win["x1"]) - float(win["x0"])))

func _Y(y: float) -> float:
	return (y - (float(win["y0"]) + float(win["y1"])) * 0.5) * (2.0 * HGT / (float(win["y1"]) - float(win["y0"])))

func _xw(wx: float) -> float:
	return wx / (2.0 * W / (float(win["x1"]) - float(win["x0"]))) + (float(win["x0"]) + float(win["x1"])) * 0.5

func _yw(wy: float) -> float:
	return wy / (2.0 * HGT / (float(win["y1"]) - float(win["y0"]))) + (float(win["y0"]) + float(win["y1"])) * 0.5

func _p(x: float, y: float) -> Vector3:
	return Vector3(_X(x), _Y(y), 0.0)

## Espacio del tablero (local, sin la elevación) ↔ coordenadas matemáticas.
func to_world(x: float, y: float, z: float) -> Vector3:
	if tipo == 3:
		return _surf(x, y) if is_finite(z) else Vector3.ZERO
	return _p(x, y) + Vector3(0, LIFT, 0)

func to_math(w: Vector3) -> Vector3:
	if tipo == 3:
		return Vector3(lerpf(xr.x, xr.y, w.x / SIZE + 0.5), lerpf(yr.x, yr.y, 0.5 - w.z / SIZE), w.y)
	return Vector3(_xw(w.x), _yw(w.y - LIFT), 0.0)

func _in_y(y: float) -> bool:
	var m := (float(win["y1"]) - float(win["y0"])) * 0.04
	return is_finite(y) and y >= float(win["y0"]) - m and y <= float(win["y1"]) + m

# --- Dibujo ------------------------------------------------------------------------------------

func _redraw() -> void:
	for c in board_node.get_children():
		c.queue_free()
	for c in draw_node.get_children():
		c.queue_free()
	if tipo == 3:
		_draw_surface()
		return
	surf_mesh.visible = false
	clip_materials.clear()
	board_node.position = Vector3(0, LIFT, 0)
	draw_node.position = Vector3(0, LIFT, 0)
	_auto_window()
	_compute_marks()
	_board()
	match tipo:
		0:
			for i in range(NF):
				if f_expr[i] != null:
					_fn_curve(i)
		1, 2:
			_param_curve()
	for p in puntos:
		if p.x >= float(win["x0"]) and p.x <= float(win["x1"]) and _in_y(p.y):
			var s := sphere(0.045, glow_mat(Color(1.0, 0.92, 0.35), 2.4))
			s.position = _p(p.x, p.y) + Vector3(0, 0, 0.02)
			draw_node.add_child(s)
	var labeled := {}
	var used: Array = []            # posiciones de las etiquetas ya puestas
	for mk in marks:
		if not _in_y(float(mk["y"])):
			continue
		var s2 := sphere(0.04 if mk["tipo"] != "corte" else 0.05, glow_mat(mk["col"], 2.6))
		s2.position = _p(mk["x"], mk["y"]) + Vector3(0, 0, 0.03)
		draw_node.add_child(s2)
		# Etiquetas solo para las primeras marcas de cada tipo: con sin x en [−100, 100] serían un muro.
		var key := "%s%d" % [mk["tipo"], mk["f"]]
		labeled[key] = int(labeled.get(key, 0)) + 1
		var lp := s2.position + Vector3(0.06, 0.12, 0.02)
		var free := true
		for q in used:
			if absf((q as Vector3).y - lp.y) < 0.12 and absf((q as Vector3).x - lp.x) < 0.75:
				free = false
				break
		if labeled[key] <= 4 and free:
			used.append(lp)
			var txt := "(%s, %s)" % [_short(mk["x"]), _short(mk["y"])]
			draw_node.add_child(label3d(txt, lp, (mk["col"] as Color).lerp(Color.WHITE, 0.3), 0.0022))

func _board() -> void:
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(W * 2.0 + 0.4, HGT * 2.0 + 0.4, 0.04)
	board.mesh = bm
	board.material_override = glass_mat(Color(0.05, 0.12, 0.2), 0.55)
	board.position = Vector3(0, 0, -0.12)
	board_node.add_child(board)
	var grid_m := glow_mat(Color(0.35, 0.45, 0.6), 0.35)
	var axis_m := glow_mat(Color(0.8, 0.85, 0.95), 1.0)
	for axis in [0, 1]:
		var lo := float(win["x0"] if axis == 0 else win["y0"])
		var hi := float(win["x1"] if axis == 0 else win["y1"])
		var step := _tick_step(hi - lo)
		var t: float = ceilf(lo / step) * step
		var n := 0
		while t <= hi + step * 1e-6 and n < 40:
			n += 1
			var lbl := MathExpr._num_text(snappedf(t, step * 0.01))
			if axis == 0:
				var X := _X(t)
				board_node.add_child(rod(Vector3(X, -HGT, -0.02), Vector3(X, HGT, -0.02), 0.0025, grid_m))
				var y_lab := clampf(_Y(0.0), -HGT, HGT) - 0.13
				board_node.add_child(label3d(lbl, Vector3(X, y_lab, 0.02), Color(0.7, 0.75, 0.85), 0.0024))
			else:
				var Y := _Y(t)
				board_node.add_child(rod(Vector3(-W, Y, -0.02), Vector3(W, Y, -0.02), 0.0025, grid_m))
				if absf(t) > step * 0.01:
					var x_lab := clampf(_X(0.0), -W, W) - 0.16
					board_node.add_child(label3d(lbl, Vector3(x_lab, Y, 0.02), Color(0.7, 0.75, 0.85), 0.0024))
			t += step
	var y0 := _Y(0.0)
	if absf(y0) <= HGT:
		board_node.add_child(arrow(Vector3(-W - 0.1, y0, 0), Vector3(W + 0.2, y0, 0), 0.008, axis_m))
		board_node.add_child(label3d("x", Vector3(W + 0.3, y0 + 0.02, 0.02), Color(1, 0.5, 0.5), 0.003))
	var x0 := _X(0.0)
	if absf(x0) <= W:
		board_node.add_child(arrow(Vector3(x0, -HGT - 0.1, 0), Vector3(x0, HGT + 0.2, 0), 0.008, axis_m))
		board_node.add_child(label3d("y", Vector3(x0 + 0.06, HGT + 0.3, 0.02), Color(0.5, 1, 0.6), 0.003))
	# Leyenda y título.
	var legend := []
	match tipo:
		0:
			for i in range(NF):
				if f_expr[i] != null:
					legend.append(["f%s(x) = %s" % [SUB[i], (f_expr[i] as MathExpr).to_pretty()], COLORS[i]])
		1:
			legend.append(["x(t) = %s,  y(t) = %s,  t ∈ [%s, %s]" % [_pretty(px_expr), _pretty(py_expr), t_text[0], t_text[1]], COLORS[0]])
		2:
			legend.append(["r(θ) = %s,  θ ∈ [%s, %s]" % [_theta(_pretty(r_expr)), t_text[0], t_text[1]], COLORS[0]])
	if not puntos.is_empty():
		legend.append(["● %d puntos" % puntos.size(), Color(1.0, 0.92, 0.35)])
	if titulo != "":
		board_node.add_child(label3d(titulo, Vector3(0, HGT + 0.42 + legend.size() * 0.17, 0.02), Color(1, 1, 1), 0.0036))
	for k in range(legend.size()):
		var l := label3d(legend[k][0], Vector3(-W, HGT + 0.34 + (legend.size() - 1 - k) * 0.17, 0.03), legend[k][1], 0.0028)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		board_node.add_child(l)

static func _tick_step(span: float) -> float:
	var step := pow(10.0, floor(log(maxf(span, 1e-9)) / log(10.0)))
	if span / step < 4.0:
		step *= 0.5
	if span / step > 10.0:
		step *= 2.0
	return step

func _fn_curve(i: int) -> void:
	var x0 := float(win["x0"])
	var x1 := float(win["x1"])
	var span := float(win["y1"]) - float(win["y0"])
	var mat := glow_mat(COLORS[i], 1.6)
	var pts := PackedVector3Array()
	var N := 700
	var prev := NAN
	for k in range(N + 1):
		var x := lerpf(x0, x1, float(k) / N)
		var y := F(i, x)
		# Se corta en huecos, fuera de la ventana y en los saltos de las asíntotas.
		var inside := _in_y(y)
		var jump := inside and is_finite(prev) and absf(y - prev) > span * 0.6
		if not inside or jump:
			if pts.size() >= 2:
				draw_node.add_child(tube(pts, 0.018, mat))
			pts = PackedVector3Array()
		if inside:
			pts.append(_p(x, y))
		prev = y
	if pts.size() >= 2:
		draw_node.add_child(tube(pts, 0.018, mat))

func _param_curve() -> void:
	var mat := glow_mat(COLORS[0], 1.6)
	var pts := PackedVector3Array()
	var N := 1200
	var prev := Vector2(NAN, NAN)
	var diag := Vector2(float(win["x1"]) - float(win["x0"]), float(win["y1"]) - float(win["y0"])).length()
	for k in range(N + 1):
		var q := _curve_point(lerpf(tr.x, tr.y, float(k) / N))
		var ok := q.is_finite() and _in_y(q.y) and q.x >= float(win["x0"]) and q.x <= float(win["x1"])
		if ok and prev.is_finite() and (q - prev).length() > diag * 0.3:
			ok = false
		if not ok:
			if pts.size() >= 2:
				draw_node.add_child(tube(pts, 0.018, mat))
			pts = PackedVector3Array()
			prev = q
			continue
		pts.append(_p(q.x, q.y))
		prev = q
	if pts.size() >= 2:
		draw_node.add_child(tube(pts, 0.018, mat))
	if tipo == 2:
		var s := sphere(0.035, glow_mat(Color(1, 1, 1), 2.0))
		s.position = _p(0, 0)
		draw_node.add_child(s)

func _surf(x: float, y: float) -> Vector3:
	var u := (x - xr.x) / (xr.y - xr.x)
	var v := (y - yr.x) / (yr.y - yr.x)
	var h := 0.0
	if z_expr != null:
		h = clampf((z_expr.eval_fast([x, y]) - zr.x) / maxf(1e-9, zr.y - zr.x), -0.05, 1.05) * HEIGHT
	return Vector3((u - 0.5) * SIZE, h + 0.025, -(v - 0.5) * SIZE)

func _draw_surface() -> void:
	board_node.position = Vector3.ZERO
	draw_node.position = Vector3.ZERO
	marks = []
	if z_expr == null:
		surf_mesh.visible = false
		return
	zr = SurfaceShader.value_range(z_expr, Vector2(xr.x, yr.x), Vector2(xr.y, yr.y), 80)
	surf_mat = ShaderMaterial.new()
	surf_mat.shader = SurfaceShader.make(z_expr)
	surf_mat.set_shader_parameter("dom_min", Vector2(xr.x, yr.x))
	surf_mat.set_shader_parameter("dom_max", Vector2(xr.y, yr.y))
	surf_mat.set_shader_parameter("world_size", SIZE)
	surf_mat.set_shader_parameter("zmin", zr.x)
	surf_mat.set_shader_parameter("zmax", zr.y)
	surf_mat.set_shader_parameter("height", HEIGHT)
	surf_mat.set_shader_parameter("log_mode", false)
	surf_mat.set_shader_parameter("pal", 0)
	surf_mat.set_shader_parameter("contour_step", 0.05)
	surf_mesh.material_override = surf_mat
	surf_mesh.visible = true
	clip_materials.clear()
	register_clip(surf_mat)
	var half := SIZE * 0.5
	var lab_col := Color(0.75, 0.8, 0.9)
	draw_node.add_child(label3d("x ∈ [%s, %s]" % [x_text[0], x_text[1]], Vector3(0, 0.05, half + 0.3), lab_col, 0.003))
	draw_node.add_child(label3d("y ∈ [%s, %s]" % [y_text[0], y_text[1]], Vector3(half + 0.4, 0.05, 0), lab_col, 0.003))
	draw_node.add_child(label3d("z = %s ∈ [%s, %s]" % [_pretty(z_expr), _short(zr.x), _short(zr.y)], Vector3(0, HEIGHT + 0.25, -half), lab_col, 0.003))
	if titulo != "":
		draw_node.add_child(label3d(titulo, Vector3(0, HEIGHT + 0.55, -half), Color(1, 1, 1), 0.0036))

# --- Interfaz ------------------------------------------------------------------------------------

func _rebuild_ui() -> void:
	if not is_instance_valid(_panel):
		return
	for k in range(_panel.get_child_count() - 1, 0, -1):
		var c := _panel.get_child(k)
		_panel.remove_child(c)
		c.queue_free()
	build_ui(_panel)

func build_ui(p: VBoxContainer) -> void:
	_panel = p
	LabUI.option(p, "Tipo:", TIPOS, tipo, func(i): set_tipo(i))
	var names := []
	for q in PRESETS:
		names.append(q["nombre"])
	LabUI.option(p, "Ejemplo:", names, preset, func(i): load_preset(i))
	match tipo:
		0:
			for i in range(NF):
				var idx := i
				LabUI.expr_field(p, "f%s(x) =" % SUB[i], f_text[i], ["x"], false, func(m):
					_set_fn(idx, m), true)
			LabUI.section(p, "Ventana")
			_range_fields(p, "x", x_text, func(r, t):
				xr = r
				x_text = t
				_changed())
			LabUI.check(p, "y automática", y_auto, func(v):
				y_auto = v
				_changed())
			_range_fields(p, "y", y_text, func(r, t):
				yr = r
				y_text = t
				y_auto = false
				_changed())
			LabUI.check(p, "Marcar raíces, extremos y cortes", marcar, func(v):
				marcar = v
				_changed())
		1:
			LabUI.expr_field(p, "x(t) =", px_text, ["t"], false, func(m):
				px_expr = m
				px_expr.compile_fast()
				px_text = m.source
				_changed())
			LabUI.expr_field(p, "y(t) =", py_text, ["t"], false, func(m):
				py_expr = m
				py_expr.compile_fast()
				py_text = m.source
				_changed())
			_range_fields(p, "t", t_text, func(r, t):
				tr = r
				t_text = t
				_changed())
		2:
			LabUI.expr_field(p, "r(t) =", r_text, ["t"], false, func(m):
				r_expr = m
				r_expr.compile_fast()
				r_text = m.source
				_changed())
			LabUI.note(p, "t es el ángulo θ (en radianes).")
			_range_fields(p, "θ", t_text, func(r, t):
				tr = r
				t_text = t
				_changed())
		3:
			LabUI.expr_field(p, "f(x, y) =", z_text, ["x", "y"], false, func(m):
				z_expr = m
				z_expr.compile_fast()
				z_text = m.source
				_changed())
			LabUI.section(p, "Dominio")
			_range_fields(p, "x", x_text, func(r, t):
				xr = r
				x_text = t
				_changed())
			_range_fields(p, "y", y_text, func(r, t):
				yr = r
				y_text = t
				_changed())
	if tipo != 3:
		LabUI.section(p, "Puntos")
		var pe := LabUI.text_field(p, "Puntos (x, y):", points_text(), "(1, 2); (3, 4)", func(t):
			puntos = parse_points(t)
			_changed())
		pe.tooltip_text = "Pares (x, y) separados por «;» o uno por línea, p. ej. (0, 1); (2, 3.5)"
		LabUI.button(p, "Borrar puntos", func():
			puntos = []
			_changed()
			call_deferred("_rebuild_ui"))
	LabUI.note(p, "Se escribe como en papel: 2x, sin x, x², e^-x, √x, ln|x|. OpenClaw puede dibujar aquí lo que lea en una imagen o un PDF adjunto al chat.")

func _range_fields(p: VBoxContainer, v: String, texts: Array, cb: Callable) -> void:
	var cur := [str(texts[0]), str(texts[1])]
	var apply := func():
		var a := _num(cur[0])
		var b := _num(cur[1])
		if is_finite(a) and is_finite(b) and b > a:
			cb.call(Vector2(a, b), cur.duplicate())
	LabUI.value_field(p, "%s mín.:" % v, cur[0], func(_val, t):
		cur[0] = t
		apply.call())
	LabUI.value_field(p, "%s máx.:" % v, cur[1], func(_val, t):
		cur[1] = t
		apply.call())

func _set_fn(i: int, m) -> void:
	if m == null:
		f_text[i] = ""
		f_expr[i] = null
	else:
		var e: MathExpr = m
		e.compile_fast()
		f_text[i] = e.source
		f_expr[i] = e
	_changed()

func _changed() -> void:
	_redraw()
	if lab:
		lab._update_info(false)

# --- Ratón, API y lecturas ----------------------------------------------------------------------

func pick(origin: Vector3, dir: Vector3):
	if tipo == 3:
		var hf := func(X: float, Z: float) -> float:
			return _surf(lerpf(xr.x, xr.y, X / SIZE + 0.5), lerpf(yr.x, yr.y, 0.5 - Z / SIZE)).y - 0.025
		return ray_heightfield(origin, dir, hf, SIZE * 0.5)
	if absf(dir.z) < 1e-6:
		return null
	var t := -origin.z / dir.z
	if t < 0.0:
		return null
	var hit := origin + dir * t
	var lp := hit - Vector3(0, LIFT, 0)
	if absf(lp.x) > W + 0.1 or absf(lp.y) > HGT + 0.2:
		return null
	return hit

func hover_text(hit: Vector3) -> String:
	if tipo == 3:
		var q := to_math(hit)
		return "x = %.4f   y = %.4f\nz = %.6f" % [q.x, q.y, z_expr.eval_fast([q.x, q.y]) if z_expr else NAN]
	var x := _xw(hit.x)
	var y := _yw(hit.y - LIFT)
	var t := "x = %.4f   y = %.4f" % [x, y]
	if tipo == 0:
		for i in range(NF):
			if f_expr[i] != null:
				t += "\nf%s(x) = %.6f" % [SUB[i], F(i, x)]
	elif tipo == 2:
		t += "\nr = %.4f   θ = %.4f rad" % [Vector2(x, y).length(), atan2(y, x)]
	return t

func perturb(hit: Vector3, first: bool) -> void:
	if not first or tipo == 3:
		return
	puntos.append(Vector2(snappedf(_xw(hit.x), 0.001), snappedf(_yw(hit.y - LIFT), 0.001)))
	_changed()
	if _panel:
		call_deferred("_rebuild_ui")

func api_points(x: float, y: float) -> Array:
	if tipo == 3:
		var u := (x - xr.x) / (xr.y - xr.x) - 0.5
		var v := 0.5 - (y - yr.x) / (yr.y - yr.x)
		return [to_global(Vector3(u * SIZE, 0.0, v * SIZE))]
	return [to_global(_p(x, y) + Vector3(0, LIFT, 0))]

func critical_points() -> Array:
	var out := []
	for mk in marks:
		if _in_y(float(mk["y"])):
			out.append({"pos": to_global(_p(mk["x"], mk["y"]) + Vector3(0, LIFT, 0)), "nombre": mk["nombre"], "dist": 3.0})
	return out

## Capturas (mflabshot graficas <modo>): «polar», «parametrica», «superficie», «tangente», «puntos».
func demo(extra: Array) -> void:
	if "polar" in extra:
		load_preset(6)
	elif "parametrica" in extra:
		load_preset(5)
	elif "superficie" in extra:
		load_preset(9)
	elif "tangente" in extra:
		load_preset(3)
	elif "puntos" in extra:
		load_spec({"funciones": ["0.5x + 1"], "x": [0, 6], "puntos": [[0.5, 1.1], [1.5, 1.9], [2.5, 2.2], [3.5, 2.9], [4.5, 3.1], [5.5, 3.9]], "titulo": "Ajuste de datos"})
	await lab.get_tree().process_frame

func info() -> String:
	if tipo == 3:
		return "z ∈ [%s, %s] en x ∈ [%s, %s], y ∈ [%s, %s]" % [_short(zr.x), _short(zr.y), x_text[0], x_text[1], y_text[0], y_text[1]] if z_expr else ""
	var t := ""
	if tipo == 0:
		for i in range(NF):
			if f_expr[i] == null:
				continue
			var roots := []
			var ext := []
			for mk in marks:
				if int(mk["f"]) != i:
					continue
				if mk["tipo"] == "raíz":
					roots.append(_short(mk["x"]))
				elif mk["tipo"] in ["máximo", "mínimo"]:
					ext.append("%s (%s, %s)" % [mk["tipo"], _short(mk["x"]), _short(mk["y"])])
			var col := (COLORS[i] as Color).to_html(false)
			t += "[color=#%s]f%s[/color]: " % [col, SUB[i]]
			t += ("raíces x = " + ", ".join(roots)) if not roots.is_empty() else "sin raíces en la ventana"
			if not ext.is_empty():
				t += "; " + ", ".join(ext.slice(0, 4)) + ("…" if ext.size() > 4 else "")
			t += "\n"
		var cuts := []
		for mk in marks:
			if mk["tipo"] == "corte":
				cuts.append(mk["nombre"].split(": ")[1] if ": " in mk["nombre"] else mk["nombre"])
		if not cuts.is_empty():
			t += "Cortes: " + ", ".join(cuts.slice(0, 6)) + "\n"
	elif tipo == 1:
		t += "t ∈ [%s, %s]\n" % [t_text[0], t_text[1]]
	elif tipo == 2:
		t += "θ ∈ [%s, %s]\n" % [t_text[0], t_text[1]]
	if not puntos.is_empty():
		t += "%d puntos: %s" % [puntos.size(), points_text().left(160)]
	return t.strip_edges()
