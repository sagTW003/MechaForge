extends LabModule
## Mapeos conformes: una rejilla del plano z se transforma en su imagen w = f(z)
## con una animación continua (la interpolación se hace en el shader de vértices:
## cada vértice guarda su posición en z y en w). Las dos familias de líneas se
## siguen cortando en ángulo recto allí donde f′(z) ≠ 0 (conformidad); en los
## puntos críticos (f′ = 0) los ángulos se multiplican.

const S := 0.9
const PRESETS := [
	["eᶻ (rectas → rayos y círculos)", "exp(z)", 0],
	["z² (duplica ángulos)", "z^2", 0],
	["1/z (inversión)", "1/z", 1],
	["Joukowsky z + 1/z (perfil alar)", "z + 1/z", 2],
	["Möbius (z − i)/(z + i)", "(z - i)/(z + i)", 0],
	["sin z", "sin(z)", 0],
	["log z (polar → cartesiana)", "log(z)", 1],
	["z³", "z^3", 1],
]
const GRIDS := ["Cartesiana", "Polar", "Círculo desplazado (Joukowsky)"]

const SHADER := """
shader_type spatial;
render_mode cull_disabled;
#include "res://mathlab/shaders/common.gdshaderinc"
uniform float morph = 0.0;
varying vec3 wpos;
void vertex() {
	float s = morph * morph * (3.0 - 2.0 * morph);
	VERTEX = mix(VERTEX, CUSTOM0.xyz, s);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	if (clipped(wpos)) discard;
	ALBEDO = COLOR.rgb;
	EMISSION = COLOR.rgb * 1.6;
	ROUGHNESS = 0.4;
}
"""

var expr: MathExpr
var preset: int = 3
var grid: int = 2
var nlines: int = 16
var morph: float = 1.0
var animating: bool = false
var _dir: float = 1.0
var lines: MeshInstance3D
var mat: ShaderMaterial
var crit_node: Node3D
var crit: Array = []           # [[z, w]] puntos críticos f′(z) = 0 y su imagen

func title() -> String: return "Mapeos conformes"
func formula() -> String: return "w = f(z) analítica, f′(z) ≠ 0 ⇒ conserva ángulos"
func uses_time() -> bool: return true
func perturb_hint() -> String: return "clic: invierte la animación z ⇄ w"
func view() -> Dictionary: return {"target": Vector3(0, 0, 0), "dist": 7.5, "yaw": 0.0, "pitch": -62.0}

func setup() -> void:
	scale_xy = S
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(9, 9)
	plane.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.02, 0.03, 0.05)
	pmat.roughness = 0.7
	pmat.metallic = 0.05
	plane.material_override = pmat
	plane.position = Vector3(0, -0.02, 0)
	add_child(plane)
	add_child(arrow(Vector3(-4.3, 0, 0), Vector3(4.4, 0, 0), 0.008, glow_mat(Color(0.7, 0.75, 0.85), 0.7)))
	add_child(arrow(Vector3(0, 0, 4.3), Vector3(0, 0, -4.4), 0.008, glow_mat(Color(0.7, 0.75, 0.85), 0.7)))
	add_child(label3d("Re", Vector3(4.55, 0.05, 0), Color(0.8, 0.85, 0.95), 0.003))
	add_child(label3d("Im", Vector3(0, 0.05, -4.55), Color(0.8, 0.85, 0.95), 0.003))
	lines = MeshInstance3D.new()
	add_child(lines)
	mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	mat.shader = sh
	lines.material_override = mat
	register_clip(mat)
	crit_node = Node3D.new()
	add_child(crit_node)
	expr = MathExpr.parse(PRESETS[preset][1], ["z"], true)
	grid = PRESETS[preset][2]
	_build()

func f(z: Vector2) -> Vector2:
	return expr.eval_c({"z": z})

func _zw(z: Vector2) -> Vector3:
	return Vector3(z.x * S, 0.01, -z.y * S)

