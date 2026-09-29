# preparar_godot.ps1 - Descarga el motor exacto con el que se construye MechaForge.
#
#   powershell -ExecutionPolicy Bypass -File tools\preparar_godot.ps1 [-Plantillas]
#
# Desde las releases oficiales de Godot (github.com/godotengine/godot-builds):
#   - Godot 4.7.2-stable .NET para Windows (116 MB) -> tools\godot\
#   - con -Plantillas: las plantillas de exportacion .NET (1,2 GB; solo se extraen
#     las de Windows) -> %APPDATA%\Godot\export_templates\4.7.2.stable.mono
#     (necesarias para tools\empaquetar.ps1 -Exe).
# Cada descarga se comprueba con el SHA512-SUMS.txt oficial. No instala nada en el
# sistema; si algo ya esta en su sitio, no lo vuelve a descargar.
param([switch]$Plantillas)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"   # Invoke-WebRequest va mucho mas rapido sin barra
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$release = "4.7.2-stable"
$base = "https://github.com/godotengine/godot-builds/releases/download/$release"
$root = Split-Path -Parent $PSScriptRoot
$toolsGodot = Join-Path $root "tools\godot"
$editorName = "Godot_v4.7.2-stable_mono_win64"
$tmp = Join-Path $env:TEMP "mechaforge_godot"
New-Item -ItemType Directory -Force $tmp | Out-Null

function Get-Verificado([string]$nombre) {
    $sums = Join-Path $tmp "SHA512-SUMS.txt"
    if (-not (Test-Path $sums)) {
        Invoke-WebRequest -Uri "$base/SHA512-SUMS.txt" -OutFile $sums -UseBasicParsing
    }
    $linea = Select-String -Path $sums -Pattern ([regex]::Escape($nombre)) | Select-Object -First 1
    if (-not $linea) { throw "$nombre no aparece en SHA512-SUMS.txt" }
    $esperado = ($linea.Line -split "\s+")[0].ToLower()
    $destino = Join-Path $tmp $nombre
    if (Test-Path $destino) {
        if ((Get-FileHash -Algorithm SHA512 $destino).Hash.ToLower() -ne $esperado) { Remove-Item -Force $destino }
    }
    if (-not (Test-Path $destino)) {
        Write-Host "Descargando $nombre ..."
        Invoke-WebRequest -Uri "$base/$nombre" -OutFile $destino -UseBasicParsing
    }
    $obtenido = (Get-FileHash -Algorithm SHA512 $destino).Hash.ToLower()
    if ($obtenido -ne $esperado) {
        Remove-Item -Force $destino
        throw "La suma SHA-512 de $nombre no coincide: descarga corrupta o manipulada."
    }
    Write-Host "  SHA-512 correcta ($nombre)."
    return $destino
}

# 1) Editor de Godot .NET.
$exe = Join-Path $toolsGodot "$editorName\${editorName}_console.exe"
if (Test-Path $exe) {
    Write-Host "Godot 4.7.2 .NET ya esta en $toolsGodot"
} else {
    $zip = Get-Verificado "$editorName.zip"
    Write-Host "Descomprimiendo en $toolsGodot ..."
    New-Item -ItemType Directory -Force $toolsGodot | Out-Null
    Expand-Archive -Path $zip -DestinationPath $toolsGodot -Force
    if (-not (Test-Path $exe)) { throw "El zip no tiene la estructura esperada: falta $exe" }
}

# 2) Plantillas de exportacion (solo las de Windows).
if ($Plantillas) {
    $tplDir = Join-Path $env:APPDATA "Godot\export_templates\4.7.2.stable.mono"
    if (Test-Path (Join-Path $tplDir "windows_release_x86_64.exe")) {
        Write-Host "Las plantillas ya estan en $tplDir"
    } else {
        $tpz = Get-Verificado "Godot_v4.7.2-stable_mono_export_templates.tpz"
        Write-Host "Extrayendo las plantillas de Windows en $tplDir ..."
        New-Item -ItemType Directory -Force $tplDir | Out-Null
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $arch = [System.IO.Compression.ZipFile]::OpenRead($tpz)
        try {
            foreach ($e in $arch.Entries) {
                if ($e.Name -like "windows_*" -or $e.Name -eq "version.txt") {
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, (Join-Path $tplDir $e.Name), $true)
                }
            }
        } finally { $arch.Dispose() }
    }
}

Write-Host ""
Write-Host "Listo. Siguientes pasos:"
Write-Host "  dotnet build project\MechaForge.sln"
Write-Host "  tools\godot\$editorName\$editorName.exe --path project            (abrir MechaForge)"
Write-Host "  tools\godot\$editorName\${editorName}_console.exe --headless --path project -- mftest   (pruebas)"
Write-Host "  powershell -ExecutionPolicy Bypass -File tools\empaquetar.ps1 -Zip -Exe             (ejecutable; requiere -Plantillas)"
