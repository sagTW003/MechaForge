using System;
using System.Collections.Generic;
using Godot;

namespace MechaForge;

/// <summary>
/// MeshMass — Propiedades de masa de una malla triangular (sólido de densidad 1):
/// volumen, área de la superficie, centroide y tensor de inercia respecto al centroide.
///
/// Teorema de la divergencia: el sólido se descompone en tetraedros (O, a, b, c), uno
/// por triángulo, con volumen con signo V6/6 (V6 = a·(b×c)). Para cada tetraedro
///   ∫ x dV     = V6 · (a + b + c) / 24
///   ∫ x xᵀ dV  = V6 · (a aᵀ + b bᵀ + c cᵀ + s sᵀ) / 120,   s = a + b + c
/// y la suma da los momentos del sólido. Si la malla tiene las caras al revés el
/// volumen sale negativo y se cambia el signo de todo. Las cuentas van en double y
/// respecto al centro de la caja envolvente, para no perder cifras.
///
/// "cerrada" indica si la malla es estanca (cada arista la comparten exactamente dos
/// triángulos con sentidos opuestos, tras soldar vértices repetidos, como en un STL).
/// Si no lo es, el volumen no está bien definido y quien llama debe usar una estimación.
///
/// Uso desde GDScript: MeshTools.Compute(triangulos) (autoload) con
/// triangulos = PackedVector3Array (3 vértices por triángulo, en metros).
/// </summary>
public static class MeshMass
{
    public static Godot.Collections.Dictionary ComputeTris(Vector3[] tris)
    {
        int n = tris.Length / 3;
        var result = new Godot.Collections.Dictionary
        {
            ["volumen"] = 0.0, ["area"] = 0.0, ["centroide"] = Vector3.Zero,
            ["inercia"] = new Godot.Collections.Array { 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 },
            ["cerrada"] = false, ["triangulos"] = n,
        };
        if (n == 0)
            return result;
        // Centro de la caja envolvente (origen de los tetraedros).
        double minX = double.MaxValue, minY = double.MaxValue, minZ = double.MaxValue;
        double maxX = double.MinValue, maxY = double.MinValue, maxZ = double.MinValue;
        for (int i = 0; i < n * 3; i++)
        {
            var p = tris[i];
            minX = Math.Min(minX, p.X); maxX = Math.Max(maxX, p.X);
            minY = Math.Min(minY, p.Y); maxY = Math.Max(maxY, p.Y);
            minZ = Math.Min(minZ, p.Z); maxZ = Math.Max(maxZ, p.Z);
        }
        double ox = 0.5 * (minX + maxX), oy = 0.5 * (minY + maxY), oz = 0.5 * (minZ + maxZ);
        double diag = Math.Sqrt((maxX - minX) * (maxX - minX) + (maxY - minY) * (maxY - minY) + (maxZ - minZ) * (maxZ - minZ));

        double vol6 = 0, area2 = 0, mx = 0, my = 0, mz = 0;
        double cxx = 0, cyy = 0, czz = 0, cxy = 0, cxz = 0, cyz = 0;
        for (int t = 0; t < n; t++)
        {
            var pa = tris[3 * t]; var pb = tris[3 * t + 1]; var pc = tris[3 * t + 2];
            double ax = pa.X - ox, ay = pa.Y - oy, az = pa.Z - oz;
            double bx = pb.X - ox, by = pb.Y - oy, bz = pb.Z - oz;
            double qx = pc.X - ox, qy = pc.Y - oy, qz = pc.Z - oz;
            // Área: |(b − a) × (c − a)| / 2.
            double ux = bx - ax, uy = by - ay, uz = bz - az;
            double wx = qx - ax, wy = qy - ay, wz = qz - az;
            double nx = uy * wz - uz * wy, ny = uz * wx - ux * wz, nz = ux * wy - uy * wx;
            area2 += Math.Sqrt(nx * nx + ny * ny + nz * nz);
            // V6 = a · (b × c).
            double v6 = ax * (by * qz - bz * qy) + ay * (bz * qx - bx * qz) + az * (bx * qy - by * qx);
            double sx = ax + bx + qx, sy = ay + by + qy, sz = az + bz + qz;
            vol6 += v6;
            mx += v6 * sx; my += v6 * sy; mz += v6 * sz;
            cxx += v6 * (ax * ax + bx * bx + qx * qx + sx * sx);
            cyy += v6 * (ay * ay + by * by + qy * qy + sy * sy);
            czz += v6 * (az * az + bz * bz + qz * qz + sz * sz);
            cxy += v6 * (ax * ay + bx * by + qx * qy + sx * sy);
            cxz += v6 * (ax * az + bx * bz + qx * qz + sx * sz);
            cyz += v6 * (ay * az + by * bz + qy * qz + sy * sz);
        }
        double vol = vol6 / 6.0;
        mx /= 24.0; my /= 24.0; mz /= 24.0;
        cxx /= 120.0; cyy /= 120.0; czz /= 120.0; cxy /= 120.0; cxz /= 120.0; cyz /= 120.0;
        if (vol < 0.0)
        {
            vol = -vol; mx = -mx; my = -my; mz = -mz;
            cxx = -cxx; cyy = -cyy; czz = -czz; cxy = -cxy; cxz = -cxz; cyz = -cyz;
        }
        double rx = 0, ry = 0, rz = 0;
        double ixx = 0, iyy = 0, izz = 0, ixy = 0, ixz = 0, iyz = 0;
        if (vol > 0.0)
        {
            rx = mx / vol; ry = my / vol; rz = mz / vol;
            // Inercia respecto al origen y traslado al centroide (Steiner).
            ixx = cyy + czz - vol * (ry * ry + rz * rz);
            iyy = cxx + czz - vol * (rx * rx + rz * rz);
            izz = cxx + cyy - vol * (rx * rx + ry * ry);
            ixy = -(cxy - vol * rx * ry);
            ixz = -(cxz - vol * rx * rz);
            iyz = -(cyz - vol * ry * rz);
        }
        result["volumen"] = vol;
        result["area"] = area2 * 0.5;
        result["centroide"] = new Vector3((float)(rx + ox), (float)(ry + oy), (float)(rz + oz));
        result["inercia"] = new Godot.Collections.Array { ixx, iyy, izz, ixy, ixz, iyz };
        result["cerrada"] = IsClosed(tris, n, Math.Max(1e-9, diag * 1e-7));
        return result;
    }

