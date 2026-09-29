extends LabModule
## Sistemas de ecuaciones lineales 3×3 como intersección de tres planos.
##   · Iterativos: Jacobi, Gauss-Seidel, SOR (con ω óptimo), Richardson, descenso
##     más pronunciado y gradiente conjugado. Dibujan su trayectoria de iterados
##     y el vector residuo r = b − A·x, con la gráfica de log‖r‖. El radio
##     espectral de la matriz de iteración predice si converge y a qué ritmo.
##   · Directos: eliminación gaussiana paso a paso con interpretación geométrica
##     (cada paso sustituye un plano por otro que pasa por la misma solución, hasta
##     x = c₁, y = c₂, z = c₃), factorización LU con pivoteo, Cholesky, QR y regla
##     de Cramer, con el determinante y el número de condición.

const S := 0.5            # escala: unidad matemática → mundo
const BOX := 4.0          # semilado del cubo de dibujo (unidades matemáticas)
const PRESETS := {
	"Diagonal dominante (converge)": [[[4, -1, 1], [-2, 6, 1], [1, 1, 5]], [7, 9, -6]],
	"Sin dominancia (Jacobi diverge)": [[[1, 2, -1], [2, 1, 1], [1, 1, 1]], [2, 3, 1]],
	"Mal condicionado (planos casi paralelos)": [[[3, 1, 1], [3, 1.05, 1], [1, 2, 4]], [5, 5.1, 3]],
	"Simétrica definida positiva": [[[5, 1, 0], [1, 4, 1], [0, 1, 3]], [6, 1, -2]],
	"SPD alargada (gradiente conjugado frente a descenso)": [[[10, 2, 0], [2, 3, 1], [0, 1, 1]], [12, 4, -1]],
}
const ITER := ["Jacobi", "Gauss-Seidel", "SOR", "Richardson", "Descenso más pronunciado", "Gradiente conjugado"]
const ITER_COLORS := [Color(1.0, 0.6, 0.15), Color(0.2, 0.9, 1.0), Color(1.0, 0.4, 0.85), Color(0.8, 1.0, 0.3), Color(1.0, 0.35, 0.3), Color(0.4, 1.0, 0.6)]
const DIRECT := ["Eliminación gaussiana (paso a paso)", "Factorización LU con pivoteo (PA = LU)", "Cholesky (A = LLᵀ)", "QR (Gram–Schmidt modificado)", "Regla de Cramer"]
const ELIM_TEXT := [
	"Sistema original",
	"Paso 1: pivote de máximo |aᵢ₁| y se anula x en las filas 2 y 3",
	"Paso 2: se anula y en la fila 3 → matriz triangular superior",
	"Sustitución regresiva: se anula z en las filas 1 y 2",
	"Se anula y en la fila 1 → matriz diagonal",
	"Se normaliza: los planos son x = x₁*, y = x₂*, z = x₃* (Gauss-Jordan)",
]

var A: Array = [[4.0, -1.0, 1.0], [-2.0, 6.0, 1.0], [1.0, 1.0, 5.0]]
var b: Array = [7.0, 9.0, -6.0]
var start := Vector3.ZERO
var n_iter: int = 12
var shown: Array = [true, true, true, false, false, true]
var omega: float = 1.2
var sol: Variant = null
var paths: Array = []          # trayectoria de cada método iterativo (Vector3, para dibujar)
var res_hist: Array = []       # ‖r‖ de cada iterado, en doble precisión
var jac: Array = []
var gs: Array = []
var direct: int = 0
var elim_step: int = 0
var elim_states: Array = []    # [[A, b], …] de la eliminación de Gauss-Jordan
var planes_node: Node3D
var paths_node: Node3D
var res_plot: Control
var _spins: Array = []
var _anim: int = 999
var _anim_t: float = 0.0
var _omega_slider: HSlider

# Compatibilidad con las casillas originales.
var show_jacobi: bool:
	get: return shown[0]
	set(v): shown[0] = v
var show_gs: bool:
	get: return shown[1]
	set(v): shown[1] = v

