using System;
using System.Collections.Generic;
using System.Linq;

namespace MechaForge;

/// <summary>
/// Materia — Construcción de materia a partir de sus piezas:
///   · hadrones con quarks (sin color: qqq, q̄q̄q̄ o qq̄), identificados en la tabla del PDG;
///   · cuarkonio con el potencial de Cornell V = −(4/3)αₛ/r + σr (ecuación radial por
///     diferencias finitas y autovalores por secuencias de Sturm);
///   · núcleos: fórmula semiempírica de masas (coeficientes de Rohlf, Modern Physics from α to
///     Z⁰, 1994) y, para 30 núclidos, vida media y modos reales (NUBASE2020: Kondev et al.,
///     Chin. Phys. C 45, 030001 (2021));
///   · átomos: configuración electrónica por la regla de Madelung con sus 20 excepciones (Z ≤ 103);
///   · moléculas: saturación de valencias (enlaces de orden 1 a 3, molécula conexa).
/// </summary>
public static class Materia
{
    public static readonly string[] Simbolos = {
        "n", "H", "He", "Li", "Be", "B", "C", "N", "O", "F", "Ne", "Na", "Mg", "Al", "Si", "P", "S", "Cl", "Ar", "K", "Ca",
        "Sc", "Ti", "V", "Cr", "Mn", "Fe", "Co", "Ni", "Cu", "Zn", "Ga", "Ge", "As", "Se", "Br", "Kr", "Rb", "Sr", "Y", "Zr",
        "Nb", "Mo", "Tc", "Ru", "Rh", "Pd", "Ag", "Cd", "In", "Sn", "Sb", "Te", "I", "Xe", "Cs", "Ba", "La", "Ce", "Pr", "Nd",
        "Pm", "Sm", "Eu", "Gd", "Tb", "Dy", "Ho", "Er", "Tm", "Yb", "Lu", "Hf", "Ta", "W", "Re", "Os", "Ir", "Pt", "Au", "Hg",
        "Tl", "Pb", "Bi", "Po", "At", "Rn", "Fr", "Ra", "Ac", "Th", "Pa", "U", "Np", "Pu", "Am", "Cm", "Bk", "Cf", "Es", "Fm",
        "Md", "No", "Lr", "Rf", "Db", "Sg", "Bh", "Hs", "Mt", "Ds", "Rg", "Cn", "Nh", "Fl", "Mc", "Lv", "Ts", "Og" };

    public static readonly string[] Nombres = {
        "neutrón", "hidrógeno", "helio", "litio", "berilio", "boro", "carbono", "nitrógeno", "oxígeno", "flúor", "neón",
        "sodio", "magnesio", "aluminio", "silicio", "fósforo", "azufre", "cloro", "argón", "potasio", "calcio", "escandio",
        "titanio", "vanadio", "cromo", "manganeso", "hierro", "cobalto", "níquel", "cobre", "cinc", "galio", "germanio",
        "arsénico", "selenio", "bromo", "kriptón", "rubidio", "estroncio", "itrio", "circonio", "niobio", "molibdeno",
        "tecnecio", "rutenio", "rodio", "paladio", "plata", "cadmio", "indio", "estaño", "antimonio", "telurio", "yodo",
        "xenón", "cesio", "bario", "lantano", "cerio", "praseodimio", "neodimio", "prometio", "samario", "europio",
        "gadolinio", "terbio", "disprosio", "holmio", "erbio", "tulio", "iterbio", "lutecio", "hafnio", "tantalio",
        "wolframio", "renio", "osmio", "iridio", "platino", "oro", "mercurio", "talio", "plomo", "bismuto", "polonio",
        "astato", "radón", "francio", "radio", "actinio", "torio", "protactinio", "uranio", "neptunio", "plutonio",
        "americio", "curio", "berkelio", "californio", "einstenio", "fermio", "mendelevio", "nobelio", "laurencio",
        "rutherfordio", "dubnio", "seaborgio", "bohrio", "hasio", "meitnerio", "darmstatio", "roentgenio", "copernicio",
        "nihonio", "flerovio", "moscovio", "livermorio", "teneso", "oganesón" };

    // --- Núcleos ---------------------------------------------------------------------------
    const double AV = 15.75, AS = 17.8, AC = 0.711, AA = 23.7, AP = 11.18;   // MeV (Rohlf)
    static double Mp => Particulas.Get("p").MasaMeV;
    static double Mn => Particulas.Get("n").MasaMeV;
    static double Me => Particulas.Get("e-").MasaMeV;

