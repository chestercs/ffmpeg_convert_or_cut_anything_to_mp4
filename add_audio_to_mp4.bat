@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM =========================
REM 0) FFmpeg
REM =========================
call "%~dp0lib\ffmpeg.bat" :ENSURE_FFMPEG
if errorlevel 1 goto END

call "%~dp0lib\draw.bat" :INIT_COLORS
call "%~dp0lib\draw.bat" :HEADER_AUDIO

echo   %_CGr%Replaces the video's original audio with a music file.%_C0%
echo   %_CGr%Output length always matches the video length.%_C0%

REM =========================
REM 1) Input video file
REM =========================
call "%~dp0lib\draw.bat" :SECTION "VIDEO FILE"
echo   %_CY%Enter full path to the VIDEO file%_C0%  %_CGr%(or drag ^& drop it here)%_C0%
set /p "videofile="
if "%videofile%"=="" (
  echo.
  echo %_CR%  [!]  Video path cannot be empty.%_C0%
  goto END
)
for %%A in ("%videofile%") do set "videofile=%%~A"
if not exist "%videofile%" (
  echo.
  echo %_CR%  [!]  Video file not found:%_C0%  %videofile%
  goto END
)
call "%~dp0lib\ui.bat" :ESCAPE_PATH videofile videofile_esc

REM =========================
REM 2) Input music file
REM =========================
call "%~dp0lib\draw.bat" :SECTION "MUSIC FILE"
echo   %_CY%Enter full path to the MUSIC file%_C0%  %_CGr%(or drag ^& drop it here)%_C0%
set /p "musicfile="
if "%musicfile%"=="" (
  echo.
  echo %_CR%  [!]  Music path cannot be empty.%_C0%
  goto END
)
for %%A in ("%musicfile%") do set "musicfile=%%~A"
if not exist "%musicfile%" (
  echo.
  echo %_CR%  [!]  Music file not found:%_C0%  %musicfile%
  goto END
)
call "%~dp0lib\ui.bat" :ESCAPE_PATH musicfile musicfile_esc

REM =========================
REM 3) Probe durations
REM =========================
echo.
echo   %_CGr%Reading media durations...%_C0%

call "%~dp0lib\ffmpeg.bat" :GET_DURATION "%videofile%" video_sec video_hms
if errorlevel 1 (
  echo.
  echo %_CR%  [!]  Could not read VIDEO duration via ffprobe.%_C0%
  goto END
)

call "%~dp0lib\ffmpeg.bat" :GET_DURATION "%musicfile%" music_sec music_hms
if errorlevel 1 (
  echo.
  echo %_CR%  [!]  Could not read MUSIC duration via ffprobe.%_C0%
  goto END
)

echo   %_CGr%Video duration:%_C0%  %_CW%%video_hms%%_C0%
echo   %_CGr%Music duration:%_C0%  %_CW%%music_hms%%_C0%

REM =========================
REM 4) Music start time
REM =========================
:MUSIC_START_LOOP
call "%~dp0lib\draw.bat" :SECTION "MUSIC START TIME"
echo   %_CGr%Music duration:%_C0%  %_CW%%music_hms%%_C0%
echo.
set "music_from_ts=00:00:00"
echo   %_CY%Start time in music [HH:MM:SS, default: 00:00:00]%_C0%
set /p "music_from_ts="
set "music_from_ts=%music_from_ts: =%"

call "%~dp0lib\time.bat" :HMS_TO_SEC "%music_from_ts%" music_from_sec
if errorlevel 1 (
  echo   %_CY%[Info]%_C0%  Invalid format. Use HH:MM:SS; minutes/seconds 00-59.
  goto MUSIC_START_LOOP
)
if %music_from_sec% GEQ %music_sec% (
  echo   %_CY%[Info]%_C0%  Start is beyond music duration ^(%music_hms%^). Choose an earlier time.
  goto MUSIC_START_LOOP
)

