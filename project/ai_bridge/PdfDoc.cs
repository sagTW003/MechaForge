using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using Godot;

namespace MechaForge;

/// <summary>
/// PdfDoc — Lectura de PDF para los adjuntos del chat de OpenClaw.
///
/// Usa PDFium (el motor de PDF de Chromium; binarios de bblanchon.PDFium.Win32 desde
/// nuget.org) para extraer el texto de cada página y renderizarla como imagen. Así un
/// agente con visión puede «ver» las páginas (fórmulas, figuras, escaneos) y uno solo
/// de texto recibe el texto extraído.
///
/// Uso desde GDScript:
///   var pdf = load("res://ai_bridge/PdfDoc.cs").new()
///   if pdf.Open(bytes, ""): pdf.PageCount, pdf.PageText(0), pdf.RenderPage(0, 1600)
///   pdf.Close()
/// Todo ocurre en el hilo principal (PDFium no es seguro entre hilos).
/// </summary>
[GlobalClass]
public partial class PdfDoc : RefCounted
{
    private const string Lib = "pdfium";
    private const int FpdfAnnot = 0x01;

    [DllImport(Lib)] private static extern void FPDF_InitLibrary();
    [DllImport(Lib, CharSet = CharSet.Ansi)] private static extern IntPtr FPDF_LoadMemDocument(IntPtr data, int size, string? password);
    [DllImport(Lib)] private static extern uint FPDF_GetLastError();
    [DllImport(Lib)] private static extern int FPDF_GetPageCount(IntPtr doc);
    [DllImport(Lib)] private static extern IntPtr FPDF_LoadPage(IntPtr doc, int index);
    [DllImport(Lib)] private static extern float FPDF_GetPageWidthF(IntPtr page);
    [DllImport(Lib)] private static extern float FPDF_GetPageHeightF(IntPtr page);
    [DllImport(Lib)] private static extern void FPDF_ClosePage(IntPtr page);
    [DllImport(Lib)] private static extern void FPDF_CloseDocument(IntPtr doc);
    [DllImport(Lib)] private static extern IntPtr FPDFText_LoadPage(IntPtr page);
    [DllImport(Lib)] private static extern void FPDFText_ClosePage(IntPtr textPage);
    [DllImport(Lib)] private static extern int FPDFText_CountChars(IntPtr textPage);
    [DllImport(Lib)] private static extern int FPDFText_GetText(IntPtr textPage, int start, int count, [Out] ushort[] buffer);
    [DllImport(Lib)] private static extern IntPtr FPDFBitmap_Create(int width, int height, int alpha);
    [DllImport(Lib)] private static extern int FPDFBitmap_FillRect(IntPtr bitmap, int left, int top, int width, int height, uint color);
    [DllImport(Lib)] private static extern IntPtr FPDFBitmap_GetBuffer(IntPtr bitmap);
    [DllImport(Lib)] private static extern int FPDFBitmap_GetStride(IntPtr bitmap);
    [DllImport(Lib)] private static extern void FPDFBitmap_Destroy(IntPtr bitmap);
    [DllImport(Lib)] private static extern void FPDF_RenderPageBitmap(IntPtr bitmap, IntPtr page, int x, int y, int w, int h, int rotate, int flags);

    private static bool _initialized;
    private static bool _resolverSet;
    private static readonly object _lock = new();

    private IntPtr _doc = IntPtr.Zero;
    private IntPtr _data = IntPtr.Zero;

    /// <summary>Motivo del último fallo, en español (vacío si todo fue bien).</summary>
    public string Error { get; private set; } = "";

    public int PageCount { get; private set; }

    public bool IsOpen => _doc != IntPtr.Zero;

    /// <summary>¿Se puede cargar PDFium en este equipo?</summary>
    public bool IsAvailable()
    {
        try
        {
            EnsureInit();
            return true;
        }
        catch (Exception e)
        {
            Error = "No se pudo cargar PDFium: " + e.Message;
            return false;
        }
    }

    /// <summary>Busca pdfium.dll junto al ensamblado, en runtimes/&lt;rid&gt;/native (compilación del
    /// editor) y junto al ejecutable (exportación), por si la resolución por defecto falla.</summary>
    private static void SetResolver()
    {
        if (_resolverSet)
            return;
        _resolverSet = true;
        try
        {
            NativeLibrary.SetDllImportResolver(typeof(PdfDoc).Assembly, (name, asm, path) =>
            {
                if (name != Lib)
                    return IntPtr.Zero;
                if (NativeLibrary.TryLoad(name, asm, path, out var h))
                    return h;
                string file = OperatingSystem.IsWindows() ? "pdfium.dll" : OperatingSystem.IsMacOS() ? "libpdfium.dylib" : "libpdfium.so";
                string arch = RuntimeInformation.ProcessArchitecture switch
                {
                    Architecture.Arm64 => "arm64",
                    Architecture.X86 => "x86",
                    _ => "x64",
                };
                string os = OperatingSystem.IsWindows() ? "win" : OperatingSystem.IsMacOS() ? "osx" : "linux";
                string asmDir = Path.GetDirectoryName(asm.Location) ?? "";
                string exeDir = Path.GetDirectoryName(OS.GetExecutablePath()) ?? "";
                foreach (var dir in new[] { asmDir, Path.Combine(asmDir, "runtimes", $"{os}-{arch}", "native"), exeDir })
                {
                    string p = Path.Combine(dir, file);
                    if (dir != "" && File.Exists(p) && NativeLibrary.TryLoad(p, out h))
                        return h;
                }
                return IntPtr.Zero;
            });
        }
        catch (InvalidOperationException)
        {
            // Ya había un resolvedor para este ensamblado.
        }
    }

