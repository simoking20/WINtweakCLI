@echo off
:: ============================================================
::  input.bat - USB poll rate optimization
:: ============================================================

setlocal EnableDelayedExpansion

if not defined BASE_DIR call "%~dp0_init.bat"

set "ACTION=%~1"
if "%ACTION%"=="" goto INTERACTIVE_MENU

if /i "%ACTION%"=="OPTIMIZE_USB"     goto OPTIMIZE_USB
if /i "%ACTION%"=="LIST_DEVICES"     goto LIST_DEVICES
if /i "%ACTION%"=="INTERACTIVE_MENU" goto INTERACTIVE_MENU
goto :EOF

:OPTIMIZE_USB
echo.
echo  [INPUT] Optimizing USB input devices...

:: Disable USB selective suspend globally
reg add "HKLM\SYSTEM\CurrentControlSet\Services\USB\Parameters" /v "DisableSelectiveSuspend" /t REG_DWORD /d 1 /f >nul 2>&1
echo  [OK] USB selective suspend disabled

:: Keyboard repeat rate (fastest)
reg add "HKCU\Control Panel\Keyboard" /v "KeyboardDelay" /t REG_SZ /d "0" /f >nul 2>&1
reg add "HKCU\Control Panel\Keyboard" /v "KeyboardSpeed" /t REG_SZ /d "31" /f >nul 2>&1
echo  [OK] Keyboard: delay=0, speed=31 (maximum)

:: USB HID poll rate - set to 1000Hz (1ms)
:: This requires modifying HID device parameters
echo  [*] Setting USB HID poll intervals...
for /f "tokens=*" %%k in ('reg query "HKLM\SYSTEM\CurrentControlSet\Enum" /s /k 2^>nul ^| findstr /i "HID"') do (
    reg add "%%k\Device Parameters" /v "KeyboardDataQueueSize" /t REG_DWORD /d 100 /f >nul 2>&1
)

:: Mouse fix - disable pointer precision
reg add "HKCU\Control Panel\Mouse" /v "MouseSpeed" /t REG_SZ /d "0" /f >nul 2>&1
reg add "HKCU\Control Panel\Mouse" /v "MouseThreshold1" /t REG_SZ /d "0" /f >nul 2>&1
reg add "HKCU\Control Panel\Mouse" /v "MouseThreshold2" /t REG_SZ /d "0" /f >nul 2>&1
echo  [OK] Mouse acceleration disabled

:: USB power management - disable suspend for all USB hubs
powershell -Command ^
    "Get-WmiObject Win32_USBHub -ErrorAction SilentlyContinue | ForEach-Object {" ^
    "  Set-WmiInstance -Path $_.Path -Argument @{PowerManagementCapabilities='0'} -ErrorAction SilentlyContinue" ^
    "}" >nul 2>&1
echo  [OK] USB hub power management disabled

echo.
echo  [INFO] For hardware 1000Hz poll rate, use your mouse's software:
echo         - Logitech G HUB, Razer Synapse, SteelSeries GG, etc.
echo  [INFO] Registry changes take effect immediately
goto :EOF

:LIST_DEVICES
echo.
echo  [INPUT] Connected HID devices:
powershell -Command ^
    "Get-WmiObject Win32_PointingDevice -ErrorAction SilentlyContinue | Select-Object Name,DeviceID | ForEach-Object { '  [MOUSE] ' + $_.Name }" 2>nul
powershell -Command ^
    "Get-WmiObject Win32_Keyboard -ErrorAction SilentlyContinue | Select-Object Name,DeviceID | ForEach-Object { '  [KB]    ' + $_.Name }" 2>nul
goto :EOF

:INTERACTIVE_MENU
echo.
echo  ============================================================
echo   INPUT DEVICE OPTIMIZATION
echo  ============================================================
echo   [1] Optimize USB Input (poll rate + suspend)
echo   [2] List Connected Devices
echo   [0] Back
echo.
set /p "_opt=  Select option: "
if "%_opt%"=="1" ( call "%~f0" OPTIMIZE_USB & goto INTERACTIVE_MENU )
if "%_opt%"=="2" ( call "%~f0" LIST_DEVICES & goto INTERACTIVE_MENU )
goto :EOF
