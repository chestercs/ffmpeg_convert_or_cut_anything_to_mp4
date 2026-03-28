# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A collection of Windows-only interactive batch (`.bat`) scripts that wrap FFmpeg for common media processing tasks. No build system, no tests, no dependencies beyond FFmpeg itself.

## Scripts

| Script | Purpose |
|---|---|
| `convert_or_cut_to_mp4.bat` | Convert any FFmpeg-readable file to MP4, or cut a time segment out of it |
| `add_audio_to_mp4.bat` | Replace a video's audio track with a music file (starting at a chosen timestamp); output length always matches video length |

## Shared Library Architecture

Shared logic lives in `lib\` and is called via the dispatch convention below. Both main scripts follow the same flow: FFmpeg detection → user input/validation → processing mode selection → FFmpeg execution → success/fail output.

### Dispatch convention

Every `lib\*.bat` file begins with:
```batch
@echo off
if "%~1"=="" goto :EOF
goto %~1
```

Callers always pass the label as the first argument:
```batch
call "%~dp0lib\ffmpeg.bat" :ENSURE_FFMPEG
call "%~dp0lib\time.bat"   :HMS_TO_SEC "%from_ts%" from_sec
call "%~dp0lib\ui.bat"     :ESCAPE_PATH infile infile_esc
```

Inside the subroutine, `%1` is the label name — actual arguments start at `%2`. This is critical: passing `arg1` as the second token means it lands in `%2` inside the sub, not `%1`.

### lib\time.bat

- `:HMS_TO_SEC "%HH:MM:SS%" outvar` — validates and converts timestamp to integer seconds; errorlevel 1 on bad format or MM/SS ≥ 60
- `:SEC_TO_HMS seconds outvar` — converts integer seconds to zero-padded `HH:MM:SS`

Both use `setlocal` / `endlocal & set "%~3=value"` to return values to the caller.

### lib\ffmpeg.bat

- `:FIND_FFMPEG` — locates `ffmpeg.exe` via PATH → WinGet links → WinGet packages → `%ProgramFiles%\ffmpeg\bin`; sets `FFMPEG_EXE`
- `:ENSURE_FFMPEG` — calls `:FIND_FFMPEG`, offers winget install if missing, sets `FF` and `FFPROBE`; errorlevel 1 on failure/abort
- `:PROBE_DURATION filepath sec_outvar hms_outvar` — reads duration via ffprobe into temp files; errorlevel 1 if unreadable

### lib\ui.bat

- `:ESCAPE_PATH invar outvar` — escapes `^ & | < > ( )` in a path variable; reads var by name using `call set "_ep=%%%~2%%"`
- `:ASK_PRESET_AND_CODEC [simple]` — prompts preset (1–9) and codec (H.264/H.265); sets `x_preset`, `vcodec`, `vcrf`, `codec_label`
- `:ASK_GPU_BACKEND codec_label vcrf` — prompts GPU/CPU backend; sets `gpu_mode`, `nv_preset`, `nv_qp`, `qsv_gq`, `amf_qp_i/p/b`, `mf_bitrate`
- `:ASK_OUTPUT` — prompts output dir + filename; auto-generates timestamp basename if empty; sets `outdir`, `outfile`, `outfile_esc`

## Key Implementation Notes

**Path escaping** — user paths are stored in two variables: `infile` (for `if exist` checks) and `infile_esc` (for FFmpeg calls). `setlocal DisableDelayedExpansion` wraps every FFmpeg call block so `!` in paths is not consumed.

**`set /p` defaults** — pre-set the variable before `set /p` so that pressing Enter without typing keeps the default:
```batch
set "from_ts=00:00:00"
set /p "from_ts=FROM time (HH:MM:SS, Default: 00:00:00): "
```

**GPU backend matrix** (re-encode path):
- CPU: `libx264`/`libx265` with CRF + preset
- NVENC: `h264_nvenc`/`hevc_nvenc` with `constqp`
- QSV: `h264_qsv`/`hevc_qsv` with `global_quality`
- AMF: `h264_amf`/`hevc_amf` with CQP (`qp_i`/`qp_p`/`qp_b`)
- MediaFoundation: `h264_mf`/`hevc_mf` with bitrate

For H.265 GPU encodes, QP values are bumped by +4 (NVENC/QSV/AMF I+P) or +6 (AMF B-frames) relative to the H.264 CRF, and `-tag:v hvc1` is always added for MP4 compatibility. No automatic backend fallback — if the selected backend fails, the script stops.

**TS/M2TS inputs** — stream copy path automatically adds `-bsf:a aac_adtstoasc` for `.ts` and `.m2ts` files.

**Timestamp filename generation** — tries `wmic os get LocalDateTime` via a temp file (to avoid stdout pollution), validates 14-digit result, falls back to `%DATE%`/`%TIME%` string manipulation; always appends `_%RANDOM%` to prevent collisions.

## Automated Tests

```
bash tests/run_tests.sh
```

Run from Git Bash — no arguments needed. Requires FFmpeg. On first run it generates small test assets (`tests\assets\`) with `ffmpeg -f lavfi`. Test outputs land in `tests\tmp_output\` (both gitignored).

**How it works:** Each test case writes CRLF-terminated lines to a temp file (`printf '%s\r\n'`), then redirects it as stdin to the tested script. `set /p` reads from stdin regardless of source, so all interactive prompts are answered automatically. A blank line (`""`) keeps the pre-set default. Output MP4s are verified with `ffprobe` for duration ± a tolerance.

**Adding a test:** Copy an existing test block, adjust the `write_input` line sequence, and update the `check` call (`id`, `description`, `output_path`, `expected_seconds`, `tolerance_seconds`).

## CMD Batch Gotchas

**All `.bat` files must use CRLF line endings.** LF-only files cause CMD's label scanner to fail to find labels in certain positions. Use `unix2dos` after any editor that saves LF-only.

**Escape `(`, `)`, and `:` inside compound blocks.** Inside a parenthesized `if`/`else`/`for` block, CMD counts ALL bare `(` and `)` — including those inside `echo` text. Unescaped `)` changes the depth counter, and a bare `:` at non-zero block depth triggers `: was unexpected at this time.` Use `^(`, `^)`, `^:` in any `echo` line that lives inside a compound block and contains these characters.

## Running the Scripts

Double-click or run from Command Prompt — they are fully interactive wizards. FFmpeg must be in PATH or installable via `winget install Gyan.FFmpeg`.