REM =========================
REM 5) Processing mode
REM =========================
call "%~dp0lib\draw.bat" :SECTION "PROCESSING MODE"
call "%~dp0lib\draw.bat" :MENUITEM "1" "Copy VIDEO + encode AUDIO" "(default; fast)"
call "%~dp0lib\draw.bat" :MENUITEM "2" "Re-encode VIDEO + encode AUDIO" "(slower; choose codec + GPU)"
echo.
echo   %_CY%Select [1-2, default: 1]%_C0%
set /p "mode_sel="
if "%mode_sel:~0,1%"=="2" ( set "proc_mode=reencode" ) else ( set "proc_mode=copy" & goto ASK_OUTDIR )

call "%~dp0lib\ui.bat" :ASK_PRESET_AND_CODEC simple
call "%~dp0lib\ui.bat" :ASK_GPU_BACKEND "%codec_label%" %vcrf%

:ASK_OUTDIR
call "%~dp0lib\ui.bat" :ASK_OUTPUT
if errorlevel 1 goto END

REM =========================
REM 6) Summary
REM =========================
call "%~dp0lib\draw.bat" :SECTION "SUMMARY"
call "%~dp0lib\draw.bat" :KV "Video      :" "%videofile%"
call "%~dp0lib\draw.bat" :KV "Video len  :" "%video_hms%"
call "%~dp0lib\draw.bat" :KV "Music      :" "%musicfile%"
call "%~dp0lib\draw.bat" :KV "Music start:" "%music_from_ts%"
call "%~dp0lib\draw.bat" :KV "Output     :" "%outfile%"
echo.

if /i "%proc_mode%"=="copy" goto DO_COPY
goto DO_REENC

REM ---- Copy video + encode audio ----
:DO_COPY
call "%~dp0lib\draw.bat" :KV "Method     :" "copy VIDEO + encode AAC AUDIO"
echo.
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
call "%~dp0lib\draw.bat" :KV "Method     :" "re-encode VIDEO + AAC AUDIO  ^(codec: %codec_label%, backend: %gpu_mode%^)"
echo.
if /i "%gpu_mode%"=="nvenc" goto DO_NVENC
if /i "%gpu_mode%"=="qsv"   goto DO_QSV
if /i "%gpu_mode%"=="amf"   goto DO_AMF
if /i "%gpu_mode%"=="mf"    goto DO_MF
goto DO_CPU

:DO_NVENC
setlocal DisableDelayedExpansion
if /i "%codec_label%"=="H.265" (
  "%FF%" -hide_banner -y ^
    -i "%videofile_esc%" ^
    -ss "%music_from_ts%" -i "%musicfile_esc%" ^
    -map 0:v:0 -map 1:a:0 -map_metadata 0 ^
    -t %video_sec% ^
    -c:v hevc_nvenc -preset %nv_preset% -rc constqp -qp %nv_qp% -tag:v hvc1 ^
    -c:a aac -b:a 192k -movflags +faststart ^
    "%outfile_esc%"
) else (
  "%FF%" -hide_banner -y ^
    -i "%videofile_esc%" ^
    -ss "%music_from_ts%" -i "%musicfile_esc%" ^
    -map 0:v:0 -map 1:a:0 -map_metadata 0 ^
    -t %video_sec% ^
    -c:v h264_nvenc -preset %nv_preset% -rc constqp -qp %nv_qp% ^
    -c:a aac -b:a 192k -movflags +faststart ^
    "%outfile_esc%"
)
endlocal
if errorlevel 1 goto FAIL
goto SUCCESS

:DO_QSV
setlocal DisableDelayedExpansion
if /i "%codec_label%"=="H.265" (
  "%FF%" -hide_banner -y ^
    -i "%videofile_esc%" ^
    -ss "%music_from_ts%" -i "%musicfile_esc%" ^
    -map 0:v:0 -map 1:a:0 -map_metadata 0 ^
    -t %video_sec% ^
    -c:v hevc_qsv -global_quality %qsv_gq% -tag:v hvc1 ^
    -c:a aac -b:a 192k -movflags +faststart ^
    "%outfile_esc%"
) else (
  "%FF%" -hide_banner -y ^
    -i "%videofile_esc%" ^
    -ss "%music_from_ts%" -i "%musicfile_esc%" ^
    -map 0:v:0 -map 1:a:0 -map_metadata 0 ^
    -t %video_sec% ^
    -c:v h264_qsv -global_quality %qsv_gq% ^
    -c:a aac -b:a 192k -movflags +faststart ^
    "%outfile_esc%"
)
endlocal
if errorlevel 1 goto FAIL
goto SUCCESS

