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
rem After "git pull" new art/rigs must be imported before running.
rem The last imported commit is kept in .godot\last_import_rev; re-import only when the commit changed.
set "REV=nogit"
for /f "delims=" %%i in ('git rev-parse HEAD 2^>nul') do set "REV=%%i"
set "STAMP=.godot\last_import_rev"
set "OLD="
if exist "%STAMP%" set /p OLD=<"%STAMP%"
if not exist ".godot\imported" goto doimport
if "%REV%"=="nogit" goto doimport
if not "%OLD%"=="%REV%" goto doimport
goto run
:doimport
echo Importing resources after update, up to 1-2 minutes...
"%GODOT_CON%" --headless --path . --import >nul 2>nul
if not exist ".godot" mkdir ".godot"
>"%STAMP%" echo %REV%
:run
if /i "%~1"=="edit" (
  start "" "%GODOT%" --path . --editor
) else (
  start "" "%GODOT%" --path .
)
