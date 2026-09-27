shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Estaño de soldadura con transición de estado.
//   melt = 0 → sólido: aleación Sn/Pb gris satinado (junta enfriada).
//   melt = 1 → líquido: espejo muy brillante, superficie ondulando por la tensión
//              superficial y leve brillo cálido del fundente caliente.
//   grow     → escala del menisco (0 = aún no hay estaño, 1 = gota completa).

uniform float melt : hint_range(0.0, 1.0) = 0.0;
uniform float grow : hint_range(0.0, 1.0) = 1.0;
uniform vec3 solid_color : source_color = vec3(0.66, 0.67, 0.7);
uniform vec3 liquid_color : source_color = vec3(0.9, 0.91, 0.94);

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
	// Crece desde la base; en estado líquido, onda sutil (tensión superficial).
	float wob = sin(TIME * 24.0 + VERTEX.y * 2600.0 + VERTEX.x * 1900.0) * 0.00006 * melt;
	VERTEX = VERTEX * vec3(mix(0.3, 1.0, grow), grow, mix(0.3, 1.0, grow)) + NORMAL * wob;
}

void fragment() {
	float ripple = sin(TIME * 30.0 + local_pos.y * 4000.0) * melt;
	ALBEDO = mix(solid_color, liquid_color, melt);
	METALLIC = 1.0;
	ROUGHNESS = mix(0.2, 0.04, melt);
	// Microrelieve: grano de solidificación (sólido) u ondas (líquido).
	float grain = fract(sin(dot(floor(local_pos.xz * 60000.0), vec2(12.9898, 78.233))) * 43758.5453);
	NORMAL = normalize(NORMAL + vec3(ripple * 0.08, (grain - 0.5) * 0.06 * (1.0 - melt), 0.0));
	EMISSION = vec3(1.0, 0.62, 0.3) * melt * 0.35;
}