func _families() -> Array:
	# Cada familia: [color, [curvas]] con curvas = listas de z.
	var fam_a := []
	var fam_b := []
	var ns := 180
	match grid:
		0:
			var X := PI if preset == 0 or preset == 5 else 2.0
			for i in range(nlines + 1):
				var v := lerpf(-X, X, float(i) / nlines)
				var ha := []
				var vb := []
				for k in range(ns + 1):
					var u := lerpf(-X, X, float(k) / ns)
					ha.append(Vector2(u * (1.5 / X if preset == 0 else 1.0), v))
					vb.append(Vector2(v * (1.5 / X if preset == 0 else 1.0), u))
				fam_a.append(ha)
				fam_b.append(vb)
		1:
			for i in range(1, nlines + 1):
				var r := 2.2 * float(i) / nlines
				var c := []
				for k in range(ns + 1):
					var a := TAU * float(k) / ns
					c.append(Vector2(cos(a), sin(a)) * r)
				fam_a.append(c)
			for i in range(nlines * 2):
				var a2 := TAU * float(i) / (nlines * 2) + 0.001
				var ray := []
				for k in range(1, ns + 1):
					ray.append(Vector2(cos(a2), sin(a2)) * 2.2 * float(k) / ns)
				fam_b.append(ray)
		2:
			var c0 := Vector2(-0.12, 0.1)
			var a0 := (Vector2(1, 0) - c0).length()
			for i in range(nlines):
				var r2 := a0 * (1.0 + 1.4 * float(i) / nlines)
				var cc := []
				for k in range(ns + 1):
					var a3 := TAU * float(k) / ns
					cc.append(c0 + Vector2(cos(a3), sin(a3)) * r2)
				fam_a.append(cc)
			for i in range(nlines * 2):
				var a4 := TAU * float(i) / (nlines * 2) + 0.001
				var ray2 := []
				for k in range(ns + 1):
					ray2.append(c0 + Vector2(cos(a4), sin(a4)) * a0 * (1.0 + 1.4 * float(k) / ns))
				fam_b.append(ray2)
	return [[Color(0.2, 0.85, 1.0), fam_a], [Color(1.0, 0.55, 0.15), fam_b]]

func _build() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGB_FLOAT)
	var hw := 0.012
	for fam in _families():
		var col: Color = fam[0]
		for curve in fam[1]:
			var zs: Array = curve
			var seg_z := []
			var seg_w := []
			for z in zs:
				var w := f(z)
				var ok: bool = w.is_finite() and w.length() < 12.0
				if ok and not seg_w.is_empty() and (seg_w[seg_w.size() - 1] as Vector2).distance_to(w) > 1.5:
					ok = false
				if not ok:
					_ribbon(st, seg_z, seg_w, col, hw)
					seg_z = []
					seg_w = []
					if w.is_finite() and w.length() < 12.0:
						seg_z.append(z)
						seg_w.append(w)
					continue
				seg_z.append(z)
				seg_w.append(w)
			_ribbon(st, seg_z, seg_w, col, hw)
	lines.mesh = st.commit()
	mat.set_shader_parameter("morph", morph)
	_crit_points()

func _ribbon(st: SurfaceTool, zs: Array, ws: Array, col: Color, hw: float) -> void:
	if zs.size() < 2:
		return
	var n := zs.size()
	var prev_a := Vector3.ZERO
	var prev_b := Vector3.ZERO
	var prev_ca := Vector3.ZERO
	var prev_cb := Vector3.ZERO
	for i in range(n):
		var pz := _zw(zs[i])
		var pw := _zw(ws[i])
		var tz := (_zw(zs[mini(i + 1, n - 1)]) - _zw(zs[maxi(i - 1, 0)])).normalized()
		var tw := (_zw(ws[mini(i + 1, n - 1)]) - _zw(ws[maxi(i - 1, 0)])).normalized()
		var oz := Vector3(-tz.z, 0, tz.x) * hw
		var ow := Vector3(-tw.z, 0, tw.x) * hw
		var a := pz + oz
		var b := pz - oz
		var ca := pw + ow
		var cb := pw - ow
		if i > 0:
			for q in [[prev_a, prev_ca], [prev_b, prev_cb], [b, cb], [prev_a, prev_ca], [b, cb], [a, ca]]:
				st.set_color(col)
				st.set_normal(Vector3.UP)
				st.set_custom(0, Color(q[1].x, q[1].y, q[1].z))
				st.add_vertex(q[0])
		prev_a = a
		prev_b = b
		prev_ca = ca
		prev_cb = cb

