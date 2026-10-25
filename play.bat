@echo off
rem RT Zerosum 실행 (Windows). "play.bat edit" 이면 Godot 에디터로 연다.
setlocal
cd /d "%~dp0"
set "GODOT=%~dp0_engine\Godot_v4.7-stable_win64.exe"
set "GODOT_CON=%~dp0_engine\Godot_v4.7-stable_win64_console.exe"
if not exist "%GODOT%" (
  where godot >nul 2>nul && (set "GODOT=godot" & set "GODOT_CON=godot") || (
    echo Godot 4.7 이 없습니다. setup\install_windows.ps1 을 먼저 실행하세요.
    pause
    exit /b 1
  )
)
if not exist ".godot\imported" (
  echo 첫 실행: 리소스 임포트 중 (1~2분)...
  "%GODOT_CON%" --headless --path . --import >nul 2>nul
)
if /i "%~1"=="edit" (
  start "" "%GODOT%" --path . --editor
) else (
  start "" "%GODOT%" --path .
)
