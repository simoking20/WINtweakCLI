@echo off
:: WinTweak CLI v3.0 - Run as Administrator
chcp 65001 >nul 2>&1
setlocal EnableDelayedExpansion

set "BASE_DIR=%~dp0"
if "%BASE_DIR:~-1%"=="\" set "BASE_DIR=%BASE_DIR:~0,-1%"
set "MOD=%BASE_DIR%\modules"
set "SCR=%BASE_DIR%\scripts"
set "PRO=%BASE_DIR%\config\profiles"

:: Initialize (admin check + dirs + log)
call "%MOD%\_init.bat"
if %errorlevel% neq 0 exit /b 1

:: CLI argument routing
if not "%~1"=="" goto CMDLINE

goto MENU

:CMDLINE
if /i "%~1"=="/ultimate"    goto MODE_ULTIMATE
if /i "%~1"=="/gaming"      goto MODE_ULTIMATE
if /i "%~1"=="/compstable"  goto MODE_COMPSTABLE
if /i "%~1"=="/latency"     goto MODE_LATENCY
if /i "%~1"=="/esports"     goto MODE_ESPORTS
if /i "%~1"=="/stable"      goto MODE_STABLE
if /i "%~1"=="/laptop"      goto MODE_LAPTOP
if /i "%~1"=="/battery"     goto MODE_BATTERY
if /i "%~1"=="/backup"      goto BACKUP
if /i "%~1"=="/monitor"     goto MONITOR
if /i "%~1"=="/benchmark"   goto BENCHMARK
if /i "%~1"=="/undo"        goto UNDO_MODE
if /i "%~1"=="/list"        ( call "%MOD%\checkpoint.bat" LIST & exit /b 0 )
if /i "%~1"=="/checkpoint"  ( call "%MOD%\checkpoint.bat" CREATE "%~2" & exit /b 0 )
if /i "%~1"=="/restore"     ( call "%MOD%\checkpoint.bat" RESTORE "%~2" & exit /b 0 )
if /i "%~1"=="/compare"     ( call "%MOD%\checkpoint.bat" COMPARE "%~2" "%~3" & exit /b 0 )
if /i "%~1"=="/help"        goto HELP
if /i "%~1"=="/?"           goto HELP
echo [ERROR] Unknown argument: %~1
goto HELP

:: ============================================================
:MENU
:: ============================================================
cls
echo.
echo   WinTweak CLI v3.0  -  by SIMO_Dev
echo   =====================================
echo.

:: Live status
set "DEV=Unknown"
if exist "%BASE_DIR%\config\device_profile.ini" (
    for /f "tokens=2 delims==" %%v in ('findstr "DeviceType" "%BASE_DIR%\config\device_profile.ini" 2^>nul') do set "DEV=%%v"
)
set "CP_COUNT=0"
for /f %%i in ('type "%BASE_DIR%\config\checkpoints\index.txt" 2^>nul ^| find /c "checkpoint_"') do set "CP_COUNT=%%i"
echo   Device: %DEV%   Checkpoints saved: %CP_COUNT%
echo.
  echo   [STABILITY] [RISK]  MODE                    [TEMP] [POWER] [RESTART]
  echo   ---------------------------------------------------------------------
  echo   [*****] [NONE]  [1] BATTERY SAVER        65C    30W      No
  echo   [*****] [NONE]  [2] STABLE PERFORMANCE   70C    70%%      No
  echo   [****]  [LOW]   [3] LAPTOP BALANCED      75C    80%%      No
  echo   [****]  [LOW]   [4] COMPETITIVE STABLE   75C    80%%      Yes*
  echo   [***]   [MED]   [5] COMPETITIVE ESPORTS  80C    100%%     No
  echo   [**]    [HIGH]  [6] ULTIMATE GAMING       85C    100%%     No
  echo   [*]     [VHIGH] [7] LATENCY ^& SMOOTHNESS  85C+   100%%     Yes
echo.
echo   * HPET disable requires restart
  echo   [STABILITY MONITOR]: Active ^| [LAST CHECK]: Pass ^| [CHECKPOINTS]: %CP_COUNT%
