@echo off
setlocal
rem Abre o prototipo GT3 no Godot (Interlagos + Porsche).
set "GODOT=%USERPROFILE%\Tools\godot\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" set "GODOT=C:\Users\davim\Tools\godot\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" set "GODOT=C:\Users\davi.ladeira\Tools\godot\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" (
    echo [ERRO] Godot nao encontrado em "%USERPROFILE%\Tools\godot\".
    pause
    exit /b 1
)
start "" "%GODOT%" --path "%~dp0."
