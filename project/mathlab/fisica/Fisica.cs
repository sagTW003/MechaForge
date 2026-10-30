using System;
using Godot;
using Godot.Collections;

namespace MechaForge;

/// <summary>
/// Fisica — Autoload que expone a GDScript la física del pilar «Física moderna»
/// (mathlab/fisica/dominio/: C# puro, sin escena, en doble precisión).
/// Funciones sin estado con tipos simples, como Electronics y MeshTools: no se crea
/// ningún objeto de C# que haya que liberar a mano.
/// Convención de ejes del laboratorio: (x, y, z) matemático → (x·s, z·s, −y·s) en el mundo.
/// </summary>
public partial class Fisica : Node
{
    /// <summary>Constantes de Unidades (CODATA 2022) para la UI y las pruebas.</summary>
    public Dictionary Constantes() => new Dictionary
    {
        { "c_m_s", Unidades.C_m_s },
        { "hbarc_MeV_fm", Unidades.HbarC_MeV_fm },
        { "alpha", Unidades.Alpha },
        { "mec2_MeV", Unidades.MeC2_MeV },
        { "hartree_eV", Unidades.Hartree_eV },
        { "bohr_m", Unidades.Bohr_m },
        { "mp_me", Unidades.MpMe },
        { "tiempo_atomico_s", Unidades.AtomicTime_s },
    };

    // --- Hidrógeno ---
    public double HydrogenEnergyEv(int n, bool reducedMass) => Hidrogeno.EnergyEv(n, reducedMass);
    public double HydrogenMeanR(int n, int l) => Hidrogeno.MeanR(n, l);
    public double HydrogenMeanR2(int n, int l) => Hidrogeno.MeanR2(n, l);
    public double HydrogenRadius(int n, int l, double q) => Hidrogeno.RadiusQuantile(n, l, q);
    public double HydrogenRadialMoment(int n, int l, int k) => Hidrogeno.RadialMoment(n, l, k);
    public double HydrogenYlmNorm(int l, int m) => Hidrogeno.YlmNorm(l, m);
    public float[] HydrogenSample(int n, int l, int m, int count, int seed) => Hidrogeno.Sample(n, l, m, count, seed);

    /// <summary>[Re ψ, Im ψ] en (x, y, z), en a₀^{−3/2}.</summary>
    public double[] HydrogenPsi(int n, int l, int m, double x, double y, double z)
    {
        var psi = Hidrogeno.Psi(n, l, m, x, y, z);
        return new[] { psi.Real, psi.Imaginary };
    }

    // --- Cargas de Coulomb ---
    /// <summary>Referencia en CPU del kernel coulomb.glsl: p = [x, y, z, q] por carga.</summary>
    public float[] CoulombForces(float[] p, double eps2) => Coulomb.Forces(p, eps2);
    public float[] CoulombKick(float[] v, float[] f, double h) => Coulomb.Kick(v, f, h);
    public float[] CoulombDrift(float[] p, float[] v, double h, double box) => Coulomb.Drift(p, v, h, box);
    public double[] CoulombEnergy(float[] p, float[] v, double eps2) => Coulomb.Energy(p, v, eps2);
    public double[] CoulombEnergyFromForces(float[] v, float[] f) => Coulomb.EnergyFromForces(v, f);
    public bool AllFinite(float[] a) => Coulomb.AllFinite(a);
    public float[] CoulombRotate(float[] p, float[] v, double bz, double h) => Coulomb.Rotate(p, v, bz, h);
    public float[] FieldLines(float[] p, double eps2, int k, int maxSteps, double ds, double lim) =>
        Coulomb.FieldLines(p, eps2, k, maxSteps, ds, lim);

    // --- Modelo Estándar: tabla, conservación y desintegraciones ---
    const string TablaPdg = "res://mathlab/fisica/datos/particulas_pdg.json";

    void EnsureParticles()
    {
        if (!Particulas.Loaded)
            Particulas.Load(Godot.FileAccess.GetFileAsString(TablaPdg));
    }

    public string ParticlesSource() { EnsureParticles(); return Particulas.Fuente; }

    /// <summary>Ids de la tabla (con las antipartículas), en el orden del archivo.</summary>
    public string[] ParticleIds() { EnsureParticles(); return System.Linq.Enumerable.ToArray(Particulas.Ids); }

    /// <summary>Ficha de una partícula para el inspector (y las pruebas).</summary>
    public Dictionary ParticleInfo(string id)
    {
        EnsureParticles();
        var p = Particulas.Get(id);
        var canales = new Godot.Collections.Array();
        double tot = 0;
        foreach (var d in p.Desint) tot += d.Br;
        for (int i = 0; i < p.Desint.Count; i++)
            canales.Add(new Dictionary { { "br", p.Desint[i].Br }, { "br_norm", p.Desint[i].Br / tot },
                { "texto", Desintegraciones.ChannelText(p, i) }, { "productos", p.Desint[i].Productos } });
        return new Dictionary
        {
            { "id", p.Id }, { "simbolo", p.Simbolo }, { "nombre", p.Nombre }, { "tipo", p.Tipo },
            { "masa_MeV", p.MasaMeV }, { "carga3", p.Carga3 }, { "carga", Particulas.Fraccion(p.Carga3) },
            { "J2", p.J2 }, { "espin", p.J2 % 2 == 0 ? (p.J2 / 2).ToString() : p.J2 + "/2" },
            { "B3", p.B3 }, { "B", Particulas.Fraccion(p.B3) }, { "Le", p.Le }, { "Lmu", p.Lmu }, { "Ltau", p.Ltau },
            { "vida_s", double.IsInfinity(p.VidaS) ? -1.0 : p.VidaS }, { "quarks", p.Quarks }, { "color", p.Color },
            { "nota", p.Nota }, { "anti", p.AntiId }, { "canales", canales },
        };
    }