    /// <summary>Estanca: tras soldar vértices, cada arista dirigida aparece una vez
    /// y su opuesta también una vez (sin bordes libres ni caras invertidas).</summary>
    private static bool IsClosed(Vector3[] tris, int n, double q)
    {
        var ids = new Dictionary<(long, long, long), int>();
        int Weld(Vector3 p)
        {
            var key = ((long)Math.Round(p.X / q), (long)Math.Round(p.Y / q), (long)Math.Round(p.Z / q));
            if (!ids.TryGetValue(key, out int id))
            {
                id = ids.Count;
                ids[key] = id;
            }
            return id;
        }
        var edges = new Dictionary<(int, int), int>();
        int faces = 0;
        for (int t = 0; t < n; t++)
        {
            int a = Weld(tris[3 * t]), b = Weld(tris[3 * t + 1]), c = Weld(tris[3 * t + 2]);
            if (a == b || b == c || a == c)
                continue;       // triángulo degenerado
            faces++;
            foreach (var e in new[] { (a, b), (b, c), (c, a) })
            {
                edges.TryGetValue(e, out int k);
                edges[e] = k + 1;
            }
        }
        if (faces < 4)
            return false;
        foreach (var kv in edges)
        {
            if (kv.Value != 1)
                return false;
            if (!edges.TryGetValue((kv.Key.Item2, kv.Key.Item1), out int r) || r != 1)
                return false;
        }
        return true;
    }
}
