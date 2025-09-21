@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM =========================
REM 0) Check ffmpeg / optional winget install
REM =========================
where ffmpeg >nul 2>&1
if errorlevel 1 goto NOFFMPEG
goto FFOK

:NOFFMPEG
echo.
echo [!] ffmpeg was not found on this system.
set /p "ans=Install via winget? (Y/N, Default: N): "
if /i "%ans%"=="Y" goto INSTALL_FFMPEG
echo Aborted.
goto END

:INSTALL_FFMPEG
where winget >nul 2>&1
if errorlevel 1 (
  echo.
  echo [!] winget is not available. Please install "App Installer" from Microsoft Store.
  goto END
)
echo.
echo Installing ffmpeg with winget...
winget install --id Gyan.FFmpeg -e --source winget
if errorlevel 1 (
  echo.
  echo [!] Installation failed.
  goto END
)
where ffmpeg >nul 2>&1
if errorlevel 1 (
  echo.
  echo [!] ffmpeg installed, but PATH did not refresh in this window. Close and rerun.
  goto END
)

:FFOK

REM =========================
REM 1) Input file path (any format supported by FFmpeg)
REM =========================
echo.
set /p "infile=Enter FULL PATH to the input media file: "
if "%infile%"=="" (
  echo [!] Input path cannot be empty.
  goto END
)
for %%A in ("%infile%") do (
  set "infile=%%~A"
  set "inext=%%~xA"
)
if not exist "%infile%" (
  echo [!] File not found: %infile%
  goto END
)

REM Escape special CMD chars in paths (& | < > ^)
set "infile_esc=%infile%"
set "infile_esc=%infile_esc:^=^^%"
set "infile_esc=%infile_esc:&=^&%"
set "infile_esc=%infile_esc:|=^|%"
set "infile_esc=%infile_esc:<=^<%"
set "infile_esc=%infile_esc:>=^>%"

REM If input is TS/M2TS, prep audio bitstream filter for MP4 mux
set "abits="
if /i "%inext%"==".ts"   set "abits=-bsf:a aac_adtstoasc"
if /i "%inext%"==".m2ts" set "abits=-bsf:a aac_adtstoasc"

REM =========================
REM 2) Action: convert whole file or cut segment
REM =========================
echo.
echo What do you want to do?
echo   1) Convert the WHOLE file to MP4   [fast if stream copy]
echo   2) CUT a segment and make an MP4   [choose times]
set /p "do_sel=Select action (Default: 1): "
if "%do_sel%"=="2" ( set "do_cut=yes" ) else ( set "do_cut=no" )

if /i "%do_cut%"=="yes" goto ASK_TIMES
goto ASK_MODE

:ASK_TIMES
echo.
echo Enter times in HH:MM:SS (example FROM=00:07:55  TO=00:12:04)
set /p "from_ts=FROM time (HH:MM:SS): "
set /p "to_ts=TO   time (HH:MM:SS): "
if "%from_ts%"=="" ( echo [!] FROM cannot be empty. & goto END )
if "%to_ts%"==""   ( echo [!] TO cannot be empty.   & goto END )

REM =========================
REM 3) Processing mode
REM =========================
:ASK_MODE
echo.
echo Choose processing mode:
echo   1) Stream copy (no re-encode)  - very fast remux to MP4; for cuts it is keyframe-aligned and not frame-accurate
echo   2) Re-encode                   - slower; frame-accurate cuts; pick codec, preset and GPU
set /p "mode_sel=Select mode (Default: 1): "
if "%mode_sel%"=="2" ( set "cutmode=reencode" & goto ASK_PRESET ) else ( set "cutmode=copy" & goto ASK_OUTDIR )

:ASK_PRESET
set "x_preset=veryfast"
echo.
echo Select encoder preset (slower = better compression at the same quality):
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

REM Codec choice
set "vcodec=libx264"
set "vcrf=20"
set "codec_label=H.264"
echo.
echo Select video codec:
echo   1) H.264 / AVC (libx264)  [default; widest compatibility]
echo   2) H.265 / HEVC (libx265)  [smaller files; slower; may be less compatible]
set /p "codec_sel=Select codec (Default: 1): "
if "%codec_sel%"=="2" goto TRY_X265
goto ASK_GPU

