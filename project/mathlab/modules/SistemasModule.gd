extends LabModule
## Sistemas de ecuaciones lineales 3×3 como intersección de tres planos.
## Jacobi y Gauss-Seidel dibujan su trayectoria de iterados hacia la solución,
## con el vector residuo r = b − A·x en cada paso. El radio espectral de la
## matriz de iteración predice si converge (ρ < 1) y a qué ritmo.

const S := 0.5            # escala: unidad matemática → mundo
const BOX := 4.0          # semilado del cubo de dibujo (unidades matemáticas)
const PRESETS := {
	"Diagonal dominante (converge)": [[[4, -1, 1], [-2, 6, 1], [1, 1, 5]], [7, 9, -6]],
	"Sin dominancia (Jacobi diverge)": [[[1, 2, -1], [2, 1, 1], [1, 1, 1]], [2, 3, 1]],
	"Mal condicionado (planos casi paralelos)": [[[3, 1, 1], [3, 1.05, 1], [1, 2, 4]], [5, 5.1, 3]],
	"Simétrica definida positiva": [[[5, 1, 0], [1, 4, 1], [0, 1, 3]], [6, 1, -2]],
}

var A: Array = [[4.0, -1.0, 1.0], [-2.0, 6.0, 1.0], [1.0, 1.0, 5.0]]
var b: Array = [7.0, 9.0, -6.0]
var start := Vector3.ZERO
var n_iter: int = 12
var show_jacobi: bool = true
var show_gs: bool = true
var sol: Variant = null
var jac: Array = []
var gs: Array = []
var planes_node: Node3D
var paths_node: Node3D
var _spins: Array = []
var _anim: int = 999
var _anim_t: float = 0.0

func title() -> String: return "Sistemas de ecuaciones"
func formula() -> String: return "A·x = b   ·   Jacobi: xᵏ⁺¹ = D⁻¹(b − (L+U)xᵏ)   ·   G-S: (D+L)xᵏ⁺¹ = b − U·xᵏ"
func uses_time() -> bool: return true
func perturb_hint() -> String: return "clic sobre el plano horizontal (z = 0): nuevo punto de partida x⁰"
const LIFT := 0.7
func view() -> Dictionary: return {"target": Vector3(0, LIFT, 0), "dist": 8.0, "yaw": -40.0, "pitch": -26.0}

func setup() -> void:
	scale_xy = S
	scale_z = S
	position = Vector3(0, LIFT, 0)
	planes_node = Node3D.new()
	add_child(planes_node)
	paths_node = Node3D.new()
	add_child(paths_node)
	add_child(axes(BOX * S * 0.9))
	_rebuild()

func _v(p: Vector3) -> Vector3:
	return to_world(p.x, p.y, p.z)

func _solve() -> Variant:
	var M := [A[0].duplicate(), A[1].duplicate(), A[2].duplicate()]
	var r := b.duplicate()
	for i in range(3):
		M[i] = M[i].duplicate()
	for c in range(3):
		var piv := c
		for k in range(c + 1, 3):
			if absf(M[k][c]) > absf(M[piv][c]): piv = k
		if absf(M[piv][c]) < 1e-12:
			return null
		var tmp = M[c]; M[c] = M[piv]; M[piv] = tmp
		var tb = r[c]; r[c] = r[piv]; r[piv] = tb
		for k in range(c + 1, 3):
			var f: float = M[k][c] / M[c][c]
			for j in range(c, 3):
				M[k][j] -= f * M[c][j]
			r[k] -= f * r[c]
	var x := [0.0, 0.0, 0.0]
	for i in range(2, -1, -1):
		var s: float = r[i]
		for j in range(i + 1, 3):
			s -= M[i][j] * x[j]
		x[i] = s / M[i][i]
	return Vector3(x[0], x[1], x[2])

func _iterate(gauss_seidel: bool) -> Array:
	var out := [start]
	var x := [start.x, start.y, start.z]
	for k in range(n_iter):
		var xn := x.duplicate()
		for i in range(3):
			if absf(A[i][i]) < 1e-12:
				return out
			var s: float = b[i]
			for j in range(3):
				if j != i:
					s -= A[i][j] * (xn[j] if gauss_seidel else x[j])
			xn[i] = s / A[i][i]
		x = xn
		var v := Vector3(x[0], x[1], x[2])
		if not v.is_finite() or v.length() > 1e6:
			break
		out.append(v)
	return out

func residual(x: Vector3) -> Vector3:
	var r := Vector3.ZERO
	for i in range(3):
		r[i] = b[i] - (A[i][0] * x.x + A[i][1] * x.y + A[i][2] * x.z)
	return r

