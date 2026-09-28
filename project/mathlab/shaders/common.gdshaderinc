// Utilidades comunes de los shaders del Laboratorio matemático:
// mapas de color científicos, color por fase, planos de corte y rejilla.

uniform vec3 clip_on = vec3(0.0);      // planos de corte X/Y/Z activos (1 = sí)
uniform vec3 clip_pos = vec3(0.0);     // posición de cada plano (mundo)
uniform vec3 clip_side = vec3(1.0);    // 1: descarta lo que queda por encima del plano, −1: por debajo

vec3 cm_viridis(float t) {
	t = clamp(t, 0.0, 1.0);
	const vec3 c0 = vec3(0.2777, 0.0054, 0.3340);
	const vec3 c1 = vec3(0.1051, 1.4046, 1.3846);
	const vec3 c2 = vec3(-0.3309, 0.2148, 0.0951);
	const vec3 c3 = vec3(-4.6342, -5.7991, -19.3324);
	const vec3 c4 = vec3(6.2283, 14.1799, 56.6906);
	const vec3 c5 = vec3(4.7764, -13.7451, -65.3530);
	const vec3 c6 = vec3(-5.4355, 4.6459, 26.3124);
	return c0 + t * (c1 + t * (c2 + t * (c3 + t * (c4 + t * (c5 + t * c6)))));
}

vec3 cm_inferno(float t) {
	t = clamp(t, 0.0, 1.0);
	const vec3 c0 = vec3(0.0002, 0.0016, -0.0194);
	const vec3 c1 = vec3(0.1065, 0.5639, 3.9327);
	const vec3 c2 = vec3(11.6025, -3.9729, -15.9424);
	const vec3 c3 = vec3(-41.7040, 17.4364, 44.3541);
	const vec3 c4 = vec3(77.1629, -33.4023, -81.8073);
	const vec3 c5 = vec3(-71.3194, 32.6261, 73.2095);
	const vec3 c6 = vec3(25.1311, -12.2427, -23.0703);
	return c0 + t * (c1 + t * (c2 + t * (c3 + t * (c4 + t * (c5 + t * c6)))));
}

vec3 cm_turbo(float t) {
	t = clamp(t, 0.0, 1.0);
	const vec4 kr = vec4(0.13572138, 4.61539260, -42.66032258, 132.13108234);
	const vec4 kg = vec4(0.09140261, 2.19418839, 4.84296658, -14.18503333);
	const vec4 kb = vec4(0.10667330, 12.64194608, -60.58204836, 110.36276771);
	const vec2 kr2 = vec2(-152.94239396, 59.28637943);
	const vec2 kg2 = vec2(4.27729857, 2.82956604);
	const vec2 kb2 = vec2(-89.90310912, 27.34824973);
	vec4 v4 = vec4(1.0, t, t * t, t * t * t);
	vec2 v2 = v4.zw * v4.z;
	return vec3(dot(v4, kr) + dot(v2, kr2), dot(v4, kg) + dot(v2, kg2), dot(v4, kb) + dot(v2, kb2));
}

// Divergente azul–blanco–rojo (valores con signo, t en [−1, 1]).
vec3 cm_diverging(float t) {
	t = clamp(t, -1.0, 1.0);
	vec3 neg = vec3(0.10, 0.35, 0.95);
	vec3 mid = vec3(0.92, 0.94, 0.97);
	vec3 pos = vec3(0.95, 0.25, 0.12);
	return t < 0.0 ? mix(mid, neg, -t) : mix(mid, pos, t);
}

// Color por fase (rueda cromática HSV, s = v = 1).
vec3 hue_color(float phase) {
	float h = fract(phase / 6.2831853);
	vec3 k = vec3(1.0, 2.0 / 3.0, 1.0 / 3.0);
	vec3 p = abs(fract(vec3(h) + k) * 6.0 - 3.0);
	return clamp(p - 1.0, 0.0, 1.0);
}

vec3 palette(int id, float t) {
	if (id == 1) return cm_inferno(t);
	if (id == 2) return cm_turbo(t);
	if (id == 3) return cm_diverging(t * 2.0 - 1.0);
	return cm_viridis(t);
}

// Planos de corte: devuelve true si el fragmento debe descartarse.
bool clipped(vec3 w) {
	if (clip_on.x > 0.5 && (w.x - clip_pos.x) * clip_side.x > 0.0) return true;
	if (clip_on.y > 0.5 && (w.y - clip_pos.y) * clip_side.y > 0.0) return true;
	if (clip_on.z > 0.5 && (w.z - clip_pos.z) * clip_side.z > 0.0) return true;
	return false;
}

// Brillo de la sección transversal junto a cada plano de corte.
float clip_edge(vec3 w) {
	float e = 0.0;
	if (clip_on.x > 0.5) e = max(e, 1.0 - smoothstep(0.0, 0.025, abs(w.x - clip_pos.x)));
	if (clip_on.y > 0.5) e = max(e, 1.0 - smoothstep(0.0, 0.025, abs(w.y - clip_pos.y)));
	if (clip_on.z > 0.5) e = max(e, 1.0 - smoothstep(0.0, 0.025, abs(w.z - clip_pos.z)));
	return e;
}

// Líneas de rejilla antialiasadas sobre una coordenada 2D.
float grid_lines(vec2 p, float spacing, float width) {
	vec2 g = abs(fract(p / spacing - 0.5) - 0.5) / fwidth(p / spacing);
	return 1.0 - clamp(min(g.x, g.y) / max(width, 0.001), 0.0, 1.0);
}

// Isolíneas de un valor escalar.
float iso_lines(float v, float spacing, float width) {
	if (spacing <= 0.0) return 0.0;
	float f = abs(fract(v / spacing - 0.5) - 0.5) / max(fwidth(v / spacing), 1e-5);
	return 1.0 - clamp(f / width, 0.0, 1.0);
}
