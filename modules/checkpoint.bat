@echo off
:: ============================================================
::  checkpoint.bat - Full checkpoint CRUD operations
::  Callable: checkpoint.bat [CREATE|LIST|RESTORE|DELETE|COMPARE|EXPORT|IMPORT] [args...]
:: ============================================================

setlocal EnableDelayedExpansion

if not defined BASE_DIR (
    call "%~dp0_init.bat"
)

set "CP_DIR=%BASE_DIR%\config\checkpoints"
set "INDEX=%CP_DIR%\index.txt"
set "CP_LOG=%BASE_DIR%\logs\checkpoints.log"

set "ACTION=%~1"
set "ARG2=%~2"
set "ARG3=%~3"

if /i "%ACTION%"=="CREATE"  goto CREATE_CHECKPOINT
if /i "%ACTION%"=="LIST"    goto LIST_CHECKPOINTS
if /i "%ACTION%"=="RESTORE" goto RESTORE_CHECKPOINT
if /i "%ACTION%"=="DELETE"  goto DELETE_CHECKPOINT
if /i "%ACTION%"=="COMPARE" goto COMPARE_CHECKPOINTS
if /i "%ACTION%"=="EXPORT"  goto EXPORT_CHECKPOINT
if /i "%ACTION%"=="IMPORT"  goto IMPORT_CHECKPOINT

echo  [ERROR] Unknown checkpoint action: %ACTION%
exit /b 1

:: ============================================================
:CREATE_CHECKPOINT
:: Usage: checkpoint.bat CREATE "Name"
:: ============================================================
setlocal EnableDelayedExpansion
set "CP_NAME=%ARG2%"
if "!CP_NAME!"=="" set "CP_NAME=Manual"

:: Count existing checkpoints for number
set "CP_COUNT=0"
for /f %%i in ('type "%INDEX%" 2^>nul ^| find /c "checkpoint_"') do set "CP_COUNT=%%i"
set /a "CP_NUM=CP_COUNT+1"

:: Generate timestamp via PowerShell
for /f "delims=" %%t in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do set "TS=%%t"
if not defined TS set "TS=%DATE:~-4%%DATE:~3,2%%DATE:~0,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%"
set "TS=%TS: =0%"
set "CP_ID=checkpoint_%CP_NUM%_%TS%"
set "CP_PATH=%CP_DIR%\%CP_ID%"

mkdir "%CP_PATH%" 2>nul

echo.
echo  [CHECKPOINT] Creating checkpoint #%CP_NUM%: %CP_NAME%
echo  [CHECKPOINT] ID: %CP_ID%
echo.

:: Export HKLM registry hive
echo  [*] Exporting HKLM registry hive...
reg export HKLM "%CP_PATH%\hklm.reg" /y >nul 2>&1
if %errorlevel% equ 0 (echo  [OK] HKLM exported) else (echo  [WARN] HKLM export failed)

:: Export HKCU registry hive
echo  [*] Exporting HKCU registry hive...
reg export HKCU "%CP_PATH%\hkcu.reg" /y >nul 2>&1
if %errorlevel% equ 0 (echo  [OK] HKCU exported) else (echo  [WARN] HKCU export failed)

:: Export service states
echo  [*] Exporting service states...
sc query type= all state= all > "%CP_PATH%\services.txt" 2>nul
if %errorlevel% equ 0 (echo  [OK] Services exported) else (echo  [WARN] Services export failed)

:: Export power plan
echo  [*] Exporting power plan...
for /f "tokens=4" %%p in ('powercfg /getactivescheme 2^>nul') do set "ACTIVE_PLAN=%%p"
if defined ACTIVE_PLAN (
    powercfg /export "%CP_PATH%\powerplan.pow" %ACTIVE_PLAN% >nul 2>&1
    echo  [OK] Power plan exported: %ACTIVE_PLAN%
) else (
    echo  [WARN] Could not detect active power plan
)

:: Export network config
echo  [*] Exporting network config...
netsh dump > "%CP_PATH%\network.cfg" 2>nul
if %errorlevel% equ 0 (echo  [OK] Network config exported) else (echo  [WARN] Network export failed)

:: Record timer resolution
echo  [*] Recording timer resolution...
powershell -Command "& { Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public class TR{[DllImport(\"ntdll.dll\")]public static extern int NtQueryTimerResolution(out uint mn,out uint mx,out uint cur);public static string Get(){uint mn,mx,cur;NtQueryTimerResolution(out mn,out mx,out cur);return $\"min={mn} max={mx} current={cur}\";}}'; [TR]::Get() }" > "%CP_PATH%\timer_state.txt" 2>nul
echo  [OK] Timer state recorded

