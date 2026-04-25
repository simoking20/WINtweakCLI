@echo off
:: ============================================================
::  amd.bat - AMD ULPS & Anti-Lag control
:: ============================================================

setlocal EnableDelayedExpansion

if not defined BASE_DIR call "%~dp0_init.bat"

set "ACTION=%~1"
if "%ACTION%"=="" goto INTERACTIVE_MENU

if /i "%ACTION%"=="DISABLE_ULPS"    goto DISABLE_ULPS
if /i "%ACTION%"=="ENABLE_ULPS"     goto ENABLE_ULPS
if /i "%ACTION%"=="ENABLE_ANTILAG"  goto ENABLE_ANTILAG
if /i "%ACTION%"=="DISABLE_ANTILAG" goto DISABLE_ANTILAG
if /i "%ACTION%"=="OPTIMIZE_AMD"    goto OPTIMIZE_AMD
if /i "%ACTION%"=="INTERACTIVE_MENU" goto INTERACTIVE_MENU

echo  [ERROR] Unknown AMD action: %ACTION%
exit /b 1

:DISABLE_ULPS
echo  [AMD] Disabling ULPS (Ultra Low Power State)...
:: Disable ULPS for all AMD adapters in registry
for /f "tokens=*" %%k in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}" /s /v "EnableUlps" 2^>nul ^| findstr "HKLM"') do (
    reg add "%%k" /v "EnableUlps" /t REG_DWORD /d 0 /f >nul 2>&1
    reg add "%%k" /v "EnableUlps_NA" /t REG_DWORD /d 0 /f >nul 2>&1
)
:: Direct path attempt
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000" /v "EnableUlps" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000" /v "EnableUlps_NA" /t REG_DWORD /d 0 /f >nul 2>&1
echo  [OK] ULPS disabled - GPU will maintain standby clocks
echo  [INFO] Helps reduce micro-stutters and clock transition delays
goto :EOF

:ENABLE_ULPS
echo  [AMD] Enabling ULPS (power saving mode)...
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000" /v "EnableUlps" /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000" /v "EnableUlps_NA" /t REG_DWORD /d 1 /f >nul 2>&1
echo  [OK] ULPS enabled (power saving)
goto :EOF

:ENABLE_ANTILAG
echo  [AMD] Enabling Anti-Lag...
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000" /v "KMD_EnableAntiLag" /t REG_DWORD /d 1 /f >nul 2>&1
echo  [OK] Anti-Lag enabled (reduces input latency)
echo  [INFO] Enable in AMD Software: Adrenalin for per-game settings
goto :EOF

:DISABLE_ANTILAG
echo  [AMD] Disabling Anti-Lag...
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000" /v "KMD_EnableAntiLag" /t REG_DWORD /d 0 /f >nul 2>&1
echo  [OK] Anti-Lag disabled
goto :EOF

:OPTIMIZE_AMD
echo  [AMD] Applying full AMD optimization...
call :DISABLE_ULPS
call :ENABLE_ANTILAG
:: FreeSync for competitive (disable screen tearing)
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000" /v "DALFreeSyncDCEVersion" /t REG_DWORD /d 0 /f >nul 2>&1
:: Override TGP if Radeon
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000" /v "PP_ThermalAutoThrottlingEnable" /t REG_DWORD /d 0 /f >nul 2>&1
echo  [OK] Full AMD optimization applied
goto :EOF

:INTERACTIVE_MENU
echo.
echo  ============================================================
echo   AMD GPU CONTROL
echo  ============================================================
echo   [1] Disable ULPS          (recommended for gaming)
echo   [2] Enable ULPS           (power saving)
echo   [3] Enable Anti-Lag       (input latency reduction)
echo   [4] Disable Anti-Lag
echo   [5] Full AMD Optimization (all tweaks)
echo   [0] Back
echo.
set /p "_opt=  Select option: "

if "%_opt%"=="1" ( call "%~f0" DISABLE_ULPS & goto INTERACTIVE_MENU )
if "%_opt%"=="2" ( call "%~f0" ENABLE_ULPS & goto INTERACTIVE_MENU )
if "%_opt%"=="3" ( call "%~f0" ENABLE_ANTILAG & goto INTERACTIVE_MENU )
if "%_opt%"=="4" ( call "%~f0" DISABLE_ANTILAG & goto INTERACTIVE_MENU )
if "%_opt%"=="5" ( call "%~f0" OPTIMIZE_AMD & goto INTERACTIVE_MENU )
goto :EOF