    /// <summary>B(Z, N) = a_V A − a_S A^{2/3} − a_C Z(Z−1)/A^{1/3} − a_A (N−Z)²/A ± a_P/√A (MeV).</summary>
    public static double Binding(int z, int n)
    {
        int a = z + n;
        if (a <= 0) return 0.0;
        double b = AV * a - AS * Math.Pow(a, 2.0 / 3.0) - AC * z * (z - 1) / Math.Pow(a, 1.0 / 3.0) - AA * (n - z) * (double)(n - z) / a;
        if (a % 2 == 0) b += (z % 2 == 0 ? 1 : -1) * AP / Math.Sqrt(a);
        return b;
    }

    /// <summary>Masa atómica (núcleo + Z electrones, sin la energía de enlace de los electrones), MeV.</summary>
    public static double AtomicMass(int z, int n) => z * (Mp + Me) + n * Mn - Binding(z, n);

    public sealed class Modo { public string Tipo = ""; public double Fraccion = 1.0; public int Z, N; public string Nota = ""; }
    sealed class Nuclido { public double Medio = double.PositiveInfinity; public string Texto = "estable"; public List<Modo> Modos = new(); }

    const double Anio = 365.2422 * 86400.0;          // año de NUBASE (días tropicales)
    static readonly Dictionary<(int, int), Nuclido> Datos = BuildDatos();

    static Dictionary<(int, int), Nuclido> BuildDatos()
    {
        var d = new Dictionary<(int, int), Nuclido>();
        foreach (var (z, n) in new[] { (1, 0), (1, 1), (2, 1), (2, 2), (3, 3), (3, 4), (4, 5), (5, 5), (5, 6), (6, 6), (6, 7), (7, 7),
            (7, 8), (8, 8), (8, 9), (8, 10), (9, 10), (10, 10), (11, 12), (12, 12), (13, 14), (14, 14), (15, 16), (16, 16), (17, 18),
            (18, 22), (20, 20), (26, 30), (28, 32), (56, 81), (79, 118), (82, 124), (82, 126) })
            d[(z, n)] = new Nuclido();
        void R(int z, int n, double medio, string texto, params Modo[] m) => d[(z, n)] = new Nuclido { Medio = medio, Texto = texto, Modos = m.ToList() };
        Modo M(string tipo, double f, int z, int n, string nota = "") => new() { Tipo = tipo, Fraccion = f, Z = z, N = n, Nota = nota };
        R(1, 2, 12.32 * Anio, "12,32 años", M("β⁻", 1, 2, 1));
        R(2, 4, 0.80692, "806,92 ms", M("β⁻", 1, 3, 3));
        R(4, 3, 53.22 * 86400, "53,22 días", M("CE", 1, 3, 4, "captura electrónica"));
        R(4, 4, 81.9e-18, "81,9 as", M("α", 1, 2, 2, "se parte en dos partículas α"));
        R(6, 5, 20.3402 * 60, "20,3402 min", M("β⁺", 1, 5, 6));
        R(6, 8, 5.70e3 * Anio, "5700 años", M("β⁻", 1, 7, 7));
        R(7, 6, 9.965 * 60, "9,965 min", M("β⁺", 1, 6, 7));
        R(8, 7, 122.266, "122,266 s", M("β⁺", 1, 7, 8));
        R(9, 9, 109.734 * 60, "109,734 min", M("β⁺", 1, 8, 10));
        R(19, 21, 1.248e9 * Anio, "1,248·10⁹ años", M("β⁻", 0.8928, 20, 20), M("CE", 0.1072, 18, 22, "captura electrónica (y β⁺, 0,001 %)"));
        R(27, 33, 5.2714 * Anio, "5,2714 años", M("β⁻", 1, 28, 32, "el ⁶⁰Ni emite γ de 1,17 y 1,33 MeV"));
        R(55, 82, 30.04 * Anio, "30,04 años", M("β⁻", 0.9470, 56, 81, "al ¹³⁷ᵐBa (2,552 min), que emite un γ de 661,659 keV"), M("β⁻", 0.0530, 56, 81, "al estado fundamental del ¹³⁷Ba"));
        R(84, 126, 138.376 * 86400, "138,376 días", M("α", 1, 82, 124));
        R(86, 136, 3.8215 * 86400, "3,8215 días", M("α", 1, 84, 134));
        R(88, 138, 1600 * Anio, "1600 años", M("α", 1, 86, 136));
        R(92, 143, 7.04e8 * Anio, "7,04·10⁸ años", M("α", 1, 90, 141));
        R(92, 146, 4.463e9 * Anio, "4,463·10⁹ años", M("α", 1, 90, 144));
        return d;
    }

