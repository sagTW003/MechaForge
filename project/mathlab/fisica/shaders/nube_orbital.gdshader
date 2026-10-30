shader_type spatial;
// Nube orbital: un cuadrado encarado a la cámara por cada punto muestreado de |ψ|², con
// la fase de ψ (INSTANCE_CUSTOM.r) como tono de la rueda de color del laboratorio.
// Mezcla aditiva: donde hay más puntos (más probabilidad) hay más luz.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
#include "res://mathlab/shaders/common.gdshaderinc"

uniform float phase_offset = 0.0;    // −Eₙt/ħ: la fase global gira y |ψ|² no cambia
uniform float brightness = 0.55;
varying float fase;
varying vec3 wpos;

void vertex() {
	fase = INSTANCE_CUSTOM.r;
	wpos = MODEL_MATRIX[3].xyz;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	if (clipped(wpos)) discard;
	vec2 d = UV * 2.0 - 1.0;
	float a = clamp(1.0 - dot(d, d), 0.0, 1.0);
	ALBEDO = hue_color(fase + phase_offset) * a * a * brightness;
}
