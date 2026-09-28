extends LabModule
## Coloreado de dominio 3D de w = f(z): la altura es |f(z)| (escala logarítmica
## acotada) y el color es la fase arg f(z) (rueda cromática). Curvas de módulo
## constante (log₂|f|) y de fase constante realzan la estructura. Los ceros y
## polos se detectan automáticamente y se clasifican por su número de vueltas
## (índice): +k = cero de orden k, −k = polo de orden k. Los cortes de rama de
## log y √ aparecen como saltos de color.

const SIZE := 4.0
const PRESETS := [
	["z³ − 1 (raíces de la unidad)", "z^3 - 1"],
	["(z² − 1)/(z² + 1)", "(z^2 - 1)/(z^2 + 1)"],
	["(z − 1)/(z + 1)² (polo doble)", "(z - 1)/(z + 1)^2"],
	["z⁵ − z", "z^5 - z"],
	["sin(z)", "sin(z)"],
	["exp(1/z) (singularidad esencial)", "exp(1/z)"],
	["log(z) (corte de rama)", "log(z)"],
	["√(z² − 1) (dos puntos de rama)", "sqrt(z^2 - 1)"],
	["(z² + i)/(z³ − 2)", "(z^2 + i)/(z^3 - 2)"],
]

const TEMPLATE := """
shader_type spatial;
render_mode cull_disabled;
#include "res://mathlab/shaders/common.gdshaderinc"
/*PRELUDE*/
uniform float R = 2.5;
uniform float world_size = 4.0;
uniform float height = 1.3;
uniform int hmode = 0;
uniform float hcap = 4.0;
uniform bool enhanced = true;
uniform bool phase_lines = true;
uniform bool zgrid = false;
varying vec3 wpos;

vec2 FZ(vec2 z) { return /*EXPR*/; }

float Hf(vec2 w) {
	float m = length(w);
	if (hmode == 2) return 0.0;
	if (hmode == 1) return clamp(m / hcap, 0.0, 1.0);
	return clamp(log(1.0 + m) / log(1.0 + hcap), 0.0, 1.0);
}

vec2 zof(vec2 uv) { return vec2(mix(-R, R, uv.x), mix(R, -R, uv.y)); }

void vertex() {
	vec2 z = zof(UV);
	float h = Hf(FZ(z)) * height;
	VERTEX.y = h;
	float e = 2.0 * R / 300.0;
	float hx = (Hf(FZ(z + vec2(e, 0.0))) - Hf(FZ(z - vec2(e, 0.0)))) * height;
	float hy = (Hf(FZ(z + vec2(0.0, e))) - Hf(FZ(z - vec2(0.0, e)))) * height;
	float wstep = 2.0 * e / (2.0 * R) * world_size;
	NORMAL = normalize(vec3(-hx / wstep, 1.0, hy / wstep));
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (clipped(wpos)) discard;
	vec2 z = zof(UV);
	vec2 w = FZ(z);
	float ph = atan(w.y, w.x);
	vec3 col = hue_color(ph);
	float m = length(w);
	if (enhanced) {
		float lm = log2(max(m, 1e-12));
		float band = fract(lm);
		col *= 0.62 + 0.38 * band;
	}
	if (phase_lines) {
		float pl = iso_lines(ph, 3.14159265 / 6.0, 0.9);
		col = mix(col, vec3(0.03), pl * 0.45);
	}
	if (zgrid) {
		float g = grid_lines(z, 0.5, 0.8);
		col = mix(col, vec3(1.0), g * 0.35);
	}
	// Ceros → negro, polos → blanco (como en los retratos de fase clásicos).
	col = mix(col, vec3(0.0), smoothstep(0.06, 0.0, m));
	col = mix(col, vec3(1.0), smoothstep(40.0, 400.0, m) * 0.7);
	ALBEDO = col;
	ROUGHNESS = 0.3;
	SPECULAR = 0.6;
	CLEARCOAT = 0.4;
	EMISSION = col * 0.18 + vec3(0.2, 0.9, 1.0) * clip_edge(wpos) * 2.0;
}
"""

var expr: MathExpr
var preset: int = 1
var R: float = 2.5
var mesh: MeshInstance3D
var mat: ShaderMaterial
var markers: Node3D
var zeros: Array = []      # [[z, orden]]
var poles: Array = []
var hmode: int = 0

func title() -> String: return "Coloreado de dominio"
func formula() -> String: return "w = f(z) · altura ∝ log(1 + |f|) · color = arg f(z) ∈ (−π, π]"
func perturb_hint() -> String: return "clic: centra la vista en ese punto del plano complejo"
func view() -> Dictionary: return {"target": Vector3(0, 0.3, 0), "dist": 7.0, "yaw": -25.0, "pitch": -45.0}