    public static string NucleusName(int z, int n) => Sup(z + n) + (z < Simbolos.Length ? Simbolos[z] : "?");

    static string Sup(int x)
    {
        const string s = "⁰¹²³⁴⁵⁶⁷⁸⁹";
        return string.Concat(x.ToString().Select(c => s[c - '0']));
    }

    /// <summary>
    /// Datos del núcleo (Z, N): si está en NUBASE2020 (de la tabla), su vida media y modos; si
    /// no, la predicción de la fórmula semiempírica con los valores Q (poco fiable si A &lt; 20).
    /// </summary>
    public static (bool ligado, bool estable, bool dato, string medio, double medioS, List<Modo> modos, double b, string nota) Nucleus(int z, int n)
    {
        double b = Binding(z, n);
        if (Datos.TryGetValue((z, n), out var nu))
            return (true, nu.Modos.Count == 0, true, nu.Texto, nu.Medio, nu.Modos, b, "dato de NUBASE2020");
        var modos = new List<Modo>();
        string nota = z + n < 20 ? "predicción de la fórmula semiempírica (poco fiable con A < 20)" : "predicción de la fórmula semiempírica";
        if (z == 0) return (false, false, false, "", 0, modos, b, "sin protones no hay núcleo ligado (salvo el neutrón libre)");
        if (b <= 0) return (false, false, false, "", 0, modos, b, "no está ligado: B ≤ 0 según la fórmula semiempírica");
        double m = AtomicMass(z, n);
        // Emisión de nucleones: energía de separación negativa.
        if (n > 0 && b - Binding(z, n - 1) < 0) modos.Add(new Modo { Tipo = "n", Z = z, N = n - 1, Nota = "emite un neutrón (S_n < 0)" });
        if (z > 0 && b - Binding(z - 1, n) < 0) modos.Add(new Modo { Tipo = "p", Z = z - 1, N = n, Nota = "emite un protón (S_p < 0)" });
        if (modos.Count == 0)
        {
            if (n > 0 && m - AtomicMass(z + 1, n - 1) > 0) modos.Add(new Modo { Tipo = "β⁻", Z = z + 1, N = n - 1, Nota = $"Q = {m - AtomicMass(z + 1, n - 1):0.###} MeV" });
            if (z > 1 && m - AtomicMass(z - 1, n + 1) > 0) modos.Add(new Modo { Tipo = m - AtomicMass(z - 1, n + 1) > 2 * Me ? "β⁺" : "CE", Z = z - 1, N = n + 1, Nota = $"Q_CE = {m - AtomicMass(z - 1, n + 1):0.###} MeV" });
            double qa = z > 2 && n > 2 ? m - AtomicMass(z - 2, n - 2) - AtomicMass(2, 2) : -1;
            if (qa > 0 && z + n > 140) modos.Add(new Modo { Tipo = "α", Z = z - 2, N = n - 2, Nota = $"Q_α = {qa:0.###} MeV" });
        }
        if (modos.Count > 0) modos.ForEach(x => x.Fraccion = 1.0 / modos.Count);
        return (true, modos.Count == 0, false, modos.Count == 0 ? "estable" : "sin dato", double.NaN, modos, b, nota);
    }

    public static double RadiusFm(int a) => 1.2 * Math.Pow(a, 1.0 / 3.0);   // R = r₀A^{1/3}, r₀ ≈ 1,2 fm

