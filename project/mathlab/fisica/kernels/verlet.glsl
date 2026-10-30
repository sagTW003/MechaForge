#[compute]
#version 450
// Verlet de velocidades en la GPU, por fases (las fuerzas las calcula coulomb.glsl):
//   modo 0, impulso:  v ← v + h·F/m            (v.w = 1/m)
//   modo 1, deriva:   r ← r + h·v; con extra = caja > 0, choque elástico con las paredes |x| ≤ caja
//   modo 2, rotación de Boris en un campo B según z (extra = B): t = (q/m)Bh/2, s = 2t/(1 + t²)
// Misma cuenta que Coulomb.Kick, Coulomb.Drift y Coulomb.Rotate (dominio/Coulomb.cs).
layout(local_size_x = 64) in;
layout(set = 0, binding = 0, std430) restrict buffer Posiciones { vec4 p[]; };      // xyz, q
layout(set = 0, binding = 1, std430) restrict buffer Velocidades { vec4 v[]; };    // xyz, 1/m
layout(set = 0, binding = 2, std430) restrict readonly buffer Fuerzas { vec4 f[]; };
layout(push_constant, std430) uniform Params { uint n; uint modo; float h; float extra; } pc;

void main() {
	uint i = gl_GlobalInvocationID.x;
	if (i >= pc.n) {
		return;
	}
	if (pc.modo == 0u) {
		v[i].xyz += pc.h * f[i].xyz * v[i].w;
		return;
	}
	if (pc.modo == 2u) {
		float t = p[i].w * v[i].w * pc.extra * pc.h * 0.5;
		float s = 2.0 * t / (1.0 + t * t);
		vec2 u = v[i].xy;
		vec2 w = vec2(u.x + u.y * t, u.y - u.x * t);
		v[i].xy = vec2(u.x + w.y * s, u.y - w.x * s);
		return;
	}
	vec3 x = p[i].xyz + pc.h * v[i].xyz;
	vec3 u = v[i].xyz;
	if (pc.extra > 0.0) {
		for (int k = 0; k < 3; k++) {
			if (x[k] > pc.extra) {
				x[k] = 2.0 * pc.extra - x[k];
				u[k] = -abs(u[k]);
			} else if (x[k] < -pc.extra) {
				x[k] = -2.0 * pc.extra - x[k];
				u[k] = abs(u[k]);
			}
		}
	}
	p[i].xyz = x;
	v[i].xyz = u;
}
