@echo off
if "%~1"=="" goto :EOF
goto %~1

REM ============================================================
REM lib\time.bat  —  time conversion utilities
REM
REM Call convention:
REM   call "%~dp0lib\time.bat" :LABEL_NAME  arg2  arg3
REM   %1 = label to dispatch to (kept as %1 inside the sub)
REM   actual args start at %2
REM ============================================================

REM ============================================================
REM :HMS_TO_SEC
REM   Converts HH:MM:SS to integer seconds.
REM   Validates that minutes and seconds are 0-59.
REM   %2 = "HH:MM:SS" (quoted)
REM   %3 = output variable name
REM   errorlevel 1 on invalid format
REM ============================================================
:HMS_TO_SEC
setlocal EnableDelayedExpansion
set "in=%~2"
set "in=!in: =!"
for /f "tokens=1-3 delims=:" %%a in ("!in!") do (
  set "H=%%a" & set "M=%%b" & set "S=%%c"
)
echo.!H!.!M!.!S!| findstr /r "^[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$" >nul || ( endlocal & exit /b 1 )
for /f "tokens=* delims=0" %%x in ("!H!") do set "H=%%x"
for /f "tokens=* delims=0" %%x in ("!M!") do set "M=%%x"
for /f "tokens=* delims=0" %%x in ("!S!") do set "S=%%x"
if "!H!"=="" set "H=0"
if "!M!"=="" set "M=0"
if "!S!"=="" set "S=0"
set /a _H=!H!+0, _M=!M!+0, _S=!S!+0
if !_M! LSS 0  endlocal & exit /b 1
if !_S! LSS 0  endlocal & exit /b 1
if !_M! GEQ 60 endlocal & exit /b 1
if !_S! GEQ 60 endlocal & exit /b 1
set /a total=_H*3600 + _M*60 + _S
endlocal & set "%~3=%total%" & exit /b 0

REM ============================================================
REM :SEC_TO_HMS
REM   Converts integer seconds to zero-padded HH:MM:SS.
REM   %2 = seconds (integer)
REM   %3 = output variable name
REM ============================================================
:SEC_TO_HMS
setlocal EnableDelayedExpansion
set /a _T=%~2
if !_T! LSS 0 set /a _T=0
set /a H=_T/3600, R=_T%%3600, M=R/60, S=R%%60
set "HH=0!H!" & set "MM=0!M!" & set "SS=0!S!"
set "HH=!HH:~-2!" & set "MM=!MM:~-2!" & set "SS=!SS:~-2!"
endlocal & set "%~3=%HH%:%MM%:%SS%" & exit /b 0