func title() -> String: return "Sistemas de ecuaciones"
func formula() -> String: return "A·x = b   ·   Jacobi: xᵏ⁺¹ = D⁻¹(b − (L+U)xᵏ)   ·   SOR: xᵏ⁺¹ = (1−ω)xᵏ + ω·x_GS   ·   CG: dirección A-conjugada"
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

static func _copy(M: Array) -> Array:
	var out := []
	for row in M:
		out.append((row as Array).duplicate())
	return out

func _solve() -> Variant:
	var M := _copy(A)
	var r := b.duplicate()
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

func _mul(M: Array, x: Vector3) -> Vector3:
	var r := Vector3.ZERO
	for i in range(3):
		r[i] = M[i][0] * x.x + M[i][1] * x.y + M[i][2] * x.z
	return r

func residual(x: Vector3) -> Vector3:
	return Vector3(b[0], b[1], b[2]) - _mul(A, x)

func is_symmetric() -> bool:
	for i in range(3):
		for j in range(3):
			if absf(float(A[i][j]) - float(A[j][i])) > 1e-12:
				return false
	return true

## Parámetro de Richardson: 2/(λmín + λmáx) si A es SPD; si no, 1/‖A‖∞.
func richardson_alpha() -> float:
	if is_symmetric() and cholesky() != null:
		var ev := sym_eigenvalues(A)
		return 2.0 / (float(ev[0]) + float(ev[2]))
	var nrm := 0.0
	for i in range(3):
		nrm = maxf(nrm, absf(A[i][0]) + absf(A[i][1]) + absf(A[i][2]))
	return 1.0 / maxf(nrm, 1e-12)

## Un paso de un método estacionario (0 Jacobi, 1 Gauss-Seidel, 2 SOR, 3 Richardson).
func _iter_step(meth: int, x: Array, bb: Array) -> Array:
	var xn := x.duplicate()
	if meth == 3:
		var alpha := richardson_alpha()
		for i in range(3):
			var ax: float = A[i][0] * x[0] + A[i][1] * x[1] + A[i][2] * x[2]
			xn[i] = x[i] + alpha * (bb[i] - ax)
		return xn
	for i in range(3):
		if absf(A[i][i]) < 1e-12:
			return []
		var s: float = bb[i]
		for j in range(3):
			if j != i:
				s -= A[i][j] * (x[j] if meth == 0 else xn[j])
		var gsv: float = s / A[i][i]
		xn[i] = (1.0 - omega) * x[i] + omega * gsv if meth == 2 else gsv
	return xn

static func _mv(M: Array, x: Array) -> Array:
	return [M[0][0] * x[0] + M[0][1] * x[1] + M[0][2] * x[2], M[1][0] * x[0] + M[1][1] * x[1] + M[1][2] * x[2], M[2][0] * x[0] + M[2][1] * x[1] + M[2][2] * x[2]]

static func _dot(u: Array, v: Array) -> float:
	return float(u[0]) * float(v[0]) + float(u[1]) * float(v[1]) + float(u[2]) * float(v[2])

static func _axpy(u: Array, s: float, v: Array) -> Array:
	return [float(u[0]) + s * float(v[0]), float(u[1]) + s * float(v[1]), float(u[2]) + s * float(v[2])]

## ‖b − A·x‖ en doble precisión (Vector3 es de precisión simple).
func res_norm(x: Array) -> float:
	var r := _axpy(b, -1.0, _mv(A, x))
	return sqrt(_dot(r, r))

## Devuelve [trayectoria (Vector3), ‖r‖ de cada iterado].
func _iterate_stationary(meth: int) -> Array:
	var out := [start]
	var x := [float(start.x), float(start.y), float(start.z)]
	var res := [res_norm(x)]
	for k in range(n_iter):
		x = _iter_step(meth, x, b)
		if x.is_empty():
			break
		var v := Vector3(x[0], x[1], x[2])
		if not v.is_finite() or v.length() > 1e6:
			break
		out.append(v)
		res.append(res_norm(x))
	return [out, res]

