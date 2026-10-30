#[compute]
#version 450
// Coulomb todas contra todas con suavizado ε (k = 1), en float32:
//   F_i = Σ_j q_i q_j (r_i − r_j) / (|r_i − r_j|² + ε²)^{3/2}
// Misma cuenta que dominio/Coulomb.cs, la referencia en doble precisión.
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
	for (uint j = 0u; j < pc.n; j++) {
		vec3 d = p[i].xyz - p[j].xyz;
		float r2 = dot(d, d) + pc.eps2;
		acc += p[i].w * p[j].w * d / (r2 * sqrt(r2));
	}
	f[i] = vec4(acc, 0.0);
}
