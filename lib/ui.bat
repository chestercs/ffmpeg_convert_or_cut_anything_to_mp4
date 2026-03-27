@echo off
if "%~1"=="" goto :EOF
goto %~1

REM ============================================================
REM lib\ui.bat  —  shared interactive UI helpers
REM
REM Call convention:
REM   call "%~dp0lib\ui.bat" :LABEL_NAME  arg2  arg3
REM   actual args start at %2
REM ============================================================

REM ============================================================
REM :ESCAPE_PATH
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
REM :ASK_PRESET_AND_CODEC
REM   Prompts for encoder preset and video codec.
REM   Requires FF to be set.
REM   No args.
REM   Sets: x_preset, vcodec, vcrf, codec_label
REM ============================================================
:ASK_PRESET_AND_CODEC
set "x_preset=veryfast"
echo.
if /i "%~2"=="simple" (
  echo Select encoder preset:
) else (
  echo Select encoder preset (slower = better compression at the same quality):
)
echo   1) ultrafast
echo   2) superfast
echo   3) veryfast   [default]
echo   4) faster
echo   5) fast
echo   6) medium
echo   7) slow
echo   8) slower
echo   9) veryslow
set /p "preset_sel=Select preset (Default: 3): "
if "%preset_sel%"=="1" set "x_preset=ultrafast"
if "%preset_sel%"=="2" set "x_preset=superfast"
if "%preset_sel%"=="3" set "x_preset=veryfast"
if "%preset_sel%"=="4" set "x_preset=faster"
if "%preset_sel%"=="5" set "x_preset=fast"
if "%preset_sel%"=="6" set "x_preset=medium"
if "%preset_sel%"=="7" set "x_preset=slow"
if "%preset_sel%"=="8" set "x_preset=slower"
if "%preset_sel%"=="9" set "x_preset=veryslow"

set "vcodec=libx264"
set "vcrf=20"
set "codec_label=H.264"
echo.
echo Select video codec:
echo   1) H.264 / AVC (libx264)  [default; widest compatibility]
echo   2) H.265 / HEVC (libx265)  [smaller files; slower; may be less compatible]
set /p "codec_sel=Select codec (Default: 1): "
if not "%codec_sel%"=="2" exit /b 0

"%FF%" -v error -hide_banner -encoders | findstr /i " libx265 " >nul
if errorlevel 1 (
  echo.
  echo [!] libx265 encoder not found. Using H.264 instead.
  exit /b 0
)
set "vcodec=libx265"
set "vcrf=23"
set "codec_label=H.265"
exit /b 0

REM ============================================================
REM :ASK_GPU_BACKEND
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

echo.
echo Select encoder backend (GPU or CPU):
echo   1) CPU  - %codec_label% (%vcodec%)  [default]
echo   2) NVIDIA NVENC
echo   3) Intel Quick Sync
echo   4) AMD AMF
echo   5) MediaFoundation
echo (Only the selected backend will be attempted; on failure the script stops.)
set /p "gpu_choice=Select backend (Default: 1): "

set "gpu_mode=cpu"
set "enc_video=%vcodec%"
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

if "%gpu_choice%"=="2" (
  if "%codec_label%"=="H.264" ( set "gpu_mode=nvenc" & set "enc_video=h264_nvenc" ) else ( set "gpu_mode=nvenc" & set "enc_video=hevc_nvenc" )
) else if "%gpu_choice%"=="3" (
  if "%codec_label%"=="H.264" ( set "gpu_mode=qsv"   & set "enc_video=h264_qsv"  ) else ( set "gpu_mode=qsv"   & set "enc_video=hevc_qsv"  )
) else if "%gpu_choice%"=="4" (
  if "%codec_label%"=="H.264" ( set "gpu_mode=amf"   & set "enc_video=h264_amf"  ) else ( set "gpu_mode=amf"   & set "enc_video=hevc_amf"  )
) else if "%gpu_choice%"=="5" (
  if "%codec_label%"=="H.264" ( set "gpu_mode=mf"    & set "enc_video=h264_mf"   ) else ( set "gpu_mode=mf"    & set "enc_video=hevc_mf"   )
) else (
  set "gpu_mode=cpu"
)
exit /b 0

REM ============================================================
REM :ASK_OUTPUT
REM   Prompts for output directory and filename.
REM   No args.
REM   Sets: outdir, basename, outfile, outfile_esc
REM   errorlevel 1 if output directory cannot be created
REM ============================================================
:ASK_OUTPUT
set "default_outdir=%USERPROFILE%\Downloads"
echo.
set /p "outdir=Output directory (Default: %default_outdir%): "
if "%outdir%"=="" set "outdir=%default_outdir%"
for %%A in ("%outdir%") do set "outdir=%%~A"
if not exist "%outdir%" (
  echo Creating directory: %outdir%
  mkdir "%outdir%" >nul 2>&1
  if errorlevel 1 (
    echo [!] Failed to create output directory.
    exit /b 1
  )
)

echo.
echo Example filename: output_01   (do NOT type .mp4)
set /p "basename=Output filename (Default: auto timestamp): "
for %%A in ("%basename%") do set "basename=%%~A"

if "%basename%"=="" call :_GEN_TIMESTAMP

if /i "%basename:~-4%"==".mp4" set "basename=%basename:~0,-4%"
if "%basename:~-1%"=="." set "basename=%basename:~0,-1%"
set "outfile=%outdir%\%basename%.mp4"
call "%~dp0ui.bat" :ESCAPE_PATH outfile outfile_esc
exit /b 0

REM ============================================================
REM :_GEN_TIMESTAMP  (internal — do not call from outside)
REM   Generates a timestamped basename using wmic, falls back
REM   to %DATE%/%TIME% string manipulation.
REM   Sets: basename
REM ============================================================
:_GEN_TIMESTAMP
setlocal EnableDelayedExpansion
set "rawts="
set "ts="
set "_tmpts=%TEMP%\ts_%RANDOM%_%RANDOM%.txt"
wmic os get LocalDateTime /value >"%_tmpts%" 2>nul
for /f "usebackq tokens=2 delims==." %%I in ("%_tmpts%") do if not "%%I"=="" set "rawts=%%I"
if exist "%_tmpts%" del /q "%_tmpts%" >nul 2>&1
REM validate: rawts must be at least 14 pure digits (YYYYMMDDHHmmss...)
if defined rawts (
  set "_chk=!rawts:~0,14!"
  for /f "delims=0123456789" %%Z in ("!_chk!") do set "rawts="
)
if defined rawts (
  set "ts=!rawts:~0,8!_!rawts:~8,6!_%RANDOM%"
) else (
  REM Fallback: %DATE% %TIME% alapú, ugyanaz mint régen + _RANDOM a végén
  set "ts=%DATE: =0%_%TIME: =0%"
  set "ts=!ts::=!"
  set "ts=!ts:/=!"
  set "ts=!ts:.=!"
  for /f "tokens=1,2 delims=_" %%a in ("!ts!") do set "ts=%%a_%%b"
  set "ts=!ts:~0,15!_%RANDOM%"
)
endlocal & set "basename=output_%ts%"
exit /b 0
