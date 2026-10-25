using Godot;

namespace MechaForge;

/// <summary>
/// MeshTools — Autoload con los cálculos de mallas en C# (MeshMass) para GDScript:
///   MeshTools.Compute(triangulos) → {volumen, area, centroide, inercia, cerrada, triangulos}
/// Antes cada cálculo creaba un objeto MeshMass (RefCounted de C#) desde GDScript; los
/// que quedaban sin recoger al cerrar los liberaba .NET con el motor ya apagado y la
/// aplicación fallaba al salir. Un autoload no crea ningún objeto por cálculo.
/// </summary>
public partial class MeshTools : Node
{
    public Godot.Collections.Dictionary Compute(Vector3[] tris) => MeshMass.ComputeTris(tris);
}