    // --- Átomos -----------------------------------------------------------------------------
    static readonly (int n, int l)[] Orden = { (1, 0), (2, 0), (2, 1), (3, 0), (3, 1), (4, 0), (3, 2), (4, 1), (5, 0), (4, 2), (5, 1),
        (6, 0), (4, 3), (5, 2), (6, 1), (7, 0), (5, 3), (6, 2), (7, 1), (8, 0) };
    // Excepciones a la regla de Madelung (Z, desde, hacia, electrones movidos).
    static readonly (int z, (int, int) de, (int, int) a, int k)[] Excepciones = {
        (24, (4, 0), (3, 2), 1), (29, (4, 0), (3, 2), 1), (41, (5, 0), (4, 2), 1), (42, (5, 0), (4, 2), 1), (44, (5, 0), (4, 2), 1),
        (45, (5, 0), (4, 2), 1), (46, (5, 0), (4, 2), 2), (47, (5, 0), (4, 2), 1), (57, (4, 3), (5, 2), 1), (58, (4, 3), (5, 2), 1),
        (64, (4, 3), (5, 2), 1), (78, (6, 0), (5, 2), 1), (79, (6, 0), (5, 2), 1), (89, (5, 3), (6, 2), 1), (90, (5, 3), (6, 2), 2),
        (91, (5, 3), (6, 2), 1), (92, (5, 3), (6, 2), 1), (93, (5, 3), (6, 2), 1), (96, (5, 3), (6, 2), 1), (103, (6, 2), (7, 1), 1) };

    /// <summary>Ocupación de cada orbital (n, l) del átomo neutro de número atómico z.</summary>
    static SortedDictionary<(int, int), int> Neutral(int z)
    {
        var occ = new SortedDictionary<(int, int), int>();
        int left = z;
        foreach (var o in Orden)
        {
            if (left <= 0) break;
            int k = Math.Min(left, 2 * (2 * o.l + 1));
            occ[o] = k;
            left -= k;
        }
        foreach (var e in Excepciones.Where(x => x.z == z))
        {
            occ[e.de] -= e.k;
            if (occ[e.de] == 0) occ.Remove(e.de);
            occ[e.a] = occ.GetValueOrDefault(e.a) + e.k;
        }
        return occ;
    }

    /// <summary>
    /// Configuración con «electrones» electrones (neutro, catión o anión). Los cationes pierden
    /// primero los electrones de mayor n (y de mayor l si empatan): el Fe²⁺ es [Ar] 3d⁶.
    /// </summary>
    public static string Configuration(int z, int electrones)
    {
        var occ = Neutral(z);
        int quitar = z - electrones;
        while (quitar > 0 && occ.Count > 0)
        {
            var o = occ.Keys.OrderByDescending(k => k.Item1).ThenByDescending(k => k.Item2).First();
            occ[o]--;
            if (occ[o] == 0) occ.Remove(o);
            quitar--;
        }
        if (quitar < 0)
        {
            int extra = -quitar;
            foreach (var o in Orden)
            {
                if (extra == 0) break;
                int libre = 2 * (2 * o.l + 1) - occ.GetValueOrDefault(o);
                int k = Math.Min(libre, extra);
                if (k > 0) { occ[o] = occ.GetValueOrDefault(o) + k; extra -= k; }
            }
        }
        const string spdf = "spdfgh";
        return string.Join(" ", occ.OrderBy(k => k.Key.Item1).ThenBy(k => k.Key.Item2)
            .Select(k => $"{k.Key.Item1}{spdf[k.Key.Item2]}{Sup(k.Value)}"));
    }

    public static bool IsMadelungException(int z) => Excepciones.Any(x => x.z == z);

    // --- Hadrones ---------------------------------------------------------------------------
    /// <summary>
    /// Hadrón con estos quarks («u», «d~»…): comprueba que no tenga color y lo busca en la
    /// tabla (el de menor masa; el resto, como alternativas). Devuelve el id (o "") y el motivo.
    /// </summary>
    public static (string id, string tipo, string motivo, string[] alternativas) Hadron(string[] quarks)
    {
        int q = quarks.Count(x => !x.EndsWith("~")), aq = quarks.Length - q;
        bool barion = q == 3 && aq == 0, antibarion = q == 0 && aq == 3, meson = q == 1 && aq == 1;
        if (!barion && !antibarion && !meson)
        {
            if ((q - aq) % 3 == 0 && q + aq > 0)
                return ("", "exotico", $"{q} quarks y {aq} antiquarks pueden no tener color (tetraquark, pentaquark…), pero esos hadrones exóticos no se modelan", Array.Empty<string>());
            return ("", "", $"carga de color: {q} quarks y {aq} antiquarks no forman un estado sin color (hacen falta qqq, q̄q̄q̄ o qq̄)", Array.Empty<string>());
        }
        string Clave(IEnumerable<string> qs) => string.Join(",", qs.OrderBy(x => x));
        string clave = Clave(quarks);
        // Mesones neutros ligeros: uū y dd̄ se mezclan (π⁰, ρ⁰, ω); ss̄ va con el η de la tabla.
        if (meson && (clave == "d,d~" || clave == "u,u~")) clave = Clave(new[] { "u", "u~" });
        var cand = Particulas.Ids.Select(Particulas.Get)
            .Where(p => p.Quarks != "" && Clave(Tokens(p.Quarks)) == clave)
            .OrderBy(p => p.MasaMeV).ToList();
        string tipo = barion ? "barion" : antibarion ? "antibarion" : "meson";
        if (cand.Count == 0)
            return ("", tipo, "hadrón sin color, pero no está en la tabla del PDG de este laboratorio", Array.Empty<string>());
        return (cand[0].Id, tipo, "", cand.Skip(1).Select(p => p.Id).ToArray());
    }

