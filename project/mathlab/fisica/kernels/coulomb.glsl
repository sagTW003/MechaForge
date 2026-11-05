#[compute]
#version 450
// Coulomb todas contra todas con suavizado ε (k = 1), en float32:
//   F_i = Σ_{j≠i} q_i q_j (r_i − r_j) / (|r_i − r_j|² + ε²)^{3/2}
// y en w la energía potencial de cada carga, U_i = Σ_{j≠i} q_i q_j / √(|r_i − r_j|² + ε²)
// (la total es ½ Σ U_i). Misma cuenta que dominio/Coulomb.cs, la referencia en doble.
// Las cargas se leen por bloques de 64 a memoria compartida: cada una sale de la memoria
// global una vez por grupo en lugar de una vez por hilo.
layout(local_size_x = 64) in;
layout(set = 0, binding = 0, std430) restrict readonly buffer Cargas { vec4 p[]; };    // xyz, q
layout(set = 0, binding = 1, std430) restrict writeonly buffer Fuerzas { vec4 f[]; };
layout(push_constant, std430) uniform Params { uint n; float eps2; } pc;

shared vec4 bloque[64];

void main() {
	uint i = gl_GlobalInvocationID.x;
	uint li = gl_LocalInvocationID.x;
	vec4 pi = i < pc.n ? p[i] : vec4(0.0);
	vec3 acc = vec3(0.0);
	float pot = 0.0;
	// Sin «return» antes de barrier(): todos los hilos del grupo tienen que llegar.
	for (uint base = 0u; base < pc.n; base += 64u) {
		uint j = base + li;
		bloque[li] = j < pc.n ? p[j] : vec4(0.0);
		barrier();
		uint m = min(64u, pc.n - base);
		for (uint k = 0u; k < m; k++) {
			if (base + k == i) {
				continue;    // con ε = 0 el término propio sería 0/0
			}
			vec3 d = pi.xyz - bloque[k].xyz;
			float inv = inversesqrt(dot(d, d) + pc.eps2);
			float qq = pi.w * bloque[k].w;
			acc += qq * d * inv * inv * inv;
			pot += qq * inv;
		}
		barrier();
	}
	if (i < pc.n) {
		f[i] = vec4(acc, pot);
	}
}
