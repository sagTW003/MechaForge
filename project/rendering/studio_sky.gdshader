shader_type sky;

// "HDRI" procedural para iluminación basada en imagen (reflejos realistas en
// metales y plásticos) sin depender de archivos externos.
//   mode 0 — Estudio: ciclorama neutro con softboxes (clave, relleno, cenital, contra).
//   mode 1 — Taller: nave con ventanales, tubos fluorescentes, paneles y banco.
// Los valores son radiancia lineal HDR (>1 en las fuentes de luz).

uniform int mode = 0;
uniform float energy = 1.0;
uniform vec3 key_tint : source_color = vec3(1.0, 0.97, 0.92);

const float DEG = 0.01745329;

float soft_rect(float az, float el, float az0, float el0, float hw, float hh, float soft) {
	float da = abs(mod(az - az0 + 3.14159265, 6.2831853) - 3.14159265);
	float de = abs(el - el0);
	float a = 1.0 - smoothstep(hw - soft, hw + soft, da * cos(el));
	float e = 1.0 - smoothstep(hh - soft, hh + soft, de);
	return a * e;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 studio(vec3 d) {
	float el = asin(clamp(d.y, -1.0, 1.0));
	float az = atan(d.x, d.z);
	// Ciclorama: gris neutro con degradado suave; suelo más oscuro.
	vec3 col = mix(vec3(0.13, 0.133, 0.14), vec3(0.09, 0.092, 0.1), smoothstep(0.0, 1.2, el));
	col = mix(vec3(0.025, 0.025, 0.028), col, smoothstep(-0.08, 0.02, el));
	// Softboxes (HDR).
	col += key_tint * 4.5 * soft_rect(az, el, 60.0 * DEG, 40.0 * DEG, 17.0 * DEG, 11.0 * DEG, 2.0 * DEG);
	col += vec3(0.9, 0.95, 1.0) * 1.6 * soft_rect(az, el, -120.0 * DEG, 18.0 * DEG, 4.0 * DEG, 14.0 * DEG, 1.5 * DEG);
	col += vec3(1.0) * 2.2 * soft_rect(az, el, 150.0 * DEG, 70.0 * DEG, 30.0 * DEG, 7.0 * DEG, 2.0 * DEG);
	col += vec3(1.0, 0.98, 0.95) * 3.0 * soft_rect(az, el, 165.0 * DEG, 24.0 * DEG, 3.0 * DEG, 15.0 * DEG, 1.0 * DEG);
	// Tarjeta reflectora tenue a ras de suelo.
	col += vec3(0.25) * soft_rect(az, el, -60.0 * DEG, 4.0 * DEG, 35.0 * DEG, 3.0 * DEG, 3.0 * DEG);
	return col;
}

vec3 workshop(vec3 d) {
	// Habitación virtual: el observador a 1.2 m del suelo, nave de 14x14x4 m.
	vec3 lo = vec3(-7.0, -1.2, -7.0);
	vec3 hi = vec3(7.0, 2.8, 7.0);
	vec3 inv = 1.0 / max(abs(d), vec3(1e-4)) * sign(d + vec3(1e-6));
	vec3 t1 = lo * inv;
	vec3 t2 = hi * inv;
	vec3 tmax = max(t1, t2);
	float t = min(min(tmax.x, tmax.y), tmax.z);
	vec3 p = d * t;
	float y = p.y + 1.2;                       // altura sobre el suelo (0..4 m)
	vec3 col;
	if (tmax.y <= t + 1e-4 && d.y > 0.0) {
		// Techo con filas de tubos fluorescentes.
		col = vec3(0.07, 0.07, 0.075);
		float row = abs(fract(p.z / 2.5 + 0.5) - 0.5) * 2.5;
		float seg = abs(fract(p.x / 2.0 + 0.5) - 0.5) * 2.0;
		float tube = (1.0 - smoothstep(0.05, 0.09, row)) * (1.0 - smoothstep(0.72, 0.76, seg));
		col = mix(col, vec3(1.0, 0.98, 0.94) * 11.0, tube * step(abs(p.x), 5.5) * step(abs(p.z), 5.5));
		// Vigas.
		float beam = 1.0 - smoothstep(0.08, 0.1, abs(fract(p.x / 3.5 + 0.5) - 0.5) * 3.5);
		col = mix(col, vec3(0.04), beam * 0.8);
	} else if (tmax.y <= t + 1e-4) {
		// Suelo de hormigón con juntas.
		float j = min(abs(fract(p.x / 3.0 + 0.5) - 0.5), abs(fract(p.z / 3.0 + 0.5) - 0.5)) * 3.0;
		col = vec3(0.16, 0.155, 0.15) * (0.85 + 0.3 * hash(floor(p.xz * 2.0)));
		col *= mix(0.6, 1.0, smoothstep(0.0, 0.02, j));
	} else {
		// Paredes: coordenada horizontal a lo largo de la pared.
		bool wall_x = tmax.x <= tmax.z;
		float u = wall_x ? p.z : p.x;
		float side = wall_x ? sign(d.x) : sign(d.z);
		col = vec3(0.30, 0.29, 0.27);                           // pintura
		if (y < 0.9) {
			// Armarios bajos con puertas.
			col = vec3(0.10, 0.12, 0.16);
			float door = abs(fract(u / 0.6 + 0.5) - 0.5) * 0.6;
			col *= mix(0.5, 1.0, smoothstep(0.004, 0.012, door));
		} else if (y < 0.95) {
			col = vec3(0.35, 0.28, 0.2);                          // encimera de madera
		} else if (y < 2.1 && !(wall_x && side > 0.0)) {
			// Panel perforado para herramientas.
			col = vec3(0.22, 0.2, 0.17);
			vec2 g = fract(vec2(u, y) / 0.025) - 0.5;
			col *= mix(0.55, 1.0, smoothstep(0.12, 0.2, length(g)));
			// Herramientas colgadas (siluetas).
			float tool = step(0.72, hash(floor(vec2(u / 0.35, 0.0)))) * step(1.2, y) * step(y, 1.9);
			col = mix(col, vec3(0.05, 0.05, 0.06), tool * 0.8);
		}
		// Ventanales en la pared +X.
		if (wall_x && side > 0.0 && y > 1.2 && y < 2.6) {
			float pane = abs(fract(u / 1.6 + 0.5) - 0.5) * 1.6;
			float mull = abs(y - 1.9);
			float glass = smoothstep(0.03, 0.05, pane) * smoothstep(0.02, 0.035, mull);
			vec3 sky = mix(vec3(0.75, 0.85, 1.0), vec3(0.45, 0.6, 0.9), (y - 1.2) / 1.4) * 7.0;
			col = mix(vec3(0.08), sky, glass * step(abs(u), 5.8));
		}
		// Pizarra blanca en la pared -Z.
		if (!wall_x && side < 0.0 && y > 1.1 && y < 2.2 && abs(u) < 1.8) {
			col = vec3(0.85);
		}
	}
	return col;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 col = (mode == 1) ? workshop(d) : studio(d);
	COLOR = col * energy;
}
