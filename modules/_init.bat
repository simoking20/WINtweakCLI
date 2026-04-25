@echo off
:: ============================================================
::  _init.bat - Admin check, directory creation, initialization
:: ============================================================

setlocal EnableDelayedExpansion

:: ---- Set base directory (project root) ----
set "BASE_DIR=%~dp0.."
pushd "%BASE_DIR%"
set "BASE_DIR=%CD%"
popd

:: ---- Admin Privilege Check ----
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo  [ERROR] Administrator privileges required!
    echo  Please right-click and select "Run as administrator"
    echo.
    pause
    exit /b 1
)

:: ---- Directory Creation ----
if not exist "%BASE_DIR%\config"               mkdir "%BASE_DIR%\config"
if not exist "%BASE_DIR%\config\checkpoints"   mkdir "%BASE_DIR%\config\checkpoints"
if not exist "%BASE_DIR%\config\profiles"      mkdir "%BASE_DIR%\config\profiles"
if not exist "%BASE_DIR%\logs"                 mkdir "%BASE_DIR%\logs"
if not exist "%BASE_DIR%\config\checkpoints\index.txt" (
    type nul > "%BASE_DIR%\config\checkpoints\index.txt"
)

:: ---- Timestamp Generation (PowerShell-safe) ----
for /f "delims=" %%t in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do set "LOG_TIMESTAMP=%%t"
if not defined LOG_TIMESTAMP set "LOG_TIMESTAMP=%DATE:~-4%%DATE:~3,2%%DATE:~0,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%"
set "LOG_TIMESTAMP=%LOG_TIMESTAMP: =0%"
set "TIMESTAMP=%LOG_TIMESTAMP%"

:: ---- Log File Initialization ----
set "LOGFILE=%BASE_DIR%\logs\wtweak_%LOG_TIMESTAMP%.log"
(
  echo ============================================================
  echo  WinTweak CLI v3.0 - Session Log
  echo  Started: %LOG_TIMESTAMP%
  echo  User: %USERNAME%  Computer: %COMPUTERNAME%
  echo ============================================================
) > "%LOGFILE%"

:: ---- Dependency Check: PowerShell ----
where powershell >nul 2>&1
if %errorlevel% neq 0 (
    echo  [ERROR] PowerShell not found. Some features will be unavailable.
) else (
    :: Set execution policy for this session
    powershell -Command "Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force" >nul 2>&1
)

:: ---- Dependency Check: nvidia-smi ----
set "NVIDIA_AVAILABLE=0"
where nvidia-smi >nul 2>&1
if %errorlevel% equ 0 set "NVIDIA_AVAILABLE=1"

:: ---- Export globals ----
endlocal & (
    set "BASE_DIR=%BASE_DIR%"
    set "LOG_TIMESTAMP=%LOG_TIMESTAMP%"
    set "TIMESTAMP=%TIMESTAMP%"
    set "LOGFILE=%LOGFILE%"
    set "NVIDIA_AVAILABLE=%NVIDIA_AVAILABLE%"
)
exit /b 0
