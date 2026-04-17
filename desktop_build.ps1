param(
    [switch]$OneFile
)

$ErrorActionPreference = "Stop"

Write-Host "Installing/updating PyInstaller..."
python -m pip install --upgrade pyinstaller

$args = @(
    "-m", "PyInstaller",
    "--noconfirm",
    "--windowed",
    "--clean",
    "--collect-all", "customtkinter",
    "--collect-all", "darkdetect",
    "--exclude-module", "torch",
    "--exclude-module", "torchaudio",
    "--exclude-module", "torchvision",
    "--exclude-module", "tensorflow",
    "--exclude-module", "av",
    "--exclude-module", "faster_whisper",
    "--name", "WeatherAssistantDesktop",
    "desktop_app.py"
)

if ($OneFile) {
    $args += "--onefile"
}

Write-Host "Building desktop app..."
python @args

Write-Host ""
Write-Host "Done."
if ($OneFile) {
    Write-Host "EXE: .\\dist\\WeatherAssistantDesktop.exe"
} else {
    Write-Host "EXE: .\\dist\\WeatherAssistantDesktop\\WeatherAssistantDesktop.exe"
}