    /// <summary>Leyes que incumple «entrada → salida» (vacío: ninguna).</summary>
    public string[] Conservation(string[] entrada, string[] salida, bool decay)
    {
        EnsureParticles();
        return Particulas.Violations(entrada, salida, decay).ToArray();
    }

    public double TwoBodyP(double M, double m1, double m2) => Desintegraciones.TwoBodyP(M, m1, m2);

    /// <summary>
    /// Suceso en la cámara de burbujas: por traza, su partícula, la traza padre, los puntos (m),
    /// los cuadrimomentos al nacer y al final, si se desintegra (canal y leyes incumplidas).
    /// </summary>
    public Godot.Collections.Array DecayEvent(string id, double p, double bz, double radio, int profundidad, int seed)
    {
        EnsureParticles();
        var o = new Godot.Collections.Array();
        foreach (var t in Desintegraciones.Event(id, p, bz, radio, profundidad, seed))
        {
            var pts = new Vector3[t.Puntos.Count];
            for (int i = 0; i < pts.Length; i++) pts[i] = new Vector3((float)t.Puntos[i][0], (float)t.Puntos[i][1], (float)t.Puntos[i][2]);
            var part = Particulas.Get(t.Id);
            o.Add(new Dictionary
            {
                { "id", t.Id }, { "simbolo", part.Simbolo }, { "padre", t.Padre }, { "puntos", pts },
                { "carga3", part.Carga3 }, { "neutrino", part.Tipo == "lepton" && part.Carga3 == 0 },
                { "p0", new[] { t.P0.E, t.P0.X, t.P0.Y, t.P0.Z } }, { "p1", new[] { t.P1.E, t.P1.X, t.P1.Y, t.P1.Z } },
                { "decae", t.Decae }, { "longitud_m", t.LongitudM },
                { "canal", t.Canal >= 0 ? Desintegraciones.ChannelText(part, t.Canal) : "" },
                { "violaciones", t.Violaciones.ToArray() },
            });
        }
        return o;
    }

    /// <summary>Para las pruebas: cuántas veces sale cada canal en n desintegraciones.</summary>
    public int[] SampleChannels(string id, int n, int seed)
    {
        EnsureParticles();
        var p = Particulas.Get(id);
        var rng = new Random(seed);
        var c = new int[p.Desint.Count];
        for (int i = 0; i < n; i++) c[Desintegraciones.ChooseChannel(p, rng)]++;
        return c;
    }

    /// <summary>Para las pruebas: longitud de vuelo media (m) de n partículas con momento p (GeV/c), sin campo.</summary>
    public double MeanDecayLength(string id, double p, int n, int seed)
    {
        EnsureParticles();
        // Semillas de un solo generador: con semillas consecutivas, el primer número de cada
        // Random de .NET sale casi equiespaciado y la muestra no sería aleatoria.
        var semillas = new Random(seed);
        double s = 0;
        for (int i = 0; i < n; i++)
            s += Desintegraciones.Event(id, p, 0.0, 1e9, 1, semillas.Next())[0].LongitudM;
        return s / n;
    }

    // --- Buffers de MultiMesh (12 valores de la transformación + 4 de color o de datos) ---

    /// <summary>Nube orbital: posición escalada y la fase de ψ en los datos de la instancia.</summary>
    public float[] OrbitalInstances(float[] pts, double scale)
    {
        int n = pts.Length / 4;
        var b = new float[n * 16];
        for (int i = 0; i < n; i++)
        {
            int o = 16 * i;
            b[o] = 1; b[o + 3] = (float)(pts[4 * i] * scale);
            b[o + 5] = 1; b[o + 7] = (float)(pts[4 * i + 2] * scale);
            b[o + 10] = 1; b[o + 11] = (float)(-pts[4 * i + 1] * scale);
            b[o + 12] = pts[4 * i + 3];
        }
        return b;
    }

    /// <summary>Cargas: esferas con radio según la masa y color según el signo de la carga.</summary>
    public float[] ParticleInstances(float[] p, float[] v, double scale)
    {
        int n = p.Length / 4;
        var b = new float[n * 16];
        for (int i = 0; i < n; i++)
        {
            int o = 16 * i;
            float r = (float)(0.02 * Math.Pow(1.0 / v[4 * i + 3], 1.0 / 9.0));    // electrón 0,02; protón ≈ 0,046
            b[o] = r; b[o + 3] = (float)(p[4 * i] * scale);
            b[o + 5] = r; b[o + 7] = (float)(p[4 * i + 2] * scale);
            b[o + 10] = r; b[o + 11] = (float)(-p[4 * i + 1] * scale);
            bool pos = p[4 * i + 3] > 0;
            b[o + 12] = pos ? 1.0f : 0.35f; b[o + 13] = pos ? 0.4f : 0.65f; b[o + 14] = pos ? 0.3f : 1.0f; b[o + 15] = 1.0f;
        }
        return b;
    }

    /// <summary>Índice de la carga más cercana al rayo (en el mundo) a menos de «radius», o −1.</summary>
    public int NearestToRay(float[] p, double scale, Vector3 origin, Vector3 dir, double radius)
    {
        int best = -1;
        double bestT = double.MaxValue;
        var d = dir.Normalized();
        for (int i = 0; i < p.Length / 4; i++)
        {
            var w = new Vector3((float)(p[4 * i] * scale), (float)(p[4 * i + 2] * scale), (float)(-p[4 * i + 1] * scale));
            double t = (w - origin).Dot(d);
            if (t < 0 || t >= bestT) continue;
            if ((origin + d * (float)t - w).Length() < radius) { best = i; bestT = t; }
        }
        return best;
    }
}
