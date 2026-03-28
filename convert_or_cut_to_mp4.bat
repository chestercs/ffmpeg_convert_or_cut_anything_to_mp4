@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM =========================
REM 0) FFmpeg
REM =========================
call "%~dp0lib\ffmpeg.bat" :ENSURE_FFMPEG
if errorlevel 1 goto END

echo.
echo -------------------------------------------------------
echo    ChesTeRcs - FFmpeg Petyus Vegas Vibe v.0.1.1
echo -------------------------------------------------------

REM =========================
REM 1) Input file
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
call "%~dp0lib\ui.bat" :ESCAPE_PATH infile infile_esc

REM TS/M2TS: add AAC bitstream filter for stream copy mux
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
if "%do_sel:~0,1%"=="2" ( set "do_cut=yes" ) else ( set "do_cut=no" )

if /i "%do_cut%"=="yes" goto DO_PROBE
goto ASK_MODE

REM =========================
REM 2/b) Probe duration (only needed for cut)
REM =========================
:DO_PROBE
call "%~dp0lib\ffmpeg.bat" :GET_DURATION "%infile%" dur_sec dur_hms
if errorlevel 1 (
  echo.
  echo [!] Could not read media duration with FFprobe. Cannot safely cut.
  echo     Check that FFprobe is available and the file is readable.
  goto END
)

REM =========================
REM 3) Ask + validate cut times
REM =========================
:TIMES_LOOP
echo.
echo Enter times in HH:MM:SS
echo   FROM=00:00:00    TO=%dur_hms%   (max = full duration)
set "from_ts=00:00:00"
set "to_ts=%dur_hms%"
set /p "from_ts=FROM time (HH:MM:SS, Default: 00:00:00): "
set /p "to_ts=TO   time (HH:MM:SS, Default: %dur_hms%): "

set "from_ts=%from_ts: =%"
set "to_ts=%to_ts: =%"

call "%~dp0lib\time.bat" :HMS_TO_SEC "%from_ts%" from_sec
if errorlevel 1 echo [Info] Invalid FROM format. Use HH:MM:SS; minutes/seconds must be min 00 and max 59.& goto TIMES_LOOP

call "%~dp0lib\time.bat" :HMS_TO_SEC "%to_ts%" to_sec
if errorlevel 1 echo [Info] Invalid TO format. Use HH:MM:SS; minutes/seconds must be min 00 and max 59.& goto TIMES_LOOP

if %from_sec% GEQ %dur_sec% echo [Info] FROM is beyond duration (%dur_hms%). Choose an earlier time.& goto TIMES_LOOP
if %to_sec%   LEQ %from_sec% echo [Info] TO must be strictly greater than FROM.& goto TIMES_LOOP

set "CLAMPED_TO="
if %to_sec% GTR %dur_sec% (
  set "to_sec=%dur_sec%"
  set "CLAMPED_TO=1"
)

set /a t_sec=to_sec-from_sec
if %t_sec% LEQ 0 echo [Info] Computed length is not positive. Please re-enter times.& goto TIMES_LOOP

call "%~dp0lib\time.bat" :SEC_TO_HMS %from_sec% from_ts
call "%~dp0lib\time.bat" :SEC_TO_HMS %to_sec%   to_ts

if defined CLAMPED_TO echo [Info] TO exceeded media duration; trimmed to %to_ts%.

REM =========================
REM 4) Processing mode
REM =========================
:ASK_MODE
echo.
echo Choose processing mode:
echo   1) Stream copy (no re-encode)  - very fast remux to MP4; for cuts it is keyframe-aligned and not frame-accurate
echo   2) Re-encode                   - slower; frame-accurate cuts; pick codec, preset and GPU
set /p "mode_sel=Select mode (Default: 1): "
if "%mode_sel:~0,1%"=="2" ( set "cutmode=reencode" ) else ( set "cutmode=copy" & goto ASK_OUTDIR )

call "%~dp0lib\ui.bat" :ASK_PRESET_AND_CODEC
call "%~dp0lib\ui.bat" :ASK_GPU_BACKEND "%codec_label%" %vcrf%

:ASK_OUTDIR
call "%~dp0lib\ui.bat" :ASK_OUTPUT
if errorlevel 1 goto END

