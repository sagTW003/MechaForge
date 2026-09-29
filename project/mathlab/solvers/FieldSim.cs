using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Godot;

namespace MechaForge;

/// <summary>
/// FieldSim — Integrador de EDPs 2D en tiempo real para el Laboratorio matemático.
///
///   · "onda":        ∂²u/∂t² = c²∇²u − γ ∂u/∂t   (FDTD en salto de rana, Courant ≤ 0.5).
///                     Fronteras fija (Dirichlet), libre (Neumann) o absorbente (Mur).
///                     Membrana cuadrada o circular (tambor), modos normales y fuentes.
///   · "calor":       ∂T/∂t = ∇·(α∇T) − κ(T − T_amb) + q    (explícito conservativo con
///                     α por celda: materiales pintados). Bordes a T fija o aislados.
///   · "schrodinger": iħ∂ψ/∂t = −ħ²/2m ∇²ψ + Vψ   (ħ = m = 1; esquema de Visscher con
///                     partes real e imaginaria desfasadas medio paso, estable y que
///                     conserva la norma) con potencial absorbente en los bordes.
///
/// El estado se publica en una textura RGBA float (R = altura/valor principal,
/// G y B = auxiliares, A = máscara/material/potencial) que el shader de superficie
/// usa para deformar la malla en la GPU y colorearla.
/// Coordenadas de entrada normalizadas u, v ∈ [0, 1].
/// </summary>
[GlobalClass]
public partial class FieldSim : RefCounted
{
    private string _kind = "onda";
    private int _nx = 2, _ny = 2;
    private float[] _a = System.Array.Empty<float>();     // onda: u      calor: T     schr: Re ψ
    private float[] _b = System.Array.Empty<float>();     // onda: u_ant  calor: T'    schr: Im ψ
    private float[] _c = System.Array.Empty<float>();     // onda: u_sig  calor: α     schr: V
    private float[] _q = System.Array.Empty<float>();     // calor: fuente fija; schr: absorción
    private byte[] _mask = System.Array.Empty<byte>();
    private float[] _rgba = System.Array.Empty<float>();
    private byte[] _bytes = System.Array.Empty<byte>();
    private Image _img = null!;           // se crean en Setup() antes de usarse
    private ImageTexture _tex = null!;
    private double _time;
    private readonly List<double[]> _sources = new();     // [u, v, frecuencia, amplitud]

    // Parámetros (SetParam)
    public double C = 1.0;              // velocidad de onda
    public double Damping = 0.02;       // γ
    public int Boundary = 0;            // 0 fija, 1 libre, 2 absorbente
    public int Shape = 0;               // 0 cuadrada, 1 circular
    public double Length = 2.0;         // lado del dominio (m o unidades)
    public double Ambient = 20.0;       // °C
    public double Cooling = 0.0;        // κ (1/s)
    public int HeatEdge = 1;            // 0 aislado, 1 T fija = ambiente
    public double VMax = 10.0;          // escala del potencial para la textura

    public int Nx => _nx;
    public int Ny => _ny;
    public double Time => _time;

    public void Setup(string kind, int nx, int ny, double length)
    {
        _kind = kind;
        _nx = Math.Max(8, nx);
        _ny = Math.Max(8, ny);
        Length = length;
        int n = _nx * _ny;
        _a = new float[n]; _b = new float[n]; _c = new float[n]; _q = new float[n];
        _mask = new byte[n];
        _rgba = new float[n * 4];
        _bytes = new byte[n * 16];
        _img = Image.CreateEmpty(_nx, _ny, false, Image.Format.Rgbaf);
        _tex = ImageTexture.CreateFromImage(_img);
        _sources.Clear();
        Reset();
    }

    public ImageTexture GetTexture() => _tex;

    public void Reset()
    {
        _time = 0;
        Array.Clear(_a); Array.Clear(_b);
        if (_kind == "calor")
        {
            for (int i = 0; i < _a.Length; i++) { _a[i] = (float)Ambient; _b[i] = (float)Ambient; }
            if (_c.Length > 0 && _c[0] == 0f)
                for (int i = 0; i < _c.Length; i++) _c[i] = 9.7e-5f;       // aluminio
        }
        if (_kind == "onda") Array.Clear(_c);
        RebuildMask();
        Upload();
    }

