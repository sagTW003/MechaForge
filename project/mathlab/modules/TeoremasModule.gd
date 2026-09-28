extends LabModule
## Teoremas integrales visualizados y verificados numéricamente:
##   · Gauss (divergencia): ∯_S F·n dA = ∭_V ∇·F dV sobre una esfera móvil. La
##     superficie se colorea con F·n (rojo sale, azul entra) y se calculan ambos
##     miembros por cuadratura.
##   · Stokes: ∮_C F·dr = ∬_Σ (∇×F)·n dA sobre un disco con orientación libre. La
##     curva se colorea con F·t y el disco con (∇×F)·n.

const Campo = preload("res://mathlab/modules/CampoModule.gd")
const S := 0.8
const OFFSET := Vector3(0, 0.3, 0)

var P: MathExpr
var Q: MathExpr
var R: MathExpr
var preset: int = 1
var theorem: int = 0         # 0 Gauss, 1 Stokes
var center := Vector3.ZERO
var radius: float = 1.0
var n_theta: float = 30.0    # orientación de la normal del disco (grados)
var n_phi: float = 20.0
var surf: MeshInstance3D
var extra: Node3D
var context: MultiMeshInstance3D
var lhs: float = 0.0
var rhs: float = 0.0

func title() -> String: return "Teoremas de Gauss y Stokes"
func formula() -> String:
	return "∯ F·n dA = ∭ ∇·F dV" if theorem == 0 else "∮ F·dr = ∬ (∇×F)·n dA"
func perturb_hint() -> String: return "clic en el plano z = 0: mueve el centro de la superficie"
func view() -> Dictionary: return {"target": OFFSET, "dist": 6.5, "yaw": -35.0, "pitch": -25.0}

func setup() -> void:
	scale_xy = S
	scale_z = S
	position = OFFSET
	surf = MeshInstance3D.new()
	add_child(surf)
	extra = Node3D.new()
	add_child(extra)
	context = MultiMeshInstance3D.new()
	add_child(context)
	add_child(axes(2.2 * S, 0.006))
	_load(preset)

func _load(i: int) -> void:
	var p: Array = Campo.PRESETS[i]
	P = MathExpr.parse(p[1], ["x", "y", "z"])
	Q = MathExpr.parse(p[2], ["x", "y", "z"])
	R = MathExpr.parse(p[3], ["x", "y", "z"])
	for e in [P, Q, R]: e.compile_fast()
	_rebuild()

func F(p: Vector3) -> Vector3:
	var a := [p.x, p.y, p.z]
	return Vector3(P.eval_fast(a), Q.eval_fast(a), R.eval_fast(a))

func div(p: Vector3) -> float:
	var h := 1e-3
	return (F(p + Vector3(h, 0, 0)).x - F(p - Vector3(h, 0, 0)).x + F(p + Vector3(0, h, 0)).y - F(p - Vector3(0, h, 0)).y + F(p + Vector3(0, 0, h)).z - F(p - Vector3(0, 0, h)).z) / (2 * h)

func curl(p: Vector3) -> Vector3:
	var h := 1e-3
	var dx := (F(p + Vector3(h, 0, 0)) - F(p - Vector3(h, 0, 0))) / (2 * h)
	var dy := (F(p + Vector3(0, h, 0)) - F(p - Vector3(0, h, 0))) / (2 * h)
	var dz := (F(p + Vector3(0, 0, h)) - F(p - Vector3(0, 0, h))) / (2 * h)
	return Vector3(dy.z - dz.y, dz.x - dx.z, dx.y - dy.x)

func normal() -> Vector3:
	var t := deg_to_rad(n_theta)
	var ph := deg_to_rad(n_phi)
	return Vector3(sin(t) * cos(ph), sin(t) * sin(ph), cos(t)).normalized()

func _w(p: Vector3) -> Vector3:
	return to_world(p.x, p.y, p.z)

