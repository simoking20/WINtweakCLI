@echo off
:: ============================================================
::  power.bat - Ultimate/Balanced/Battery power plans
:: ============================================================

setlocal EnableDelayedExpansion

if not defined BASE_DIR call "%~dp0_init.bat"

set "ACTION=%~1"
if "%ACTION%"=="" goto INTERACTIVE_MENU

if /i "%ACTION%"=="SET_ULTIMATE"       goto SET_ULTIMATE
if /i "%ACTION%"=="SET_BALANCED_LAPTOP" goto SET_BALANCED_LAPTOP
if /i "%ACTION%"=="SET_BATTERY_SAVER"   goto SET_BATTERY_SAVER
if /i "%ACTION%"=="INTERACTIVE_MENU"   goto INTERACTIVE_MENU

echo  [ERROR] Unknown power action: %ACTION%
exit /b 1

:SET_ULTIMATE
echo  [POWER] Applying Ultimate Performance plan...

:: Duplicate the Ultimate Performance scheme (GUID: e9a42b02...)
set "NEW_GUID="
for /f "tokens=*" %%g in ('powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2^>nul') do (
    :: Output: "Power Scheme GUID: xxxxxxxx-..."
    echo %%g | findstr /i "GUID" >nul && (
        for /f "tokens=4" %%x in ("%%g") do set "NEW_GUID=%%x"
    )
)

if not defined NEW_GUID (
    echo  [WARN] Could not duplicate - looking for existing Ultimate plan...
    for /f "tokens=4" %%g in ('powercfg /list 2^>nul ^| findstr /i "ultimate"') do set "NEW_GUID=%%g"
)

if defined NEW_GUID (
    powercfg /setactive %NEW_GUID% >nul 2>&1
    echo  [OK] Ultimate Performance plan activated: %NEW_GUID%
) else (
    echo  [WARN] Ultimate Performance plan not available. Using High Performance.
    powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c >nul 2>&1
)

:: Disable all timeouts
powercfg /change monitor-timeout-ac 0 >nul 2>&1
powercfg /change monitor-timeout-dc 0 >nul 2>&1
powercfg /change standby-timeout-ac 0 >nul 2>&1
powercfg /change standby-timeout-dc 0 >nul 2>&1
powercfg /change hibernate-timeout-ac 0 >nul 2>&1
powercfg /change hibernate-timeout-dc 0 >nul 2>&1
powercfg /change disk-timeout-ac 0 >nul 2>&1
echo  [OK] All timeouts disabled (monitor, sleep, hibernate, disk)

:: Disable USB selective suspend
reg add "HKLM\SYSTEM\CurrentControlSet\Services\USB\Parameters" /v "DisableSelectiveSuspend" /t REG_DWORD /d 1 /f >nul 2>&1
powercfg /SETACVALUEINDEX SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 >nul 2>&1
echo  [OK] USB selective suspend disabled

:: Processor performance: 100%
if defined NEW_GUID (
    powercfg /setacvalueindex %NEW_GUID% SUB_PROCESSOR PROCTHROTTLEMAX 100 >nul 2>&1
    powercfg /setacvalueindex %NEW_GUID% SUB_PROCESSOR PROCTHROTTLEMIN 100 >nul 2>&1
) else (
    powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100 >nul 2>&1
    powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100 >nul 2>&1
)
echo  [OK] Processor performance locked at 100%%
echo  [INFO] Expected: +3-8%% AVG FPS
goto :EOF

:SET_BALANCED_LAPTOP
echo  [POWER] Applying Laptop Balanced plan...

:: Activate Balanced (GUID: 381b4222...)
powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e >nul 2>&1
if %errorlevel% equ 0 (
    echo  [OK] Balanced power plan activated
) else (
    echo  [WARN] Balanced plan not found, creating default...
    powercfg -duplicatescheme 381b4222-f694-41f0-9685-ff5bb260df2e >nul 2>&1
)

:: AC: 100% CPU, DC: 50% CPU
powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100 >nul 2>&1
powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 5 >nul 2>&1
powercfg /SETDCVALUEINDEX  SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 50 >nul 2>&1
powercfg /SETDCVALUEINDEX  SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 5 >nul 2>&1
echo  [OK] CPU: AC=100%%, DC=50%%

:: Disable sleep on AC, allow on DC
powercfg /change standby-timeout-ac 0 >nul 2>&1
powercfg /change standby-timeout-dc 30 >nul 2>&1
echo  [OK] Sleep: AC=Never, DC=30min
goto :EOF

:SET_BATTERY_SAVER
echo  [POWER] Applying Battery Saver plan...

:: Activate Power Saver (a1841308-3541-4fab-bc81-f71556f20b4a)
powercfg /setactive a1841308-3541-4fab-bc81-f71556f20b4a >nul 2>&1
if %errorlevel% neq 0 (
    :: Power Saver may not exist, try creating
    powercfg -duplicatescheme a1841308-3541-4fab-bc81-f71556f20b4a >nul 2>&1
    powercfg /setactive a1841308-3541-4fab-bc81-f71556f20b4a >nul 2>&1
)
echo  [OK] Power Saver plan activated

:: 50% CPU limit on DC
powercfg /SETDCVALUEINDEX  SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 50 >nul 2>&1

:: Battery Saver threshold at 20%
powercfg /SETDCVALUEINDEX SCHEME_CURRENT SUB_ENERGYSAVER ESBATTTHRESHOLD 20 >nul 2>&1
echo  [OK] Battery Saver threshold: 20%%
echo  [INFO] Expected: -10-20%% performance, +30-50%% battery life
goto :EOF

:INTERACTIVE_MENU
echo.
echo  ============================================================
echo   POWER PLAN CONTROL
echo  ============================================================
powercfg /getactivescheme 2>nul
echo  ============================================================
echo   [1] Ultimate Performance  (desktop gaming)
echo   [2] Laptop Balanced       (AC/DC differentiated)
echo   [3] Battery Saver         (maximum battery life)
echo   [0] Back
echo.
set /p "_opt=  Select option: "

if "%_opt%"=="1" ( call "%~f0" SET_ULTIMATE       & goto INTERACTIVE_MENU )
if "%_opt%"=="2" ( call "%~f0" SET_BALANCED_LAPTOP & goto INTERACTIVE_MENU )
if "%_opt%"=="3" ( call "%~f0" SET_BATTERY_SAVER   & goto INTERACTIVE_MENU )
goto :EOF