    public void SetParam(string name, double v)
    {
        switch (name)
        {
            case "c": C = v; break;
            case "amortiguamiento": Damping = v; break;
            case "frontera": Boundary = (int)v; break;
            case "forma": Shape = (int)v; RebuildMask(); break;
            case "ambiente": Ambient = v; break;
            case "enfriamiento": Cooling = v; break;
            case "borde_calor": HeatEdge = (int)v; break;
            case "vmax": VMax = v; break;
        }
    }

    private int Idx(int i, int j) => j * _nx + i;
    private double H => Length / (_nx - 1);

    private void RebuildMask()
    {
        for (int j = 0; j < _ny; j++)
            for (int i = 0; i < _nx; i++)
            {
                double x = (double)i / (_nx - 1) * 2 - 1, y = (double)j / (_ny - 1) * 2 - 1;
                bool inside = Shape == 0 ? (i > 0 && j > 0 && i < _nx - 1 && j < _ny - 1) : (x * x + y * y < 0.985);
                _mask[Idx(i, j)] = (byte)(inside ? 1 : 0);
            }
    }

    // ------------------------------------------------------------------ paso
    /// <summary>Avanza "simTime" segundos repartidos en sub-pasos estables. Devuelve los sub-pasos usados.</summary>
    public int Step(double simTime, int maxSub)
    {
        if (simTime <= 0) { Upload(); return 0; }
        double h = H;
        double dtMax;
        switch (_kind)
        {
            case "onda": dtMax = 0.5 * h / Math.Max(1e-6, C); break;
            case "calor":
                {
                    float amax = 1e-12f;
                    foreach (var a in _c) amax = Math.Max(amax, a);
                    dtMax = 0.24 * h * h / amax;
                    break;
                }
            default:
                {
                    float vm = 0f;
                    foreach (var v in _c) vm = Math.Max(vm, Math.Abs(v));
                    dtMax = 1.0 / (4.0 / (h * h) + vm) * 0.9;
                    break;
                }
        }
        int sub = (int)Math.Ceiling(simTime / dtMax);
        sub = Math.Clamp(sub, 1, Math.Max(1, maxSub));
        double dt = Math.Min(dtMax, simTime / sub);
        for (int s = 0; s < sub; s++)
        {
            switch (_kind)
            {
                case "onda": WaveStep(dt, h); break;
                case "calor": HeatStep(dt, h); break;
                default: SchrStep(dt, h); break;
            }
            _time += dt;
        }
        Upload();
        return sub;
    }

    private void WaveStep(double dt, double h)
    {
        float r2 = (float)(C * C * dt * dt / (h * h));
        float g = (float)(Damping * dt);
        int nx = _nx, ny = _ny;
        var u = _a; var up = _b; var un = _c; var m = _mask;
        Parallel.For(1, ny - 1, j =>
        {
            for (int i = 1; i < nx - 1; i++)
            {
                int k = j * nx + i;
                if (m[k] == 0) { un[k] = 0; continue; }
                float lap = u[k - 1] + u[k + 1] + u[k - nx] + u[k + nx] - 4f * u[k];
                un[k] = (2f - g) * u[k] - (1f - g) * up[k] + r2 * lap;
            }
        });
        // Fuentes continuas (senoides suaves).
        foreach (var s in _sources)
        {
            double f = s[2], amp = s[3];
            AddGaussian(un, s[0], s[1], amp * Math.Sin(2 * Math.PI * f * (_time + dt)) * 0.02, 0.018, true);
        }
        // Fronteras.
        if (Shape == 0)
        {
            if (Boundary == 1)
            {
                for (int i = 0; i < nx; i++) { un[Idx(i, 0)] = un[Idx(i, 1)]; un[Idx(i, ny - 1)] = un[Idx(i, ny - 2)]; }
                for (int j = 0; j < ny; j++) { un[Idx(0, j)] = un[Idx(1, j)]; un[Idx(nx - 1, j)] = un[Idx(nx - 2, j)]; }
            }
            else if (Boundary == 2)
            {
                float cr = (float)(C * dt / h);
                float kmur = (cr - 1f) / (cr + 1f);
                for (int i = 0; i < nx; i++)
                {
                    un[Idx(i, 0)] = u[Idx(i, 1)] + kmur * (un[Idx(i, 1)] - u[Idx(i, 0)]);
                    un[Idx(i, ny - 1)] = u[Idx(i, ny - 2)] + kmur * (un[Idx(i, ny - 2)] - u[Idx(i, ny - 1)]);
                }
                for (int j = 0; j < ny; j++)
                {
                    un[Idx(0, j)] = u[Idx(1, j)] + kmur * (un[Idx(1, j)] - u[Idx(0, j)]);
                    un[Idx(nx - 1, j)] = u[Idx(nx - 2, j)] + kmur * (un[Idx(nx - 2, j)] - u[Idx(nx - 1, j)]);
                }
            }
            else
            {
                for (int i = 0; i < nx; i++) { un[Idx(i, 0)] = 0; un[Idx(i, ny - 1)] = 0; }
                for (int j = 0; j < ny; j++) { un[Idx(0, j)] = 0; un[Idx(nx - 1, j)] = 0; }
            }
        }
        // Rotación de búferes: anterior ← actual ← siguiente.
        _b = u; _a = un; _c = up;
    }

