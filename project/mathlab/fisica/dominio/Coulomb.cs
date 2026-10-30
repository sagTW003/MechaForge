using System;
using System.Threading.Tasks;

namespace MechaForge;

/// <summary>
/// Coulomb — Fuerza entre cargas puntuales, todas contra todas, con suavizado ε:
///   F_i = Σ_j q_i q_j (r_i − r_j) / (|r_i − r_j|² + ε²)^{3/2}     (k = 1)
/// Es la referencia en doble precisión del kernel kernels/coulomb.glsl, que hace la
/// misma cuenta en float32 en la GPU; las pruebas comparan uno con otro.
/// Nivel de fidelidad: aproximado (cargas clásicas, sin radiación; ε evita la
/// singularidad cuando dos cargas coinciden).
/// </summary>
public static class Coulomb
{
    /// <summary>p: [x, y, z, q] por carga (el formato del buffer de la GPU). Devuelve [Fx, Fy, Fz, 0].</summary>
    public static float[] Forces(float[] p, double eps2)
    {
        int n = p.Length / 4;
        var f = new float[p.Length];
        Parallel.For(0, n, i =>
        {
            double xi = p[4 * i], yi = p[4 * i + 1], zi = p[4 * i + 2], qi = p[4 * i + 3];
            double fx = 0, fy = 0, fz = 0;
            for (int j = 0; j < n; j++)
            {
                double dx = xi - p[4 * j], dy = yi - p[4 * j + 1], dz = zi - p[4 * j + 2];
                double r2 = dx * dx + dy * dy + dz * dz + eps2;
                double s = qi * p[4 * j + 3] / (r2 * Math.Sqrt(r2));
                fx += s * dx; fy += s * dy; fz += s * dz;
            }
            f[4 * i] = (float)fx; f[4 * i + 1] = (float)fy; f[4 * i + 2] = (float)fz;
        });
        return f;
    }
}
