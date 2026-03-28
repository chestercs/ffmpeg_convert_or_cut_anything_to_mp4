@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM =========================
REM 0) FFmpeg
REM =========================
call "%~dp0lib\ffmpeg.bat" :ENSURE_FFMPEG
if errorlevel 1 goto END

echo.
echo -------------------------------------------------------
echo    ChesTeRcs - FFmpeg Music-on-Video v.0.2.0
echo -------------------------------------------------------
echo.
echo This script replaces the video's original audio with the
echo selected music starting from the given music timestamp.
echo The final MP4 length will always match the video length.
echo.

REM =========================
REM 1) Input video file
REM =========================
echo.
set /p "videofile=Enter FULL PATH to the VIDEO file: "
if "%videofile%"=="" (
  echo [!] Video path cannot be empty.
  goto END
)
for %%A in ("%videofile%") do set "videofile=%%~A"
if not exist "%videofile%" (
  echo [!] Video file not found: %videofile%
  goto END
)
call "%~dp0lib\ui.bat" :ESCAPE_PATH videofile videofile_esc

REM =========================
REM 2) Input music file
REM =========================
echo.
set /p "musicfile=Enter FULL PATH to the MUSIC file: "
if "%musicfile%"=="" (
  echo [!] Music path cannot be empty.
  goto END
)
for %%A in ("%musicfile%") do set "musicfile=%%~A"
if not exist "%musicfile%" (
  echo [!] Music file not found: %musicfile%
  goto END
)
call "%~dp0lib\ui.bat" :ESCAPE_PATH musicfile musicfile_esc

REM =========================
REM 3) Probe durations
REM =========================
echo.
echo Reading media durations...

call "%~dp0lib\ffmpeg.bat" :GET_DURATION "%videofile%" video_sec video_hms
if errorlevel 1 (
  echo [!] Could not read VIDEO duration with FFprobe.
  goto END
)

call "%~dp0lib\ffmpeg.bat" :GET_DURATION "%musicfile%" music_sec music_hms
if errorlevel 1 (
  echo [!] Could not read MUSIC duration with FFprobe.
  goto END
)

echo [INFO] Video duration: %video_hms%
echo [INFO] Music duration: %music_hms%

REM =========================
REM 4) Music start time
REM =========================
:MUSIC_START_LOOP
echo.
echo Enter music start time in HH:MM:SS
echo   FROM=00:00:00    TO=%music_hms%   (max = full music duration)
set "music_from_ts=00:00:00"
set /p "music_from_ts=Music start (Default: 00:00:00): "
set "music_from_ts=%music_from_ts: =%"

call "%~dp0lib\time.bat" :HMS_TO_SEC "%music_from_ts%" music_from_sec
if errorlevel 1 echo [Info] Invalid music start format. Use HH:MM:SS; minutes/seconds must be min 00 and max 59.& goto MUSIC_START_LOOP

if %music_from_sec% GEQ %music_sec% echo [Info] Music start is beyond music duration (%music_hms%). Choose an earlier time.& goto MUSIC_START_LOOP

REM =========================
REM 5) Processing mode
REM =========================
echo.
echo Choose processing mode:
echo   1) Copy VIDEO + encode new AUDIO  [default]
echo   2) Re-encode VIDEO + encode AUDIO
set /p "mode_sel=Select mode (Default: 1): "
if "%mode_sel:~0,1%"=="2" ( set "proc_mode=reencode" ) else ( set "proc_mode=copy" & goto ASK_OUTDIR )

call "%~dp0lib\ui.bat" :ASK_PRESET_AND_CODEC simple
call "%~dp0lib\ui.bat" :ASK_GPU_BACKEND "%codec_label%" %vcrf%

:ASK_OUTDIR
call "%~dp0lib\ui.bat" :ASK_OUTPUT
if errorlevel 1 goto END

REM =========================
REM 6) Do the work
REM =========================
echo.
echo Video:        %videofile%
echo Video length: %video_hms%
echo Music:        %musicfile%
echo Music start:  %music_from_ts%
echo Output:       %outfile%
echo.

