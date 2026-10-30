using System;
using System.Collections.Generic;
using System.Numerics;

namespace MechaForge;

/// <summary>
/// Compactas — Cuerda cerrada libre en un toro rectangular T^k (radios R_i, sin campo B):
///   M² = Σ_i [(n_i/R_i)² + (w_i R_i/α′)²] + (2/α′)(N + Ñ − 2a),   N − Ñ = Σ_i n_i w_i,
/// con a = 1 en la bosónica y a = 0 en la tipo II (N, Ñ: niveles tras la GSO, como en Cuerdas).
/// n: momento de Kaluza-Klein; w: veces que la cuerda da la vuelta (enrollamiento).
/// Dualidad T: R → α′/R con n ↔ w deja el espectro igual; en R = √α′ aparecen bosones gauge
/// sin masa extra (SU(2) × SU(2) en la bosónica).
/// Calabi-Yau: χ de hipersuperficies de CPⁿ por la clase de Chern, y la sección real de la
/// de Fermat zⁿ + wⁿ = 1 de Hanson (la imagen habitual de la quíntica; ilustrativa).
/// Referencias: Polchinski I, §8.1–8.3; Zwiebach, cap. 17–18; Candelas, Horowitz, Strominger
/// y Witten, Nucl. Phys. B 258, 46 (1985); Hanson, Notices AMS 41, 1156 (1994).
/// </summary>
public static class Compactas
{
    public static double Mass2(bool super, double alpha, double[] radios, int[] n, int[] w, int nl, int nr)
    {
        double m2 = 2.0 / alpha * (nl + nr - (super ? 0 : 2));
        for (int i = 0; i < radios.Length; i++)
            m2 += Math.Pow(n[i] / radios[i], 2) + Math.Pow(w[i] * radios[i] / alpha, 2);
        return m2;
    }

    public static bool LevelMatched(int[] n, int[] w, int nl, int nr)
    {
        int s = 0;
        for (int i = 0; i < n.Length; i++) s += n[i] * w[i];
        return nl - nr == s;
    }

    /// <summary>
    /// Estados en un círculo de radio R con |n|, |w| ≤ 3 y N, Ñ ≤ 2 que cumplen el emparejamiento,
    /// de menor a mayor M²: [n, w, N, Ñ, M²] seguidos.
    /// </summary>
    public static double[] CircleSpectrum(bool super, double alpha, double r, int count)
    {
        var l = new List<double[]>();
        var rad = new[] { r };
        for (int n = -3; n <= 3; n++)
            for (int w = -3; w <= 3; w++)
                for (int nl = 0; nl <= 2; nl++)
                    for (int nr = 0; nr <= 2; nr++)
                        if (nl - nr == n * w)
                            l.Add(new double[] { n, w, nl, nr, Mass2(super, alpha, rad, new[] { n }, new[] { w }, nl, nr) });
        l.Sort((a, b) => a[4] != b[4] ? a[4].CompareTo(b[4]) : (Math.Abs(a[0]) + Math.Abs(a[1])).CompareTo(Math.Abs(b[0]) + Math.Abs(b[1])));
        int m = Math.Min(count, l.Count);
        var o = new double[5 * m];
        for (int i = 0; i < m; i++) Array.Copy(l[i], 0, o, 5 * i, 5);
        return o;
    }

    /// <summary>χ de una hipersuperficie lisa de grado d en CPⁿ: d por el coeficiente de H^{n−1} en (1 + H)^{n+1}/(1 + dH).</summary>
    public static long HypersurfaceEuler(int d, int n)
    {
        long c = 0, pot = 1;
        for (int j = 0; j <= n - 1; j++, pot *= -d)
            c += Binom(n + 1, n - 1 - j) * pot;
        return d * c;
    }

    static long Binom(int n, int k)
    {
        long b = 1;
        for (int i = 1; i <= k; i++) b = b * (n - k + i) / i;
        return b;
    }

    /// <summary>
    /// Sección real de z₁ⁿ + z₂ⁿ = 1 en C² (Hanson): z₁ = e^{2πik₁/n} cos(ξ)^{2/n}, z₂ = e^{2πik₂/n} sin(ξ)^{2/n},
    /// ξ = a + ib con a ∈ [0, π/2], b ∈ [−bmax, bmax]; n² parches de grid × grid vértices, cada uno
    /// (Re z₁, Re z₂, Im z₁, Im z₂). Con la rama principal, (cos ξ^{2/n})ⁿ = cos² ξ: la ecuación se cumple exacta.
    /// </summary>
    public static double[] FermatSection(int n, int grid, double bmax)
    {
        var o = new double[n * n * grid * grid * 4];
        int idx = 0;
        for (int k1 = 0; k1 < n; k1++)
            for (int k2 = 0; k2 < n; k2++)
            {
                var f1 = Complex.FromPolarCoordinates(1.0, 2.0 * Math.PI * k1 / n);
                var f2 = Complex.FromPolarCoordinates(1.0, 2.0 * Math.PI * k2 / n);
                for (int i = 0; i < grid; i++)
                    for (int j = 0; j < grid; j++)
                    {
                        var xi = new Complex(0.5 * Math.PI * i / (grid - 1), bmax * (2.0 * j / (grid - 1) - 1.0));
                        var z1 = f1 * Complex.Pow(Complex.Cos(xi), 2.0 / n);
                        var z2 = f2 * Complex.Pow(Complex.Sin(xi), 2.0 / n);
                        o[idx++] = z1.Real; o[idx++] = z2.Real; o[idx++] = z1.Imaginary; o[idx++] = z2.Imaginary;
                    }
            }
        return o;
    }
}
