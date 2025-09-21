# convert_or_cut_to_mp4.bat 🎬
**Windows-only interactive batch tool to cut or convert _any FFmpeg-readable media_ into MP4 — with optional re-encode (H.264/H.265), GPU backends (NVENC / QSV / AMF / MediaFoundation), presets, and automatic FFmpeg installation via `winget`.**

---

## ✨ Features

- **Two workflows**
    1) **Convert whole file** → remux or re-encode into MP4
    2) **Cut a segment** → specify FROM/TO (`HH:MM:SS`) and export to MP4
- **Processing modes**
    - **Stream copy (default)**: ultra fast, *no quality loss*, but cuts are **keyframe-aligned** (may be slightly off).
    - **Re-encode**: slower, **frame-accurate** cuts; choose **H.264 (libx264)** or **H.265/HEVC (libx265)** and a **preset** (ultrafast → veryslow).
- **GPU encoding menu (re-encode only)**
    - Pick **NVIDIA NVENC**, **Intel QSV**, **AMD AMF**, **MediaFoundation**, or **CPU**.
    - The script **doesn’t chain/fallback** across backends: it runs the one you pick and **stops on failure** (suggests CPU next time).
- **Automatic FFmpeg install (optional)**
    - If `ffmpeg` isn’t found, the script can **install it via `winget`** (asks for confirmation).
- **Any input format FFmpeg can read**
    - Works with `.mp4`, `.ts`, `.mkv`, `.mov`, `.avi`, …
    - Output is **always MP4**.
- **MP4 compatibility tweaks**
    - `-movflags +faststart` for web playback.
    - For TS/M2TS, auto-applies `-bsf:a aac_adtstoasc` on stream copy.
    - For HEVC encodes, uses `-tag:v hvc1` for better MP4 compatibility.
- **Robust batch UX**
    - Escapes special characters in paths (`& | < > ^`).
    - Avoids prompts that create stray files.
    - Timestamped default filenames.

---

## ⚙️ Requirements

- **Windows 10/11** (Batch script `.bat`)
- **FFmpeg** (auto-install supported via **winget**)
    - If you choose **H.265**, the script checks for `libx265`. If unavailable, it falls back to **H.264**.
- **GPU backends (optional)**
    - **NVENC** ⇒ NVIDIA driver with NVENC support.
    - **QSV** ⇒ Intel iGPU enabled + proper driver.
    - **AMF** ⇒ AMD GPU driver.
    - **MediaFoundation** ⇒ built-in Windows encoder (feature set/quality limited).

> The script **does not auto-detect devices**. If a chosen backend fails (e.g., missing driver), the script **stops** and suggests using CPU.

---

## 📦 Installation

1. Save the script as **`convert_or_cut_to_mp4.bat`**
2. Place it anywhere (e.g., Desktop).
3. Ensure `ffmpeg` is in PATH, *or* let the script install it via **winget** on first run.

> Tip: Keep the script in a folder where you have write access (it prompts for an output directory anyway).

---

## 🚀 Usage

Run by **double-click** or via **Command Prompt**.

### 1) Start
- The script checks for **FFmpeg**. If missing, it offers to install via **winget**.

### 2) Input file
- Paste the **full path** to the input media file, e.g.:
  ```
  C:\Users\you\Videos\lecture.mkv
  ```

### 3) Action
You’ll be asked what to do:
```
What do you want to do?
  1) Convert the WHOLE file to MP4   [fast if stream copy]
  2) CUT a segment and make an MP4   [choose times]
Select action (Default: 1):
```
- **1** → Convert entire file
- **2** → Cut a **FROM → TO** segment (prompted next)

If you chose **Cut**, provide times (format `HH:MM:SS`), e.g.:
```
FROM time (HH:MM:SS): 00:07:55
TO   time (HH:MM:SS): 00:12:04
```

### 4) Processing mode
Choose stream copy vs re-encode:
```
Choose processing mode:
  1) Stream copy (no re-encode)  - very fast remux to MP4; for cuts it is keyframe-aligned and not frame-accurate
  2) Re-encode                   - slower; frame-accurate cuts; pick codec and preset
Select mode (Default: 1):
```
- **1 = Stream copy**
    - Fastest. No quality loss.
    - **Cuts may be off by a few seconds** (nearest **keyframe**).