if /i "%proc_mode%"=="copy" goto DO_COPY
goto DO_REENC

REM ---- Copy video + encode audio ----
:DO_COPY
echo Method: copy VIDEO + encode AAC AUDIO
setlocal DisableDelayedExpansion
"%FF%" -hide_banner -y ^
  -i "%videofile_esc%" ^
  -ss "%music_from_ts%" -i "%musicfile_esc%" ^
  -map 0:v:0 -map 1:a:0 ^
  -map_metadata 0 ^
  -t %video_sec% ^
  -c:v copy ^
  -c:a aac -b:a 192k ^
  -movflags +faststart ^
  "%outfile_esc%"
endlocal
if errorlevel 1 goto FAIL
goto SUCCESS

REM ---- Re-encode dispatch ----
:DO_REENC
echo Method: re-encode VIDEO + encode AAC AUDIO (codec: %codec_label%, preset: %x_preset%)
if /i "%gpu_mode%"=="nvenc" goto DO_NVENC
if /i "%gpu_mode%"=="qsv"   goto DO_QSV
if /i "%gpu_mode%"=="amf"   goto DO_AMF
if /i "%gpu_mode%"=="mf"    goto DO_MF
goto DO_CPU

:DO_NVENC
echo Backend: NVIDIA NVENC  (preset %nv_preset%, QP %nv_qp%)
setlocal DisableDelayedExpansion
if /i "%codec_label%"=="H.265" (
  "%FF%" -hide_banner -y ^
    -i "%videofile_esc%" ^
    -ss "%music_from_ts%" -i "%musicfile_esc%" ^
    -map 0:v:0 -map 1:a:0 ^
    -map_metadata 0 ^
    -t %video_sec% ^
    -c:v hevc_nvenc -preset %nv_preset% -rc constqp -qp %nv_qp% -tag:v hvc1 ^
    -c:a aac -b:a 192k ^
    -movflags +faststart ^
    "%outfile_esc%"
) else (
  "%FF%" -hide_banner -y ^
    -i "%videofile_esc%" ^
    -ss "%music_from_ts%" -i "%musicfile_esc%" ^
    -map 0:v:0 -map 1:a:0 ^
    -map_metadata 0 ^
    -t %video_sec% ^
    -c:v h264_nvenc -preset %nv_preset% -rc constqp -qp %nv_qp% ^
    -c:a aac -b:a 192k ^
    -movflags +faststart ^
    "%outfile_esc%"
)
endlocal
if errorlevel 1 goto FAIL
goto SUCCESS

:DO_QSV
echo Backend: Intel Quick Sync  (global_quality %qsv_gq%)
setlocal DisableDelayedExpansion
if /i "%codec_label%"=="H.265" (
  "%FF%" -hide_banner -y ^
    -i "%videofile_esc%" ^
    -ss "%music_from_ts%" -i "%musicfile_esc%" ^
    -map 0:v:0 -map 1:a:0 ^
    -map_metadata 0 ^
    -t %video_sec% ^
    -c:v hevc_qsv -global_quality %qsv_gq% -tag:v hvc1 ^
    -c:a aac -b:a 192k ^
    -movflags +faststart ^
    "%outfile_esc%"
) else (
  "%FF%" -hide_banner -y ^
    -i "%videofile_esc%" ^
    -ss "%music_from_ts%" -i "%musicfile_esc%" ^
    -map 0:v:0 -map 1:a:0 ^
    -map_metadata 0 ^
    -t %video_sec% ^
    -c:v h264_qsv -global_quality %qsv_gq% ^
    -c:a aac -b:a 192k ^
    -movflags +faststart ^
    "%outfile_esc%"
)
endlocal
if errorlevel 1 goto FAIL
goto SUCCESS

