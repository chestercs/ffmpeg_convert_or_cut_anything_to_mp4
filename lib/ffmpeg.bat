@echo off
if "%~1"=="" goto :EOF
goto %~1

REM ============================================================
REM lib\ffmpeg.bat  —  FFmpeg discovery, install, duration probe
REM
REM Call convention:
REM   call "%~dp0lib\ffmpeg.bat" :LABEL_NAME  arg2  arg3
REM   actual args start at %2
REM ============================================================

REM ============================================================
REM :FIND_FFMPEG
REM   Searches for ffmpeg.exe and sets FFMPEG_EXE if found.
REM   Search order: PATH → WinGet links → WinGet packages → Program Files
REM   No args.
REM ============================================================
:FIND_FFMPEG
set "FFMPEG_EXE="
for %%P in (ffmpeg.exe) do (
  if not defined FFMPEG_EXE set "FFMPEG_EXE=%%~$PATH:P"
)
if not defined FFMPEG_EXE if exist "%LOCALAPPDATA%\Microsoft\WinGet\Links\ffmpeg.exe" (
  set "FFMPEG_EXE=%LOCALAPPDATA%\Microsoft\WinGet\Links\ffmpeg.exe"
)
if not defined FFMPEG_EXE if exist "%LOCALAPPDATA%\Microsoft\WinGet\Packages" (
  for /f "delims=" %%F in ('where /r "%LOCALAPPDATA%\Microsoft\WinGet\Packages" ffmpeg.exe 2^>nul') do (
    if exist "%%~fF" (
      set "FFMPEG_EXE=%%~fF"
      goto :_FF_FIND_DONE
    )
  )
)
if not defined FFMPEG_EXE if exist "%ProgramFiles%\ffmpeg\bin\ffmpeg.exe" (
  set "FFMPEG_EXE=%ProgramFiles%\ffmpeg\bin\ffmpeg.exe"
)
:_FF_FIND_DONE
exit /b 0

REM ============================================================
REM :ENSURE_FFMPEG
REM   Finds or installs FFmpeg via winget.
REM   Sets FF and FFPROBE on success.
REM   errorlevel 1 on failure / user abort.
REM   No args.
REM ============================================================
:ENSURE_FFMPEG
call :FIND_FFMPEG
if defined FFMPEG_EXE goto :_EF_OK

echo.
echo [ERROR] FFmpeg was not found on this system.
echo.
set "ans=Y"
set /p "ans=Install via winget? [Y/N] (Default: Y): "
if /I "%ans%"=="N" (
  echo.
  echo Aborted.
  exit /b 1
)

where winget >nul 2>&1
if errorlevel 1 (
  echo.
  echo [!] winget is not available. Please install "App Installer" from Microsoft Store.
  exit /b 1
)

echo.
echo Installing FFmpeg with winget...
winget install --id Gyan.FFmpeg -e --source winget
if errorlevel 1 (
  echo.
  echo [!] Installation failed.
  exit /b 1
)

set "FFMPEG_EXE="
call :FIND_FFMPEG
if not defined FFMPEG_EXE (
  echo.
  echo [!] FFmpeg installed, but PATH did not refresh in this window.
  echo     Close this terminal and rerun the script.
  exit /b 1
)

:_EF_OK
set "FF=%FFMPEG_EXE%"
if not defined FF set "FF=ffmpeg"
echo [INFO] Using FFmpeg: "%FF%"
set "FFPROBE=ffprobe"
for %%D in ("%FFMPEG_EXE%") do if exist "%%~dpDffprobe.exe" set "FFPROBE=%%~dpDffprobe.exe"
echo [INFO] Using FFprobe: "%FFPROBE%"
exit /b 0

REM ============================================================
REM :PROBE_DURATION
REM   Reads media file duration via ffprobe.
REM   Requires FF and FFPROBE to be set (call :ENSURE_FFMPEG first).
REM   %2 = file path
REM   %3 = output variable name for integer seconds
REM   %4 = output variable name for HH:MM:SS string
REM   errorlevel 1 if duration cannot be determined
REM ============================================================
:PROBE_DURATION
setlocal EnableExtensions DisableDelayedExpansion
set "probe_file=%~2"
set "dur_raw="
set "dur_sec="
set "TMPDUR=%TEMP%\ffprobe_dur_%RANDOM%_%RANDOM%.txt"
set "TMPDBG=%TEMP%\ffprobe_dbg_%RANDOM%_%RANDOM%.txt"

if exist "%TMPDUR%" del /q "%TMPDUR%" >nul 2>&1
if exist "%TMPDBG%" del /q "%TMPDBG%" >nul 2>&1

"%FFPROBE%" -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "%probe_file%" 1>"%TMPDUR%" 2>"%TMPDBG%"
for %%# in ("%TMPDUR%") do if %%~z# LSS 2 (
  "%FFPROBE%" -v error -show_entries format=duration -of csv=p=0 "%probe_file%" 1>"%TMPDUR%" 2>>"%TMPDBG%"
)

if exist "%TMPDUR%" set /p "dur_raw=" < "%TMPDUR%"
for /f "tokens=* delims= " %%A in ("%dur_raw%") do set "dur_raw=%%A"
if defined dur_raw for /f "tokens=1 delims=., " %%E in ("%dur_raw%") do set "dur_sec=%%E"
for /f "delims=0123456789" %%Z in ("%dur_sec%") do set "dur_sec="
if not defined dur_sec set "dur_sec=0"

if exist "%TMPDUR%" del /q "%TMPDUR%" >nul 2>&1
if exist "%TMPDBG%" del /q "%TMPDBG%" >nul 2>&1

if %dur_sec% LEQ 0 endlocal & exit /b 1

call "%~dp0time.bat" :SEC_TO_HMS %dur_sec% dur_hms
endlocal & set "%~3=%dur_sec%" & set "%~4=%dur_hms%" & exit /b 0
