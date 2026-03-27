# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A collection of Windows-only interactive batch (`.bat`) scripts that wrap FFmpeg for common media processing tasks. No build system, no tests, no dependencies beyond FFmpeg itself.

## Scripts

| Script | Purpose |
|---|---|
| `convert_or_cut_to_mp4.bat` | Convert any FFmpeg-readable file to MP4, or cut a time segment out of it |
| `add_audio_to_mp4.bat` | Replace a video's audio track with a music file (starting at a chosen timestamp); output length always matches video length |

## Shared Architecture

Both scripts follow the same structure and share duplicated subroutines:

**Flow:** FFmpeg detection → user input/validation → processing mode selection → FFmpeg execution → success/fail output

**Shared subroutines (copy-pasted between scripts):**
- `:FIND_FFMPEG` — locates `ffmpeg.exe` via PATH → WinGet links → WinGet packages dir → `%ProgramFiles%\ffmpeg\bin`
- `:HMS_TO_SEC "HH:MM:SS" outvar` — validates and converts timestamp to integer seconds (errorlevel 1 on bad format)
- `:SEC_TO_HMS seconds outvar` — converts integer seconds to zero-padded `HH:MM:SS`

**Path escaping pattern** — both scripts escape `^ & | < > ( )` in user-supplied paths into two variables: `infile` (for `if exist` checks) and `infile_esc` (for passing to FFmpeg inside `setlocal DisableDelayedExpansion` blocks). The `DisableDelayedExpansion` around FFmpeg calls is intentional — it prevents `!` characters in paths from being consumed.

**GPU backend matrix** (re-encode path in both scripts):
- CPU: `libx264`/`libx265` with CRF + preset
- NVENC: `h264_nvenc`/`hevc_nvenc` with `constqp`
- QSV: `h264_qsv`/`hevc_qsv` with `global_quality`
- AMF: `h264_amf`/`hevc_amf` with CQP (`qp_i`/`qp_p`/`qp_b`)
- MediaFoundation: `h264_mf`/`hevc_mf` with bitrate

For H.265 GPU encodes, QP values are bumped by +4 (NVENC/QSV/AMF) or +6 (AMF B-frames) relative to the H.264 CRF, and `-tag:v hvc1` is always added for MP4 compatibility.

**No automatic backend fallback** — if the selected GPU backend fails, the script stops and tells the user to retry with CPU. This is a deliberate design choice.

**TS/M2TS inputs** — stream copy path automatically adds `-bsf:a aac_adtstoasc` when the input extension is `.ts` or `.m2ts`.

**Timestamp generation** — tries PowerShell `Get-Date` first, falls back to `wmic os get localdatetime`, then falls back to `%DATE%`/`%TIME%` string manipulation.

## Running the Scripts

Double-click or run from Command Prompt — they are fully interactive wizards. FFmpeg must be in PATH or installable via `winget install Gyan.FFmpeg`.