    static IEnumerable<string> Tokens(string q)
    {
        for (int i = 0; i < q.Length; i++)
        {
            if (i + 1 < q.Length && q[i + 1] == '~') { yield return q[i] + "~"; i++; }
            else yield return q[i].ToString();
        }
    }

    /// <summary>
    /// Niveles del cuarkonio QQ̄ (energía sobre 2m_Q, GeV) con V = −(4/3)αₛ/r + σr: ecuación radial
    /// −u″/2μ + [V + l(l+1)/2μr²]u = Eu (μ = m_Q/2, r en GeV⁻¹) en una malla de k puntos hasta rMax.
    /// </summary>
    public static double[] Quarkonium(double mq, double alphaS, double sigma, int l, int niveles, double rMax = 25.0, int k = 6000)
    {
        double mu = mq / 2.0, h = rMax / (k + 1);
        var d = new double[k];
        double off = -1.0 / (2.0 * mu * h * h);
        for (int i = 0; i < k; i++)
        {
            double r = (i + 1) * h;
            d[i] = 1.0 / (mu * h * h) - 4.0 / 3.0 * alphaS / r + sigma * r + l * (l + 1) / (2.0 * mu * r * r);
        }
        int Count(double x)                // autovalores menores que x (secuencia de Sturm)
        {
            int c = 0;
            double q = d[0] - x;
            if (q < 0) c++;
            for (int i = 1; i < k; i++)
            {
                q = d[i] - x - off * off / (Math.Abs(q) < 1e-300 ? 1e-300 : q);
                if (q < 0) c++;
            }
            return c;
        }
        var e = new double[niveles];
        double lo0 = d.Min() + 2 * off, hi0 = d.Max() - 2 * off;
        for (int j = 0; j < niveles; j++)
        {
            double lo = lo0, hi = hi0;
            for (int it = 0; it < 100; it++)
            {
                double mid = 0.5 * (lo + hi);
                if (Count(mid) > j) hi = mid; else lo = mid;
            }
            e[j] = 0.5 * (lo + hi);
        }
        return e;
    }

    // --- Moléculas --------------------------------------------------------------------------
    static int Valence(int z) => z switch
    {
        1 => 1, 2 => 0, 3 => 1, 4 => 2, 5 => 3, 6 => 4, 7 => 3, 8 => 2, 9 => 1, 10 => 0,
        11 => 1, 12 => 2, 13 => 3, 14 => 4, 15 => 3, 16 => 2, 17 => 1, 18 => 0,
        19 => 1, 20 => 2, 35 => 1, 36 => 0, 53 => 1, 54 => 0, _ => -1,
    };

