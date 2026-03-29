@echo off
if "%~1"=="" goto :EOF
goto %~1

REM ============================================================
REM lib\ui.bat   -   shared interactive UI helpers
REM
REM Call convention:
REM   call "%~dp0lib\ui.bat" :LABEL_NAME  arg2  arg3
REM   actual args start at %2
REM ============================================================

REM ============================================================
REM ESCAPE_PATH
REM   Reads the value of a named variable, escapes CMD special
REM   characters (^ & | < > ( )) and stores the result.
REM   %2 = input variable name  (e.g. infile)
REM   %3 = output variable name (e.g. infile_esc)
REM ============================================================
:ESCAPE_PATH
call set "_ep=%%%~2%%"
set "_ep=%_ep:^=^^%"
set "_ep=%_ep:&=^&%"
set "_ep=%_ep:|=^|%"
set "_ep=%_ep:<=^<%"
set "_ep=%_ep:>=^>%"
set "_ep=%_ep:(=^(%"
set "_ep=%_ep:)=^)%"
set "%~3=%_ep%"
set "_ep="
exit /b 0

REM ============================================================
REM ASK_PRESET_AND_CODEC
REM   Prompts for encoder preset and video codec.
REM   Requires FF to be set.
REM   %2 = "simple" -> shorter header (used by add_audio_to_mp4)
REM   Sets: x_preset, vcodec, vcrf, codec_label
REM ============================================================
:ASK_PRESET_AND_CODEC
set "x_preset=veryfast"
call "%~dp0draw.bat" :SECTION "ENCODER PRESET"
if /i "%~2"=="simple" (
  echo   %_CGr%Select how hard the encoder works ^(slower = smaller file, same quality^)%_C0%
) else (
  echo   %_CGr%Select encoder preset ^(slower = better compression at the same quality^)%_C0%
)
echo.
call "%~dp0draw.bat" :MENUITEM "1" "ultrafast"
call "%~dp0draw.bat" :MENUITEM "2" "superfast"
call "%~dp0draw.bat" :MENUITEM "3" "veryfast " "(default)"
call "%~dp0draw.bat" :MENUITEM "4" "faster   "
call "%~dp0draw.bat" :MENUITEM "5" "fast     "
call "%~dp0draw.bat" :MENUITEM "6" "medium   "
call "%~dp0draw.bat" :MENUITEM "7" "slow     "
call "%~dp0draw.bat" :MENUITEM "8" "slower   "
call "%~dp0draw.bat" :MENUITEM "9" "veryslow "
echo.
echo   %_CY%Select preset [1-9, default: 3]%_C0%
set /p "preset_sel="
if "%preset_sel:~0,1%"=="1" set "x_preset=ultrafast"
if "%preset_sel:~0,1%"=="2" set "x_preset=superfast"
if "%preset_sel:~0,1%"=="3" set "x_preset=veryfast"
if "%preset_sel:~0,1%"=="4" set "x_preset=faster"
if "%preset_sel:~0,1%"=="5" set "x_preset=fast"
if "%preset_sel:~0,1%"=="6" set "x_preset=medium"
if "%preset_sel:~0,1%"=="7" set "x_preset=slow"
if "%preset_sel:~0,1%"=="8" set "x_preset=slower"
if "%preset_sel:~0,1%"=="9" set "x_preset=veryslow"

set "vcodec=libx264"
set "vcrf=20"
set "codec_label=H.264"
call "%~dp0draw.bat" :SECTION "VIDEO CODEC"
call "%~dp0draw.bat" :MENUITEM "1" "H.264 / AVC  ^(libx264^)" "(default; widest compatibility)"
call "%~dp0draw.bat" :MENUITEM "2" "H.265 / HEVC ^(libx265^)" "(smaller files; slower; less compatible)"
echo.
echo   %_CY%Select codec [1-2, default: 1]%_C0%
set /p "codec_sel="
if not "%codec_sel:~0,1%"=="2" exit /b 0

"%FF%" -v error -hide_banner -encoders | findstr /i " libx265 " >nul
if errorlevel 1 (
  echo.
  echo   %_CY%[!]%_C0%  libx265 not found in this FFmpeg build. Using H.264 instead.
  exit /b 0
)
set "vcodec=libx265"
set "vcrf=23"
set "codec_label=H.265"
exit /b 0

REM ============================================================
REM ASK_GPU_BACKEND
REM   Prompts for GPU/CPU encoder backend and sets encoder vars.
REM   %2 = codec_label  (H.264 or H.265)
REM   %3 = vcrf         (base quality value)
REM   Sets: gpu_mode, enc_video, nv_preset, nv_qp,
REM         qsv_gq, amf_qp_i, amf_qp_p, amf_qp_b, mf_bitrate
REM ============================================================
:ASK_GPU_BACKEND
set "codec_label=%~2"
set "vcrf=%~3"
set "vcodec=libx264"
if "%codec_label%"=="H.265" set "vcodec=libx265"

