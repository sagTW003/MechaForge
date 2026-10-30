using System;
using System.Threading.Tasks;

namespace MechaForge;

/// <summary>
/// CadenaEspines — Batería cuántica de N ≤ 12 espines ½ (dimensión 2^N ≤ 4096), ħ = 1:
///   batería   H_B = (ω₀/2) Σᵢ σᶻᵢ + H_int,  H_int = J Σᵢ (σˣᵢσˣᵢ₊₁ + σʸᵢσʸᵢ₊₁ + Δ σᶻᵢσᶻᵢ₊₁)  (cadena abierta)
///   cargador  g Σᵢ σˣᵢ, resonante: en el sistema que rota con ω₀ la evolución es
///             H_rot = H_int + g Σᵢ σˣᵢ (H_int conserva Σσᶻ y no cambia al rotar).
/// La energía de la batería ⟨H_B⟩ es la misma en los dos sistemas. Evolución unitaria exacta
/// por subespacios de Krylov (Lanczos con reortogonalización completa) y la exponencial de la
/// matriz tridiagonal por Jacobi. Estado: [Re, Im] de cada amplitud; bit i = 1 es |↑⟩.
/// Ergotropía: máximo trabajo extraíble con operaciones unitarias (Allahverdyan, Balian y
/// Nieuwenhuizen, Europhys. Lett. 67, 565 (2004)); para un estado puro, ⟨H_B⟩ − E_mín(H_B).
/// Modelo inspirado en Le, Levinsen, Modi, Parish y Pollock, Phys. Rev. A 97, 022106 (2018).
/// </summary>
public static class CadenaEspines
{
    /// <summary>
    /// y = H ψ con H = zeeman·(ω₀/2)Σσᶻ + J Σ(XX + YY + Δ ZZ) + g Σσˣ. Cada amplitud de salida
    /// recoge las de sus vecinas (H es real y simétrica): sin escrituras cruzadas, en paralelo.
    /// </summary>
    static void Apply(int n, double w0z, double j, double d, double g, double[] psi, double[] y)
    {
        int dim = 1 << n;
        void Row(int s)
        {
            double diag = 0.0, yr = 0.0, yi = 0.0;
            for (int i = 0; i < n; i++)
            {
                bool up = ((s >> i) & 1) == 1;
                diag += 0.5 * w0z * (up ? 1.0 : -1.0);
                if (g != 0.0)
                {
                    int t = s ^ (1 << i);
                    yr += g * psi[2 * t]; yi += g * psi[2 * t + 1];
                }
                if (i + 1 < n)
                {
                    bool up2 = ((s >> (i + 1)) & 1) == 1;
                    diag += j * d * (up == up2 ? 1.0 : -1.0);
                    if (up != up2 && j != 0.0)
                    {
                        // σˣσˣ + σʸσʸ = 2(σ⁺σ⁻ + σ⁻σ⁺): intercambia ↑↓ ↔ ↓↑ con amplitud 2J.
                        int t = s ^ (3 << i);
                        yr += 2.0 * j * psi[2 * t]; yi += 2.0 * j * psi[2 * t + 1];
                    }
                }
            }
            y[2 * s] = yr + diag * psi[2 * s];
            y[2 * s + 1] = yi + diag * psi[2 * s + 1];
        }
        if (dim >= 1024) Parallel.For(0, dim, Row);
        else for (int s = 0; s < dim; s++) Row(s);
    }

    static (double re, double im) Dot(double[] a, double[] b)
    {
        double re = 0, im = 0;
        for (int k = 0; k < a.Length; k += 2)
        {
            re += a[k] * b[k] + a[k + 1] * b[k + 1];
            im += a[k] * b[k + 1] - a[k + 1] * b[k];
        }
        return (re, im);
    }

    static double Norm(double[] a) => Math.Sqrt(Dot(a, a).re);