static func _div_col(v: float, vmax: float) -> Color:
	var t := clampf(v / maxf(vmax, 1e-9), -1.0, 1.0)
	var mid := Color(0.9, 0.92, 0.95)
	return mid.lerp(Color(1.0, 0.25, 0.15), t) if t >= 0.0 else mid.lerp(Color(0.15, 0.45, 1.0), -t)

func _rebuild() -> void:
	for c in extra.get_children():
		c.queue_free()
	if theorem == 0:
		_gauss()
	else:
		_stokes()
	_context_arrows()

func _gauss() -> void:
	# Superficie coloreada por F·n.
	var nt := 36
	var np := 72
	var vals := []
	var vmax := 1e-9
	for i in range(nt + 1):
		var row := []
		for j in range(np + 1):
			var th := PI * i / nt
			var ph := TAU * j / np
			var n := Vector3(sin(th) * cos(ph), sin(th) * sin(ph), cos(th))
			var v := F(center + n * radius).dot(n)
			row.append([n, v])
			vmax = maxf(vmax, absf(v) if is_finite(v) else 0.0)
		vals.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(nt):
		for j in range(np):
			for q in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j], [i + 1, j + 1], [i, j + 1]]:
				var e: Array = vals[q[0]][q[1]]
				var n: Vector3 = e[0]
				st.set_color(_div_col(e[1], vmax))
				st.set_normal(Vector3(n.x, n.z, -n.y))
				st.add_vertex(_w(center + n * radius))
	surf.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1, 1, 1, 0.8)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.25
	m.emission_enabled = true
	m.emission = Color(0.12, 0.12, 0.14)
	surf.material_override = m
	# Flechas de la componente normal.
	for i in range(1, 8):
		for j in range(0, 14):
			var th := PI * i / 8.0
			var ph := TAU * j / 14.0
			var n := Vector3(sin(th) * cos(ph), sin(th) * sin(ph), cos(th))
			var p := center + n * radius
			var fn := F(p).dot(n)
			if not is_finite(fn): continue
			var L := clampf(fn / vmax, -1.0, 1.0) * 0.35
			if absf(L) < 0.02: continue
			extra.add_child(arrow(_w(p), _w(p + n * L), 0.006, glow_mat(_div_col(fn, vmax), 1.6)))
	# Cuadraturas: flujo (superficie) y divergencia (volumen).
	var flux := 0.0
	var mt := 60
	var mp := 120
	for i in range(mt):
		var th := PI * (i + 0.5) / mt
		for j in range(mp):
			var ph := TAU * (j + 0.5) / mp
			var n := Vector3(sin(th) * cos(ph), sin(th) * sin(ph), cos(th))
			flux += F(center + n * radius).dot(n) * sin(th)
	flux *= radius * radius * (PI / mt) * (TAU / mp)
	var vol := 0.0
	var mr := 16
	var vt := 20
	var vp := 40
	for a in range(mr):
		var r := radius * (a + 0.5) / mr
		for i in range(vt):
			var th := PI * (i + 0.5) / vt
			for j in range(vp):
				var ph := TAU * (j + 0.5) / vp
				var p := center + Vector3(sin(th) * cos(ph), sin(th) * sin(ph), cos(th)) * r
				vol += div(p) * r * r * sin(th)
	vol *= (radius / mr) * (PI / vt) * (TAU / vp)
	lhs = flux
	rhs = vol