:TRY_X265
ffmpeg -v error -hide_banner -encoders | findstr /i " libx265 " >nul
if errorlevel 1 goto NO_X265
set "vcodec=libx265"
set "vcrf=23"
set "codec_label=H.265"
goto ASK_GPU

:NO_X265
echo.
echo [!] libx265 encoder not found. Using H.264 instead.
set "vcodec=libx264"
set "vcrf=20"
set "codec_label=H.264"

REM =========================
REM 3/b) GPU backend menu (no availability hints, no probing)
REM =========================
:ASK_GPU
echo.
echo Select encoder backend (GPU or CPU):
echo   1) CPU  - %codec_label% (%vcodec%)  [default]
echo   2) NVIDIA NVENC
echo   3) Intel Quick Sync
echo   4) AMD AMF
echo   5) MediaFoundation
echo (Only the selected backend will be attempted; on failure the script stops.)
set /p "gpu_choice=Select backend (Default: 1): "

REM Configure per-backend params (no auto-fallbacks here)
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
  if "%codec_label%"=="H.264" ( set "gpu_mode=qsv"   & set "enc_video=h264_qsv" )   else ( set "gpu_mode=qsv"   & set "enc_video=hevc_qsv" )
) else if "%gpu_choice%"=="4" (
  if "%codec_label%"=="H.264" ( set "gpu_mode=amf"   & set "enc_video=h264_amf" )   else ( set "gpu_mode=amf"   & set "enc_video=hevc_amf" )
) else if "%gpu_choice%"=="5" (
  if "%codec_label%"=="H.264" ( set "gpu_mode=mf"    & set "enc_video=h264_mf" )    else ( set "gpu_mode=mf"    & set "enc_video=hevc_mf" )
) else (
  set "gpu_mode=cpu"
)

REM Map x264 preset to NVENC preset roughly (ultrafast..veryslow -> p1..p7)
set "nv_preset=p5"
if /i "%x_preset%"=="ultrafast" set "nv_preset=p1"
if /i "%x_preset%"=="superfast" set "nv_preset=p2"
if /i "%x_preset%"=="veryfast"  set "nv_preset=p5"
if /i "%x_preset%"=="faster"    set "nv_preset=p6"
if /i "%x_preset%"=="fast"      set "nv_preset=p6"
if /i "%x_preset%"=="medium"    set "nv_preset=p7"
if /i "%x_preset%"=="slow"      set "nv_preset=p7"
if /i "%x_preset%"=="slower"    set "nv_preset=p7"
if /i "%x_preset%"=="veryslow"  set "nv_preset=p7"

REM =========================
REM 4) Output directory (default: Downloads)
REM =========================
:ASK_OUTDIR
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
    goto END
  )
)

REM =========================
REM 5) Output filename (without .mp4) + robust timestamp
REM =========================
echo.
echo Example filename: output_01   (do NOT type .mp4)
set /p "basename=Output filename (Default: auto timestamp): "
for %%A in ("%basename%") do set "basename=%%~A"

if "%basename%"=="" (
  for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "ts=%%I"
  if "!ts!"=="" (
    for /f "tokens=2 delims==." %%I in ('wmic os get localdatetime /value 2^>nul') do set "rawts=%%I"
    if defined rawts (
      set "ts=!rawts:~0,8!_!rawts:~8,6!"
    ) else (
      set "ts=%DATE: =0%_%TIME: =0%"
      set "ts=!ts::=!"
      set "ts=!ts:/=!"
      set "ts=!ts:.=!"
      for /f "tokens=1,2 delims=_" %%a in ("!ts!") do set "ts=%%a_%%b"
      set "ts=!ts:~0,15!"
    )
  )
  set "basename=output_!ts!"
)

if /i "%basename:~-4%"==".mp4" set "basename=%basename:~0,-4%"
if "%basename:~-1%"=="." set "basename=%basename:~0,-1%"

