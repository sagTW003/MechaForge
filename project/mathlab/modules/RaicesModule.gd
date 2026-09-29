extends LabModule
## Ecuaciones no lineales f(x) = 0: bisección, Newton-Raphson, secante y punto
## fijo, paso a paso sobre la gráfica 3D. Muestra intervalos, tangentes, secantes
## o el diagrama de telaraña, la tabla de iteraciones, el orden de convergencia
## observado y la gráfica de convergencia (log₁₀ del error).

const METHODS := ["Bisección", "Newton-Raphson", "Secante", "Punto fijo"]
const W := 3.0          # semiancho del tablero (mundo)
const HGT := 2.0        # semialto del tablero

var f_expr: MathExpr
var g_expr: MathExpr
var method: int = 1
var xa: float = -3.0
var xb: float = 3.0
var a0: float = 1.0
var b0: float = 3.0
var x0: float = 3.0
var x1: float = 2.5
var tol: float = 1e-10
var hist: Array = []           # [{x, fx, a, b, extra}]
var root_ref: float = NAN
var ky: float = 1.0
var yrange: Vector2 = Vector2(-10, 10)
var curve_node: Node3D
var iter_node: Node3D
var plot: Control
var _auto: bool = false
var _auto_t: float = 0.0
var _table: String = ""

func title() -> String: return "Ecuaciones no lineales"
func formula() -> String: return ["f(a)·f(b) < 0 → c = (a + b)/2", "xₙ₊₁ = xₙ − f(xₙ)/f′(xₙ)", "xₙ₊₁ = xₙ − f(xₙ)(xₙ − xₙ₋₁)/(f(xₙ) − f(xₙ₋₁))", "xₙ₊₁ = g(xₙ)"][method]
func uses_time() -> bool: return true
func perturb_hint() -> String: return "clic sobre el eje x: fija el punto inicial (o el extremo más cercano del intervalo)"
const LIFT := 0.8
func view() -> Dictionary: return {"target": Vector3(0, LIFT, 0), "dist": 8.5, "yaw": -8.0, "pitch": -8.0}

func setup() -> void:
	position = Vector3(0, LIFT, 0)
	f_expr = MathExpr.parse("x^3 - 2x - 5", ["x"])
	g_expr = MathExpr.parse("(2x + 5)^(1/3)", ["x"])
	# Tablero de vidrio oscuro y ejes.
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(W * 2.0 + 0.4, HGT * 2.0 + 0.4, 0.04)
	board.mesh = bm
	var gm := glass_mat(Color(0.05, 0.12, 0.2), 0.55)
	board.material_override = gm
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
	var h := 1e-6 * maxf(1.0, absf(x))
	return (_f(x + h) - _f(x - h)) / (2.0 * h)

func _X(x: float) -> float:
	return (x - (xa + xb) * 0.5) * (2.0 * W / (xb - xa))

func _Y(y: float) -> float:
	return clampf(y * ky, -HGT * 1.2, HGT * 1.2)

func _p(x: float, y: float) -> Vector3:
	return Vector3(_X(x), _Y(y), 0.0)

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
	# Curva f(x) por tramos continuos.
	_add_curve(func(x): return _f(x), Color(0.3, 0.85, 1.0), 0.022)
	if method == 3:
		_add_curve(func(x): return _g(x), Color(1.0, 0.45, 0.85), 0.016)
		var a := maxf(xa, -HGT / ky)
		var b := minf(xb, HGT / ky)
		if b > a:
			curve_node.add_child(rod(_p(a, a), _p(b, b), 0.008, glow_mat(Color(0.7, 0.7, 0.75), 0.8)))
	# Raíz de referencia (Newton con muchas iteraciones desde varios puntos).
	root_ref = NAN
	for s in [x0, (a0 + b0) * 0.5, 0.0, xa, xb]:
		var x: float = s
		for k in range(80):
			var d := _df(x)
			if d == 0.0 or not is_finite(d):
				break
			x -= _f(x) / d
		if is_finite(x) and absf(_f(x)) < 1e-9:
			root_ref = x
			break

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

func reset() -> void:
	hist.clear()
	_auto = false
	match method:
		0: hist.append({"a": a0, "b": b0, "x": (a0 + b0) * 0.5, "fx": _f((a0 + b0) * 0.5)})
		1, 3: hist.append({"x": x0, "fx": _f(x0)})
		2:
			hist.append({"x": x0, "fx": _f(x0)})
			hist.append({"x": x1, "fx": _f(x1)})
	_draw_iters()

func converged() -> bool:
	if hist.size() < 2:
		return false
	var last: Dictionary = hist[hist.size() - 1]
	var prev: Dictionary = hist[hist.size() - 2]
	if method == 0:
		return absf(float(last["b"]) - float(last["a"])) < tol
	return absf(float(last["x"]) - float(prev["x"])) < tol or absf(float(last["fx"])) < 1e-14

