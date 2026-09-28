shader_type spatial;
render_mode cull_disabled, depth_draw_always, shadows_disabled;
// Variante translúcida (paredes de potencial de vidrio) de field_surface.
// Superficie de un campo 2D simulado (FieldSim): la malla se deforma en la GPU
// con la textura del solver y se colorea según el tipo de campo:
//   0 onda        → altura = u, color divergente azul–blanco–rojo, brillo especular
//   1 calor       → mapa de calor (inferno) con isotermas; altura opcional = T − T_amb
//   2 cuántica    → altura = |ψ|², color = fase arg ψ, brillo emisivo ∝ densidad
//   3 potencial   → paredes de vidrio translúcido con la altura del potencial V
#include "res://mathlab/shaders/common.gdshaderinc"

uniform sampler2D field : filter_linear, repeat_disable;
uniform int mode = 3;
uniform float height_scale = 1.0;
uniform float value_offset = 0.0;
uniform float value_scale = 1.0;
uniform float color_min = 0.0;
uniform float color_max = 1.0;
uniform vec2 texel = vec2(0.004);
uniform float world_size = 4.0;
uniform bool show_grid = true;
uniform float iso_step = 0.0;
uniform float color_gain = 5.0;
uniform vec3 material_tint[5];

varying vec3 wpos;
varying vec4 samp;

float h_of(vec4 s) {
	if (mode == 1) return (s.r - value_offset) * value_scale;
	if (mode == 3) return s.a;
	return s.r * value_scale;
}

void vertex() {
	vec4 s = texture(field, UV);
	samp = s;
	float h = h_of(s) * height_scale;
	VERTEX.y += h;
	float hl = h_of(texture(field, UV - vec2(texel.x, 0.0))) * height_scale;
	float hr = h_of(texture(field, UV + vec2(texel.x, 0.0))) * height_scale;
	float hd = h_of(texture(field, UV - vec2(0.0, texel.y))) * height_scale;
	float hu = h_of(texture(field, UV + vec2(0.0, texel.y))) * height_scale;
	float dx = 2.0 * texel.x * world_size;
	float dz = 2.0 * texel.y * world_size;
	NORMAL = normalize(vec3(-(hr - hl) / dx, 1.0, -(hu - hd) / dz));
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (clipped(wpos)) discard;
	vec4 s = texture(field, UV);
	vec3 col;
	float emi = 0.0;
	vec3 emi_col = vec3(0.0);
	float alpha = 1.0;
	if (mode == 0) {
		if (s.a < 0.5) discard;           // fuera del tambor
		float t = clamp(s.r * value_scale * color_gain, -1.0, 1.0);
		// Base oscura pulida; crestas naranja-amarillas y valles cian-azules que brillan.
		vec3 base = vec3(0.035, 0.06, 0.1);
		vec3 up = mix(vec3(0.95, 0.35, 0.08), vec3(1.0, 0.85, 0.35), clamp(t * 1.5 - 0.5, 0.0, 1.0));
		vec3 dn = mix(vec3(0.05, 0.45, 1.0), vec3(0.3, 0.95, 1.0), clamp(-t * 1.5 - 0.5, 0.0, 1.0));
		col = t >= 0.0 ? mix(base, up, pow(t, 0.7)) : mix(base, dn, pow(-t, 0.7));
		ROUGHNESS = 0.14;
		METALLIC = 0.35;
		SPECULAR = 0.8;
		CLEARCOAT = 0.8;
		emi = pow(abs(t), 1.3) * 1.6;
		emi_col = col;
	} else if (mode == 1) {
		float t = (s.r - color_min) / max(1e-4, color_max - color_min);
		col = cm_inferno(t);
		int mi = int(round(s.a));
		col = mix(col, col * material_tint[clamp(mi, 0, 4)], 0.35);
		ROUGHNESS = 0.45;
		emi = pow(clamp(t, 0.0, 1.0), 2.0) * 1.8;
		emi_col = cm_inferno(t);
		float iso = iso_lines(s.r, iso_step, 1.0);
		col = mix(col, vec3(1.0), iso * 0.55);
		// Fuentes de calor activas: anillo cálido.
		col += vec3(1.0, 0.5, 0.1) * step(0.001, s.g) * 0.25;
	} else if (mode == 2) {
		float dens = s.r * value_scale;
		float ph = atan(s.b, s.g);
		vec3 hc = hue_color(ph);
		float b = clamp(sqrt(max(dens, 0.0)), 0.0, 1.0);
		col = mix(vec3(0.012, 0.016, 0.03), hc, b);
		ROUGHNESS = 0.3;
		SPECULAR = 0.6;
		emi = b * b * 2.4;
		emi_col = hc;
		// Potencial debajo: tono oscuro azulado donde V > 0.
		col = mix(col, vec3(0.06, 0.1, 0.18), clamp(s.a, 0.0, 1.0) * (1.0 - b) * 0.8);
	} else {
		if (s.a < 0.01) discard;
		col = vec3(0.45, 0.75, 1.0);
		alpha = clamp(0.18 + s.a * 0.35, 0.0, 0.55);
		ROUGHNESS = 0.05;
		SPECULAR = 0.9;
		emi = 0.25;
		emi_col = vec3(0.3, 0.6, 1.0);
	}
	if (show_grid && mode != 3) {
		float g = grid_lines(UV * world_size, world_size / 16.0, 0.8);
		col = mix(col, col * 0.55 + vec3(0.05, 0.25, 0.35), g * 0.5);
	}
	float edge = clip_edge(wpos);
	ALBEDO = col;
	ALPHA = alpha;
	EMISSION = emi_col * emi + vec3(0.2, 0.9, 1.0) * edge * 2.0;
}
