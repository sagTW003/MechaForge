shader_type spatial;
// Suelo del holodeck: superficie oscura y brillante (refleja con SSR) con una
// rejilla luminosa de dos escalas que se desvanece con la distancia y un halo
// circular bajo el pedestal central.

uniform vec3 base_color : source_color = vec3(0.018, 0.022, 0.03);
uniform vec3 line_color : source_color = vec3(0.1, 0.75, 1.0);
uniform float minor = 0.5;
uniform float major = 2.5;
uniform float fade_radius = 18.0;
uniform float glow = 1.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float gl(vec2 p, float s, float w) {
	vec2 q = p / s;
	vec2 g = abs(fract(q - 0.5) - 0.5) / fwidth(q);
	return 1.0 - clamp(min(g.x, g.y) / w, 0.0, 1.0);
}

void fragment() {
	float r = length(wpos.xz);
	float fade = 1.0 - smoothstep(fade_radius * 0.35, fade_radius, r);
	float g1 = gl(wpos.xz, minor, 1.0) * 0.35;
	float g2 = gl(wpos.xz, major, 1.4);
	float lines = max(g1, g2) * fade;
	// Anillos del pedestal.
	float ring = (1.0 - smoothstep(0.0, 0.03, abs(r - 3.2))) + 0.5 * (1.0 - smoothstep(0.0, 0.02, abs(r - 3.45)));
	float halo = exp(-r * r / 6.0) * 0.08;
	ALBEDO = base_color;
	METALLIC = 0.6;
	ROUGHNESS = 0.18;
	SPECULAR = 0.6;
	EMISSION = line_color * (lines * 0.28 + ring * 0.7 + halo) * glow;
}