    private void HeatStep(double dt, double h)
    {
        int nx = _nx, ny = _ny;
        var T = _a; var Tn = _b; var al = _c; var q = _q;
        float kdt = (float)(dt / (h * h));
        float cool = (float)(Cooling * dt);
        float amb = (float)Ambient;
        Parallel.For(1, ny - 1, j =>
        {
            for (int i = 1; i < nx - 1; i++)
            {
                int k = j * nx + i;
                float ak = al[k];
                // Conductividad de cara (media armónica): fronteras entre materiales correctas.
                float ae = 2f * ak * al[k + 1] / (ak + al[k + 1] + 1e-20f);
                float aw = 2f * ak * al[k - 1] / (ak + al[k - 1] + 1e-20f);
                float an = 2f * ak * al[k + nx] / (ak + al[k + nx] + 1e-20f);
                float as_ = 2f * ak * al[k - nx] / (ak + al[k - nx] + 1e-20f);
                float div = ae * (T[k + 1] - T[k]) - aw * (T[k] - T[k - 1]) + an * (T[k + nx] - T[k]) - as_ * (T[k] - T[k - nx]);
                Tn[k] = T[k] + kdt * div - cool * (T[k] - amb) + (float)dt * q[k];
            }
        });
        for (int i = 0; i < nx; i++)
        {
            Tn[Idx(i, 0)] = HeatEdge == 1 ? amb : Tn[Idx(i, 1)];
            Tn[Idx(i, ny - 1)] = HeatEdge == 1 ? amb : Tn[Idx(i, ny - 2)];
        }
        for (int j = 0; j < ny; j++)
        {
            Tn[Idx(0, j)] = HeatEdge == 1 ? amb : Tn[Idx(1, j)];
            Tn[Idx(nx - 1, j)] = HeatEdge == 1 ? amb : Tn[Idx(nx - 2, j)];
        }
        _a = Tn; _b = T;
    }

    private void SchrStep(double dt, double h)
    {
        int nx = _nx, ny = _ny;
        var R = _a; var I = _b; var V = _c; var cap = _q;
        float kin = (float)(0.5 / (h * h));
        float fdt = (float)dt;
        // R(t+dt) = R + dt·H·I ;  I(t+3dt/2) = I − dt·H·R(t+dt)
        Parallel.For(1, ny - 1, j =>
        {
            for (int i = 1; i < nx - 1; i++)
            {
                int k = j * nx + i;
                float hi = -kin * (I[k - 1] + I[k + 1] + I[k - nx] + I[k + nx] - 4f * I[k]) + V[k] * I[k];
                R[k] += fdt * hi;
            }
        });
        Parallel.For(1, ny - 1, j =>
        {
            for (int i = 1; i < nx - 1; i++)
            {
                int k = j * nx + i;
                float hr = -kin * (R[k - 1] + R[k + 1] + R[k - nx] + R[k + nx] - 4f * R[k]) + V[k] * R[k];
                I[k] -= fdt * hr;
                // Potencial absorbente en el marco exterior (evita reflexiones).
                if (cap[k] > 0f)
                {
                    float d = 1f - cap[k] * fdt;
                    R[k] *= d; I[k] *= d;
                }
            }
        });
    }