## Radio espectral estimado ‖Tᵏ‖^(1/k) de la matriz de iteración.
func spectral_radius(gauss_seidel: bool) -> float:
	var T := []
	for i in range(3):
		T.append([0.0, 0.0, 0.0])
	# Columnas de T = matriz de iteración aplicada a e₁, e₂, e₃ con b = 0.
	for c in range(3):
		var x := [0.0, 0.0, 0.0]
		x[c] = 1.0
		var xn := x.duplicate()
		for i in range(3):
			var s := 0.0
			for j in range(3):
				if j != i:
					s -= A[i][j] * (xn[j] if gauss_seidel else x[j])
			xn[i] = s / A[i][i] if absf(A[i][i]) > 1e-12 else 0.0
		for i in range(3):
			T[i][c] = xn[i]
	var v := Vector3(0.577, 0.577, 0.577)
	var k := 60
	var acc := 0.0
	for it in range(k):
		var w := Vector3.ZERO
		for i in range(3):
			w[i] = T[i][0] * v.x + T[i][1] * v.y + T[i][2] * v.z
		var nrm := w.length()
		if nrm < 1e-300:
			return 0.0
		acc += log(nrm)
		v = w / nrm
	return exp(acc / k)

func _plane_polygon(n: Vector3, d: float) -> PackedVector3Array:
	# Intersección del plano n·x = d con el cubo [−BOX, BOX]³.
	var pts := PackedVector3Array()
	var corners := []
	for i in range(8):
		corners.append(Vector3(BOX if i & 1 else -BOX, BOX if i & 2 else -BOX, BOX if i & 4 else -BOX))
	var edges := [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]
	for e in edges:
		var p0: Vector3 = corners[e[0]]
		var p1: Vector3 = corners[e[1]]
		var d0 := n.dot(p0) - d
		var d1 := n.dot(p1) - d
		if d0 * d1 <= 0.0 and absf(d0 - d1) > 1e-12:
			pts.append(p0.lerp(p1, d0 / (d0 - d1)))
	if pts.size() < 3:
		return pts
	var c := Vector3.ZERO
	for p in pts: c += p
	c /= pts.size()
	var u := (pts[0] - c).normalized()
	var w := n.normalized().cross(u)
	var arr := Array(pts)
	arr.sort_custom(func(a, bb): return atan2((a - c).dot(w), (a - c).dot(u)) < atan2((bb - c).dot(w), (bb - c).dot(u)))
	return PackedVector3Array(arr)

func _rebuild() -> void:
	for c in planes_node.get_children():
		c.queue_free()
	var cols := [Color(1.0, 0.35, 0.3), Color(0.35, 1.0, 0.45), Color(0.35, 0.6, 1.0)]
	for i in range(3):
		var n := Vector3(A[i][0], A[i][1], A[i][2])
		if n.length() < 1e-9:
			continue
		var poly := _plane_polygon(n, b[i])
		if poly.size() < 3:
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var nw := _v(n).normalized()
		for k in range(1, poly.size() - 1):
			for q in [poly[0], poly[k], poly[k + 1]]:
				st.set_normal(nw)
				st.add_vertex(_v(q))
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = glass_mat(cols[i], 0.22)
		planes_node.add_child(mi)
		var outline := poly.duplicate()
		outline.append(poly[0])
		var ow := PackedVector3Array()
		for q in outline: ow.append(_v(q))
		planes_node.add_child(tube(ow, 0.006, glow_mat(cols[i], 1.2), 5))
		planes_node.add_child(label3d("%s₍%d₎" % ["π", i + 1], _v(poly[0]), cols[i], 0.003))
	# Rectas de intersección de cada par de planos.
	for pr in [[0, 1], [0, 2], [1, 2]]:
		var n1 := Vector3(A[pr[0]][0], A[pr[0]][1], A[pr[0]][2])
		var n2 := Vector3(A[pr[1]][0], A[pr[1]][1], A[pr[1]][2])
		var dir := n1.cross(n2)
		if dir.length() < 1e-9:
			continue
		var p0 := (n2.cross(dir) * float(b[pr[0]]) + dir.cross(n1) * float(b[pr[1]])) / dir.length_squared()
		var dn := dir.normalized()
		planes_node.add_child(rod(_v(p0 - dn * BOX * 1.6), _v(p0 + dn * BOX * 1.6), 0.008, glow_mat(Color(0.95, 0.95, 1.0), 1.0)))
	sol = _solve()
	if sol != null:
		var s := sphere(0.07, glow_mat(Color(1.0, 1.0, 1.0), 4.0))
		s.position = _v(sol)
		planes_node.add_child(s)
		planes_node.add_child(label3d("x* = (%.3f, %.3f, %.3f)" % [sol.x, sol.y, sol.z], _v(sol) + Vector3(0, 0.25, 0), Color(1, 1, 1), 0.0032))
	jac = _iterate(false)
	gs = _iterate(true)
	_anim = 999
	_draw_paths(999)