    private static void EnsureInit()
    {
        lock (_lock)
        {
            if (_initialized)
                return;
            SetResolver();
            FPDF_InitLibrary();
            _initialized = true;
        }
    }

    /// <summary>Abre un PDF desde memoria. Devuelve false (y rellena Error) si no se puede.
    /// (GDScript no admite parámetros opcionales de C#: sin contraseña, password = "".)</summary>
    public bool Open(byte[] data, string password)
    {
        Close();
        Error = "";
        if (data == null || data.Length < 8)
        {
            Error = "El archivo está vacío.";
            return false;
        }
        try
        {
            EnsureInit();
        }
        catch (Exception e)
        {
            Error = "No se pudo cargar PDFium: " + e.Message;
            return false;
        }
        // PDFium lee del búfer mientras el documento esté abierto: copia fija fuera del GC.
        _data = Marshal.AllocHGlobal(data.Length);
        Marshal.Copy(data, 0, _data, data.Length);
        _doc = FPDF_LoadMemDocument(_data, data.Length, password == "" ? null : password);
        if (_doc == IntPtr.Zero)
        {
            Error = FPDF_GetLastError() switch
            {
                3 => "No es un PDF válido o está dañado.",
                4 => "El PDF está protegido con contraseña.",
                5 => "El PDF usa una protección no admitida.",
                _ => "No se pudo abrir el PDF.",
            };
            Marshal.FreeHGlobal(_data);
            _data = IntPtr.Zero;
            return false;
        }
        PageCount = Math.Max(0, FPDF_GetPageCount(_doc));
        return true;
    }

    /// <summary>Texto de la página (índice desde 0), tal como lo extrae PDFium.</summary>
    public string PageText(int index)
    {
        if (!IsOpen || index < 0 || index >= PageCount)
            return "";
        IntPtr page = FPDF_LoadPage(_doc, index);
        if (page == IntPtr.Zero)
            return "";
        IntPtr tp = FPDFText_LoadPage(page);
        string text = "";
        if (tp != IntPtr.Zero)
        {
            int n = FPDFText_CountChars(tp);
            if (n > 0)
            {
                var buf = new ushort[n + 1];
                int written = FPDFText_GetText(tp, 0, n, buf);
                var chars = new char[Math.Max(0, written - 1)];
                for (int i = 0; i < chars.Length; i++)
                    chars[i] = (char)buf[i];
                text = new string(chars).Replace("\r\n", "\n").Replace('\r', '\n');
            }
            FPDFText_ClosePage(tp);
        }
        FPDF_ClosePage(page);
        return text;
    }

    /// <summary>Tamaño de la página en puntos (1/72 pulgada).</summary>
    public Vector2 PageSize(int index)
    {
        if (!IsOpen || index < 0 || index >= PageCount)
            return Vector2.Zero;
        IntPtr page = FPDF_LoadPage(_doc, index);
        if (page == IntPtr.Zero)
            return Vector2.Zero;
        var s = new Vector2(FPDF_GetPageWidthF(page), FPDF_GetPageHeightF(page));
        FPDF_ClosePage(page);
        return s;
    }

    /// <summary>Renderiza la página sobre fondo blanco con su lado mayor de maxSide píxeles.</summary>
    public Image? RenderPage(int index, int maxSide)
    {
        if (!IsOpen || index < 0 || index >= PageCount)
            return null;
        IntPtr page = FPDF_LoadPage(_doc, index);
        if (page == IntPtr.Zero)
            return null;
        float pw = FPDF_GetPageWidthF(page), ph = FPDF_GetPageHeightF(page);
        if (pw <= 0 || ph <= 0)
        {
            FPDF_ClosePage(page);
            return null;
        }
        float k = Math.Clamp(maxSide, 64, 4096) / Math.Max(pw, ph);
        int w = Math.Max(1, (int)Math.Round(pw * k)), h = Math.Max(1, (int)Math.Round(ph * k));
        IntPtr bmp = FPDFBitmap_Create(w, h, 0);
        if (bmp == IntPtr.Zero)
        {
            FPDF_ClosePage(page);
            return null;
        }
        FPDFBitmap_FillRect(bmp, 0, 0, w, h, 0xFFFFFFFF);
        FPDF_RenderPageBitmap(bmp, page, 0, 0, w, h, 0, FpdfAnnot);
        IntPtr buf = FPDFBitmap_GetBuffer(bmp);
        int stride = FPDFBitmap_GetStride(bmp);
        var row = new byte[stride];
        var rgb = new byte[w * h * 3];
        // PDFium entrega BGRx por filas; Godot quiere RGB8 contiguo.
        for (int y = 0; y < h; y++)
        {
            Marshal.Copy(buf + y * stride, row, 0, stride);
            int o = y * w * 3;
            for (int x = 0; x < w; x++)
            {
                rgb[o + x * 3] = row[x * 4 + 2];
                rgb[o + x * 3 + 1] = row[x * 4 + 1];
                rgb[o + x * 3 + 2] = row[x * 4];
            }
        }
        FPDFBitmap_Destroy(bmp);
        FPDF_ClosePage(page);
        return Image.CreateFromData(w, h, false, Image.Format.Rgb8, rgb);
    }

    public void Close()
    {
        if (_doc != IntPtr.Zero)
        {
            FPDF_CloseDocument(_doc);
            _doc = IntPtr.Zero;
        }
        if (_data != IntPtr.Zero)
        {
            Marshal.FreeHGlobal(_data);
            _data = IntPtr.Zero;
        }
        PageCount = 0;
    }

    protected override void Dispose(bool disposing)
    {
        Close();
        base.Dispose(disposing);
    }
}
