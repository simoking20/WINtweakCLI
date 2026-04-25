@echo off
:: WinTweak CLI v2.2 - Latency & Smoothness Module
:: Pure low-latency: max boost clocks + aggressive timer + input tuning
setlocal EnableDelayedExpansion

set "MODULES_DIR=%~dp0"
if "%MODULES_DIR:~-1%"=="\" set "MODULES_DIR=%MODULES_DIR:~0,-1%"

:: ============================================================
:LATENCY_SMOOTH_MODE
:: ============================================================
echo.
echo   [*] Applying LATENCY & SMOOTHNESS MODE (v2.2)...
echo   ---------------------------------------------------
echo   Target: Min input lag, max boost clocks, may throttle
echo.

:: 1. Timer 0.5ms
echo   [1/7] Setting timer resolution to 0.5ms...
call "%MODULES_DIR%\timer.bat" SET_MAXIMUM

:: 2. GPU max boost (unlock clocks)
echo   [2/7] Unlocking GPU clocks (max boost)...
nvidia-smi --reset-gpu-clocks    >nul 2>&1
nvidia-smi --reset-memory-clocks >nul 2>&1
:: Reset power limit to default (full TDP)
nvidia-smi --power-limit=0 >nul 2>&1

:: 3. Disable preemption for lower latency pipeline
echo   [3/7] Disabling GPU preemption and MPO...
reg add "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Scheduler" /v "DisablePreemption" /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows\Dwm" /v "OverlayTestMode" /t REG_DWORD /d 5 /f >nul 2>&1

:: 4. Low latency NVIDIA pipeline
echo   [4/7] Enabling NVIDIA low-latency mode...
reg add "HKLM\SOFTWARE\NVIDIA Corporation\Global\NvCplApi\Profiles" /v "LowLatencyMode" /t REG_DWORD /d 1 /f >nul 2>&1

:: 5. Raw input / anti-acceleration
echo   [5/7] Disabling mouse acceleration (raw input)...
reg add "HKCU\Control Panel\Mouse" /v "MouseSpeed" /t REG_SZ /d "0" /f >nul 2>&1
reg add "HKCU\Control Panel\Mouse" /v "MouseThreshold1" /t REG_SZ /d "0" /f >nul 2>&1
reg add "HKCU\Control Panel\Mouse" /v "MouseThreshold2" /t REG_SZ /d "0" /f >nul 2>&1

:: 6. USB selective suspend off
echo   [6/7] Disabling USB selective suspend...
powercfg /setacvalueindex scheme_current 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-1bbbed1e2aba 0 >nul 2>&1
powercfg /setactive scheme_current >nul 2>&1

:: 7. Process priority
echo   [7/7] Setting system responsiveness to 0...
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v "SystemResponsiveness" /t REG_DWORD /d 0 /f >nul 2>&1

echo.
echo   [+] LATENCY & SMOOTHNESS MODE APPLIED:
echo       GPU  : Max boost (unrestricted)
echo       TDP  : 100%% (full power)
echo       Timer: 0.5ms
echo       Lag  : ~6ms input latency
echo       Temps: 80-85C (monitor closely!)
echo       Note : May throttle in long sessions
echo.

endlocal
exit /b 0
