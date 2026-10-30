# verificar.ps1 — Lint, compilación y pruebas de MechaForge en un solo paso.
#
#   powershell -ExecutionPolicy Bypass -File tools\verificar.ps1 [suite ...]
#
# 1. gdlint (gdtoolkit 4.x, reglas en project\gdlintrc) sobre todos los .gd del repo.
#    Instalar una vez: uv tool install "gdtoolkit==4.*"
# 2. dotnet build: 0 errores y 0 avisos de C#.
# 3. Godot --import: ningún error de análisis de GDScript.
# 4. Las suites (todas, o las que se pasen): código de salida 0 y sin objetos de C#
#    liberados con el motor apagado («Leaked unsafe reference», SEHException).
# Termina con código 1 si algo falla.
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Suites)
# Continue: en PowerShell 5.1, con Stop, la salida de error de gdlint o Godot cortaría el script.
$ErrorActionPreference = "Continue"

$root = Split-Path -Parent $PSScriptRoot
$godotCon = Join-Path $root "tools\godot\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe"
$proj = Join-Path $root "project"
if (-not (Test-Path $godotCon)) { throw "No se encuentra Godot .NET: ejecuta tools\preparar_godot.ps1" }
if (-not $Suites) {
    $Suites = "mftest mfelec mfphys mfrefactor mffinal mfentorno mfejemplos mfmulti mflabtest mfadjuntos mfmanos mfvr".Split(" ")
}
$fallos = @()

Write-Host "[1/4] gdlint..."
Push-Location $proj
try {
    $files = git ls-files "*.gd"
    $lint = & gdlint @files 2>&1
    if ($LASTEXITCODE -ne 0) { $lint | Select-Object -Last 20 | Out-Host; $fallos += "gdlint" }
    else { Write-Host "      sin problemas ($($files.Count) archivos)" }
} finally { Pop-Location }

Write-Host "[2/4] dotnet build..."
$build = dotnet build (Join-Path $proj "MechaForge.csproj") -v q 2>&1 | Out-String
if ($LASTEXITCODE -ne 0 -or $build -match "(warning|advertencia) CS") { $build | Out-Host; $fallos += "dotnet build" }
else { Write-Host "      0 errores, 0 avisos" }

Write-Host "[3/4] Godot --import..."
$imp = & $godotCon --headless --path $proj --import 2>&1 | Out-String
$err = $imp -split "`n" | Where-Object { $_ -match "SCRIPT ERROR|Parse Error" }
if ($err) { $err | Out-Host; $fallos += "import" } else { Write-Host "      sin errores de análisis" }

Write-Host "[4/4] Suites..."
foreach ($s in $Suites) {
    $log = & $godotCon --headless --path $proj -- $s 2>&1 | Out-String
    $rc = $LASTEXITCODE
    $res = ($log -split "`n" | Where-Object { $_ -match "\[TEST\].*(OK|FALLOS)" } | Select-Object -Last 1)
    $leak = ($log -split "`n" | Where-Object { $_ -match "Leaked unsafe|SEHException|SCRIPT ERROR" }).Count
    Write-Host ("      {0,-11} salida={1} fugas/errores={2} :: {3}" -f $s, $rc, $leak, "$res".Trim())
    if ($rc -ne 0 -or $leak -gt 0) {
        $log -split "`n" | Where-Object { $_ -match "\[FALLO\]" } | Select-Object -First 5 | Out-Host
        $fallos += $s
    }
}

if ($fallos) { Write-Host "FALLA: $($fallos -join ', ')"; exit 1 }
Write-Host "Todo correcto."
