shader_type spatial;
render_mode cull_back;

// Protoboard: cuerpo blanco con matriz de agujeros (paso 2.54 mm) y rieles de
// alimentación rojo (+) y azul (−) en los bordes.

uniform vec2 half_xz = vec2(0.05, 0.03);

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	vec2 p = lp.xz;            // p.x = X, p.y = Z (local)
	float step = 0.00254;      // 0.1"
	vec2 g = fract(p / step - 0.5) - 0.5;
	float hole = smoothstep(0.22, 0.10, length(g));
	vec3 base = vec3(0.92, 0.92, 0.88);
	vec3 col = mix(base, vec3(0.07, 0.07, 0.09), hole * 0.85);

	float ez = half_xz.y;
	if (p.y > ez * 0.72) { col = mix(col, vec3(0.85, 0.15, 0.15), 0.55); }
	if (p.y < -ez * 0.72) { col = mix(col, vec3(0.20, 0.35, 0.85), 0.55); }

	ALBEDO = col;
	ROUGHNESS = 0.55;
	METALLIC = 0.0;
}
