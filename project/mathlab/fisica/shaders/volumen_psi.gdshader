shader_type spatial;
// |ψ|² en 3D por trazado de rayos (raymarching) dentro de un cubo: cada muestra aporta
// opacidad según la densidad y el color es la fase de ψ en la rueda del laboratorio.
// Textura 3D (Schrodinger3D.Volumen): R = √(ρ/ρ_máx), G y B = cos y sin de arg ψ, A = V/V_máx.
// Ejes como en todo el laboratorio (LabModule.to_world): física (x, y, z) = mundo (x, z, −y).
// Las paredes del potencial se ven grises.
render_mode unshaded, cull_front, depth_draw_never, blend_mix, shadows_disabled;
#include "res://mathlab/shaders/common.gdshaderinc"

uniform sampler3D volumen : filter_linear, repeat_disable;
uniform float lado = 4.0;          // lado del cubo en el mundo
uniform float opacidad = 40.0;     // opacidad por unidad de recorrido con ρ = ρ_máx (ilustrativa)
const int MUESTRAS = 128;
varying vec3 pos_local;

void vertex() {
	pos_local = VERTEX;
}

void fragment() {
	vec3 cam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	vec3 dir = normalize(pos_local - cam);
	// Entrada y salida del rayo en el cubo (método de las placas); desde dentro, empieza en la cámara.
	vec3 h = vec3(0.5 * lado);
	vec3 t1 = (-h - cam) / dir;
	vec3 t2 = (h - cam) / dir;
	vec3 tmin = min(t1, t2);
	vec3 tmax = max(t1, t2);
	float t0 = max(max(tmin.x, tmin.y), max(tmin.z, 0.0));
	float tf = min(min(tmax.x, tmax.y), tmax.z);
	if (tf <= t0) {
		discard;
	}
	float paso = (tf - t0) / float(MUESTRAS);
	vec4 acc = vec4(0.0);
	for (int s = 0; s < MUESTRAS; s++) {
		if (acc.a > 0.98) {
			break;
		}
		vec3 p = cam + dir * (t0 + (float(s) + 0.5) * paso);
		if (clipped((MODEL_MATRIX * vec4(p, 1.0)).xyz)) {
			continue;
		}
		vec4 v = texture(volumen, vec3(p.x, -p.z, p.y) / lado + 0.5);
		float a = 1.0 - exp(-opacidad * v.r * v.r * paso);
		float pared = 1.0 - exp(-6.0 * v.a * paso);
		vec3 col = hue_color(atan(v.b * 2.0 - 1.0, v.g * 2.0 - 1.0));
		float total = 1.0 - (1.0 - a) * (1.0 - pared);
		col = (col * a + vec3(0.7) * pared) / max(a + pared, 1e-4);
		acc.rgb += (1.0 - acc.a) * total * col;
		acc.a += (1.0 - acc.a) * total;
	}
	if (acc.a < 0.003) {
		discard;
	}
	ALBEDO = acc.rgb / acc.a;
	ALPHA = acc.a;
}