func _draw_paths(upto: int) -> void:
	for c in paths_node.get_children():
		c.queue_free()
	var sets := []
	if show_jacobi: sets.append([jac, Color(1.0, 0.6, 0.15), "Jacobi"])
	if show_gs: sets.append([gs, Color(0.2, 0.9, 1.0), "Gauss-Seidel"])
	for st in sets:
		var path: Array = st[0]
		var col: Color = st[1]
		var m := glow_mat(col, 2.2)
		var pts := PackedVector3Array()
		var last := mini(path.size(), upto + 1)
		for i in range(last):
			var p: Vector3 = path[i]
			if absf(p.x) > BOX * 3 or absf(p.y) > BOX * 3 or absf(p.z) > BOX * 3:
				break
			pts.append(_v(p))
			var s := sphere(0.035, m)
			s.position = _v(p)
			paths_node.add_child(s)
		if pts.size() >= 2:
			paths_node.add_child(tube(pts, 0.012, m, 6))
		if last >= 1:
			var cur: Vector3 = path[last - 1]
			var r := residual(cur)
			var scale := minf(1.0, 1.5 / maxf(r.length(), 1e-9))
			if r.length() > 1e-6:
				paths_node.add_child(arrow(_v(cur), _v(cur + r * scale), 0.01, glow_mat(Color(1.0, 0.25, 0.6), 2.0)))

func step(dt: float) -> void:
	if _anim >= n_iter:
		return
	_anim_t += dt
	if _anim_t > 0.45:
		_anim_t = 0.0
		_anim += 1
		_draw_paths(_anim)

func reset() -> void:
	_anim = 0
	_draw_paths(0)

func build_ui(p: VBoxContainer) -> void:
	LabUI.option(p, "Ejemplo:", PRESETS.keys(), 0, func(i):
		var pr = PRESETS.values()[i]
		for r in range(3):
			for c in range(3):
				A[r][c] = float(pr[0][r][c])
			b[r] = float(pr[1][r])
		_sync_spins()
		_rebuild())
	LabUI.section(p, "Matriz A | b")
	_spins.clear()
	for r in range(3):
		var row := LabUI.row(p)
		for c in range(4):
			var s := SpinBox.new()
			s.min_value = -20
			s.max_value = 20
			s.step = 0.05
			s.custom_minimum_size = Vector2(62, 0)
			s.value = A[r][c] if c < 3 else b[r]
			var rr := r
			var cc := c
			s.value_changed.connect(func(v):
				if cc < 3: A[rr][cc] = v
				else: b[rr] = v
				_rebuild())
			row.add_child(s)
			_spins.append(s)
	LabUI.slider(p, "Iteraciones", 1, 40, 1, n_iter, func(v):
		n_iter = int(v)
		_rebuild(), "%.0f")
	LabUI.check(p, "Jacobi (naranja)", show_jacobi, func(v):
		show_jacobi = v
		_draw_paths(999))
	LabUI.check(p, "Gauss-Seidel (cian)", show_gs, func(v):
		show_gs = v
		_draw_paths(999))
	LabUI.button(p, "▶ Animar iteraciones", reset)
	LabUI.note(p, "El vector magenta es el residuo r = b − A·xᵏ del último iterado. Gauss-Seidel usa en cada ecuación los valores recién calculados: suele converger unas dos veces más rápido que Jacobi (ρ_GS ≈ ρ_J² en matrices consistentes).")

func _sync_spins() -> void:
	for r in range(3):
		for c in range(4):
			(_spins[r * 4 + c] as SpinBox).set_value_no_signal(A[r][c] if c < 3 else b[r])

func pick(origin: Vector3, dir: Vector3):
	return ray_plane_y(origin, dir, LIFT)

func hover_text(hit: Vector3) -> String:
	var m := to_math(to_local(hit))
	var r := residual(m)
	return "(x, y, z) = (%.2f, %.2f, %.2f)\n‖b − A·x‖ = %.3f" % [m.x, m.y, m.z, r.length()]

func perturb(hit: Vector3, first: bool) -> void:
	if first:
		start = to_math(to_local(hit))
		_rebuild()
		reset()

func critical_points() -> Array:
	var out := []
	if sol != null:
		out.append({"pos": to_global(_v(sol)), "nombre": "Solución x*", "dist": 3.0})
	out.append({"pos": to_global(_v(start)), "nombre": "Punto de partida x⁰", "dist": 3.5})
	return out

func info() -> String:
	var rj := spectral_radius(false)
	var rg := spectral_radius(true)
	var t := ""
	if sol != null:
		t += "x* = (%.4f, %.4f, %.4f)\n" % [sol.x, sol.y, sol.z]
	else:
		t += "[color=#ff7766]A es singular: no hay solución única.[/color]\n"
	t += "ρ(T_Jacobi) = %.3f %s   ·   ρ(T_GS) = %.3f %s\n" % [rj, "✔" if rj < 1.0 else "✖ diverge", rg, "✔" if rg < 1.0 else "✖ diverge"]
	if not jac.is_empty():
		t += "‖r‖ tras %d iter.: Jacobi %s · G-S %s" % [n_iter, LabUI.sci(residual(jac[jac.size() - 1]).length(), 2), LabUI.sci(residual(gs[gs.size() - 1]).length(), 2)]
	return t
