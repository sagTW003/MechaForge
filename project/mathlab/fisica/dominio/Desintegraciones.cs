using System;
using System.Collections.Generic;
using System.Linq;

namespace MechaForge;

/// <summary>Cuadrimomento (E, px, py, pz) en GeV.</summary>
public struct V4
{
    public double E, X, Y, Z;
    public V4(double e, double x, double y, double z) { E = e; X = x; Y = y; Z = z; }
    public double P => Math.Sqrt(X * X + Y * Y + Z * Z);
    public double M => Math.Sqrt(Math.Max(0.0, E * E - X * X - Y * Y - Z * Z));
    public static V4 operator +(V4 a, V4 b) => new(a.E + b.E, a.X + b.X, a.Y + b.Y, a.Z + b.Z);

    /// <summary>Transformación de Lorentz pura con velocidad β = (bx, by, bz) (en unidades de c).</summary>
    public V4 Boost(double bx, double by, double bz)
    {
        double b2 = bx * bx + by * by + bz * bz;
        if (b2 <= 0.0) return this;
        double g = 1.0 / Math.Sqrt(1.0 - b2);
        double bp = bx * X + by * Y + bz * Z;
        double g2 = (g - 1.0) / b2;
        return new V4(g * (E + bp), X + g2 * bp * bx + g * bx * E, Y + g2 * bp * by + g * by * E, Z + g2 * bp * bz + g * bz * E);
    }
}

/// <summary>
/// Desintegraciones — Cinemática relativista y sucesos de una cámara de burbujas:
///   · dos cuerpos: p* = √[(M² − (m₁ + m₂)²)(M² − (m₁ − m₂)²)] / 2M, isótropo (exacto);
///   · tres o más: espacio de fases plano (GENBOD, F. James, CERN 68-15, 1968), sin el elemento
///     de matriz de cada canal (aproximado: la distribución de energías no es la real);
///   · vida en el laboratorio: longitud de vuelo L = βγcτ·(−ln U) (exacto);
///   · trazas en un campo B uniforme según z: hélices de radio R = p_T / (0,299792458 |q| B)
///     (R en m, p en GeV/c, B en T, q en e); sin pérdida de energía en el medio (por eso cada
///     traza se corta a las 30 veces el radio de la cámara: si no, giraría sin fin).
/// Canal elegido al azar con las fracciones del PDG (renormalizadas si la tabla no los tiene todos).
/// </summary>
public static class Desintegraciones
{
    public const double C = 299792458.0;

    public static double TwoBodyP(double M, double m1, double m2)
    {
        double a = (M * M - (m1 + m2) * (m1 + m2)) * (M * M - (m1 - m2) * (m1 - m2));
        return a > 0.0 ? Math.Sqrt(a) / (2.0 * M) : 0.0;
    }

    static (double, double, double) Isotropic(Random rng)
    {
        double c = 2.0 * rng.NextDouble() - 1.0, s = Math.Sqrt(1.0 - c * c), f = 2.0 * Math.PI * rng.NextDouble();
        return (s * Math.Cos(f), s * Math.Sin(f), c);
    }

    /// <summary>Productos de masas m (GeV) de una partícula de cuadrimomento parent (espacio de fases plano).</summary>
    public static V4[] Decay(V4 parent, double[] m, Random rng)
    {
        int n = m.Length;
        double M = parent.M, tecm = M - m.Sum();
        var res = new V4[n];
        if (n == 1) { res[0] = parent; return res; }
        // Peso máximo (como TGenPhaseSpace) y masas invariantes intermedias M_k de los k primeros.
        double wmax = 1.0, emmax = tecm + m[0], emmin = 0.0;
        for (int k = 1; k < n; k++) { emmin += m[k - 1]; emmax += m[k]; wmax *= TwoBodyP(emmax, emmin, m[k]); }
        var inv = new double[n];
        while (true)
        {
            var r = new double[n];
            r[0] = 0.0; r[n - 1] = 1.0;
            for (int k = 1; k < n - 1; k++) r[k] = rng.NextDouble();
            Array.Sort(r, 1, n - 2 > 0 ? n - 2 : 0);
            double sum = 0.0, w = 1.0;
            for (int k = 0; k < n; k++) { sum += m[k]; inv[k] = r[k] * tecm + sum; }
            for (int k = 1; k < n; k++) w *= TwoBodyP(inv[k], inv[k - 1], m[k]);
            if (n == 2 || w >= rng.NextDouble() * wmax) break;
        }
        // De arriba abajo: el sistema de los k primeros (masa inv[k−1]) se parte en el de los
        // k − 1 primeros y la partícula k−1, isótropo en su reposo; se lleva al sistema en reposo.
        var sys = new V4(M, 0, 0, 0);
        for (int k = n - 1; k >= 1; k--)
        {
            double q = TwoBodyP(inv[k], inv[k - 1], m[k]);
            var (ux, uy, uz) = Isotropic(rng);
            var pk = new V4(Math.Sqrt(q * q + m[k] * m[k]), q * ux, q * uy, q * uz);
            var rest = new V4(Math.Sqrt(q * q + inv[k - 1] * inv[k - 1]), -q * ux, -q * uy, -q * uz);
            double bx = sys.X / sys.E, by = sys.Y / sys.E, bz = sys.Z / sys.E;
            res[k] = pk.Boost(bx, by, bz);
            sys = rest.Boost(bx, by, bz);
        }
        res[0] = sys;
        double gx = parent.X / parent.E, gy = parent.Y / parent.E, gz = parent.Z / parent.E;
        for (int k = 0; k < n; k++) res[k] = res[k].Boost(gx, gy, gz);
        return res;
    }

