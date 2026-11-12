@echo off
setlocal
rem ========================================================
rem   GT3 Time Attack - Build Web / PWA (Vercel)
rem ========================================================

set "GODOT=%USERPROFILE%\Tools\godot\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT%" set "GODOT=C:\Users\davim\Tools\godot\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%GODOT%" set "GODOT=C:\Users\davi.ladeira\Tools\godot\Godot_v4.7.2-stable_win64_console.exe"

if not exist "%GODOT%" (
    echo [ERRO] Binario de console do Godot 4.7 nao encontrado em:
    echo        "%USERPROFILE%\Tools\godot\"
    pause
    exit /b 1
)

set "DEPLOY_DIR=%~dp0deploy\vercel"
set "TEMPLATE_DIR=%~dp0deploy\pwa-template"
set "OUT_HTML=%DEPLOY_DIR%\index.html"

if not exist "%DEPLOY_DIR%" mkdir "%DEPLOY_DIR%"

echo ========================================================
echo   GT3 Time Attack - Compilando Versao Web PWA
echo ========================================================
echo Destino: %DEPLOY_DIR%
echo Executando exportador Godot (modo headless)...
echo.

"%GODOT%" --headless --path "%~dp0." --export-release "Web" "%OUT_HTML%"

if %ERRORLEVEL% neq 0 (
    echo.
    echo ========================================================
    echo   [ERRO] Falha durante a exportacao do Godot para Web!
    echo ========================================================
    exit /b %ERRORLEVEL%
)

echo.
echo Particionando index.pck para respeitar o limite de 100MB do GitHub e Vercel...
powershell -NoProfile -Command ^
    "$pck = '%DEPLOY_DIR%\index.pck';" ^
    "if (Test-Path $pck) {" ^
    "  Remove-Item '%DEPLOY_DIR%\index.pck.part*' -Force -ErrorAction SilentlyContinue;" ^
    "  $fs = [System.IO.File]::OpenRead($pck);" ^
    "  $chunkSize = 45 * 1024 * 1024;" ^
    "  $buf = New-Object byte[] $chunkSize;" ^
    "  $idx = 0;" ^
    "  while ($fs.Position -lt $fs.Length) {" ^
    "    $read = $fs.Read($buf, 0, $chunkSize);" ^
    "    $out = [System.IO.File]::Create('%DEPLOY_DIR%\index.pck.part' + $idx);" ^
    "    $out.Write($buf, 0, $read);" ^
    "    $out.Close();" ^
    "    $idx++;" ^
    "  }" ^
    "  $fs.Close();" ^
    "  Remove-Item $pck -Force;" ^
    "  Write-Host '  [OK] index.pck dividido em ' $idx ' partes (<45MB cada). Original removido para git seguro.';" ^
    "}"

echo.
echo Copiando camada PWA (manifest, sw, headers Vercel, icones)...
copy /Y "%TEMPLATE_DIR%\manifest.json" "%DEPLOY_DIR%\manifest.json" >nul
copy /Y "%TEMPLATE_DIR%\sw.js" "%DEPLOY_DIR%\sw.js" >nul
copy /Y "%TEMPLATE_DIR%\vercel.json" "%DEPLOY_DIR%\vercel.json" >nul
if exist "%TEMPLATE_DIR%\icon-192.png" copy /Y "%TEMPLATE_DIR%\icon-192.png" "%DEPLOY_DIR%\icon-192.png" >nul
if exist "%TEMPLATE_DIR%\icon-512.png" copy /Y "%TEMPLATE_DIR%\icon-512.png" "%DEPLOY_DIR%\icon-512.png" >nul
if exist "%TEMPLATE_DIR%\og.jpg" copy /Y "%TEMPLATE_DIR%\og.jpg" "%DEPLOY_DIR%\og.jpg" >nul
if exist "%TEMPLATE_DIR%\og-image.jpg" copy /Y "%TEMPLATE_DIR%\og-image.jpg" "%DEPLOY_DIR%\og-image.jpg" >nul

echo.
echo ========================================================
echo   [OK] Build Web PWA gerada com sucesso!
echo   Diretorio de deploy: %DEPLOY_DIR%
echo.
echo   Arquivos principais:
echo   - index.html        (Shell responsivo + Splash + Audio Unlock)
echo   - index.wasm        (Binario WebAssembly)
echo   - index.pck.part*   (Pacote particionado em <45MB para GitHub)
echo   - manifest.json     (PWA Landscape)
echo   - sw.js             (Service Worker para instalacao PWA)
echo   - vercel.json       (Headers COOP/COEP e regras de cache)
echo.
echo   Pronto para commit no GitHub Desktop sem alertas de 100MB!
echo ========================================================