    // --------------------------------------------------------------- publicación
    public void Upload()
    {
        int n = _nx * _ny;
        switch (_kind)
        {
            case "onda":
                for (int k = 0; k < n; k++)
                {
                    _rgba[k * 4] = _a[k];
                    _rgba[k * 4 + 1] = _a[k] - _b[k];
                    _rgba[k * 4 + 2] = 0f;
                    _rgba[k * 4 + 3] = _mask[k];
                }
                break;
            case "calor":
                for (int k = 0; k < n; k++)
                {
                    _rgba[k * 4] = _a[k];
                    _rgba[k * 4 + 1] = _q[k];
                    _rgba[k * 4 + 2] = 0f;
                    _rgba[k * 4 + 3] = MaterialIndex(_c[k]);
                }
                break;
            default:
                float vs = (float)(1.0 / Math.Max(1e-6, VMax));
                for (int k = 0; k < n; k++)
                {
                    _rgba[k * 4] = _a[k] * _a[k] + _b[k] * _b[k];
                    _rgba[k * 4 + 1] = _a[k];
                    _rgba[k * 4 + 2] = _b[k];
                    _rgba[k * 4 + 3] = _c[k] * vs;
                }
                break;
        }
        Buffer.BlockCopy(_rgba, 0, _bytes, 0, _bytes.Length);
        _img.SetData(_nx, _ny, false, Image.Format.Rgbaf, _bytes);
        _tex.Update(_img);
    }

    private static float MaterialIndex(float a)
    {
        // α (m²/s) → índice de material para el shader (0 madera … 4 cobre).
        if (a > 1.0e-4f) return 4f;
        if (a > 5e-5f) return 3f;
        if (a > 5e-6f) return 2f;
        if (a > 2e-7f) return 1f;
        return 0f;
    }

    // --------------------------------------------------------------- interacción
    private void AddGaussian(float[] f, double u, double v, double amp, double radius, bool respectMask)
    {
        int ci = (int)Math.Round(u * (_nx - 1)), cj = (int)Math.Round(v * (_ny - 1));
        int rr = (int)Math.Ceiling(radius * 3 * (_nx - 1)) + 1;
        double s2 = radius * radius * (_nx - 1) * (_nx - 1);
        for (int j = Math.Max(1, cj - rr); j <= Math.Min(_ny - 2, cj + rr); j++)
            for (int i = Math.Max(1, ci - rr); i <= Math.Min(_nx - 2, ci + rr); i++)
            {
                int k = Idx(i, j);
                if (respectMask && _mask.Length > 0 && _mask[k] == 0 && _kind == "onda") continue;
                double d2 = (i - ci) * (i - ci) + (j - cj) * (j - cj);
                f[k] += (float)(amp * Math.Exp(-d2 / (2 * s2)));
            }
    }

    /// <summary>Perturbación: pulso (onda), calor inyectado (calor) o barrera de potencial (Schrödinger).</summary>
    public void Perturb(double u, double v, double amp, double radius)
    {
        switch (_kind)
        {
            case "onda":
                AddGaussian(_a, u, v, amp, radius, true);
                AddGaussian(_b, u, v, amp, radius, true);
                break;
            case "calor":
                AddGaussian(_a, u, v, amp, radius, false);
                AddGaussian(_b, u, v, amp, radius, false);
                break;
            default:
                AddGaussian(_c, u, v, amp, radius, false);
                break;
        }
        Upload();
    }

    public void AddSource(double u, double v, double freq, double amp) => _sources.Add(new[] { u, v, freq, amp });
    public void ClearSources() => _sources.Clear();
    public int SourceCount() => _sources.Count;