func _stokes() -> void:
	var n := normal()
	var u := n.cross(Vector3(0, 0, 1) if absf(n.z) < 0.9 else Vector3(1, 0, 0)).normalized()
	var v := n.cross(u)
	# Disco coloreado por (∇×F)·n.
	var nr := 16
	var na := 72
	var cvals := []
	var cmax := 1e-9
	for i in range(nr + 1):
		var row := []
		for j in range(na + 1):
			var a := TAU * j / na
			var p := center + (u * cos(a) + v * sin(a)) * radius * float(i) / nr
			var c := curl(p).dot(n)
			row.append([p, c])
			cmax = maxf(cmax, absf(c) if is_finite(c) else 0.0)
		cvals.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nw := Vector3(n.x, n.z, -n.y)
	for i in range(nr):
		for j in range(na):
			for q in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j], [i + 1, j + 1], [i, j + 1]]:
				var e: Array = cvals[q[0]][q[1]]
				st.set_color(_div_col(e[1], cmax))
				st.set_normal(nw)
				st.add_vertex(_w(e[0]))
	surf.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1, 1, 1, 0.75)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.emission_enabled = true
	m.emission = Color(0.1, 0.1, 0.12)
	surf.material_override = m
	extra.add_child(arrow(_w(center), _w(center + n * radius * 0.9), 0.012, glow_mat(Color(1, 1, 1), 2.0)))
	extra.add_child(label3d("n", _w(center + n * radius * 1.0), Color(1, 1, 1), 0.003))
	# Curva frontera coloreada por F·t y flechas tangentes.
	var pts := PackedVector3Array()
	var circ := 0.0
	var N := 480
	var tmax := 1e-9
	for k in range(N):
		var a := TAU * (k + 0.5) / N
		var p := center + (u * cos(a) + v * sin(a)) * radius
		var t := (-u * sin(a) + v * cos(a))
		var ft := F(p).dot(t)
		circ += ft * radius * TAU / N
		tmax = maxf(tmax, absf(ft))
	for k in range(N + 1):
		var a := TAU * k / N
		pts.append(_w(center + (u * cos(a) + v * sin(a)) * radius))
	extra.add_child(tube(pts, 0.018, glow_mat(Color(1.0, 0.85, 0.3), 2.0), 8))
	for k in range(16):
		var a := TAU * k / 16.0
		var p := center + (u * cos(a) + v * sin(a)) * radius
		var t := (-u * sin(a) + v * cos(a))
		var ft := F(p).dot(t)
		var L := clampf(ft / tmax, -1.0, 1.0) * 0.4
		if absf(L) > 0.02:
			extra.add_child(arrow(_w(p), _w(p + t * L), 0.008, glow_mat(_div_col(ft, tmax), 2.0)))
	var fl := 0.0
	var mr := 30
	var ma := 120
	for i in range(mr):
		var r := radius * (i + 0.5) / mr
		for j in range(ma):
			var a := TAU * (j + 0.5) / ma
			var p := center + (u * cos(a) + v * sin(a)) * r
			fl += curl(p).dot(n) * r
	fl *= (radius / mr) * (TAU / ma)
	lhs = circ
	rhs = fl

func _context_arrows() -> void:
	var n := 5
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = Campo.arrow_mesh()
	mm.instance_count = n * n * n
	var sp := 4.0 / n
	var fmax := 1e-9
	var samples := []
	for k in range(n):
		for j in range(n):
			for i in range(n):
				var p := Vector3(-2 + (i + 0.5) * sp, -2 + (j + 0.5) * sp, -2 + (k + 0.5) * sp)
				var f := F(p)
				samples.append([p, f])
				if f.is_finite(): fmax = maxf(fmax, f.length())
	for idx in range(samples.size()):
		var p: Vector3 = samples[idx][0]
		var f: Vector3 = samples[idx][1]
		var d := Vector3(f.x, f.z, -f.y).normalized() if f.length() > 1e-9 and f.is_finite() else Vector3.UP
		var b := Basis(Quaternion(Vector3.UP, d)) if absf(d.dot(Vector3.UP)) < 0.9999 else Basis.IDENTITY
		var L := sp * 0.7 * (clampf(f.length() / fmax, 0.15, 1.0) if f.is_finite() else 0.0)
		mm.set_instance_transform(idx, Transform3D(b * Basis.from_scale(Vector3(S * sp, L * S, S * sp)), _w(p)))
		mm.set_instance_color(idx, Color(0.55, 0.75, 1.0, 0.45))
	context.multimesh = mm
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(0.1, 0.2, 0.35)
	context.material_override = m

