@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "ROOT=%~dp0.."
set "ASSETS=%~dp0assets"
set "OUT=%~dp0tmp_output"
set "PASS=0"
set "FAIL=0"

echo.
echo ===================================================
echo   ChesTeRcs VegasVibe - Automated Test Suite
echo ===================================================
echo.

REM ===================================================
REM  FFmpeg
REM ===================================================
call "%ROOT%\lib\ffmpeg.bat" :ENSURE_FFMPEG
if errorlevel 1 (
  echo [!] FFmpeg required to run tests.
  goto SUMMARY
)
echo.

REM ===================================================
REM  Directories
REM ===================================================
if not exist "%ASSETS%" mkdir "%ASSETS%"
if not exist "%OUT%"     mkdir "%OUT%"

REM ===================================================
REM  Test assets  (generated once; delete to regenerate)
REM ===================================================
echo Checking test assets...
if not exist "%ASSETS%\test_video.mp4" (
  echo   Generating test_video.mp4  ^(30s 320x240 H264+AAC^)...
  "%FF%" -hide_banner -y ^
    -f lavfi -i "testsrc=duration=30:size=320x240:rate=25" ^
    -f lavfi -i "sine=frequency=440:duration=30" ^
    -c:v libx264 -preset ultrafast -crf 28 ^
    -c:a aac -b:a 64k ^
    "%ASSETS%\test_video.mp4" >nul 2>&1
  if errorlevel 1 ( echo [!] Failed to generate test_video.mp4 & goto SUMMARY )
)
if not exist "%ASSETS%\test_audio.mp3" (
  echo   Generating test_audio.mp3  ^(60s 440Hz sine^)...
  "%FF%" -hide_banner -y ^
    -f lavfi -i "sine=frequency=440:duration=60" ^
    -c:a libmp3lame -b:a 64k ^
    "%ASSETS%\test_audio.mp3" >nul 2>&1
  if errorlevel 1 ( echo [!] Failed to generate test_audio.mp3 & goto SUMMARY )
)
echo Assets OK.
echo.

REM ===================================================
REM  convert_or_cut_to_mp4.bat
REM ===================================================
echo ---------------------------------------------------
echo  convert_or_cut_to_mp4.bat
echo ---------------------------------------------------
echo.

REM ---- TC01: Convert whole file, stream copy ----
REM Inputs:
REM   1: input file path
REM   2: action  (Enter = 1 = convert whole)
REM   3: mode    (Enter = 1 = stream copy)
REM   4: outdir
REM   5: filename
REM   6: pause
(
  echo %ASSETS%\test_video.mp4
  echo.
  echo.
  echo %OUT%
  echo TC01
  echo.
) > "%OUT%\_input.txt"
call "%ROOT%\convert_or_cut_to_mp4.bat" < "%OUT%\_input.txt" > "%OUT%\_TC01.log" 2>&1
call :CHECK "TC01" "Convert whole - stream copy" "%OUT%\TC01.mp4" 30 3

REM ---- TC02: Cut 5-20s, stream copy ----
REM Inputs:
REM   1: input file path
REM   2: action = 2 (cut)
REM   3: from   = 00:00:05
REM   4: to     = 00:00:20
REM   5: mode   (Enter = 1 = stream copy)
REM   6: outdir
REM   7: filename
REM   8: pause
(
  echo %ASSETS%\test_video.mp4
  echo 2
  echo 00:00:05
  echo 00:00:20
  echo.
  echo %OUT%
  echo TC02
  echo.
) > "%OUT%\_input.txt"
call "%ROOT%\convert_or_cut_to_mp4.bat" < "%OUT%\_input.txt" > "%OUT%\_TC02.log" 2>&1
call :CHECK "TC02" "Cut 5-20s - stream copy" "%OUT%\TC02.mp4" 15 3

REM ---- TC03: Cut 5-20s, re-encode CPU H.264 (all defaults) ----
REM Inputs:
REM   1: input file path
REM   2: action = 2 (cut)
REM   3: from   = 00:00:05
REM   4: to     = 00:00:20
REM   5: mode = 2 (re-encode)
REM   6: preset  (Enter = veryfast)
REM   7: codec   (Enter = H.264)
REM   8: backend (Enter = CPU)
REM   9: outdir
REM  10: filename
REM  11: pause
(
  echo %ASSETS%\test_video.mp4
  echo 2
  echo 00:00:05
  echo 00:00:20
  echo 2
  echo.
  echo.
  echo.
  echo %OUT%
  echo TC03
  echo.
) > "%OUT%\_input.txt"
call "%ROOT%\convert_or_cut_to_mp4.bat" < "%OUT%\_input.txt" > "%OUT%\_TC03.log" 2>&1
call :CHECK "TC03" "Cut 5-20s - re-encode CPU H.264" "%OUT%\TC03.mp4" 15 2

REM ---- TC04: Convert whole file, re-encode CPU H.264 (all defaults) ----
REM Inputs:
REM   1: input file path
REM   2: action  (Enter = 1 = convert whole)
REM   3: mode = 2 (re-encode)
REM   4: preset  (Enter = veryfast)
REM   5: codec   (Enter = H.264)
REM   6: backend (Enter = CPU)
REM   7: outdir
REM   8: filename
REM   9: pause
(
  echo %ASSETS%\test_video.mp4
  echo.
  echo 2
  echo.
  echo.
  echo.
  echo %OUT%
  echo TC04
  echo.
) > "%OUT%\_input.txt"
call "%ROOT%\convert_or_cut_to_mp4.bat" < "%OUT%\_input.txt" > "%OUT%\_TC04.log" 2>&1
call :CHECK "TC04" "Convert whole - re-encode CPU H.264" "%OUT%\TC04.mp4" 30 2

