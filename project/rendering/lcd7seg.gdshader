shader_type spatial;
// Pantalla LCD reflectiva de 7 segmentos del multímetro, dibujada por completo en
// el fragment shader (nítida a cualquier distancia):
//   · 4 dígitos inclinados (itálica) con segmentos hexagonales, punto decimal y
//     signo menos; los segmentos apagados se intuyen levemente como en un LCD real;
//   · iconos: batería, continuidad (altavoz con ondas), AC (~) y DC (⎓).
// Uniformes: seg[4] (bits a=1 … g=64), dp (bit por dígito), minus e iconos.

uniform int seg0 = 0;
uniform int seg1 = 0;
uniform int seg2 = 0;
uniform int seg3 = 0;
uniform int dp = 0;
uniform bool minus_sign = false;
uniform bool icon_ac = false;
uniform bool icon_dc = true;
uniform bool icon_cont = false;
uniform bool icon_battery = true;
uniform bool powered = true;
uniform float backlight = 0.0;
uniform vec2 size_mm = vec2(64.0, 30.0);

const vec3 BG = vec3(0.64, 0.69, 0.62);
const vec3 INK = vec3(0.06, 0.07, 0.065);

// Distancia a un segmento con puntas en diamante (forma clásica de 7 segmentos).
float seg_d(vec2 p, vec2 a, vec2 b, float th) {
	vec2 d = b - a;
	float len = length(d);
	vec2 u = d / len;
	vec2 q = p - a;
	float along = dot(q, u) - len * 0.5;
	float perp = abs(q.x * u.y - q.y * u.x);
	return max(perp - th * 0.5, abs(along) + perp - len * 0.5 + th * 0.15);
}

float digit_ink(vec2 p, int bits, out float ghost) {
	// Celda: segmento de 7 mm de largo, 14 mm de alto; itálica.
	float w = 7.0;
	float h = 14.0;
	float th = 1.35;
	float gap = 0.35;
	p.x -= (h - p.y) * 0.12;
	vec2 A0 = vec2(0.0, 0.0), A1 = vec2(w, 0.0);
	vec2 M0 = vec2(0.0, h * 0.5), M1 = vec2(w, h * 0.5);
	vec2 D0 = vec2(0.0, h), D1 = vec2(w, h);
	float ds[7];
	ds[0] = seg_d(p, A0 + vec2(gap, 0.0), A1 - vec2(gap, 0.0), th);
	ds[1] = seg_d(p, A1 + vec2(0.0, gap), M1 - vec2(0.0, gap), th);
	ds[2] = seg_d(p, M1 + vec2(0.0, gap), D1 - vec2(0.0, gap), th);
	ds[3] = seg_d(p, D0 + vec2(gap, 0.0), D1 - vec2(gap, 0.0), th);
	ds[4] = seg_d(p, M0 + vec2(0.0, gap), D0 - vec2(0.0, gap), th);
	ds[5] = seg_d(p, A0 + vec2(0.0, gap), M0 - vec2(0.0, gap), th);
	ds[6] = seg_d(p, M0 + vec2(gap, 0.0), M1 - vec2(gap, 0.0), th);
	float on_d = 1e5;
	float all_d = 1e5;
	for (int i = 0; i < 7; i++) {
		all_d = min(all_d, ds[i]);
		if (((bits >> i) & 1) == 1) {
			on_d = min(on_d, ds[i]);
		}
	}
	ghost = all_d;
	return on_d;
}

float fill(float d, float aa) {
	return 1.0 - smoothstep(-aa, aa, d);
}

float box_d(vec2 p, vec2 c, vec2 hs) {
	vec2 q = abs(p - c) - hs;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}

void fragment() {
	vec2 p = UV * size_mm;
	float aa = max(fwidth(p.x), fwidth(p.y)) * 0.8;
	float ink = 0.0;
	float ghost_ink = 0.0;
	if (powered) {
		int bits[4] = int[](seg0, seg1, seg2, seg3);
		for (int i = 0; i < 4; i++) {
			vec2 o = vec2(14.0 + float(i) * 11.2, 7.5);
			float gd;
			float d = digit_ink(p - o, bits[i], gd);
			ink = max(ink, fill(d, aa));
			ghost_ink = max(ghost_ink, fill(gd, aa));
			// Punto decimal a la derecha del dígito.
			if (((dp >> i) & 1) == 1) {
				ink = max(ink, fill(length(p - (o + vec2(8.6, 14.0))) - 0.8, aa));
			}
		}
		if (minus_sign) {
			ink = max(ink, fill(box_d(p, vec2(8.5, 14.5), vec2(2.4, 0.6)), aa));
		}
		// Batería (arriba a la izquierda): contorno, borne y tres barras.
		if (icon_battery) {
			float b = abs(box_d(p, vec2(6.0, 3.2), vec2(3.2, 1.5))) - 0.25;
			b = min(b, box_d(p, vec2(9.6, 3.2), vec2(0.35, 0.7)));
			for (int k = 0; k < 3; k++) {
				b = min(b, box_d(p, vec2(4.2 + float(k) * 1.8, 3.2), vec2(0.55, 0.9)));
			}
			ink = max(ink, fill(b, aa));
		}
		// DC: línea continua sobre línea discontinua.
		if (icon_dc) {
			float d = box_d(p, vec2(6.0, 25.0), vec2(3.0, 0.35));
			for (int k = 0; k < 3; k++) {
				d = min(d, box_d(p, vec2(3.8 + float(k) * 2.2, 27.0), vec2(0.7, 0.35)));
			}
			ink = max(ink, fill(d, aa));
		}
		// AC: onda senoidal.
		if (icon_ac) {
			float x = p.x - 3.0;
			float d = 1e5;
			if (x > 0.0 && x < 6.0) {
				float yy = 26.0 - sin(x / 6.0 * 6.2832) * 1.4;
				d = abs(p.y - yy) - 0.4;
			}
			ink = max(ink, fill(d, aa));
		}
		// Continuidad: altavoz y dos ondas (arriba a la derecha).
		if (icon_cont) {
			vec2 c = vec2(55.0, 3.4);
			float d = box_d(p, c - vec2(1.4, 0.0), vec2(0.7, 0.8));
			vec2 q = p - c;
			float cone = max(abs(q.y) - (0.8 + q.x * 0.9), max(-q.x + 0.7 - 0.7, q.x - 1.4));
			d = min(d, cone);
			for (int k = 1; k <= 2; k++) {
				float r = 1.6 + float(k) * 1.1;
				float ring = abs(length(q) - r) - 0.3;
				ring = max(ring, -(q.x - abs(q.y) * 0.7));
				d = min(d, ring);
			}
			ink = max(ink, fill(d, aa));
		}
	}
	vec3 bg = BG * (0.92 + 0.08 * UV.y);
	bg = mix(bg, bg * 0.93, ghost_ink * 0.6);
	vec3 col = mix(bg, INK, ink);
	if (!powered) {
		col = BG * 0.55;
	}
	ALBEDO = col;
	ROUGHNESS = 0.22;
	SPECULAR = 0.6;
	EMISSION = col * backlight;
}
