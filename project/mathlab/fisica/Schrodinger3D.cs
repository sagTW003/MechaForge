using System;
using System.Threading.Tasks;
using Godot;

namespace MechaForge;

/// <summary>
/// Schrodinger3D — Ecuación de Schrödinger dependiente del tiempo en 3D, en unidades atómicas
/// (ħ = mₑ = 1):  i ∂ψ/∂t = −½∇²ψ + Vψ, en una caja de lado L con ψ = 0 en las paredes (rebota).
/// Esquema de Visscher (Computers in Physics 5, 596 (1991)): ψ = R + iI con R en t e I en t + Δt/2,
///   R(t + Δt) = R(t) + Δt·H·I(t + Δt/2),   I(t + 3Δt/2) = I(t + Δt/2) − Δt·H·R(t + Δt);
/// estable si Δt ≤ 2/E_máx (E_máx = 6/h² + V_máx con el laplaciano de 7 puntos) y conserva exacta
/// P = Σ [R(t)² + I(t + Δt/2)·I(t − Δt/2)]·h³. Error de discretización O(h²): un paquete de número
/// de onda k avanza a sin(kh)/h en lugar de k.
/// Superposición: los estados se suman antes de normalizar. Medición de posición con resolución σ
/// (proyección gaussiana ψ → e^{−|r − r₀|²/(4σ²)}ψ, con r₀ sacado de |ψ|²: regla de Born) o de en
/// qué lado de un plano está la partícula (ψ se queda solo en la mitad que salió).
/// Como FieldSim, el estado vive en el objeto: el módulo lo crea con load(...).new().
/// </summary>
[GlobalClass]
public partial class Schrodinger3D : RefCounted
{
    int _n = 8;
    double _l = 20.0, _h = 1.0, _dt = 0.01, _t, _seguridad = 0.8, _vmax;
    double[] _re = new double[512], _im = new double[512], _imAnt = new double[512], _v = new double[512], _tmp = new double[512];

    public int N => _n;
    public double Lado => _l;
    public double Dt => _dt;
    public double Tiempo => _t;

    public void Setup(int n, double lado)
    {
        _n = Math.Max(8, n);
        _l = lado;
        _h = lado / (_n - 1);
        int m = _n * _n * _n;
        _re = new double[m]; _im = new double[m]; _imAnt = new double[m]; _v = new double[m]; _tmp = new double[m];
        _t = 0;
    }

    double X(int i) => -0.5 * _l + i * _h;
    int Idx(int i, int j, int k) => (k * _n + j) * _n + i;

    public void Limpiar()
    {
        Array.Clear(_re); Array.Clear(_im); Array.Clear(_imAnt);
        _t = 0;
    }

    /// <summary>Suma c·e^{−|r − r₀|²/(4σ²)}·e^{ik·r} (σ: desviación típica de |ψ|² en cada eje).</summary>
    public void AgregarPaquete(double x0, double y0, double z0, double kx, double ky, double kz, double sigma, double cRe, double cIm)
    {
        double a = 1.0 / (4 * sigma * sigma);
        Parallel.For(0, _n, k =>
        {
            for (int j = 0; j < _n; j++)
                for (int i = 0; i < _n; i++)
                {
                    double dx = X(i) - x0, dy = X(j) - y0, dz = X(k) - z0;
                    double env = Math.Exp(-a * (dx * dx + dy * dy + dz * dz));
                    double ph = kx * X(i) + ky * X(j) + kz * X(k);
                    double cr = env * Math.Cos(ph), ci = env * Math.Sin(ph);
                    int c = Idx(i, j, k);
                    _re[c] += cRe * cr - cIm * ci;
                    _im[c] += cRe * ci + cIm * cr;
                }
        });
    }

