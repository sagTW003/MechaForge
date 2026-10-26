using System;
using Godot;

namespace MechaForge;

/// <summary>
/// PidController — Controlador PID discreto con anti-windup y límites de salida.
///
/// u = Kp·e + Ki·∫e·dt + Kd·de/dt,  con e = consigna − medición.
/// Anti-windup por abrazadera: el integral no crece si la salida está saturada
/// y el error empuja aún más hacia la saturación.
///
/// Clase normal de C# (no es un objeto de Godot): GDScript la usa a través del
/// autoload Electronics, y así no hay que liberarla a mano.
/// </summary>
public class PidController
{
    public double Kp = 1.0;
    public double Ki = 0.0;
    public double Kd = 0.0;
    public double OutMin = -1e12;
    public double OutMax = 1e12;
    public double Setpoint = 0.0;

    private double _integral;
    private double _prevError;
    private bool _hasPrev;

    public double LastError { get; private set; }
    public double LastOutput { get; private set; }
    public double Integral => _integral;

    public void Configure(double kp, double ki, double kd)
    {
        Kp = kp; Ki = ki; Kd = kd;
    }

    public void SetLimits(double min, double max)
    {
        OutMin = min; OutMax = max;
    }

    public void Reset()
    {
        _integral = 0; _prevError = 0; _hasPrev = false;
        LastError = 0; LastOutput = 0;
    }

    /// <summary>Un paso del PID. dt en segundos. Devuelve la salida acotada.</summary>
    public double Update(double measurement, double dt)
    {
        if (dt <= 0) return LastOutput;
        double error = Setpoint - measurement;
        double deriv = _hasPrev ? (error - _prevError) / dt : 0.0;

        double integralCandidate = _integral + error * dt;
        double output = Kp * error + Ki * integralCandidate + Kd * deriv;

        double clamped = Math.Clamp(output, OutMin, OutMax);
        bool saturated = output != clamped;
        if (!saturated || Math.Sign(error) != Math.Sign(output))
            _integral = integralCandidate;
        else
            output = Kp * error + Ki * _integral + Kd * deriv;

        _prevError = error; _hasPrev = true;
        LastError = error;
        LastOutput = Math.Clamp(output, OutMin, OutMax);
        return LastOutput;
    }
}
