shader_type spatial;
// Cable recalentado: el aislamiento se chamusca y el conductor brilla con el
// color de cuerpo negro de su temperatura (rojo oscuro ≈ 525 °C → naranja →
// amarillo). El parpadeo sutil imita la convección sobre el cable.

uniform vec3 base_color : source_color = vec3(0.1, 0.35, 0.85);
uniform float temperature = 25.0;   // °C
uniform float char_amount = 0.0;    // 0..1 aislamiento chamuscado

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 blackbody(float t_c) {
	float k = t_c + 273.15;
	float g = pow(clamp((k - 700.0) / 1500.0, 0.0, 1.0), 1.2) * 0.85;
	float b = pow(clamp((k - 1100.0) / 2200.0, 0.0, 1.0), 1.5) * 0.7;
	return vec3(1.0, g, b);
}

void fragment() {
	float glow = clamp((temperature - 450.0) / 650.0, 0.0, 1.0);
	float warm = clamp((temperature - 120.0) / 400.0, 0.0, 1.0);
	vec3 charred = mix(base_color, vec3(0.045, 0.038, 0.032), max(char_amount, warm * 0.6));
	float flick = 0.82 + 0.18 * sin(world_pos.x * 900.0 + world_pos.z * 700.0 + TIME * 9.0)
		* sin(world_pos.y * 1300.0 - TIME * 5.0);
	ALBEDO = mix(charred, vec3(0.02), glow * 0.85);
	ROUGHNESS = mix(0.38, 0.95, max(char_amount, warm));
	SPECULAR = 0.4;
	EMISSION = blackbody(temperature) * glow * glow * 10.0 * flick;
}