    /// <summary>Suma c·φ_{nx}(x)φ_{ny}(y)φ_{nz}(z), estado propio del oscilador isótropo de frecuencia ω (n ≤ 2).</summary>
    public void AgregarOscilador(int nx, int ny, int nz, double omega, double cRe, double cIm)
    {
        double Phi(int n, double x)
        {
            double u = Math.Sqrt(omega) * x;
            double hn = n switch { 0 => 1.0, 1 => 2 * u, _ => 4 * u * u - 2 };
            double fact = n switch { 0 => 1.0, 1 => 1.0, _ => 2.0 };
            return Math.Pow(omega / Math.PI, 0.25) / Math.Sqrt(Math.Pow(2, n) * fact) * hn * Math.Exp(-0.5 * u * u);
        }
        Parallel.For(0, _n, k =>
        {
            for (int j = 0; j < _n; j++)
                for (int i = 0; i < _n; i++)
                {
                    double f = Phi(nx, X(i)) * Phi(ny, X(j)) * Phi(nz, X(k));
                    int c = Idx(i, j, k);
                    _re[c] += cRe * f;
                    _im[c] += cIm * f;
                }
        });
    }

    /// <summary>
    /// Potencial: «libre», «armonico» (½ω²r²), «barrera» (placa |x| &lt; ancho/2 de altura «alto») o
    /// «doble_rendija» (esa placa con dos rendijas en y separadas L/5, de ancho L/14, a lo largo de z).
    /// </summary>
    public void SetPotencial(string nombre, double alto, double ancho, double omega)
    {
        double sep = _l * 0.2, rendija = _l / 14.0;
        _vmax = 0;
        for (int k = 0; k < _n; k++)
            for (int j = 0; j < _n; j++)
                for (int i = 0; i < _n; i++)
                {
                    double x = X(i), y = X(j), z = X(k), v = 0;
                    switch (nombre)
                    {
                        case "armonico": v = 0.5 * omega * omega * (x * x + y * y + z * z); break;
                        case "barrera": v = Math.Abs(x) < 0.5 * ancho ? alto : 0; break;
                        case "doble_rendija":
                            bool abierta = Math.Abs(y - 0.5 * sep) < 0.5 * rendija || Math.Abs(y + 0.5 * sep) < 0.5 * rendija;
                            v = Math.Abs(x) < 0.5 * ancho && !abierta ? alto : 0;
                            break;
                    }
                    _v[Idx(i, j, k)] = v;
                    _vmax = Math.Max(_vmax, v);
                }
    }

    public void Normalizar()
    {
        double s = 0;
        for (int c = 0; c < _re.Length; c++) s += _re[c] * _re[c] + _im[c] * _im[c];
        double f = s > 0 ? 1.0 / Math.Sqrt(s * _h * _h * _h) : 0;
        for (int c = 0; c < _re.Length; c++) { _re[c] *= f; _im[c] *= f; }
    }

    /// <summary>
    /// Arranca el salto de rana desde ψ(t) = R + iI: ψ = 0 en las paredes, Δt = seguridad·2/E_máx,
    /// I pasa a t + Δt/2 y se guarda I(t − Δt/2) para la norma de Visscher.
    /// </summary>
    public void Iniciar(double seguridad)
    {
        _seguridad = seguridad;
        _dt = seguridad * 2.0 / (6.0 / (_h * _h) + _vmax);
        for (int k = 0; k < _n; k++)
            for (int j = 0; j < _n; j++)
                for (int i = 0; i < _n; i++)
                    if (i == 0 || j == 0 || k == 0 || i == _n - 1 || j == _n - 1 || k == _n - 1)
                    {
                        int c = Idx(i, j, k);
                        _re[c] = 0; _im[c] = 0;
                    }
        AplicarH(_re, _tmp);
        for (int c = 0; c < _re.Length; c++)
        {
            _imAnt[c] = _im[c] + 0.5 * _dt * _tmp[c];
            _im[c] -= 0.5 * _dt * _tmp[c];
        }
        // La norma de Visscher difiere O(Δt²) de Σ(R² + I²): se normaliza la que se conserva.
        double f = 1.0 / Math.Sqrt(Math.Max(Norma(), 1e-300));
        for (int c = 0; c < _re.Length; c++) { _re[c] *= f; _im[c] *= f; _imAnt[c] *= f; }
    }

