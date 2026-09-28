extends LabModule
## Solución numérica de la ecuación de calor 1D u_t = α u_xx con tres esquemas:
## explícito (FTCS), implícito (Euler hacia atrás) y Crank-Nicolson. Cada uno se
## dibuja como una superficie espacio-tiempo (x, t, u). Con r = αΔt/Δx² > ½ el
## explícito se vuelve inestable y sus oscilaciones crecen (se ve en rojo),
## mientras los implícitos siguen estables. Error frente a la solución exacta.

const NX := 41
const NT := 120
const W := 1.6          # ancho de cada superficie (mundo)
const D := 2.6          # profundidad (eje del tiempo)
const H := 1.1          # altura para u = 1
const NAMES := ["Explícito (FTCS)", "Implícito (Euler)", "Crank-Nicolson"]

var r: float = 0.4
var ic: int = 0
var alpha: float = 0.05
var sols: Array = []
var errs: Array = [0.0, 0.0, 0.0]
var node: Node3D
var _bk: Array = []
var _bk_ic: int = -1

func title() -> String: return "EDP numérica (calor 1D)"
func formula() -> String: return "u_t = α u_xx   ·   r = αΔt/Δx²   ·   FTCS estable si r ≤ ½"
func perturb_hint() -> String: return "clic: sube r un paso (Mayús+clic: lo baja)"
func view() -> Dictionary: return {"target": Vector3(0, 0.3, 0), "dist": 7.8, "yaw": -20.0, "pitch": -32.0}

func setup() -> void:
	node = Node3D.new()
	add_child(node)
	_solve_all()

func _u0(x: float) -> float:
	match ic:
		1: return 1.0 if absf(x - 0.5) < 0.15 else 0.0
		2: return 4.0 * x * (1.0 - x)
	return sin(PI * x) + 0.5 * sin(3.0 * PI * x)

func _exact(x: float, t: float) -> float:
	if ic == 0:
		return exp(-PI * PI * alpha * t) * sin(PI * x) + 0.5 * exp(-9.0 * PI * PI * alpha * t) * sin(3.0 * PI * x)
	# Serie de Fourier de la condición inicial (60 modos, coeficientes en caché).
	if _bk_ic != ic:
		_bk = [0.0]
		for k in range(1, 61):
			var bk := 0.0
			var m := 400
			for i in range(1, m):
				var xi := float(i) / m
				bk += _u0(xi) * sin(k * PI * xi)
			_bk.append(bk * 2.0 / m)
		_bk_ic = ic
	var s := 0.0
	for k in range(1, 61):
		s += float(_bk[k]) * exp(-k * k * PI * PI * alpha * t) * sin(k * PI * x)
	return s

func _thomas(a: float, b: float, c: float, d: Array) -> Array:
	# Sistema tridiagonal constante (a, b, c) con Dirichlet homogéneo.
	var n := d.size()
	var cp := []
	var dp := []
	cp.resize(n)
	dp.resize(n)
	cp[0] = c / b
	dp[0] = d[0] / b
	for i in range(1, n):
		var m: float = b - a * float(cp[i - 1])
		cp[i] = c / m
		dp[i] = (d[i] - a * dp[i - 1]) / m
	var x := []
	x.resize(n)
	x[n - 1] = dp[n - 1]
	for i in range(n - 2, -1, -1):
		x[i] = dp[i] - cp[i] * x[i + 1]
	return x

func _solve(scheme: int) -> Array:
	var u := []
	for i in range(NX):
		u.append(_u0(float(i) / (NX - 1)))
	u[0] = 0.0
	u[NX - 1] = 0.0
	var rows := [u.duplicate()]
	for k in range(NT):
		var un := []
		un.resize(NX)
		un[0] = 0.0
		un[NX - 1] = 0.0
		match scheme:
			0:
				for i in range(1, NX - 1):
					un[i] = u[i] + r * (u[i + 1] - 2.0 * u[i] + u[i - 1])
			1:
				var d := []
				for i in range(1, NX - 1): d.append(u[i])
				var x := _thomas(-r, 1.0 + 2.0 * r, -r, d)
				for i in range(1, NX - 1): un[i] = x[i - 1]
			2:
				var d2 := []
				for i in range(1, NX - 1):
					d2.append(u[i] + 0.5 * r * (u[i + 1] - 2.0 * u[i] + u[i - 1]))
				var x2 := _thomas(-0.5 * r, 1.0 + r, -0.5 * r, d2)
				for i in range(1, NX - 1): un[i] = x2[i - 1]
		for i in range(NX):
			un[i] = clampf(float(un[i]), -1e6, 1e6)
		u = un
		rows.append(u.duplicate())
	return rows

func _solve_all() -> void:
	sols = []
	var dx := 1.0 / (NX - 1)
	var dt := r * dx * dx / alpha
	var tf := dt * NT
	for s in range(3):
		var rows := _solve(s)
		sols.append(rows)
		var e := 0.0
		var last: Array = rows[NT]
		for i in range(NX):
			e = maxf(e, absf(float(last[i]) - _exact(float(i) / (NX - 1), tf)))
		errs[s] = e
	_draw()

