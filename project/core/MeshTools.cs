using Godot;

namespace MechaForge;

/// <summary>
/// MeshTools — Autoload con los cálculos de mallas en C# (MeshMass) para GDScript:
///   MeshTools.Compute(triangulos) → {volumen, area, centroide, inercia, cerrada, triangulos}
/// MeshMass es una clase normal de C#, que GDScript no ve; este autoload es el puente.
/// </summary>
public partial class MeshTools : Node
{
    public Godot.Collections.Dictionary Compute(Vector3[] tris) => MeshMass.ComputeTris(tris);
}