REM =========================
REM 5) Do the work
REM =========================
echo.
echo Source:  %infile%
if /i "%do_cut%"=="yes" (
  echo From:    %from_ts%
  echo To:      %to_ts%
  echo Length:  %t_sec%s  (Duration: %dur_hms%)
)
echo Output:  %outfile%

if /i "%cutmode%"=="copy" goto DO_COPY
goto DO_REENC

REM ---- Stream copy ----
:DO_COPY
echo Method:  stream copy (no re-encode)
setlocal DisableDelayedExpansion
if /i "%do_cut%"=="yes" (
  "%FF%" -hide_banner -y -ss "%from_ts%" -i "%infile_esc%" -t %t_sec% -c copy %abits% -movflags +faststart "%outfile_esc%"
) else (
  "%FF%" -hide_banner -y -i "%infile_esc%" -c copy %abits% -movflags +faststart "%outfile_esc%"
)
endlocal
if errorlevel 1 goto FAIL
goto SUCCESS

REM ---- Re-encode dispatch ----
:DO_REENC
echo Method:  re-encode (codec: %codec_label%, preset: %x_preset%)
if /i "%gpu_mode%"=="nvenc" goto DO_NVENC
if /i "%gpu_mode%"=="qsv"   goto DO_QSV
if /i "%gpu_mode%"=="amf"   goto DO_AMF
if /i "%gpu_mode%"=="mf"    goto DO_MF
goto DO_CPU

:DO_NVENC
echo Backend: NVIDIA NVENC  (preset %nv_preset%, QP %nv_qp%)
setlocal DisableDelayedExpansion
if /i "%codec_label%"=="H.265" (
  if /i "%do_cut%"=="yes" (
    "%FF%" -hide_banner -y -ss "%from_ts%" -i "%infile_esc%" -t %t_sec% -c:v hevc_nvenc -preset %nv_preset% -rc constqp -qp %nv_qp% -tag:v hvc1 -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  ) else (
    "%FF%" -hide_banner -y -i "%infile_esc%" -c:v hevc_nvenc -preset %nv_preset% -rc constqp -qp %nv_qp% -tag:v hvc1 -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  )
) else (
  if /i "%do_cut%"=="yes" (
    "%FF%" -hide_banner -y -ss "%from_ts%" -i "%infile_esc%" -t %t_sec% -c:v h264_nvenc -preset %nv_preset% -rc constqp -qp %nv_qp% -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  ) else (
    "%FF%" -hide_banner -y -i "%infile_esc%" -c:v h264_nvenc -preset %nv_preset% -rc constqp -qp %nv_qp% -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  )
)
endlocal
if errorlevel 1 goto FAIL
goto SUCCESS

:DO_QSV
echo Backend: Intel Quick Sync  (global_quality %qsv_gq%)
setlocal DisableDelayedExpansion
if /i "%codec_label%"=="H.265" (
  if /i "%do_cut%"=="yes" (
    "%FF%" -hide_banner -y -ss "%from_ts%" -i "%infile_esc%" -t %t_sec% -c:v hevc_qsv -global_quality %qsv_gq% -tag:v hvc1 -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  ) else (
    "%FF%" -hide_banner -y -i "%infile_esc%" -c:v hevc_qsv -global_quality %qsv_gq% -tag:v hvc1 -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  )
) else (
  if /i "%do_cut%"=="yes" (
    "%FF%" -hide_banner -y -ss "%from_ts%" -i "%infile_esc%" -t %t_sec% -c:v h264_qsv -global_quality %qsv_gq% -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  ) else (
    "%FF%" -hide_banner -y -i "%infile_esc%" -c:v h264_qsv -global_quality %qsv_gq% -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  )
)
endlocal
if errorlevel 1 goto FAIL
goto SUCCESS