## Descenso más pronunciado y gradiente conjugado sobre A (si es simétrica) o
## sobre las ecuaciones normales AᵀA·x = Aᵀb.
func _iterate_krylov(cg: bool) -> Array:
	var M := A
	var rhs := b.duplicate()
	if not is_symmetric():
		var At := [[A[0][0], A[1][0], A[2][0]], [A[0][1], A[1][1], A[2][1]], [A[0][2], A[1][2], A[2][2]]]
		M = []
		for i in range(3):
			var row := []
			for j in range(3):
				row.append(At[i][0] * A[0][j] + At[i][1] * A[1][j] + At[i][2] * A[2][j])
			M.append(row)
		rhs = _mv(At, rhs)
	var out := [start]
	var x := [float(start.x), float(start.y), float(start.z)]
	var res := [res_norm(x)]
	var r := _axpy(rhs, -1.0, _mv(M, x))
	var d := r.duplicate()
	for k in range(n_iter):
		var rr := _dot(r, r)
		if sqrt(rr) < 1e-14:
			break
		var Md := _mv(M, d)
		var den := _dot(d, Md)
		if absf(den) < 1e-300:
			break
		var alpha := rr / den if cg else rr / _dot(r, _mv(M, r))
		x = _axpy(x, alpha, d if cg else r)
		var rn := _axpy(rhs, -1.0, _mv(M, x))
		if cg:
			d = _axpy(rn, _dot(rn, rn) / maxf(rr, 1e-300), d)
		r = rn
		var v := Vector3(x[0], x[1], x[2])
		if not v.is_finite():
			break
		out.append(v)
		res.append(res_norm(x))
	return [out, res]

## Radio espectral estimado ‖Tᵏ‖^(1/k) de la matriz de iteración del método.
func spectral_radius_of(meth: int) -> float:
	var T := []
	for i in range(3):
		T.append([0.0, 0.0, 0.0])
	for c in range(3):
		var e := [0.0, 0.0, 0.0]
		e[c] = 1.0
		var col := _iter_step(meth, e, [0.0, 0.0, 0.0])
		if col.is_empty():
			return INF
		for i in range(3):
			T[i][c] = col[i]
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

func spectral_radius(gauss_seidel: bool) -> float:
	return spectral_radius_of(1 if gauss_seidel else 0)

## ω óptimo de SOR para matrices consistentemente ordenadas: 2/(1 + √(1 − ρ_J²)).
func omega_opt() -> float:
	var rj := spectral_radius(false)
	if rj >= 1.0:
		return NAN
	return 2.0 / (1.0 + sqrt(1.0 - rj * rj))

# --- Métodos directos ------------------------------------------------------------------

func det3(M: Array) -> float:
	return M[0][0] * (M[1][1] * M[2][2] - M[1][2] * M[2][1]) - M[0][1] * (M[1][0] * M[2][2] - M[1][2] * M[2][0]) + M[0][2] * (M[1][0] * M[2][1] - M[1][1] * M[2][0])

## Estados de la eliminación de Gauss con pivoteo parcial seguida de la fase de Jordan.
func _elimination() -> Array:
	var M := _copy(A)
	var r := b.duplicate()
	var states := [[_copy(M), r.duplicate()]]
	for col in range(2):
		var piv := col
		for k in range(col + 1, 3):
			if absf(M[k][col]) > absf(M[piv][col]): piv = k
		if absf(M[piv][col]) < 1e-12:
			return states
		var tmp = M[col]; M[col] = M[piv]; M[piv] = tmp
		var tb = r[col]; r[col] = r[piv]; r[piv] = tb
		for k in range(col + 1, 3):
			var f: float = M[k][col] / M[col][col]
			for j in range(3):
				M[k][j] -= f * M[col][j]
			r[k] -= f * r[col]
		states.append([_copy(M), r.duplicate()])
	if absf(M[2][2]) < 1e-12:
		return states
	for col in [2, 1]:
		for k in range(col):
			var f2: float = M[k][col] / M[col][col]
			for j in range(3):
				M[k][j] -= f2 * M[col][j]
			r[k] -= f2 * r[col]
		states.append([_copy(M), r.duplicate()])
	for i in range(3):
		var dg: float = M[i][i]
		for j in range(3):
			M[i][j] /= dg
		r[i] /= dg
	states.append([_copy(M), r.duplicate()])
	return states

