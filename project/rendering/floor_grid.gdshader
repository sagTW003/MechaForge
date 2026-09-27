shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Suelo del área de trabajo con rejilla CAD.
//   style 0 — Estudio/laboratorio: resina epoxi oscura con escamas, satinada.
//   style 1 — Taller: hormigón pulido con juntas y cinta de seguridad amarilla.
//   style 2 — Exterior: losa de pruebas de hormigón, asfalto y césped alrededor.
// Las líneas de la rejilla tienen grosor constante en PÍXELES (no en metros), y
// las menores se desvanecen cuando quedan demasiado juntas en pantalla.

uniform int style = 0;
uniform float minor_step = 0.01;     // metros (paso de la rejilla)
uniform float grid_opacity = 1.0;
uniform float grid_radius = 4.0;     // radio de la zona con rejilla (m)
uniform vec3 axis_x_color : source_color = vec3(0.9, 0.3, 0.3);
uniform vec3 axis_z_color : source_color = vec3(0.3, 0.55, 0.95);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

// Línea de "px" píxeles de grosor en la coordenada dada.
float line_px(float coord, float step, float px) {
	float w = fwidth(coord);
	float d = abs(fract(coord / step + 0.5) - 0.5) * step;
	return 1.0 - smoothstep(w * px * 0.5, w * (px * 0.5 + 1.0), d);
}

// 0 cuando las líneas de paso "step" quedan a menos de ~5 px entre sí.
float density_fade(float step, vec2 p) {
	float w = max(fwidth(p.x), fwidth(p.y));
	return clamp((step / max(w, 1e-6) - 5.0) / 10.0, 0.0, 1.0);
}

void fragment() {
	vec2 p = world_pos.xz;
	float dist = length(p);
	vec3 col;
	float rough;
	float spec = 0.5;
	if (style == 0) {
		// Epoxi: base oscura con escamas claras y leves variaciones.
		col = vec3(0.055, 0.06, 0.068) * (0.9 + 0.2 * fbm(p * 1.5));
		// Moteado sutil de la resina (sin detalle subpíxel que parpadee).
		col *= 0.92 + 0.16 * fbm(p * 12.0);
		rough = 0.38 + 0.12 * fbm(p * 4.0);
	} else if (style == 1) {
		// Hormigón pulido del taller.
		float n = fbm(p * 2.0);
		col = vec3(0.2, 0.196, 0.19) * (0.78 + 0.35 * n);
		col *= 0.9 + 0.1 * fbm(p * 25.0);
		float stain = smoothstep(0.62, 0.8, fbm(p * 0.4 + 7.0));
		col *= 1.0 - stain * 0.25;
		float joint = min(abs(fract(p.x / 3.0 + 0.5) - 0.5), abs(fract(p.y / 3.0 + 0.5) - 0.5)) * 3.0;
		col *= mix(0.45, 1.0, smoothstep(0.003, 0.008, joint));
		// Cinta de seguridad amarilla delimitando la zona de trabajo (3 x 3 m).
		float box = max(abs(p.x), abs(p.y));
		float tape = step(abs(box - 1.5), 0.025);
		float stripe = step(0.5, fract((p.x + p.y) * 5.0));
		col = mix(col, mix(vec3(0.75, 0.6, 0.05), vec3(0.03), stripe), tape);
		rough = 0.55 + 0.25 * n;
	} else {
		// Exterior: losa de pruebas, asfalto y césped.
		float box = max(abs(p.x), abs(p.y));
		vec3 slab = vec3(0.42, 0.41, 0.39) * (0.8 + 0.3 * fbm(p * 1.5));
		float joint = min(abs(fract(p.x / 2.0 + 0.5) - 0.5), abs(fract(p.y / 2.0 + 0.5) - 0.5)) * 2.0;
		slab *= mix(0.55, 1.0, smoothstep(0.004, 0.01, joint));
		vec3 asphalt = vec3(0.05, 0.05, 0.055) * (0.8 + 0.5 * fbm(p * 6.0));
		asphalt += vec3(0.08) * step(0.992, hash(floor(p * 300.0)));
		// Líneas de carril blancas.
		float lane = step(abs(abs(p.y) - 9.0), 0.06) * step(0.5, fract(p.x / 3.0));
		asphalt = mix(asphalt, vec3(0.7), lane);
		vec3 grass = mix(vec3(0.05, 0.12, 0.03), vec3(0.12, 0.2, 0.05), fbm(p * 0.8)) * (0.7 + 0.5 * fbm(p * 20.0));
		col = mix(slab, asphalt, smoothstep(6.0, 6.05, box));
		col = mix(col, grass, smoothstep(14.0, 15.0, box + fbm(p * 0.5) * 1.5));
		rough = mix(0.75, 0.9, smoothstep(6.0, 6.05, box));
		spec = mix(0.5, 0.3, smoothstep(14.0, 15.0, box));
	}

	// Rejilla (solo en la zona de trabajo).
	float zone = 1.0 - smoothstep(grid_radius * 0.6, grid_radius, dist);
	float minor = max(line_px(p.x, minor_step, 1.0), line_px(p.y, minor_step, 1.0)) * density_fade(minor_step, p);
	float mstep = minor_step * 10.0;
	float major = max(line_px(p.x, mstep, 1.4), line_px(p.y, mstep, 1.4)) * density_fade(mstep, p);
	float mstep2 = minor_step * 100.0;
	float major2 = max(line_px(p.x, mstep2, 1.6), line_px(p.y, mstep2, 1.6)) * density_fade(mstep2, p);
	vec3 gcol = (style == 0) ? vec3(0.2, 0.23, 0.28) : vec3(0.06, 0.065, 0.07);
	float gk = (style == 0) ? 1.0 : 0.6;
	float g = max(max(minor * 0.12, major * 0.25), major2 * 0.35) * zone * grid_opacity * gk;
	col = mix(col, gcol, g);
	// Ejes X (rojo) y Z (azul), finos.
	float axz = line_px(p.y, 1.0e6, 2.0) * step(abs(p.y), 0.5);
	float axx = line_px(p.x, 1.0e6, 2.0) * step(abs(p.x), 0.5);
	float ax_fade = (1.0 - smoothstep(grid_radius, grid_radius * 2.5, dist)) * grid_opacity;
	col = mix(col, axis_x_color, (1.0 - smoothstep(0.0, fwidth(p.y) * 1.5, abs(p.y))) * ax_fade * 0.85);
	col = mix(col, axis_z_color, (1.0 - smoothstep(0.0, fwidth(p.x) * 1.5, abs(p.x))) * ax_fade * 0.85);

	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = spec;
	METALLIC = 0.0;
}
