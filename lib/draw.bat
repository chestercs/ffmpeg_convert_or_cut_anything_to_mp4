@echo off
if "%~1"=="" goto :EOF
goto %~1

REM ============================================================
REM lib\draw.bat  -  ANSI color and terminal drawing helpers
REM Requires Windows 10/11 (VT100 support).
REM Call convention: call "%~dp0lib\draw.bat" :LABEL_NAME  arg2
REM ============================================================

REM ============================================================
REM INIT_COLORS
REM   Enables VT processing and defines all _C* color variables.
REM   Call once at script startup before any other draw function.
REM ============================================================
:INIT_COLORS
for /f %%a in ('echo prompt $E^| cmd') do set "_ESC=%%a"
reg add HKCU\Console /v VirtualTerminalLevel /t REG_DWORD /d 1 /f >nul 2>&1
set "_C0=%_ESC%[0m"
set "_CB=%_ESC%[1m"
set "_CC=%_ESC%[96m"
set "_CY=%_ESC%[93m"
set "_CG=%_ESC%[92m"
set "_CR=%_ESC%[91m"
set "_CW=%_ESC%[97m"
set "_CGr=%_ESC%[90m"
exit /b 0

REM ============================================================
REM HEADER_CONVERT  -  banner for convert_or_cut_to_mp4.bat
REM HEADER_AUDIO    -  banner for add_audio_to_mp4.bat
REM ============================================================
:HEADER_CONVERT
echo.
echo %_CC%  ======================================================%_C0%
echo   %_CB%%_CW%ChesTeRcs VegasVibe%_C0%  %_CGr%^|%_C0%  %_CY%FFmpeg Converter%_C0%  %_CGr%^| v0.2.0%_C0%
echo %_CC%  ======================================================%_C0%
echo.
exit /b 0

:HEADER_AUDIO
echo.
echo %_CC%  ======================================================%_C0%
echo   %_CB%%_CW%ChesTeRcs VegasVibe%_C0%  %_CGr%^|%_C0%  %_CY%Music on Video%_C0%  %_CGr%^| v0.2.0%_C0%
echo %_CC%  ======================================================%_C0%
echo.
exit /b 0

REM ============================================================
REM SECTION %2=label
REM   Prints a colored section divider line with label.
REM ============================================================
:SECTION
echo.
echo   %_CC%-%_C0% %_CB%%_CY%%~2 %_CC%------------------------------------------------%_C0%
echo.
exit /b 0

REM ============================================================
REM OK %2=message
REM   Green success message.
REM ============================================================
:OK
echo.
echo %_CG%%_CB%  ^>  Done.%_C0%  %_CW%%~2%_C0%
echo.
exit /b 0

REM ============================================================
REM FAIL_MSG
REM   Red failure message with tip line.
REM ============================================================
:FAIL_MSG
echo.
echo %_CR%%_CB%  ^!  Error:%_C0%  processing failed for the selected backend.
echo %_CGr%     Tip: try CPU mode if a GPU backend fails.%_C0%
exit /b 0

REM ============================================================
REM MENUITEM %2=number %3=label %4=note
REM   Prints one menu row:  [N]  label  (note)
REM ============================================================
:MENUITEM
echo   %_CC%%_CB%[%~2]%_C0%  %_CW%%~3%_C0%  %_CGr%%~4%_C0%
exit /b 0

REM ============================================================
REM KV %2=key %3=value
REM   Prints a summary key/value pair line.
REM ============================================================
:KV
echo   %_CGr%%~2%_C0%  %_CW%%~3%_C0%
exit /b 0
