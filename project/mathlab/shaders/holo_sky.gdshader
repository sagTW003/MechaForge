shader_type sky;
// Cielo del holodeck: sala oscura con franjas de luz horizontales, paneles
// luminosos y una retícula tenue en la cúpula. Actúa como mapa de entorno
// (HDRI procedural): da reflejos realistas a las superficies metálicas y
// brillantes de las gráficas sin depender de archivos externos.

uniform vec3 top_color : source_color = vec3(0.004, 0.006, 0.012);
uniform vec3 horizon_color : source_color = vec3(0.02, 0.035, 0.06);
uniform vec3 strip_color : source_color = vec3(0.55, 0.8, 1.0);
uniform float strip_energy = 2.2;
uniform vec3 warm_color : source_color = vec3(1.0, 0.72, 0.45);

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col = mix(horizon_color, top_color, smoothstep(0.0, 0.8, h));
	col = mix(col, horizon_color * 0.4, smoothstep(0.0, -0.4, h));
	float az = atan(d.x, d.z);
	// Franjas de luz a dos alturas (como tiras LED en las paredes).
	float s1 = exp(-pow((h - 0.08) / 0.012, 2.0));
	float s2 = exp(-pow((h - 0.32) / 0.008, 2.0)) * 0.6;
	float seg = smoothstep(0.1, 0.2, abs(sin(az * 6.0)));
	col += strip_color * (s1 + s2) * seg * strip_energy;
	// Paneles cenitales cálidos (luz principal para los reflejos).
	vec2 p = d.xz / max(d.y, 0.05);
	float panel = step(abs(p.x - 0.4), 0.25) * step(abs(p.y + 0.2), 0.5) * step(0.65, h);
	col += warm_color * panel * 1.1;
	// Retícula tenue de la cúpula.
	float gx = abs(fract(az * 12.0 / 6.2831853) - 0.5);
	float gy = abs(fract(h * 10.0) - 0.5);
	float grid = (1.0 - smoothstep(0.0, 0.015, gx)) + (1.0 - smoothstep(0.0, 0.02, gy));
	col += strip_color * grid * 0.025 * smoothstep(0.0, 0.3, h);
	COLOR = col;
}
