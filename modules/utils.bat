@echo off
:: ============================================================
::  utils.bat - Header display & utilities for WinTweak CLI
:: ============================================================

goto :EOF

:HEADER
:: Usage: call utils.bat HEADER "Title"
setlocal
set "TITLE=%~1"
echo.
echo  +================================================+
echo  ^|                                                ^|
echo  ^|   %-46s^|
echo  ^|                                                ^|
echo  +================================================+
echo.
endlocal
goto :EOF

:LOG
:: Usage: call utils.bat LOG "message"
setlocal
set "MSG=%~1"
set "LOGFILE=%BASE_DIR%\logs\wtweak_default.log"
    for /f "delims=" %%t in ('powershell -NoProfile -Command "Get-Date -Format HH:mm:ss" 2^>nul') do set "TS=%%t"
echo [%TS%] %MSG% >> "%LOGFILE%" 2>nul
echo [LOG] %MSG%
endlocal
goto :EOF

:PAUSE_MSG
echo.
echo  Press any key to continue...
pause >nul
goto :EOF

:COLOR_GREEN
echo [92m%~1[0m
goto :EOF

:COLOR_RED
echo [91m%~1[0m
goto :EOF

:COLOR_YELLOW
echo [93m%~1[0m
goto :EOF

:GET_TIMESTAMP
:: Sets global TIMESTAMP variable YYYYMMDD_HHmmss
for /f "delims=" %%t in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do set "TIMESTAMP=%%t"
if not defined TIMESTAMP set "TIMESTAMP=%DATE:~-4%%DATE:~3,2%%DATE:~0,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%"
set "TIMESTAMP=%TIMESTAMP: =0%"
goto :EOF

:CONFIRM_YES
:: Usage: call CONFIRM_YES "message"  => sets CONFIRMED=1 or 0
setlocal
set "CONFIRMED=0"
set /p "_ans=  %~1 (type YES to confirm): "
if /i "%_ans%"=="YES" set "CONFIRMED=1"
endlocal & set "CONFIRMED=%CONFIRMED%"
goto :EOF
