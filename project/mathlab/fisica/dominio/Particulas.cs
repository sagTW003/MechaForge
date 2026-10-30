using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

namespace MechaForge;

/// <summary>Una partícula de la tabla (o su antipartícula, generada al cargar).</summary>
public sealed class Particula
{
    public string Id = "", Simbolo = "", Nombre = "", Tipo = "", Quarks = "", Color = "neutro", Nota = "";
    public double MasaMeV;
    public int Carga3, J2, B3, Le, Lmu, Ltau;
    public double VidaS = double.PositiveInfinity;   // ∞: estable o sin dato (quarks)
    public string AntiId = "";                        // = Id si es su propia antipartícula
    public List<(double Br, string[] Productos)> Desint = new();
}

/// <summary>
/// Particulas — Tabla del Modelo Estándar y de los hadrones más comunes (datos/particulas_pdg.json,
/// PDG 2026) y las leyes de conservación que debe cumplir cada desintegración o combinación:
/// carga, número bariónico, números leptónicos de cada familia, energía (masa en reposo) y la
/// paridad del número de fermiones (necesaria para conservar el momento angular).
/// Las cantidades se guardan como enteros (carga y B por 3, espín por 2) para comparar sin redondeo.
/// </summary>
public static class Particulas
{
    /// <summary>ħ en GeV·s (exacta, de h y e del SI): τ = ħ/Γ.</summary>
    public static readonly double HbarGeVs = Unidades.H_J_s / (2.0 * Math.PI) / Unidades.E_C / 1e9;

    static Dictionary<string, Particula> _tabla = new();
    public static string Fuente = "";
    public static bool Loaded => _tabla.Count > 0;
    public static IEnumerable<string> Ids => _tabla.Keys;

    public static Particula Get(string id) =>
        _tabla.TryGetValue(id, out var p) ? p : throw new ArgumentException($"partícula desconocida: {id}");
    public static bool Has(string id) => _tabla.ContainsKey(id);

    public static void Load(string json)
    {
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;
        Fuente = root.GetProperty("fuente").GetString() ?? "";
        var tabla = new Dictionary<string, Particula>();
        var antis = new List<(Particula baseP, JsonElement anti)>();
        foreach (var e in root.GetProperty("particulas").EnumerateArray())
        {
            var p = new Particula
            {
                Id = e.GetProperty("id").GetString()!,
                Simbolo = e.GetProperty("simbolo").GetString()!,
                Nombre = e.GetProperty("nombre").GetString()!,
                Tipo = e.GetProperty("tipo").GetString()!,
                MasaMeV = e.GetProperty("masa_MeV").GetDouble(),
                Carga3 = Int(e, "carga3"), J2 = Int(e, "J2"), B3 = Int(e, "B3"),
                Le = Int(e, "Le"), Lmu = Int(e, "Lmu"), Ltau = Int(e, "Ltau"),
                Quarks = Str(e, "quarks"), Color = Str(e, "color", "neutro"), Nota = Str(e, "nota"),
            };
            if (e.TryGetProperty("vida_s", out var v)) p.VidaS = v.GetDouble();
            else if (e.TryGetProperty("anchura_GeV", out var w)) p.VidaS = HbarGeVs / w.GetDouble();
            if (e.TryGetProperty("desint", out var ds))
                foreach (var d in ds.EnumerateArray())
                    p.Desint.Add((d.GetProperty("br").GetDouble(),
                        d.GetProperty("productos").EnumerateArray().Select(x => x.GetString()!).ToArray()));
            p.AntiId = p.Id;
            tabla[p.Id] = p;
            if (e.TryGetProperty("anti", out var a)) antis.Add((p, a));
        }
        foreach (var (b, a) in antis)
        {
            var q = new Particula
            {
                Id = a.GetProperty("id").GetString()!, Simbolo = a.GetProperty("simbolo").GetString()!,
                Nombre = a.GetProperty("nombre").GetString()!, Tipo = b.Tipo, MasaMeV = b.MasaMeV,
                Carga3 = -b.Carga3, J2 = b.J2, B3 = -b.B3, Le = -b.Le, Lmu = -b.Lmu, Ltau = -b.Ltau,
                VidaS = b.VidaS, Quarks = ConjugateQuarks(b.Quarks), Nota = b.Nota,
                Color = b.Color == "triplete" ? "antitriplete" : b.Color, AntiId = b.Id,
            };
            b.AntiId = q.Id;
            tabla[q.Id] = q;
        }
        // Canales de las antipartículas: los de la partícula con cada producto conjugado.
        foreach (var (b, _) in antis)
            tabla[b.AntiId].Desint = b.Desint.Select(d => (d.Br, d.Productos.Select(x => tabla[x].AntiId).ToArray())).ToList();
        _tabla = tabla;
    }

    static int Int(JsonElement e, string k) => e.TryGetProperty(k, out var v) ? v.GetInt32() : 0;
    static string Str(JsonElement e, string k, string def = "") => e.TryGetProperty(k, out var v) ? v.GetString() ?? def : def;

    /// <summary>"ud~" → "u~d": cada quark pasa a antiquark y al revés.</summary>
    public static string ConjugateQuarks(string q)
    {
        var o = new System.Text.StringBuilder();
        for (int i = 0; i < q.Length; i++)
        {
            bool anti = i + 1 < q.Length && q[i + 1] == '~';
            o.Append(q[i]);
            if (!anti) o.Append('~');
            if (anti) i++;
        }
        return o.ToString();
    }

    public static string Fraccion(int x3)
    {
        if (x3 % 3 == 0) return (x3 / 3).ToString("+0;−0;0");
        return (x3 > 0 ? "+" : "−") + Math.Abs(x3) + "/3";
    }

    /// <summary>
    /// Leyes que incumple el paso de «entrada» a «salida» (lista vacía: se cumplen todas). Con
    /// decay = true, además la energía: una partícula en reposo no puede dar productos más pesados.
    /// </summary>
    public static List<string> Violations(string[] entrada, string[] salida, bool decay)
    {
        var a = entrada.Select(Get).ToList();
        var b = salida.Select(Get).ToList();
        var v = new List<string>();
        void Ley(string nombre, Func<Particula, int> f, bool tercios)
        {
            int x = a.Sum(f), y = b.Sum(f);
            if (x != y)
                v.Add($"{nombre}: entra {(tercios ? Fraccion(x) : x.ToString("+0;−0;0"))}, sale {(tercios ? Fraccion(y) : y.ToString("+0;−0;0"))}");
        }
        Ley("carga eléctrica", p => p.Carga3, true);
        Ley("número bariónico", p => p.B3, true);
        Ley("número leptónico electrónico", p => p.Le, false);
        Ley("número leptónico muónico", p => p.Lmu, false);
        Ley("número leptónico tauónico", p => p.Ltau, false);
        int fa = a.Count(p => p.J2 % 2 == 1), fb = b.Count(p => p.J2 % 2 == 1);
        if (fa % 2 != fb % 2)
            v.Add($"momento angular: {fa} fermiones no pueden dar {fb} (el espín total pasaría de {(fa % 2 == 1 ? "semientero a entero" : "entero a semientero")})");
        if (decay)
        {
            double mi = a.Sum(p => p.MasaMeV), mo = b.Sum(p => p.MasaMeV);
            if (mo > mi)
                v.Add($"energía: la masa inicial ({mi:0.###} MeV) es menor que la suma de las finales ({mo:0.###} MeV)");
        }
        return v;
    }
}