:DO_AMF
echo Backend: AMD AMF  (CQP QP I/P/B: %amf_qp_i% / %amf_qp_p% / %amf_qp_b%)
setlocal DisableDelayedExpansion
if /i "%codec_label%"=="H.265" (
  "%FF%" -hide_banner -y ^
    -i "%videofile_esc%" ^
    -ss "%music_from_ts%" -i "%musicfile_esc%" ^
    -map 0:v:0 -map 1:a:0 ^
    -map_metadata 0 ^
    -t %video_sec% ^
    -c:v hevc_amf -rc cqp -qp_i %amf_qp_i% -qp_p %amf_qp_p% -qp_b %amf_qp_b% -tag:v hvc1 ^
    -c:a aac -b:a 192k ^
    -movflags +faststart ^
    "%outfile_esc%"
) else (
  "%FF%" -hide_banner -y ^
    -i "%videofile_esc%" ^
    -ss "%music_from_ts%" -i "%musicfile_esc%" ^
    -map 0:v:0 -map 1:a:0 ^
    -map_metadata 0 ^
    -t %video_sec% ^
    -c:v h264_amf -rc cqp -qp_i %amf_qp_i% -qp_p %amf_qp_p% -qp_b %amf_qp_b% ^
    -c:a aac -b:a 192k ^
    -movflags +faststart ^
    "%outfile_esc%"
)
endlocal
if errorlevel 1 goto FAIL
goto SUCCESS

:DO_MF
echo Backend: Media Foundation  (bitrate %mf_bitrate%)
setlocal DisableDelayedExpansion
if /i "%codec_label%"=="H.265" (
  "%FF%" -hide_banner -y ^
    -i "%videofile_esc%" ^
    -ss "%music_from_ts%" -i "%musicfile_esc%" ^
    -map 0:v:0 -map 1:a:0 ^
    -map_metadata 0 ^
    -t %video_sec% ^
    -c:v hevc_mf -b:v %mf_bitrate% -tag:v hvc1 ^
    -c:a aac -b:a 192k ^
    -movflags +faststart ^
    "%outfile_esc%"
) else (
  "%FF%" -hide_banner -y ^
    -i "%videofile_esc%" ^
    -ss "%music_from_ts%" -i "%musicfile_esc%" ^
    -map 0:v:0 -map 1:a:0 ^
    -map_metadata 0 ^
    -t %video_sec% ^
    -c:v h264_mf -b:v %mf_bitrate% ^
    -c:a aac -b:a 192k ^
    -movflags +faststart ^
    "%outfile_esc%"
)
endlocal
if errorlevel 1 goto FAIL
goto SUCCESS

:DO_CPU
echo Backend: CPU (%vcodec%), CRF %vcrf%
setlocal DisableDelayedExpansion
if /i "%codec_label%"=="H.265" (
  "%FF%" -hide_banner -y ^
    -i "%videofile_esc%" ^
    -ss "%music_from_ts%" -i "%musicfile_esc%" ^
    -map 0:v:0 -map 1:a:0 ^
    -map_metadata 0 ^
    -t %video_sec% ^
    -c:v libx265 -preset %x_preset% -crf %vcrf% -tag:v hvc1 ^
    -c:a aac -b:a 192k ^
    -movflags +faststart ^
    "%outfile_esc%"
) else (
  "%FF%" -hide_banner -y ^
    -i "%videofile_esc%" ^
    -ss "%music_from_ts%" -i "%musicfile_esc%" ^
    -map 0:v:0 -map 1:a:0 ^
    -map_metadata 0 ^
    -t %video_sec% ^
    -c:v libx264 -preset %x_preset% -crf %vcrf% ^
    -c:a aac -b:a 192k ^
    -movflags +faststart ^
    "%outfile_esc%"
)
endlocal
if errorlevel 1 goto FAIL
goto SUCCESS

:SUCCESS
echo.
echo [OK] Done.
echo Full path: %outfile%
if /i "%proc_mode%"=="copy" (
  echo Method: copy VIDEO + encode AUDIO
) else (
  echo Method: re-encode VIDEO + encode AUDIO  ^(codec: %codec_label%; backend: %gpu_mode%^)
)
echo Note: original video audio was replaced by the selected music.
echo       Output length matches the video length.
goto END

:FAIL
echo.
echo [!] Error: processing failed for the selected backend or input combination.
echo     Tip: Select CPU or copy-video mode next time if GPU backend fails.

:END
echo.
pause
exit /b