    /// <summary>Autovalores y autovectores (columnas de v) de una simétrica real por Jacobi cíclico.</summary>
    static void Jacobi(double[,] a, int m, double[] w, double[,] v)
    {
        for (int i = 0; i < m; i++) for (int k = 0; k < m; k++) v[i, k] = i == k ? 1 : 0;
        for (int sweep = 0; sweep < 100; sweep++)
        {
            double off = 0;
            for (int p = 0; p < m; p++) for (int q = p + 1; q < m; q++) off += a[p, q] * a[p, q];
            if (off < 1e-30) break;
            for (int p = 0; p < m; p++)
                for (int q = p + 1; q < m; q++)
                {
                    if (Math.Abs(a[p, q]) < 1e-300) continue;
                    double th = (a[q, q] - a[p, p]) / (2 * a[p, q]);
                    double t = Math.Sign(th) / (Math.Abs(th) + Math.Sqrt(th * th + 1));
                    if (th == 0) t = 1;
                    double c = 1 / Math.Sqrt(t * t + 1), s = t * c;
                    for (int k = 0; k < m; k++)
                    {
                        double akp = a[k, p], akq = a[k, q];
                        a[k, p] = c * akp - s * akq; a[k, q] = s * akp + c * akq;
                    }
                    for (int k = 0; k < m; k++)
                    {
                        double apk = a[p, k], aqk = a[q, k];
                        a[p, k] = c * apk - s * aqk; a[q, k] = s * apk + c * aqk;
                    }
                    for (int k = 0; k < m; k++)
                    {
                        double vkp = v[k, p], vkq = v[k, q];
                        v[k, p] = c * vkp - s * vkq; v[k, q] = s * vkp + c * vkq;
                    }
                }
        }
        for (int i = 0; i < m; i++) w[i] = a[i, i];
    }

    /// <summary>
    /// Base de Krylov (Lanczos, reortogonalización completa) y la tridiagonal T. Con dt &gt; 0 se
    /// para en cuanto el error estimado de e^{−iHdt}ψ, β·|última componente de e^{−iTdt}e₁|
    /// (Saad, 1992), baja de 10⁻¹³: no hace falta llegar siempre a mMax.
    /// </summary>
    static (double[][] vecs, double[,] T, int m) Krylov(int n, double w0z, double j, double d, double g, double[] psi, int mMax, double dt = 0.0)
    {
        int len = psi.Length;
        double b0 = Norm(psi);
        var vecs = new double[mMax][];
        var T = new double[mMax, mMax];
        vecs[0] = new double[len];
        for (int k = 0; k < len; k++) vecs[0][k] = psi[k] / b0;
        var w = new double[len];
        int m = mMax;
        for (int it = 0; it < mMax; it++)
        {
            Apply(n, w0z, j, d, g, vecs[it], w);
            for (int pass = 0; pass < 2; pass++)
                for (int k = 0; k <= it; k++)
                {
                    var (re, im) = Dot(vecs[k], w);
                    if (pass == 0 && k == it) T[it, it] = re;
                    for (int x = 0; x < len; x += 2)
                    {
                        double vr = vecs[k][x], vi = vecs[k][x + 1];
                        w[x] -= re * vr - im * vi; w[x + 1] -= re * vi + im * vr;
                    }
                }
            if (it + 1 == mMax) break;
            double beta = Norm(w);
            if (beta < 1e-12) { m = it + 1; break; }
            if (dt > 0.0 && it >= 5 && beta * Math.Abs(LastExpComponent(T, it + 1, dt)) < 1e-13) { m = it + 1; break; }
            T[it, it + 1] = T[it + 1, it] = beta;
            vecs[it + 1] = new double[len];
            for (int k = 0; k < len; k++) vecs[it + 1][k] = w[k] / beta;
        }
        return (vecs, T, m);
    }

    /// <summary>|[e^{−iTdt}]_{m−1,0}| de la tridiagonal m×m (para el criterio de parada).</summary>
    static double LastExpComponent(double[,] T, int m, double dt)
    {
        var a = new double[m, m];
        for (int p = 0; p < m; p++) for (int q = 0; q < m; q++) a[p, q] = T[p, q];
        var wv = new double[m];
        var u = new double[m, m];
        Jacobi(a, m, wv, u);
        double cr = 0, ci = 0;
        for (int l = 0; l < m; l++)
        {
            double f = u[m - 1, l] * u[0, l];
            cr += f * Math.Cos(wv[l] * dt); ci -= f * Math.Sin(wv[l] * dt);
        }
        return Math.Sqrt(cr * cr + ci * ci);
    }

    /// <summary>exp(−i H_rot dt) ψ, con H_rot = H_int + gΣσˣ (sin el término de Zeeman).</summary>
    public static double[] Step(double[] psi, int n, double j, double d, double g, double dt)
    {
        int dim = 1 << n;
        int mMax = Math.Min(24, dim);
        double b0 = Norm(psi);
        var (vecs, T, m) = Krylov(n, 0.0, j, d, g, psi, mMax, dt);
        var a = new double[m, m];
        for (int p = 0; p < m; p++) for (int q = 0; q < m; q++) a[p, q] = T[p, q];
        var wv = new double[m];
        var u = new double[m, m];
        Jacobi(a, m, wv, u);
        var o = new double[psi.Length];
        for (int k = 0; k < m; k++)
        {
            // c_k = Σ_l U_kl e^{−iλ_l dt} U_0l
            double cr = 0, ci = 0;
            for (int l = 0; l < m; l++)
            {
                double f = u[k, l] * u[0, l];
                cr += f * Math.Cos(wv[l] * dt); ci -= f * Math.Sin(wv[l] * dt);
            }
            cr *= b0; ci *= b0;
            var vk = vecs[k];
            for (int x = 0; x < o.Length; x += 2)
            {
                o[x] += cr * vk[x] - ci * vk[x + 1];
                o[x + 1] += cr * vk[x + 1] + ci * vk[x];
            }
        }
        return o;
    }

