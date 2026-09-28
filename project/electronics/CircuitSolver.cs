using System;
using System.Collections.Generic;
using Godot;
using Godot.Collections;

namespace MechaForge;

/// <summary>
/// CircuitSolver — Análisis Nodal Modificado NO LINEAL para el circuito "vivo".
///
/// Elementos:
///   · Rama (p, n, R, E): corriente de p a n = (Vp − Vn − E) / R. Con E = 0 es una
///     resistencia; con E ≠ 0 es una fuente con resistencia interna (equivalente de
///     Norton): baterías, salidas de integrados, pines digitales, derivador del
///     amperímetro, cables (R ≈ 0.1 Ω) e interruptores.
///   · Diodo/LED (a, k, Is, n·Vt, Rs): ecuación de Shockley con resistencia serie
///     (nodo interno de unión). Se resuelve por Newton-Raphson con limitación de la
///     tensión de unión (pnjlim, como SPICE) para converger desde cualquier punto.
///   · gmin: conductancia mínima de cada nodo a tierra (1 GΩ): los nodos flotantes
///     quedan definidos sin alterar el circuito.
///
/// El nodo 0 es la tierra. Todas las magnitudes en SI (V, A, Ω).
/// </summary>
public static class CircuitSolver
{
    public struct Branch { public int P, N; public double R, E; }
    public struct Diode { public int A, K; public double Is, Nvt, Rs; }

    public sealed class Result
    {
        public bool Ok;
        public int Iterations;
        public double[] V = System.Array.Empty<double>();
        public double[] Ib = System.Array.Empty<double>();
        public double[] Id = System.Array.Empty<double>();
        public double[] Vd = System.Array.Empty<double>();
    }

    public static Result Solve(int nodeCount, IList<Branch> branches, IList<Diode> diodes, double gmin = 1e-9, int maxIter = 200)
    {
        int nd = diodes.Count;
        int total = nodeCount + nd;        // nodos externos + nodo interno de cada diodo
        int n = total - 1;                 // incógnitas (sin la tierra)
        var res = new Result { V = new double[nodeCount], Ib = new double[branches.Count], Id = new double[nd], Vd = new double[nd] };
        if (n <= 0)
        {
            res.Ok = true;
            return res;
        }
        var v = new double[total];
        var vdLim = new double[nd];
        for (int k = 0; k < nd; k++) vdLim[k] = 0.6;
        var g = new double[n, n];
        var z = new double[n];
        bool converged = false;
        int it = 0;
        for (it = 1; it <= maxIter; it++)
        {
            System.Array.Clear(g);
            System.Array.Clear(z);
            for (int i = 0; i < n; i++) g[i, i] += gmin;
            foreach (var b in branches)
                StampBranch(g, z, b.P, b.N, 1.0 / Math.Max(1e-9, b.R), b.E);
            for (int k = 0; k < nd; k++)
            {
                var d = diodes[k];
                int j = nodeCount + k;
                StampBranch(g, z, d.A, j, 1.0 / Math.Max(1e-6, d.Rs), 0.0);
                double vd = vdLim[k];
                double ex = Math.Exp(Math.Min(vd / d.Nvt, 80.0));
                double id = d.Is * (ex - 1.0);
                double gd = d.Is / d.Nvt * ex + 1e-12;
                double ieq = id - gd * vd;
                StampConductance(g, j, d.K, gd);
                if (j > 0) z[j - 1] -= ieq;
                if (d.K > 0) z[d.K - 1] += ieq;
            }
            if (!SolveLinear(g, z, out double[] x))
                break;
            double maxDelta = 0.0;
            for (int i = 0; i < n; i++)
            {
                maxDelta = Math.Max(maxDelta, Math.Abs(x[i] - v[i + 1]));
                v[i + 1] = x[i];
            }
            // Tensión de unión nueva, limitada para la siguiente linealización.
            double maxVdDelta = 0.0;
            for (int k = 0; k < nd; k++)
            {
                var d = diodes[k];
                double vnew = v[nodeCount + k] - v[d.K];
                double vlim = PnjLim(vnew, vdLim[k], d.Nvt, d.Is);
                maxVdDelta = Math.Max(maxVdDelta, Math.Abs(vlim - vdLim[k]));
                vdLim[k] = vlim;
            }
            if (it > 1 && maxDelta < 1e-9 + 1e-7 * MaxAbs(v) && maxVdDelta < 1e-9)
            {
                converged = true;
                break;
            }
            if (nd == 0 && it >= 1)
            {
                converged = true;     // circuito lineal: una sola resolución
                break;
            }
        }
        res.Ok = converged;
        res.Iterations = it;
        for (int i = 0; i < nodeCount; i++) res.V[i] = v[i];
        for (int k = 0; k < branches.Count; k++)
        {
            var b = branches[k];
            res.Ib[k] = (v[b.P] - v[b.N] - b.E) / Math.Max(1e-9, b.R);
        }
        for (int k = 0; k < nd; k++)
        {
            var d = diodes[k];
            res.Id[k] = (v[d.A] - v[nodeCount + k]) / Math.Max(1e-6, d.Rs);
            res.Vd[k] = v[d.A] - v[d.K];
        }
        return res;
    }

