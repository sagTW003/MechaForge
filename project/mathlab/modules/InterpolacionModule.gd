extends LabModule
## Interpolación y ajuste:
##   · Spline cúbico natural 3D por puntos de control arrastrables
##     (parametrización por longitud de cuerda; sistema tridiagonal por
##     coordenada) comparado con Catmull-Rom y la poligonal.
##     También B-spline cúbica uniforme y curva de Bézier (de Casteljau), que
##     aproximan sin pasar por los puntos.
##   · Mínimos cuadrados: ajuste de un plano o una cuádrica z = f(x, y) a datos con
##     ruido (ecuaciones normales AᵀA·c = Aᵀz), residuos y coeficiente R².
##   · Superficie por datos dispersos: Shepard (IDW), funciones de base radial
##     (gaussiana, multicuádrica, thin-plate spline), vecino más cercano y
##     interpolación lineal sobre la triangulación de Delaunay.

const S := 0.8
var mode: int = 0                 # 0 spline, 1 mínimos cuadrados, 2 datos dispersos
var ctrl: Array = [Vector3(-2.2, -0.6, 0.2), Vector3(-1.2, 0.9, 1.3), Vector3(0.0, -0.4, 0.6), Vector3(1.0, 1.1, 1.8), Vector3(2.0, 0.2, 0.4), Vector3(2.6, -1.0, 1.2)]
var show_catmull: bool = true
var show_poly: bool = true
var show_bspline: bool = false
var show_bezier: bool = false
const SC_METHODS := ["Shepard (IDW, 1/dᵖ)", "RBF gaussiana e^(−(εr)²)", "RBF multicuádrica √(1 + (εr)²)", "RBF thin-plate spline r²·ln r", "Vecino más cercano (Voronoi)", "Lineal sobre la triangulación de Delaunay"]
var sc_method: int = 3
var sc_n: int = 25
var sc_p: float = 2.0
var sc_eps: float = 1.2
var sc_data: Array = []
var sc_w: Array = []
var sc_tri: PackedInt32Array = PackedInt32Array()
var sc_rms: float = 0.0
var sc_max: float = 0.0
var show_truth: bool = true
var sel: int = -1
var model: int = 1                # 0 plano, 1 cuádrica
var noise: float = 0.25
var npts: int = 70
var data: Array = []
var coef: Array = []
var r2: float = 0.0
var rms: float = 0.0
var nodes: Node3D
var _drag_h: float = 0.0

func title() -> String: return "Interpolación y ajuste"
func formula() -> String:
	if mode == 0:
		return "S(t) cúbico por tramos, C² continuo, S″ = 0 en los extremos (spline natural)"
	if mode == 2:
		return ["s(x) = Σ wᵢ zᵢ / Σ wᵢ,  wᵢ = 1/‖x − xᵢ‖ᵖ", "s(x) = Σ λᵢ φ(‖x − xᵢ‖),  Φλ = z", "s(x) = Σ λᵢ φ(‖x − xᵢ‖),  Φλ = z", "s(x) = Σ λᵢ r²ln r + a + bx + cy", "s(x) = zᵢ del dato más cercano", "s lineal en cada triángulo de Delaunay"][sc_method]
	return "mín ‖A·c − z‖²  ⇔  AᵀA·c = Aᵀz"
func perturb_hint() -> String: return "arrastra un punto de control (Mayús: en altura)" if mode == 0 else "clic: añade un dato en ese punto"
func view() -> Dictionary: return {"target": Vector3(0, 0.4, 0), "dist": 7.0, "yaw": -30.0, "pitch": -28.0}

func setup() -> void:
	scale_xy = S
	scale_z = S
	nodes = Node3D.new()
	add_child(nodes)
	add_child(axes(2.8))
	_gen_data()
	_gen_scattered()
	_rebuild()

func _w(p: Vector3) -> Vector3:
	return to_world(p.x, p.y, p.z)

