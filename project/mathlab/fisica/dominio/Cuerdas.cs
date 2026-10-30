using System;
using System.Collections.Generic;

namespace MechaForge;

/// <summary>
/// Cuerdas — Cuerda relativista libre cuantizada en el gauge del cono de luz (α′ = ℓ_s²):
///   bosónica (D = 26): abierta α′M² = N − 1; cerrada α′M² = 4(N − 1) con N = Ñ;
///   supercuerda (D = 10): abierta NS α′M² = N − ½ (con la proyección GSO, α′M² entero ≥ 0),
///   R α′M² = N; cerrada tipo II, α′M² = 4·(nivel) con los dos lados iguales.
/// Degeneraciones: coeficientes de las funciones de partición de los D − 2 osciladores
/// transversales (y de los fermiones, en la supercuerda). La igualdad NS = R nivel a nivel es
/// la identidad «abstrusa» de Jacobi: la supersimetría del espectro.
/// Referencias: Polchinski, String Theory I, cap. 1–4 y II, cap. 10; Zwiebach, A First Course
/// in String Theory (2.ª ed.), cap. 12–14; Gliozzi, Scherk y Olive, Nucl. Phys. B 122, 253 (1977).
/// </summary>
public static class Cuerdas
{
    /// <summary>Coeficientes de Π_{n≥1} (1 − qⁿ)^{−d} hasta q^nMax: estados bosónicos de cada nivel N.</summary>
    public static long[] BosonicLevels(int d, int nMax)
    {
        var c = new long[nMax + 1];
        c[0] = 1;
        for (int n = 1; n <= nMax; n++)
            for (int k = 0; k < d; k++)
                for (int m = n; m <= nMax; m++)      // multiplicar por 1/(1 − qⁿ) = Σ q^{nj}
                    c[m] += c[m - n];
        return c;
    }

    /// <summary>
    /// Supercuerda abierta en D = 10: estados por nivel α′M² = 0, 1, 2… del sector NS tras la
    /// proyección GSO y del sector R (8 transversales bosónicos y 8 fermiónicos).
    /// Las series van en potencias de q^{1/2} (índice = 2·exponente).
    /// </summary>
    public static (long[] ns, long[] r) SuperLevels(int niveles)
    {
        int m = 2 * niveles + 2;
        long[] Mul(long[] a, long[] b)
        {
            var o = new long[m + 1];
            for (int i = 0; i <= m; i++) if (a[i] != 0) for (int j = 0; i + j <= m; j++) o[i + j] += a[i] * b[j];
            return o;
        }
        long[] Pow(long[] a, int e) { var o = new long[m + 1]; o[0] = 1; for (int i = 0; i < e; i++) o = Mul(o, a); return o; }
        long[] One() { var o = new long[m + 1]; o[0] = 1; return o; }
        // Productos sobre n de (1 ± q^{n−1/2}), (1 + qⁿ) y 1/(1 − qⁿ), en potencias de q^{1/2}.
        var plusHalf = One(); var minusHalf = One(); var plusInt = One(); var invInt = One();
        for (int n = 1; 2 * n - 1 <= m; n++)
        {
            var f = One(); f[2 * n - 1] = 1; plusHalf = Mul(plusHalf, f);
            var g = One(); g[2 * n - 1] = -1; minusHalf = Mul(minusHalf, g);
        }
        for (int n = 1; 2 * n <= m; n++)
        {
            var f = One(); f[2 * n] = 1; plusInt = Mul(plusInt, f);
            var inv = new long[m + 1];
            for (int j = 0; j * 2 * n <= m; j++) inv[j * 2 * n] = 1;
            invInt = Mul(invInt, inv);
        }
        var bos8 = Pow(invInt, 8);
        // NS con GSO: ½ q^{−1/2} [Π(1 + q^{n−1/2})⁸ − Π(1 − q^{n−1/2})⁸] / Π(1 − qⁿ)⁸.
        var dif = Pow(plusHalf, 8);
        var neg = Pow(minusHalf, 8);
        for (int i = 0; i <= m; i++) dif[i] -= neg[i];
        var nsSerie = Mul(dif, bos8);
        // R: 8·Π(1 + qⁿ)⁸ / Π(1 − qⁿ)⁸.
        var rSerie = Mul(Pow(plusInt, 8), bos8);
        var ns = new long[niveles + 1];
        var r = new long[niveles + 1];
        for (int l = 0; l <= niveles; l++)
        {
            ns[l] = nsSerie[2 * l + 1] / 2;       // q^{l + 1/2} · q^{−1/2} = q^l
            r[l] = 8 * rSerie[2 * l];
        }
        return (ns, r);
    }

