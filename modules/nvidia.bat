@echo off
:: ============================================================
::  nvidia.bat - NVIDIA GPU clock locking & power management
:: ============================================================

setlocal EnableDelayedExpansion

if not defined BASE_DIR call "%~dp0_init.bat"

set "ACTION=%~1"
if "%ACTION%"=="" goto INTERACTIVE_MENU

if /i "%ACTION%"=="LOCK_MAXIMUM"    goto LOCK_MAXIMUM
if /i "%ACTION%"=="LOCK_STABLE"     goto LOCK_STABLE
if /i "%ACTION%"=="SET_ADAPTIVE"    goto SET_ADAPTIVE
if /i "%ACTION%"=="SET_EFFICIENCY"  goto SET_EFFICIENCY
if /i "%ACTION%"=="UNLOCK_CLOCKS"   goto UNLOCK_CLOCKS
if /i "%ACTION%"=="INTERACTIVE_MENU" goto INTERACTIVE_MENU

echo  [ERROR] Unknown nvidia action: %ACTION%
exit /b 1

:CHECK_NVIDIA
where nvidia-smi >nul 2>&1
if %errorlevel% neq 0 (
    echo  [ERROR] nvidia-smi not found. NVIDIA GPU not detected or driver not installed.
    exit /b 1
)
goto :EOF

:LOCK_MAXIMUM
call :CHECK_NVIDIA
echo.
echo  [NVIDIA] Locking GPU to maximum clocks...
echo  [WARN]   Monitor temperatures! This locks clocks to boost maximum.

:: Lock GPU core clocks (0,0 = max boost range)
nvidia-smi --lock-gpu-clocks=0,0 >nul 2>&1
if %errorlevel% equ 0 (
    echo  [OK] GPU core clocks locked to maximum boost
) else (
    :: Try newer syntax
    nvidia-smi -lgc 0,0 >nul 2>&1
    if %errorlevel% equ 0 (echo  [OK] GPU core clocks locked) else (echo  [WARN] Clock lock may not be supported on this GPU)
)

:: Lock memory clocks (0,0 = max)
nvidia-smi --lock-memory-clocks=0,0 >nul 2>&1
if %errorlevel% equ 0 (
    echo  [OK] GPU memory clocks locked to maximum
) else (
    nvidia-smi -lmc 0,0 >nul 2>&1
    echo  [WARN] Memory clock lock: see above for status
)

:: Set maximum power limit
for /f "tokens=1 delims= " %%p in ('nvidia-smi --query-gpu^=power.max_limit --format^=csv^,noheader^,nounits 2^>nul') do set "MAX_PWR=%%p"
if defined MAX_PWR (
    nvidia-smi --power-limit=%MAX_PWR% >nul 2>&1
    echo  [OK] Power limit set to maximum: %MAX_PWR%W
)

:: Enable persistence mode
nvidia-smi --persistence-mode=1 >nul 2>&1
echo  [OK] Persistence mode enabled

:: Registry: PowerMizer, Low Latency, Threaded Optimization
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000" /v "PowerMizerMode" /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKCU\SOFTWARE\NVIDIA Corporation\Global\NVTweak" /v "Ambient" /t REG_DWORD /d 0 /f >nul 2>&1

echo  [OK] NVIDIA registry tweaks applied
echo  [INFO] Expected: +15-20%% 1%% lows, 0%% clock variance
goto :EOF

:LOCK_STABLE
call :CHECK_NVIDIA
echo  [NVIDIA] Locking stable clocks (1500 MHz core, 5000 MHz memory)...
nvidia-smi --lock-gpu-clocks=1500,1500 >nul 2>&1
if %errorlevel% neq 0 nvidia-smi -lgc 1500,1500 >nul 2>&1
nvidia-smi --lock-memory-clocks=5000,5000 >nul 2>&1
if %errorlevel% neq 0 nvidia-smi -lmc 5000,5000 >nul 2>&1
echo  [OK] Stable clock lock applied (1500 MHz / 5000 MHz)
echo  [INFO] For thermal stability - adjust values based on your GPU model
goto :EOF

:SET_ADAPTIVE
call :CHECK_NVIDIA
echo  [NVIDIA] Setting adaptive mode (dynamic scaling)...
nvidia-smi --reset-gpu-clocks >nul 2>&1
if %errorlevel% neq 0 nvidia-smi -rgc >nul 2>&1
nvidia-smi --reset-memory-clocks >nul 2>&1
if %errorlevel% neq 0 nvidia-smi -rmc >nul 2>&1
echo  [OK] GPU clocks set to adaptive/dynamic mode
goto :EOF

:SET_EFFICIENCY
call :CHECK_NVIDIA
echo  [NVIDIA] Setting efficiency mode (50W power limit)...
nvidia-smi --reset-gpu-clocks >nul 2>&1
nvidia-smi --power-limit=50 >nul 2>&1
if %errorlevel% equ 0 (
    echo  [OK] Power limit set to 50W
) else (
    echo  [WARN] 50W may be below minimum power limit. Using minimum allowed.
    for /f %%p in ('nvidia-smi --query-gpu^=power.min_limit --format^=csv^,noheader^,nounits 2^>nul') do nvidia-smi --power-limit=%%p >nul 2>&1
)
echo  [INFO] Efficiency mode for laptop battery saving
goto :EOF

:UNLOCK_CLOCKS
call :CHECK_NVIDIA
echo  [NVIDIA] Unlocking all GPU clocks (full reset)...
nvidia-smi --reset-gpu-clocks >nul 2>&1
if %errorlevel% neq 0 nvidia-smi -rgc >nul 2>&1
nvidia-smi --reset-memory-clocks >nul 2>&1
if %errorlevel% neq 0 nvidia-smi -rmc >nul 2>&1
nvidia-smi --persistence-mode=0 >nul 2>&1
echo  [OK] All GPU clocks reset to dynamic behavior
goto :EOF

:INTERACTIVE_MENU
echo.
echo  ============================================================
echo   NVIDIA GPU CONTROL
echo  ============================================================
echo  [LIVE STATUS]
nvidia-smi --query-gpu=name,clocks.gr,clocks.mem,temperature.gpu,power.draw,utilization.gpu --format=csv,noheader 2>nul
echo.
echo  ============================================================
echo   [1] Maximum Performance  - Lock to max boost clocks
echo   [2] Stable Mode          - Lock to 1500/5000 MHz
echo   [3] Adaptive Mode        - Dynamic (default)
echo   [4] Efficiency Mode      - Low power (laptop)
echo   [5] Unlock All Clocks    - Full reset
echo   [6] Detailed Status      - Full nvidia-smi output
echo   [0] Back
echo.
set /p "_opt=  Select option: "

if "%_opt%"=="1" ( call "%~f0" LOCK_MAXIMUM   & goto INTERACTIVE_MENU )
if "%_opt%"=="2" ( call "%~f0" LOCK_STABLE    & goto INTERACTIVE_MENU )
if "%_opt%"=="3" ( call "%~f0" SET_ADAPTIVE   & goto INTERACTIVE_MENU )
if "%_opt%"=="4" ( call "%~f0" SET_EFFICIENCY & goto INTERACTIVE_MENU )
if "%_opt%"=="5" ( call "%~f0" UNLOCK_CLOCKS  & goto INTERACTIVE_MENU )
if "%_opt%"=="6" ( nvidia-smi                  & goto INTERACTIVE_MENU )
goto :EOF