    /// <summary>d = H·s en los puntos interiores (las paredes quedan en 0).</summary>
    void AplicarH(double[] s, double[] d)
    {
        int n = _n, n2 = n * n;
        double kin = -0.5 / (_h * _h);
        Parallel.For(1, n - 1, k =>
        {
            for (int j = 1; j < n - 1; j++)
            {
                int c = (k * n + j) * n + 1;
                for (int i = 1; i < n - 1; i++, c++)
                    d[c] = kin * (s[c - 1] + s[c + 1] + s[c - n] + s[c + n] + s[c - n2] + s[c + n2] - 6.0 * s[c]) + _v[c] * s[c];
            }
        });
    }

    public void Paso(int pasos)
    {
        for (int p = 0; p < pasos; p++)
        {
            AplicarH(_im, _tmp);
            for (int c = 0; c < _re.Length; c++) _re[c] += _dt * _tmp[c];
            Array.Copy(_im, _imAnt, _im.Length);
            AplicarH(_re, _tmp);
            for (int c = 0; c < _im.Length; c++) _im[c] -= _dt * _tmp[c];
            _t += _dt;
        }
    }

    /// <summary>Densidad en t con la definición de Visscher (la que se conserva).</summary>
    double Rho(int c) => _re[c] * _re[c] + _im[c] * _imAnt[c];

    public double Norma()
    {
        double s = 0;
        for (int c = 0; c < _re.Length; c++) s += Rho(c);
        return s * _h * _h * _h;
    }

    /// <summary>[⟨x⟩, ⟨y⟩, ⟨z⟩, Δx, Δy, Δz].</summary>
    public double[] Esperado()
    {
        double s = 0, sx = 0, sy = 0, sz = 0, sxx = 0, syy = 0, szz = 0;
        for (int k = 0; k < _n; k++)
            for (int j = 0; j < _n; j++)
                for (int i = 0; i < _n; i++)
                {
                    double p = Rho(Idx(i, j, k)), x = X(i), y = X(j), z = X(k);
                    s += p; sx += p * x; sy += p * y; sz += p * z; sxx += p * x * x; syy += p * y * y; szz += p * z * z;
                }
        if (s <= 0) return new double[6];
        double mx = sx / s, my = sy / s, mz = sz / s;
        return new[] { mx, my, mz, Math.Sqrt(Math.Max(0, sxx / s - mx * mx)), Math.Sqrt(Math.Max(0, syy / s - my * my)), Math.Sqrt(Math.Max(0, szz / s - mz * mz)) };
    }

    /// <summary>⟨H⟩ = ⟨R|H|R⟩ + ⟨I|H|I⟩ (en tiempos desfasados medio paso: error O(Δt)).</summary>
    public double Energia()
    {
        AplicarH(_re, _tmp);
        double e = 0;
        for (int c = 0; c < _re.Length; c++) e += _re[c] * _tmp[c];
        AplicarH(_im, _tmp);
        for (int c = 0; c < _im.Length; c++) e += _im[c] * _tmp[c];
        return e * _h * _h * _h / Math.Max(Norma(), 1e-300);
    }

    /// <summary>Probabilidad de que la coordenada «eje» (0 x, 1 y, 2 z) sea mayor que «corte».</summary>
    public double ProbabilidadMas(int eje, double corte)
    {
        double s = 0;
        for (int k = 0; k < _n; k++)
            for (int j = 0; j < _n; j++)
                for (int i = 0; i < _n; i++)
                    if (X(eje == 0 ? i : eje == 1 ? j : k) > corte)
                        s += Rho(Idx(i, j, k));
        return s * _h * _h * _h / Math.Max(Norma(), 1e-300);
    }

    /// <summary>Posiciones sacadas de |ψ|² (regla de Born) con los números uniformes «u» dados, sin medir: [x, y, z]…</summary>
    public double[] Muestrear(double[] u)
    {
        var acum = new double[_re.Length];
        double s = 0;
        for (int c = 0; c < acum.Length; c++) { s += Math.Max(0, Rho(c)); acum[c] = s; }
        var o = new double[3 * u.Length];
        for (int m = 0; m < u.Length; m++)
        {
            int c = Array.BinarySearch(acum, u[m] * s);
            if (c < 0) c = ~c;
            c = Math.Min(c, acum.Length - 1);
            o[3 * m] = X(c % _n); o[3 * m + 1] = X(c / _n % _n); o[3 * m + 2] = X(c / (_n * _n));
        }
        return o;
    }