## PA = LU (Doolittle con pivoteo parcial): [P (orden de filas), L, U] o null.
func lu() -> Variant:
	var U := _copy(A)
	var L := [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
	var P := [0, 1, 2]
	for c in range(3):
		var piv := c
		for k in range(c + 1, 3):
			if absf(U[k][c]) > absf(U[piv][c]): piv = k
		if absf(U[piv][c]) < 1e-12:
			return null
		if piv != c:
			var t = U[c]; U[c] = U[piv]; U[piv] = t
			var tp = P[c]; P[c] = P[piv]; P[piv] = tp
			for j in range(c):
				var tl = L[c][j]; L[c][j] = L[piv][j]; L[piv][j] = tl
		for k in range(c + 1, 3):
			var f: float = U[k][c] / U[c][c]
			L[k][c] = f
			for j in range(3):
				U[k][j] -= f * U[c][j]
	return [P, L, U]

## A = LLᵀ si A es simétrica definida positiva; si no, null.
func cholesky() -> Variant:
	if not is_symmetric():
		return null
	var L := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	for i in range(3):
		for j in range(i + 1):
			var s: float = A[i][j]
			for k in range(j):
				s -= L[i][k] * L[j][k]
			if i == j:
				if s <= 0.0:
					return null
				L[i][i] = sqrt(s)
			else:
				L[i][j] = s / L[j][j]
	return L

## A = QR por Gram–Schmidt modificado: [Q, R] o null.
func qr() -> Variant:
	var R := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	var Q := []
	for j in range(3):
		var v := [float(A[0][j]), float(A[1][j]), float(A[2][j])]
		for i in range(j):
			R[i][j] = _dot(Q[i], v)
			v = _axpy(v, -float(R[i][j]), Q[i])
		R[j][j] = sqrt(_dot(v, v))
		if R[j][j] < 1e-12:
			return null
		Q.append([float(v[0]) / R[j][j], float(v[1]) / R[j][j], float(v[2]) / R[j][j]])
	var Qm := []
	for i in range(3):
		Qm.append([Q[0][i], Q[1][i], Q[2][i]])
	return [Qm, R]

## Autovalores de una matriz simétrica 3×3 (método de Jacobi), ordenados.
static func sym_eigenvalues(M0: Array) -> Array:
	var M := _copy(M0)
	for sweep in range(50):
		var off := 0.0
		for p in range(3):
			for q in range(p + 1, 3):
				off += M[p][q] * M[p][q]
		if off < 1e-24:
			break
		for p in range(3):
			for q in range(p + 1, 3):
				if absf(M[p][q]) < 1e-300:
					continue
				var th: float = (M[q][q] - M[p][p]) / (2.0 * M[p][q])
				var t := signf(th) / (absf(th) + sqrt(th * th + 1.0)) if th != 0.0 else 1.0
				var c := 1.0 / sqrt(t * t + 1.0)
				var s := t * c
				for k in range(3):
					var mkp: float = M[k][p]
					var mkq: float = M[k][q]
					M[k][p] = c * mkp - s * mkq
					M[k][q] = s * mkp + c * mkq
				for k in range(3):
					var mpk: float = M[p][k]
					var mqk: float = M[q][k]
					M[p][k] = c * mpk - s * mqk
					M[q][k] = s * mpk + c * mqk
	var ev := [M[0][0], M[1][1], M[2][2]]
	ev.sort()
	return ev

## Número de condición κ∞(A) = ‖A‖∞·‖A⁻¹‖∞.
func condition() -> float:
	var d := det3(A)
	if absf(d) < 1e-300:
		return INF
	var inv := []
	for i in range(3):
		inv.append([0.0, 0.0, 0.0])
	for i in range(3):
		for j in range(3):
			var m := []
			for r in range(3):
				if r == j:
					continue
				var row := []
				for c in range(3):
					if c != i:
						row.append(A[r][c])
				m.append(row)
			var cof: float = (m[0][0] * m[1][1] - m[0][1] * m[1][0]) * (1.0 if (i + j) % 2 == 0 else -1.0)
			inv[i][j] = cof / d
	var na := 0.0
	var ni := 0.0
	for i in range(3):
		na = maxf(na, absf(A[i][0]) + absf(A[i][1]) + absf(A[i][2]))
		ni = maxf(ni, absf(inv[i][0]) + absf(inv[i][1]) + absf(inv[i][2]))
	return na * ni

# --- Dibujo ----------------------------------------------------------------------------

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
	elim_states = _elimination()
	elim_step = clampi(elim_step, 0, elim_states.size() - 1)
	_draw_planes()
	sol = _solve()
	if sol != null:
		var s := sphere(0.07, glow_mat(Color(1.0, 1.0, 1.0), 4.0))
		s.position = _v(sol)
		planes_node.add_child(s)
		planes_node.add_child(label3d("x* = (%.3f, %.3f, %.3f)" % [sol.x, sol.y, sol.z], _v(sol) + Vector3(0, 0.25, 0), Color(1, 1, 1), 0.0032))
	paths.clear()
	res_hist.clear()
	var runs := []
	for m in range(4):
		runs.append(_iterate_stationary(m))
	runs.append(_iterate_krylov(false))
	runs.append(_iterate_krylov(true))
	for rn in runs:
		paths.append(rn[0])
		res_hist.append(rn[1])
	jac = paths[0]
	gs = paths[1]
	_anim = 999
	_draw_paths(999)

func _draw_planes() -> void:
	for c in planes_node.get_children():
		c.queue_free()
	var st_: Array = elim_states[elim_step] if not elim_states.is_empty() else [A, b]
	var MA: Array = st_[0]
	var MB: Array = st_[1]
	var cols := [Color(1.0, 0.35, 0.3), Color(0.35, 1.0, 0.45), Color(0.35, 0.6, 1.0)]
	for i in range(3):
		var n := Vector3(MA[i][0], MA[i][1], MA[i][2])
		if n.length() < 1e-9:
			continue
		var poly := _plane_polygon(n, MB[i])
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
		planes_node.add_child(label3d("π%s%s" % [["₁", "₂", "₃"][i], "′" if elim_step > 0 else ""], _v(poly[0]), cols[i], 0.003))
	# Rectas de intersección de cada par de planos.
	for pr in [[0, 1], [0, 2], [1, 2]]:
		var n1 := Vector3(MA[pr[0]][0], MA[pr[0]][1], MA[pr[0]][2])
		var n2 := Vector3(MA[pr[1]][0], MA[pr[1]][1], MA[pr[1]][2])
		var dir := n1.cross(n2)
		if dir.length() < 1e-9:
			continue
		var p0 := (n2.cross(dir) * float(MB[pr[0]]) + dir.cross(n1) * float(MB[pr[1]])) / dir.length_squared()
		var dn := dir.normalized()
		planes_node.add_child(rod(_v(p0 - dn * BOX * 1.6), _v(p0 + dn * BOX * 1.6), 0.008, glow_mat(Color(0.95, 0.95, 1.0), 1.0)))

func set_elim_step(k: int) -> void:
	elim_step = clampi(k, 0, maxi(0, elim_states.size() - 1))
	_draw_planes()
	if sol != null:
		var s := sphere(0.07, glow_mat(Color(1.0, 1.0, 1.0), 4.0))
		s.position = _v(sol)
		planes_node.add_child(s)

func _draw_paths(upto: int) -> void:
	for c in paths_node.get_children():
		c.queue_free()
	for m in range(ITER.size()):
		if not shown[m] or m >= paths.size():
			continue
		var path: Array = paths[m]
		var col: Color = ITER_COLORS[m]
		var mat := glow_mat(col, 2.2)
		var pts := PackedVector3Array()
		var last := mini(path.size(), upto + 1)
		for i in range(last):
			var p: Vector3 = path[i]
			if absf(p.x) > BOX * 3 or absf(p.y) > BOX * 3 or absf(p.z) > BOX * 3:
				break
			pts.append(_v(p))
			var s := sphere(0.035, mat)
			s.position = _v(p)
			paths_node.add_child(s)
		if pts.size() >= 2:
			paths_node.add_child(tube(pts, 0.012, mat, 6))
		if last >= 1:
			var cur: Vector3 = path[last - 1]
			var r := residual(cur)
			var scale := minf(1.0, 1.5 / maxf(r.length(), 1e-9))
			if r.length() > 1e-6:
				paths_node.add_child(arrow(_v(cur), _v(cur + r * scale), 0.01, glow_mat(Color(1.0, 0.25, 0.6), 2.0)))
	if res_plot:
		res_plot.queue_redraw()

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
		_rebuild()
		lab._update_info(false))
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
			s.set_meta("lab_param", ("A%d%d" % [r + 1, c + 1]) if c < 3 else ("b%d" % (r + 1)))
			var rr := r
			var cc := c
			s.value_changed.connect(func(v):
				if cc < 3: A[rr][cc] = v
				else: b[rr] = v
				_rebuild())
			row.add_child(s)
			_spins.append(s)
	LabUI.section(p, "Métodos iterativos")
	LabUI.slider(p, "Iteraciones", 1, 40, 1, n_iter, func(v):
		n_iter = int(v)
		_rebuild(), "%.0f")
	for m in range(ITER.size()):
		var mm := m
		var chk := LabUI.check(p, ITER[m], shown[m], func(v):
			shown[mm] = v
			_draw_paths(999))
		chk.add_theme_color_override("font_color", ITER_COLORS[m].lerp(Color.WHITE, 0.3))
		chk.add_theme_color_override("font_pressed_color", ITER_COLORS[m].lerp(Color.WHITE, 0.3))
	_omega_slider = LabUI.slider(p, "ω de SOR", 0.05, 1.95, 0.01, omega, func(v):
		omega = v
		_rebuild()
		lab._update_info(false))
	LabUI.button(p, "ω óptimo = 2/(1 + √(1 − ρ_J²))", func():
		var w := omega_opt()
		if not is_nan(w):
			_omega_slider.value = w)
	LabUI.button(p, "▶ Animar iteraciones", reset)
	LabUI.section(p, "log₁₀ ‖r‖ por iteración")
	res_plot = ResPlot.new()
	res_plot.module = self
	res_plot.custom_minimum_size = Vector2(260, 120)
	p.add_child(res_plot)
	LabUI.section(p, "Métodos directos")
	LabUI.option(p, "Método directo:", DIRECT, direct, func(i):
		direct = i
		lab._update_info(false))
	LabUI.slider(p, "Paso de eliminación", 0, 5, 1, elim_step, func(v):
		set_elim_step(int(v))
		lab._update_info(false), "%.0f")
	LabUI.note(p, "Cada paso de la eliminación cambia los planos por combinaciones de ellos que pasan por la misma solución, hasta x = c₁, y = c₂, z = c₃. Richardson usa α = 2/(λmín + λmáx) si A es SPD. Descenso y gradiente conjugado usan AᵀA si A no es simétrica; en 3×3 el gradiente conjugado termina en 3 pasos.")

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