:DO_AMF
echo Backend: AMD AMF  (CQP QP I/P/B: %amf_qp_i% / %amf_qp_p% / %amf_qp_b%)
setlocal DisableDelayedExpansion
if /i "%codec_label%"=="H.265" (
  if /i "%do_cut%"=="yes" (
    "%FF%" -hide_banner -y -ss "%from_ts%" -i "%infile_esc%" -t %t_sec% -c:v hevc_amf -rc cqp -qp_i %amf_qp_i% -qp_p %amf_qp_p% -qp_b %amf_qp_b% -tag:v hvc1 -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  ) else (
    "%FF%" -hide_banner -y -i "%infile_esc%" -c:v hevc_amf -rc cqp -qp_i %amf_qp_i% -qp_p %amf_qp_p% -qp_b %amf_qp_b% -tag:v hvc1 -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  )
) else (
  if /i "%do_cut%"=="yes" (
    "%FF%" -hide_banner -y -ss "%from_ts%" -i "%infile_esc%" -t %t_sec% -c:v h264_amf -rc cqp -qp_i %amf_qp_i% -qp_p %amf_qp_p% -qp_b %amf_qp_b% -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  ) else (
    "%FF%" -hide_banner -y -i "%infile_esc%" -c:v h264_amf -rc cqp -qp_i %amf_qp_i% -qp_p %amf_qp_p% -qp_b %amf_qp_b% -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  )
)
endlocal
if errorlevel 1 goto FAIL
goto SUCCESS

:DO_MF
echo Backend: Media Foundation  (bitrate %mf_bitrate%)
setlocal DisableDelayedExpansion
if /i "%codec_label%"=="H.265" (
  if /i "%do_cut%"=="yes" (
    "%FF%" -hide_banner -y -ss "%from_ts%" -i "%infile_esc%" -t %t_sec% -c:v hevc_mf -b:v %mf_bitrate% -tag:v hvc1 -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  ) else (
    "%FF%" -hide_banner -y -i "%infile_esc%" -c:v hevc_mf -b:v %mf_bitrate% -tag:v hvc1 -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  )
) else (
  if /i "%do_cut%"=="yes" (
    "%FF%" -hide_banner -y -ss "%from_ts%" -i "%infile_esc%" -t %t_sec% -c:v h264_mf -b:v %mf_bitrate% -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  ) else (
    "%FF%" -hide_banner -y -i "%infile_esc%" -c:v h264_mf -b:v %mf_bitrate% -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  )
)
endlocal
if errorlevel 1 goto FAIL
goto SUCCESS

:DO_CPU
echo Backend: CPU (%vcodec%), CRF %vcrf%
setlocal DisableDelayedExpansion
if /i "%codec_label%"=="H.265" (
  if /i "%do_cut%"=="yes" (
    "%FF%" -hide_banner -y -ss "%from_ts%" -i "%infile_esc%" -t %t_sec% -c:v libx265 -preset %x_preset% -crf %vcrf% -tag:v hvc1 -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  ) else (
    "%FF%" -hide_banner -y -i "%infile_esc%" -c:v libx265 -preset %x_preset% -crf %vcrf% -tag:v hvc1 -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  )
) else (
  if /i "%do_cut%"=="yes" (
    "%FF%" -hide_banner -y -ss "%from_ts%" -i "%infile_esc%" -t %t_sec% -c:v libx264 -preset %x_preset% -crf %vcrf% -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  ) else (
    "%FF%" -hide_banner -y -i "%infile_esc%" -c:v libx264 -preset %x_preset% -crf %vcrf% -c:a aac -b:a 160k -movflags +faststart "%outfile_esc%"
  )
)
endlocal
if errorlevel 1 goto FAIL
goto SUCCESS

:SUCCESS
echo.
echo [OK] Done.
echo Full path: %outfile%
if /i "%cutmode%"=="copy" (
  echo Method:    stream copy ^(no re-encode^)
  if /i "%do_cut%"=="yes" echo Note: the cut is keyframe aligned and may be slightly off.
) else (
  if /i "%do_cut%"=="yes" (
    echo Method:    re-encode segment ^(codec: %codec_label%; backend: %gpu_mode%^)
  ) else (
    echo Method:    re-encode full ^(codec: %codec_label%; backend: %gpu_mode%^)
  )
)
goto END

:FAIL
echo.
echo [!] Error: processing failed for the selected backend.
echo     Tip: Select CPU next time if GPU backend is unavailable or fails.

:END
echo.
pause
exit /b
