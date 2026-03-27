@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM =========================
REM 0) Check FFmpeg / optional winget install
REM =========================
set "FFMPEG_EXE="
call :FIND_FFMPEG
if defined FFMPEG_EXE goto FF_OK

echo.
echo [ERROR] FFmpeg was not found on this system.
echo.
set "ans=Y"
set /p "ans=Install via winget? [Y/N] (Default: Y): "
if /I "%ans%"=="N" (
  echo.
  echo Aborted.
  goto END
)

where winget >nul 2>&1
if errorlevel 1 (
  echo.
  echo [!] winget is not available. Please install "App Installer" from Microsoft Store.
  goto END
)

echo.
echo Installing FFmpeg with winget...
winget install --id Gyan.FFmpeg -e --source winget
if errorlevel 1 (
  echo.
  echo [!] Installation failed.
  goto END
)

set "FFMPEG_EXE="
call :FIND_FFMPEG
if not defined FFMPEG_EXE (
  echo.
  echo [!] FFmpeg installed, but PATH did not refresh in this window.
  echo     Close this terminal and rerun the script.
  goto END
)

:FF_OK
set "FF=%FFMPEG_EXE%"
if not defined FF set "FF=ffmpeg"
echo [INFO] Using FFmpeg: "%FF%"

set "FFPROBE=ffprobe"
for %%D in ("%FFMPEG_EXE%") do if exist "%%~dpDffprobe.exe" set "FFPROBE=%%~dpDffprobe.exe"
echo [INFO] Using FFprobe: "%FFPROBE%"

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
REM 1) Input VIDEO file path
REM =========================
echo.
set /p "videofile=Enter FULL PATH to the VIDEO file: "
if "%videofile%"=="" (
  echo [!] Video path cannot be empty.
  goto END
)
for %%A in ("%videofile%") do (
  set "videofile=%%~A"
)
if not exist "%videofile%" (
  echo [!] Video file not found: %videofile%
  goto END
)

set "videofile_esc=%videofile%"
set "videofile_esc=%videofile_esc:^=^^%"
set "videofile_esc=%videofile_esc:&=^&%"
set "videofile_esc=%videofile_esc:|=^|%"
set "videofile_esc=%videofile_esc:<=^<%"
set "videofile_esc=%videofile_esc:>=^>%"
set "videofile_esc=%videofile_esc:(=^(%"
set "videofile_esc=%videofile_esc:)=^)%"

REM =========================
REM 2) Input MUSIC file path
REM =========================
echo.
set /p "musicfile=Enter FULL PATH to the MUSIC file: "
if "%musicfile%"=="" (
  echo [!] Music path cannot be empty.
  goto END
)
for %%A in ("%musicfile%") do (
  set "musicfile=%%~A"
)
if not exist "%musicfile%" (
  echo [!] Music file not found: %musicfile%
  goto END
)

set "musicfile_esc=%musicfile%"
set "musicfile_esc=%musicfile_esc:^=^^%"
set "musicfile_esc=%musicfile_esc:&=^&%"
set "musicfile_esc=%musicfile_esc:|=^|%"
set "musicfile_esc=%musicfile_esc:<=^<%"
set "musicfile_esc=%musicfile_esc:>=^>%"
set "musicfile_esc=%musicfile_esc:(=^(%"
set "musicfile_esc=%musicfile_esc:)=^)%"

REM =========================
REM 3) Probe durations
REM =========================
echo.
echo Reading media durations...

call :PROBE_DURATION "%videofile%" video_sec video_hms
if errorlevel 1 (
  echo [!] Could not read VIDEO duration with FFprobe.
  goto END
)

call :PROBE_DURATION "%musicfile%" music_sec music_hms
if errorlevel 1 (
  echo [!] Could not read MUSIC duration with FFprobe.
  goto END
)

echo [INFO] Video duration: %video_hms%
echo [INFO] Music duration: %music_hms%

REM =========================
REM 4) Ask + VALIDATE music start (same logic as original script)
REM =========================
:ASK_MUSIC_START
:MUSIC_START_LOOP
echo.
echo Enter music start time in HH:MM:SS
echo   FROM=00:00:00    TO=%music_hms%   (max = full music duration)
set "music_from_ts="
set /p "music_from_ts=Music start (Default: 00:00:00): "

REM Hard-trim all spaces exactly like in the original script
set "music_from_ts=%music_from_ts: =%"

REM Empty enter = default
if not defined music_from_ts set "music_from_ts=00:00:00"

call :HMS_TO_SEC "%music_from_ts%" music_from_sec
if errorlevel 1 echo [Info] Invalid music start format. Use HH:MM:SS; minutes/seconds must be min 00 and max 59.& goto MUSIC_START_LOOP

