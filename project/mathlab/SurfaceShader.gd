class_name SurfaceShader
extends RefCounted
## SurfaceShader — Genera en tiempo de ejecución el shader de una superficie
## z = f(x, y) a partir de la expresión del usuario (MathExpr → GLSL): la GPU
## evalúa f en cada vértice (altura y normal por diferencias finitas) y en cada
## fragmento (color por altura, curvas de nivel, rejilla y planos de corte).
## Transformación de altura: lineal o logarítmica, log(1 + f − f_mín), para
## funciones con gran rango (Rosenbrock, Himmelblau).

const TEMPLATE := """
shader_type spatial;
render_mode cull_disabled;
#include "res://mathlab/shaders/common.gdshaderinc"
/*PRELUDE*/
uniform vec2 dom_min = vec2(-2.0);
uniform vec2 dom_max = vec2(2.0);
uniform float world_size = 4.0;
uniform float zmin = 0.0;
uniform float zmax = 1.0;
uniform float height = 2.0;
uniform bool log_mode = false;
uniform int pal = 0;
uniform float contour_step = 0.1;
uniform bool show_grid = true;
uniform float t = 0.0;
uniform float alpha_mul = 1.0;

varying vec3 wpos;
varying float hn;

float F(float x, float y) {
	return /*EXPR*/;
}

float Hn(float x, float y) {
	float f = F(x, y);
	float v = log_mode ? log(1.0 + max(f - zmin, 0.0)) / log(1.0 + zmax - zmin) : (f - zmin) / max(1e-6, zmax - zmin);
	return clamp(v, -0.05, 1.05);
}

void vertex() {
	// UV: u → +X (x crece), v → +Z (y matemática decrece hacia el observador).
	vec2 p = mix(dom_min, dom_max, vec2(UV.x, 1.0 - UV.y));
	hn = Hn(p.x, p.y);
	VERTEX.y = hn * height;
	vec2 e = (dom_max - dom_min) / 256.0;
	float hx = (Hn(p.x + e.x, p.y) - Hn(p.x - e.x, p.y)) * height;
	float hy = (Hn(p.x, p.y + e.y) - Hn(p.x, p.y - e.y)) * height;
	float wx = 2.0 * e.x / (dom_max.x - dom_min.x) * world_size;
	float wy = 2.0 * e.y / (dom_max.y - dom_min.y) * world_size;
	NORMAL = normalize(vec3(-hx / wx, 1.0, hy / wy));
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (clipped(wpos)) discard;
	vec2 p = mix(dom_min, dom_max, vec2(UV.x, 1.0 - UV.y));
	float h = Hn(p.x, p.y);
	vec3 col = palette(pal, h);
	float c = iso_lines(h, contour_step, 1.0);
	col = mix(col, vec3(0.02, 0.02, 0.03), c * 0.65);
	if (show_grid) {
		float g = grid_lines(p, max(0.25, floor((dom_max.x - dom_min.x) / 8.0 + 0.5)), 0.7);
		col = mix(col, vec3(0.9, 0.95, 1.0), g * 0.25);
	}
	ALBEDO = col;
	ROUGHNESS = 0.32;
	SPECULAR = 0.55;
	CLEARCOAT = 0.3;
	EMISSION = col * 0.12 + vec3(0.2, 0.9, 1.0) * clip_edge(wpos) * 2.0;
}
"""

## Crea el Shader para la expresión real (variables x, y; opcionalmente t).
static func make(expr: MathExpr) -> Shader:
	var code := TEMPLATE.replace("/*PRELUDE*/", MathExpr.GLSL_PRELUDE).replace("/*EXPR*/", expr.to_glsl({"x": "x", "y": "y", "t": "t"}))
	var sh := Shader.new()
	sh.code = code
	return sh

## Malla plana subdividida del tamaño del mundo (UV: u → +X, v → +Z).
static func plane(world_size: float, subdiv: int = 200) -> PlaneMesh:
	var pm := PlaneMesh.new()
	pm.size = Vector2(world_size, world_size)
	pm.subdivide_width = subdiv
	pm.subdivide_depth = subdiv
	return pm

## Rango de f en el dominio (muestreo en CPU) para normalizar la altura.
static func value_range(expr: MathExpr, dmin: Vector2, dmax: Vector2, n: int = 60) -> Vector2:
	var lo := INF
	var hi := -INF
	expr.compile_fast()
	for j in range(n + 1):
		for i in range(n + 1):
			var x := lerpf(dmin.x, dmax.x, float(i) / n)
			var y := lerpf(dmin.y, dmax.y, float(j) / n)
			var v := expr.eval_fast([x, y]) if expr.variables.size() == 2 else expr.eval_fast([x, y, 0.0])
			if is_finite(v):
				lo = minf(lo, v)
				hi = maxf(hi, v)
	if hi - lo < 1e-9:
		hi = lo + 1.0
	return Vector2(lo, hi)