- **2 = Re-encode**
    - Frame-accurate cuts.
    - Choose **codec** and **preset**:
        - **Presets** (speed vs compression; *slower = better compression at same quality*): ultrafast, superfast, veryfast (default), faster, fast, medium, slow, slower, veryslow.
        - **Codecs**: H.264 (libx264 — default), H.265/HEVC (libx265 — smaller files, slower; may be less compatible).
          > If H.265 is selected but `libx265` is not present, fallback to **H.264**.

### 5) GPU backend (re-encode only)
Select one backend:
```
  1) CPU (libx264/libx265)
  2) NVIDIA NVENC (h264_nvenc / hevc_nvenc)
  3) Intel Quick Sync (h264_qsv / hevc_qsv)
  4) AMD AMF (h264_amf / hevc_amf)
  5) MediaFoundation (h264_mf / hevc_mf)
```
- The script **runs only the chosen backend**. If it fails (e.g., driver/device missing), it **stops** and prints a hint to try **CPU**.

### 6) Output directory & filename
- **Output directory** defaults to `C:\Users\<you>\Downloads` (you can change it).
- **Output filename** should be given **without** `.mp4`.  
  If blank, a **timestamped** name is used, e.g. `output_20250921_194532.mp4`.

### 7) Result
At the end, you’ll see:
- **Full path** to the output file
- **Method** used (stream copy vs re-encode; codec & backend for re-encode)
- Notes (e.g., keyframe-aligned cut caveat)

---

## 🧪 Examples

### Convert an MKV to MP4 (no re-encode)
- Action: `1` (Convert whole file)
- Mode: `1` (Stream copy)
- Output: MP4 with `-movflags +faststart`. No quality loss (if codecs are MP4-compatible).

### Cut 00:07:55–00:12:04 with frame accuracy (NVENC)
- Action: `2` (Cut)
- Times: `00:07:55` → `00:12:04`
- Mode: `2` (Re-encode)
- Preset: `3` (veryfast)
- Codec: `2` (H.265) or `1` (H.264)
- Backend: `2` (NVIDIA NVENC)

---

## 🔍 How it works

- **FFmpeg detection/installation**
    - `where ffmpeg` to check availability; optional `winget install Gyan.FFmpeg` if missing.
- **Safe path handling**
    - Escapes `& | < > ^` in user-provided paths to avoid CMD parsing issues.
- **TS/M2TS handling**
    - Adds `-bsf:a aac_adtstoasc` when input is `.ts` or `.m2ts` (stream copy path).
- **Stream copy**
    - `-c copy` (no re-encode), `-movflags +faststart`
    - For cuts: `-ss FROM -to TO -i input -c copy ...` (keyframe-aligned, not exact).
- **Re-encode (CPU)**
    - **H.264**: `-c:v libx264 -crf 20 -preset <preset> -c:a aac -b:a 160k`
    - **H.265**: `-c:v libx265 -crf 23 -preset <preset> -tag:v hvc1 -c:a aac -b:a 160k`
- **Re-encode (GPU backends)**
    - **NVENC**: `h264_nvenc`/`hevc_nvenc` with **const QP** (`-rc constqp -qp <value>`) and a mapped `-preset p1..p7`.
    - **QSV**: `h264_qsv`/`hevc_qsv` with `-global_quality <value>`.
    - **AMF**: `h264_amf`/`hevc_amf` with **CQP** (`-rc cqp -qp_i/_p/_b`).
    - **MediaFoundation**: `h264_mf`/`hevc_mf` with **bitrate** (default ~6M / 4M).
    - For HEVC: `-tag:v hvc1` improves MP4 player compatibility.
- **No automatic fallback**
    - The chosen backend is attempted once; on error, the script ends (pick CPU next time).

---

## ⚠️ Notes & Limitations

- **Windows only** (batch `.bat`).
- **Stream copy cuts** are **not frame-accurate**; use **re-encode** for precision.
- Some inputs may **not mux** to MP4 in stream copy; choose **re-encode**.
- **GPU backends require proper drivers/devices**. If unavailable, use **CPU**.
- **HEVC in MP4** may be less compatible on older devices; `-tag:v hvc1` helps, but YMMV.

---

## 🧾 License (MIT)

MIT License © Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the “Software”), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