    /// <summary>Fuente de calor fija (W/m³ normalizados → °C/s) en un disco.</summary>
    public void SetHeatSource(double u, double v, double radius, double rate)
    {
        int ci = (int)Math.Round(u * (_nx - 1)), cj = (int)Math.Round(v * (_ny - 1));
        int rr = (int)Math.Ceiling(radius * (_nx - 1));
        for (int j = Math.Max(1, cj - rr); j <= Math.Min(_ny - 2, cj + rr); j++)
            for (int i = Math.Max(1, ci - rr); i <= Math.Min(_nx - 2, ci + rr); i++)
                if ((i - ci) * (i - ci) + (j - cj) * (j - cj) <= rr * rr)
                    _q[Idx(i, j)] = (float)rate;
        Upload();
    }

    public void ClearHeatSources() { Array.Clear(_q); Upload(); }

    /// <summary>Pinta un material (difusividad α) en un disco.</summary>
    public void PaintMaterial(double u, double v, double radius, double alpha)
    {
        int ci = (int)Math.Round(u * (_nx - 1)), cj = (int)Math.Round(v * (_ny - 1));
        int rr = Math.Max(1, (int)Math.Ceiling(radius * (_nx - 1)));
        for (int j = Math.Max(0, cj - rr); j <= Math.Min(_ny - 1, cj + rr); j++)
            for (int i = Math.Max(0, ci - rr); i <= Math.Min(_nx - 1, ci + rr); i++)
                if ((i - ci) * (i - ci) + (j - cj) * (j - cj) <= rr * rr)
                    _c[Idx(i, j)] = (float)alpha;
        Upload();
    }

    public void FillMaterial(double alpha)
    {
        for (int i = 0; i < _c.Length; i++) _c[i] = (float)alpha;
        Upload();
    }

    /// <summary>Rectángulo de material [u0,u1]×[v0,v1].</summary>
    public void RectMaterial(double u0, double v0, double u1, double v1, double alpha)
    {
        for (int j = 0; j < _ny; j++)
            for (int i = 0; i < _nx; i++)
            {
                double u = (double)i / (_nx - 1), v = (double)j / (_ny - 1);
                if (u >= u0 && u <= u1 && v >= v0 && v <= v1) _c[Idx(i, j)] = (float)alpha;
            }
        Upload();
    }

    /// <summary>Modo normal (m, n) de la membrana: cuadrada (senos) o circular (Bessel).</summary>
    public void NormalMode(int m, int n, double amp)
    {
        Array.Clear(_a); Array.Clear(_b);
        double omega;
        if (Shape == 0)
        {
            omega = C * Math.PI / Length * Math.Sqrt(m * m + n * n);
        }
        else
        {
            double alpha = BesselZero(m, n);
            omega = C * alpha / (Length * 0.5);
        }
        double h = H;
        double dt = 0.5 * h / Math.Max(1e-6, C);
        for (int j = 0; j < _ny; j++)
            for (int i = 0; i < _nx; i++)
            {
                int k = Idx(i, j);
                if (_mask[k] == 0) continue;
                double x = (double)i / (_nx - 1), y = (double)j / (_ny - 1);
                double val;
                if (Shape == 0)
                    val = Math.Sin(m * Math.PI * x) * Math.Sin(n * Math.PI * y);
                else
                {
                    double X = x * 2 - 1, Y = y * 2 - 1;
                    double r = Math.Sqrt(X * X + Y * Y), th = Math.Atan2(Y, X);
                    val = BesselJ(m, BesselZero(m, n) * r) * Math.Cos(m * th);
                }
                _a[k] = (float)(amp * val);
                _b[k] = (float)(amp * val * Math.Cos(omega * dt));
            }
        _time = 0;
        Upload();
    }

    public static double BesselJ(int m, double x)
    {
        double sum = 0, term = Math.Pow(x / 2, m);
        double fact = 1;
        for (int k = 1; k <= m; k++) fact *= k;
        term /= fact;
        for (int k = 0; k < 60; k++)
        {
            sum += term;
            term *= -(x * x / 4) / ((k + 1) * (k + 1 + m));
            if (Math.Abs(term) < 1e-16) break;
        }
        return sum;
    }

