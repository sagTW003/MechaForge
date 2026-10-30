using System;
using System.Numerics;

namespace MechaForge;

/// <summary>
/// Hidrogeno — Átomo de hidrógeno no relativista, en unidades atómicas (a₀ = Eₕ = ħ = 1):
///   ψ_nlm(r, θ, φ) = R_nl(r) · Y_l^m(θ, φ),     E_n = −1/(2n²) Eₕ
///   R_nl(r) = √[(2/n)³ (n−l−1)! / (2n (n+l)!)] · e^{−ρ/2} ρ^l L_{n−l−1}^{(2l+1)}(ρ),  ρ = 2r/n
///   Y_l^m con la fase de Condon–Shortley.
/// Núcleo puntual infinitamente pesado (EnergyEv admite la masa reducida); sin
/// estructura fina, espín ni corrimiento de Lamb. Nivel de fidelidad: exacto.
/// Referencias: Griffiths, Introduction to Quantum Mechanics, §4.2; Bransden y
/// Joachain, Physics of Atoms and Molecules, cap. 3.
/// </summary>
public static class Hidrogeno
{
    public static bool Valid(int n, int l, int m) => n >= 1 && l >= 0 && l < n && Math.Abs(m) <= l;

    /// <summary>E_n en eV; con masa reducida, multiplicada por μ/mₑ = mₚ/(mₚ + mₑ).</summary>
    public static double EnergyEv(int n, bool reducedMass)
    {
        double e = -0.5 / ((double)n * n) * Unidades.Hartree_eV;
        return reducedMass ? e * Unidades.MpMe / (Unidades.MpMe + 1.0) : e;
    }

    /// <summary>⟨r⟩ = (3n² − l(l+1))/2 y ⟨r²⟩ = n²(5n² + 1 − 3l(l+1))/2, en a₀.</summary>
    public static double MeanR(int n, int l) => 0.5 * (3.0 * n * n - l * (l + 1));
    public static double MeanR2(int n, int l) => 0.5 * n * n * (5.0 * n * n + 1 - 3.0 * l * (l + 1));

    static double Factorial(int k)
    {
        double f = 1;
        for (int i = 2; i <= k; i++) f *= i;
        return f;
    }

    /// <summary>Laguerre generalizado L_k^{(α)}(x) por recurrencia.</summary>
    static double Laguerre(int k, double alpha, double x)
    {
        if (k == 0) return 1.0;
        double l0 = 1.0, l1 = 1.0 + alpha - x;
        for (int i = 1; i < k; i++)
        {
            double l2 = ((2 * i + 1 + alpha - x) * l1 - (i + alpha) * l0) / (i + 1);
            l0 = l1; l1 = l2;
        }
        return l1;
    }

    public static double Radial(int n, int l, double r)
    {
        double rho = 2.0 * r / n;
        double norm = Math.Sqrt(Math.Pow(2.0 / n, 3) * Factorial(n - l - 1) / (2.0 * n * Factorial(n + l)));
        return norm * Math.Exp(-rho / 2.0) * Math.Pow(rho, l) * Laguerre(n - l - 1, 2 * l + 1, rho);
    }

    /// <summary>P_l^m(x), m ≥ 0, con la fase de Condon–Shortley (recurrencia en l).</summary>
    static double Legendre(int l, int m, double x)
    {
        double pmm = 1.0;
        double s = Math.Sqrt((1.0 - x) * (1.0 + x)), fact = 1.0;
        for (int i = 1; i <= m; i++) { pmm *= -fact * s; fact += 2.0; }
        if (l == m) return pmm;
        double pmm1 = x * (2 * m + 1) * pmm;
        if (l == m + 1) return pmm1;
        double pll = 0.0;
        for (int ll = m + 2; ll <= l; ll++)
        {
            pll = (x * (2 * ll - 1) * pmm1 - (ll + m - 1) * pmm) / (ll - m);
            pmm = pmm1; pmm1 = pll;
        }
        return pll;
    }

    /// <summary>Y_l^m(θ, φ); para m &lt; 0, Y_l^{−|m|} = (−1)^|m| conj(Y_l^{|m|}).</summary>
    public static Complex Ylm(int l, int m, double theta, double phi)
    {
        int am = Math.Abs(m);
        double a = Math.Sqrt((2 * l + 1) / (4.0 * Math.PI) * Factorial(l - am) / Factorial(l + am)) * Legendre(l, am, Math.Cos(theta));
        var y = new Complex(a * Math.Cos(am * phi), a * Math.Sin(am * phi));
        return m >= 0 ? y : (am % 2 == 0 ? 1.0 : -1.0) * Complex.Conjugate(y);
    }

    public static Complex Psi(int n, int l, int m, double x, double y, double z)
    {
        double r = Math.Sqrt(x * x + y * y + z * z);
        double theta = r > 0.0 ? Math.Acos(Math.Clamp(z / r, -1.0, 1.0)) : 0.0;
        return Radial(n, l, r) * Ylm(l, m, theta, Math.Atan2(y, x));
    }

