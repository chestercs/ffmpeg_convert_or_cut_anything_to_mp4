#!/usr/bin/env bash
# Automated test runner for ChesTeRcs VegasVibe FFmpeg scripts.
# Input files use CRLF (printf '\r\n') — required by Windows CMD set /p.
# Requires: bash (Git for Windows), ffmpeg/ffprobe in PATH or WinGet packages.

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$TESTS_DIR/.." && pwd)"
ASSETS_DIR="$TESTS_DIR/assets"
OUT_DIR="$TESTS_DIR/tmp_output"

mkdir -p "$ASSETS_DIR" "$OUT_DIR"

echo
echo "==================================================="
echo "  ChesTeRcs VegasVibe - Automated Test Suite"
echo "==================================================="
echo

# FFmpeg detection (mirrors lib/ffmpeg.bat search order)
FF=""
if command -v ffmpeg &>/dev/null; then
  FF="$(command -v ffmpeg)"
else
  _wl="${LOCALAPPDATA:-$USERPROFILE/AppData/Local}/Microsoft/WinGet/Links/ffmpeg.exe"
  [[ -f "$_wl" ]] && FF="$_wl"
  if [[ -z "$FF" ]]; then
    for _p in "${LOCALAPPDATA:-$USERPROFILE/AppData/Local}/Microsoft/WinGet/Packages/Gyan.FFmpeg"*/ffmpeg-*/bin/ffmpeg.exe; do
      [[ -f "$_p" ]] && FF="$_p" && break
    done
  fi
  if [[ -z "$FF" ]] && [[ -f "${PROGRAMFILES:-/c/Program Files}/ffmpeg/bin/ffmpeg.exe" ]]; then
    FF="${PROGRAMFILES:-/c/Program Files}/ffmpeg/bin/ffmpeg.exe"
  fi
fi
if [[ -z "$FF" ]]; then
  echo "[!] ffmpeg not found. Tests require FFmpeg."
  exit 1
fi
FFPROBE="${FF%ffmpeg.exe}ffprobe.exe"
[[ -f "$FFPROBE" ]] || FFPROBE="ffprobe"
echo "[INFO] Using FFmpeg:  $FF"
echo "[INFO] Using FFprobe: $FFPROBE"
echo

# ===================================================
# Test assets (generated once; delete to regenerate)
# ===================================================
echo "Checking test assets..."
if [[ ! -f "$ASSETS_DIR/test_video.mp4" ]]; then
  echo "  Generating test_video.mp4 (30s 320x240 H264+AAC)..."
  "$FF" -hide_banner -y \
    -f lavfi -i "testsrc=duration=30:size=320x240:rate=25" \
    -f lavfi -i "sine=frequency=440:duration=30" \
    -c:v libx264 -preset ultrafast -crf 28 \
    -c:a aac -b:a 64k \
    "$ASSETS_DIR/test_video.mp4" >/dev/null 2>&1
fi
if [[ ! -f "$ASSETS_DIR/test_audio.mp3" ]]; then
  echo "  Generating test_audio.mp3 (60s 440Hz sine)..."
  "$FF" -hide_banner -y \
    -f lavfi -i "sine=frequency=440:duration=60" \
    -c:a libmp3lame -b:a 64k \
    "$ASSETS_DIR/test_audio.mp3" >/dev/null 2>&1
fi
echo "Assets OK."
echo

# Windows-style paths for use inside .bat scripts
WIN_TEST_VIDEO="$(cygpath -w "$ASSETS_DIR/test_video.mp4")"
WIN_TEST_AUDIO="$(cygpath -w "$ASSETS_DIR/test_audio.mp3")"
WIN_OUT="$(cygpath -w "$OUT_DIR")"

# Write a CRLF-terminated input file for a test case.
# Usage: write_input line1 line2 ... (empty string = blank line = press Enter)
write_input() {
  local out="$OUT_DIR/_input.txt"
  : > "$out"
  for line in "$@"; do
    printf '%s\r\n' "$line" >> "$out"
  done
}

PASS=0
FAIL=0

check() {
  local id="$1" desc="$2" file="$3" expected="$4" tolerance="$5"
  if [[ ! -f "$file" ]]; then
    FAIL=$((FAIL+1))
    echo "[FAIL] $id - $desc"
    echo "       Output file not found."
    echo "       Log: $OUT_DIR/_${id}.log"
    return
  fi
  local dur_raw dur
  dur_raw=$("$FFPROBE" -v error -show_entries format=duration \
    -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || true)
  dur="${dur_raw%.*}"
  if [[ -z "$dur" ]] || ! [[ "$dur" =~ ^[0-9]+$ ]]; then
    FAIL=$((FAIL+1))
    echo "[FAIL] $id - $desc"
    echo "       Could not read output duration."
    echo "       Log: $OUT_DIR/_${id}.log"
    return
  fi
  local diff=$(( dur - expected ))
  [[ $diff -lt 0 ]] && diff=$(( -diff ))
  if [[ $diff -le $tolerance ]]; then
    PASS=$((PASS+1))
    echo "[PASS] $id - $desc  (duration=${dur}s, expected ~${expected}s)"
  else
    FAIL=$((FAIL+1))
    echo "[FAIL] $id - $desc"
    echo "       duration=${dur}s, expected ~${expected}s  (tolerance +-${tolerance}s)"
    echo "       Log: $OUT_DIR/_${id}.log"
  fi
}

