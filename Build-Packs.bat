@echo off
setlocal
rem ========================================================
rem   GT3 Time Attack - Exportador de Pacotes PCK (GitHub Releases)
rem ========================================================

set GODOT=C:\Users\davim\Tools\godot\Godot_v4.7.2-stable_win64_console.exe
if not exist "%GODOT%" (
    rem Fallback para caminho com davi.ladeira caso o usuário use este login
    set GODOT=C:\Users\davi.ladeira\Tools\godot\Godot_v4.7.2-stable_win64_console.exe
)

set OUT_DIR=build\packs
set OUT_BASE=%OUT_DIR%\base_data.pck
set OUT_PATCH=%OUT_DIR%\patch.pck

if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"

echo ========================================================
echo   1. Gerar base_data.pck (Pacote Pesado Inicial ~250MB)
echo   2. Gerar patch.pck (Atualizacao Leve Incremental)
echo   3. Gerar Ambos
echo ========================================================
set /p OPCAO="Escolha uma opcao (1, 2 ou 3): "

if "%OPCAO%"=="1" goto BUILD_BASE
if "%OPCAO%"=="2" goto BUILD_PATCH
if "%OPCAO%"=="3" goto BUILD_AMBOS

echo Opcao invalida.
exit /b 1

:BUILD_BASE
echo.
echo Exportando base_data.pck...
"%GODOT%" --headless --path "%~dp0." --export-pack "DataPack" "%OUT_BASE%"
if %ERRORLEVEL% equ 0 (
    echo [OK] base_data.pck gerado em: %OUT_BASE%
) else (
    echo [ERRO] Falha ao exportar base_data.pck.
)
goto FIM

:BUILD_PATCH
echo.
echo Exportando patch.pck...
"%GODOT%" --headless --path "%~dp0." --export-pack "Patch" "%OUT_PATCH%"
if %ERRORLEVEL% equ 0 (
    echo [OK] patch.pck gerado em: %OUT_PATCH%
) else (
    echo [ERRO] Falha ao exportar patch.pck.
)
goto FIM

:BUILD_AMBOS
echo.
echo Exportando base_data.pck...
"%GODOT%" --headless --path "%~dp0." --export-pack "DataPack" "%OUT_BASE%"
echo Exportando patch.pck...
"%GODOT%" --headless --path "%~dp0." --export-pack "Patch" "%OUT_PATCH%"
echo [OK] Pacotes gerados com sucesso em %OUT_DIR%!
goto FIM

:FIM
echo.
echo ========================================================
echo   Concluido! Anexe os arquivos na sua Release do GitHub.
echo ========================================================
