#[compute]
#version 450
// Coulomb todas contra todas con suavizado ε (k = 1), en float32:
//   F_i = Σ_{j≠i} q_i q_j (r_i − r_j) / (|r_i − r_j|² + ε²)^{3/2}
// y en w la energía potencial de cada carga, U_i = Σ_{j≠i} q_i q_j / √(|r_i − r_j|² + ε²)
// (la total es ½ Σ U_i). Misma cuenta que dominio/Coulomb.cs, la referencia en doble.
layout(local_size_x = 64) in;
layout(set = 0, binding = 0, std430) restrict readonly buffer Cargas { vec4 p[]; };    // xyz, q
layout(set = 0, binding = 1, std430) restrict writeonly buffer Fuerzas { vec4 f[]; };
layout(push_constant, std430) uniform Params { uint n; float eps2; } pc;

void main() {
	uint i = gl_GlobalInvocationID.x;
	if (i >= pc.n) {
		return;
	}
	vec3 acc = vec3(0.0);
	float pot = 0.0;
	for (uint j = 0u; j < pc.n; j++) {
		if (j == i) {
			continue;    // con ε = 0 el término propio sería 0/0
		}
		vec3 d = p[i].xyz - p[j].xyz;
		float inv = inversesqrt(dot(d, d) + pc.eps2);
		float qq = p[i].w * p[j].w;
		acc += qq * d * inv * inv * inv;
		pot += qq * inv;
	}
	f[i] = vec4(acc, pot);
}