if %music_from_sec% LSS 0 echo [Info] Music start must be >= 00:00:00.& goto MUSIC_START_LOOP
if %music_from_sec% GEQ %music_sec% echo [Info] Music start is beyond music duration (%music_hms%). Choose an earlier time.& goto MUSIC_START_LOOP

set /a music_left_sec=music_sec-music_from_sec
call :SEC_TO_HMS %music_left_sec% music_left_hms

REM =========================
REM 5) Processing mode
REM =========================
echo.
echo Choose processing mode:
echo   1) Copy VIDEO + encode new AUDIO  [fastest; default]
echo   2) Re-encode VIDEO + encode AUDIO [slower]
set /p "mode_sel=Select mode (Default: 1): "
if "%mode_sel%"=="2" ( set "proc_mode=reencode" & goto ASK_PRESET ) else ( set "proc_mode=copy" & goto ASK_OUTDIR )

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

set "vcodec=libx264"
set "vcrf=20"
set "codec_label=H.264"
echo.
echo Select video codec:
echo   1) H.264 / AVC (libx264)  [default; widest compatibility]
echo   2) H.265 / HEVC (libx265) [smaller files; slower; may be less compatible]
set /p "codec_sel=Select codec (Default: 1): "
if "%codec_sel%"=="2" goto TRY_X265
goto ASK_GPU

:TRY_X265
"%FF%" -v error -hide_banner -encoders | findstr /i " libx265 " >nul
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

REM =========================
REM 6) Output directory
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
REM 7) Output filename
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

set "outfile_esc=%outfile%"
set "outfile_esc=%outfile_esc:^=^^%"
set "outfile_esc=%outfile_esc:&=^&%"
set "outfile_esc=%outfile_esc:|=^|%"
set "outfile_esc=%outfile_esc:<=^<%"
set "outfile_esc=%outfile_esc:>=^>%"
set "outfile_esc=%outfile_esc:(=^(%"
set "outfile_esc=%outfile_esc:)=^)%"

REM =========================
REM 8) Do the work
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
  echo Method: re-encode VIDEO + encode AUDIO  (codec: %codec_label%; backend: %gpu_mode%)
)
echo Note: original video audio was replaced by the selected music.
echo       Output length matches the video length.
goto END

:FAIL
echo.
echo [!] Error: processing failed for the selected backend or input combination.
echo     Tip: Select CPU or copy-video mode next time if GPU backend fails.
goto END

:END
echo.
pause
exit /b

REM ============================================================
REM Helper: FIND_FFMPEG -> sets FFMPEG_EXE if found
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
      goto :FIND_DONE
    )
  )
)
if not defined FFMPEG_EXE if exist "%ProgramFiles%\ffmpeg\bin\ffmpeg.exe" (
  set "FFMPEG_EXE=%ProgramFiles%\ffmpeg\bin\ffmpeg.exe"
)
:FIND_DONE
exit /b 0

REM ============================================================
REM Helper: PROBE_DURATION "file" out_sec out_hms
REM ============================================================
:PROBE_DURATION
setlocal EnableExtensions DisableDelayedExpansion
set "probe_file=%~1"
set "dur_raw="
set "dur_sec="
set "dur_hms="
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

if %dur_sec% LEQ 0 (
  endlocal & exit /b 1
)

call :SEC_TO_HMS %dur_sec% dur_hms
endlocal & set "%~2=%dur_sec%" & set "%~3=%dur_hms%" & exit /b 0

REM ============================================================
REM Helper: SEC_TO_HMS seconds -> HH:MM:SS (zero-padded)
REM Usage: call :SEC_TO_HMS 754 outvar
REM ============================================================
:SEC_TO_HMS
setlocal EnableDelayedExpansion
set /a _T=%~1
if !_T! LSS 0 set /a _T=0
set /a H=_T/3600, R=_T%%3600, M=R/60, S=R%%60
set "HH=0!H!" & set "MM=0!M!" & set "SS=0!S!"
set "HH=!HH:~-2!" & set "MM=!MM:~-2!" & set "SS=!SS:~-2!"
endlocal & set "%~2=%HH%:%MM%:%SS%" & exit /b 0

REM ============================================================
REM Helper: HMS_TO_SEC "HH:MM:SS" -> seconds (pure batch)
REM Validates HH:MM:SS with minute/second 0–59.
REM Usage: call :HMS_TO_SEC "00:12:34" outvar  || (errorlevel 1)
REM ============================================================
:HMS_TO_SEC
setlocal EnableDelayedExpansion
set "in=%~1"
REM remove all spaces defensively
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
endlocal & set "%~2=%total%" & exit /b 0