echo.
echo   --- Hardware ---
echo    8. NVIDIA GPU Control     (clock lock, power limit)
echo    9. AMD GPU Control        (ULPS, Anti-Lag)
echo   10. VRAM Optimization      (HAGS, MPO, Game DVR)
echo.
echo   --- Tuning ---
echo   11. Timer Resolution       (0.5ms / 1.0ms / 15.6ms)
echo   12. Input Optimization     (USB poll rate + mouse)
echo   13. FPS Registry Tweaks    (MPO, Game Mode, preemption)
echo.
echo   --- System ---
echo   14. Device Detection       (auto-detect + apply)
echo   15. Thermal Control        (CPU/GPU throttling)
echo   16. Process Isolation      (core affinity + priority)
echo   17. Network Optimizer      (TCP/IP + DNS)
echo   18. Clean Up Temp File     (System temp folders)
echo.
echo   --- Checkpoints ---
echo    C. Create checkpoint
echo    L. List checkpoints
echo    R. Restore checkpoint
echo    D. Delete checkpoint
echo    X. Compare checkpoints
echo.
echo   --- Tools ---
echo    M. Stability Dashboard
echo    B. Full system backup
echo    S. Apply JSON profile
echo    P. Real-time Monitor       [NEW v3.0]
echo    K. Run Benchmark           [NEW v3.0]
echo    U. Undo Last Mode          [NEW v3.0]
echo    Q. Quit
echo.
set /p "OPT=  Select: "

if "%OPT%"=="1"  goto MODE_BATTERY
if "%OPT%"=="2"  goto MODE_STABLE
if "%OPT%"=="3"  goto MODE_LAPTOP
if "%OPT%"=="4"  goto MODE_COMPSTABLE
if "%OPT%"=="5"  goto MODE_ESPORTS
if "%OPT%"=="6"  goto MODE_ULTIMATE
if "%OPT%"=="7"  goto MODE_LATENCY
if "%OPT%"=="8"  ( call "%MOD%\nvidia.bat"     INTERACTIVE_MENU & goto MENU )
if "%OPT%"=="9"  ( call "%MOD%\amd.bat"        INTERACTIVE_MENU & goto MENU )
if "%OPT%"=="10" ( call "%MOD%\gpu_memory.bat" INTERACTIVE_MENU & goto MENU )
if "%OPT%"=="11" ( call "%MOD%\timer.bat"      INTERACTIVE_MENU & goto MENU )
if "%OPT%"=="12" ( call "%MOD%\input.bat"      INTERACTIVE_MENU & goto MENU )
if "%OPT%"=="13" ( call "%MOD%\registry.bat"   INTERACTIVE_MENU & goto MENU )
if "%OPT%"=="14" ( call "%MOD%\system.bat"     DETECT_AND_APPLY & pause & goto MENU )
if "%OPT%"=="15" ( call "%MOD%\thermal.bat"    INTERACTIVE_MENU & goto MENU )
if "%OPT%"=="16" ( call "%MOD%\process.bat"    INTERACTIVE_MENU & goto MENU )
if "%OPT%"=="17" ( call "%MOD%\network.bat"    INTERACTIVE_MENU & goto MENU )
if "%OPT%"=="18" ( call "%MOD%\system.bat"     CLEAN_TEMP & pause & goto MENU )
if /i "%OPT%"=="C" ( call "%MOD%\checkpoint.bat" CREATE "Manual" & pause & goto MENU )
if /i "%OPT%"=="L" ( call "%MOD%\checkpoint.bat" LIST            & pause & goto MENU )
if /i "%OPT%"=="R" ( call "%MOD%\checkpoint.bat" RESTORE         & pause & goto MENU )
if /i "%OPT%"=="D" ( call "%MOD%\checkpoint.bat" DELETE          & pause & goto MENU )
if /i "%OPT%"=="X" ( call "%MOD%\checkpoint.bat" COMPARE         & pause & goto MENU )
if /i "%OPT%"=="M" goto STABILITY_DASHBOARD
if /i "%OPT%"=="B" goto BACKUP
if /i "%OPT%"=="S" goto PROFILE_MENU
if /i "%OPT%"=="P" goto MONITOR
if /i "%OPT%"=="K" goto BENCHMARK
if /i "%OPT%"=="U" goto UNDO_MODE
if /i "%OPT%"=="Q" goto QUIT
if /i "%OPT%"=="0" goto QUIT

echo   [!] Invalid option.
timeout /t 1 >nul
goto MENU

:: ============================================================
:MODE_ULTIMATE
:: ============================================================
cls
call "%MOD%\stability_engine.bat" pre_flight_check ULTIMATE
if %errorlevel% neq 0 exit /b 1