func _draw() -> void:
	for c in node.get_children():
		c.queue_free()
	for s in range(3):
		var ox := (s - 1) * (W + 0.45)
		var rows: Array = sols[s]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var P := func(i: int, k: int) -> Vector3:
			var u := float(rows[k][i])
			return Vector3(ox + (float(i) / (NX - 1) - 0.5) * W, clampf(u, -1.5, 1.5) * H, (float(k) / NT - 0.5) * D)
		var C := func(i: int, k: int) -> Color:
			var u := float(rows[k][i])
			if absf(u) > 1.2:
				return Color(1.0, 0.15, 0.35)
			var t := clampf(u * 0.6 + 0.3, 0.0, 1.0)
			return Color.from_hsv(0.66 - t * 0.66, 0.8, 0.5 + t * 0.5)
		for k in range(NT):
			for i in range(NX - 1):
				var a: Vector3 = P.call(i, k)
				var b: Vector3 = P.call(i + 1, k)
				var c: Vector3 = P.call(i + 1, k + 1)
				var d: Vector3 = P.call(i, k + 1)
				var nrm := (b - a).cross(d - a).normalized()
				if nrm.y < 0: nrm = -nrm
				var quad := [[a, i, k], [b, i + 1, k], [c, i + 1, k + 1], [a, i, k], [c, i + 1, k + 1], [d, i, k + 1]]
				for q in quad:
					st.set_normal(nrm)
					st.set_color(C.call(q[1], q[2]))
					st.add_vertex(q[0])
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 0.3
		m.emission_enabled = true
		m.emission = Color(0.05, 0.1, 0.15)
		mi.material_override = m
		node.add_child(mi)
		var unstable: bool = float(errs[s]) > 1.0
		var col := Color(1.0, 0.35, 0.4) if unstable else Color(0.4, 0.95, 1.0)
		node.add_child(label3d("%s\nerror máx = %s" % [NAMES[s], LabUI.sci(errs[s], 2)], Vector3(ox, H * 1.7, -D * 0.5), col, 0.0034))
		# Ejes x y t de cada superficie.
		node.add_child(rod(Vector3(ox - W * 0.5, 0, D * 0.52), Vector3(ox + W * 0.5, 0, D * 0.52), 0.006, glow_mat(Color(0.8, 0.8, 0.9), 0.8)))
		node.add_child(rod(Vector3(ox - W * 0.55, 0, -D * 0.5), Vector3(ox - W * 0.55, 0, D * 0.5), 0.006, glow_mat(Color(0.8, 0.8, 0.9), 0.8)))
	node.add_child(label3d("x →", Vector3(W * 0.5 + 1.8, 0, D * 0.6), Color(0.8, 0.85, 0.95), 0.003))
	node.add_child(label3d("t →", Vector3(-W * 1.5 - 0.7, 0, -D * 0.4), Color(0.8, 0.85, 0.95), 0.003))

func build_ui(p: VBoxContainer) -> void:
	LabUI.slider(p, "r = αΔt/Δx²", 0.05, 1.5, 0.01, r, func(v):
		r = v
		_solve_all())
	LabUI.option(p, "Condición inicial:", ["sin(πx) + ½ sin(3πx)", "Pulso rectangular", "Parábola 4x(1−x)"], ic, func(i):
		ic = i
		_solve_all())
	LabUI.note(p, "Sube r por encima de 0.5: el esquema explícito amplifica el modo de mayor frecuencia (factor |1 − 4r| > 1) y la superficie estalla en rojo. Euler implícito es estable pero de orden 1 en el tiempo; Crank-Nicolson es de orden 2 (aunque con r grande y datos no suaves muestra oscilaciones amortiguadas).")

func pick(origin: Vector3, dir: Vector3):
	return ray_plane_y(origin, dir, 0.0)

func hover_text(hit: Vector3) -> String:
	var s := clampi(int(round(hit.x / (W + 0.45))) + 1, 0, 2)
	var ox := (s - 1) * (W + 0.45)
	var x := clampf((hit.x - ox) / W + 0.5, 0.0, 1.0)
	var k := clampi(int((hit.z / D + 0.5) * NT), 0, NT)
	var dx := 1.0 / (NX - 1)
	var dt := r * dx * dx / alpha
	var i := clampi(int(round(x * (NX - 1))), 0, NX - 1)
	var u := float(sols[s][k][i])
	return "%s\nx = %.3f   t = %.4f\nu = %.4f · exacta = %.4f" % [NAMES[s], x, k * dt, u, _exact(x, k * dt)]

func perturb(_hit: Vector3, first: bool) -> void:
	if first:
		r = clampf(r + (-0.05 if Input.is_key_pressed(KEY_SHIFT) else 0.05), 0.05, 1.5)
		_solve_all()

func info() -> String:
	var stable := "[color=#66ff88]estable[/color]" if r <= 0.5 else "[color=#ff6677]INESTABLE (r > ½)[/color]"
	return "r = %.2f → FTCS %s · amplificación del modo más alto |1 − 4r| = %.2f\nError máx. final: FTCS %s · Euler implícito %s · Crank-Nicolson %s" % [
		r, stable, absf(1.0 - 4.0 * r), LabUI.sci(errs[0], 2), LabUI.sci(errs[1], 2), LabUI.sci(errs[2], 2)]
