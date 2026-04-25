@echo off
:: ============================================================
::  timer.bat - Timer resolution control via NtSetTimerResolution
::  Uses timer_helper.ps1 for reliable C# interop
:: ============================================================

setlocal EnableDelayedExpansion

if not defined BASE_DIR call "%~dp0_init.bat"

set "HELPER=%~dp0timer_helper.ps1"
set "ACTION=%~1"
if "%ACTION%"=="" goto INTERACTIVE_MENU

if /i "%ACTION%"=="SET_MAXIMUM"      goto SET_MAXIMUM
if /i "%ACTION%"=="SET_EFFICIENT"    goto SET_EFFICIENT
if /i "%ACTION%"=="SET_DEFAULT"      goto SET_DEFAULT
if /i "%ACTION%"=="DISABLE_HPET"     goto DISABLE_HPET
if /i "%ACTION%"=="INTERACTIVE_MENU" goto INTERACTIVE_MENU

echo  [ERROR] Unknown timer action: %ACTION%
exit /b 1

:SET_MAXIMUM
echo  [TIMER] Setting maximum timer resolution (0.5ms target)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%HELPER%" -Action SetMaximum
if %errorlevel% neq 0 (
    echo  [WARN] PowerShell helper failed. Applying bcdedit fallback...
    bcdedit /set useplatformclock false >nul 2>&1
)
echo  [INFO] Expected benefit: +25-30%% frame consistency (not AVG FPS)
goto :EOF

:SET_EFFICIENT
echo  [TIMER] Setting efficient timer resolution (1.0ms)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%HELPER%" -Action SetEfficient
echo  [INFO] Efficient mode - good balance for work+gaming
goto :EOF

:SET_DEFAULT
echo  [TIMER] Resetting to Windows default timer (15.6ms)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%HELPER%" -Action SetDefault
goto :EOF

:DISABLE_HPET
echo.
echo  [TIMER] HPET Disable
echo  -------------------------------------------------------
echo   WARNING: System-dependent. May give +10-20%% FPS gain.
echo   Requires RESTART. Some systems become unstable.
echo  -------------------------------------------------------
set /p "_conf=  Type YES to disable HPET: "
if /i not "%_conf%"=="YES" (
    echo  [CANCELLED] HPET disable cancelled.
    goto :EOF
)
echo  [*] Disabling HPET via bcdedit + registry...
bcdedit /set useplatformclock false      >nul 2>&1
bcdedit /set useplatformtick yes         >nul 2>&1
bcdedit /set disabledynamictick yes      >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\kernel" /v "GlobalTimerResolutionRequests" /t REG_DWORD /d 1 /f >nul 2>&1
echo  [OK] HPET disabled. RESTART REQUIRED.
echo  [TIP] Also disable "High precision event timer" in Device Manager ^> System Devices.
goto :EOF

:INTERACTIVE_MENU
echo.
echo  ============================================================
echo   TIMER RESOLUTION CONTROL
echo  ============================================================
echo  [Current status]
powershell -NoProfile -ExecutionPolicy Bypass -File "%HELPER%" -Action QueryCurrent
echo.
echo   [1] Maximum Performance   0.5ms  (gaming, recommended)
echo   [2] Balanced / Efficient  1.0ms  (work+gaming)
echo   [3] Windows Default       15.6ms (stock behavior)
echo   [4] Disable HPET          (requires restart, risky)
echo   [0] Back
echo.
set /p "_opt=  Select option: "

if "%_opt%"=="1" ( call "%~f0" SET_MAXIMUM  & goto INTERACTIVE_MENU )
if "%_opt%"=="2" ( call "%~f0" SET_EFFICIENT & goto INTERACTIVE_MENU )
if "%_opt%"=="3" ( call "%~f0" SET_DEFAULT   & goto INTERACTIVE_MENU )
if "%_opt%"=="4" ( call "%~f0" DISABLE_HPET  & goto INTERACTIVE_MENU )
goto :EOF
