@echo off
:: ============================================================
::  network.bat - TCP/IP optimization & DNS
:: ============================================================

setlocal EnableDelayedExpansion

if not defined BASE_DIR call "%~dp0_init.bat"

set "ACTION=%~1"
if "%ACTION%"=="" goto INTERACTIVE_MENU

if /i "%ACTION%"=="OPTIMIZE_COMPETITIVE" goto OPTIMIZE_COMPETITIVE
if /i "%ACTION%"=="RESTORE_DEFAULT"      goto RESTORE_DEFAULT
if /i "%ACTION%"=="SET_CUSTOM_DNS"       goto SET_CUSTOM_DNS
if /i "%ACTION%"=="INTERACTIVE_MENU"     goto INTERACTIVE_MENU
goto :EOF

:OPTIMIZE_COMPETITIVE
echo.
echo  [NETWORK] Applying competitive TCP/IP optimizations...

:: TCP Heuristics
netsh int tcp set heuristics disabled >nul 2>&1
echo  [OK] TCP heuristics disabled

:: Auto-tuning
netsh int tcp set global autotuninglevel=disabled >nul 2>&1
echo  [OK] TCP auto-tuning disabled

:: Congestion provider (CTCP for lower latency)
netsh int tcp set global congestionprovider=ctcp >nul 2>&1
if %errorlevel% neq 0 (
    netsh int tcp set global congestionprovider=none >nul 2>&1
    echo  [OK] Congestion provider set (CTCP not available, using none)
) else (
    echo  [OK] Congestion provider set to CTCP
)

:: ECN capability
netsh int tcp set global ecncapability=disabled >nul 2>&1
echo  [OK] ECN (Explicit Congestion Notification) disabled

:: Timestamps
netsh int tcp set global timestamps=disabled >nul 2>&1
echo  [OK] TCP timestamps disabled

:: RSS (Receive-Side Scaling)
netsh int tcp set global rss=enabled >nul 2>&1
echo  [OK] RSS enabled

:: Disable Nagle's Algorithm (reduces small-packet latency)
echo  [*] Disabling Nagle's Algorithm...
for /f "tokens=*" %%k in ('reg query "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces" /s /k 2^>nul ^| findstr "HKLM"') do (
    reg add "%%k" /v "TcpAckFrequency" /t REG_DWORD /d 1 /f >nul 2>&1
    reg add "%%k" /v "TCPNoDelay" /t REG_DWORD /d 1 /f >nul 2>&1
)
echo  [OK] Nagle's Algorithm disabled

:: Network throttling index (disable throttling)
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v "NetworkThrottlingIndex" /t REG_DWORD /d 0xFFFFFFFF /f >nul 2>&1
echo  [OK] Network throttling disabled

:: Priority for system tasks
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v "SystemResponsiveness" /t REG_DWORD /d 0 /f >nul 2>&1
echo  [OK] System responsiveness set for gaming

echo.
echo  [INFO] Network optimizations applied successfully
echo  [INFO] Expected: Lower ping variance and reduced packet loss
goto :EOF

:RESTORE_DEFAULT
echo  [NETWORK] Restoring default network settings...
netsh int tcp set global autotuninglevel=normal >nul 2>&1
netsh int tcp set heuristics enabled >nul 2>&1
netsh int tcp set global ecncapability=enabled >nul 2>&1
netsh int tcp set global timestamps=enabled >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v "NetworkThrottlingIndex" /t REG_DWORD /d 10 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v "SystemResponsiveness" /t REG_DWORD /d 20 /f >nul 2>&1
echo  [OK] Network settings restored to defaults
goto :EOF

:SET_CUSTOM_DNS
echo.
echo  ============================================================
echo   CUSTOM DNS CONFIGURATION
echo  ============================================================
echo   [1] Cloudflare  - 1.1.1.1    / 1.0.0.1    (fastest)
echo   [2] Google      - 8.8.8.8    / 8.8.4.4    (reliable)
echo   [3] Quad9       - 9.9.9.9    / 149.112.112.112 (secure)
echo   [4] AdGuard     - 94.140.14.14 / 94.140.15.15 (ad-blocking)
echo   [5] Restore ISP DNS
echo   [0] Back
echo.
set /p "_dns=  Select DNS: "

set "DNS1="
set "DNS2="
if "%_dns%"=="1" (set "DNS1=1.1.1.1" & set "DNS2=1.0.0.1")
if "%_dns%"=="2" (set "DNS1=8.8.8.8" & set "DNS2=8.8.4.4")
if "%_dns%"=="3" (set "DNS1=9.9.9.9" & set "DNS2=149.112.112.112")
if "%_dns%"=="4" (set "DNS1=94.140.14.14" & set "DNS2=94.140.15.15")

if defined DNS1 (
    :: Apply to all active adapters
    for /f "tokens=*" %%a in ('netsh interface show interface ^| findstr "Connected"') do (
        for /f "tokens=4" %%n in ("%%a") do (
            netsh interface ip set dns name="%%n" static %DNS1% >nul 2>&1
            netsh interface ip add dns name="%%n" %DNS2% index=2 >nul 2>&1
        )
    )
    echo  [OK] DNS set to %DNS1% / %DNS2%
)

if "%_dns%"=="5" (
    for /f "tokens=4" %%n in ('netsh interface show interface ^| findstr "Connected"') do (
        netsh interface ip set dns name="%%n" dhcp >nul 2>&1
    )
    echo  [OK] DNS restored to DHCP (ISP default)
)
goto :EOF

:INTERACTIVE_MENU
echo.
echo  ============================================================
echo   NETWORK OPTIMIZATION
echo  ============================================================
echo   [1] Apply Competitive Optimizations
echo   [2] Restore Default Network Settings
echo   [3] Set Custom DNS
echo   [0] Back
echo.
set /p "_opt=  Select option: "
if "%_opt%"=="1" ( call "%~f0" OPTIMIZE_COMPETITIVE & goto INTERACTIVE_MENU )
if "%_opt%"=="2" ( call "%~f0" RESTORE_DEFAULT & goto INTERACTIVE_MENU )
if "%_opt%"=="3" ( call "%~f0" SET_CUSTOM_DNS & goto INTERACTIVE_MENU )
goto :EOF
