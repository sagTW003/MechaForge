shader_type spatial;
// Miles de cuerdas en la GPU: cada instancia es una cuerda (malla de líneas con UV.x = s ∈ [0, 1]
// a lo largo de σ) y su forma se evalúa aquí con los modos normales, sin tocar la CPU.
// INSTANCE_CUSTOM = (A₁, A₂, A₃, tipo): amplitudes de los modos 1, 2 y 3; tipo 0 abierta con
// extremos libres (cos nσ, ondas estacionarias), 1 cerrada (ondas viajeras en un anillo).
// COLOR de la instancia: el nivel de masa.
render_mode unshaded, cull_disabled, shadows_disabled;

uniform float tau = 0.0;
uniform float largo = 0.6;     // longitud del dibujo de una abierta (y diámetro de una cerrada)

void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	float ph = float(INSTANCE_ID) * 2.399963;
	float s = UV.x;
	vec3 p;
	if (c.w < 0.5) {
		float sg = PI * s;
		float y = c.x * cos(sg) * cos(tau + ph) + c.z * cos(3.0 * sg) * cos(3.0 * tau + ph);
		float z = c.y * cos(2.0 * sg) * cos(2.0 * tau + 1.7 * ph);
		p = vec3((s - 0.5) * largo, y, z);
	} else {
		float sg = TAU * s;
		float rad = 0.5 * largo + c.x * cos(tau - sg + ph) + c.z * cos(3.0 * (tau - sg) + ph);
		float z = c.y * cos(2.0 * (tau + sg) + 1.7 * ph);
		p = vec3(rad * cos(sg), z, rad * sin(sg));
	}
	VERTEX = p;
}

void fragment() {
	ALBEDO = COLOR.rgb;
}