    public static double BesselZero(int m, int n)
    {
        double[,] z = {
            { 2.404826, 5.520078, 8.653728, 11.791534 },
            { 3.831706, 7.015587, 10.173468, 13.323692 },
            { 5.135622, 8.417244, 11.619841, 14.795952 },
            { 6.380162, 9.761023, 13.015201, 16.223466 },
            { 7.588342, 11.064709, 14.372537, 17.615966 },
        };
        return z[Math.Clamp(m, 0, 4), Math.Clamp(n - 1, 0, 3)];
    }

    // --------------------------------------------------------------- Schrödinger
    /// <summary>Paquete gaussiano centrado en (u0,v0) con momento (kx, ky) y anchura σ (unidades del dominio).</summary>
    public void InitPacket(double u0, double v0, double kx, double ky, double sigma)
    {
        double L = Length;
        double x0 = (u0 - 0.5) * L, y0 = (v0 - 0.5) * L;
        double norm = 0;
        for (int j = 0; j < _ny; j++)
            for (int i = 0; i < _nx; i++)
            {
                double x = ((double)i / (_nx - 1) - 0.5) * L, y = ((double)j / (_ny - 1) - 0.5) * L;
                double env = Math.Exp(-((x - x0) * (x - x0) + (y - y0) * (y - y0)) / (4 * sigma * sigma));
                double ph = kx * x + ky * y;
                int k = Idx(i, j);
                _a[k] = (float)(env * Math.Cos(ph));
                _b[k] = (float)(env * Math.Sin(ph));
                norm += env * env;
            }
        double h = H;
        double s = 1.0 / Math.Sqrt(norm * h * h);
        for (int k = 0; k < _a.Length; k++) { _a[k] *= (float)s; _b[k] *= (float)s; }
        // Visscher: la parte imaginaria va medio paso por delante.
        double dt = 1.0 / (4.0 / (h * h)) * 0.9 * 0.5;
        var R = (float[])_a.Clone();
        for (int j = 1; j < _ny - 1; j++)
            for (int i = 1; i < _nx - 1; i++)
            {
                int k = Idx(i, j);
                float kin = (float)(0.5 / (h * h));
                float hr = -kin * (R[k - 1] + R[k + 1] + R[k - _nx] + R[k + _nx] - 4f * R[k]) + _c[k] * R[k];
                _b[k] -= (float)dt * hr;
            }
        _time = 0;
        SetupAbsorber();
        Upload();
    }

    private void SetupAbsorber()
    {
        int w = Math.Max(4, _nx / 14);
        for (int j = 0; j < _ny; j++)
            for (int i = 0; i < _nx; i++)
            {
                int d = Math.Min(Math.Min(i, _nx - 1 - i), Math.Min(j, _ny - 1 - j));
                double s = d < w ? Math.Pow((double)(w - d) / w, 2) : 0.0;
                _q[Idx(i, j)] = (float)(s * 6.0);
            }
    }

    /// <summary>Potenciales predefinidos: libre, barrera, doble_rendija, pozo, armonico.</summary>
    public void SetPotential(string name, double height, double width)
    {
        double L = Length;
        for (int j = 0; j < _ny; j++)
            for (int i = 0; i < _nx; i++)
            {
                double x = ((double)i / (_nx - 1) - 0.5) * L, y = ((double)j / (_ny - 1) - 0.5) * L;
                double v = 0;
                switch (name)
                {
                    case "barrera":
                        if (Math.Abs(x) < width * 0.5) v = height;
                        break;
                    case "doble_rendija":
                        if (Math.Abs(x) < width * 0.5)
                        {
                            double sep = L * 0.1, sw = L * 0.035;
                            bool slit = Math.Abs(y - sep) < sw * 0.5 || Math.Abs(y + sep) < sw * 0.5;
                            v = slit ? 0 : height;
                        }
                        break;
                    case "pozo":
                        v = (Math.Abs(x) < L * 0.25 && Math.Abs(y) < L * 0.25) ? 0 : height;
                        break;
                    case "armonico":
                        double w0 = width;                     // ω
                        v = Math.Min(0.5 * w0 * w0 * (x * x + y * y), height * 4);
                        break;
                }
                _c[Idx(i, j)] = (float)v;
            }
        Upload();
    }

