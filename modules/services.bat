@echo off
:: ============================================================
::  services.bat - Windows services disable/enable
:: ============================================================

setlocal EnableDelayedExpansion

if not defined BASE_DIR call "%~dp0_init.bat"

set "ACTION=%~1"
if "%ACTION%"=="" goto INTERACTIVE_MENU

if /i "%ACTION%"=="DISABLE_GAMING_BLOAT" goto DISABLE_GAMING_BLOAT
if /i "%ACTION%"=="RESTORE_SERVICES"     goto RESTORE_SERVICES
if /i "%ACTION%"=="LIST_DISABLED"        goto LIST_DISABLED
if /i "%ACTION%"=="INTERACTIVE_MENU"     goto INTERACTIVE_MENU
goto :EOF

:: List of services to disable for gaming
:: Format: service_name|display_name
set "BLOAT_SERVICES=DiagTrack|Connected User Experiences and Telemetry"
set "S1=DiagTrack"
set "S2=dmwappushservice"
set "S3=diagnosticshub.standardcollector.service"
set "S4=MapsBroker"
set "S5=WMPNetworkSvc"
set "S6=WSearch"
set "S7=SysMain"
set "S8=TabletInputService"
set "S9=Fax"
set "S10=PrintNotify"

:DISABLE_GAMING_BLOAT
echo.
echo  [SERVICES] Disabling gaming bloat services...
echo  [INFO] Services will be stopped and set to DISABLED

for %%s in (%S1% %S2% %S3% %S4% %S5% %S6% %S7% %S8% %S9% %S10%) do (
    sc query %%s >nul 2>&1
    if %errorlevel% equ 0 (
        sc stop %%s >nul 2>&1
        sc config %%s start= disabled >nul 2>&1
        echo  [OK] Disabled: %%s
    ) else (
        echo  [--] Not found: %%s
    )
)

echo.
echo  [OK] Gaming bloat services disabled
echo  [INFO] Frees background CPU/disk/memory usage for games
echo  [INFO] Run RESTORE_SERVICES to re-enable if needed
goto :EOF

:RESTORE_SERVICES
echo.
echo  [SERVICES] Restoring disabled services to automatic...

for %%s in (%S1% %S2% %S3% %S4% %S5% %S6% %S7% %S8% %S9% %S10%) do (
    sc config %%s start= auto >nul 2>&1
    sc start %%s >nul 2>&1
    echo  [OK] Restored: %%s
)

echo.
echo  [OK] Services restored to automatic start
goto :EOF

:LIST_DISABLED
echo.
echo  [SERVICES] Currently disabled services from bloat list:
for %%s in (%S1% %S2% %S3% %S4% %S5% %S6% %S7% %S8% %S9% %S10%) do (
    for /f "tokens=3" %%t in ('sc qc %%s 2^>nul ^| findstr "START_TYPE"') do (
        if "%%t"=="DISABLED" (
            echo   [OFF] %%s
        ) else (
            echo   [ON ] %%s - START: %%t
        )
    )
)
goto :EOF

:INTERACTIVE_MENU
echo.
echo  ============================================================
echo   WINDOWS SERVICES MANAGEMENT
echo  ============================================================
echo   [1] Disable Gaming Bloat Services
echo   [2] Restore All Services
echo   [3] List Service Status
echo   [0] Back
echo.
set /p "_opt=  Select option: "
if "%_opt%"=="1" ( call "%~f0" DISABLE_GAMING_BLOAT & goto INTERACTIVE_MENU )
if "%_opt%"=="2" ( call "%~f0" RESTORE_SERVICES & goto INTERACTIVE_MENU )
if "%_opt%"=="3" ( call "%~f0" LIST_DISABLED & goto INTERACTIVE_MENU )
goto :EOF