    /// <summary>Índice del canal según las fracciones (renormalizadas).</summary>
    public static int ChooseChannel(Particula p, Random rng)
    {
        double tot = p.Desint.Sum(d => d.Br), u = rng.NextDouble() * tot, acc = 0.0;
        for (int i = 0; i < p.Desint.Count; i++) { acc += p.Desint[i].Br; if (u < acc) return i; }
        return p.Desint.Count - 1;
    }

    public static string ChannelText(Particula p, int i) =>
        p.Simbolo + " → " + string.Join(" ", p.Desint[i].Productos.Select(x => Particulas.Get(x).Simbolo));

    public sealed class Traza
    {
        public string Id = "";
        public int Padre = -1, Canal = -1;
        public List<double[]> Puntos = new();             // m
        public V4 P0, P1;                                 // al nacer y al final
        public bool Decae;
        public double LongitudM;                          // recorrida
        public List<string> Violaciones = new();          // en su vértice de desintegración
    }

    /// <summary>
    /// Un suceso: la partícula «id» nace en el origen con momento p (GeV/c) según x, en un campo B
    /// (T) según z, dentro de un cilindro de radio y semialtura «radio» (m). Las inestables se
    /// desintegran (hasta «profundidad» generaciones) y sus productos siguen. Máximo 40 trazas.
    /// </summary>
    public static List<Traza> Event(string id, double p, double bz, double radio, int profundidad, int seed)
    {
        var rng = new Random(seed);
        var trazas = new List<Traza>();
        var cola = new Queue<(string id, double[] x, V4 mom, int padre, int prof)>();
        double m0 = Particulas.Get(id).MasaMeV / 1000.0;
        cola.Enqueue((id, new double[3], new V4(Math.Sqrt(p * p + m0 * m0), p, 0, 0), -1, 0));
        while (cola.Count > 0 && trazas.Count < 40)
        {
            var (pid, x0, mom, padre, prof) = cola.Dequeue();
            var part = Particulas.Get(pid);
            var t = new Traza { Id = pid, Padre = padre, P0 = mom };
            trazas.Add(t);
            double m = part.MasaMeV / 1000.0;
            double L = double.PositiveInfinity;
            if (part.Desint.Count > 0 && prof < profundidad && !double.IsInfinity(part.VidaS) && m > 0)
                L = mom.P / m * C * part.VidaS * -Math.Log(1.0 - rng.NextDouble());
            var (x1, mom1, dentro) = Propagate(t, x0, mom, part.Carga3 / 3.0, bz, L, radio);
            t.P1 = mom1;
            if (!dentro) continue;
            t.Decae = true;
            t.Canal = ChooseChannel(part, rng);
            var prods = part.Desint[t.Canal].Productos;
            var hijos = Decay(mom1, prods.Select(q => Particulas.Get(q).MasaMeV / 1000.0).ToArray(), rng);
            t.Violaciones = Particulas.Violations(new[] { pid }, prods, true);
            var suma = hijos.Aggregate(new V4(), (a, b) => a + b);
            double d4 = Math.Abs(suma.E - mom1.E) + Math.Abs(suma.X - mom1.X) + Math.Abs(suma.Y - mom1.Y) + Math.Abs(suma.Z - mom1.Z);
            if (d4 > 1e-9 * mom1.E) t.Violaciones.Add($"cuadrimomento: no se conserva (diferencia {d4:E2} GeV)");
            for (int i = 0; i < prods.Length; i++) cola.Enqueue((prods[i], x1, hijos[i], trazas.Count - 1, prof + 1));
        }
        return trazas;
    }

