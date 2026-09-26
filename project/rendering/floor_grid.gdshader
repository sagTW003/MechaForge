shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Rejilla de taller estilo CAD dibujada sobre el plano del suelo.
// Líneas menores (paso configurable) y mayores (cada 10 pasos), con desvanecido a distancia.

uniform vec3 floor_color : source_color = vec3(0.09, 0.10, 0.12);
uniform vec3 minor_color : source_color = vec3(0.18, 0.20, 0.24);
uniform vec3 major_color : source_color = vec3(0.35, 0.40, 0.48);
uniform vec3 axis_x_color : source_color = vec3(0.85, 0.30, 0.30);
uniform vec3 axis_z_color : source_color = vec3(0.30, 0.55, 0.85);
uniform float minor_step = 0.05;   // metros
uniform float line_width = 0.004;  // metros
uniform float fade_distance = 12.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float line_mask(float coord, float step, float width) {
	float d = abs(fract(coord / step - 0.5) - 0.5) * step;
	float aa = fwidth(coord) * 1.5 + 0.0001;
	return 1.0 - smoothstep(width, width + aa, d);
}

void fragment() {
	vec2 p = world_pos.xz;
	float minor = max(line_mask(p.x, minor_step, line_width), line_mask(p.y, minor_step, line_width));
	float major = max(line_mask(p.x, minor_step * 10.0, line_width * 1.8),
					  line_mask(p.y, minor_step * 10.0, line_width * 1.8));

	vec3 col = floor_color;
	col = mix(col, minor_color, minor * 0.7);
	col = mix(col, major_color, major);

	// Ejes principales.
	float ax = line_mask(p.y, 1.0e9, line_width * 2.0); // nunca
	if (abs(p.y) < line_width * 2.0) { col = axis_x_color; }
	if (abs(p.x) < line_width * 2.0) { col = axis_z_color; }

	float dist = length(world_pos.xz);
	float fade = clamp(1.0 - dist / fade_distance, 0.0, 1.0);
	col = mix(floor_color, col, fade);

	ALBEDO = col;
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
}