echo.
echo ---------------------------------------------------
echo  add_audio_to_mp4.bat
echo ---------------------------------------------------
echo.

REM ---- TC05: Replace audio from start, copy video (default) ----
REM Inputs:
REM   1: video file
REM   2: music file
REM   3: music start (Enter = 00:00:00)
REM   4: mode        (Enter = 1 = copy video)
REM   5: outdir
REM   6: filename
REM   7: pause
(
  echo %ASSETS%\test_video.mp4
  echo %ASSETS%\test_audio.mp3
  echo.
  echo.
  echo %OUT%
  echo TC05
  echo.
) > "%OUT%\_input.txt"
call "%ROOT%\add_audio_to_mp4.bat" < "%OUT%\_input.txt" > "%OUT%\_TC05.log" 2>&1
call :CHECK "TC05" "Replace audio from start - copy video" "%OUT%\TC05.mp4" 30 3

REM ---- TC06: Replace audio from 10s offset, copy video ----
REM Inputs:
REM   1: video file
REM   2: music file
REM   3: music start = 00:00:10
REM   4: mode        (Enter = 1 = copy video)
REM   5: outdir
REM   6: filename
REM   7: pause
(
  echo %ASSETS%\test_video.mp4
  echo %ASSETS%\test_audio.mp3
  echo 00:00:10
  echo.
  echo %OUT%
  echo TC06
  echo.
) > "%OUT%\_input.txt"
call "%ROOT%\add_audio_to_mp4.bat" < "%OUT%\_input.txt" > "%OUT%\_TC06.log" 2>&1
call :CHECK "TC06" "Replace audio from 10s offset - copy video" "%OUT%\TC06.mp4" 30 3

REM ---- TC07: Replace audio, re-encode video CPU H.264 (all defaults) ----
REM Inputs:
REM   1: video file
REM   2: music file
REM   3: music start (Enter = 00:00:00)
REM   4: mode = 2 (re-encode)
REM   5: preset  (Enter = veryfast)
REM   6: codec   (Enter = H.264)
REM   7: backend (Enter = CPU)
REM   8: outdir
REM   9: filename
REM  10: pause
(
  echo %ASSETS%\test_video.mp4
  echo %ASSETS%\test_audio.mp3
  echo.
  echo 2
  echo.
  echo.
  echo.
  echo %OUT%
  echo TC07
  echo.
) > "%OUT%\_input.txt"
call "%ROOT%\add_audio_to_mp4.bat" < "%OUT%\_input.txt" > "%OUT%\_TC07.log" 2>&1
call :CHECK "TC07" "Replace audio - re-encode CPU H.264" "%OUT%\TC07.mp4" 30 2

REM ===================================================
REM  Cleanup temp files
REM ===================================================
if exist "%OUT%\_input.txt" del /q "%OUT%\_input.txt" >nul 2>&1
if exist "%OUT%\_probe.txt" del /q "%OUT%\_probe.txt" >nul 2>&1

goto SUMMARY

REM ===================================================
REM :CHECK  id  desc  outfile  expected_sec  tolerance_sec
REM   Checks that outfile exists and its duration is
REM   within expected_sec +/- tolerance_sec.
REM   Updates PASS / FAIL counters.
REM ===================================================
:CHECK
set "_id=%~1"
set "_desc=%~2"
set "_file=%~3"
set "_exp=%~4"
set "_tol=%~5"

if not exist "%_file%" (
  set /a FAIL+=1
  echo [FAIL] !_id! - !_desc!
  echo        Output file not found.
  echo        Log: %OUT%\_!_id!.log
  exit /b 0
)

REM Get duration (integer seconds) via ffprobe
REM  Use for/f to read the probe file — avoids any stdin dependency
set "_dur="
"%FFPROBE%" -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "%_file%" > "%OUT%\_probe.txt" 2>nul
set "_dur_raw="
for /f "usebackq tokens=*" %%L in ("%OUT%\_probe.txt") do if not defined _dur_raw set "_dur_raw=%%L"
for /f "tokens=1 delims=." %%A in ("!_dur_raw!") do set "_dur=%%A"
for /f "delims=0123456789" %%Z in ("!_dur!") do set "_dur="

if not defined _dur (
  set /a FAIL+=1
  echo [FAIL] !_id! - !_desc!
  echo        Could not read output duration.
  echo        Log: %OUT%\_!_id!.log
  exit /b 0
)

set /a "_diff=!_dur!-!_exp!"
if !_diff! LSS 0 set /a "_diff=0-!_diff!"
if !_diff! LEQ !_tol! (
  set /a PASS+=1
  echo [PASS] !_id! - !_desc!  ^(duration=!_dur!s, expected ~!_exp!s^)
) else (
  set /a FAIL+=1
  echo [FAIL] !_id! - !_desc!
  echo        duration=!_dur!s, expected ~!_exp!s  ^(tolerance +-!_tol!s^)
  echo        Log: %OUT%\_!_id!.log
)
exit /b 0

REM ===================================================
REM :SUMMARY
REM ===================================================
:SUMMARY
echo.
set /a _TOTAL=PASS+FAIL
if !_TOTAL! EQU 0 (
  echo No tests ran.
  goto END
)
echo ===================================================
if !FAIL! EQU 0 (
  echo   ALL TESTS PASSED  ^(!PASS!/!_TOTAL!^)
) else (
  echo   !PASS! passed,  !FAIL! FAILED  out of !_TOTAL! tests
  echo   Check logs in: %OUT%\
)
echo ===================================================

:END
echo.
pause
exit /b