call "%~dp0draw.bat" :SECTION "ENCODER BACKEND"
call "%~dp0draw.bat" :MENUITEM "1" "CPU  ^(%codec_label% / %vcodec%^)" "(default)"
call "%~dp0draw.bat" :MENUITEM "2" "NVIDIA NVENC"
call "%~dp0draw.bat" :MENUITEM "3" "Intel Quick Sync"
call "%~dp0draw.bat" :MENUITEM "4" "AMD AMF"
call "%~dp0draw.bat" :MENUITEM "5" "MediaFoundation"
echo.
echo   %_CGr%Only the selected backend is attempted; on failure the script stops.%_C0%
echo.
echo   %_CY%Select backend [1-5, default: 1]%_C0%
set /p "gpu_choice="

set "gpu_mode=cpu"
set "nv_preset=p5"
set "nv_qp=%vcrf%"
set "qsv_gq=%vcrf%"
set "amf_qp_i=%vcrf%"
set "amf_qp_p=%vcrf%"
set "amf_qp_b=%vcrf%"
set "mf_bitrate=6000k"

if "%codec_label%"=="H.265" (
  set /a nv_qp=%vcrf%+4
  set /a qsv_gq=%vcrf%+4
  set /a amf_qp_i=%vcrf%+4
  set /a amf_qp_p=%vcrf%+4
  set /a amf_qp_b=%vcrf%+6
  set "mf_bitrate=4000k"
)

if "%gpu_choice:~0,1%"=="2" (
  set "gpu_mode=nvenc"
) else if "%gpu_choice:~0,1%"=="3" (
  set "gpu_mode=qsv"
) else if "%gpu_choice:~0,1%"=="4" (
  set "gpu_mode=amf"
) else if "%gpu_choice:~0,1%"=="5" (
  set "gpu_mode=mf"
) else (
  set "gpu_mode=cpu"
)
exit /b 0

REM ============================================================
REM ASK_OUTPUT
REM   Prompts for output directory and filename.
REM   Sets: outdir, basename, outfile, outfile_esc
REM   errorlevel 1 if output directory cannot be created
REM ============================================================
:ASK_OUTPUT
set "default_outdir=%USERPROFILE%\Downloads"
call "%~dp0draw.bat" :SECTION "OUTPUT"
echo   %_CY%Output directory [default: %default_outdir%]%_C0%
set /p "outdir="
if "%outdir%"=="" set "outdir=%default_outdir%"
for %%A in ("%outdir%") do set "outdir=%%~A"
if not exist "%outdir%" (
  echo   %_CGr%Creating directory: %outdir%%_C0%
  mkdir "%outdir%" >nul 2>&1
  if errorlevel 1 (
    echo.
    echo   %_CR%[!]  Failed to create output directory.%_C0%
    exit /b 1
  )
)

echo.
echo   %_CGr%Filename without .mp4 extension. Leave blank for auto timestamp.%_C0%
echo.
echo   %_CY%Output filename [no .mp4, default: auto timestamp]%_C0%
set /p "basename="
for %%A in ("%basename%") do set "basename=%%~A"

if "%basename%"=="" call :_GEN_TIMESTAMP

if /i "%basename:~-4%"==".mp4" set "basename=%basename:~0,-4%"
if "%basename:~-1%"=="." set "basename=%basename:~0,-1%"
set "outfile=%outdir%\%basename%.mp4"
call "%~dp0ui.bat" :ESCAPE_PATH outfile outfile_esc
exit /b 0

REM ============================================================
REM _GEN_TIMESTAMP  (internal)
REM   Generates a timestamped basename. Sets: basename
REM ============================================================
:_GEN_TIMESTAMP
setlocal EnableDelayedExpansion
set "rawts="
set "ts="
set "_tmpts=%TEMP%\ts_%RANDOM%_%RANDOM%.txt"
wmic os get LocalDateTime /value >"%_tmpts%" 2>nul
for /f "usebackq tokens=2 delims==." %%I in ("%_tmpts%") do if not "%%I"=="" set "rawts=%%I"
if exist "%_tmpts%" del /q "%_tmpts%" >nul 2>&1
if defined rawts (
  set "_chk=!rawts:~0,14!"
  for /f "delims=0123456789" %%Z in ("!_chk!") do set "rawts="
)
if defined rawts (
  set "ts=!rawts:~0,8!_!rawts:~8,6!_%RANDOM%"
) else (
  set "ts=%DATE: =0%_%TIME: =0%"
  set "ts=!ts::=!"
  set "ts=!ts:/=!"
  set "ts=!ts:.=!"
  for /f "tokens=1,2 delims=_" %%a in ("!ts!") do set "ts=%%a_%%b"
  set "ts=!ts:~0,15!_%RANDOM%"
)
endlocal & set "basename=output_%ts%"
exit /b 0
