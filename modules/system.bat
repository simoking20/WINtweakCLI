@echo off
:: ============================================================
::  system.bat - Device type detection & auto-apply
:: ============================================================

setlocal EnableDelayedExpansion

if not defined BASE_DIR call "%~dp0_init.bat"

set "ACTION=%~1"
if "%ACTION%"=="" set "ACTION=DETECT_DEVICE_TYPE"

if /i "%ACTION%"=="DETECT_DEVICE_TYPE" goto DETECT_DEVICE_TYPE
if /i "%ACTION%"=="DETECT_AND_APPLY"   goto DETECT_AND_APPLY
if /i "%ACTION%"=="CLEAN_TEMP"         goto CLEAN_TEMP

:DETECT_DEVICE_TYPE
echo  [SYSTEM] Detecting device type...

:: Check for battery (WMI)
set "DEVICE_TYPE=DESKTOP"
set "BATTERY_PCT=N/A"
powershell -Command "if(Get-WmiObject Win32_Battery -ErrorAction SilentlyContinue){Write-Host 'LAPTOP'}else{Write-Host 'DESKTOP'}" > "%TEMP%\dev.tmp" 2>nul
set /p DEVICE_TYPE= < "%TEMP%\dev.tmp"
del "%TEMP%\dev.tmp" 2>nul

if /i "%DEVICE_TYPE%"=="LAPTOP" (
    powershell -Command "(Get-WmiObject -Class Win32_Battery -ErrorAction SilentlyContinue).EstimatedChargeRemaining" > "%TEMP%\bat.tmp" 2>nul
    set /p BATTERY_PCT= < "%TEMP%\bat.tmp"
    del "%TEMP%\bat.tmp" 2>nul
    echo  [INFO] Laptop detected. Battery: %BATTERY_PCT%%%
) else (
    echo  [INFO] Desktop detected.
)

:: Detect GPU
set "GPU_VENDOR=Unknown"
set "GPU_NAME=Unknown"
where nvidia-smi >nul 2>&1
if %errorlevel% equ 0 (
    set "GPU_VENDOR=NVIDIA"
    nvidia-smi --query-gpu=name --format=csv,noheader > "%TEMP%\gpu.tmp" 2>nul
    set /p GPU_NAME= < "%TEMP%\gpu.tmp"
    del "%TEMP%\gpu.tmp" 2>nul
) else (
    powershell -Command "(Get-WmiObject Win32_VideoController | Select-Object -First 1).Name" > "%TEMP%\gpu.tmp" 2>nul
    set /p GPU_NAME= < "%TEMP%\gpu.tmp"
    del "%TEMP%\gpu.tmp" 2>nul
    echo %GPU_NAME% | findstr /i "amd radeon" >nul && set "GPU_VENDOR=AMD"
    echo %GPU_NAME% | findstr /i "intel" >nul && set "GPU_VENDOR=Intel"
)
echo  [INFO] GPU: %GPU_NAME% (%GPU_VENDOR%)

:: Detect CPU
set "CPU_NAME=Unknown"
set "CPU_THREADS=0"
powershell -Command "(Get-WmiObject Win32_Processor | Select-Object -First 1).Name" > "%TEMP%\cpu.tmp" 2>nul
set /p CPU_NAME= < "%TEMP%\cpu.tmp"
del "%TEMP%\cpu.tmp" 2>nul
powershell -Command "[Environment]::ProcessorCount" > "%TEMP%\thr.tmp" 2>nul
set /p CPU_THREADS= < "%TEMP%\thr.tmp"
del "%TEMP%\thr.tmp" 2>nul
echo  [INFO] CPU: %CPU_NAME% (%CPU_THREADS% threads)

:: Detect RAM
set "RAM_GB=Unknown"
powershell -Command "[math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory/1GB,1)" > "%TEMP%\ram.tmp" 2>nul
set /p RAM_GB= < "%TEMP%\ram.tmp"
del "%TEMP%\ram.tmp" 2>nul
echo  [INFO] RAM: %RAM_GB% GB

:: Save to device_profile.ini
(
echo [Device]
echo DeviceType=%DEVICE_TYPE%
echo BatteryPercent=%BATTERY_PCT%
echo [GPU]
echo Vendor=%GPU_VENDOR%
echo Name=%GPU_NAME%
echo [CPU]
echo Name=%CPU_NAME%
echo Threads=%CPU_THREADS%
echo [Memory]
echo TotalGB=%RAM_GB%
) > "%BASE_DIR%\config\device_profile.ini"

echo  [OK] Profile saved to config\device_profile.ini

endlocal & (
    set "DEVICE_TYPE=%DEVICE_TYPE%"
    set "GPU_VENDOR=%GPU_VENDOR%"
    set "GPU_NAME=%GPU_NAME%"
    set "CPU_THREADS=%CPU_THREADS%"
    set "RAM_GB=%RAM_GB%"
    set "BATTERY_PCT=%BATTERY_PCT%"
)
goto :EOF

:DETECT_AND_APPLY
call :DETECT_DEVICE_TYPE
echo.
echo  [SYSTEM] Applying device-appropriate settings...
if /i "%DEVICE_TYPE%"=="LAPTOP" (
    echo  [INFO] Laptop mode: balanced power + efficient timer
    call "%~dp0power.bat" SET_BALANCED_LAPTOP
    call "%~dp0timer.bat" SET_EFFICIENT
) else (
    echo  [INFO] Desktop mode: ultimate power + maximum timer
    call "%~dp0power.bat" SET_ULTIMATE
    call "%~dp0timer.bat" SET_MAXIMUM
)
echo  [OK] Device-appropriate settings applied.
goto :EOF

:CLEAN_TEMP
echo  [SYSTEM] Cleaning up temporary files...
call "%~dp0utils.bat" header "CLEAN UP TEMP FILES" >nul 2>&1
del /q /f /s "%TEMP%\*.*" >nul 2>&1
for /d %%x in ("%TEMP%\*") do rd /s /q "%%x" >nul 2>&1

del /q /f /s "C:\Windows\Temp\*.*" >nul 2>&1
for /d %%x in ("C:\Windows\Temp\*") do rd /s /q "%%x" >nul 2>&1

echo  [OK] Temporary files cleaned.
goto :EOF