## Spline cúbico natural de una secuencia de escalares con parámetros t.
static func natural_spline(t: Array, y: Array) -> Array:
	var n := t.size()
	var h := []
	for i in range(n - 1): h.append(float(t[i + 1]) - float(t[i]))
	var alpha := [0.0]
	for i in range(1, n - 1):
		alpha.append(3.0 / h[i] * (float(y[i + 1]) - float(y[i])) - 3.0 / h[i - 1] * (float(y[i]) - float(y[i - 1])))
	var l := [1.0]
	var mu := [0.0]
	var z := [0.0]
	for i in range(1, n - 1):
		l.append(2.0 * (float(t[i + 1]) - float(t[i - 1])) - h[i - 1] * mu[i - 1])
		mu.append(h[i] / l[i])
		z.append((alpha[i] - h[i - 1] * z[i - 1]) / l[i])
	var c := []
	c.resize(n)
	c[n - 1] = 0.0
	var b := []
	b.resize(n - 1)
	var d := []
	d.resize(n - 1)
	for j in range(n - 2, -1, -1):
		c[j] = z[j] - mu[j] * c[j + 1] if j > 0 else 0.0
		b[j] = (float(y[j + 1]) - float(y[j])) / h[j] - h[j] * (c[j + 1] + 2.0 * c[j]) / 3.0
		d[j] = (c[j + 1] - c[j]) / (3.0 * h[j])
	return [b, c, d, h]

func spline_points(samples: int = 40) -> PackedVector3Array:
	var t := [0.0]
	for i in range(1, ctrl.size()):
		t.append(float(t[i - 1]) + maxf(1e-4, (ctrl[i] - ctrl[i - 1]).length()))
	var coefs := []
	for axis in range(3):
		var y := []
		for p in ctrl: y.append((p as Vector3)[axis])
		coefs.append(natural_spline(t, y))
	var out := PackedVector3Array()
	for i in range(ctrl.size() - 1):
		for s in range(samples):
			var dt := float(t[i + 1] - t[i]) * float(s) / samples
			var p := Vector3.ZERO
			for axis in range(3):
				var cf: Array = coefs[axis]
				p[axis] = (ctrl[i] as Vector3)[axis] + cf[0][i] * dt + cf[1][i] * dt * dt + cf[2][i] * dt * dt * dt
			out.append(p)
	out.append(ctrl[ctrl.size() - 1])
	return out

func catmull_points(samples: int = 40) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := ctrl.size()
	for i in range(n - 1):
		var p0: Vector3 = ctrl[maxi(0, i - 1)]
		var p1: Vector3 = ctrl[i]
		var p2: Vector3 = ctrl[i + 1]
		var p3: Vector3 = ctrl[mini(n - 1, i + 2)]
		for s in range(samples):
			var u := float(s) / samples
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u * u * u))
	out.append(ctrl[n - 1])
	return out

## B-spline cúbica uniforme con los extremos repetidos (empieza y acaba en P₀ y Pₙ).
func bspline_points(samples: int = 30) -> PackedVector3Array:
	var P := [ctrl[0], ctrl[0]] + ctrl + [ctrl[ctrl.size() - 1], ctrl[ctrl.size() - 1]]
	var out := PackedVector3Array()
	for i in range(P.size() - 3):
		for k in range(samples + (1 if i == P.size() - 4 else 0)):
			var u := float(k) / samples
			var b0 := (1.0 - u) * (1.0 - u) * (1.0 - u) / 6.0
			var b1 := (3.0 * u * u * u - 6.0 * u * u + 4.0) / 6.0
			var b2 := (-3.0 * u * u * u + 3.0 * u * u + 3.0 * u + 1.0) / 6.0
			var b3 := u * u * u / 6.0
			out.append(P[i] * b0 + P[i + 1] * b1 + P[i + 2] * b2 + P[i + 3] * b3)
	return out

## Curva de Bézier de todos los puntos de control (algoritmo de De Casteljau).
func bezier_points(samples: int = 200) -> PackedVector3Array:
	var out := PackedVector3Array()
	for k in range(samples + 1):
		var u := float(k) / samples
		var q := ctrl.duplicate()
		for r in range(1, q.size()):
			for i in range(q.size() - r):
				q[i] = (q[i] as Vector3).lerp(q[i + 1], u)
		out.append(q[0])
	return out

# --- Datos dispersos -------------------------------------------------------------------

func _gen_scattered() -> void:
	sc_data.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 + sc_n
	for i in range(sc_n):
		var x := rng.randf_range(-2.5, 2.5)
		var y := rng.randf_range(-2.0, 2.0)
		sc_data.append(Vector3(x, y, _truth(x, y)))
	_fit_scattered()

