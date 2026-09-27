shader_type spatial;
render_mode cull_back;

// Protoboard MB-102 (830 puntos). Los agujeros se dibujan EXACTAMENTE en las
// posiciones de los terminales (core/PartInstance.gd: gen_protoboard_terminals):
// 63 columnas a 2.54 mm, filas a–e / f–j con canal central de 7.62 mm y cuatro
// rieles de 50 puntos (grupos de 5) con sus líneas roja (+) y azul (−).
// Coordenadas locales en metros; half_xz = semidimensiones de la placa.

uniform vec2 half_xz = vec2(0.0825, 0.0275);

varying vec3 lp;
varying vec3 ln;

const float P = 0.00254;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

// Agujero cuadrado (~1 mm) centrado en c: 1 dentro, 0 fuera (suavizado).
float sq_hole(vec2 p, vec2 c) {
	vec2 d = abs(p - c);
	float m = max(d.x, d.y);
	float aa = fwidth(m) * 1.2 + 1e-6;
	return 1.0 - smoothstep(0.00048 - aa, 0.00048 + aa, m);
}

float strip_holes(vec2 p) {
	// Columna más cercana.
	float cf = floor(p.x / P + 31.5);
	if (cf < 0.0 || cf > 62.0) return 0.0;
	float cx = (cf - 31.0) * P;
	float az = abs(p.y);
	if (az < 0.0038 - 0.0013 || az > 0.0038 + 4.0 * P + 0.0013) return 0.0;
	float r = clamp(floor((az - 0.00381) / P + 0.5), 0.0, 4.0);
	float cz = sign(p.y) * (0.00381 + r * P);
	return sq_hole(p, vec2(cx, cz));
}

float rail_holes(vec2 p, float z) {
	if (abs(p.y - z) > 0.0013) return 0.0;
	float k = floor(p.x / P + 29.5);
	if (k < 0.0 || k > 58.0 || mod(k, 6.0) == 5.0) return 0.0;
	return sq_hole(p, vec2((k - 29.0) * P, z));
}

float line_mask(float v, float c, float w) {
	float aa = fwidth(v) + 1e-6;
	return 1.0 - smoothstep(w - aa, w + aa, abs(v - c));
}

void fragment() {
	vec3 base = vec3(0.93, 0.93, 0.9);
	vec3 col = base;
	float rough = 0.6;
	if (ln.y > 0.5) {
		vec2 p = lp.xz;
		// Canal central.
		float chan = 1.0 - smoothstep(0.0011, 0.0013, abs(p.y));
		col = mix(col, vec3(0.78, 0.78, 0.75), chan);
		// Líneas de los rieles: roja (+) y azul (−), a los lados de cada par.
		col = mix(col, vec3(0.85, 0.12, 0.12), line_mask(p.y, 0.02540, 0.00025));
		col = mix(col, vec3(0.15, 0.3, 0.85), line_mask(p.y, 0.01778, 0.00025));
		col = mix(col, vec3(0.85, 0.12, 0.12), line_mask(p.y, -0.01778, 0.00025));
		col = mix(col, vec3(0.15, 0.3, 0.85), line_mask(p.y, -0.02540, 0.00025));
		float h = strip_holes(p);
		h = max(h, rail_holes(p, 0.02286));
		h = max(h, rail_holes(p, 0.02032));
		h = max(h, rail_holes(p, -0.02032));
		h = max(h, rail_holes(p, -0.02286));
		// Agujero: fondo oscuro con el brillo del contacto metálico.
		col = mix(col, vec3(0.05, 0.05, 0.06), h);
		rough = mix(rough, 0.35, h);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = 0.0;
}
