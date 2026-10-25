using Godot;
using Godot.Collections;

namespace MechaForge;

/// <summary>
/// Electronics — Servicio (autoload) que expone a GDScript el cálculo eléctrico
/// y los controladores PID escritos en C#.
///
/// GDScript no puede referenciar clases C# por nombre de forma fiable, así que
/// toda la interacción pasa por este autoload con tipos simples y diccionarios.
/// </summary>
public partial class Electronics : Node
{
    // --- Circuitos ---
    /// <summary>
    /// Resuelve un circuito. resistors = [[a,b,ohms],...], sources = [[a,b,volts],...].
    /// El nodo 0 es tierra. Devuelve el diccionario del solver
    /// (ok, node_voltages, source_currents, main_current, total_power).
    /// </summary>
    public Dictionary SolveCircuit(int nodeCount, Array resistors, Array sources)
    {
        using var solver = new ElectricalSolver();
        solver.EnsureNode(nodeCount - 1);
        foreach (Variant item in resistors)
        {
            Array a = item.AsGodotArray();
            solver.AddResistor(a[0].AsInt32(), a[1].AsInt32(), a[2].AsDouble());
        }
        foreach (Variant item in sources)
        {
            Array a = item.AsGodotArray();
            solver.AddVoltageSource(a[0].AsInt32(), a[1].AsInt32(), a[2].AsDouble());
        }
        return solver.Solve();
    }

    /// <summary>Autonomía en horas dada la corriente (A) y la capacidad (mAh).</summary>
    public double Autonomy(double amps, double mah) => ElectricalSolver.AutonomyHours(amps, mah);

    /// <summary>
    /// Circuito vivo (no lineal): ramas [[p, n, R, E]] con corriente p→n =
    /// (Vp − Vn − E)/R y diodos [[a, k, Is, n·Vt, Rs]]. Devuelve
    /// { ok, iters, v (tensiones de nodo), ib (corriente de cada rama),
    ///   id (corriente de cada diodo), vd (tensión ánodo-cátodo) }.
    /// </summary>
    public Dictionary SolveNetlist(int nodeCount, Array branches, Array diodes)
        => CircuitSolver.SolveArrays(nodeCount, branches, diodes);

    // --- Controladores PID (pool por id) ---
    private readonly System.Collections.Generic.Dictionary<int, PidController> _pids = new();
    private int _nextPid = 1;

    public int PidCreate()
    {
        int id = _nextPid++;
        _pids[id] = new PidController();
        return id;
    }

    public void PidConfigure(int id, double kp, double ki, double kd)
    {
        if (_pids.TryGetValue(id, out var p)) p.Configure(kp, ki, kd);
    }

    public void PidSetLimits(int id, double min, double max)
    {
        if (_pids.TryGetValue(id, out var p)) p.SetLimits(min, max);
    }

    public void PidSetSetpoint(int id, double setpoint)
    {
        if (_pids.TryGetValue(id, out var p)) p.Setpoint = setpoint;
    }

    public double PidUpdate(int id, double measurement, double dt)
        => _pids.TryGetValue(id, out var p) ? p.Update(measurement, dt) : 0.0;

    public double PidError(int id) => _pids.TryGetValue(id, out var p) ? p.LastError : 0.0;

    public void PidReset(int id)
    {
        if (_pids.TryGetValue(id, out var p)) p.Reset();
    }

    // Los PID y el solver son RefCounted de C#: si no se liberan aquí, los recoge el
    // recolector de .NET con el motor ya apagado y la aplicación falla al salir.
    public void PidDestroy(int id)
    {
        if (_pids.Remove(id, out var p)) p.Dispose();
    }

    public override void _Notification(int what)
    {
        if (what != NotificationPredelete) return;
        foreach (var p in _pids.Values) p.Dispose();
        _pids.Clear();
    }
}