    /// <summary>Mide la posición con resolución σ: saca r₀ de |ψ|², proyecta y vuelve a normalizar. Devuelve r₀.</summary>
    public double[] MedirPosicion(double u, double sigma)
    {
        var r = Muestrear(new[] { u });
        double a = 1.0 / (4 * sigma * sigma);
        Colapsar(c =>
        {
            int i = c % _n, j = c / _n % _n, k = c / (_n * _n);
            double dx = X(i) - r[0], dy = X(j) - r[1], dz = X(k) - r[2];
            return Math.Exp(-a * (dx * dx + dy * dy + dz * dz));
        });
        return r;
    }

    /// <summary>Mide si la coordenada «eje» es positiva (+1) o negativa (−1); ψ queda en esa mitad. Devuelve [resultado, P(+)].</summary>
    public double[] MedirLado(int eje, double u)
    {
        double p = ProbabilidadMas(eje, 0.0);
        double res = u < p ? 1.0 : -1.0;
        Colapsar(c =>
        {
            int i = c % _n, j = c / _n % _n, k = c / (_n * _n);
            return X(eje == 0 ? i : eje == 1 ? j : k) * res > 0 ? 1.0 : 0.0;
        });
        return new[] { res, p };
    }

    /// <summary>ψ(t) → f·ψ(t) normalizada; con I(t) ≈ [I(t + Δt/2) + I(t − Δt/2)]/2 se vuelve a arrancar el salto de rana.</summary>
    void Colapsar(Func<int, double> f)
    {
        for (int c = 0; c < _re.Length; c++)
        {
            double g = f(c);
            _re[c] *= g;
            _im[c] = 0.5 * (_im[c] + _imAnt[c]) * g;
        }
        Normalizar();
        Iniciar(_seguridad);
    }

    /// <summary>Volumen para el shader, RGBA8 por celda: R = √(ρ/ρ_máx), G y B = cos y sin de arg ψ en [0, 255], A = V/V_máx.</summary>
    public byte[] Volumen()
    {
        double max = 1e-300;
        for (int c = 0; c < _re.Length; c++) max = Math.Max(max, _re[c] * _re[c] + _im[c] * _im[c]);
        var o = new byte[4 * _re.Length];
        Parallel.For(0, _n, k =>
        {
            for (int c = k * _n * _n; c < (k + 1) * _n * _n; c++)
            {
                double rho = _re[c] * _re[c] + _im[c] * _im[c];
                double fase = Math.Atan2(_im[c], _re[c]);
                o[4 * c] = (byte)Math.Round(255 * Math.Sqrt(rho / max));
                o[4 * c + 1] = (byte)Math.Round(127.5 + 127.5 * Math.Cos(fase));
                o[4 * c + 2] = (byte)Math.Round(127.5 + 127.5 * Math.Sin(fase));
                o[4 * c + 3] = (byte)Math.Round(_vmax > 0 ? 255 * _v[c] / _vmax : 0);
            }
        });
        return o;
    }

    /// <summary>[|ψ|², arg ψ, V] en el punto de la rejilla más cercano a (x, y, z).</summary>
    public double[] ValorEn(double x, double y, double z)
    {
        int I(double v) => Math.Clamp((int)Math.Round((v + 0.5 * _l) / _h), 0, _n - 1);
        int c = Idx(I(x), I(y), I(z));
        return new[] { _re[c] * _re[c] + _im[c] * _im[c], Math.Atan2(_im[c], _re[c]), _v[c] };
    }

    /// <summary>
    /// false si hay NaN/∞ o ψ se dispara (inestable). Con Σ(R² + I²), siempre positiva: en un modo
    /// inestable el producto I(t + Δt/2)·I(t − Δt/2) de la norma de Visscher se vuelve muy negativo.
    /// </summary>
    public bool Finito()
    {
        double s = 0;
        for (int c = 0; c < _re.Length; c++) s += _re[c] * _re[c] + _im[c] * _im[c];
        s *= _h * _h * _h;
        return double.IsFinite(s) && s < 1.5;
    }
}
