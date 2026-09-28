extends LabModule
## Fractales de Mandelbrot y Julia en relieve 3D (iteración en la GPU por vértice
## y por fragmento, coloreado continuo por conteo de escape suavizado). Los dos
## conjuntos se muestran lado a lado: el punto c elegido en el de Mandelbrot
## (clic, o siguiendo al cursor) define el conjunto de Julia correspondiente.

const PSIZE := 3.4
const GAP := 0.3
const SHADER := """
shader_type spatial;
render_mode cull_disabled;
#include "res://mathlab/shaders/common.gdshaderinc"
uniform vec2 center = vec2(-0.5, 0.0);
uniform float span = 3.0;
uniform int max_iter = 300;
uniform int vert_iter = 48;
uniform bool julia = false;
uniform vec2 cj = vec2(-0.8, 0.156);
uniform float height = 0.5;
uniform float pal_shift = 0.0;
varying vec3 wpos;
varying float vh;

float esc(vec2 p, int maxit, out bool inside) {
	vec2 z = julia ? p : vec2(0.0);
	vec2 c = julia ? cj : p;
	inside = true;
	for (int i = 0; i < maxit; i++) {
		z = vec2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
		float m2 = dot(z, z);
		if (m2 > 256.0) {
			inside = false;
			return max(0.0, (float(i) + 1.0 - log2(log2(m2) * 0.5)) / float(maxit));
		}
	}
	return 1.0;
}

vec2 pof(vec2 uv) { return center + vec2(uv.x - 0.5, 0.5 - uv.y) * span; }

void vertex() {
	bool ins;
	float v = esc(pof(UV), vert_iter, ins);
	vh = ins ? 1.0 : pow(clamp(v * float(vert_iter) / 48.0, 0.0, 1.0), 0.45);
	VERTEX.y = vh * height;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (clipped(wpos)) discard;
	bool ins;
	float v = esc(pof(UV), max_iter, ins);
	vec3 col;
	if (ins) {
		col = vec3(0.01, 0.012, 0.02);
		ROUGHNESS = 0.08;
		METALLIC = 0.6;
	} else {
		float t = sqrt(v) * 3.0 + pal_shift;
		col = 0.5 + 0.5 * cos(6.2831853 * (t + vec3(0.0, 0.33, 0.67) + vec3(0.1, 0.2, 0.25)));
		ROUGHNESS = 0.35;
		EMISSION = col * (0.25 + 0.9 * pow(clamp(v * 3.0, 0.0, 1.0), 2.0));
	}
	vec3 nw = normalize(cross(dFdy(wpos), dFdx(wpos)));
	if (nw.y < 0.0) nw = -nw;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ALBEDO = col;
}
"""

var mand: MeshInstance3D
var jul: MeshInstance3D
var mat_m: ShaderMaterial
var mat_j: ShaderMaterial
var cj := Vector2(-0.8, 0.156)
var center_m := Vector2(-0.5, 0.0)
var span_m: float = 3.0
var center_j := Vector2.ZERO
var span_j: float = 3.2
var follow: bool = false
var max_iter: int = 300
var c_marker: MeshInstance3D

func title() -> String: return "Fractales"
func formula() -> String: return "zₙ₊₁ = zₙ² + c  ·  Mandelbrot: z₀ = 0, c = píxel  ·  Julia: z₀ = píxel, c fijo"
func perturb_hint() -> String: return "clic en Mandelbrot: elige c · Mayús+clic: zoom ×2 · Ctrl+clic: zoom ×½"
func view() -> Dictionary: return {"target": Vector3(0, 0.1, 0), "dist": 8.0, "yaw": 0.0, "pitch": -58.0}

func setup() -> void:
	var sh := Shader.new()
	sh.code = SHADER
	mand = MeshInstance3D.new()
	mand.mesh = SurfaceShader.plane(PSIZE, 360)
	mat_m = ShaderMaterial.new()
	mat_m.shader = sh
	mand.material_override = mat_m
	mand.position = Vector3(-(PSIZE + GAP) * 0.5, 0, 0)
	add_child(mand)
	jul = MeshInstance3D.new()
	jul.mesh = SurfaceShader.plane(PSIZE, 360)
	mat_j = ShaderMaterial.new()
	mat_j.shader = sh
	mat_j.set_shader_parameter("julia", true)
	jul.material_override = mat_j
	jul.position = Vector3((PSIZE + GAP) * 0.5, 0, 0)
	add_child(jul)
	register_clip(mat_m)
	register_clip(mat_j)
	c_marker = sphere(0.04, glow_mat(Color(1, 1, 1), 4.0))
	add_child(c_marker)
	add_child(label3d("Mandelbrot", Vector3(-(PSIZE + GAP) * 0.5, 0.05, -PSIZE * 0.56), Color(0.4, 0.9, 1.0), 0.004))
	add_child(label3d("Julia", Vector3((PSIZE + GAP) * 0.5, 0.05, -PSIZE * 0.56), Color(1.0, 0.7, 0.35), 0.004))
	_apply()