    /// <summary>α′M² del nivel: teoría «bosonica» o «super», cuerda «abierta» o «cerrada».</summary>
    public static double AlphaM2(string teoria, string cuerda, double nivel)
    {
        bool cerrada = cuerda == "cerrada";
        if (teoria == "bosonica") return cerrada ? 4.0 * (nivel - 1.0) : nivel - 1.0;
        return cerrada ? 4.0 * nivel : nivel;        // supercuerda tras la GSO (nivel α′M² de cada lado)
    }

    /// <summary>
    /// Qué partícula es el nivel más bajo de cada caso (en D dimensiones; la reducción a 4 dimensiones
    /// es de la fase 6). Para niveles masivos, el espín máximo de la trayectoria de Regge principal.
    /// </summary>
    public static string Identify(string teoria, string cuerda, int nivel)
    {
        bool cerrada = cuerda == "cerrada";
        if (teoria == "bosonica")
        {
            if (nivel == 0) return "taquión (M² < 0): el vacío de la cuerda bosónica es inestable";
            if (nivel == 1) return cerrada
                ? "sin masa: gravitón (espín 2, 299 estados), campo B (276) y dilatón (1) en 26 dimensiones"
                : "sin masa: bosón gauge de espín 1 (24 polarizaciones), como el fotón";
            return cerrada ? $"masivo; espín máximo {2 * nivel} (trayectoria de Regge principal)" : $"masivo; espín máximo {nivel} (trayectoria de Regge principal)";
        }
        if (nivel == 0) return cerrada
            ? "sin masa: supergravedad tipo II (gravitón, B, dilatón, campos de Ramond-Ramond y dos gravitinos)"
            : "sin masa: bosón gauge (8 estados, NS) y su compañero supersimétrico, el gaugino (8, R)";
        return cerrada ? $"masivo; espín máximo {2 * nivel + 2}" : $"masivo; espín máximo {nivel + 1}";
    }

    /// <summary>
    /// Desplazamiento transversal clásico en (σ, τ): suma de modos normales con amplitud
    /// A_n = 2√(2α′N_n/n) (estado coherente con N_n cuantos en el modo n). Contorno «NN»
    /// (extremos libres, cos nσ), «DD» (extremos fijos, sin nσ) o «cerrada» (ondas viajeras:
    /// derecha cos n(τ − σ), izquierda cos n(τ + σ), con A_n = √(2α′N_n/n)).
    /// </summary>
    public static double Displacement(string contorno, double alpha, int[] ocupacion, double[] fase, double sigma, double tau, bool izquierda = false)
    {
        double x = 0.0;
        for (int i = 0; i < ocupacion.Length; i++)
        {
            int n = i + 1;
            if (ocupacion[i] == 0) continue;
            double ph = fase.Length > i ? fase[i] : 0.0;
            if (contorno == "cerrada")
            {
                double a = Math.Sqrt(2.0 * alpha * ocupacion[i] / n);
                x += a * Math.Cos(n * (izquierda ? tau + sigma : tau - sigma) - ph);
            }
            else
            {
                double a = 2.0 * Math.Sqrt(2.0 * alpha * ocupacion[i] / n);
                x += a * (contorno == "DD" ? Math.Sin(n * sigma) : Math.Cos(n * sigma)) * Math.Cos(n * tau - ph);
            }
        }
        return x;
    }
}
