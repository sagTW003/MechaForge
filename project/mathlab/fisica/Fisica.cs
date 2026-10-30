using Godot;
using Godot.Collections;

namespace MechaForge;

/// <summary>
/// Fisica — Autoload que expone a GDScript la física del pilar «Física moderna»
/// (mathlab/fisica/dominio/: C# puro, sin escena, en doble precisión).
/// Funciones sin estado con tipos simples, como Electronics y MeshTools: no se crea
/// ningún objeto de C# que haya que liberar a mano.
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
    };

    /// <summary>Referencia en CPU del kernel coulomb.glsl: p = [x, y, z, q] por carga.</summary>
    public float[] CoulombForces(float[] p, double eps2) => Coulomb.Forces(p, eps2);
}
