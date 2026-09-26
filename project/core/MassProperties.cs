using Godot;

namespace MechaForge;

/// <summary>
/// MassProperties — Cálculo de propiedades de masa e inercia (módulo C#).
///
/// Primer módulo en C# de MechaForge. En la Fase 1 se usa para verificar que la
/// cadena de herramientas .NET compila y carga. En fases posteriores concentrará
/// el cálculo intensivo (tensores de inercia, centros de masa de ensamblajes).
/// Todas las magnitudes en unidades SI (m, kg).
/// </summary>
public static class MassProperties
{
    /// <summary>Masa de un prisma rectangular: densidad (kg/m³) × volumen (m³).</summary>
    public static double BoxMass(Vector3 sizeMeters, double densityKgM3)
    {
        double v = sizeMeters.X * sizeMeters.Y * sizeMeters.Z;
        return densityKgM3 * v;
    }

    /// <summary>
    /// Tensor de inercia (diagonal, kg·m²) de un prisma rectangular macizo
    /// respecto a su centro de masa, con ejes alineados a X/Y/Z.
    /// </summary>
    public static Vector3 BoxInertiaDiagonal(Vector3 sizeMeters, double mass)
    {
        double w = sizeMeters.X, h = sizeMeters.Y, d = sizeMeters.Z;
        double k = mass / 12.0;
        return new Vector3(
            (float)(k * (h * h + d * d)),
            (float)(k * (w * w + d * d)),
            (float)(k * (w * w + h * h))
        );
    }

    /// <summary>Masa de un cilindro macizo.</summary>
    public static double CylinderMass(double radiusMeters, double heightMeters, double densityKgM3)
    {
        double v = Mathf.Pi * radiusMeters * radiusMeters * heightMeters;
        return densityKgM3 * v;
    }

    /// <summary>Versión de <see cref="BoxMass"/> para tests / firma constante.</summary>
    public static string EngineInfo() => "MechaForge C# runtime OK (.NET 8, Godot 4.7)";
}
