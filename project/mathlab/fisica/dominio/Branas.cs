using System;
using System.Collections.Generic;
using System.Linq;

namespace MechaForge;

/// <summary>
/// Branas — Las cinco supercuerdas en D = 10 y sus D-branas, a primer orden en g_s:
///   tensión de una Dp: T_p = 1/(g_s (2π)^p α′^{(p+1)/2}); de la cuerda fundamental T_F1 = 1/(2πα′);
///   cuerda abierta estirada una distancia d entre dos branas: M² = (d/2πα′)² + N/α′ (tras la GSO);
///   N branas juntas: U(N) (tipo II); en la tipo I, O(k) en D1 y Sp(k) en D5 (proyección Ω);
///   16πG₁₀ = (2π)⁷ g_s² α′⁴; IIA a acoplamiento fuerte: 11.ª dimensión de radio R₁₁ = g_s √α′;
///   radio de AdS₅ cerca de N D3: L⁴ = 4π g_s N α′².
/// Heterótica: el grupo gauge sale de una red par autodual de dimensión 16 (E8 ⊕ E8 o D16⁺):
///   bosones gauge = raíces (vectores de norma 2) + 16.
/// Referencias: Polchinski II, cap. 12–14; Johnson, D-Branes (2003); Witten, Nucl. Phys. B 460,
/// 541 (1996) y 443, 85 (1995); Polchinski y Witten, Nucl. Phys. B 460, 525 (1996);
/// Maldacena, Adv. Theor. Math. Phys. 2, 231 (1998).
/// </summary>
public static class Branas
{
    public sealed record Tipo(string Id, string Nombre, int Supercargas, bool Orientada, bool Abiertas,
        bool Quiral, int[] Dp, string Gauge, string SinMasa);

    public static readonly Tipo[] Tipos =
    {
        new("I", "Tipo I", 16, false, true, true, new[] { 1, 5, 9 }, "SO(32)",
            "gravitón, dilatón y C₂ (Ramond-Ramond); 496 bosones gauge de SO(32) con sus gauginos; un gravitino"),
        new("IIA", "Tipo IIA", 32, true, false, false, new[] { 0, 2, 4, 6, 8 }, "ninguno perturbativo (U(1) de C₁)",
            "gravitón, B, dilatón; C₁ y C₃ (Ramond-Ramond); dos gravitinos de quiralidad opuesta"),
        new("IIB", "Tipo IIB", 32, true, false, true, new[] { -1, 1, 3, 5, 7, 9 }, "ninguno perturbativo",
            "gravitón, B, dilatón; C₀, C₂ y C₄ autodual (Ramond-Ramond); dos gravitinos de la misma quiralidad"),
        new("HO", "Heterótica SO(32)", 16, true, false, true, Array.Empty<int>(), "SO(32)",
            "gravitón, B, dilatón; 496 bosones gauge de SO(32) con sus gauginos; un gravitino"),
        new("HE", "Heterótica E8 × E8", 16, true, false, true, Array.Empty<int>(), "E8 × E8",
            "gravitón, B, dilatón; 496 bosones gauge de E8 × E8 con sus gauginos; un gravitino"),
    };

    public static Tipo? Find(string id) => Tipos.FirstOrDefault(t => t.Id == id);

    public static double Tension(int p, double gs, double alpha) =>
        1.0 / (gs * Math.Pow(2.0 * Math.PI, p) * Math.Pow(alpha, 0.5 * (p + 1)));

    public static double F1Tension(double alpha) => 1.0 / (2.0 * Math.PI * alpha);

    public static double StretchedMass2(double d, double alpha, int nivel) =>
        Math.Pow(d / (2.0 * Math.PI * alpha), 2) + nivel / alpha;

    public static double Newton10(double gs, double alpha) => 8.0 * Math.Pow(Math.PI, 6) * gs * gs * Math.Pow(alpha, 4);

    public static double R11(double gs, double alpha) => gs * Math.Sqrt(alpha);

    public static double AdsRadius(double gs, int n, double alpha) => Math.Pow(4.0 * Math.PI * gs * n * alpha * alpha, 0.25);

    /// <summary>
    /// Grupo gauge de branas Dp en las posiciones dadas (juntas si distan menos de tol) y número de
    /// bosones gauge sin masa: U(k) con k² en la tipo II; en la tipo I O(k) (D1, k(k−1)/2) y Sp(k) (D5, k(2k+1)).
    /// </summary>
    public static (string grupo, int vectores) GaugeGroup(string tipo, int p, double[] pos, double tol)
    {
        var x = pos.OrderBy(v => v).ToArray();
        var pilas = new List<int>();
        for (int i = 0; i < x.Length; i++)
            if (i > 0 && x[i] - x[i - 1] < tol) pilas[^1]++;
            else pilas.Add(1);
        var partes = new List<string>();
        int vec = 0;
        foreach (var g in pilas.GroupBy(k => k).OrderByDescending(g => g.Key))
        {
            int k = g.Key, veces = g.Count();
            string nombre;
            if (tipo != "I") { nombre = $"U({k})"; vec += veces * k * k; }
            else if (p == 5) { nombre = $"Sp({k})"; vec += veces * k * (2 * k + 1); }
            else { nombre = $"O({k})"; vec += veces * k * (k - 1) / 2; }
            partes.Add(veces > 1 ? $"{nombre}{Sup(veces)}" : nombre);
        }
        return (string.Join(" × ", partes), vec);
    }

    static string Sup(int k) => string.Concat(k.ToString().Select(c => "⁰¹²³⁴⁵⁶⁷⁸⁹"[c - '0']));

    /// <summary>
    /// Raíces (vectores de norma 2) de la red par autodual Γ = Dₙ ∪ (Dₙ + (½,…,½)) de dimensión n
    /// (múltiplo de 8): E8 para n = 8, D16⁺ = Spin(32)/Z₂ para n = 16. Se cuentan en coordenadas
    /// dobladas u = 2v: enteras (u par) o semienteras (u impar), |u|² = 8 y Σu ≡ 0 (mód 4).
    /// </summary>
    public static long LatticeRoots(int n)
    {
        long cuenta = 0;
        void Dfs(int i, int resto, int suma, int par)
        {
            if (par == 1 && resto < n - i) return;           // cada coordenada impar cuesta al menos 1
            if (i == n)
            {
                if (resto == 0 && ((suma % 4) + 4) % 4 == 0) cuenta++;
                return;
            }
            for (int u = -3; u <= 3; u++)
                if ((Math.Abs(u) % 2) == par && u * u <= resto)
                    Dfs(i + 1, resto - u * u, suma + u, par);
        }
        Dfs(0, 8, 0, 0);
        Dfs(0, 8, 0, 1);
        return cuenta;
    }
}
