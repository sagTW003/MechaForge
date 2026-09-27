using System;
using System.Runtime.InteropServices;
using Godot;

namespace MechaForge;

/// <summary>
/// SystemMedia — Control de música del sistema (autoload).
///
/// Envía las teclas multimedia de Windows (play/pausa, siguiente, anterior,
/// volumen), que controlan el reproductor activo del sistema —incluido
/// **Spotify**— sin necesidad de credenciales ni OAuth. Solo Windows.
/// </summary>
public partial class SystemMedia : Node
{
    [DllImport("user32.dll")]
    private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const byte VK_MEDIA_NEXT = 0xB0;
    private const byte VK_MEDIA_PREV = 0xB1;
    private const byte VK_MEDIA_STOP = 0xB2;
    private const byte VK_MEDIA_PLAY_PAUSE = 0xB3;
    private const byte VK_VOLUME_MUTE = 0xAD;
    private const byte VK_VOLUME_DOWN = 0xAE;
    private const byte VK_VOLUME_UP = 0xAF;

    private bool IsWindows => OS.GetName() == "Windows";

    private void Tap(byte vk)
    {
        if (!IsWindows) return;
        keybd_event(vk, 0, 0, UIntPtr.Zero);
        keybd_event(vk, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
    }

    public bool Available() => IsWindows;
    public void PlayPause() => Tap(VK_MEDIA_PLAY_PAUSE);
    public void Next() => Tap(VK_MEDIA_NEXT);
    public void Previous() => Tap(VK_MEDIA_PREV);
    public void StopMedia() => Tap(VK_MEDIA_STOP);
    public void VolumeUp() => Tap(VK_VOLUME_UP);
    public void VolumeDown() => Tap(VK_VOLUME_DOWN);
    public void Mute() => Tap(VK_VOLUME_MUTE);

    /// <summary>Intenta abrir la app de Spotify (URI spotify:). Devuelve si lo lanzó.</summary>
    public bool OpenSpotify()
    {
        try
        {
            var psi = new System.Diagnostics.ProcessStartInfo("spotify:") { UseShellExecute = true };
            System.Diagnostics.Process.Start(psi);
            return true;
        }
        catch
        {
            try
            {
                var psi = new System.Diagnostics.ProcessStartInfo("https://open.spotify.com") { UseShellExecute = true };
                System.Diagnostics.Process.Start(psi);
                return true;
            }
            catch { return false; }
        }
    }
}
