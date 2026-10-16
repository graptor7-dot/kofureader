# Compila KofuReader para Windows (release) y lo instala en
# %LOCALAPPDATA%\Programs\KofuReader con acceso directo en el menú Inicio.
# Volver a ejecutarlo actualiza la app (tus datos no se tocan).
#
#   powershell -ExecutionPolicy Bypass -File scripts\instalar-windows.ps1

$ErrorActionPreference = 'Stop'
$flutter = 'C:\dev\flutter\bin'
if (Test-Path $flutter) { $env:Path = "$flutter;$env:Path" }

$app = Join-Path $PSScriptRoot '..\app' | Resolve-Path
$dest = Join-Path $env:LOCALAPPDATA 'Programs\KofuReader'

Write-Host 'Compilando...'
Push-Location $app
flutter build windows --release
Pop-Location
if ($LASTEXITCODE -ne 0) { throw 'La compilación ha fallado' }

$running = Get-Process kofu_reader -ErrorAction SilentlyContinue
if ($running) {
    $running | Stop-Process -Force
    $running | Wait-Process -Timeout 10 -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500  # Windows tarda un instante en liberar las DLL
}
if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item -Recurse -Force (Join-Path $app 'build\windows\x64\runner\Release\*') $dest

$exe = Join-Path $dest 'kofu_reader.exe'
$shell = New-Object -ComObject WScript.Shell
$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\KofuReader.lnk'
$link = $shell.CreateShortcut($startMenu)
$link.TargetPath = $exe
$link.WorkingDirectory = $dest
$link.IconLocation = "$exe,0"
$link.Description = 'Lector de Komga'
$link.Save()

Write-Host "Instalado en $dest"
Write-Host 'Busca "KofuReader" en el menú Inicio.'
