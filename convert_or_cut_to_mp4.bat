@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM =========================
REM 0) FFmpeg
REM =========================
call "%~dp0lib\ffmpeg.bat" :ENSURE_FFMPEG
if errorlevel 1 goto END

call "%~dp0lib\draw.bat" :INIT_COLORS
call "%~dp0lib\draw.bat" :HEADER_CONVERT

REM =========================
REM 1) Input file
REM =========================
call "%~dp0lib\draw.bat" :SECTION "INPUT FILE"
echo   %_CY%Enter full path to the media file%_C0%
set /p "infile="
if "%infile%"=="" (
  echo.
  echo %_CR%  [!]  Input path cannot be empty.%_C0%
  goto END
)
for %%A in ("%infile%") do (
  set "infile=%%~A"
  set "inext=%%~xA"
)
if not exist "%infile%" (
  echo.
  echo %_CR%  [!]  File not found:%_C0%  %infile%
  goto END
)
call "%~dp0lib\ui.bat" :ESCAPE_PATH infile infile_esc

REM TS/M2TS: add AAC bitstream filter for stream copy mux
set "abits="
if /i "%inext%"==".ts"   set "abits=-bsf:a aac_adtstoasc"
if /i "%inext%"==".m2ts" set "abits=-bsf:a aac_adtstoasc"

REM =========================
REM 2) Action: convert or cut
REM =========================
call "%~dp0lib\draw.bat" :SECTION "ACTION"
call "%~dp0lib\draw.bat" :MENUITEM "1" "Convert whole file to MP4" "(fast stream copy)"
call "%~dp0lib\draw.bat" :MENUITEM "2" "Cut a segment"             "(choose start/end times)"
echo.
echo   %_CY%Select [1-2, default: 1]%_C0%
set /p "do_sel="
if "%do_sel:~0,1%"=="2" ( set "do_cut=yes" ) else ( set "do_cut=no" )

if /i "%do_cut%"=="yes" goto DO_PROBE
goto ASK_MODE

REM =========================
REM 2b) Probe duration (cut only)
REM =========================
:DO_PROBE
call "%~dp0lib\ffmpeg.bat" :GET_DURATION "%infile%" dur_sec dur_hms
if errorlevel 1 (
  echo.
  echo %_CR%  [!]  Could not read media duration via ffprobe.%_C0%
  echo %_CGr%       Check that FFprobe is available and the file is readable.%_C0%
  goto END
)

REM =========================
REM 3) Cut times
REM =========================
:TIMES_LOOP
call "%~dp0lib\draw.bat" :SECTION "CUT TIMES"
echo   %_CGr%Duration:%_C0%  %_CW%%dur_hms%%_C0%
echo.
set "from_ts=00:00:00"
set "to_ts=%dur_hms%"
echo   %_CY%FROM [HH:MM:SS, default: 00:00:00]%_C0%
set /p "from_ts="
echo   %_CY%TO   [HH:MM:SS, default: %dur_hms%]%_C0%
set /p "to_ts="

set "from_ts=%from_ts: =%"
set "to_ts=%to_ts: =%"

call "%~dp0lib\time.bat" :HMS_TO_SEC "%from_ts%" from_sec
if errorlevel 1 (
  echo   %_CY%[Info]%_C0%  Invalid FROM format. Use HH:MM:SS; minutes/seconds 00-59.
  goto TIMES_LOOP
)

call "%~dp0lib\time.bat" :HMS_TO_SEC "%to_ts%" to_sec
if errorlevel 1 (
  echo   %_CY%[Info]%_C0%  Invalid TO format. Use HH:MM:SS; minutes/seconds 00-59.
  goto TIMES_LOOP
)

if %from_sec% GEQ %dur_sec% (
  echo   %_CY%[Info]%_C0%  FROM is beyond duration ^(%dur_hms%^). Choose an earlier time.
  goto TIMES_LOOP
)
if %to_sec% LEQ %from_sec% (
  echo   %_CY%[Info]%_C0%  TO must be strictly greater than FROM.
  goto TIMES_LOOP
)

set "CLAMPED_TO="
if %to_sec% GTR %dur_sec% (
  set "to_sec=%dur_sec%"
  set "CLAMPED_TO=1"
)

set /a t_sec=to_sec-from_sec
if %t_sec% LEQ 0 (
  echo   %_CY%[Info]%_C0%  Computed length is not positive. Please re-enter times.
  goto TIMES_LOOP
)

call "%~dp0lib\time.bat" :SEC_TO_HMS %from_sec% from_ts
call "%~dp0lib\time.bat" :SEC_TO_HMS %to_sec%   to_ts

if defined CLAMPED_TO echo   %_CY%[Info]%_C0%  TO exceeded media duration; trimmed to %to_ts%.

REM =========================
REM 4) Processing mode
REM =========================
:ASK_MODE
call "%~dp0lib\draw.bat" :SECTION "PROCESSING MODE"
call "%~dp0lib\draw.bat" :MENUITEM "1" "Stream copy (no re-encode)" "(very fast remux; cuts are keyframe-aligned)"
call "%~dp0lib\draw.bat" :MENUITEM "2" "Re-encode"                  "(slower; frame-accurate; choose codec + GPU)"
echo.
echo   %_CY%Select [1-2, default: 1]%_C0%
set /p "mode_sel="
if "%mode_sel:~0,1%"=="2" ( set "cutmode=reencode" ) else ( set "cutmode=copy" & goto ASK_OUTDIR )

call "%~dp0lib\ui.bat" :ASK_PRESET_AND_CODEC
call "%~dp0lib\ui.bat" :ASK_GPU_BACKEND "%codec_label%" %vcrf%

:ASK_OUTDIR
call "%~dp0lib\ui.bat" :ASK_OUTPUT
if errorlevel 1 goto END

REM =========================
REM 5) Summary
REM =========================
call "%~dp0lib\draw.bat" :SECTION "SUMMARY"
call "%~dp0lib\draw.bat" :KV "Source :" "%infile%"
if /i "%do_cut%"=="yes" (
  call "%~dp0lib\draw.bat" :KV "From   :" "%from_ts%"
  call "%~dp0lib\draw.bat" :KV "To     :" "%to_ts%"
  call "%~dp0lib\draw.bat" :KV "Length :" "%t_sec%s  ^(duration: %dur_hms%^)"
)
call "%~dp0lib\draw.bat" :KV "Output :" "%outfile%"
echo.

if /i "%cutmode%"=="copy" goto DO_COPY
goto DO_REENC

REM ---- Stream copy ----
:DO_COPY
call "%~dp0lib\draw.bat" :KV "Method :" "stream copy ^(no re-encode^)"
echo.
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
call "%~dp0lib\draw.bat" :KV "Method :" "re-encode  ^(codec: %codec_label%, backend: %gpu_mode%^)"
echo.
if /i "%gpu_mode%"=="nvenc" goto DO_NVENC
if /i "%gpu_mode%"=="qsv"   goto DO_QSV
if /i "%gpu_mode%"=="amf"   goto DO_AMF
if /i "%gpu_mode%"=="mf"    goto DO_MF
goto DO_CPU

:DO_NVENC
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
call "%~dp0lib\draw.bat" :OK "%outfile%"
if /i "%cutmode%"=="copy" (
  if /i "%do_cut%"=="yes" echo   %_CGr%Note: the cut is keyframe-aligned and may be slightly off.%_C0%
)
goto END

:FAIL
call "%~dp0lib\draw.bat" :FAIL_MSG

:END
echo.
pause
exit /b
