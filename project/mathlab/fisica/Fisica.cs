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