func do_step() -> bool:
	if hist.is_empty() or converged() or hist.size() > 60:
		return false
	var last: Dictionary = hist[hist.size() - 1]
	match method:
		0:
			var a: float = last["a"]
			var b: float = last["b"]
			var c: float = last["x"]
			if _f(a) * _f(c) <= 0.0:
				b = c
			else:
				a = c
			var m := (a + b) * 0.5
			hist.append({"a": a, "b": b, "x": m, "fx": _f(m)})
		1:
			var x: float = last["x"]
			var d := _df(x)
			if d == 0.0:
				return false
			var xn := x - _f(x) / d
			hist.append({"x": xn, "fx": _f(xn), "desde": x})
		2:
			var p: Dictionary = hist[hist.size() - 2]
			var xa_: float = p["x"]
			var xb_: float = last["x"]
			var den := _f(xb_) - _f(xa_)
			if den == 0.0:
				return false
			var xn2 := xb_ - _f(xb_) * (xb_ - xa_) / den
			hist.append({"x": xn2, "fx": _f(xn2)})
		3:
			var xg := _g(float(last["x"]))
			hist.append({"x": xg, "fx": _f(xg)})
	_draw_iters()
	return true

func step(dt: float) -> void:
	if not _auto:
		return
	_auto_t += dt
	if _auto_t >= 0.55:
		_auto_t = 0.0
		if not do_step():
			_auto = false

func _draw_iters() -> void:
	for c in iter_node.get_children():
		c.queue_free()
	var col_pt := glow_mat(Color(1.0, 0.8, 0.25), 3.0)
	var col_line := glow_mat(Color(1.0, 0.55, 0.2), 1.6)
	var n := hist.size()
	for i in range(n):
		var h: Dictionary = hist[i]
		var x: float = h["x"]
		var fade := 0.35 + 0.65 * float(i + 1) / n
		var s := sphere(0.035 if i < n - 1 else 0.06, col_pt)
		s.position = _p(x, 0.0)
		s.scale = Vector3.ONE * fade
		iter_node.add_child(s)
		match method:
			0:
				if i == n - 1:
					var slab := MeshInstance3D.new()
					var bm := BoxMesh.new()
					var wa := _X(float(h["a"]))
					var wb := _X(float(h["b"]))
					bm.size = Vector3(maxf(0.004, wb - wa), HGT * 2.0, 0.02)
					slab.mesh = bm
					slab.material_override = glass_mat(Color(1.0, 0.7, 0.2), 0.18)
					slab.position = Vector3((wa + wb) * 0.5, 0, -0.02)
					iter_node.add_child(slab)
					for e in ["a", "b"]:
						var xe: float = h[e]
						iter_node.add_child(rod(_p(xe, 0.0), _p(xe, _f(xe)), 0.008, col_line))
			1:
				if h.has("desde"):
					var xp: float = h["desde"]
					iter_node.add_child(rod(_p(xp, 0.0), _p(xp, _f(xp)), 0.006, glow_mat(Color(0.8, 0.8, 0.85), 0.8)))
					iter_node.add_child(rod(_p(xp, _f(xp)), _p(x, 0.0), 0.009, col_line))
			2:
				if i >= 1:
					var hp: Dictionary = hist[i - 1]
					var xp2: float = hp["x"]
					iter_node.add_child(rod(_p(xp2, _f(xp2)), _p(x, _f(x)), 0.007, col_line))
					if i + 1 < n:
						var xn: float = hist[i + 1]["x"]
						iter_node.add_child(rod(_p(x, _f(x)), _p(xn, 0.0), 0.005, glow_mat(Color(0.8, 0.8, 0.85), 0.8)))
			3:
				if i + 1 < n:
					var xn2: float = hist[i + 1]["x"]
					iter_node.add_child(rod(_p(x, x), _p(x, xn2), 0.008, col_line))
					iter_node.add_child(rod(_p(x, xn2), _p(xn2, xn2), 0.008, col_line))
	if not is_nan(root_ref):
		var r := sphere(0.05, glow_mat(Color(0.3, 1.0, 0.5), 2.5))
		r.position = _p(root_ref, 0.0) + Vector3(0, 0, 0.03)
		iter_node.add_child(r)
	_update_table()
	if plot:
		plot.queue_redraw()

func _errors() -> Array:
	var out := []
	for h in hist:
		var e := absf(float(h["x"]) - root_ref) if not is_nan(root_ref) else absf(float(h["fx"]))
		out.append(e)
	return out