    /// <summary>Distancia hasta la pared del cilindro (radio y semialtura «radio») por la recta x + s·d.</summary>
    static double ExitDistance(double[] x, double dx, double dy, double dz, double radio)
    {
        double sOut = double.PositiveInfinity;
        double a = dx * dx + dy * dy;
        if (a > 0)
        {
            double b = 2 * (x[0] * dx + x[1] * dy), c = x[0] * x[0] + x[1] * x[1] - radio * radio;
            sOut = (-b + Math.Sqrt(Math.Max(0.0, b * b - 4 * a * c))) / (2 * a);
        }
        if (dz > 0) sOut = Math.Min(sOut, (radio - x[2]) / dz);
        else if (dz < 0) sOut = Math.Min(sOut, (-radio - x[2]) / dz);
        return sOut;
    }

    /// <summary>
    /// Avanza una longitud L (m) o hasta salir del cilindro. Con carga y B: hélice exacta (cada paso
    /// es una cuerda de la circunferencia); devuelve la posición, el momento al final y si sigue dentro.
    /// </summary>
    static (double[] x, V4 mom, bool dentro) Propagate(Traza t, double[] x0, V4 mom, double q, double bz, double L, double radio)
    {
        double[] x = (double[])x0.Clone();
        t.Puntos.Add((double[])x.Clone());
        double p = mom.P;
        if (p <= 0.0) return (x, mom, true);
        double pt = Math.Sqrt(mom.X * mom.X + mom.Y * mom.Y);
        double ux = pt > 0 ? mom.X / pt : 0, uy = pt > 0 ? mom.Y / pt : 0;
        double kappa = (q != 0.0 && bz != 0.0 && pt > 0) ? 0.299792458 * Math.Abs(q) * Math.Abs(bz) / pt : 0.0;
        double sgn = -Math.Sign(q) * Math.Sign(bz);      // carga positiva con B según +z: giro horario
        if (kappa == 0.0)
        {
            // Recta (neutra o sin campo): de una vez, hasta L o hasta la pared del cilindro.
            double dx = mom.X / p, dy = mom.Y / p, dz = mom.Z / p;
            double sEnd = Math.Min(L, ExitDistance(x, dx, dy, dz, radio));
            x[0] += sEnd * dx; x[1] += sEnd * dy; x[2] += sEnd * dz;
            t.Puntos.Add((double[])x.Clone());
            t.LongitudM = sEnd;
            return (x, mom, sEnd < ExitDistance(x0, dx, dy, dz, radio));
        }
        double ds = 0.005, s = 0.0;                       // longitud recorrida (m)
        bool dentro = true;
        while (s < L)
        {
            double h = Math.Min(ds, L - s);
            double hT = h * pt / p, hz = h * mom.Z / p;
            double da = sgn * kappa * hT;
            double cm = Math.Cos(da / 2), sm = Math.Sin(da / 2);
            double mx = ux * cm - uy * sm, my = ux * sm + uy * cm;
            double chord = Math.Abs(da) > 1e-12 ? hT * Math.Sin(da / 2) / (da / 2) : hT;
            x[0] += chord * mx; x[1] += chord * my; x[2] += hz;
            double c = Math.Cos(da), sn = Math.Sin(da);
            (ux, uy) = (ux * c - uy * sn, ux * sn + uy * c);
            s += h;
            if (t.Puntos.Count < 800 && (t.Puntos.Count < 2 || s - t.LongitudM > 0.02))
            {
                t.Puntos.Add((double[])x.Clone());
                t.LongitudM = s;
            }
            if (x[0] * x[0] + x[1] * x[1] > radio * radio || Math.Abs(x[2]) > radio) { dentro = false; break; }
            // Una estable cuya circunferencia cabe en la cámara giraría sin fin (no pierde energía).
            if (s > 30.0 * radio) { dentro = false; break; }
        }
        t.LongitudM = Math.Min(s, L);
        t.Puntos.Add((double[])x.Clone());
        return (x, new V4(mom.E, pt * ux, pt * uy, mom.Z), dentro && !double.IsInfinity(L));
    }
}
