shader_type spatial;
// Sección real de la Calabi-Yau de Fermat z₁⁵ + z₂⁵ = 1 (la imagen de Hanson de la quíntica).
// Cada vértice trae (Re z₁, Re z₂) en VERTEX.xz e (Im z₁, Im z₂) en UV; la altura es la
// proyección cos(ángulo)·Im z₁ + sin(ángulo)·Im z₂, que gira con el tiempo. COLOR: el parche.
render_mode cull_disabled, specular_schlick_ggx;

uniform float angulo = 0.6;

void vertex() {
	VERTEX.y = cos(angulo) * UV.x + sin(angulo) * UV.y;
}

void fragment() {
	// Normal de faceta por derivadas de pantalla, hacia la cámara (se ve por las dos caras).
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	NORMAL = dot(n, VERTEX) > 0.0 ? -n : n;
	ALBEDO = COLOR.rgb;
	EMISSION = COLOR.rgb * 0.25;
	ROUGHNESS = 0.45;
}