func setup() -> void:
	scale_xy = SIZE / (2.0 * R)
	mesh = MeshInstance3D.new()
	mesh.mesh = SurfaceShader.plane(SIZE, 300)
	add_child(mesh)
	markers = Node3D.new()
	add_child(markers)
	_set_expr(MathExpr.parse(PRESETS[preset][1], ["z"], true))

func _set_expr(m: MathExpr) -> void:
	expr = m
	var sh := Shader.new()
	sh.code = TEMPLATE.replace("/*PRELUDE*/", MathExpr.GLSL_PRELUDE).replace("/*EXPR*/", m.to_glsl_complex({"z": "z"}))
	mat = ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("R", R)
	mat.set_shader_parameter("world_size", SIZE)
	mat.set_shader_parameter("hmode", hmode)
	mesh.material_override = mat
	clip_materials.clear()
	register_clip(mat)
	_find_singularities()

func f(z: Vector2) -> Vector2:
	return expr.eval_c({"z": z})

func _winding(z0: Vector2, r: float) -> int:
	var total := 0.0
	var prev := f(z0 + Vector2(r, 0))
	var n := 96
	for k in range(1, n + 1):
		var a := TAU * k / n
		var cur := f(z0 + Vector2(cos(a), sin(a)) * r)
		var d := atan2(prev.x * cur.y - prev.y * cur.x, prev.dot(cur))
		total += d
		prev = cur
	return int(round(total / TAU))

func _find_singularities() -> void:
	zeros.clear()
	poles.clear()
	var n := 80
	var grid := []
	for j in range(n + 1):
		var row := []
		for i in range(n + 1):
			var z := Vector2(lerpf(-R, R, float(i) / n), lerpf(-R, R, float(j) / n))
			var m := f(z).length()
			row.append(m if is_finite(m) else 1e12)
		grid.append(row)
	var cand_z := []
	var cand_p := []
	for j in range(1, n):
		for i in range(1, n):
			var v: float = grid[j][i]
			var is_min := true
			var is_max := true
			for dj in [-1, 0, 1]:
				for di in [-1, 0, 1]:
					if di == 0 and dj == 0: continue
					var w: float = grid[j + dj][i + di]
					if w < v: is_min = false
					if w > v: is_max = false
			var z := Vector2(lerpf(-R, R, float(i) / n), lerpf(-R, R, float(j) / n))
			if is_min: cand_z.append(z)
			if is_max: cand_p.append(z)
	for z0 in cand_z:
		var z: Vector2 = z0
		for k in range(40):
			var fz := f(z)
			var h := 1e-6
			var d := (f(z + Vector2(h, 0)) - f(z - Vector2(h, 0))) / (2 * h)
			if d.length() < 1e-14: break
			z -= MathExpr.cdiv(fz, d)
			if not z.is_finite(): break
		if z.is_finite() and f(z).length() < 2e-5 and absf(z.x) <= R and absf(z.y) <= R and not _near(zeros, z):
			zeros.append([z, maxi(1, _winding(z, 0.03))])
	for z0 in cand_p:
		var z2: Vector2 = z0
		var ok := false
		var f0 := f(z2)
		if not f0.is_finite() or f0.length() > 1e12:
			ok = true              # la muestra cae justo en el polo (f = ∞)
		for k in range(0 if ok else 40):
			var g := MathExpr.cdiv(Vector2(1, 0), f(z2))
			if g.length() < 2e-6:
				ok = true
				break
			var h2 := 1e-6
			var gd := (MathExpr.cdiv(Vector2(1, 0), f(z2 + Vector2(h2, 0))) - MathExpr.cdiv(Vector2(1, 0), f(z2 - Vector2(h2, 0)))) / (2 * h2)
			if gd.length() < 1e-14: break
			z2 -= MathExpr.cdiv(g, gd)
			if not z2.is_finite(): break
		if (ok or (z2.is_finite() and f(z2).length() > 1e5)) and absf(z2.x) <= R and absf(z2.y) <= R and not _near(poles, z2):
			var w := _winding(z2, 0.03)
			if w < 0:
				poles.append([z2, -w])
	_draw_markers()

func _near(list: Array, z: Vector2) -> bool:
	for e in list:
		if (e[0] as Vector2).distance_to(z) < 1e-3:
			return true
	return false

func _zw(z: Vector2, h: float = 0.0) -> Vector3:
	return Vector3(z.x * scale_xy, h, -z.y * scale_xy)