:DO_AMF
setlocal DisableDelayedExpansion
if /i "%codec_label%"=="H.265" (
  "%FF%" -hide_banner -y ^
    -i "%videofile_esc%" ^
    -ss "%music_from_ts%" -i "%musicfile_esc%" ^
    -map 0:v:0 -map 1:a:0 -map_metadata 0 ^
    -t %video_sec% ^
    -c:v hevc_amf -rc cqp -qp_i %amf_qp_i% -qp_p %amf_qp_p% -qp_b %amf_qp_b% -tag:v hvc1 ^
    -c:a aac -b:a 192k -movflags +faststart ^
    "%outfile_esc%"
) else (
  "%FF%" -hide_banner -y ^
    -i "%videofile_esc%" ^
    -ss "%music_from_ts%" -i "%musicfile_esc%" ^
    -map 0:v:0 -map 1:a:0 -map_metadata 0 ^
    -t %video_sec% ^
    -c:v h264_amf -rc cqp -qp_i %amf_qp_i% -qp_p %amf_qp_p% -qp_b %amf_qp_b% ^
    -c:a aac -b:a 192k -movflags +faststart ^
    "%outfile_esc%"
)
endlocal
if errorlevel 1 goto FAIL
goto SUCCESS

:DO_MF
setlocal DisableDelayedExpansion
if /i "%codec_label%"=="H.265" (
  "%FF%" -hide_banner -y ^
    -i "%videofile_esc%" ^
    -ss "%music_from_ts%" -i "%musicfile_esc%" ^
    -map 0:v:0 -map 1:a:0 -map_metadata 0 ^
    -t %video_sec% ^
    -c:v hevc_mf -b:v %mf_bitrate% -tag:v hvc1 ^
    -c:a aac -b:a 192k -movflags +faststart ^
    "%outfile_esc%"
) else (
  "%FF%" -hide_banner -y ^
    -i "%videofile_esc%" ^
    -ss "%music_from_ts%" -i "%musicfile_esc%" ^
    -map 0:v:0 -map 1:a:0 -map_metadata 0 ^
    -t %video_sec% ^
    -c:v h264_mf -b:v %mf_bitrate% ^
    -c:a aac -b:a 192k -movflags +faststart ^
    "%outfile_esc%"
)
endlocal
if errorlevel 1 goto FAIL
goto SUCCESS

:DO_CPU
setlocal DisableDelayedExpansion
if /i "%codec_label%"=="H.265" (
  "%FF%" -hide_banner -y ^
    -i "%videofile_esc%" ^
    -ss "%music_from_ts%" -i "%musicfile_esc%" ^
    -map 0:v:0 -map 1:a:0 -map_metadata 0 ^
    -t %video_sec% ^
    -c:v libx265 -preset %x_preset% -crf %vcrf% -tag:v hvc1 ^
    -c:a aac -b:a 192k -movflags +faststart ^
    "%outfile_esc%"
) else (
  "%FF%" -hide_banner -y ^
    -i "%videofile_esc%" ^
    -ss "%music_from_ts%" -i "%musicfile_esc%" ^
    -map 0:v:0 -map 1:a:0 -map_metadata 0 ^
    -t %video_sec% ^
    -c:v libx264 -preset %x_preset% -crf %vcrf% ^
    -c:a aac -b:a 192k -movflags +faststart ^
    "%outfile_esc%"
)
endlocal
if errorlevel 1 goto FAIL
goto SUCCESS

:SUCCESS
call "%~dp0lib\draw.bat" :OK "%outfile%"
echo   %_CGr%Original audio was replaced by the selected music.%_C0%
goto END

:FAIL
call "%~dp0lib\draw.bat" :FAIL_MSG

:END
echo.
pause
exit /b