    public double Norm()
    {
        double s = 0;
        for (int k = 0; k < _a.Length; k++) s += _a[k] * _a[k] + _b[k] * _b[k];
        return s * H * H;
    }

    /// <summary>Probabilidad en la región u > uCut (transmisión a través de una barrera).</summary>
    public double ProbabilityBeyond(double uCut)
    {
        double s = 0;
        int ic = (int)Math.Round(uCut * (_nx - 1));
        for (int j = 0; j < _ny; j++)
            for (int i = ic; i < _nx; i++)
            {
                int k = Idx(i, j);
                s += _a[k] * _a[k] + _b[k] * _b[k];
            }
        return s * H * H;
    }

    public Vector2 ExpectedPosition()
    {
        double sx = 0, sy = 0, st = 0, L = Length;
        for (int j = 0; j < _ny; j++)
            for (int i = 0; i < _nx; i++)
            {
                int k = Idx(i, j);
                double p = _a[k] * _a[k] + _b[k] * _b[k];
                sx += p * ((double)i / (_nx - 1) - 0.5) * L;
                sy += p * ((double)j / (_ny - 1) - 0.5) * L;
                st += p;
            }
        return st > 0 ? new Vector2((float)(sx / st), (float)(sy / st)) : Vector2.Zero;
    }

    // --------------------------------------------------------------- consultas
    /// <summary>Valores (R, G, B, A) de la textura en (u, v) con interpolación bilineal.</summary>
    public Vector4 Sample(double u, double v)
    {
        double x = Math.Clamp(u, 0, 1) * (_nx - 1), y = Math.Clamp(v, 0, 1) * (_ny - 1);
        int i0 = Math.Min((int)x, _nx - 2), j0 = Math.Min((int)y, _ny - 2);
        double fx = x - i0, fy = y - j0;
        Vector4 Get(int i, int j)
        {
            int k = Idx(i, j) * 4;
            return new Vector4(_rgba[k], _rgba[k + 1], _rgba[k + 2], _rgba[k + 3]);
        }
        var a = Get(i0, j0).Lerp(Get(i0 + 1, j0), (float)fx);
        var b = Get(i0, j0 + 1).Lerp(Get(i0 + 1, j0 + 1), (float)fx);
        return a.Lerp(b, (float)fy);
    }

    /// <summary>Energía de la membrana (cinética + potencial elástica), en unidades relativas.</summary>
    public double Energy()
    {
        if (_kind != "onda") return 0;
        double h = H, e = 0;
        for (int j = 1; j < _ny - 1; j++)
            for (int i = 1; i < _nx - 1; i++)
            {
                int k = Idx(i, j);
                double ut = (_a[k] - _b[k]);
                double ux = (_a[k + 1] - _a[k - 1]) * 0.5, uy = (_a[k + _nx] - _a[k - _nx]) * 0.5;
                e += ut * ut / (0.25 * h * h / Math.Max(1e-9, C * C)) + C * C * (ux * ux + uy * uy) / (h * h);
            }
        return 0.5 * e * h * h;
    }

    public double MaxValue()
    {
        float m = float.MinValue;
        foreach (var x in _a) m = Math.Max(m, x);
        return m;
    }

    public double MinValue()
    {
        float m = float.MaxValue;
        foreach (var x in _a) m = Math.Min(m, x);
        return m;
    }

    /// <summary>Temperatura/valor en (u, v) del campo principal (sin pasar por la textura).</summary>
    public double ValueAt(double u, double v)
    {
        int i = (int)Math.Round(Math.Clamp(u, 0, 1) * (_nx - 1)), j = (int)Math.Round(Math.Clamp(v, 0, 1) * (_ny - 1));
        int k = Idx(i, j);
        return _kind == "schrodinger" ? _a[k] * _a[k] + _b[k] * _b[k] : _a[k];
    }

    public double AlphaAt(double u, double v)
    {
        int i = (int)Math.Round(Math.Clamp(u, 0, 1) * (_nx - 1)), j = (int)Math.Round(Math.Clamp(v, 0, 1) * (_ny - 1));
        return _c[Idx(i, j)];
    }
}
