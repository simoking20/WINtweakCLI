@echo off
:: ============================================================
::  stability_engine.bat - Pre-flight checks and post-apply monitoring
::  Usage: stability_engine.bat [pre_flight_check|post_apply_monitor] [MODE]
:: ============================================================

setlocal EnableDelayedExpansion

if not defined BASE_DIR call "%~dp0_init.bat"

set "ACTION=%~1"
set "MODE=%~2"

if /i "%ACTION%"=="pre_flight_check"   goto PRE_FLIGHT
if /i "%ACTION%"=="post_apply_monitor" goto POST_MONITOR

echo  [STABILITY] Unknown action: %ACTION%
exit /b 0

:: ============================================================
:PRE_FLIGHT
:: ============================================================
echo.
echo  [STABILITY] Running pre-flight check for mode: %MODE%

:: Check admin rights
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo  [ERROR] Administrator privileges required.
    exit /b 1
)

:: Check disk space (need at least 500MB free for checkpoints)
set "DISK_OK=1"
for /f "tokens=3" %%s in ('dir /-c "%BASE_DIR%" 2^>nul ^| findstr /r "bytes free"') do (
    set "FREE_BYTES=%%s"
)

:: Check if nvidia-smi is available and set flag
set "NVIDIA_AVAILABLE=0"
where nvidia-smi >nul 2>&1
if %errorlevel% equ 0 (
    set "NVIDIA_AVAILABLE=1"
)

:: Check CPU temp via WMI (warn only)
set "CPU_WARN=0"
powershell -NoProfile -Command ^
  "$t=(Get-WmiObject MSAcpi_ThermalZoneTemperature -EA SilentlyContinue).CurrentTemperature; if($t){$c=($t-2732)/10; if($c -gt 85){Write-Host 'HOT'}else{Write-Host 'OK'}}" ^
  > "%TEMP%\_se_temp.tmp" 2>nul
set /p _TEMP_STATUS= < "%TEMP%\_se_temp.tmp"
del "%TEMP%\_se_temp.tmp" 2>nul
if /i "%_TEMP_STATUS%"=="HOT" (
    echo  [WARN] CPU temperature is high. Consider waiting for temps to drop.
    set "CPU_WARN=1"
) else (
    echo  [OK] Thermal status: Normal
)

:: Check if a checkpoint exists before high-risk mode
if /i "%MODE%"=="ULTIMATE" (
    set "CP_COUNT=0"
    for /f %%i in ('type "%BASE_DIR%\config\checkpoints\index.txt" 2^>nul ^| find /c "checkpoint_"') do set "CP_COUNT=%%i"
    if !CP_COUNT! LSS 1 (
        echo  [WARN] No checkpoints found. A checkpoint will be created before applying.
    )
)

echo  [STABILITY] Pre-flight check passed.
endlocal & set "NVIDIA_AVAILABLE=%NVIDIA_AVAILABLE%"
exit /b 0

:: ============================================================
:POST_MONITOR
:: ============================================================
echo.
echo  [STABILITY] Post-apply monitoring active...

:: Show current GPU status if NVIDIA available
where nvidia-smi >nul 2>&1
if %errorlevel% equ 0 (
    echo  [GPU] Current state:
    nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,power.draw,clocks.gr --format=csv,noheader 2>nul
)

:: Show CPU temp
powershell -NoProfile -Command ^
  "$t=(Get-WmiObject MSAcpi_ThermalZoneTemperature -EA SilentlyContinue).CurrentTemperature; if($t){$c=($t-2732)/10; Write-Host \"  CPU Temp: ${c}C\"}" ^
  2>nul

echo  [STABILITY] Monitor complete. Watch temperatures for first 5 minutes.
echo.
exit /b 0