    /// <summary>Estado vacío: todos los espines abajo, |↓↓…↓⟩.</summary>
    public static double[] Empty(int n)
    {
        var o = new double[2 << n];
        o[0] = 1.0;
        return o;
    }

    /// <summary>E_mín(H_B) por Lanczos con reinicios desde un vector al azar (todos los sectores de Sᶻ).</summary>
    public static double GroundEnergy(int n, double w0, double j, double d)
    {
        int dim = 1 << n, len = 2 * dim;
        var rng = new Random(12345);
        var psi = new double[len];
        for (int k = 0; k < len; k += 2) psi[k] = rng.NextDouble() - 0.5;
        double e = double.MaxValue;
        var y = new double[len];
        for (int restart = 0; restart < 30; restart++)
        {
            int mMax = Math.Min(60, dim);
            var (vecs, T, m) = Krylov(n, w0, j, d, 0.0, psi, mMax);
            var a = new double[m, m];
            for (int p = 0; p < m; p++) for (int q = 0; q < m; q++) a[p, q] = T[p, q];
            var wv = new double[m];
            var u = new double[m, m];
            Jacobi(a, m, wv, u);
            int lo = 0;
            for (int k = 1; k < m; k++) if (wv[k] < wv[lo]) lo = k;
            var r = new double[len];
            for (int k = 0; k < m; k++)
                for (int x = 0; x < len; x++) r[x] += u[k, lo] * vecs[k][x];
            double nr = Norm(r);
            for (int x = 0; x < len; x++) r[x] /= nr;
            Apply(n, w0, j, d, 0.0, r, y);
            double res = 0;
            for (int x = 0; x < len; x++) { double dd = y[x] - wv[lo] * r[x]; res += dd * dd; }
            e = wv[lo];
            psi = r;
            if (Math.Sqrt(res) < 1e-10 || m < mMax) break;
        }
        return e;
    }

    /// <summary>
    /// [⟨H_B⟩, ⟨H_rot⟩, norma, ergotropía local, rx₀, ry₀, rz₀, rx₁, …]: energías, norma, la
    /// ergotropía extraíble espín a espín, Σᵢ (ω₀/2)(rᶻᵢ + |rᵢ|) respecto de (ω₀/2)σᶻᵢ, y el
    /// vector de Bloch de cada espín.
    /// </summary>
    public static double[] Observables(double[] psi, int n, double w0, double j, double d, double g)
    {
        int dim = 1 << n;
        var y = new double[psi.Length];
        Apply(n, w0, j, d, 0.0, psi, y);
        double eb = Dot(psi, y).re;
        Apply(n, 0.0, j, d, g, psi, y);
        double erot = Dot(psi, y).re;
        var o = new double[4 + 3 * n];
        o[0] = eb; o[1] = erot; o[2] = Norm(psi);
        double ergo = 0;
        for (int i = 0; i < n; i++)
        {
            double rx = 0, ry = 0, rz = 0;
            int bit = 1 << i;
            for (int s = 0; s < dim; s++)
            {
                double p2 = psi[2 * s] * psi[2 * s] + psi[2 * s + 1] * psi[2 * s + 1];
                if ((s & bit) != 0) { rz += p2; continue; }
                rz -= p2;
                int u = s | bit;                   // ψ↑ = ψ[u], ψ↓ = ψ[s]: ⟨σˣ⟩ + i⟨σʸ⟩ = 2 conj(ψ↑) ψ↓
                double ar = psi[2 * u], ai = psi[2 * u + 1], br = psi[2 * s], bi = psi[2 * s + 1];
                rx += 2 * (ar * br + ai * bi);
                ry += 2 * (ar * bi - ai * br);
            }
            o[4 + 3 * i] = rx; o[5 + 3 * i] = ry; o[6 + 3 * i] = rz;
            ergo += 0.5 * w0 * (rz + Math.Sqrt(rx * rx + ry * ry + rz * rz));
        }
        o[3] = ergo;
        return o;
    }
}