    /// <summary>
    /// Molécula con estos átomos: busca órdenes de enlace (1 a 3) que saturen la valencia habitual
    /// de cada átomo y dejen la molécula conexa. Devuelve los enlaces [i, j, orden] o el motivo.
    /// </summary>
    public static (bool ok, string motivo, List<int[]> enlaces) Molecule(int[] z)
    {
        int n = z.Length;
        var enlaces = new List<int[]>();
        if (n < 2) return (false, "una molécula necesita al menos dos átomos", enlaces);
        if (n > 10) return (false, "como mucho 10 átomos en este modelo", enlaces);
        var v = z.Select(Valence).ToArray();
        for (int i = 0; i < n; i++)
            if (v[i] < 0) return (false, $"el {Nombres[z[i]]} no tiene una valencia covalente sencilla en este modelo", enlaces);
        if (v.Sum() % 2 == 1) return (false, $"la suma de valencias ({v.Sum()}) es impar: quedaría un electrón desapareado (un radical)", enlaces);
        if (v.Any(x => x == 0)) return (false, $"el {Nombres[z[Array.IndexOf(v, 0)]]} es un gas noble: no forma enlaces", enlaces);
        var pares = new List<(int, int)>();
        for (int i = 0; i < n; i++) for (int j = i + 1; j < n; j++) pares.Add((i, j));
        var orden = new int[pares.Count];
        var resto = (int[])v.Clone();
        int nodos = 0;                      // la búsqueda es exponencial: se corta a los 200 000 nodos
        bool Conexa()
        {
            var vis = new bool[n];
            var pila = new Stack<int>();
            pila.Push(0); vis[0] = true;
            while (pila.Count > 0)
            {
                int a = pila.Pop();
                for (int p = 0; p < pares.Count; p++)
                {
                    if (orden[p] == 0) continue;
                    var (i, j) = pares[p];
                    int b = i == a ? j : j == a ? i : -1;
                    if (b >= 0 && !vis[b]) { vis[b] = true; pila.Push(b); }
                }
            }
            return vis.All(x => x);
        }
        bool Buscar(int p)
        {
            if (++nodos > 200000) return false;
            if (p == pares.Count) return resto.All(x => x == 0) && Conexa();
            var (i, j) = pares[p];
            for (int o = 0; o <= Math.Min(3, Math.Min(resto[i], resto[j])); o++)
            {
                // Lo que le quede a i ya solo se puede cerrar con los pares siguientes.
                orden[p] = o; resto[i] -= o; resto[j] -= o;
                bool ok = resto[i] <= RestoPosible(p, i) && Buscar(p + 1);
                resto[i] += o; resto[j] += o;
                if (ok) return true;
            }
            orden[p] = 0;
            return false;
        }
        int RestoPosible(int p, int i)
        {
            int s = 0;
            for (int q = p + 1; q < pares.Count; q++)
                if (pares[q].Item1 == i || pares[q].Item2 == i) s += 3;
            return s;
        }
        if (!Buscar(0))
            return (false, nodos > 200000 ? "demasiadas combinaciones de enlaces para buscarlas (prueba con menos átomos)"
                : "no hay forma de saturar todas las valencias con enlaces de orden 1 a 3 en una sola molécula", enlaces);
        for (int p = 0; p < pares.Count; p++)
            if (orden[p] > 0) enlaces.Add(new[] { pares[p].Item1, pares[p].Item2, orden[p] });
        return (true, "", enlaces);
    }

    /// <summary>Posiciones 3D (unidades de enlace) por muelles en los enlaces y repulsión entre átomos.</summary>
    public static double[] Layout(int n, List<int[]> enlaces, int seed)
    {
        var rng = new Random(seed);
        var x = new double[3 * n];
        for (int i = 0; i < 3 * n; i++) x[i] = rng.NextDouble() - 0.5;
        var f = new double[3 * n];
        for (int it = 0; it < 600; it++)
        {
            Array.Clear(f);
            for (int i = 0; i < n; i++)
                for (int j = i + 1; j < n; j++)
                {
                    double dx = x[3 * i] - x[3 * j], dy = x[3 * i + 1] - x[3 * j + 1], dz = x[3 * i + 2] - x[3 * j + 2];
                    double r2 = dx * dx + dy * dy + dz * dz + 1e-6, s = 0.6 / r2;
                    f[3 * i] += s * dx; f[3 * i + 1] += s * dy; f[3 * i + 2] += s * dz;
                    f[3 * j] -= s * dx; f[3 * j + 1] -= s * dy; f[3 * j + 2] -= s * dz;
                }
            foreach (var e in enlaces)
            {
                int i = e[0], j = e[1];
                double dx = x[3 * i] - x[3 * j], dy = x[3 * i + 1] - x[3 * j + 1], dz = x[3 * i + 2] - x[3 * j + 2];
                double r = Math.Sqrt(dx * dx + dy * dy + dz * dz) + 1e-9, l0 = 1.0 - 0.1 * (e[2] - 1);
                double s = -2.0 * (r - l0) / r;
                f[3 * i] += s * dx; f[3 * i + 1] += s * dy; f[3 * i + 2] += s * dz;
                f[3 * j] -= s * dx; f[3 * j + 1] -= s * dy; f[3 * j + 2] -= s * dz;
            }
            for (int i = 0; i < 3 * n; i++) x[i] += 0.05 * Math.Clamp(f[i], -2, 2);
        }
        return x;
    }
}