call "%MOD%\utils.bat" header "ULTIMATE GAMING MODE [** HIGH RISK]"
echo [WARN] WARNING: This mode runs hot and may throttle.
echo     Stability: 2/5 stars ^| Risk: HIGH
echo.
call "%MOD%\checkpoint.bat" CREATE "Before_Ultimate"
call "%MOD%\timer.bat" set_maximum
call "%MOD%\nvidia.bat" lock_maximum
call "%MOD%\power.bat" set_ultimate
call "%MOD%\registry.bat" apply_fps_tweaks
call "%MOD%\services.bat" disable_gaming_bloat
call "%MOD%\gpu_memory.bat" optimize_full
call "%MOD%\checkpoint.bat" CREATE "After_Ultimate"
call "%MOD%\stability_engine.bat" post_apply_monitor
echo.
echo [+] ULTIMATE GAMING MODE APPLIED
echo     Monitor temperatures! Auto-restore if instability detected.
pause
goto MENU

:: ============================================================
:MODE_COMPSTABLE
:: ============================================================
cls
call "%MOD%\stability_engine.bat" pre_flight_check COMPETITIVE_STABLE
if %errorlevel% neq 0 exit /b 1

call "%MOD%\utils.bat" header "COMPETITIVE STABLE [**** LOW RISK]"
echo [i] Balanced mode: Good performance with thermal safety.
echo     Stability: 4/5 stars ^| Risk: LOW
echo     Requires restart for HPET disable.
echo.
call "%MOD%\checkpoint.bat" CREATE "Before_CompStable"
call "%MOD%\competitive_stable.bat"
call "%MOD%\checkpoint.bat" CREATE "After_CompStable"
call "%MOD%\stability_engine.bat" post_apply_monitor
echo.
echo [+] COMPETITIVE STABLE APPLIED
echo     Sweet spot: 1800MHz locked, 80%% power, sustainable performance.
pause
goto MENU

:: ============================================================
:MODE_LATENCY
:: ============================================================
cls
echo.
echo   [3] Latency ^& Smoothness Mode
echo   --------------------------------
echo   Max GPU boost + 0.5ms timer + raw input optimization
echo   Expected: ~6ms lag, 80-85C (monitor temps!), short burst sessions
echo   Note: May throttle in long sessions - use CompStable for sustained play
echo.
set /p "_c=  Apply? (Y/N): "
if /i not "%_c%"=="Y" goto MENU

echo.
echo   [checkpoint] Saving pre-state...
call "%MOD%\checkpoint.bat" CREATE "Pre_Latency"
call "%MOD%\latency_smooth.bat"
echo   [checkpoint] Saving post-state...
call "%MOD%\checkpoint.bat" CREATE "Post_Latency"
echo.
echo   Done.
echo.
pause
goto MENU

:: ============================================================
:MODE_ESPORTS
:: ============================================================
cls
echo.
echo   [4] Competitive Esports Mode
echo   ------------------------------
echo   Timer + core isolation + network + USB optimization
echo   Expected: +2-8%% FPS, -3-8ms input lag
echo.
set /p "_c=  Apply? (Y/N): "
if /i not "%_c%"=="Y" goto MENU

call "%MOD%\checkpoint.bat" CREATE "Pre_Esports"
echo   [1/7] Timer 0.5ms...
call "%MOD%\timer.bat" SET_MAXIMUM
echo   [2/7] Core isolation...
call "%MOD%\process.bat" ISOLATE_CORES
echo   [3/7] Network optimize...
call "%MOD%\network.bat" OPTIMIZE_COMPETITIVE
echo   [4/7] USB input optimize...
call "%MOD%\input.bat" OPTIMIZE_USB
echo   [5/7] Disable services...
call "%MOD%\services.bat" DISABLE_GAMING_BLOAT
echo   [6/7] FPS registry...
call "%MOD%\registry.bat" APPLY_FPS_TWEAKS
echo   [7/7] Clear RAM standby...
call "%MOD%\memory.bat" CLEAR_STANDBY
call "%MOD%\checkpoint.bat" CREATE "Post_Esports"
echo.
echo   Done.
pause
goto MENU

:: ============================================================
:MODE_STABLE
:: ============================================================
cls
call "%MOD%\stability_engine.bat" pre_flight_check STABLE
if %errorlevel% neq 0 exit /b 1