:: Record NVIDIA state
set "NVIDIA_STATE=N/A"
if "%NVIDIA_AVAILABLE%"=="1" (
    echo  [*] Recording NVIDIA state...
    nvidia-smi --query-gpu=name,clocks.gr,clocks.mem,power.limit,temperature.gpu --format=csv,noheader > "%CP_PATH%\nvidia_state.txt" 2>nul
    echo  [OK] NVIDIA state recorded
) else (
    echo N/A > "%CP_PATH%\nvidia_state.txt"
)

:: Detect device type & GPU for metadata
set "DEV_TYPE=UNKNOWN"
powershell -Command "if((Get-WmiObject Win32_Battery -ErrorAction SilentlyContinue)){Write-Host 'LAPTOP'}else{Write-Host 'DESKTOP'}" > "%TEMP%\dev_type.tmp" 2>nul
set /p DEV_TYPE= < "%TEMP%\dev_type.tmp"
del "%TEMP%\dev_type.tmp" 2>nul

set "GPU_VENDOR=Unknown"
if "%NVIDIA_AVAILABLE%"=="1" set "GPU_VENDOR=NVIDIA"

:: Get list of exported files
set "FILES_LIST=hklm.reg,hkcu.reg,services.txt,powerplan.pow,network.cfg,timer_state.txt,nvidia_state.txt"

:: Write metadata.json
(
echo {
echo   "checkpoint_id": "%CP_ID%",
echo   "number": %CP_NUM%,
echo   "name": "%CP_NAME%",
echo   "timestamp": "%TS%",
echo   "user": "%USERNAME%",
echo   "computer": "%COMPUTERNAME%",
echo   "device_type": "%DEV_TYPE%",
echo   "gpu_vendor": "%GPU_VENDOR%",
echo   "files": ["hklm.reg","hkcu.reg","services.txt","powerplan.pow","network.cfg","timer_state.txt","nvidia_state.txt"],
echo   "status": "created",
echo   "modules_applied": []
echo }
) > "%CP_PATH%\metadata.json"

:: Append to index.txt
echo %CP_NUM%^|%CP_ID%^|%CP_NAME%^|%TS:~0,8%^|%DEV_TYPE% >> "%INDEX%"

:: Audit log
echo [%TS%] CREATE #%CP_NUM% "%CP_NAME%" by %USERNAME% >> "%CP_LOG%"

echo.
echo  [CHECKPOINT] Checkpoint #%CP_NUM% created successfully!
echo  [CHECKPOINT] Location: %CP_PATH%
echo.
endlocal
goto :EOF

:: ============================================================
:LIST_CHECKPOINTS
:: ============================================================
setlocal EnableDelayedExpansion
echo.
echo  ============================================================
echo   CHECKPOINT LIST
echo  ============================================================
echo   #  ^| Name                           ^| Date       ^| Device
echo  ----+--------------------------------+------------+--------
set "COUNT=0"
for /f "tokens=1,2,3,4,5 delims=|" %%a in ('type "%INDEX%" 2^>nul ^| findstr /r "^[0-9]"') do (
    set "NUM=%%a"
    set "ID=%%b"
    set /a COUNT+=1
    set "NAME=%%c"
    set "DATE=%%d"
    set "DTYPE=%%e"
    :: Truncate name to 30 chars
    set "NSHORT=!NAME:~0,30!"
    echo   !NUM!  ^| !NSHORT!                           ^| !DATE!     ^| !DTYPE!
)
echo  ============================================================
echo   Total: %COUNT% checkpoint(s)
echo.
endlocal
goto :EOF

:: ============================================================
:RESTORE_CHECKPOINT
:: Usage: checkpoint.bat RESTORE [number]
:: ============================================================
setlocal EnableDelayedExpansion
set "CP_NUM=%ARG2%"
if "!CP_NUM!"=="" (
    set /p "CP_NUM=  Enter checkpoint number to restore: "
)

:: Find checkpoint ID from index
set "CP_ID="
for /f "tokens=1,2 delims=|" %%a in ('type "%INDEX%" 2^>nul ^| findstr /r "^[0-9]"') do (
    if "%%a"=="%CP_NUM%" set "CP_ID=%%b"
)

if "%CP_ID%"=="" (
    echo  [ERROR] Checkpoint #%CP_NUM% not found.
    exit /b 1
)

