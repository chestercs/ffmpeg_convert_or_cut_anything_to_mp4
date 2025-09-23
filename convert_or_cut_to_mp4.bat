@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM =========================
REM 0) Check ffmpeg / optional winget install
REM =========================
set "FFMPEG_EXE="
call :FIND_FFMPEG
if defined FFMPEG_EXE goto FF_OK

echo.
echo [!] ffmpeg was not found on this system.
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
echo Installing ffmpeg with winget...
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
  echo [!] ffmpeg installed, but PATH did not refresh in this window.
  echo     Close this terminal and rerun the script.
  goto END
)

:FF_OK
set "FF=%FFMPEG_EXE%"
if not defined FF set "FF=ffmpeg"
echo Using ffmpeg: "%FF%"

REM Resolve ffprobe next to ffmpeg, else from PATH
set "FFPROBE=ffprobe"
for %%D in ("%FFMPEG_EXE%") do if exist "%%~dpDffprobe.exe" set "FFPROBE=%%~dpDffprobe.exe"
echo Using ffprobe: "%FFPROBE%"

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

REM Escape special CMD chars in paths (& | < > ^) + parentheses
set "infile_esc=%infile%"
set "infile_esc=%infile_esc:^=^^%"
set "infile_esc=%infile_esc:&=^&%"
set "infile_esc=%infile_esc:|=^|%"
set "infile_esc=%infile_esc:<=^<%"
set "infile_esc=%infile_esc:>=^>%"
set "infile_esc=%infile_esc:(=^(%"
set "infile_esc=%infile_esc:)=^)%"

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

if /i "%do_cut%"=="yes" goto PROBE_DURATION
goto ASK_MODE

REM =========================
REM 2/b) PROBE DURATION (only if cutting) — TEMP FILE BASED, SAFE DEBUG
REM =========================
:PROBE_DURATION
set "DEBUG_PROBE=0"

set "dur_raw="
set "dur_sec="

set "TMPDUR=%TEMP%\ffprobe_dur_%RANDOM%.txt"
set "TMPDBG=%TEMP%\ffprobe_dbg_%RANDOM%.txt"
if exist "%TMPDUR%" del /q "%TMPDUR%" >nul 2>&1
if exist "%TMPDBG%" del /q "%TMPDBG%" >nul 2>&1

REM Try default wrapper, then CSV fallback if needed
"%FFPROBE%" -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "%infile%" 1>"%TMPDUR%" 2>"%TMPDBG%"
for %%# in ("%TMPDUR%") do if %%~z# LSS 2 (
  "%FFPROBE%" -v error -show_entries format=duration -of csv=p=0 "%infile%" 1>"%TMPDUR%" 2>>"%TMPDBG%"
)

if exist "%TMPDUR%" set /p "dur_raw=" < "%TMPDUR%"
for /f "tokens=* delims= " %%A in ("%dur_raw%") do set "dur_raw=%%A"
if defined dur_raw for /f "tokens=1 delims=., " %%E in ("%dur_raw%") do set "dur_sec=%%E"
for /f "delims=0123456789" %%Z in ("%dur_sec%") do set "dur_sec="
if not defined dur_sec set "dur_sec=0"

if %dur_sec% LEQ 0 (
  echo.
  echo [!] Could not read media duration with ffprobe. Cannot safely cut.
  echo     Check that ffprobe is available and the file is readable.
  if "%DEBUG_PROBE%"=="1" (
    echo DBG> FFPROBE=%FFPROBE%
    echo DBG> infile = %infile%
    echo DBG> dur_raw="%dur_raw%"
  )
  goto END
)

call :SEC_TO_HMS %dur_sec% dur_hms
if "%DEBUG_PROBE%"=="1" echo DBG> duration=%dur_sec% sec  (%dur_hms%)

goto ASK_TIMES

REM =========================
REM 3) Ask + VALIDATE times (pure batch, bounded by duration)
REM =========================
:ASK_TIMES
:TIMES_LOOP
echo.
echo Enter times in HH:MM:SS
echo   FROM=00:00:00    TO=%dur_hms%   (max = full duration)
set "from_ts=" & set "to_ts="
set /p "from_ts=FROM time (HH:MM:SS): "
set /p "to_ts=TO   time (HH:MM:SS): "

REM Hard-trim all spaces to dodge shell-added trailing spaces
set "from_ts=%from_ts: =%"
set "to_ts=%to_ts: =%"

if not defined from_ts echo [Info] FROM cannot be empty. Use HH:MM:SS (e.g. 00:00:00).& goto TIMES_LOOP
if not defined to_ts   echo [Info] TO cannot be empty.   Use HH:MM:SS (e.g. %dur_hms%).& goto TIMES_LOOP

call :HMS_TO_SEC "%from_ts%" from_sec
if errorlevel 1 echo [Info] Invalid FROM format. Use HH:MM:SS; minutes/seconds must be min 00 and max 59.& goto TIMES_LOOP

call :HMS_TO_SEC "%to_ts%" to_sec
if errorlevel 1 echo [Info] Invalid TO format. Use HH:MM:SS; minutes/seconds must be min 00 and max 59.& goto TIMES_LOOP

if %from_sec% LSS 0 echo [Info] FROM must be >= 00:00:00.& goto TIMES_LOOP
if %from_sec% GEQ %dur_sec% echo [Info] FROM is beyond duration (%dur_hms%). Choose an earlier time.& goto TIMES_LOOP
if %to_sec%   LEQ %from_sec% echo [Info] TO must be strictly greater than FROM.& goto TIMES_LOOP

set "CLAMPED_TO="
if %to_sec% GTR %dur_sec% (
  set "to_sec=%dur_sec%"
  set "CLAMPED_TO=1"
)

set /a t_sec=to_sec-from_sec
if %t_sec% LEQ 0 echo [Info] Computed length is not positive. Please re-enter times.& goto TIMES_LOOP

call :SEC_TO_HMS %from_sec% from_ts
call :SEC_TO_HMS %to_sec%   to_ts

if defined CLAMPED_TO echo [Info] TO exceeded media duration; trimmed to %to_ts%.

goto ASK_MODE

REM =========================
REM 4) Processing mode
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

REM =========================
REM 4/b) GPU backend menu (no availability hints, no probing)
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

REM Configure per-backend params
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
REM 5) Output directory (default: Downloads)
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
REM 6) Output filename (without .mp4) + robust timestamp
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

REM Escape output path (& | < > ^) + parentheses
set "outfile_esc=%outfile%"
set "outfile_esc=%outfile_esc:^=^^%"
set "outfile_esc=%outfile_esc:&=^&%"
set "outfile_esc=%outfile_esc:|=^|%"
set "outfile_esc=%outfile_esc:<=^<%"
set "outfile_esc=%outfile_esc:>=^>%"
set "outfile_esc=%outfile_esc:(=^(%"
set "outfile_esc=%outfile_esc:)=^)%"

REM =========================
REM 7) Do the work
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