static func _mat(M: Array, extra = null) -> String:
	var lines := []
	for i in range(M.size()):
		var cells := []
		for j in range((M[i] as Array).size()):
			cells.append("%8.4f" % float(M[i][j]))
		var s := " ".join(cells)
		if extra != null:
			s += "  │ %8.4f" % float(extra[i])
		lines.append("   [ " + s + " ]")
	return "\n".join(lines)

func iterations_to(m: int, eps: float = 1e-8) -> int:
	if m >= res_hist.size():
		return -1
	var res: Array = res_hist[m]
	for i in range(res.size()):
		if float(res[i]) < eps:
			return i
	return -1

func info() -> String:
	var t := "[font_size=12]"
	if sol != null:
		t += "x* = (%.4f, %.4f, %.4f) · det A = %.4f · κ∞(A) = %s\n" % [sol.x, sol.y, sol.z, det3(A), LabUI.sci(condition(), 2)]
	else:
		t += "[color=#ff7766]A es singular: no hay solución única.[/color]\n"
	var rj := spectral_radius_of(0)
	var rg := spectral_radius_of(1)
	var rs := spectral_radius_of(2)
	var rr := spectral_radius_of(3)
	var wo := omega_opt()
	t += "ρ Jacobi %.3f %s · ρ G-S %.3f %s · ρ SOR(ω=%.2f) %.3f %s · ρ Richardson %.3f %s\n" % [rj, "✔" if rj < 1 else "✖", rg, "✔" if rg < 1 else "✖", omega, rs, "✔" if rs < 1 else "✖", rr, "✔" if rr < 1 else "✖"]
	if not is_nan(wo):
		t += "ω óptimo ≈ %.3f · " % wo
	var its := []
	for m in range(ITER.size()):
		if shown[m]:
			var k := iterations_to(m)
			its.append("[color=#%s]%s[/color] %s" % [ITER_COLORS[m].to_html(false), ITER[m], ("%d it." % k) if k >= 0 else "✖ %s" % LabUI.sci(float(res_hist[m][res_hist[m].size() - 1]), 1)])
	t += "‖r‖ < 10⁻⁸: " + " · ".join(its) + "\n"
	match direct:
		0:
			if not elim_states.is_empty():
				var st_: Array = elim_states[elim_step]
				t += "%s\n%s" % [ELIM_TEXT[elim_step] if elim_step < ELIM_TEXT.size() else "", _mat(st_[0], st_[1])]
		1:
			var f = lu()
			if f == null:
				t += "LU: matriz singular"
			else:
				t += "PA = LU con P = filas %s\nL =\n%s\nU =\n%s" % [str((f[0] as Array).map(func(i): return i + 1)), _mat(f[1]), _mat(f[2])]
		2:
			var L = cholesky()
			t += "A no es simétrica definida positiva: Cholesky no existe." if L == null else "L (A = LLᵀ, coste ≈ n³/6) =\n%s" % _mat(L)
		3:
			var q = qr()
			t += "Columnas dependientes: QR no es completa." if q == null else "Q (ortogonal) =\n%s\nR =\n%s" % [_mat(q[0]), _mat(q[1])]
		4:
			var d := det3(A)
			if absf(d) < 1e-12:
				t += "det A = 0: Cramer no se aplica."
			else:
				var parts := []
				for i in range(3):
					var Ai := _copy(A)
					for r in range(3):
						Ai[r][i] = b[r]
					parts.append("x%d = det(A%d)/det A = %.4f/%.4f = %.5f" % [i + 1, i + 1, det3(Ai), d, det3(Ai) / d])
				t += "\n".join(parts)
	return t + "[/font_size]"

