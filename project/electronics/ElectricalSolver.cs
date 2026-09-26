using System;
using System.Collections.Generic;
using Godot;
using Godot.Collections;

namespace MechaForge;

/// <summary>
/// ElectricalSolver — Solver de circuitos DC por Análisis Nodal Modificado (MNA).
///
/// Resuelve redes resistivas con fuentes de tensión (baterías) aplicando las
/// leyes de Ohm y Kirchhoff: tensiones de nodo, corrientes de rama, consumo y
/// —con la capacidad de la batería— la autonomía estimada.
/// Unidades SI: V, A, Ω, W. El nodo 0 es SIEMPRE la tierra (0 V).
///
/// Expuesto a GDScript como clase global (RefCounted).
/// </summary>
[GlobalClass]
public partial class ElectricalSolver : RefCounted
{
    private struct Resistor { public int A, B; public double R; }
    private struct VSource { public int A, B; public double V; }

    private readonly List<Resistor> _resistors = new();
    private readonly List<VSource> _sources = new();
    private int _nodeCount = 1;

    public void EnsureNode(int n) { if (n + 1 > _nodeCount) _nodeCount = n + 1; }

    /// <summary>Añade una resistencia (Ω) entre dos nodos.</summary>
    public void AddResistor(int a, int b, double ohms)
    {
        EnsureNode(a); EnsureNode(b);
        _resistors.Add(new Resistor { A = a, B = b, R = Math.Max(1e-9, ohms) });
    }

    /// <summary>Fuente de tensión ideal (V) del nodo a (+) al nodo b (−). Devuelve su índice.</summary>
    public int AddVoltageSource(int a, int b, double volts)
    {
        EnsureNode(a); EnsureNode(b);
        _sources.Add(new VSource { A = a, B = b, V = volts });
        return _sources.Count - 1;
    }

    public int NodeCount => _nodeCount;

    /// <summary>
    /// Resuelve el circuito. Devuelve un diccionario:
    ///   { ok, node_voltages: PackedFloat64Array, source_currents: PackedFloat64Array,
    ///     main_current, total_power }.
    /// </summary>
    public Dictionary Solve()
    {
        int n = _nodeCount - 1;
        int m = _sources.Count;
        int size = n + m;
        var outDict = new Dictionary();
        var voltages = new double[_nodeCount];
        var currents = new double[m];

        if (size == 0)
        {
            outDict["ok"] = true;
            outDict["node_voltages"] = new double[] { 0.0 };
            outDict["source_currents"] = System.Array.Empty<double>();
            outDict["main_current"] = 0.0;
            outDict["total_power"] = 0.0;
            return outDict;
        }

        var A = new double[size, size];
        var z = new double[size];

        foreach (var r in _resistors)
        {
            double g = 1.0 / r.R;
            int i = r.A - 1, j = r.B - 1;
            if (i >= 0) A[i, i] += g;
            if (j >= 0) A[j, j] += g;
            if (i >= 0 && j >= 0) { A[i, j] -= g; A[j, i] -= g; }
        }
        for (int k = 0; k < m; k++)
        {
            var s = _sources[k];
            int p = s.A - 1, q = s.B - 1;
            int row = n + k;
            if (p >= 0) { A[p, row] += 1; A[row, p] += 1; }
            if (q >= 0) { A[q, row] -= 1; A[row, q] -= 1; }
            z[row] = s.V;
        }

        bool ok = SolveLinear(A, z, out double[] x);
        if (ok)
        {
            for (int i = 0; i < n; i++) voltages[i + 1] = x[i];
            for (int k = 0; k < m; k++) currents[k] = x[n + k];
        }

        double totalPower = 0;
        for (int k = 0; k < m; k++) totalPower += _sources[k].V * currents[k];

        outDict["ok"] = ok;
        outDict["node_voltages"] = voltages;
        outDict["source_currents"] = currents;
        outDict["main_current"] = m > 0 ? Math.Abs(currents[0]) : 0.0;
        outDict["total_power"] = Math.Abs(totalPower);
        return outDict;
    }

    /// <summary>Autonomía estimada en horas dada la corriente (A) y la capacidad (mAh).</summary>
    public static double AutonomyHours(double currentAmps, double capacityMah)
    {
        if (currentAmps <= 1e-9) return double.PositiveInfinity;
        return (capacityMah / 1000.0) / currentAmps;
    }

    private static bool SolveLinear(double[,] a, double[] b, out double[] x)
    {
        int n = b.Length;
        x = new double[n];
        for (int col = 0; col < n; col++)
        {
            int piv = col;
            double best = Math.Abs(a[col, col]);
            for (int r = col + 1; r < n; r++)
                if (Math.Abs(a[r, col]) > best) { best = Math.Abs(a[r, col]); piv = r; }
            if (best < 1e-12) return false;
            if (piv != col)
            {
                for (int c = 0; c < n; c++) (a[col, c], a[piv, c]) = (a[piv, c], a[col, c]);
                (b[col], b[piv]) = (b[piv], b[col]);
            }
            double d = a[col, col];
            for (int r = col + 1; r < n; r++)
            {
                double f = a[r, col] / d;
                if (f == 0) continue;
                for (int c = col; c < n; c++) a[r, c] -= f * a[col, c];
                b[r] -= f * b[col];
            }
        }
        for (int r = n - 1; r >= 0; r--)
        {
            double s = b[r];
            for (int c = r + 1; c < n; c++) s -= a[r, c] * x[c];
            x[r] = s / a[r, r];
        }
        return true;
    }
}