func _phi(r: float) -> float:
	match sc_method:
		1: return exp(-(sc_eps * r) * (sc_eps * r))
		2: return sqrt(1.0 + (sc_eps * r) * (sc_eps * r))
		3: return r * r * log(r) if r > 1e-12 else 0.0
	return 0.0

## Resuelve los pesos de la RBF (con término lineal en thin-plate) y la triangulación.
func _fit_scattered() -> void:
	sc_w.clear()
	var N := sc_data.size()
	if sc_method in [1, 2, 3] and N > 0:
		var extra := 3 if sc_method == 3 else 0
		var M := []
		var rhs := []
		for i in range(N + extra):
			var row := []
			row.resize(N + extra)
			row.fill(0.0)
			M.append(row)
			rhs.append(0.0)
		for i in range(N):
			var pi: Vector3 = sc_data[i]
			for j in range(N):
				var pj: Vector3 = sc_data[j]
				M[i][j] = _phi(Vector2(pi.x - pj.x, pi.y - pj.y).length())
			rhs[i] = pi.z
			if extra > 0:
				M[i][N] = 1.0
				M[i][N + 1] = pi.x
				M[i][N + 2] = pi.y
				M[N][i] = 1.0
				M[N + 1][i] = pi.x
				M[N + 2][i] = pi.y
		sc_w = _gauss(M, rhs)
	if sc_method == 5:
		var pts := PackedVector2Array()
		for q in sc_data:
			pts.append(Vector2(q.x, q.y))
		sc_tri = Geometry2D.triangulate_delaunay(pts)
	# Error frente a la función verdadera.
	var ss := 0.0
	var mx := 0.0
	var cnt := 0
	for j in range(31):
		for i in range(31):
			var x := lerpf(-2.5, 2.5, i / 30.0)
			var y := lerpf(-2.0, 2.0, j / 30.0)
			var e := absf(sc_eval(x, y) - _truth(x, y))
			ss += e * e
			mx = maxf(mx, e)
			cnt += 1
	sc_rms = sqrt(ss / cnt)
	sc_max = mx

func sc_eval(x: float, y: float) -> float:
	var N := sc_data.size()
	if N == 0:
		return 0.0
	match sc_method:
		0:
			var num := 0.0
			var den := 0.0
			for q in sc_data:
				var d := Vector2(x - q.x, y - q.y).length()
				if d < 1e-12:
					return q.z
				var w := 1.0 / pow(d, sc_p)
				num += w * q.z
				den += w
			return num / den
		1, 2, 3:
			if sc_w.size() < N:
				return 0.0
			var s := 0.0
			for i in range(N):
				var q: Vector3 = sc_data[i]
				s += float(sc_w[i]) * _phi(Vector2(x - q.x, y - q.y).length())
			if sc_method == 3 and sc_w.size() >= N + 3:
				s += float(sc_w[N]) + float(sc_w[N + 1]) * x + float(sc_w[N + 2]) * y
			return s
		5:
			var p := Vector2(x, y)
			for t in range(0, sc_tri.size(), 3):
				var a: Vector3 = sc_data[sc_tri[t]]
				var b: Vector3 = sc_data[sc_tri[t + 1]]
				var c: Vector3 = sc_data[sc_tri[t + 2]]
				var bc := _barycentric(p, Vector2(a.x, a.y), Vector2(b.x, b.y), Vector2(c.x, c.y))
				if bc.x >= -1e-9 and bc.y >= -1e-9 and bc.z >= -1e-9:
					return bc.x * a.z + bc.y * b.z + bc.z * c.z
	# Vecino más cercano (y fuera de la envolvente de Delaunay).
	var best := 0.0
	var bd := INF
	for q in sc_data:
		var d2 := Vector2(x - q.x, y - q.y).length_squared()
		if d2 < bd:
			bd = d2
			best = q.z
	return best