func _apply() -> void:
	mat_m.set_shader_parameter("center", center_m)
	mat_m.set_shader_parameter("span", span_m)
	mat_j.set_shader_parameter("center", center_j)
	mat_j.set_shader_parameter("span", span_j)
	mat_j.set_shader_parameter("cj", cj)
	for m in [mat_m, mat_j]:
		m.set_shader_parameter("max_iter", max_iter)
	# Marcador de c sobre el conjunto de Mandelbrot.
	var uv := Vector2((cj.x - center_m.x) / span_m + 0.5, 0.5 - (cj.y - center_m.y) / span_m)
	c_marker.visible = uv.x >= 0 and uv.x <= 1 and uv.y >= 0 and uv.y <= 1
	c_marker.position = mand.position + Vector3((uv.x - 0.5) * PSIZE, 0.55, (uv.y - 0.5) * PSIZE)

func build_ui(p: VBoxContainer) -> void:
	LabUI.slider(p, "Iteraciones máximas", 32, 1500, 1, max_iter, func(v):
		max_iter = int(v)
		_apply(), "%.0f")
	LabUI.slider(p, "Relieve", 0.0, 1.5, 0.01, 0.5, func(v):
		mat_m.set_shader_parameter("height", v)
		mat_j.set_shader_parameter("height", v))
	LabUI.slider(p, "Paleta (desplazamiento)", 0.0, 1.0, 0.01, 0.0, func(v):
		mat_m.set_shader_parameter("pal_shift", v)
		mat_j.set_shader_parameter("pal_shift", v))
	LabUI.check(p, "Julia sigue al cursor sobre Mandelbrot", follow, func(v): follow = v)
	LabUI.option(p, "c de Julia:", ["−0.8 + 0.156i (espirales)", "−0.123 + 0.745i (conejo de Douady)", "i (dendrita)", "−0.75 (San Marcos)", "−0.391 − 0.587i (disco de Siegel)", "0.285 + 0.01i"], 0, func(i):
		cj = [Vector2(-0.8, 0.156), Vector2(-0.123, 0.745), Vector2(0, 1), Vector2(-0.75, 0), Vector2(-0.391, -0.587), Vector2(0.285, 0.01)][i]
		_apply())
	var r := LabUI.row(p)
	LabUI.button(r, "Vista inicial", func():
		center_m = Vector2(-0.5, 0); span_m = 3.0; center_j = Vector2.ZERO; span_j = 3.2
		_apply())
	LabUI.button(r, "Valle de los caballitos", func():
		center_m = Vector2(-0.745, 0.113); span_m = 0.04
		_apply())
	LabUI.note(p, "Si c está dentro del conjunto de Mandelbrot, el conjunto de Julia es conexo; si está fuera, se rompe en polvo de Cantor. El borde de Mandelbrot tiene dimensión de Hausdorff 2.")

func _plane_uv(hit: Vector3) -> Array:
	for spec in [[mand, false], [jul, true]]:
		var node: Node3D = spec[0]
		var lx := hit.x - node.position.x
		if absf(lx) <= PSIZE * 0.5 and absf(hit.z) <= PSIZE * 0.5:
			return [spec[1], Vector2(lx / PSIZE + 0.5, hit.z / PSIZE + 0.5)]
	return []

func _c_of(is_j: bool, uv: Vector2) -> Vector2:
	var c := center_j if is_j else center_m
	var s := span_j if is_j else span_m
	return c + Vector2(uv.x - 0.5, 0.5 - uv.y) * s

func escape_count(p: Vector2, is_j: bool) -> int:
	var z := p if is_j else Vector2.ZERO
	var c := cj if is_j else p
	for i in range(max_iter):
		z = Vector2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c
		if z.length_squared() > 4.0:
			return i
	return -1

func pick(origin: Vector3, dir: Vector3):
	var hit = ray_plane_y(origin, dir, 0.25)
	if hit == null or _plane_uv(hit).is_empty():
		return null
	return hit

func hover_text(hit: Vector3) -> String:
	var info_uv := _plane_uv(hit)
	if info_uv.is_empty():
		return ""
	var is_j: bool = info_uv[0]
	var c := _c_of(is_j, info_uv[1])
	if follow and not is_j:
		cj = c
		_apply()
	var n := escape_count(c, is_j)
	return "%s = %.5f %+.5fi\n%s" % ["z₀" if is_j else "c", c.x, c.y, "dentro del conjunto (no escapa)" if n < 0 else "escapa en %d iteraciones" % n]

func perturb(hit: Vector3, first: bool) -> void:
	if not first:
		return
	var info_uv := _plane_uv(hit)
	if info_uv.is_empty():
		return
	var is_j: bool = info_uv[0]
	var c := _c_of(is_j, info_uv[1])
	if Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_CTRL):
		var k := 0.5 if Input.is_key_pressed(KEY_SHIFT) else 2.0
		if is_j:
			center_j = c; span_j *= k
		else:
			center_m = c; span_m *= k
	elif not is_j:
		cj = c
	_apply()

func critical_points() -> Array:
	return [{"pos": c_marker.position, "nombre": "c = %.4f %+.4fi" % [cj.x, cj.y], "dist": 2.0},
		{"pos": mand.position + Vector3(0, 0.4, 0), "nombre": "Conjunto de Mandelbrot", "dist": 4.5},
		{"pos": jul.position + Vector3(0, 0.4, 0), "nombre": "Conjunto de Julia", "dist": 4.5}]

func info() -> String:
	var inside := escape_count(cj, false) < 0
	return "c = %.5f %+.5fi → Julia %s\nZoom Mandelbrot ×%.0f · Julia ×%.0f · %d iteraciones" % [cj.x, cj.y, "conexo (c ∈ M)" if inside else "disconexo (c ∉ M)", 3.0 / span_m, 3.2 / span_j, max_iter]