func _crit_points() -> void:
	for c in crit_node.get_children():
		c.queue_free()
	# f′(z) = 0 en la región (Newton sobre f′ numérica desde una rejilla).
	var found := []
	for j in range(9):
		for i in range(9):
			var z := Vector2(lerpf(-2.2, 2.2, i / 8.0), lerpf(-2.2, 2.2, j / 8.0))
			for k in range(30):
				var h := 2e-3
				var d := (f(z + Vector2(h, 0)) - f(z - Vector2(h, 0))) / (2 * h)
				var d2 := (f(z + Vector2(h, 0)) - 2.0 * f(z) + f(z - Vector2(h, 0))) / (h * h)
				if d2.length() < 1e-10: break
				z -= MathExpr.cdiv(d, d2)
				if not z.is_finite() or z.length() > 5: break
			if z.is_finite() and z.length() <= 2.3:
				var h2 := 2e-3
				var dd := (f(z + Vector2(h2, 0)) - f(z - Vector2(h2, 0))) / (2 * h2)
				if dd.length() < 2e-3:
					var dup := false
					for q in found:
						if (q as Vector2).distance_to(z) < 1e-3: dup = true
					if not dup: found.append(z)
	crit.clear()
	for z in found:
		var s := sphere(0.06, glow_mat(Color(1.0, 0.25, 0.6), 3.0))
		crit_node.add_child(s)
		var l := label3d("f′(z) = 0", Vector3.ZERO, Color(1.0, 0.5, 0.75), 0.0028)
		crit_node.add_child(l)
		crit.append([z, f(z), s, l])
	_place_crit()

## Los puntos críticos se desplazan con la deformación z → f(z).
func _place_crit() -> void:
	var sm := morph * morph * (3.0 - 2.0 * morph)
	for c in crit:
		var p := _zw(c[0]).lerp(_zw(c[1]), sm)
		(c[2] as Node3D).position = p
		(c[3] as Node3D).position = p + Vector3(0, 0.25, 0)

func step(dt: float) -> void:
	if not animating:
		return
	morph = clampf(morph + _dir * dt / 2.5, 0.0, 1.0)
	if morph <= 0.0 or morph >= 1.0:
		_dir = -_dir
	mat.set_shader_parameter("morph", morph)
	_place_crit()

func build_ui(p: VBoxContainer) -> void:
	var names := []
	for q in PRESETS: names.append(q[0])
	LabUI.option(p, "Mapeo:", names, preset, func(i):
		preset = i
		expr = MathExpr.parse(PRESETS[i][1], ["z"], true)
		grid = PRESETS[i][2]
		_build())
	LabUI.expr_field(p, "w = f(z) =", PRESETS[preset][1], ["z"], true, func(m):
		expr = m
		_build())
	LabUI.option(p, "Rejilla de partida:", GRIDS, grid, func(i):
		grid = i
		_build())
	LabUI.slider(p, "Líneas por familia", 4, 30, 1, nlines, func(v):
		nlines = int(v)
		_build(), "%.0f")
	LabUI.slider(p, "Deformación z → w", 0.0, 1.0, 0.01, morph, func(v):
		morph = v
		mat.set_shader_parameter("morph", v)
		_place_crit())
	LabUI.check(p, "▶ Animar la deformación", animating, func(v): animating = v)
	LabUI.note(p, "Joukowsky con el círculo desplazado que pasa por z = 1 produce un perfil alar: la base de la teoría del flujo potencial alrededor de un ala. Los puntos magenta son puntos críticos (f′ = 0) donde el mapeo deja de ser conforme.")

func pick(origin: Vector3, dir: Vector3):
	return ray_plane_y(origin, dir, 0.0)

func hover_text(hit: Vector3) -> String:
	var z := Vector2(hit.x / S, -hit.z / S)
	var w := f(z)
	var h := 1e-5
	var d := (f(z + Vector2(h, 0)) - f(z - Vector2(h, 0))) / (2 * h)
	return "z = %.3f %+.3fi\nw = f(z) = %.3f %+.3fi\n|f′(z)| = %.3f (escala local)\narg f′(z) = %.1f° (giro local)" % [z.x, z.y, w.x, w.y, d.length(), rad_to_deg(atan2(d.y, d.x))]

func perturb(_hit: Vector3, first: bool) -> void:
	if first:
		animating = true
		_dir = -1.0 if morph > 0.5 else 1.0

func critical_points() -> Array:
	var out := []
	for c in crit_node.get_children():
		if c is MeshInstance3D:
			out.append({"pos": (c as Node3D).position, "nombre": "Punto crítico f′(z) = 0", "dist": 2.0})
	return out

func info() -> String:
	return "w = %s · deformación %d %%\nAzul: primera familia · naranja: segunda — siguen siendo perpendiculares." % [expr.source, int(morph * 100)]
