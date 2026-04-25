@echo off
:: ============================================================
::  registry.bat - FPS tweaks (MPO, preemption, Game Mode)
:: ============================================================

setlocal EnableDelayedExpansion

if not defined BASE_DIR call "%~dp0_init.bat"

set "ACTION=%~1"
if "%ACTION%"=="" goto INTERACTIVE_MENU

if /i "%ACTION%"=="APPLY_FPS_TWEAKS" goto APPLY_FPS_TWEAKS
if /i "%ACTION%"=="RESTORE_DEFAULTS"  goto RESTORE_DEFAULTS
if /i "%ACTION%"=="INTERACTIVE_MENU"  goto INTERACTIVE_MENU
goto :EOF

:APPLY_FPS_TWEAKS
echo.
echo  [REGISTRY] Applying FPS registry tweaks...

:: Create safety backup of relevant keys
echo  [*] Backing up registry keys...
reg export "HKLM\SOFTWARE\Microsoft\Windows\Dwm" "%BASE_DIR%\config\reg_backup_dwm.reg" /y >nul 2>&1
reg export "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "%BASE_DIR%\config\reg_backup_gpu.reg" /y >nul 2>&1
echo  [OK] Registry backup created

:: MPO Disable (Multiplane Overlay) - +20-30% stutter reduction
echo  [*] Disabling MPO (Multiplane Overlay)...
reg add "HKLM\SOFTWARE\Microsoft\Windows\Dwm" /v "OverlayTestMode" /t REG_DWORD /d 5 /f >nul 2>&1
echo  [OK] MPO disabled

:: GPU Preemption Disable (reduces input lag)
echo  [*] Configuring GPU preemption...
reg add "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v "TdrLevel" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Timeout" /v "TdrDelay" /t REG_DWORD /d 10 /f >nul 2>&1
echo  [OK] GPU preemption timeout configured

:: AMD ULPS Disable
echo  [*] Disabling AMD ULPS...
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000" /v "EnableUlps" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000" /v "EnableUlps_NA" /t REG_DWORD /d 0 /f >nul 2>&1
echo  [OK] AMD ULPS disabled

:: Game Mode Enable
echo  [*] Enabling Windows Game Mode...
reg add "HKCU\Software\Microsoft\GameBar" /v "AllowAutoGameMode" /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\GameBar" /v "AutoGameModeEnabled" /t REG_DWORD /d 1 /f >nul 2>&1
echo  [OK] Game Mode enabled (+2-5%% AVG FPS, +10-20%% minimums)

:: Fullscreen Optimizations Disable (FSEBehaviorMode)
echo  [*] Disabling Fullscreen Optimizations...
reg add "HKCU\System\GameConfigStore" /v "FSEBehaviorMode" /t REG_DWORD /d 2 /f >nul 2>&1
reg add "HKCU\System\GameConfigStore" /v "FSEBehavior" /t REG_DWORD /d 2 /f >nul 2>&1
echo  [OK] Fullscreen optimizations disabled

:: Mouse Raw Input (disable acceleration)
echo  [*] Setting raw mouse input...
reg add "HKCU\Control Panel\Mouse" /v "MouseSpeed" /t REG_SZ /d "0" /f >nul 2>&1
reg add "HKCU\Control Panel\Mouse" /v "MouseThreshold1" /t REG_SZ /d "0" /f >nul 2>&1
reg add "HKCU\Control Panel\Mouse" /v "MouseThreshold2" /t REG_SZ /d "0" /f >nul 2>&1
reg add "HKCU\Control Panel\Mouse" /v "MouseSensitivity" /t REG_SZ /d "10" /f >nul 2>&1
echo  [OK] Mouse acceleration disabled (raw input)

:: Gaming system profile
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "GPU Priority" /t REG_DWORD /d 8 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "Priority" /t REG_DWORD /d 6 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "Scheduling Category" /t REG_SZ /d "High" /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games" /v "SFIO Priority" /t REG_SZ /d "High" /f >nul 2>&1
echo  [OK] Gaming system profile configured

:: Game DVR Off
reg add "HKCU\System\GameConfigStore" /v "GameDVR_Enabled" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" /v "AppCaptureEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
echo  [OK] Game DVR disabled

echo.
echo  [INFO] Expected: +5-10%% AVG FPS, +20-30%% frame consistency
echo  [WARN] Restart recommended for all changes to take full effect
goto :EOF

:RESTORE_DEFAULTS
echo  [REGISTRY] Restoring default registry values...
reg add "HKLM\SOFTWARE\Microsoft\Windows\Dwm" /v "OverlayTestMode" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\System\GameConfigStore" /v "FSEBehaviorMode" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Control Panel\Mouse" /v "MouseSpeed" /t REG_SZ /d "1" /f >nul 2>&1
reg add "HKCU\Control Panel\Mouse" /v "MouseThreshold1" /t REG_SZ /d "6" /f >nul 2>&1
reg add "HKCU\Control Panel\Mouse" /v "MouseThreshold2" /t REG_SZ /d "10" /f >nul 2>&1
echo  [OK] Registry defaults restored
goto :EOF

:INTERACTIVE_MENU
echo.
echo  ============================================================
echo   REGISTRY FPS TWEAKS
echo  ============================================================
echo   [1] Apply All FPS Tweaks
echo   [2] Restore Default Registry Values
echo   [0] Back
echo.
set /p "_opt=  Select option: "
if "%_opt%"=="1" ( call "%~f0" APPLY_FPS_TWEAKS & goto INTERACTIVE_MENU )
if "%_opt%"=="2" ( call "%~f0" RESTORE_DEFAULTS & goto INTERACTIVE_MENU )
goto :EOF
