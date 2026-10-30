#[compute]
#version 450
// Verlet de velocidades en la GPU, en dos fases (las fuerzas las calcula coulomb.glsl):
//   modo 0, impulso:  v ← v + h·F/m            (v.w = 1/m)
//   modo 1, deriva:   r ← r + h·v; con caja > 0, choque elástico con las paredes |x| ≤ caja
// Misma cuenta que Coulomb.Kick y Coulomb.Drift (dominio/Coulomb.cs).
layout(local_size_x = 64) in;
layout(set = 0, binding = 0, std430) restrict buffer Posiciones { vec4 p[]; };      // xyz, q
layout(set = 0, binding = 1, std430) restrict buffer Velocidades { vec4 v[]; };    // xyz, 1/m
layout(set = 0, binding = 2, std430) restrict readonly buffer Fuerzas { vec4 f[]; };
layout(push_constant, std430) uniform Params { uint n; uint modo; float h; float caja; } pc;

void main() {
	uint i = gl_GlobalInvocationID.x;
	if (i >= pc.n) {
		return;
	}
	if (pc.modo == 0u) {
		v[i].xyz += pc.h * f[i].xyz * v[i].w;
		return;
	}
	vec3 x = p[i].xyz + pc.h * v[i].xyz;
	vec3 u = v[i].xyz;
	if (pc.caja > 0.0) {
		for (int k = 0; k < 3; k++) {
			if (x[k] > pc.caja) {
				x[k] = 2.0 * pc.caja - x[k];
				u[k] = -abs(u[k]);
			} else if (x[k] < -pc.caja) {
				x[k] = -2.0 * pc.caja - x[k];
				u[k] = abs(u[k]);
			}
		}
	}
	p[i].xyz = x;
	v[i].xyz = u;
}
