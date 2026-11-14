@echo off
setlocal
rem Compila o APK do GT3 Time Attack para Android (arm64).
set GODOT=C:\Users\davim\Tools\godot\Godot_v4.7.2-stable_win64_console.exe
if not exist "%GODOT%" (
    set GODOT=C:\Users\davi.ladeira\Tools\godot\Godot_v4.7.2-stable_win64_console.exe
)
set OUT=build\android\GT3 Time Attack.apk

if not exist "%~dp0segredos.cfg" (
    echo [AVISO] segredos.cfg nao encontrado: o APK vai sair SEM ranking online.
    echo         Veja tools\segredos.md para criar o arquivo com o token do GitHub.
    choice /m "Continuar mesmo assim"
    if errorlevel 2 exit /b 1
)
if not exist "build\android" mkdir "build\android"

echo ========================================================
echo   GT3 Time Attack - Build Android APK
echo ========================================================
rem texturas leves para o celular (no PC ficam em alta qualidade/2048): troca, reimporta, exporta e volta
cd /d "%~dp0"
python tools\texturas_android.py pc >nul
python tools\texturas_android.py android
if errorlevel 1 exit /b 1
echo Reimportando texturas para Android (alguns minutos)...
"%GODOT%" --headless --path "%~dp0." --import >nul 2>&1
echo Compilando APK em modo Release...
"%GODOT%" --headless --path "%~dp0." --export-release "Android" "%OUT%"
set RESULT=%ERRORLEVEL%
python tools\texturas_android.py pc
echo Reimportando texturas do PC...
"%GODOT%" --headless --path "%~dp0." --import >nul 2>&1

if %RESULT% equ 0 (
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
    exit /b %RESULT%
)
