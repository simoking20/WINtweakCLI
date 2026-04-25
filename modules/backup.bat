@echo off
:: ============================================================
::  backup.bat - Full system backup (separate from checkpoints)
:: ============================================================

setlocal EnableDelayedExpansion

if not defined BASE_DIR call "%~dp0_init.bat"

set "ACTION=%~1"
if "%ACTION%"=="" goto INTERACTIVE_MENU

if /i "%ACTION%"=="CREATE_FULL"   goto CREATE_FULL
if /i "%ACTION%"=="RESTORE_MENU"  goto RESTORE_MENU
if /i "%ACTION%"=="LIST_BACKUPS"  goto LIST_BACKUPS
if /i "%ACTION%"=="INTERACTIVE_MENU" goto INTERACTIVE_MENU
goto :EOF

:CREATE_FULL
echo.
echo  ============================================================
echo   FULL SYSTEM BACKUP
echo  ============================================================
echo  [WARN] This will export full registry hives and can take 5-20 minutes.
echo.

set /p "_dest=  Enter backup destination path (e.g. D:\Backups\): "
if "%_dest%"=="" (
    echo  [ERROR] No destination provided.
    goto :EOF
)

if not exist "%_dest%" mkdir "%_dest%" 2>nul

for /f "delims=" %%t in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do set "TS=%%t"
if not defined TS set "TS=%DATE:~-4%%DATE:~3,2%%DATE:~0,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%"
set "TS=%TS: =0%"
set "BACKUP_DIR=%_dest%\WinTweak_Backup_%TS%"
mkdir "%BACKUP_DIR%" 2>nul

echo.
echo  [*] Exporting HKLM registry hive...
reg export HKLM "%BACKUP_DIR%\HKLM_full.reg" /y
echo  [*] Exporting HKCU registry hive...
reg export HKCU "%BACKUP_DIR%\HKCU_full.reg" /y

echo  [*] Exporting services list...
sc query type= all state= all > "%BACKUP_DIR%\services_full.txt"

echo  [*] Exporting power plans...
powercfg /getactivescheme > "%BACKUP_DIR%\power_active.txt"
for /f "tokens=4" %%g in ('powercfg /getactivescheme') do (
    powercfg /export "%BACKUP_DIR%\power_active.pow" %%g >nul 2>&1
)

echo  [*] Exporting network config...
netsh dump > "%BACKUP_DIR%\network_full.cfg"
ipconfig /all > "%BACKUP_DIR%\ipconfig.txt"

echo  [*] Exporting environment variables...
set > "%BACKUP_DIR%\environment.txt"

:: Ask about user files
echo.
set /p "_userfiles=  Include user profile files? (Y/N): "
if /i "%_userfiles%"=="Y" (
    echo  [*] Backing up user AppData\Roaming...
    xcopy "%APPDATA%" "%BACKUP_DIR%\AppData_Roaming\" /E /I /Q /H /Y >nul 2>&1
    echo  [OK] User AppData backed up
)

:: Compress backup
echo.
echo  [*] Compressing backup to ZIP...
powershell -Command "Compress-Archive -Path '%BACKUP_DIR%' -DestinationPath '%BACKUP_DIR%.zip' -Force"
if %errorlevel% equ 0 (
    rd /s /q "%BACKUP_DIR%" >nul 2>&1
    echo  [OK] Backup compressed: %BACKUP_DIR%.zip
) else (
    echo  [WARN] Compression failed. Backup folder kept: %BACKUP_DIR%
)

echo  [OK] Full backup complete!
goto :EOF

:RESTORE_MENU
echo.
echo  ============================================================
echo   RESTORE FROM BACKUP
echo  ============================================================
set /p "_zip=  Enter path to backup ZIP file: "
if not exist "%_zip%" (
    echo  [ERROR] File not found: %_zip%
    goto :EOF
)

echo  [*] Extracting backup...
set "EXTRACT_DIR=%TEMP%\WinTweak_Restore_%RANDOM%"
powershell -Command "Expand-Archive -Path '%_zip%' -DestinationPath '%EXTRACT_DIR%' -Force"

echo  Available restore options:
echo   [1] Restore Registry (HKLM + HKCU)
echo   [2] Restore Network Config
echo   [3] Restore Individual Files
set /p "_ropt=  Select: "

if "%_ropt%"=="1" (
    set /p "_conf=  Type YES to import registry (will overwrite current): "
    if /i "%_conf%"=="YES" (
        :: Find the reg files
        for /r "%EXTRACT_DIR%" %%f in (HKLM_full.reg) do reg import "%%f" >nul 2>&1
        for /r "%EXTRACT_DIR%" %%f in (HKCU_full.reg) do reg import "%%f" >nul 2>&1
        echo  [OK] Registry imported. Restart required.
    )
)
if "%_ropt%"=="2" (
    for /r "%EXTRACT_DIR%" %%f in (network_full.cfg) do netsh exec "%%f" >nul 2>&1
    echo  [OK] Network config restored
)
if "%_ropt%"=="3" (
    echo  [INFO] Backup extracted to: %EXTRACT_DIR%
    echo  [INFO] Browse and copy files manually.
    start explorer "%EXTRACT_DIR%"
)
goto :EOF

:LIST_BACKUPS
echo.
echo  [BACKUP] No centralized backup index (backups go to user-specified locations).
echo  [INFO]   Backup ZIPs are named: WinTweak_Backup_[TIMESTAMP].zip
goto :EOF

:INTERACTIVE_MENU
echo.
echo  ============================================================
echo   SYSTEM BACKUP
echo  ============================================================
echo   [1] Create Full System Backup
echo   [2] Restore From Backup
echo   [0] Back
echo.
set /p "_opt=  Select option: "
if "%_opt%"=="1" ( call "%~f0" CREATE_FULL & goto INTERACTIVE_MENU )
if "%_opt%"=="2" ( call "%~f0" RESTORE_MENU & goto INTERACTIVE_MENU )
goto :EOF
