# RT Zerosum installer (Windows): clones the project into %USERPROFILE%\game, downloads Godot 4.7 into _engine\, then runs it.
# Usage (paste into PowerShell):
#   irm https://raw.githubusercontent.com/HomilBBANG/rt_zerosum/claude/clever-keller-maq0u6/setup/install_windows.ps1 | iex
# Options (env vars): $env:GAME_DIR=<folder>  $env:GAME_BRANCH=<branch>  $env:NO_RUN="1" (install only)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"   # much faster Invoke-WebRequest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Repo    = "https://github.com/HomilBBANG/rt_zerosum.git"
$Branch  = if ($env:GAME_BRANCH) { $env:GAME_BRANCH } else { "claude/clever-keller-maq0u6" }
$Dir     = if ($env:GAME_DIR) { $env:GAME_DIR } else { Join-Path $env:USERPROFILE "game" }
$GodotVer = "4.7-stable"
$Base    = "https://github.com/godotengine/godot-builds/releases/download/$GodotVer"

Write-Host "== Installing RT Zerosum into $Dir (branch $Branch)"
$hasGit = [bool](Get-Command git -ErrorAction SilentlyContinue)
if (Test-Path (Join-Path $Dir ".git")) {
    Write-Host "-- Already installed: updating to latest"
    git -C $Dir fetch origin $Branch
    git -C $Dir checkout -q $Branch
    git -C $Dir pull --ff-only origin $Branch
} elseif ($hasGit) {
    if ((Test-Path $Dir) -and (Get-ChildItem $Dir -Force | Select-Object -First 1)) {
        throw "$Dir already contains other files. Empty it or set `$env:GAME_DIR to another folder."
    }
    git clone -b $Branch $Repo $Dir
} else {
    Write-Host "-- git not found: downloading a zip instead (run again to update)"
    $tmp = Join-Path $env:TEMP ("rtz_" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $zip = Join-Path $tmp "src.zip"
    Invoke-WebRequest -Uri "https://codeload.github.com/HomilBBANG/rt_zerosum/zip/refs/heads/$Branch" -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $srcRoot = Get-ChildItem $tmp -Directory | Where-Object { $_.Name -like "rt_zerosum-*" } | Select-Object -First 1
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    Copy-Item -Path (Join-Path $srcRoot.FullName "*") -Destination $Dir -Recurse -Force
    Remove-Item $tmp -Recurse -Force
}

$Engine = Join-Path $Dir "_engine"
New-Item -ItemType Directory -Force -Path $Engine | Out-Null
$Exe     = Join-Path $Engine "Godot_v${GodotVer}_win64.exe"
$Console = Join-Path $Engine "Godot_v${GodotVer}_win64_console.exe"
if (-not (Test-Path $Exe)) {
    Write-Host "-- Downloading Godot $GodotVer for Windows (about 70 MB)"
    $gz = Join-Path $Engine "godot.zip"
    Invoke-WebRequest -Uri "$Base/Godot_v${GodotVer}_win64.exe.zip" -OutFile $gz
    Expand-Archive -Path $gz -DestinationPath $Engine -Force
    Remove-Item $gz
}

Write-Host "-- First resource import (1-2 minutes)"
$imp = if (Test-Path $Console) { $Console } else { $Exe }
& $imp --headless --path $Dir --import | Out-Null

# Desktop shortcut
try {
    $ws = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut((Join-Path ([Environment]::GetFolderPath("Desktop")) "RT Zerosum.lnk"))
    $lnk.TargetPath = Join-Path $Dir "play.bat"
    $lnk.WorkingDirectory = $Dir
    $lnk.IconLocation = $Exe
    $lnk.Save()
    Write-Host "-- Created desktop shortcut 'RT Zerosum'."
} catch { Write-Host "-- Skipped shortcut: $($_.Exception.Message)" }

Write-Host "== Done. Next time run $Dir\play.bat (or the desktop shortcut)."
if ($env:NO_RUN -ne "1") { Start-Process -FilePath (Join-Path $Dir "play.bat") -WorkingDirectory $Dir }