set "CP_PATH=%CP_DIR%\%CP_ID%"
if not exist "%CP_PATH%" (
    echo  [ERROR] Checkpoint directory not found: %CP_PATH%
    exit /b 1
)

echo.
echo  [RESTORE] About to restore checkpoint #%CP_NUM%: %CP_ID%
echo  [RESTORE] WARNING: This will overwrite current registry and power settings!
echo.
set /p "_confirm=  Type YES to confirm restore: "
if /i not "%_confirm%"=="YES" (
    echo  [CANCELLED] Restore cancelled.
    exit /b 0
)

:: Create safety checkpoint before restore
echo  [RESTORE] Creating safety checkpoint before restore...
call "%~dp0checkpoint.bat" CREATE "PreRestore_Safety_#%CP_NUM%"

:: Import HKLM
echo  [*] Restoring HKLM registry...
if exist "%CP_PATH%\hklm.reg" (
    reg import "%CP_PATH%\hklm.reg" >nul 2>&1
    if %errorlevel% equ 0 (echo  [OK] HKLM restored) else (echo  [WARN] HKLM import had errors)
) else echo  [WARN] HKLM file not found

:: Import HKCU
echo  [*] Restoring HKCU registry...
if exist "%CP_PATH%\hkcu.reg" (
    reg import "%CP_PATH%\hkcu.reg" >nul 2>&1
    if %errorlevel% equ 0 (echo  [OK] HKCU restored) else (echo  [WARN] HKCU import had errors)
) else echo  [WARN] HKCU file not found

:: Import power plan
echo  [*] Restoring power plan...
if exist "%CP_PATH%\powerplan.pow" (
    powercfg /import "%CP_PATH%\powerplan.pow" >nul 2>&1
    echo  [OK] Power plan imported (manual activation may be needed)
) else echo  [WARN] Power plan file not found

:: Service restoration notice
echo.
echo  [INFO] Services file preserved at: %CP_PATH%\services.txt
echo  [INFO] Manual service restoration may be needed for changed services.

:: Reset GPU clocks if NVIDIA
if "%NVIDIA_AVAILABLE%"=="1" (
    echo  [*] Resetting NVIDIA clocks to default...
    nvidia-smi --reset-gpu-clocks >nul 2>&1
    nvidia-smi --reset-memory-clocks >nul 2>&1
    echo  [OK] GPU clocks reset
)

:: Update metadata
for /f "delims=" %%t in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do set "TS2=%%t"
echo   ^, "restored_date": "%TS2%" >> "%CP_PATH%\metadata.json"

:: Audit log
echo [%TS2%] RESTORE #%CP_NUM% by %USERNAME% >> "%CP_LOG%"

echo.
echo  [RESTORE] Checkpoint #%CP_NUM% restored successfully!
echo  [INFO] A restart may be required for all changes to take effect.
echo.
endlocal
goto :EOF

:: ============================================================
:COMPARE_CHECKPOINTS
:: Usage: checkpoint.bat COMPARE [num1] [num2]
:: ============================================================
setlocal EnableDelayedExpansion
set "NUM1=%ARG2%"
set "NUM2=%ARG3%"
if "!NUM1!"=="" set /p "NUM1=  First checkpoint number: "
if "!NUM2!"=="" set /p "NUM2=  Second checkpoint number: "

:: Call PowerShell engine
powershell -ExecutionPolicy Bypass -File "%~dp0checkpoint_engine.ps1" -Compare -CP1 %NUM1% -CP2 %NUM2% -BaseDir "%BASE_DIR%"
endlocal
goto :EOF

:: ============================================================
:DELETE_CHECKPOINT
:: Usage: checkpoint.bat DELETE [number]
:: ============================================================
setlocal EnableDelayedExpansion
set "CP_NUM=%ARG2%"
if "!CP_NUM!"=="" set /p "CP_NUM=  Enter checkpoint number to delete: "

set "CP_ID="
for /f "tokens=1,2 delims=|" %%a in ('type "%INDEX%" 2^>nul ^| findstr /r "^[0-9]"') do (
    if "%%a"=="%CP_NUM%" set "CP_ID=%%b"
)

if "%CP_ID%"=="" (
    echo  [ERROR] Checkpoint #%CP_NUM% not found.
    exit /b 1
)

echo.
echo  [DELETE] About to delete checkpoint #%CP_NUM%: %CP_ID%
set /p "_confirm=  Type YES to confirm deletion: "
if /i not "%_confirm%"=="YES" (
    echo  [CANCELLED] Deletion cancelled.
    exit /b 0
)