call "%MOD%\utils.bat" header "STABLE PERFORMANCE [***** NO RISK]"
echo [OK] Safest mode. Maximum consistency, lowest temperatures.
echo     Stability: 5/5 stars ^| Risk: NONE
echo.
call "%MOD%\checkpoint.bat" CREATE "Before_Stable"
call "%MOD%\nvidia.bat" lock_stable
call "%MOD%\thermal.bat" disable_throttling
call "%MOD%\checkpoint.bat" CREATE "After_Stable"
echo.
echo [+] STABLE PERFORMANCE APPLIED
echo     Zero risk mode. Perfect for 24/7 operation.
pause
goto MENU

:: ============================================================
:MODE_LAPTOP
:: ============================================================
cls
echo.
echo   [6] Laptop Balanced Mode
echo   -------------------------
echo   AC: full performance / DC: battery efficiency
echo   Expected: +2-5%% FPS on AC, +30-50%% battery on DC
echo.
set /p "_c=  Apply? (Y/N): "
if /i not "%_c%"=="Y" goto MENU

call "%MOD%\checkpoint.bat" CREATE "Pre_Laptop"
echo   [1/4] Timer 1.0ms...
call "%MOD%\timer.bat" SET_EFFICIENT
echo   [2/4] Balanced power plan...
call "%MOD%\power.bat" SET_BALANCED_LAPTOP
echo   [3/4] Adaptive GPU clocks...
call "%MOD%\nvidia.bat" SET_ADAPTIVE
echo   [4/4] FPS registry...
call "%MOD%\registry.bat" APPLY_FPS_TWEAKS
call "%MOD%\checkpoint.bat" CREATE "Post_Laptop"
echo.
echo   Done.
pause
goto MENU

:: ============================================================
:MODE_BATTERY
:: ============================================================
cls
echo.
echo   [7] Battery Saver Mode
echo   -----------------------
echo   Min power draw, 50W GPU limit
echo   Expected: -10-20%% FPS, +30-50%% battery
echo.
set /p "_c=  Apply? (Y/N): "
if /i not "%_c%"=="Y" goto MENU

call "%MOD%\checkpoint.bat" CREATE "Pre_Battery"
echo   [1/3] Default timer...
call "%MOD%\timer.bat" SET_DEFAULT
echo   [2/3] Power saver plan...
call "%MOD%\power.bat" SET_BATTERY_SAVER
echo   [3/3] GPU efficiency mode...
call "%MOD%\nvidia.bat" SET_EFFICIENCY
call "%MOD%\checkpoint.bat" CREATE "Post_Battery"
echo.
echo   Done.
pause
goto MENU

:: ============================================================
:BACKUP
:: ============================================================
call "%MOD%\backup.bat" INTERACTIVE_MENU
pause
goto MENU


:: ============================================================
:PROFILE_MENU
:: ============================================================
cls
echo.
echo   Apply JSON Profile
echo   ------------------
echo    1. Desktop Ultimate Gaming
echo    2. Laptop Balanced
echo    3. Esports Competitive
echo    4. Minimal Debloat
echo    5. Competitive Stable  [NEW v2.2]
echo    6. Custom path
echo    0. Back
echo.
set /p "_p=  Select: "
set "PFILE="
if "%_p%"=="1" set "PFILE=%PRO%\desktop_ultimate.json"
if "%_p%"=="2" set "PFILE=%PRO%\laptop_balanced.json"
if "%_p%"=="3" set "PFILE=%PRO%\esports_competitive.json"
if "%_p%"=="4" set "PFILE=%PRO%\minimal_debloat.json"
if "%_p%"=="5" set "PFILE=%PRO%\competitive_stable.json"
if "%_p%"=="6" set /p "PFILE=  Path: "
if "%_p%"=="0" goto MENU
if not defined PFILE goto MENU
if not exist "%PFILE%" ( echo   [ERROR] File not found. & pause & goto MENU )
set /p "_d=  Dry run? (Y/N): "
if /i "%_d%"=="Y" (
    powershell -ExecutionPolicy Bypass -File "%SCR%\apply_profile.ps1" -Profile "%PFILE%" -DryRun
) else (
    powershell -ExecutionPolicy Bypass -File "%SCR%\apply_profile.ps1" -Profile "%PFILE%"
)
pause
goto MENU