class ResPlot extends Control:
	var module
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.03, 0.05, 0.08, 0.9))
		for k in range(0, 17, 4):
			var y := r.size.y * float(k) / 16.0
			draw_line(Vector2(0, y), Vector2(r.size.x, y), Color(0.2, 0.3, 0.4, 0.5))
		if module == null:
			return
		for m in range(module.ITER.size()):
			if not module.shown[m] or m >= module.res_hist.size():
				continue
			var res: Array = module.res_hist[m]
			var pts := PackedVector2Array()
			for i in range(res.size()):
				var rn: float = res[i]
				var le: float = log(maxf(rn, 1e-16)) / log(10.0)
				pts.append(Vector2(r.size.x * float(i) / maxf(1.0, float(module.n_iter)), r.size.y * clampf((3.0 - le) / 19.0, 0.0, 1.0)))
			if pts.size() >= 2:
				draw_polyline(pts, module.ITER_COLORS[m], 1.8, true)
		draw_string(ThemeDB.fallback_font, Vector2(4, 12), "10³", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.7, 0.8))
		draw_string(ThemeDB.fallback_font, Vector2(4, r.size.y - 4), "10⁻¹⁶", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.7, 0.8))

func demo(extra: Array) -> void:
	if "eliminacion" in extra:
		set_elim_step(2)
