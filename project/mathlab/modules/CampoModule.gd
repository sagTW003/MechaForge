extends LabModule
## Campos vectoriales 3D F(x, y, z) = (P, Q, R):
##   · rejilla de flechas instanciadas (MultiMesh) coloreadas por |F|;
##   · modo gradiente F = ∇φ de un campo escalar;
##   · líneas de corriente (Runge-Kutta 4 hacia delante y hacia atrás);
##   · partículas GPU que fluyen con el campo (la fórmula se compila al shader de
##     partículas) con estelas;
##   · divergencia (esferas rojas = fuentes, azules = sumideros) y rotacional
##     (ruedas de paletas que giran con velocidad ½|∇×F| alrededor de su eje);
##   · puntos de equilibrio F = 0 clasificados por los autovalores del jacobiano.

const S := 0.8
const OFFSET := Vector3(0, 0.3, 0)
const PRESETS := [
	["Vórtice", "-y", "x", "0"],
	["Fuente radial", "x", "y", "z"],
	["Sumidero", "-x", "-y", "-z"],
	["Punto de silla", "x", "-y", "0"],
	["Hilo con corriente (campo B)", "-y/(x^2 + y^2 + 0.05)", "x/(x^2 + y^2 + 0.05)", "0"],
	["Espiral ascendente", "-y - 0.2x", "x - 0.2y", "0.3"],
	["Flujo ABC (Arnold–Beltrami–Childress)", "sin(z) + cos(y)", "sin(x) + cos(z)", "sin(y) + cos(x)"],
	["Lorenz (escalado)", "10(y - x)/15", "(x(2.8 - z) - y)/1.5", "(x y - 0.8z)/1.5"],
	["Dipolo 2D", "(x^2 - y^2 - 0.3)/((x^2+y^2+0.1)^2)", "2x y/((x^2+y^2+0.1)^2)", "0"],
]
const PARTICLE_SHADER := """
shader_type particles;
/*PRELUDE*/
uniform float speed = 0.5;
uniform float half_box = 2.0;
uniform float s = 0.8;
uniform vec3 offset = vec3(0.0, 0.3, 0.0);
uniform float fmax = 1.0;
uniform bool grad_mode = false;

float PHI(float x, float y, float z) { return /*PHI*/; }
vec3 FF(float x, float y, float z) {
	if (grad_mode) {
		float h = 1e-3;
		return vec3(PHI(x + h, y, z) - PHI(x - h, y, z), PHI(x, y + h, z) - PHI(x, y - h, z), PHI(x, y, z + h) - PHI(x, y, z - h)) / (2.0 * h);
	}
	return vec3(/*P*/, /*Q*/, /*R*/);
}
float h1(uint n) { n = (n << 13u) ^ n; n = n * (n * n * 15731u + 789221u) + 1376312589u; return float(n & 0x7fffffffu) / float(0x7fffffff); }
vec3 turbo_c(float t) {
	t = clamp(t, 0.0, 1.0);
	return clamp(vec3(0.13572138 + t * (4.6153926 + t * (-42.66032258 + t * (132.13108234 + t * (-152.94239396 + t * 59.28637943)))),
		0.09140261 + t * (2.19418839 + t * (4.84296658 + t * (-14.18503333 + t * (4.27729857 + t * 2.82956604)))),
		0.1066733 + t * (12.64194608 + t * (-60.58204836 + t * (110.36276771 + t * (-89.90310912 + t * 27.34824973))))), 0.0, 1.0);
}
void start() {
	uint seed = INDEX * 1973u + RANDOM_SEED * 9277u;
	vec3 r = vec3(h1(seed), h1(seed + 17u), h1(seed + 101u)) * 2.0 - 1.0;
	TRANSFORM[3].xyz = offset + r * half_box * s;
	VELOCITY = vec3(0.0);
}
void process() {
	vec3 lw = (TRANSFORM[3].xyz - offset) / s;
	vec3 m = vec3(lw.x, -lw.z, lw.y);
	vec3 F = FF(m.x, m.y, m.z);
	vec3 Fw = vec3(F.x, F.z, -F.y);
	float mag = length(F);
	VELOCITY = Fw / (1.0 + mag / max(fmax, 1e-6)) * speed * s;
	COLOR = vec4(turbo_c(mag / max(fmax, 1e-6)), 1.0);
	if (any(greaterThan(abs(lw), vec3(half_box * 1.02))) || mag > 1e4 || mag != mag) {
		ACTIVE = false;
	}
}
"""