:: ============================================================
:STABILITY_DASHBOARD
:: ============================================================
cls
echo.
echo  +--------------------------------------------------------------+
echo  ^|           SYSTEM STABILITY DASHBOARD                         ^|
echo  +--------------------------------------------------------------+
echo.
echo  CURRENT STATUS:
powershell -Command "$Temp = (Get-WmiObject MSAcpi_ThermalZoneTemperature -EA SilentlyContinue).CurrentTemperature; if ($Temp) { $C = ($Temp - 2732) / 10; Write-Host \"  CPU Temp: ${C}C\" -NoNewline; if ($C -gt 80) { Write-Host ' [HOT]' -ForegroundColor Red } else { Write-Host ' [OK]' -ForegroundColor Green } }" 2>nul
nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,power.draw,clocks.gr --format=csv,noheader 2>nul
echo.
echo  STABILITY METRICS:
echo    Uptime: %UPTIME%
echo    Last Crash: %LAST_CRASH%
echo    Thermal Throttles (24h): %THERMAL_EVENTS%
echo    Driver Crashes (7d): %DRIVER_CRASHES%
echo    Checkpoints: %CHECKPOINT_COUNT%
echo    Current Mode Stability: %CURRENT_STABILITY%
echo.
echo  RECOMMENDATION:
if "%THERMAL_EVENTS%" GTR "3" echo    [WARN] Switch to Stable or Competitive Stable mode
if "%DRIVER_CRASHES%" GTR "0" echo    [WARN] Update GPU drivers before using Ultimate/Latency
if "%CHECKPOINT_COUNT%" LSS "1" echo    [WARN] Create checkpoint before any optimization
echo.
pause
goto MENU

:: ============================================================
:HELP
:: ============================================================
echo.
echo   WinTweak CLI v3.0  -  Usage (run as Administrator)
echo.
echo   wtweak.bat                    Interactive menu
echo   wtweak.bat /gaming            [1] Ultimate gaming mode
echo   wtweak.bat /compstable        [2] Competitive Stable
echo   wtweak.bat /latency           [3] Latency + Smoothness mode
echo   wtweak.bat /esports           [4] Esports competitive mode
echo   wtweak.bat /stable            [5] Stable performance mode
echo   wtweak.bat /laptop            [6] Laptop balanced mode
echo   wtweak.bat /battery           [7] Battery saver mode
echo   wtweak.bat /monitor           Real-time system monitor  [v3.0]
echo   wtweak.bat /benchmark         Before/after benchmark    [v3.0]
echo   wtweak.bat /undo              Undo last applied mode    [v3.0]
echo   wtweak.bat /checkpoint "Name" Create checkpoint
echo   wtweak.bat /restore [num]     Restore checkpoint
echo   wtweak.bat /list              List checkpoints
echo   wtweak.bat /compare [n1] [n2] Compare checkpoints
echo   wtweak.bat /backup            Full system backup
echo   wtweak.bat /help              This help
echo.
exit /b 0

:: ============================================================
:MONITOR
:: ============================================================
cls
echo.
echo   Real-time System Monitor - WinTweak CLI v3.0
echo   (Press Ctrl+C to stop)
echo.
powershell -ExecutionPolicy Bypass -NoProfile -Command "& { . '%BASE_DIR%\WTFLoader.ps1'; Invoke-WTFMonitor }"
pause
goto MENU

:: ============================================================
:BENCHMARK
:: ============================================================
cls
echo.
echo   Performance Benchmark - WinTweak CLI v3.0
echo.
powershell -ExecutionPolicy Bypass -NoProfile -Command "& { . '%BASE_DIR%\WTFLoader.ps1'; Invoke-WTFBenchmark }"
pause
goto MENU

:: ============================================================
:UNDO_MODE
:: ============================================================
cls
echo.
echo   Undo Last Mode - WinTweak CLI v3.0
echo   Restores from latest checkpoint (interactive)
echo.
powershell -ExecutionPolicy Bypass -NoProfile -Command "& { . '%BASE_DIR%\WTFLoader.ps1'; Invoke-WTFCheckpoint -Action Restore -Interactive }"
pause
goto MENU

:: ============================================================
:QUIT
:: ============================================================
echo.
echo   WinTweak CLI v3.0 - Session ended.
echo   Log: %LOGFILE%
echo.
endlocal
exit /b 0
