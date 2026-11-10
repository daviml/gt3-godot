@echo off
setlocal
rem Compila o APK do GT3 Time Attack para Android (arm64).
set GODOT=C:\Users\davim\Tools\godot\Godot_v4.7.2-stable_win64_console.exe
if not exist "%GODOT%" (
    set GODOT=C:\Users\davi.ladeira\Tools\godot\Godot_v4.7.2-stable_win64_console.exe
)
set OUT=build\android\GT3 Time Attack.apk

if not exist "build\android" mkdir "build\android"

echo ========================================================
echo   GT3 Time Attack - Build Android APK
echo ========================================================
echo Compilando APK em modo Release...
"%GODOT%" --headless --path "%~dp0." --export-release "Android" "%OUT%"

if %ERRORLEVEL% equ 0 (
    echo.
    echo ========================================================
    echo   [OK] APK gerado com sucesso!
    echo   Local: %OUT%
    echo.
    echo   Para instalar via USB:
    echo   adb install -r "%OUT%"
    echo ========================================================
) else (
    echo.
    echo ========================================================
    echo   [ERRO] Falha na compilacao do APK.
    echo ========================================================
    exit /b %ERRORLEVEL%
)