func _update_table() -> void:
	var e := _errors()
	var lines := ["[font_size=12][color=#8fa3b8] n │ xₙ                  │ f(xₙ)          │ |error|[/color]"]
	var start := maxi(0, hist.size() - 9)
	for i in range(start, hist.size()):
		var h: Dictionary = hist[i]
		lines.append("%2d │ %+.14f │ %s │ %s" % [i, float(h["x"]), LabUI.sci(float(h["fx"]), 2), LabUI.sci(float(e[i]), 2)])
	var p := _order()
	lines.append("[/font_size]Iteraciones: %d%s%s" % [hist.size() - 1, "   ·   orden observado p ≈ %.2f" % p if not is_nan(p) else "", "   ·   ✔ convergido" if converged() else ""])
	_table = "\n".join(lines)

## Orden de convergencia observado: p ≈ ln(eₙ₊₁/eₙ)/ln(eₙ/eₙ₋₁).
func _order() -> float:
	var e := _errors()
	var best := NAN
	for i in range(2, e.size()):
		var e0: float = e[i - 2]
		var e1: float = e[i - 1]
		var e2: float = e[i]
		if e0 > 1e-13 and e1 > 1e-13 and e2 > 1e-13 and e0 != e1:
			best = log(e2 / e1) / log(e1 / e0)
	return best

func info() -> String:
	return _table

func build_ui(p: VBoxContainer) -> void:
	LabUI.option(p, "Método:", METHODS, method, func(i):
		method = i
		_rebuild_curve()
		reset()
		lab._update_info(false))
	LabUI.expr_field(p, "f(x) =", f_expr.source, ["x"], false, func(m):
		f_expr = m
		_rebuild_curve()
		reset())
	LabUI.expr_field(p, "g(x) = (punto fijo: x = g(x))", g_expr.source, ["x"], false, func(m):
		g_expr = m
		_rebuild_curve()
		reset())
	var r := LabUI.row(p)
	LabUI.spin(r, "a", -50, 50, 0.1, a0, func(v): a0 = v; reset())
	LabUI.spin(r, "b", -50, 50, 0.1, b0, func(v): b0 = v; reset())
	var r2 := LabUI.row(p)
	LabUI.spin(r2, "x₀", -50, 50, 0.1, x0, func(v): x0 = v; reset())
	LabUI.spin(r2, "x₁", -50, 50, 0.1, x1, func(v): x1 = v; reset())
	var r3 := LabUI.row(p)
	LabUI.spin(r3, "dominio", -100, 0, 0.5, xa, func(v): xa = v; _rebuild_curve(); reset()).set_meta("lab_param", "dominio desde")
	LabUI.spin(r3, "a", 0, 100, 0.5, xb, func(v): xb = v; _rebuild_curve(); reset()).set_meta("lab_param", "dominio hasta")
	var r4 := LabUI.row(p)
	LabUI.button(r4, "▶ Paso", func(): do_step())
	LabUI.button(r4, "⏩ Resolver", func(): _auto = true)
	LabUI.button(r4, "⟲", reset)
	LabUI.section(p, "Convergencia: log₁₀ |error| por iteración")
	plot = ConvPlot.new()
	plot.module = self
	plot.custom_minimum_size = Vector2(260, 130)
	p.add_child(plot)
	LabUI.note(p, "Bisección: lineal (error ÷2 por paso). Secante: superlineal (p ≈ 1.618). Newton: cuadrática (p ≈ 2, los dígitos correctos se duplican). Punto fijo: lineal con razón |g′(x*)|.")

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
	match method:
		0:
			if absf(x - a0) < absf(x - b0): a0 = x
			else: b0 = x
		2:
			x1 = x0
			x0 = x
		_: x0 = x
	reset()

func critical_points() -> Array:
	var out := []
	if not is_nan(root_ref):
		out.append({"pos": to_global(_p(root_ref, 0.0)), "nombre": "Raíz x* = %.10f" % root_ref, "dist": 2.0})
	if not hist.is_empty():
		out.append({"pos": to_global(_p(float(hist[0]["x"]), 0.0)), "nombre": "Punto inicial", "dist": 3.0})
	return out

func demo(_extra: Array) -> void:
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
		var e: Array = module._errors()
		if e.size() < 1:
			return
		var pts := PackedVector2Array()
		for i in range(e.size()):
			var le: float = log(maxf(float(e[i]), 1e-16)) / log(10.0)
			var x := r.size.x * float(i) / maxf(1.0, maxf(10.0, e.size() - 1))
			var y := r.size.y * clampf((2.0 - le) / 18.0, 0.0, 1.0)
			pts.append(Vector2(x, y))
			draw_circle(Vector2(x, y), 3.0, Color(1.0, 0.8, 0.3))
		if pts.size() >= 2:
			draw_polyline(pts, Color(1.0, 0.6, 0.2), 2.0, true)
		draw_string(ThemeDB.fallback_font, Vector2(4, 12), "10²", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.7, 0.8))
		draw_string(ThemeDB.fallback_font, Vector2(4, r.size.y - 4), "10⁻¹⁶", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.7, 0.8))