set "CP_PATH=%CP_DIR%\%CP_ID%"
if exist "%CP_PATH%" (
    rd /s /q "%CP_PATH%"
    echo  [OK] Checkpoint directory deleted
)

:: Remove from index.txt - rebuild without the deleted entry
set "TMPIDX=%TEMP%\cp_index_tmp_%RANDOM%.txt"
type nul > "%TMPIDX%"
for /f "usebackq delims=" %%L in ("%INDEX%") do (
    for /f "tokens=1 delims=|" %%n in ("%%L") do (
        if not "%%n"=="%CP_NUM%" echo %%L>> "%TMPIDX%"
    )
)
move /y "%TMPIDX%" "%INDEX%" >nul 2>&1

:: Audit log
for /f "delims=" %%t in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do set "TS3=%%t"
echo [%TS3%] DELETE #%CP_NUM% by %USERNAME% >> "%CP_LOG%"

echo  [OK] Checkpoint #%CP_NUM% deleted.
endlocal
goto :EOF

:: ============================================================
:EXPORT_CHECKPOINT
:: Usage: checkpoint.bat EXPORT [number] [output_path]
:: ============================================================
setlocal EnableDelayedExpansion
set "CP_NUM=%ARG2%"
set "OUT_PATH=%ARG3%"
if "!CP_NUM!"=="" set /p "CP_NUM=  Checkpoint number to export: "
if "!OUT_PATH!"=="" set /p "OUT_PATH=  Output path (e.g. C:\Backup\): "

set "CP_ID="
for /f "tokens=1,2 delims=|" %%a in ('type "%INDEX%" 2^>nul ^| findstr /r "^[0-9]"') do (
    if "%%a"=="%CP_NUM%" set "CP_ID=%%b"
)

if "%CP_ID%"=="" (echo  [ERROR] Checkpoint not found. & exit /b 1)

set "CP_PATH=%CP_DIR%\%CP_ID%"
set "ZIP_FILE=%OUT_PATH%\%CP_ID%.zip"

powershell -Command "Compress-Archive -Path '%CP_PATH%' -DestinationPath '%ZIP_FILE%' -Force"
if %errorlevel% equ 0 (
    echo  [OK] Exported to: %ZIP_FILE%
) else (
    echo  [ERROR] Export failed.
)
endlocal
goto :EOF

:: ============================================================
:IMPORT_CHECKPOINT
:: Usage: checkpoint.bat IMPORT [zipfile]
:: ============================================================
setlocal EnableDelayedExpansion
set "ZIP_FILE=%~1"
if "%ZIP_FILE%"=="" set /p "ZIP_FILE=  Path to checkpoint ZIP: "

if not exist "%ZIP_FILE%" (echo  [ERROR] File not found: %ZIP_FILE% & exit /b 1)

echo  [*] Extracting checkpoint...
powershell -Command "Expand-Archive -Path '%ZIP_FILE%' -DestinationPath '%CP_DIR%' -Force"

:: Find extracted folder
for /d %%d in ("%CP_DIR%\checkpoint_*") do (
    set "IMPORTED_ID=%%~nd"
    set "IMPORTED_PATH=%%d"
)

:: Read metadata and add to index
if defined IMPORTED_ID (
    :: Parse basic info from metadata
    set "IMP_NUM=0"
    set "IMP_NAME=Imported"
    set "IMP_DATE=Unknown"
    set "IMP_TYPE=Unknown"

    for /f "tokens=1,2 delims=:" %%k in ('type "!IMPORTED_PATH!\metadata.json" 2^>nul ^| findstr "number name timestamp device_type"') do (
        set "_k=%%k"
        set "_v=%%l"
    )

    :: Find next available number
    set "MAX_NUM=0"
    for /f "tokens=1 delims=|" %%a in ('type "%INDEX%" 2^>nul ^| findstr /r "^[0-9]"') do (
        if %%a GTR !MAX_NUM! set "MAX_NUM=%%a"
    )
    set /a "IMP_NUM=MAX_NUM+1"

    echo !IMP_NUM!^|!IMPORTED_ID!^|Imported^|Unknown^|Unknown >> "%INDEX%"
    echo  [OK] Checkpoint imported as #!IMP_NUM!: !IMPORTED_ID!
) else (
    echo  [WARN] Could not confirm extracted checkpoint.
)
endlocal
goto :EOF