func _draw_markers() -> void:
	for c in markers.get_children():
		c.queue_free()
	for e in zeros:
		var z: Vector2 = e[0]
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.05
		tm.outer_radius = 0.075
		ring.mesh = tm
		ring.material_override = glow_mat(Color(1, 1, 1), 3.0)
		ring.position = _zw(z, 0.01)
		markers.add_child(ring)
		markers.add_child(label3d("cero%s\n%s" % [" ×%d" % e[1] if e[1] > 1 else "", _cstr(z)], _zw(z, 0.35), Color(1, 1, 1), 0.0028))
	for e in poles:
		var z2: Vector2 = e[0]
		markers.add_child(rod(_zw(z2, 0.0), _zw(z2, 1.9), 0.012, glow_mat(Color(1.0, 0.3, 0.25), 2.5)))
		markers.add_child(label3d("polo%s\n%s" % [" ×%d" % e[1] if e[1] > 1 else "", _cstr(z2)], _zw(z2, 2.1), Color(1.0, 0.45, 0.4), 0.0028))
	var src := expr.source
	if "log" in src or "sqrt" in src or "ln" in src:
		markers.add_child(label3d("corte de rama (salto de fase)", _zw(Vector2(-R * 0.6, 0.12), 0.05), Color(1.0, 0.8, 0.3), 0.003))

static func _cstr(z: Vector2) -> String:
	return "%.3f %s %.3fi" % [z.x, "+" if z.y >= 0.0 else "−", absf(z.y)]

func build_ui(p: VBoxContainer) -> void:
	var names := []
	for q in PRESETS: names.append(q[0])
	LabUI.option(p, "Función:", names, preset, func(i):
		preset = i
		_set_expr(MathExpr.parse(PRESETS[i][1], ["z"], true)))
	LabUI.expr_field(p, "f(z) =  (usa z, i, exp, log, sin, sqrt…)", PRESETS[preset][1], ["z"], true, func(m): _set_expr(m))
	LabUI.option(p, "Altura:", ["log(1 + |f|)", "|f| (acotado)", "Plano (solo color)"], hmode, func(i):
		hmode = i
		mat.set_shader_parameter("hmode", i))
	LabUI.slider(p, "Tope de altura |f|", 1.0, 30.0, 0.5, 4.0, func(v): mat.set_shader_parameter("hcap", v), "%.1f")
	LabUI.slider(p, "Región |Re z|, |Im z| ≤ R", 0.5, 8.0, 0.1, R, func(v):
		R = v
		scale_xy = SIZE / (2.0 * R)
		mat.set_shader_parameter("R", R)
		_find_singularities())
	LabUI.check(p, "Curvas de módulo (log₂|f|)", true, func(v): mat.set_shader_parameter("enhanced", v))
	LabUI.check(p, "Líneas de fase cada 30°", true, func(v): mat.set_shader_parameter("phase_lines", v))
	LabUI.check(p, "Rejilla del plano z", false, func(v): mat.set_shader_parameter("zgrid", v))
	LabUI.note(p, "Alrededor de un cero de orden k los colores giran k veces en sentido antihorario; alrededor de un polo, en sentido horario. Un salto brusco de color que no rodea un punto es un corte de rama.")

func pick(origin: Vector3, dir: Vector3):
	var hf := func(X: float, Z: float) -> float:
		var z := Vector2(X / scale_xy, -Z / scale_xy)
		var m := f(z).length()
		if not is_finite(m): m = 1e9
		var cap: float = mat.get_shader_parameter("hcap") if mat.get_shader_parameter("hcap") != null else 4.0
		if hmode == 2: return 0.0
		if hmode == 1: return clampf(m / cap, 0.0, 1.0) * 1.3
		return clampf(log(1.0 + m) / log(1.0 + cap), 0.0, 1.0) * 1.3
	return ray_heightfield(origin, dir, hf, SIZE * 0.5)

func hover_text(hit: Vector3) -> String:
	var z := Vector2(hit.x / scale_xy, -hit.z / scale_xy)
	var w := f(z)
	return "z = %s\nf(z) = %s\n|f| = %.4f   arg f = %.1f°" % [_cstr(z), _cstr(w), w.length(), rad_to_deg(atan2(w.y, w.x))]

func perturb(hit: Vector3, first: bool) -> void:
	if first:
		lab.cam.frame(Vector3(hit.x, hit.y, hit.z), lab.cam.distance * 0.7)

func critical_points() -> Array:
	var out := []
	for e in zeros:
		out.append({"pos": _zw(e[0]), "nombre": "Cero de orden %d en %s" % [e[1], _cstr(e[0])], "dist": 1.8})
	for e in poles:
		out.append({"pos": _zw(e[0], 0.8), "nombre": "Polo de orden %d en %s" % [e[1], _cstr(e[0])], "dist": 2.2})
	return out

func info() -> String:
	var zs := []
	for e in zeros: zs.append("%s%s" % [_cstr(e[0]), " (×%d)" % e[1] if e[1] > 1 else ""])
	var ps := []
	for e in poles: ps.append("%s%s" % [_cstr(e[0]), " (×%d)" % e[1] if e[1] > 1 else ""])
	return "f(z) = %s\nCeros: %s\nPolos: %s" % [expr.source, ", ".join(PackedStringArray(zs)) if not zs.is_empty() else "—", ", ".join(PackedStringArray(ps)) if not ps.is_empty() else "—"]