    /// <summary>Radio hasta el que llega la densidad radial (la cola más allá es &lt; 10⁻¹⁰).</summary>
    public static double RMax(int n) => 0.5 * n * (2.0 * n + 12.0 * Math.Sqrt(2.0 * n) + 30.0);

    /// <summary>Malla de [a, b] y la acumulada normalizada (trapecios) de la densidad f.</summary>
    static (double[] x, double[] c) Cdf(Func<double, double> f, double a, double b, int k)
    {
        var x = new double[k + 1];
        var c = new double[k + 1];
        double h = (b - a) / k, prev = f(a);
        x[0] = a;
        for (int i = 1; i <= k; i++)
        {
            x[i] = a + i * h;
            double cur = f(x[i]);
            c[i] = c[i - 1] + 0.5 * h * (prev + cur);
            prev = cur;
        }
        for (int i = 1; i <= k; i++) c[i] /= c[k];
        return (x, c);
    }

    static double Inverse(double[] x, double[] c, double u)
    {
        int i = Array.BinarySearch(c, u);
        if (i >= 0) return x[i];
        i = ~i;
        if (i <= 0) return x[0];
        if (i >= c.Length) return x[^1];
        double t = (u - c[i - 1]) / Math.Max(1e-300, c[i] - c[i - 1]);
        return x[i - 1] + t * (x[i] - x[i - 1]);
    }

    /// <summary>Radio que encierra la fracción q de la probabilidad.</summary>
    public static double RadiusQuantile(int n, int l, double q)
    {
        var (x, c) = Cdf(r => r * r * Math.Pow(Radial(n, l, r), 2), 0.0, RMax(n), 4000);
        return Inverse(x, c, q);
    }

    /// <summary>
    /// count puntos con densidad |ψ_nlm|² exacta: |ψ|² = R²(r)·|Θ_lm(θ)|²/2π se factoriza,
    /// así que r sale de la inversa de la acumulada de r²R², θ de la de sinθ·P_l^m² y φ
    /// es uniforme. Devuelve [x, y, z, arg ψ] por punto, en a₀ (vacío si n, l, m no valen).
    /// </summary>
    public static float[] Sample(int n, int l, int m, int count, int seed)
    {
        if (!Valid(n, l, m) || count <= 0) return Array.Empty<float>();
        var (rx, rc) = Cdf(r => r * r * Math.Pow(Radial(n, l, r), 2), 0.0, RMax(n), 4000);
        int am = Math.Abs(m);
        var (tx, tc) = Cdf(t => Math.Sin(t) * Math.Pow(Legendre(l, am, Math.Cos(t)), 2), 0.0, Math.PI, 2000);
        var rng = new Random(seed);
        var o = new float[count * 4];
        for (int i = 0; i < count; i++)
        {
            double r = Inverse(rx, rc, rng.NextDouble());
            double th = Inverse(tx, tc, rng.NextDouble());
            double ph = 2.0 * Math.PI * rng.NextDouble();
            double x = r * Math.Sin(th) * Math.Cos(ph), y = r * Math.Sin(th) * Math.Sin(ph), z = r * Math.Cos(th);
            Complex psi = Radial(n, l, r) * Ylm(l, m, th, ph);
            o[4 * i] = (float)x; o[4 * i + 1] = (float)y; o[4 * i + 2] = (float)z;
            o[4 * i + 3] = (float)Math.Atan2(psi.Imaginary, psi.Real);
        }
        return o;
    }

    /// <summary>∫₀^∞ r^k R² r² dr por Simpson (k = 0: norma; k = 1: ⟨r⟩), para las pruebas.</summary>
    public static double RadialMoment(int n, int l, int k)
    {
        int steps = 20000;
        double b = RMax(n), h = b / steps, s = 0.0;
        for (int i = 0; i <= steps; i++)
        {
            double r = i * h, w = (i == 0 || i == steps) ? 1 : (i % 2 == 1 ? 4 : 2);
            s += w * Math.Pow(r, k + 2) * Math.Pow(Radial(n, l, r), 2);
        }
        return s * h / 3.0;
    }

    /// <summary>∫|Y_l^m|² dΩ por Simpson en θ (|Y|² no depende de φ), para las pruebas.</summary>
    public static double YlmNorm(int l, int m)
    {
        int steps = 4000;
        double h = Math.PI / steps, s = 0.0;
        for (int i = 0; i <= steps; i++)
        {
            double t = i * h, w = (i == 0 || i == steps) ? 1 : (i % 2 == 1 ? 4 : 2);
            s += w * Math.Sin(t) * Complex.Abs(Ylm(l, m, t, 0.3)) * Complex.Abs(Ylm(l, m, t, 0.3));
        }
        return 2.0 * Math.PI * s * h / 3.0;
    }
}