set "outfile=%outdir%\%basename%.mp4"

REM Escape output path
set "outfile_esc=%outfile%"
set "outfile_esc=%outfile_esc:^=^^%"
set "outfile_esc=%outfile_esc:&=^&%"
set "outfile_esc=%outfile_esc:|=^|%"
set "outfile_esc=%outfile_esc:<=^<%"
set "outfile_esc=%outfile_esc:>=^>%"

REM =========================
REM 6) Do the work
REM =========================
echo.
echo Source:  %infile%
if /i "%do_cut%"=="yes" (
  echo From:    %from_ts%
  echo To:      %to_ts%
)
echo Output:  %outfile%

if /i "%cutmode%"=="copy" goto DO_COPY
goto DO_REENC

:DO_COPY
echo Method:  stream copy (no re-encode)
if /i "%do_cut%"=="yes" (
  ffmpeg -hide_banner -y -ss "%from_ts%" -to "%to_ts%" -i "%infile_esc%" -c copy %abits% -movflags +faststart "%outfile_esc%"
) else (
  ffmpeg -hide_banner -y -i "%infile_esc%" -c copy %abits% -movflags +faststart "%outfile_esc%"
)
if errorlevel 1 goto FAIL
goto SUCCESS

:DO_REENC
echo Method:  re-encode (codec: %codec_label%, preset: %x_preset%)
if /i "%gpu_mode%"=="nvenc" goto DO_NVENC
if /i "%gpu_mode%"=="qsv"   goto DO_QSV
if /i "%gpu_mode%"=="amf"   goto DO_AMF
if /i "%gpu_mode%"=="mf"    goto DO_MF
goto DO_CPU

:DO_NVENC
echo Backend: NVIDIA NVENC  (preset %nv_preset%, QP %nv_qp%)
if /i "%codec_label%"=="H.265" (
  if /i "%do_cut%"=="yes" (
    ffmpeg -hide_banner -y -i "%infile_esc%" -ss "%from_ts%" -to "%to_ts%" -c:v hevc_nvenc -preset %nv_preset% -rc constqp -qp %nv_qp% -tag:v hvc1 -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  ) else (
    ffmpeg -hide_banner -y -i "%infile_esc%" -c:v hevc_nvenc -preset %nv_preset% -rc constqp -qp %nv_qp% -tag:v hvc1 -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  )
) else (
  if /i "%do_cut%"=="yes" (
    ffmpeg -hide_banner -y -i "%infile_esc%" -ss "%from_ts%" -to "%to_ts%" -c:v h264_nvenc -preset %nv_preset% -rc constqp -qp %nv_qp% -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  ) else (
    ffmpeg -hide_banner -y -i "%infile_esc%" -c:v h264_nvenc -preset %nv_preset% -rc constqp -qp %nv_qp% -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  )
)
if errorlevel 1 goto FAIL
goto SUCCESS

:DO_QSV
echo Backend: Intel Quick Sync  (global_quality %qsv_gq%)
if /i "%codec_label%"=="H.265" (
  if /i "%do_cut%"=="yes" (
    ffmpeg -hide_banner -y -i "%infile_esc%" -ss "%from_ts%" -to "%to_ts%" -c:v hevc_qsv -global_quality %qsv_gq% -tag:v hvc1 -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  ) else (
    ffmpeg -hide_banner -y -i "%infile_esc%" -c:v hevc_qsv -global_quality %qsv_gq% -tag:v hvc1 -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  )
) else (
  if /i "%do_cut%"=="yes" (
    ffmpeg -hide_banner -y -i "%infile_esc%" -ss "%from_ts%" -to "%to_ts%" -c:v h264_qsv -global_quality %qsv_gq% -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  ) else (
    ffmpeg -hide_banner -y -i "%infile_esc%" -c:v h264_qsv -global_quality %qsv_gq% -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  )
)
if errorlevel 1 goto FAIL
goto SUCCESS