func build_ui(p: VBoxContainer) -> void:
	LabUI.option(p, "Teorema:", ["Gauss (divergencia)", "Stokes (rotacional)"], theorem, func(i):
		theorem = i
		_rebuild()
		lab._update_info(false))
	var names := []
	for q in Campo.PRESETS: names.append(q[0])
	LabUI.option(p, "Campo F:", names, preset, func(i):
		preset = i
		_load(i))
	LabUI.slider(p, "Radio", 0.2, 1.8, 0.05, radius, func(v):
		radius = v
		_rebuild())
	LabUI.slider(p, "Centro x", -1.5, 1.5, 0.05, 0.0, func(v):
		center.x = v
		_rebuild())
	LabUI.slider(p, "Centro y", -1.5, 1.5, 0.05, 0.0, func(v):
		center.y = v
		_rebuild())
	LabUI.slider(p, "Centro z", -1.5, 1.5, 0.05, 0.0, func(v):
		center.z = v
		_rebuild())
	LabUI.section(p, "Orientación del disco (Stokes)")
	LabUI.slider(p, "Inclinación θ de n", 0.0, 180.0, 1.0, n_theta, func(v):
		n_theta = v
		if theorem == 1: _rebuild(), "%.0f°")
	LabUI.slider(p, "Azimut φ de n", 0.0, 360.0, 1.0, n_phi, func(v):
		n_phi = v
		if theorem == 1: _rebuild(), "%.0f°")
	LabUI.note(p, "Ambos miembros se calculan por separado (cuadratura de superficie y de volumen/disco): su coincidencia es la comprobación numérica del teorema. En el campo del hilo, el disco que rodea el eje tiene circulación 2π aunque el rotacional sea casi nulo fuera de él.")

func pick(origin: Vector3, dir: Vector3):
	var lo := to_local(origin)
	var ld := (to_local(origin + dir) - lo).normalized()
	var hit = ray_plane_y(lo, ld, 0.0)
	if hit == null or absf(hit.x) > 2 * S or absf(hit.z) > 2 * S:
		return null
	return to_global(hit)

func hover_text(hit: Vector3) -> String:
	var m := to_math(to_local(hit))
	var f := F(m)
	return "(x, y, 0) = (%.2f, %.2f)\nF = (%.2f, %.2f, %.2f)\n∇·F = %.3f · (∇×F)_z = %.3f" % [m.x, m.y, f.x, f.y, f.z, div(m), curl(m).z]

func perturb(hit: Vector3, first: bool) -> void:
	var m := to_math(to_local(hit))
	center = Vector3(m.x, m.y, center.z)
	if first or Engine.get_process_frames() % 3 == 0:
		_rebuild()

func critical_points() -> Array:
	return [{"pos": to_global(_w(center)), "nombre": "Centro de la superficie", "dist": 3.5}]

func info() -> String:
	var diff := absf(lhs - rhs) / maxf(1e-9, maxf(absf(lhs), absf(rhs)))
	var ok := diff < 0.02 or absf(lhs - rhs) < 1e-4
	if theorem == 0:
		return "Flujo ∯ F·n dA = [color=#ffcc55]%.5f[/color]\n∭ ∇·F dV = [color=#ffcc55]%.5f[/color]\n%s diferencia relativa %.2f %%" % [lhs, rhs, "✔" if ok else "≈", diff * 100.0]
	return "Circulación ∮ F·dr = [color=#ffcc55]%.5f[/color]\n∬ (∇×F)·n dA = [color=#ffcc55]%.5f[/color]\n%s diferencia relativa %.2f %%" % [lhs, rhs, "✔" if ok else "≈", diff * 100.0]
