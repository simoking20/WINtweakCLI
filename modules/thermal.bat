@echo off
:: ============================================================
::  thermal.bat - CPU/GPU throttling control
:: ============================================================

setlocal EnableDelayedExpansion

if not defined BASE_DIR call "%~dp0_init.bat"

set "ACTION=%~1"
if "%ACTION%"=="" goto INTERACTIVE_MENU

if /i "%ACTION%"=="DISABLE_THROTTLING" goto DISABLE_THROTTLING
if /i "%ACTION%"=="ENABLE_THROTTLING"  goto ENABLE_THROTTLING
if /i "%ACTION%"=="SET_FAN_CURVE"      goto SET_FAN_CURVE
if /i "%ACTION%"=="INTERACTIVE_MENU"   goto INTERACTIVE_MENU
goto :EOF

:DISABLE_THROTTLING
echo  [THERMAL] Disabling CPU power throttling...

:: Disable CPU throttling via power plan
powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLE 0 >nul 2>&1
powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE 2 >nul 2>&1
powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_PROCESSOR PERFEPP 0 >nul 2>&1

:: Disable Processor Idle Demote/Promote
powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_PROCESSOR IDLEDEMOTE 0 >nul 2>&1
powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_PROCESSOR IDLEPROMOTE 0 >nul 2>&1

:: Power throttling off for all processes (Windows 10+)
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" /v "PowerThrottlingOff" /t REG_DWORD /d 1 /f >nul 2>&1

:: GPU power throttling via nvidia-smi if available
where nvidia-smi >nul 2>&1
if %errorlevel% equ 0 (
    :: Reset power limits to max
    for /f %%p in ('nvidia-smi --query-gpu^=power.max_limit --format^=csv^,noheader^,nounits 2^>nul') do (
        nvidia-smi --power-limit=%%p >nul 2>&1
        echo  [OK] NVIDIA power limit set to max: %%pW
    )
)

echo  [OK] CPU throttling disabled
echo  [WARN] Monitor CPU temperatures closely!
echo  [INFO] Use HWiNFO64 or HWMonitor for temperature monitoring
goto :EOF

:ENABLE_THROTTLING
echo  [THERMAL] Re-enabling CPU power throttling...
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling" /v "PowerThrottlingOff" /f >nul 2>&1
powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLE 100 >nul 2>&1
echo  [OK] CPU throttling re-enabled (power saving mode)
goto :EOF

:SET_FAN_CURVE
echo  [THERMAL] Fan curve control...
echo  [INFO] Hardware-specific fan control requires vendor tools:
echo         - ASUS: Armoury Crate / Fan Xpert
echo         - MSI: MSI Center / Afterburner
echo         - Gigabyte: GIGABYTE Control Center
echo         - Laptops: vendor-specific BIOS options
echo.
echo  Attempting generic WMI fan control check...
powershell -Command "Get-WmiObject -Namespace root\wmi -Class MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue | ForEach-Object { 'Thermal Zone: ' + (($_.CurrentTemperature - 2732) / 10) + ' C' }" 2>nul
echo.
echo  [INFO] For full fan curve control, use your GPU/motherboard's vendor software.
goto :EOF

:INTERACTIVE_MENU
echo.
echo  ============================================================
echo   THERMAL CONTROL
echo  ============================================================
echo   [1] Disable CPU/GPU Throttling  (maximum performance)
echo   [2] Enable CPU Throttling       (power saving)
echo   [3] Fan Curve Information       (hardware-specific)
echo   [0] Back
echo.
set /p "_opt=  Select option: "
if "%_opt%"=="1" ( call "%~f0" DISABLE_THROTTLING & goto INTERACTIVE_MENU )
if "%_opt%"=="2" ( call "%~f0" ENABLE_THROTTLING & goto INTERACTIVE_MENU )
if "%_opt%"=="3" ( call "%~f0" SET_FAN_CURVE & goto INTERACTIVE_MENU )
goto :EOF
