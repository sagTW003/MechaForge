using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Runtime.Versioning;
using Godot;

namespace MechaForge;

/// <summary>
/// CameraList — Nombres de las cámaras de vídeo del equipo para elegir con cuál se
/// hace el seguimiento de manos.
///
/// En Windows enumera los dispositivos de captura de DirectShow: es el mismo orden de
/// índices que usa OpenCV con CAP_DSHOW en mf_hands.py (índice 0 = primera de la lista).
/// Solo lee sus nombres del registro de dispositivos: no abre ninguna cámara ni
/// enciende su luz. En otros sistemas devuelve una lista vacía.
///
/// Uso desde GDScript: load("res://handtracking/CameraList.cs").new().Names()
/// </summary>
[GlobalClass]
public partial class CameraList : RefCounted
{
    private static readonly Guid ClsidSystemDeviceEnum = new("62BE5D10-60EB-11d0-BD3B-00A0C911CE86");
    private static readonly Guid ClsidVideoInputDeviceCategory = new("860BB310-5D01-11d0-BD3B-00A0C911CE86");

    /// <summary>Motivo si la enumeración falló (vacío si fue bien).</summary>
    public string Error { get; private set; } = "";

    public string[] Names()
    {
        Error = "";
        var names = new List<string>();
        if (!OperatingSystem.IsWindows())
            return names.ToArray();
        object? devEnumObj = null;
        IEnumMoniker? enumMon = null;
        try
        {
            var t = Type.GetTypeFromCLSID(ClsidSystemDeviceEnum);
            if (t == null)
                return names.ToArray();
            devEnumObj = Activator.CreateInstance(t);
            if (devEnumObj is not ICreateDevEnum devEnum)
                return names.ToArray();
            var category = ClsidVideoInputDeviceCategory;
            // S_FALSE (1) y enumerador nulo = no hay ninguna cámara.
            if (devEnum.CreateClassEnumerator(ref category, out enumMon, 0) != 0 || enumMon == null)
                return names.ToArray();
            var monikers = new IMoniker[1];
            while (enumMon.Next(1, monikers, IntPtr.Zero) == 0)
            {
                names.Add(FriendlyName(monikers[0], names.Count));
                Marshal.ReleaseComObject(monikers[0]);
            }
        }
        catch (Exception e)
        {
            Error = e.Message;
        }
        finally
        {
            if (enumMon != null)
                Marshal.ReleaseComObject(enumMon);
            if (devEnumObj != null && Marshal.IsComObject(devEnumObj))
                Marshal.ReleaseComObject(devEnumObj);
        }
        return names.ToArray();
    }

    [SupportedOSPlatform("windows")]
    private static string FriendlyName(IMoniker moniker, int index)
    {
        string name = "";
        try
        {
            Guid iid = typeof(IPropertyBag).GUID;
            moniker.BindToStorage(null!, null, ref iid, out object bagObj);
            if (bagObj is IPropertyBag bag)
            {
                object? value = null;
                if (bag.Read("FriendlyName", ref value, IntPtr.Zero) == 0)
                    name = (value as string ?? "").Trim();
                Marshal.ReleaseComObject(bag);
            }
        }
        catch (Exception)
        {
            // Sin nombre legible: se identifica por su posición.
        }
        return name != "" ? name : $"Cámara {index}";
    }

    [ComImport, Guid("29840822-5B84-11D0-BD3B-00A0C911CE86"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface ICreateDevEnum
    {
        [PreserveSig]
        int CreateClassEnumerator([In] ref Guid clsidDeviceClass, out IEnumMoniker? enumMoniker, int flags);
    }

    [ComImport, Guid("55272A00-42CB-11CE-8135-00AA004BB851"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IPropertyBag
    {
        [PreserveSig]
        int Read([MarshalAs(UnmanagedType.LPWStr)] string propName, [In, Out, MarshalAs(UnmanagedType.Struct)] ref object? value, IntPtr errorLog);

        [PreserveSig]
        int Write([MarshalAs(UnmanagedType.LPWStr)] string propName, [In, MarshalAs(UnmanagedType.Struct)] ref object value);
    }
}