static func _barycentric(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> Vector3:
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var den := v0.x * v1.y - v1.x * v0.y
	if absf(den) < 1e-12:
		return Vector3(-1, -1, -1)
	var v := (v2.x * v1.y - v1.x * v2.y) / den
	var w := (v0.x * v2.y - v2.x * v0.y) / den
	return Vector3(1.0 - v - w, v, w)

# --- Mínimos cuadrados ------------------------------------------------------------

func _truth(x: float, y: float) -> float:
	return 0.6 + 0.35 * x - 0.25 * y + 0.18 * x * x - 0.12 * x * y + 0.08 * y * y

func _gen_data() -> void:
	data.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345 + npts
	for i in range(npts):
		var x := rng.randf_range(-2.5, 2.5)
		var y := rng.randf_range(-2.0, 2.0)
		data.append(Vector3(x, y, _truth(x, y) + rng.randfn(0.0, noise)))
	_fit()

func _basis(x: float, y: float) -> Array:
	return [1.0, x, y] if model == 0 else [1.0, x, y, x * x, x * y, y * y]

func _fit() -> void:
	var m := 3 if model == 0 else 6
	var ata := []
	var atz := []
	for i in range(m):
		ata.append([])
		for j in range(m): ata[i].append(0.0)
		atz.append(0.0)
	for p in data:
		var phi := _basis(p.x, p.y)
		for i in range(m):
			atz[i] += phi[i] * p.z
			for j in range(m):
				ata[i][j] += phi[i] * phi[j]
	coef = _gauss(ata, atz)
	var mean := 0.0
	for p in data: mean += p.z
	mean /= maxf(1.0, data.size())
	var ss_res := 0.0
	var ss_tot := 0.0
	for p in data:
		var e: float = p.z - model_z(p.x, p.y)
		ss_res += e * e
		ss_tot += (p.z - mean) * (p.z - mean)
	r2 = 1.0 - ss_res / maxf(1e-12, ss_tot)
	rms = sqrt(ss_res / maxf(1.0, data.size()))

static func _gauss(a: Array, b: Array) -> Array:
	var n := b.size()
	var M := []
	for i in range(n): M.append((a[i] as Array).duplicate() + [b[i]])
	for c in range(n):
		var piv := c
		for r in range(c + 1, n):
			if absf(M[r][c]) > absf(M[piv][c]): piv = r
		var tmp = M[c]; M[c] = M[piv]; M[piv] = tmp
		if absf(M[c][c]) < 1e-14:
			continue
		for r in range(n):
			if r != c:
				var f: float = M[r][c] / M[c][c]
				for k in range(c, n + 1):
					M[r][k] -= f * M[c][k]
	var x := []
	for i in range(n): x.append(M[i][n] / M[i][i] if absf(M[i][i]) > 1e-14 else 0.0)
	return x

func model_z(x: float, y: float) -> float:
	var phi := _basis(x, y)
	var z := 0.0
	for i in range(mini(phi.size(), coef.size())): z += phi[i] * coef[i]
	return z

# --- Dibujo ----------------------------------------------------------------------------

func _rebuild() -> void:
	for c in nodes.get_children():
		c.queue_free()
	if mode == 0:
		var cm := glow_mat(Color(1.0, 0.85, 0.3), 3.0)
		for i in range(ctrl.size()):
			var s := sphere(0.07 if i != sel else 0.1, cm if i != sel else glow_mat(Color(1, 1, 1), 4.0))
			s.position = _w(ctrl[i])
			nodes.add_child(s)
			nodes.add_child(rod(_w(Vector3(ctrl[i].x, ctrl[i].y, 0)), _w(ctrl[i]), 0.004, glow_mat(Color(0.5, 0.6, 0.7), 0.6)))
		var sp := PackedVector3Array()
		for q in spline_points(): sp.append(_w(q))
		nodes.add_child(tube(sp, 0.03, glow_mat(Color(1.0, 0.45, 0.1), 2.0), 10))
		if show_catmull:
			var cp := PackedVector3Array()
			for q in catmull_points(): cp.append(_w(q))
			nodes.add_child(tube(cp, 0.014, glow_mat(Color(0.2, 0.9, 1.0), 1.6), 6))
		if show_poly:
			var pp := PackedVector3Array()
			for q in ctrl: pp.append(_w(q))
			nodes.add_child(tube(pp, 0.006, glow_mat(Color(0.7, 0.7, 0.8), 0.8), 5))
		if show_bspline:
			var bp := PackedVector3Array()
			for q in bspline_points(): bp.append(_w(q))
			nodes.add_child(tube(bp, 0.016, glow_mat(Color(0.4, 1.0, 0.5), 1.8), 6))
		if show_bezier:
			var zp := PackedVector3Array()
			for q in bezier_points(): zp.append(_w(q))
			nodes.add_child(tube(zp, 0.016, glow_mat(Color(0.75, 0.5, 1.0), 1.8), 6))
	elif mode == 2:
		nodes.add_child(_surface_mesh(func(x, y): return sc_eval(x, y), 0.8))
		if show_truth:
			nodes.add_child(_wire(func(x, y): return _truth(x, y)))
		var dm := glow_mat(Color(1.0, 0.9, 0.35), 2.8)
		for q in sc_data:
			var s := sphere(0.045, dm)
			s.position = _w(q)
			nodes.add_child(s)
			nodes.add_child(rod(_w(Vector3(q.x, q.y, -0.6)), _w(q), 0.003, glow_mat(Color(0.5, 0.6, 0.7), 0.6)))
		if sc_method == 5:
			var ep := PackedVector3Array()
			for t in range(0, sc_tri.size(), 3):
				for e in [[0, 1], [1, 2], [2, 0]]:
					ep.append(_w(sc_data[sc_tri[t + e[0]]]) + Vector3(0, 0.004, 0))
					ep.append(_w(sc_data[sc_tri[t + e[1]]]) + Vector3(0, 0.004, 0))
			var im := ImmediateMesh.new()
			im.surface_begin(Mesh.PRIMITIVE_LINES)
			for q in ep:
				im.surface_add_vertex(q)
			im.surface_end()
			var li := MeshInstance3D.new()
			li.mesh = im
			li.material_override = glow_mat(Color(1.0, 1.0, 1.0), 1.5)
			nodes.add_child(li)
	else:
		# Superficie ajustada (malla con color por altura) y datos con residuos.
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n := 40
		var grid := []
		for j in range(n + 1):
			var row := []
			for i in range(n + 1):
				var x := lerpf(-2.5, 2.5, float(i) / n)
				var y := lerpf(-2.0, 2.0, float(j) / n)
				row.append(_w(Vector3(x, y, model_z(x, y))))
			grid.append(row)
		for j in range(n):
			for i in range(n):
				var a: Vector3 = grid[j][i]
				var b: Vector3 = grid[j][i + 1]
				var c: Vector3 = grid[j + 1][i + 1]
				var d: Vector3 = grid[j + 1][i]
				var nrm := (b - a).cross(d - a).normalized()
				if nrm.y < 0: nrm = -nrm
				for q in [a, b, c, a, c, d]:
					st.set_normal(nrm)
					st.set_color(Color.from_hsv(0.55 - clampf(q.y * 0.15, -0.2, 0.3), 0.7, 0.9))
					st.add_vertex(q)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = vcolor_mat(0.6, 0.4)
		nodes.add_child(mi)
		var pm := glow_mat(Color(1.0, 0.9, 0.35), 2.5)
		for p in data:
			var s := sphere(0.035, pm)
			s.position = _w(p)
			nodes.add_child(s)
			var zf := model_z(p.x, p.y)
			var err := absf(p.z - zf)
			var col := Color(0.3, 1.0, 0.5).lerp(Color(1.0, 0.25, 0.3), clampf(err / (2.5 * noise + 1e-6), 0.0, 1.0))
			nodes.add_child(rod(_w(p), _w(Vector3(p.x, p.y, zf)), 0.005, glow_mat(col, 1.4)))

## Malla de la superficie z = fn(x, y) con color por altura.
func _surface_mesh(fn: Callable, alpha: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 48
	var grid := []
	for j in range(n + 1):
		var row := []
		for i in range(n + 1):
			var x := lerpf(-2.5, 2.5, float(i) / n)
			var y := lerpf(-2.0, 2.0, float(j) / n)
			row.append(_w(Vector3(x, y, clampf(float(fn.call(x, y)), -3.0, 5.0))))
		grid.append(row)
	for j in range(n):
		for i in range(n):
			var a: Vector3 = grid[j][i]
			var b: Vector3 = grid[j][i + 1]
			var c: Vector3 = grid[j + 1][i + 1]
			var d: Vector3 = grid[j + 1][i]
			var nrm := (b - a).cross(d - a).normalized()
			if nrm.y < 0: nrm = -nrm
			for q in [a, b, c, a, c, d]:
				st.set_normal(nrm)
				st.set_color(Color.from_hsv(0.55 - clampf(q.y * 0.15, -0.2, 0.3), 0.7, 0.9))
				st.add_vertex(q)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = vcolor_mat(alpha, 0.4)
	return mi

## Malla de alambre (referencia) de z = fn(x, y).
func _wire(fn: Callable) -> MeshInstance3D:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var n := 16
	for j in range(n + 1):
		for i in range(n):
			for k in [i, i + 1]:
				var x := lerpf(-2.5, 2.5, float(k) / n)
				var y := lerpf(-2.0, 2.0, float(j) / n)
				im.surface_add_vertex(_w(Vector3(x, y, fn.call(x, y))))
	for i in range(n + 1):
		for j in range(n):
			for k in [j, j + 1]:
				var x2 := lerpf(-2.5, 2.5, float(i) / n)
				var y2 := lerpf(-2.0, 2.0, float(k) / n)
				im.surface_add_vertex(_w(Vector3(x2, y2, fn.call(x2, y2))))
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.85, 0.9, 1.0, 0.5)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	return mi

func build_ui(p: VBoxContainer) -> void:
	LabUI.option(p, "Modo:", ["Spline cúbico 3D", "Mínimos cuadrados (superficie)", "Superficie por datos dispersos"], mode, func(i):
		mode = i
		_rebuild()
		lab._update_info(false))
	LabUI.section(p, "Spline")
	LabUI.check(p, "Catmull-Rom (cian)", show_catmull, func(v):
		show_catmull = v
		_rebuild())
	LabUI.check(p, "Poligonal de control", show_poly, func(v):
		show_poly = v
		_rebuild())
	LabUI.check(p, "B-spline cúbica uniforme (verde, aproxima)", show_bspline, func(v):
		show_bspline = v
		_rebuild())
	LabUI.check(p, "Bézier de De Casteljau (violeta, aproxima)", show_bezier, func(v):
		show_bezier = v
		_rebuild())
	var r := LabUI.row(p)
	LabUI.button(r, "+ Punto", func():
		var last: Vector3 = ctrl[ctrl.size() - 1]
		ctrl.append(last + Vector3(0.6, randf_range(-0.8, 0.8), randf_range(-0.4, 0.6)))
		_rebuild())
	LabUI.button(r, "− Punto", func():
		if ctrl.size() > 3:
			ctrl.pop_back()
			_rebuild())
	LabUI.section(p, "Mínimos cuadrados")
	LabUI.option(p, "Modelo:", ["Plano  z = a + bx + cy", "Cuádrica (6 coeficientes)"], model, func(i):
		model = i
		_fit()
		_rebuild())
	LabUI.slider(p, "Ruido σ", 0.0, 1.0, 0.01, noise, func(v):
		noise = v
		_gen_data()
		_rebuild())
	LabUI.slider(p, "Número de datos", 8, 300, 1, npts, func(v):
		npts = int(v)
		_gen_data()
		_rebuild(), "%.0f")
	LabUI.section(p, "Datos dispersos")
	LabUI.option(p, "Método:", SC_METHODS, sc_method, func(i):
		sc_method = i
		_fit_scattered()
		_rebuild()
		lab._update_info(false))
	LabUI.slider(p, "Número de puntos", 4, 60, 1, sc_n, func(v):
		sc_n = int(v)
		_gen_scattered()
		_rebuild()
		lab._update_info(false), "%.0f")
	LabUI.slider(p, "Potencia p (IDW)", 0.5, 8.0, 0.1, sc_p, func(v):
		sc_p = v
		_fit_scattered()
		_rebuild()
		lab._update_info(false))
	LabUI.slider(p, "Forma ε (RBF)", 0.1, 5.0, 0.05, sc_eps, func(v):
		sc_eps = v
		_fit_scattered()
		_rebuild()
		lab._update_info(false))
	LabUI.check(p, "Superficie verdadera (alambre)", show_truth, func(v):
		show_truth = v
		_rebuild())
	LabUI.note(p, "El spline natural pasa por todos los puntos con curvatura continua; Catmull-Rom también interpola pero solo es C¹; B-spline y Bézier solo se acercan a ellos. En el ajuste, los residuos (verde → rojo) son las distancias verticales que se minimizan al cuadrado. Con datos dispersos, IDW crea «mesetas» en los datos, las RBF dan superficies suaves y Delaunay una malla de triángulos planos.")

func pick(origin: Vector3, dir: Vector3):
	if mode == 0:
		if sel >= 0:
			return ray_plane_y(origin, dir, _drag_h) if not Input.is_key_pressed(KEY_SHIFT) else _vertical_pick(origin, dir)
		var best := -1
		var bd := 0.12
		for i in range(ctrl.size()):
			var c := _w(ctrl[i])
			var t := (c - origin).dot(dir)
			var d := (origin + dir * t).distance_to(c)
			if d < bd:
				bd = d
				best = i
		if best >= 0:
			return _w(ctrl[best])
	return ray_plane_y(origin, dir, 0.0)

func _vertical_pick(origin: Vector3, dir: Vector3):
	var c := _w(ctrl[sel])
	var n := Vector3(dir.x, 0, dir.z).normalized()
	var den := n.dot(dir)
	if absf(den) < 1e-6:
		return null
	var t := (c - origin).dot(n) / den
	return origin + dir * t

func hover_text(hit: Vector3) -> String:
	var m := to_math(hit)
	if mode == 2:
		return "x = %.2f  y = %.2f\ninterpolante = %.3f\nverdadera = %.3f" % [m.x, m.y, sc_eval(m.x, m.y), _truth(m.x, m.y)]
	if mode == 1:
		return "x = %.2f  y = %.2f\nmodelo z = %.3f" % [m.x, m.y, model_z(m.x, m.y)]
	return "(%.2f, %.2f, %.2f)" % [m.x, m.y, m.z]

func perturb(hit: Vector3, first: bool) -> void:
	var m := to_math(hit)
	if mode == 2:
		if first:
			sc_data.append(Vector3(m.x, m.y, _truth(m.x, m.y)))
			_fit_scattered()
			_rebuild()
		return
	if mode == 1:
		if first:
			data.append(Vector3(m.x, m.y, _truth(m.x, m.y) + randfn(0.0, noise)))
			_fit()
			_rebuild()
		return
	if first:
		sel = -1
		for i in range(ctrl.size()):
			if _w(ctrl[i]).distance_to(hit) < 0.15:
				sel = i
				_drag_h = _w(ctrl[i]).y
		_rebuild()
		return
	if sel >= 0:
		if Input.is_key_pressed(KEY_SHIFT):
			ctrl[sel] = Vector3(ctrl[sel].x, ctrl[sel].y, m.z)
			_drag_h = _w(ctrl[sel]).y
		else:
			ctrl[sel] = Vector3(m.x, m.y, ctrl[sel].z)
		_rebuild()

func critical_points() -> Array:
	var out := []
	for i in range(ctrl.size()):
		out.append({"pos": _w(ctrl[i]), "nombre": "Punto de control P%d" % i, "dist": 2.5})
	return out

func info() -> String:
	if mode == 2:
		return "%s · %d datos\nError frente a la superficie verdadera: RMS = [color=#ffcc55]%s[/color] · máx = %s" % [SC_METHODS[sc_method], sc_data.size(), LabUI.sci(sc_rms, 2), LabUI.sci(sc_max, 2)]
	if mode == 0:
		var L := 0.0
		var sp := spline_points()
		for i in range(sp.size() - 1): L += sp[i].distance_to(sp[i + 1])
		return "%d puntos de control · longitud del spline = %.3f\nC² continuo: posición, tangente y curvatura sin saltos" % [ctrl.size(), L]
	var names := ["a", "b (x)", "c (y)", "d (x²)", "e (xy)", "f (y²)"]
	var cs := []
	for i in range(coef.size()): cs.append("%s = %+.3f" % [names[i], coef[i]])
	return "%s\nR² = [color=#ffcc55]%.4f[/color] · error RMS = %.4f · %d datos" % [" · ".join(PackedStringArray(cs)), r2, rms, data.size()]

func demo(extra: Array) -> void:
	if "dispersos" in extra:
		mode = 2
		_rebuild()
	elif "ajuste" in extra:
		mode = 1
		_rebuild()
	elif "curvas" in extra:
		show_bspline = true
		show_bezier = true
		_rebuild()
