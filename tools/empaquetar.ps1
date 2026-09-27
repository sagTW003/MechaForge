# empaquetar.ps1 — Crea la versión PORTABLE de MechaForge para Windows.
#
#   powershell -ExecutionPolicy Bypass -File tools\empaquetar.ps1 [-Zip] [-Exe]
#
# -Exe: además exporta el ejecutable oficial (preset "Windows Desktop") en
#       dist\MechaForge_exe\ — requiere las plantillas de exportación .NET 4.7.2
#       en %APPDATA%\Godot\export_templates\4.7.2.stable.mono.
#
# Resultado: dist\MechaForge_portable\
#   MechaForge.vbs        lanzador sin ventana de consola (doble clic)
#   MechaForge.bat        lanzador alternativo (muestra el registro)
#   motor\                runtime de Godot 4.7.2 .NET (incluye GodotSharp)
#   app\                  proyecto importado y con los ensamblados C# compilados
# No requiere instalar nada salvo el runtime de .NET 8 (Microsoft.NETCore.App).
param([switch]$Zip, [switch]$Exe)
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$godotDir = Join-Path $root "tools\godot\Godot_v4.7.2-stable_mono_win64"
$godotCon = Join-Path $godotDir "Godot_v4.7.2-stable_mono_win64_console.exe"
$proj = Join-Path $root "project"
$dist = Join-Path $root "dist"
$out = Join-Path $dist "MechaForge_portable"

if (-not (Test-Path $godotCon)) { throw "No se encuentra Godot .NET en $godotDir" }

Write-Host "[1/5] Compilando los módulos C#..."
dotnet build (Join-Path $proj "MechaForge.csproj") -c Debug -v q | Out-Host
if ($LASTEXITCODE -ne 0) { throw "Falló la compilación C#" }

Write-Host "[2/5] Importando recursos del proyecto..."
& $godotCon --headless --path $proj --import 2>&1 | Out-Null

Write-Host "[3/5] Preparando $out ..."
if (Test-Path $out) { Remove-Item -Recurse -Force $out }
New-Item -ItemType Directory -Force (Join-Path $out "motor") | Out-Null
New-Item -ItemType Directory -Force (Join-Path $out "app") | Out-Null
Copy-Item -Recurse -Force (Join-Path $godotDir "*") (Join-Path $out "motor")

Write-Host "[4/5] Copiando la aplicación..."
# Se excluyen cachés del editor y artefactos intermedios que no hacen falta para ejecutar.
robocopy $proj (Join-Path $out "app") /E /NFL /NDL /NJH /NJS /NP `
    /XD "$proj\.godot\editor" "$proj\.godot\shader_cache" "$proj\.godot\exported" "$proj\.godot\mono\temp\bin\ExportRelease" "$proj\.godot\mono\temp\bin\ExportDebug" "$proj\obj" "$proj\.godot\mono\temp\obj" /XF *.jpg *.hdr | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy falló ($LASTEXITCODE)" }

$godotExe = "Godot_v4.7.2-stable_mono_win64.exe"
Set-Content -Encoding ASCII (Join-Path $out "MechaForge.bat") @"
@echo off
rem MechaForge (portable) - lanzador con registro en consola
"%~dp0motor\Godot_v4.7.2-stable_mono_win64_console.exe" --path "%~dp0app" %*
"@
Set-Content -Encoding ASCII (Join-Path $out "MechaForge.vbs") @"
' MechaForge (portable) - lanzador sin ventana de consola
Set fso = CreateObject("Scripting.FileSystemObject")
d = fso.GetParentFolderName(WScript.ScriptFullName)
CreateObject("WScript.Shell").Run """" & d & "\motor\$godotExe"" --path """ & d & "\app""", 1, False
"@
Set-Content -Encoding UTF8 (Join-Path $out "LEEME.txt") @"
MechaForge - version portable
=============================
Doble clic en MechaForge.vbs para abrir el simulador (MechaForge.bat muestra el registro).
Requisitos: Windows 10/11, GPU con Vulkan y el runtime de .NET 8 (Microsoft.NETCore.App 8.x).
Los proyectos, el autoguardado, la configuracion de OpenClaw y los HDRI propios se guardan en:
  %APPDATA%\Godot\app_userdata\MechaForge
Manual completo: README.md del repositorio.
"@

Write-Host "[5/5] Verificando que la copia portable arranca..."
$ErrorActionPreference = "Continue"   # Godot escribe avisos en stderr; no son errores
$test = & (Join-Path $out "motor\Godot_v4.7.2-stable_mono_win64_console.exe") --headless --path (Join-Path $out "app") -- mftest 2>&1
$res = ($test | Select-String "\[TEST\] Resultado").ToString()
Write-Host "      $res"

if ($Zip) {
    $zipPath = Join-Path $dist "MechaForge_portable.zip"
    if (Test-Path $zipPath) { Remove-Item -Force $zipPath }
    Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zipPath -CompressionLevel Optimal
    Write-Host "ZIP: $zipPath"
}
if ($Exe) {
    $tpl = Join-Path $env:APPDATA "Godot\export_templates\4.7.2.stable.mono"
    if (-not (Test-Path (Join-Path $tpl "windows_release_x86_64.exe"))) { throw "Faltan las plantillas .NET en $tpl" }
    $exeDir = Join-Path $dist "MechaForge_exe"
    if (Test-Path $exeDir) { Remove-Item -Recurse -Force $exeDir }
    New-Item -ItemType Directory -Force $exeDir | Out-Null
    Write-Host "[Exe] Exportando con el preset 'Windows Desktop'..."
    & $godotCon --headless --path $proj --export-release "Windows Desktop" (Join-Path $exeDir "MechaForge.exe") 2>&1 | Select-String -Pattern "ERROR" | Out-Host
    Set-Content -Encoding UTF8 (Join-Path $exeDir "LEEME.txt") @"
MechaForge - ejecutable para Windows
====================================
Doble clic en MechaForge.exe (MechaForge.console.exe muestra el registro).
Requisitos: Windows 10/11, GPU con Vulkan y el runtime de .NET 8 (Microsoft.NETCore.App 8.x).
Conserva juntos MechaForge.exe, MechaForge.pck y la carpeta data_MechaForge_windows_x86_64.
Los datos del usuario (proyectos, autoguardado, API de OpenClaw, HDRI) estan en:
  %APPDATA%\Godot\app_userdata\MechaForge
"@
    $t2 = & (Join-Path $exeDir "MechaForge.console.exe") --headless -- mftest 2>&1
    Write-Host ("      Ejecutable: " + (($t2 | Select-String "\[TEST\] Resultado").ToString()))
    if ($Zip) {
        $zipExe = Join-Path $dist "MechaForge_windows.zip"
        if (Test-Path $zipExe) { Remove-Item -Force $zipExe }
        Compress-Archive -Path (Join-Path $exeDir "*") -DestinationPath $zipExe -CompressionLevel Optimal
        Write-Host "ZIP: $zipExe"
    }
}
$size = (Get-ChildItem -Recurse $out | Measure-Object -Sum Length).Sum / 1MB
Write-Host ("Listo: {0} ({1:N0} MB)" -f $out, $size)