# ===================================================
# convert_or_cut_to_mp4.bat
# ===================================================
echo "---------------------------------------------------"
echo " convert_or_cut_to_mp4.bat"
echo "---------------------------------------------------"
echo

# TC01: Convert whole file, stream copy
# Inputs: infile | action(default=1) | mode(default=1) | outdir | filename | pause
rm -f "$OUT_DIR/TC01.mp4"
write_input "$WIN_TEST_VIDEO" "" "" "$WIN_OUT" "TC01" ""
"$ROOT_DIR/convert_or_cut_to_mp4.bat" < "$OUT_DIR/_input.txt" > "$OUT_DIR/_TC01.log" 2>&1 || true
check "TC01" "Convert whole - stream copy" "$OUT_DIR/TC01.mp4" 30 3

# TC02: Cut 5-20s, stream copy
# Inputs: infile | action=2 | from | to | mode(default=1) | outdir | filename | pause
rm -f "$OUT_DIR/TC02.mp4"
write_input "$WIN_TEST_VIDEO" "2" "00:00:05" "00:00:20" "" "$WIN_OUT" "TC02" ""
"$ROOT_DIR/convert_or_cut_to_mp4.bat" < "$OUT_DIR/_input.txt" > "$OUT_DIR/_TC02.log" 2>&1 || true
check "TC02" "Cut 5-20s - stream copy" "$OUT_DIR/TC02.mp4" 15 3

# TC03: Cut 5-20s, re-encode CPU H.264 (all defaults)
# Inputs: infile | action=2 | from | to | mode=2 | preset(default) | codec(default) | backend(default) | outdir | filename | pause
rm -f "$OUT_DIR/TC03.mp4"
write_input "$WIN_TEST_VIDEO" "2" "00:00:05" "00:00:20" "2" "" "" "" "$WIN_OUT" "TC03" ""
"$ROOT_DIR/convert_or_cut_to_mp4.bat" < "$OUT_DIR/_input.txt" > "$OUT_DIR/_TC03.log" 2>&1 || true
check "TC03" "Cut 5-20s - re-encode CPU H.264" "$OUT_DIR/TC03.mp4" 15 2

# TC04: Convert whole file, re-encode CPU H.264 (all defaults)
# Inputs: infile | action(default=1) | mode=2 | preset(default) | codec(default) | backend(default) | outdir | filename | pause
rm -f "$OUT_DIR/TC04.mp4"
write_input "$WIN_TEST_VIDEO" "" "2" "" "" "" "$WIN_OUT" "TC04" ""
"$ROOT_DIR/convert_or_cut_to_mp4.bat" < "$OUT_DIR/_input.txt" > "$OUT_DIR/_TC04.log" 2>&1 || true
check "TC04" "Convert whole - re-encode CPU H.264" "$OUT_DIR/TC04.mp4" 30 2

echo
echo "---------------------------------------------------"
echo " add_audio_to_mp4.bat"
echo "---------------------------------------------------"
echo

# TC05: Replace audio from start, copy video (default)
# Inputs: videofile | musicfile | music_start(default) | mode(default=1) | outdir | filename | pause
rm -f "$OUT_DIR/TC05.mp4"
write_input "$WIN_TEST_VIDEO" "$WIN_TEST_AUDIO" "" "" "$WIN_OUT" "TC05" ""
"$ROOT_DIR/add_audio_to_mp4.bat" < "$OUT_DIR/_input.txt" > "$OUT_DIR/_TC05.log" 2>&1 || true
check "TC05" "Replace audio from start - copy video" "$OUT_DIR/TC05.mp4" 30 3

# TC06: Replace audio from 10s offset, copy video
# Inputs: videofile | musicfile | music_start=00:00:10 | mode(default=1) | outdir | filename | pause
rm -f "$OUT_DIR/TC06.mp4"
write_input "$WIN_TEST_VIDEO" "$WIN_TEST_AUDIO" "00:00:10" "" "$WIN_OUT" "TC06" ""
"$ROOT_DIR/add_audio_to_mp4.bat" < "$OUT_DIR/_input.txt" > "$OUT_DIR/_TC06.log" 2>&1 || true
check "TC06" "Replace audio from 10s offset - copy video" "$OUT_DIR/TC06.mp4" 30 3

# TC07: Replace audio, re-encode video CPU H.264 (all defaults)
# Inputs: videofile | musicfile | music_start(default) | mode=2 | preset(default) | codec(default) | backend(default) | outdir | filename | pause
rm -f "$OUT_DIR/TC07.mp4"
write_input "$WIN_TEST_VIDEO" "$WIN_TEST_AUDIO" "" "2" "" "" "" "$WIN_OUT" "TC07" ""
"$ROOT_DIR/add_audio_to_mp4.bat" < "$OUT_DIR/_input.txt" > "$OUT_DIR/_TC07.log" 2>&1 || true
check "TC07" "Replace audio - re-encode CPU H.264" "$OUT_DIR/TC07.mp4" 30 2

# Cleanup temp files
rm -f "$OUT_DIR/_input.txt" "$OUT_DIR/_probe.txt"

# ===================================================
# Summary
# ===================================================
echo
TOTAL=$((PASS+FAIL))
echo "==================================================="
if [[ $FAIL -eq 0 ]]; then
  echo "  ALL TESTS PASSED  ($PASS/$TOTAL)"
else
  echo "  $PASS passed,  $FAIL FAILED  out of $TOTAL tests"
  echo "  Check logs in: $OUT_DIR/"
fi
echo "==================================================="
echo
