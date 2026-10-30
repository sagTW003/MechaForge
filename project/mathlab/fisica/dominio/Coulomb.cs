using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace MechaForge;

/// <summary>
/// Coulomb — Cargas puntuales clásicas, todas contra todas, con suavizado ε (Plummer):
///   F_i = Σ_{j≠i} q_i q_j (r_i − r_j) / (|r_i − r_j|² + ε²)^{3/2}
///   U   = Σ_{i&lt;j}  q_i q_j / √(|r_i − r_j|² + ε²)          (k = 1)
/// En unidades atómicas (e = mₑ = a₀ = 1) k = 1 es exacto. Forces es la referencia en
/// doble precisión del kernel kernels/coulomb.glsl; Kick y Drift forman el integrador
/// de Verlet de velocidades (simpléctico: el error de la energía queda acotado, O(Δt²)).
/// Formato: p = [x, y, z, q], v = [vx, vy, vz, 1/m] y f = [Fx, Fy, Fz, U_i] por carga, con
/// U_i = Σ_{j≠i} q_i q_j / √(r² + ε²) la energía potencial de cada una (U = ½ Σ U_i).
/// Nivel de fidelidad: aproximado (sin radiación, magnetismo ni mecánica cuántica).
/// Referencias: Jackson, Classical Electrodynamics, cap. 1; Hockney y Eastwood, Computer
/// Simulation Using Particles (suavizado); Swope et al., J. Chem. Phys. 76, 637 (1982).
/// </summary>
public static class Coulomb
{
    public static float[] Forces(float[] p, double eps2)
    {
        int n = p.Length / 4;
        var f = new float[p.Length];
        Parallel.For(0, n, i =>
        {
            double xi = p[4 * i], yi = p[4 * i + 1], zi = p[4 * i + 2], qi = p[4 * i + 3];
            double fx = 0, fy = 0, fz = 0, u = 0;
            for (int j = 0; j < n; j++)
            {
                if (j == i) continue;      // con ε = 0 el término propio sería 0/0
                double dx = xi - p[4 * j], dy = yi - p[4 * j + 1], dz = zi - p[4 * j + 2];
                double inv = 1.0 / Math.Sqrt(dx * dx + dy * dy + dz * dz + eps2);
                double qq = qi * p[4 * j + 3];
                double s = qq * inv * inv * inv;
                fx += s * dx; fy += s * dy; fz += s * dz;
                u += qq * inv;
            }
            f[4 * i] = (float)fx; f[4 * i + 1] = (float)fy; f[4 * i + 2] = (float)fz; f[4 * i + 3] = (float)u;
        });
        return f;
    }

    /// <summary>v ← v + h·F/m.</summary>
    public static float[] Kick(float[] v, float[] f, double h)
    {
        var o = (float[])v.Clone();
        for (int i = 0; i < v.Length; i += 4)
        {
            double s = h * v[i + 3];
            o[i] += (float)(s * f[i]); o[i + 1] += (float)(s * f[i + 1]); o[i + 2] += (float)(s * f[i + 2]);
        }
        return o;
    }

    /// <summary>
    /// r ← r + h·v; con box &gt; 0, las cargas rebotan en las paredes del cubo |x|, |y|, |z| ≤ box
    /// (choque elástico: se refleja la posición y la componente de la velocidad).
    /// Devuelve p y v seguidos (8 valores por carga).
    /// </summary>
    public static float[] Drift(float[] p, float[] v, double h, double box)
    {
        int n = p.Length / 4;
        var o = new float[p.Length * 2];
        Array.Copy(p, o, p.Length);
        Array.Copy(v, 0, o, p.Length, v.Length);
        for (int i = 0; i < n; i++)
            for (int k = 0; k < 3; k++)
            {
                int a = 4 * i + k, b = p.Length + 4 * i + k;
                double x = p[a] + h * v[a];
                if (box > 0.0)
                {
                    if (x > box) { x = 2.0 * box - x; o[b] = -Math.Abs(v[a]); }
                    else if (x < -box) { x = -2.0 * box - x; o[b] = Math.Abs(v[a]); }
                }
                o[a] = (float)x;
            }
        return o;
    }

    /// <summary>[cinética, potencial, px, py, pz]: energía y momento totales.</summary>
    public static double[] Energy(float[] p, float[] v, double eps2)
    {
        int n = p.Length / 4;
        double kin = 0, px = 0, py = 0, pz = 0;
        for (int i = 0; i < n; i++)
        {
            double m = 1.0 / v[4 * i + 3];
            double vx = v[4 * i], vy = v[4 * i + 1], vz = v[4 * i + 2];
            kin += 0.5 * m * (vx * vx + vy * vy + vz * vz);
            px += m * vx; py += m * vy; pz += m * vz;
        }
        var part = new double[n];
        Parallel.For(0, n, i =>
        {
            double s = 0;
            for (int j = i + 1; j < n; j++)
            {
                double dx = p[4 * i] - p[4 * j], dy = p[4 * i + 1] - p[4 * j + 1], dz = p[4 * i + 2] - p[4 * j + 2];
                s += p[4 * i + 3] * p[4 * j + 3] / Math.Sqrt(dx * dx + dy * dy + dz * dz + eps2);
            }
            part[i] = s;
        });
        double pot = 0;
        foreach (double s in part) pot += s;
        return new[] { kin, pot, px, py, pz };
    }