var P: MathExpr
var Q: MathExpr
var R: MathExpr
var PHI: MathExpr
var grad_mode: bool = false
var preset: int = 0
var density: int = 7
var normalize_len: bool = false
var show_arrows: bool = true
var show_stream: bool = true
var show_particles: bool = true
var show_div: bool = false
var show_curl: bool = false
var particle_speed: float = 0.6
var slice_z: float = 0.0
var fmax: float = 1.0
var arrows: MultiMeshInstance3D
var arrow_mat: ShaderMaterial
var stream_node: Node3D
var particles: GPUParticles3D
var div_mm: MultiMeshInstance3D
var curl_mm: MultiMeshInstance3D
var curl_data: Array = []      # [[pos_w, axis_w, omega]]
var slice: MeshInstance3D
var equilibria: Array = []     # [[p, tipo]]
var eq_node: Node3D
var eq_line: bool = false      # equilibrios no aislados (p. ej. el eje de un vórtice)
var _t: float = 0.0

func title() -> String: return "Campos vectoriales 3D"
func formula() -> String: return "F = (P, Q, R) · ∇·F = ∂P/∂x + ∂Q/∂y + ∂R/∂z · ∇×F = (R_y − Q_z, P_z − R_x, Q_x − P_y)"
func uses_time() -> bool: return true
func perturb_hint() -> String: return "clic: siembra una línea de corriente desde ese punto del plano de muestra"
func view() -> Dictionary: return {"target": OFFSET, "dist": 7.5, "yaw": -35.0, "pitch": -25.0}

func setup() -> void:
	scale_xy = S
	scale_z = S
	position = OFFSET
	arrows = MultiMeshInstance3D.new()
	add_child(arrows)
	arrow_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
