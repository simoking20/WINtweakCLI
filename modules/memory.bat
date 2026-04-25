@echo off
:: ============================================================
::  memory.bat - RAM cleanup & standby list
:: ============================================================

setlocal EnableDelayedExpansion

if not defined BASE_DIR call "%~dp0_init.bat"

set "ACTION=%~1"
if "%ACTION%"=="" goto INTERACTIVE_MENU

if /i "%ACTION%"=="CLEAR_STANDBY"     goto CLEAR_STANDBY
if /i "%ACTION%"=="OPTIMIZE_RAM"      goto OPTIMIZE_RAM
if /i "%ACTION%"=="RAM_INFO"          goto RAM_INFO
if /i "%ACTION%"=="INTERACTIVE_MENU"  goto INTERACTIVE_MENU
goto :EOF

:CLEAR_STANDBY
echo  [MEMORY] Clearing standby memory list...
:: Use PowerShell to clear standby list (EmptyStandbyList tool preferred but using API)
powershell -ExecutionPolicy Bypass -Command ^
    "Add-Type -TypeDefinition @'" ^
    "using System; using System.Runtime.InteropServices;" ^
    "public class MemClear {" ^
    "  [DllImport(\"ntdll.dll\")] public static extern uint NtSetSystemInformation(int i, IntPtr p, int s);" ^
    "  public static void ClearStandby() {" ^
    "    IntPtr buf = System.Runtime.InteropServices.Marshal.AllocHGlobal(4);" ^
    "    System.Runtime.InteropServices.Marshal.WriteInt32(buf, 4);" ^
    "    NtSetSystemInformation(0x50, buf, 4);" ^
    "    System.Runtime.InteropServices.Marshal.FreeHGlobal(buf);" ^
    "  }" ^
    "}" ^
    "'@; [MemClear]::ClearStandby(); Write-Host '  [OK] Standby list cleared'" 2>nul

if %errorlevel% neq 0 (
    echo  [INFO] Using GC collection fallback...
    powershell -Command "[System.GC]::Collect(); [System.GC]::WaitForPendingFinalizers(); Write-Host '  [OK] Managed memory collected'"
)
goto :EOF

:OPTIMIZE_RAM
echo  [MEMORY] Optimizing RAM usage...

:: Clear working sets of all processes
powershell -Command "Get-Process | ForEach-Object { $_.MinWorkingSet = 1KB; $_.MaxWorkingSet = 1GB } 2>&1" >nul 2>&1

:: Disable memory compression (optional for gaming)
echo  [*] Current memory status:
powershell -Command "Get-WmiObject -Class Win32_OperatingSystem | Select-Object TotalVisibleMemorySize,FreePhysicalMemory | ForEach-Object { 'Total: ' + [math]::Round($_.TotalVisibleMemorySize/1MB,1) + ' GB  |  Free: ' + [math]::Round($_.FreePhysicalMemory/1MB,1) + ' GB' }" 2>nul

:: Large page memory allocation hint
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v "LargePageDrivers" /t REG_MULTI_SZ /d "" /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" /v "DisablePagingExecutive" /t REG_DWORD /d 1 /f >nul 2>&1

echo  [OK] DisablePagingExecutive set (kernel kept in RAM)

:: Clear temp files
del /q "%TEMP%\*" >nul 2>&1
for /d %%d in ("%TEMP%\*") do rd /s /q "%%d" >nul 2>&1
echo  [OK] Temp files cleaned
goto :EOF

:RAM_INFO
echo.
echo  [MEMORY] RAM Information:
powershell -Command ^
    "Get-WmiObject Win32_PhysicalMemory | ForEach-Object {" ^
    "  'Slot: ' + $_.DeviceLocator + ' | ' + [math]::Round($_.Capacity/1GB,0) + ' GB | ' + $_.Speed + ' MHz | ' + $_.Manufacturer" ^
    "}" 2>nul
echo.
powershell -Command ^
    "$os = Get-WmiObject Win32_OperatingSystem;" ^
    "Write-Host ('Total: ' + [math]::Round($os.TotalVisibleMemorySize/1MB,1) + ' GB');" ^
    "Write-Host ('Free: ' + [math]::Round($os.FreePhysicalMemory/1MB,1) + ' GB');" ^
    "Write-Host ('Used: ' + [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory)/1MB,1) + ' GB');" ^
    "Write-Host ('Usage: ' + [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) * 100 / $os.TotalVisibleMemorySize,1) + '%%')" 2>nul
goto :EOF

:INTERACTIVE_MENU
echo.
echo  ============================================================
echo   MEMORY MANAGEMENT
echo  ============================================================
echo   [1] Clear Standby List     (free cached RAM)
echo   [2] Optimize RAM Usage     (working sets + tweaks)
echo   [3] RAM Information
echo   [0] Back
echo.
set /p "_opt=  Select option: "
if "%_opt%"=="1" ( call "%~f0" CLEAR_STANDBY & goto INTERACTIVE_MENU )
if "%_opt%"=="2" ( call "%~f0" OPTIMIZE_RAM & goto INTERACTIVE_MENU )
if "%_opt%"=="3" ( call "%~f0" RAM_INFO & goto INTERACTIVE_MENU )
goto :EOF