    private static double MaxAbs(double[] a)
    {
        double m = 0.0;
        foreach (var x in a) m = Math.Max(m, Math.Abs(x));
        return m;
    }

    // Corriente de p a n = g·(Vp − Vn) − g·E  (KCL: corrientes que salen = 0).
    private static void StampBranch(double[,] g, double[] z, int p, int nn, double cond, double e)
    {
        StampConductance(g, p, nn, cond);
        if (e != 0.0)
        {
            if (p > 0) z[p - 1] += cond * e;
            if (nn > 0) z[nn - 1] -= cond * e;
        }
    }

    private static void StampConductance(double[,] g, int a, int b, double cond)
    {
        int i = a - 1, j = b - 1;
        if (i >= 0) g[i, i] += cond;
        if (j >= 0) g[j, j] += cond;
        if (i >= 0 && j >= 0) { g[i, j] -= cond; g[j, i] -= cond; }
    }

    /// <summary>Limitación de la tensión de unión entre iteraciones (SPICE pnjlim).</summary>
    private static double PnjLim(double vnew, double vold, double nvt, double isat)
    {
        double vcrit = nvt * Math.Log(nvt / (Math.Sqrt(2.0) * isat));
        if (vnew > vcrit && Math.Abs(vnew - vold) > 2.0 * nvt)
        {
            if (vold > 0.0)
            {
                double arg = 1.0 + (vnew - vold) / nvt;
                vnew = arg > 0.0 ? vold + nvt * Math.Log(arg) : vcrit;
            }
            else
            {
                vnew = nvt * Math.Log(Math.Max(1e-30, vnew / nvt));
            }
        }
        return vnew;
    }

    private static bool SolveLinear(double[,] src, double[] bsrc, out double[] x)
    {
        int n = bsrc.Length;
        var a = (double[,])src.Clone();
        var b = (double[])bsrc.Clone();
        x = new double[n];
        for (int col = 0; col < n; col++)
        {
            int piv = col;
            double best = Math.Abs(a[col, col]);
            for (int r = col + 1; r < n; r++)
                if (Math.Abs(a[r, col]) > best) { best = Math.Abs(a[r, col]); piv = r; }
            if (best < 1e-300) return false;
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

    /// <summary>Puente para GDScript: ramas [[p,n,R,E]] y diodos [[a,k,Is,nVt,Rs]].</summary>
    public static Dictionary SolveArrays(int nodeCount, Godot.Collections.Array branches, Godot.Collections.Array diodes)
    {
        var br = new List<Branch>(branches.Count);
        foreach (Variant item in branches)
        {
            var a = item.AsGodotArray();
            br.Add(new Branch { P = a[0].AsInt32(), N = a[1].AsInt32(), R = a[2].AsDouble(), E = a[3].AsDouble() });
        }
        var di = new List<Diode>(diodes.Count);
        foreach (Variant item in diodes)
        {
            var a = item.AsGodotArray();
            di.Add(new Diode { A = a[0].AsInt32(), K = a[1].AsInt32(), Is = a[2].AsDouble(), Nvt = a[3].AsDouble(), Rs = a[4].AsDouble() });
        }
        var r = Solve(Math.Max(1, nodeCount), br, di);
        return new Dictionary
        {
            ["ok"] = r.Ok, ["iters"] = r.Iterations,
            ["v"] = r.V, ["ib"] = r.Ib, ["id"] = r.Id, ["vd"] = r.Vd,
        };
    }
}