#include "res://mathlab/shaders/common.gdshaderinc"
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	if (clipped(wpos)) discard;
	ALBEDO = COLOR.rgb;
	EMISSION = COLOR.rgb * 0.55;
	ROUGHNESS = 0.3;
	METALLIC = 0.2;
}
"""
	arrow_mat.shader = sh
	arrows.material_override = arrow_mat
	register_clip(arrow_mat)
	stream_node = Node3D.new()
	add_child(stream_node)
	div_mm = MultiMeshInstance3D.new()
	add_child(div_mm)
	curl_mm = MultiMeshInstance3D.new()
	add_child(curl_mm)
	eq_node = Node3D.new()
	add_child(eq_node)
	# Cubo del dominio y plano de muestra.
	var cube := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 4.0 * S
	cube.mesh = bm
	var cm := glass_mat(Color(0.2, 0.5, 0.8), 0.04)
	cube.material_override = cm
	add_child(cube)
	slice = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4.0 * S, 4.0 * S)
	slice.mesh = pm
	slice.material_override = glass_mat(Color(0.3, 0.8, 1.0), 0.07)
	add_child(slice)
	add_child(axes(2.3 * S, 0.006))
	particles = GPUParticles3D.new()
	particles.amount = 1800
	particles.lifetime = 5.0
	particles.preprocess = 2.0
	particles.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
	particles.trail_enabled = true
	particles.trail_lifetime = 0.45
	var tm := TubeTrailMesh.new()
	tm.radius = 0.007
	tm.radial_steps = 4
	tm.sections = 6
	tm.section_length = 0.02
	var tmat := StandardMaterial3D.new()
	tmat.use_particle_trails = true
	tmat.vertex_color_use_as_albedo = true
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(1, 1))
	tm.curve = curve
	tm.material = tmat
	particles.draw_pass_1 = tm
	add_child(particles)
	_load(preset)

func _load(i: int) -> void:
	var p: Array = PRESETS[i]
	_set_field(MathExpr.parse(p[1], ["x", "y", "z"]), MathExpr.parse(p[2], ["x", "y", "z"]), MathExpr.parse(p[3], ["x", "y", "z"]))

func _set_field(p: MathExpr, q: MathExpr, r: MathExpr) -> void:
	P = p; Q = q; R = r
	for e in [P, Q, R]:
		e.compile_fast()
	if PHI == null:
		PHI = MathExpr.parse("x^2 - y^2 + 0.5z^2", ["x", "y", "z"])
	PHI.compile_fast()
	_rebuild()

func F(p: Vector3) -> Vector3:
	if grad_mode:
		var h := 1e-4
		return Vector3(
			PHI.eval_fast([p.x + h, p.y, p.z]) - PHI.eval_fast([p.x - h, p.y, p.z]),
			PHI.eval_fast([p.x, p.y + h, p.z]) - PHI.eval_fast([p.x, p.y - h, p.z]),
			PHI.eval_fast([p.x, p.y, p.z + h]) - PHI.eval_fast([p.x, p.y, p.z - h])) / (2.0 * h)
	var a := [p.x, p.y, p.z]
	return Vector3(P.eval_fast(a), Q.eval_fast(a), R.eval_fast(a))

func divergence(p: Vector3) -> float:
	var h := 1e-3
	return (F(p + Vector3(h, 0, 0)).x - F(p - Vector3(h, 0, 0)).x + F(p + Vector3(0, h, 0)).y - F(p - Vector3(0, h, 0)).y + F(p + Vector3(0, 0, h)).z - F(p - Vector3(0, 0, h)).z) / (2.0 * h)

func curl(p: Vector3) -> Vector3:
	var h := 1e-3
	var dx := (F(p + Vector3(h, 0, 0)) - F(p - Vector3(h, 0, 0))) / (2.0 * h)
	var dy := (F(p + Vector3(0, h, 0)) - F(p - Vector3(0, h, 0))) / (2.0 * h)
	var dz := (F(p + Vector3(0, 0, h)) - F(p - Vector3(0, 0, h))) / (2.0 * h)
	return Vector3(dy.z - dz.y, dz.x - dx.z, dx.y - dy.x)

func _wv(v: Vector3) -> Vector3:
	return Vector3(v.x, v.z, -v.y)

static func arrow_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 8
	var rs := 0.035
	var rc := 0.1
	var hs := 0.7
	for k in range(seg):
		var a0 := TAU * k / seg
		var a1 := TAU * (k + 1) / seg
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		for q in [[d0 * rs, d0], [d1 * rs, d1], [d1 * rs + Vector3(0, hs, 0), d1], [d0 * rs, d0], [d1 * rs + Vector3(0, hs, 0), d1], [d0 * rs + Vector3(0, hs, 0), d0]]:
			st.set_normal(q[1]); st.add_vertex(q[0])
		var tip := Vector3(0, 1, 0)
		var n0 := (d0 + Vector3(0, rc / (1.0 - hs), 0)).normalized()
		var n1 := (d1 + Vector3(0, rc / (1.0 - hs), 0)).normalized()
		for q in [[d0 * rc + Vector3(0, hs, 0), n0], [tip, (n0 + n1).normalized()], [d1 * rc + Vector3(0, hs, 0), n1]]:
			st.set_normal(q[1]); st.add_vertex(q[0])
		for q in [[Vector3(0, hs, 0), Vector3.DOWN], [d0 * rc + Vector3(0, hs, 0), Vector3.DOWN], [d1 * rc + Vector3(0, hs, 0), Vector3.DOWN]]:
			st.set_normal(q[1]); st.add_vertex(q[0])
	return st.commit()

static func turbo(t: float) -> Color:
	t = clampf(t, 0.0, 1.0)
	var r := 0.13572138 + t * (4.6153926 + t * (-42.66032258 + t * (132.13108234 + t * (-152.94239396 + t * 59.28637943))))
	var g := 0.09140261 + t * (2.19418839 + t * (4.84296658 + t * (-14.18503333 + t * (4.27729857 + t * 2.82956604))))
	var b := 0.1066733 + t * (12.64194608 + t * (-60.58204836 + t * (110.36276771 + t * (-89.90310912 + t * 27.34824973))))
	return Color(clampf(r, 0, 1), clampf(g, 0, 1), clampf(b, 0, 1))

func _rebuild() -> void:
	# Magnitud de referencia (percentil 90) para colorear y escalar.
	var mags := []
	for i in range(300):
		var p := Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2))
		var m := F(p).length()
		if is_finite(m): mags.append(m)
	mags.sort()
	fmax = maxf(1e-6, mags[int(mags.size() * 0.9)] if not mags.is_empty() else 1.0)
	_build_arrows()
	_build_streamlines()
	_build_particles()
	_build_div_curl()
	_find_equilibria()
	slice.position = to_world(0, 0, slice_z)

func _build_arrows() -> void:
	arrows.visible = show_arrows
	var n := density
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = arrow_mesh()
	mm.instance_count = n * n * n
	var spacing := 4.0 / n
	var idx := 0
	for k in range(n):
		for j in range(n):
			for i in range(n):
				var p := Vector3(-2 + (i + 0.5) * spacing, -2 + (j + 0.5) * spacing, -2 + (k + 0.5) * spacing)
				var v := F(p)
				var m := v.length()
				var L: float
				if not is_finite(m) or m < 1e-9:
					L = 0.0
				elif normalize_len:
					L = spacing * 0.75
				else:
					L = spacing * 0.9 * clampf(log(1.0 + m / fmax * 1.7) / log(2.7), 0.08, 1.4)
				var dir := _wv(v).normalized() if m > 1e-9 else Vector3.UP
				var b := Basis(Quaternion(Vector3.UP, dir)) if absf(dir.dot(Vector3.UP)) < 0.9999 else (Basis.IDENTITY if dir.y > 0 else Basis(Vector3.RIGHT, PI))
				b = b * Basis.from_scale(Vector3(S * spacing * 1.2, L * S, S * spacing * 1.2))
				mm.set_instance_transform(idx, Transform3D(b, to_world(p.x, p.y, p.z)))
				mm.set_instance_color(idx, turbo(m / fmax * 0.85))
				idx += 1
	arrows.multimesh = mm

func _rk4(p: Vector3, h: float) -> Vector3:
	var k1 := F(p)
	var k2 := F(p + k1 * h * 0.5)
	var k3 := F(p + k2 * h * 0.5)
	var k4 := F(p + k3 * h)
	return p + (k1 + 2.0 * k2 + 2.0 * k3 + k4) * h / 6.0

func streamline(seed: Vector3, steps: int = 160) -> Array:
	var out := []
	for dirs in [-1.0, 1.0]:
		var pts := []
		var p := seed
		for k in range(steps):
			var v := F(p)
			var m := v.length()
			if not is_finite(m) or m < 1e-6:
				break
			var h: float = float(dirs) * clampf(0.03 / m, 0.0005, 0.08)
			p = _rk4(p, h)
			if absf(p.x) > 2 or absf(p.y) > 2 or absf(p.z) > 2 or not p.is_finite():
				break
			pts.append(p)
		if dirs < 0:
			pts.reverse()
			pts.append(seed)
		out.append_array(pts)
	return out

func _colored_tube(pts: Array, r: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring := 5
	var prev_ring := []
	var n1_prev := Vector3.ZERO
	for i in range(pts.size()):
		var p: Vector3 = to_world(pts[i].x, pts[i].y, pts[i].z)
		var pn: Vector3 = to_world(pts[mini(i + 1, pts.size() - 1)].x, pts[mini(i + 1, pts.size() - 1)].y, pts[mini(i + 1, pts.size() - 1)].z)
		var pp: Vector3 = to_world(pts[maxi(i - 1, 0)].x, pts[maxi(i - 1, 0)].y, pts[maxi(i - 1, 0)].z)
		var t := (pn - pp).normalized()
		if t.length() < 0.5: t = Vector3.RIGHT
		var n1 := n1_prev - t * n1_prev.dot(t) if n1_prev != Vector3.ZERO else t.cross(Vector3.UP)
		if n1.length() < 1e-3: n1 = t.cross(Vector3.RIGHT)
		n1 = n1.normalized()
		n1_prev = n1
		var n2 := t.cross(n1)
		var col := turbo(F(pts[i]).length() / fmax * 0.85)
		var cur := []
		for k in range(ring):
			var a := TAU * k / ring
			var d := n1 * cos(a) + n2 * sin(a)
			cur.append([p + d * r, d])
		if not prev_ring.is_empty():
			for k in range(ring):
				var k2 := (k + 1) % ring
				for q in [prev_ring[k], cur[k], cur[k2], prev_ring[k], cur[k2], prev_ring[k2]]:
					st.set_color(col)
					st.set_normal(q[1])
					st.add_vertex(q[0])
		prev_ring = cur
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.emission_enabled = true
	m.emission_energy_multiplier = 0.8
	m.emission = Color(0.15, 0.15, 0.15)
	m.roughness = 0.35
	mi.material_override = m
	return mi

func _build_streamlines() -> void:
	for c in stream_node.get_children():
		c.queue_free()
	stream_node.visible = show_stream
	if not show_stream:
		return
	# Semillas en una esfera (Fibonacci) y en el plano de muestra.
	var seeds := []
	var ns := 26
	for i in range(ns):
		var yy := 1.0 - 2.0 * (i + 0.5) / ns
		var rr := sqrt(1.0 - yy * yy)
		var th := PI * (3.0 - sqrt(5.0)) * i
		seeds.append(Vector3(cos(th) * rr, sin(th) * rr, yy) * 1.3)
	for j in range(3):
		for i in range(3):
			seeds.append(Vector3(-1.2 + i * 1.2, -1.2 + j * 1.2, slice_z))
	for sd in seeds:
		var pts := streamline(sd)
		if pts.size() >= 3:
			stream_node.add_child(_colored_tube(pts, 0.01))

func _build_particles() -> void:
	particles.visible = show_particles
	var sh := Shader.new()
	var names := {"x": "x", "y": "y", "z": "z"}
	sh.code = PARTICLE_SHADER.replace("/*PRELUDE*/", MathExpr.GLSL_PRELUDE).replace("/*P*/", P.to_glsl(names)).replace("/*Q*/", Q.to_glsl(names)).replace("/*R*/", R.to_glsl(names)).replace("/*PHI*/", PHI.to_glsl(names))
	var pm := ShaderMaterial.new()
	pm.shader = sh
	pm.set_shader_parameter("speed", particle_speed)
	pm.set_shader_parameter("s", S)
	pm.set_shader_parameter("offset", global_position if is_inside_tree() else OFFSET)
	pm.set_shader_parameter("fmax", fmax)
	pm.set_shader_parameter("grad_mode", grad_mode)
	particles.process_material = pm
	particles.restart()

func _build_div_curl() -> void:
	var n := 5
	var spacing := 4.0 / n
	var pts := []
	for k in range(n):
		for j in range(n):
			for i in range(n):
				pts.append(Vector3(-2 + (i + 0.5) * spacing, -2 + (j + 0.5) * spacing, -2 + (k + 0.5) * spacing))
	var dmax := 1e-9
	var cmax := 1e-9
	var divs := []
	var curls := []
	for p in pts:
		var d := divergence(p)
		var c := curl(p)
		divs.append(d)
		curls.append(c)
		if is_finite(d): dmax = maxf(dmax, absf(d))
		if c.is_finite(): cmax = maxf(cmax, c.length())
	div_mm.visible = show_div
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 16
	sm.rings = 8
	mm.mesh = sm
	mm.instance_count = pts.size()
	for i in range(pts.size()):
		var d: float = divs[i] if is_finite(divs[i]) else 0.0
		var sc := 0.02 + 0.22 * sqrt(absf(d) / dmax)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * sc * S), to_world(pts[i].x, pts[i].y, pts[i].z)))
		mm.set_instance_color(i, Color(1.0, 0.25, 0.2, 0.75) if d > 0 else Color(0.2, 0.5, 1.0, 0.75))
	div_mm.multimesh = mm
	var dm := StandardMaterial3D.new()
	dm.vertex_color_use_as_albedo = true
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.emission_enabled = true
	dm.emission = Color(0.3, 0.3, 0.3)
	dm.roughness = 0.2
	div_mm.material_override = dm
	# Ruedas de paletas (rotacional).
	curl_mm.visible = show_curl
	curl_data.clear()
	var wm := MultiMesh.new()
	wm.transform_format = MultiMesh.TRANSFORM_3D
	wm.use_colors = true
	wm.mesh = _paddle_mesh()
	wm.instance_count = pts.size()
	for i in range(pts.size()):
		var c: Vector3 = curls[i] if (curls[i] as Vector3).is_finite() else Vector3.ZERO
		var axis := _wv(c).normalized() if c.length() > 1e-6 else Vector3.UP
		curl_data.append([to_world(pts[i].x, pts[i].y, pts[i].z), axis, c.length() * 0.5, 0.18 * S * clampf(0.4 + c.length() / cmax, 0.4, 1.4) if c.length() > 1e-6 else 0.0])
		wm.set_instance_color(i, Color(0.9, 0.95, 1.0).lerp(Color(1.0, 0.8, 0.2), clampf(c.length() / cmax, 0.0, 1.0)))
	curl_mm.multimesh = wm
	var wmat := StandardMaterial3D.new()
	wmat.vertex_color_use_as_albedo = true
	wmat.emission_enabled = true
	wmat.emission = Color(0.4, 0.4, 0.35)
	wmat.metallic = 0.5
	wmat.roughness = 0.3
	curl_mm.material_override = wmat
	_update_paddles(0.0)

static func _paddle_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blades := 4
	for b in range(blades):
		var a := TAU * b / blades
		var d := Vector3(cos(a), 0, sin(a))
		var side := Vector3(0, 1, 0)
		var p0 := d * 0.1
		var p1 := d * 1.0
		var w := 0.35
		for q in [p0 - side * w, p1 - side * w, p1 + side * w, p0 - side * w, p1 + side * w, p0 + side * w]:
			st.set_normal(d.cross(side).normalized())
			st.add_vertex(q)
	# Eje.
	for k in range(6):
		var a0 := TAU * k / 6
		var a1 := TAU * (k + 1) / 6
		var d0 := Vector3(cos(a0), 0, sin(a0)) * 0.06
		var d1 := Vector3(cos(a1), 0, sin(a1)) * 0.06
		for q in [d0 + Vector3(0, -0.9, 0), d1 + Vector3(0, -0.9, 0), d1 + Vector3(0, 0.9, 0), d0 + Vector3(0, -0.9, 0), d1 + Vector3(0, 0.9, 0), d0 + Vector3(0, 0.9, 0)]:
			st.set_normal(Vector3(q.x, 0, q.z).normalized())
			st.add_vertex(q)
	return st.commit()

func _update_paddles(t: float) -> void:
	if curl_mm.multimesh == null:
		return
	for i in range(curl_data.size()):
		var d: Array = curl_data[i]
		var axis: Vector3 = d[1]
		var base := Basis(Quaternion(Vector3.UP, axis)) if absf(axis.dot(Vector3.UP)) < 0.9999 else (Basis.IDENTITY if axis.y > 0 else Basis(Vector3.RIGHT, PI))
		var b := base * Basis(Vector3.UP, float(d[2]) * t) * Basis.from_scale(Vector3.ONE * float(d[3]))
		curl_mm.multimesh.set_instance_transform(i, Transform3D(b, d[0]))

func _jacobian(p: Vector3) -> Array:
	var h := 1e-4
	var J := []
	for r in range(3):
		J.append([0.0, 0.0, 0.0])
	for c in range(3):
		var e := Vector3.ZERO
		e[c] = h
		var d := (F(p + e) - F(p - e)) / (2.0 * h)
		for r in range(3):
			J[r][c] = d[r]
	return J

func _find_equilibria() -> void:
	equilibria.clear()
	eq_line = false
	for c in eq_node.get_children():
		c.queue_free()
	for k in range(4):
		for j in range(4):
			for i in range(4):
				var p := Vector3(-1.5 + i, -1.5 + j, -1.5 + k)
				for it in range(25):
					var J := _jacobian(p)
					var fv := F(p)
					var sol = _solve3(J, -fv)
					if sol == null: break
					p += sol
					if not p.is_finite() or p.length() > 4: break
				if p.is_finite() and absf(p.x) <= 2 and absf(p.y) <= 2 and absf(p.z) <= 2 and F(p).length() < 1e-6:
					var Jp := _jacobian(p)
					var detp := Basis(Vector3(Jp[0][0], Jp[1][0], Jp[2][0]), Vector3(Jp[0][1], Jp[1][1], Jp[2][1]), Vector3(Jp[0][2], Jp[1][2], Jp[2][2])).determinant()
					if absf(detp) < 1e-9:
						eq_line = true
						continue
					var dup := false
					for e in equilibria:
						if (e[0] as Vector3).distance_to(p) < 1e-3: dup = true
					if not dup:
						equilibria.append([p, _classify(_jacobian(p))])
	for e in equilibria:
		var s := sphere(0.06, glow_mat(Color(1, 1, 1), 3.5))
		s.position = to_world(e[0].x, e[0].y, e[0].z)
		eq_node.add_child(s)
		eq_node.add_child(label3d(e[1], s.position + Vector3(0, 0.22, 0), Color(1, 1, 1), 0.0028))

static func _solve3(J: Array, b: Vector3):
	var m := Basis(Vector3(J[0][0], J[1][0], J[2][0]), Vector3(J[0][1], J[1][1], J[2][1]), Vector3(J[0][2], J[1][2], J[2][2]))
	if absf(m.determinant()) < 1e-12:
		return null
	return m.inverse() * b

## Clasificación por los autovalores del jacobiano (raíces del polinomio característico).
func _classify(J: Array) -> String:
	var tr: float = J[0][0] + J[1][1] + J[2][2]
	var m2: float = J[0][0] * J[1][1] - J[0][1] * J[1][0] + J[0][0] * J[2][2] - J[0][2] * J[2][0] + J[1][1] * J[2][2] - J[1][2] * J[2][1]
	var det: float = Basis(Vector3(J[0][0], J[1][0], J[2][0]), Vector3(J[0][1], J[1][1], J[2][1]), Vector3(J[0][2], J[1][2], J[2][2])).determinant()
	# λ³ − tr λ² + m2 λ − det = 0 → discriminante para saber si hay raíces complejas.
	var a := -tr
	var b := m2
	var c := -det
	var p := b - a * a / 3.0
	var q := 2.0 * a * a * a / 27.0 - a * b / 3.0 + c
	var disc := q * q / 4.0 + p * p * p / 27.0
	var complex_roots := disc > 1e-12
	if absf(det) < 1e-9 and absf(tr) < 1e-9:
		return "equilibrio degenerado"
	if complex_roots:
		if absf(tr) < 1e-6: return "centro (giro puro)"
		return "espiral " + ("inestable" if tr > 0 else "estable")
	if det > 0 and tr > 0 and m2 > 0: return "fuente (inestable)"
	if det < 0 and tr < 0 and m2 > 0: return "sumidero (estable)"
	return "punto de silla"

func step(dt: float) -> void:
	_t += dt
	if show_curl:
		_update_paddles(_t)

func build_ui(p: VBoxContainer) -> void:
	var names := []
	for q in PRESETS: names.append(q[0])
	LabUI.option(p, "Campo:", names, preset, func(i):
		preset = i
		grad_mode = false
		_load(i))
	LabUI.expr_field(p, "P(x, y, z) =", PRESETS[preset][1], ["x", "y", "z"], false, func(m): _set_field(m, Q, R))
	LabUI.expr_field(p, "Q(x, y, z) =", PRESETS[preset][2], ["x", "y", "z"], false, func(m): _set_field(P, m, R))
	LabUI.expr_field(p, "R(x, y, z) =", PRESETS[preset][3], ["x", "y", "z"], false, func(m): _set_field(P, Q, m))
	LabUI.check(p, "Usar gradiente F = ∇φ", grad_mode, func(v):
		grad_mode = v
		_rebuild())
	LabUI.expr_field(p, "φ(x, y, z) =", "x^2 - y^2 + 0.5z^2", ["x", "y", "z"], false, func(m):
		PHI = m
		PHI.compile_fast()
		if grad_mode: _rebuild())
	LabUI.section(p, "Visualización")
	LabUI.check(p, "Flechas", show_arrows, func(v):
		show_arrows = v
		arrows.visible = v)
	LabUI.slider(p, "Densidad de flechas n³", 3, 12, 1, density, func(v):
		density = int(v)
		_build_arrows(), "%.0f")
	LabUI.check(p, "Longitud normalizada (campo de direcciones)", normalize_len, func(v):
		normalize_len = v
		_build_arrows())
	LabUI.check(p, "Líneas de corriente (RK4)", show_stream, func(v):
		show_stream = v
		_build_streamlines())
	LabUI.check(p, "Partículas con estela (GPU)", show_particles, func(v):
		show_particles = v
		particles.visible = v)
	LabUI.slider(p, "Velocidad de las partículas", 0.05, 2.0, 0.05, particle_speed, func(v):
		particle_speed = v
		(particles.process_material as ShaderMaterial).set_shader_parameter("speed", v))
	LabUI.check(p, "Divergencia (esferas: rojo fuente, azul sumidero)", show_div, func(v):
		show_div = v
		div_mm.visible = v)
	LabUI.check(p, "Rotacional (ruedas de paletas)", show_curl, func(v):
		show_curl = v
		curl_mm.visible = v)
	LabUI.slider(p, "Plano de muestra z = c", -2.0, 2.0, 0.05, slice_z, func(v):
		slice_z = v
		slice.position = to_world(0, 0, v))
	LabUI.note(p, "Una rueda de paletas colocada en el fluido gira con velocidad angular ½|∇×F| alrededor del eje ∇×F: en el vórtice gira; en el campo de un hilo (fuera del eje) no gira, aunque las líneas sean círculos.")

func pick(origin: Vector3, dir: Vector3):
	var lo := to_local(origin)
	var ld := (to_local(origin + dir) - lo).normalized()
	var h := to_world(0, 0, slice_z).y
	var hit = ray_plane_y(lo, ld, h)
	if hit == null or absf(hit.x) > 2 * S or absf(hit.z) > 2 * S:
		return null
	return to_global(hit)

func hover_text(hit: Vector3) -> String:
	var m := to_math(to_local(hit))
	var v := F(m)
	var c := curl(m)
	return "(x, y, z) = (%.2f, %.2f, %.2f)\nF = (%.3f, %.3f, %.3f)   |F| = %.3f\n∇·F = %.3f\n∇×F = (%.2f, %.2f, %.2f)" % [m.x, m.y, m.z, v.x, v.y, v.z, v.length(), divergence(m), c.x, c.y, c.z]

func perturb(hit: Vector3, first: bool) -> void:
	if not first:
		return
	var m := to_math(to_local(hit))
	var pts := streamline(m, 300)
	if pts.size() >= 3:
		var t := _colored_tube(pts, 0.018)
		stream_node.add_child(t)
		stream_node.visible = true

func critical_points() -> Array:
	var out := []
	for e in equilibria:
		out.append({"pos": to_global(to_world(e[0].x, e[0].y, e[0].z)), "nombre": "Equilibrio F = 0: %s" % e[1], "dist": 2.2})
	return out

func info() -> String:
	var t := "F = (%s, %s, %s)%s\n" % [P.source, Q.source, R.source, "  [∇φ, φ = %s]" % PHI.source if grad_mode else ""]
	t += "|F| de referencia (p90) = %.3f · ∇·F(0) = %.3f · |∇×F(0)| = %.3f\n" % [fmax, divergence(Vector3.ZERO), curl(Vector3.ZERO).length()]
	var eqs := []
	for e in equilibria: eqs.append("(%.2f, %.2f, %.2f) %s" % [e[0].x, e[0].y, e[0].z, e[1]])
	t += "Equilibrios: %s%s" % [", ".join(PackedStringArray(eqs)) if not eqs.is_empty() else "—", " · hay equilibrios no aislados (una recta o superficie de puntos con F = 0)" if eq_line else ""]
	return t
