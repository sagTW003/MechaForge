using System;

namespace MechaForge;

/// <summary>
/// Unidades — Constantes físicas y conversiones del pilar «Física moderna».
///
///   · Cuántica atómica en unidades atómicas: ħ = mₑ = e = 4πε₀ = 1 (energía en
///     hartree Eₕ, longitud en radios de Bohr a₀).
///   · Partículas en MeV y fm; ħc pasa de una a otra.
///
/// Fuente: CODATA 2022 (NIST, physics.nist.gov/cuu/Constants). h, c y e son exactas
/// desde el SI de 2019 y ħc se deriva de ellas; α, mₑc², Eₕ y a₀ son valores
/// recomendados (su incertidumbre relativa es ≤ 2·10⁻¹⁰ y no se usa en las cuentas).
/// </summary>
public static class Unidades
{
    public const double C_m_s = 299792458.0;            // exacta
    public const double H_J_s = 6.62607015e-34;          // exacta
    public const double E_C = 1.602176634e-19;           // exacta
    /// <summary>ħc = h·c/2π en MeV·fm (exacta, 197.3269804… MeV·fm).</summary>
    public static readonly double HbarC_MeV_fm = H_J_s * C_m_s / (2.0 * Math.PI) / (E_C * 1e6) * 1e15;
    public const double Alpha = 7.2973525643e-3;         // constante de estructura fina
    public const double MeC2_MeV = 0.51099895069;         // energía en reposo del electrón
    public const double Hartree_eV = 27.211386245981;     // Eₕ = α²·mₑc²
    public const double Bohr_m = 5.29177210544e-11;       // a₀ = ħc / (α·mₑc²)
    public const double MpMe = 1836.152673426;            // mₚ/mₑ
    public const double AtomicTime_s = 2.4188843265864e-17; // ħ/Eₕ

    public static double HartreeToEv(double eh) => eh * Hartree_eV;
    public static double EvToHartree(double ev) => ev / Hartree_eV;
    public static double BohrToFm(double a0) => a0 * Bohr_m * 1e15;
}
