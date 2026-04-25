@echo off
:: ============================================================
::  process.bat - Core isolation & priority management
:: ============================================================

setlocal EnableDelayedExpansion

if not defined BASE_DIR call "%~dp0_init.bat"

set "ACTION=%~1"
if "%ACTION%"=="" goto INTERACTIVE_MENU

if /i "%ACTION%"=="ISOLATE_CORES"      goto ISOLATE_CORES
if /i "%ACTION%"=="SET_GAME_PRIORITY"  goto SET_GAME_PRIORITY
if /i "%ACTION%"=="RESET_PRIORITIES"   goto RESET_PRIORITIES
if /i "%ACTION%"=="INTERACTIVE_MENU"   goto INTERACTIVE_MENU
goto :EOF

:ISOLATE_CORES
echo.
echo  [PROCESS] Detecting CPU topology...

:: Get thread count
set "THREADS=0"
powershell -Command "[Environment]::ProcessorCount" > "%TEMP%\threads.tmp" 2>nul
set /p THREADS= < "%TEMP%\threads.tmp"
del "%TEMP%\threads.tmp" 2>nul

:: Get physical core count
set "PHYS_CORES=0"
powershell -Command "(Get-WmiObject Win32_Processor | Select-Object -First 1).NumberOfCores" > "%TEMP%\cores.tmp" 2>nul
set /p PHYS_CORES= < "%TEMP%\cores.tmp"
del "%TEMP%\cores.tmp" 2>nul

echo  [INFO] Logical threads: %THREADS% / Physical cores: %PHYS_CORES%

:: Calculate affinity mask for last 4 cores (for game isolation)
:: Typically cores 4-7 (or last N cores) are dedicated to game
set /a "GAME_CORES=4"
if %PHYS_CORES% LEQ 4 set /a "GAME_CORES=PHYS_CORES"

:: Calculate affinity mask (last GAME_CORES threads)
:: For 8 threads last 4: mask = 0xF0 = 240
:: For 16 threads last 4: mask = 0xF000
powershell -Command ^
    "$t=%THREADS%; $gc=%GAME_CORES%;" ^
    "$mask = ((1 -shl $gc) - 1) -shl ($t - $gc);" ^
    "Write-Host ('Affinity mask for game (last ' + $gc + ' threads): 0x' + $mask.ToString('X') + ' (' + $mask + ')')" 2>nul

:: Get affinity mask via PowerShell
powershell -Command ^
    "$t=%THREADS%; $gc=%GAME_CORES%;" ^
    "((1 -shl $gc) - 1) -shl ($t - $gc)" > "%TEMP%\affmask.tmp" 2>nul
set /p AFFMASK= < "%TEMP%\affmask.tmp"
del "%TEMP%\affmask.tmp" 2>nul

echo  [INFO] Game process affinity mask: %AFFMASK%
echo.
set /p "_game=  Enter game process name (e.g. game.exe) or press ENTER to skip: "

if not "%_game%"=="" (
    powershell -Command ^
        "Get-Process -Name '%_game:.exe=%' -ErrorAction SilentlyContinue | ForEach-Object {" ^
        "  $_.ProcessorAffinity = [IntPtr]%AFFMASK%;" ^
        "  $_.PriorityClass = 'High';" ^
        "  Write-Host ('  [OK] Set affinity and High priority for: ' + $_.Name + ' (PID ' + $_.Id + ')')" ^
        "}" 2>nul
    if %errorlevel% neq 0 echo  [WARN] Process not found or access denied
)

:: Apply registry-based priority for known game processes
echo.
echo  [*] Setting registry priority hints for common game processes...
for %%g in (csgo.exe valorant.exe r5apex.exe EscapeFromTarkov.exe RainbowSix.exe overwatch.exe) do (
    reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\%%g\PerfOptions" /v "CpuPriorityClass" /t REG_DWORD /d 3 /f >nul 2>&1
    reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\%%g\PerfOptions" /v "IoPriority" /t REG_DWORD /d 3 /f >nul 2>&1
)
echo  [OK] High priority set for common FPS games
goto :EOF

:SET_GAME_PRIORITY
echo  [PROCESS] Setting real-time / high priority for running games...
set /p "_proc=  Enter process name (without .exe): "
powershell -Command ^
    "Get-Process '%_proc%' -ErrorAction Stop | ForEach-Object {" ^
    "  $_.PriorityClass = 'AboveNormal';" ^
    "  Write-Host ('  [OK] Priority set for: ' + $_.Name)" ^
    "}" 2>nul
if %errorlevel% neq 0 echo  [WARN] Process not found
goto :EOF

:RESET_PRIORITIES
echo  [PROCESS] Resetting process priority registry entries...
for %%g in (csgo.exe valorant.exe r5apex.exe EscapeFromTarkov.exe RainbowSix.exe) do (
    reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\%%g\PerfOptions" /f >nul 2>&1
)
echo  [OK] Priority registry entries cleared
goto :EOF

:INTERACTIVE_MENU
echo.
echo  ============================================================
echo   PROCESS & CORE ISOLATION
echo  ============================================================
echo   [1] Isolate Cores for Gaming  (affinity + registry)
echo   [2] Set Priority for Process  (interactive)
echo   [3] Reset Priority Settings
echo   [0] Back
echo.
set /p "_opt=  Select option: "
if "%_opt%"=="1" ( call "%~f0" ISOLATE_CORES & goto INTERACTIVE_MENU )
if "%_opt%"=="2" ( call "%~f0" SET_GAME_PRIORITY & goto INTERACTIVE_MENU )
if "%_opt%"=="3" ( call "%~f0" RESET_PRIORITIES & goto INTERACTIVE_MENU )
goto :EOF
