@echo off
rem RT Zerosum launcher (Windows). "play.bat edit" opens the Godot editor.
setlocal
cd /d "%~dp0"
set "GODOT=%~dp0_engine\Godot_v4.7-stable_win64.exe"
set "GODOT_CON=%~dp0_engine\Godot_v4.7-stable_win64_console.exe"
if not exist "%GODOT%" (
  where godot >nul 2>nul && (set "GODOT=godot" & set "GODOT_CON=godot") || (
    echo Godot 4.7 not found. Run setup\install_windows.ps1 first.
    pause
    exit /b 1
  )
)
if not exist ".godot\imported" (
  echo First run: importing resources, 1-2 minutes...
  "%GODOT_CON%" --headless --path . --import >nul 2>nul
)
if /i "%~1"=="edit" (
  start "" "%GODOT%" --path . --editor
) else (
  start "" "%GODOT%" --path .
)