    /// <summary>
    /// Rotación de Boris en un campo B uniforme según z durante h (fuerza de Lorentz q v × B en
    /// unidades atómicas): t = (q/m)·B·h/2, s = 2t/(1 + t²); v' = v + v × t; v ← v + v' × s.
    /// Conserva |v| exactamente; gira un ángulo 2·atan(qBh/2m) por paso (Boris, 1970).
    /// </summary>
    public static float[] Rotate(float[] p, float[] v, double bz, double h)
    {
        var o = (float[])v.Clone();
        for (int i = 0; i < v.Length; i += 4)
        {
            double t = p[i + 3] * v[i + 3] * bz * h * 0.5, s = 2.0 * t / (1.0 + t * t);
            double vx = v[i], vy = v[i + 1];
            double px = vx + vy * t, py = vy - vx * t;
            o[i] = (float)(vx + py * s); o[i + 1] = (float)(vy - px * s);
        }
        return o;
    }

    /// <summary>
    /// Líneas del campo E de las cargas: de cada carga positiva salen k líneas (direcciones de una
    /// espiral de Fibonacci) que siguen E/|E| con RK4 de paso ds hasta acercarse a una negativa,
    /// salir del cubo |x| ≤ lim o dar maxSteps pasos. Sin positivas, salen de las negativas hacia −E.
    /// Devuelve x, y, z de los puntos, con un NaN entre líneas.
    /// </summary>
    public static float[] FieldLines(float[] p, double eps2, int k, int maxSteps, double ds, double lim)
    {
        int n = p.Length / 4;
        var o = new List<float>();
        bool hayPos = false;
        for (int i = 0; i < n; i++) if (p[4 * i + 3] > 0) { hayPos = true; break; }
        double signo = hayPos ? 1.0 : -1.0;
        (double, double, double) Dir(double x, double y, double z)
        {
            double ex = 0, ey = 0, ez = 0;
            for (int j = 0; j < n; j++)
            {
                double dx = x - p[4 * j], dy = y - p[4 * j + 1], dz = z - p[4 * j + 2];
                double r2 = dx * dx + dy * dy + dz * dz + eps2, s = p[4 * j + 3] / (r2 * Math.Sqrt(r2));
                ex += s * dx; ey += s * dy; ez += s * dz;
            }
            double m = Math.Sqrt(ex * ex + ey * ey + ez * ez);
            return m > 0 ? (signo * ex / m, signo * ey / m, signo * ez / m) : (0, 0, 0);
        }
        for (int i = 0; i < n; i++)
        {
            if (Math.Sign(p[4 * i + 3]) != (int)signo) continue;
            for (int a = 0; a < k; a++)
            {
                double cz = 1.0 - 2.0 * (a + 0.5) / k, sz = Math.Sqrt(1.0 - cz * cz), f = a * 2.399963229728653;
                double x = p[4 * i] + 0.05 * sz * Math.Cos(f), y = p[4 * i + 1] + 0.05 * sz * Math.Sin(f), z = p[4 * i + 2] + 0.05 * cz;
                for (int st = 0; st < maxSteps; st++)
                {
                    o.Add((float)x); o.Add((float)y); o.Add((float)z);
                    var (k1x, k1y, k1z) = Dir(x, y, z);
                    var (k2x, k2y, k2z) = Dir(x + 0.5 * ds * k1x, y + 0.5 * ds * k1y, z + 0.5 * ds * k1z);
                    var (k3x, k3y, k3z) = Dir(x + 0.5 * ds * k2x, y + 0.5 * ds * k2y, z + 0.5 * ds * k2z);
                    var (k4x, k4y, k4z) = Dir(x + ds * k3x, y + ds * k3y, z + ds * k3z);
                    x += ds / 6 * (k1x + 2 * k2x + 2 * k3x + k4x);
                    y += ds / 6 * (k1y + 2 * k2y + 2 * k3y + k4y);
                    z += ds / 6 * (k1z + 2 * k2z + 2 * k3z + k4z);
                    if (Math.Abs(x) > lim || Math.Abs(y) > lim || Math.Abs(z) > lim) break;
                    bool llega = false;
                    for (int j = 0; j < n && !llega; j++)
                    {
                        if (Math.Sign(p[4 * j + 3]) == (int)signo) continue;
                        double dx = x - p[4 * j], dy = y - p[4 * j + 1], dz = z - p[4 * j + 2];
                        llega = dx * dx + dy * dy + dz * dz < 0.0016;
                    }
                    if (llega) { o.Add((float)x); o.Add((float)y); o.Add((float)z); break; }
                }
                o.Add(float.NaN); o.Add(float.NaN); o.Add(float.NaN);
            }
        }
        return o.ToArray();
    }

    /// <summary>[cinética, potencial, px, py, pz] en O(N), con la potencial de las fuerzas (½ Σ U_i).</summary>
    public static double[] EnergyFromForces(float[] v, float[] f)
    {
        double kin = 0, pot = 0, px = 0, py = 0, pz = 0;
        for (int i = 0; i < v.Length; i += 4)
        {
            double m = 1.0 / v[i + 3];
            double vx = v[i], vy = v[i + 1], vz = v[i + 2];     // en double: float·float pierde cifras
            kin += 0.5 * m * (vx * vx + vy * vy + vz * vz);
            px += m * vx; py += m * vy; pz += m * vz;
            pot += 0.5 * f[i + 3];
        }
        return new[] { kin, pot, px, py, pz };
    }

    public static bool AllFinite(float[] a)
    {
        foreach (float x in a)
            if (!float.IsFinite(x)) return false;
        return true;
    }
}