:DO_AMF
echo Backend: AMD AMF  (CQP QP I/P/B: %amf_qp_i% / %amf_qp_p% / %amf_qp_b%)
if /i "%codec_label%"=="H.265" (
  if /i "%do_cut%"=="yes" (
    ffmpeg -hide_banner -y -i "%infile_esc%" -ss "%from_ts%" -to "%to_ts%" -c:v hevc_amf -rc cqp -qp_i %amf_qp_i% -qp_p %amf_qp_p% -qp_b %amf_qp_b% -tag:v hvc1 -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  ) else (
    ffmpeg -hide_banner -y -i "%infile_esc%" -c:v hevc_amf -rc cqp -qp_i %amf_qp_i% -qp_p %amf_qp_p% -qp_b %amf_qp_b% -tag:v hvc1 -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  )
) else (
  if /i "%do_cut%"=="yes" (
    ffmpeg -hide_banner -y -i "%infile_esc%" -ss "%from_ts%" -to "%to_ts%" -c:v h264_amf -rc cqp -qp_i %amf_qp_i% -qp_p %amf_qp_p% -qp_b %amf_qp_b% -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  ) else (
    ffmpeg -hide_banner -y -i "%infile_esc%" -c:v h264_amf -rc cqp -qp_i %amf_qp_i% -qp_p %amf_qp_p% -qp_b %amf_qp_b% -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  )
)
if errorlevel 1 goto FAIL
goto SUCCESS

:DO_MF
echo Backend: Media Foundation  (bitrate %mf_bitrate%)
if /i "%codec_label%"=="H.265" (
  if /i "%do_cut%"=="yes" (
    ffmpeg -hide_banner -y -i "%infile_esc%" -ss "%from_ts%" -to "%to_ts%" -c:v hevc_mf -b:v %mf_bitrate% -tag:v hvc1 -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  ) else (
    ffmpeg -hide_banner -y -i "%infile_esc%" -c:v hevc_mf -b:v %mf_bitrate% -tag:v hvc1 -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  )
) else (
  if /i "%do_cut%"=="yes" (
    ffmpeg -hide_banner -y -i "%infile_esc%" -ss "%from_ts%" -to "%to_ts%" -c:v h264_mf -b:v %mf_bitrate% -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  ) else (
    ffmpeg -hide_banner -y -i "%infile_esc%" -c:v h264_mf -b:v %mf_bitrate% -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  )
)
if errorlevel 1 goto FAIL
goto SUCCESS

:DO_CPU
echo Backend: CPU (%vcodec%), CRF %vcrf%
if /i "%codec_label%"=="H.265" (
  if /i "%do_cut%"=="yes" (
    ffmpeg -hide_banner -y -i "%infile_esc%" -ss "%from_ts%" -to "%to_ts%" -c:v libx265 -preset %x_preset% -crf %vcrf% -tag:v hvc1 -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  ) else (
    ffmpeg -hide_banner -y -i "%infile_esc%" -c:v libx265 -preset %x_preset% -crf %vcrf% -tag:v hvc1 -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  )
) else (
  if /i "%do_cut%"=="yes" (
    ffmpeg -hide_banner -y -i "%infile_esc%" -ss "%from_ts%" -to "%to_ts%" -c:v libx264 -preset %x_preset% -crf %vcrf% -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  ) else (
    ffmpeg -hide_banner -y -i "%infile_esc%" -c:v libx264 -preset %x_preset% -crf %vcrf% -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  )
)
if errorlevel 1 goto FAIL
goto SUCCESS

:SUCCESS
echo.
echo [OK] Done.
echo Full path: %outfile%
if /i "%cutmode%"=="copy" (
  echo Method:    stream copy (no re-encode)
  if /i "%do_cut%"=="yes" echo Note: the cut is keyframe aligned and may be slightly off.
) else (
  if /i "%do_cut%"=="yes" (
    echo Method:    re-encode segment (codec: %codec_label%; backend: %gpu_mode%)
  ) else (
    echo Method:    re-encode full (codec: %codec_label%; backend: %gpu_mode%)
  )
)
goto END

:FAIL
echo.
echo [!] Error: processing failed for the selected backend.
echo     Tip: Select CPU next time if GPU backend is unavailable or fails.
goto END

:END
echo.
pause
