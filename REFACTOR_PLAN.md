# Refactor terv – közös batch library-k

## Probléma

Mindkét script (`convert_or_cut_to_mp4.bat`, `add_audio_to_mp4.bat`) tartalmaz teljesen azonos kódrészleteket:
- FFmpeg keresés + winget telepítés (~45 sor)
- `HMS_TO_SEC` / `SEC_TO_HMS` segédfüggvények (~35 + 10 sor)
- Path escape blokk (~7 sor, kétszer mindkét scriptben)
- GPU backend menü + változók beállítása (~45 sor)
- Output könyvtár + fájlnév prompt + timestamp generálás (~45 sor)
- `PROBE_DURATION` (~30 sor, részben eltérő implementációval)

---

## Megoldás: batch „library" fájlok

A batch scriptekben egy másik fájl specifikus label-jét meg lehet hívni ezzel a szintaxissal:

```bat
call "%~dp0lib\utils.bat" :HMS_TO_SEC "00:12:34" result_var
```

A `%~dp0` az aktuális script mappájára mutat, így a lib elérési útja relatív marad.
A library fájl tetején `goto :EOF` megakadályozza, hogy véletlenül önállóan fusson le.

---

## Javasolt struktúra

```
project/
├── lib/
│   ├── ffmpeg.bat     ← FFmpeg keresés, telepítés, PROBE_DURATION
│   ├── time.bat       ← HMS_TO_SEC, SEC_TO_HMS
│   └── ui.bat         ← path escape, GPU menü, output dir/fájlnév prompt
├── convert_or_cut_to_mp4.bat
└── add_audio_to_mp4.bat
```

---

## Library-k részletezése

### `lib\ffmpeg.bat`

| Label | Mit csinál | Input | Output változók |
|---|---|---|---|
| `:FIND_FFMPEG` | Megkeresi az `ffmpeg.exe`-t (PATH → WinGet links → WinGet packages → Program Files) | — | `FFMPEG_EXE` |
| `:ENSURE_FFMPEG` | FIND_FFMPEG + ha nincs, winget telepítési kérdés; siker után beállítja `FF` és `FFPROBE` változókat; errorlevel 1 ha nem sikerül | — | `FF`, `FFPROBE`, errorlevel |
| `:PROBE_DURATION` | ffprobe-bal lekérdezi a médiafájl hosszát másodpercben és HH:MM:SS formában | `%1`=fájlpath, `%2`=sec outvar, `%3`=hms outvar | errorlevel 1 ha nem sikerül |

**Megjegyzés:** Az `FF` és `FFPROBE` változókat `:ENSURE_FFMPEG` hívás után a fő script és a többi lib is használhatja – ezek lesznek a „globális" FFmpeg elérési utak.

---

### `lib\time.bat`

| Label | Mit csinál | Input | Output |
|---|---|---|---|
| `:HMS_TO_SEC` | `HH:MM:SS` → egész másodperc, validálja perc/mp 0–59 tartományt | `%1`=időstring (idézőjelben), `%2`=outvar neve | errorlevel 1 ha invalid |
| `:SEC_TO_HMS` | egész másodperc → `HH:MM:SS` (zero-padded) | `%1`=másodperc, `%2`=outvar neve | — |

---

### `lib\ui.bat`

| Label | Mit csinál | Input | Output változók |
|---|---|---|---|
| `:ESCAPE_PATH` | Escape-eli a CMD speciális karaktereket (`^ & \| < > ( )`) egy path stringben | `%1`=input változó neve, `%2`=output változó neve | a megadott outvar |
| `:ASK_GPU_BACKEND` | Kiírja a GPU menüt és beállítja az encoder változókat | `%1`=codec_label (`H.264`/`H.265`), `%2`=vcrf | `gpu_mode`, `enc_video`, `nv_preset`, `nv_qp`, `qsv_gq`, `amf_qp_i/p/b`, `mf_bitrate` |
| `:ASK_OUTPUT` | Output könyvtár + fájlnév prompt, timestamp generálás, `.mp4` suffix kezelés | — | `outdir`, `basename`, `outfile`, `outfile_esc` |

---

## Ami marad a fő scriptekben

A library-k kizárólag újrafelhasználható, általános részeket tartalmaznak. A fő scriptekben marad:

**`convert_or_cut_to_mp4.bat`:**
- Üdvözlő fejléc
- Input fájl bekérése + validálása + `infile_esc` előállítása (`:ESCAPE_PATH` hívással)
- TS/M2TS `abits` logika
- Action választó (egész fájl vs. vágás)
- Időpont bekérés + validáció + duration check (`:PROBE_DURATION` + `:HMS_TO_SEC` hívásokkal)
- Feldolgozási mód választó (stream copy vs. re-encode)
- Preset + codec választó
- GPU menü hívás (`:ASK_GPU_BACKEND`)
- Output prompt hívás (`:ASK_OUTPUT`)
- Tényleges FFmpeg parancsok (DO_COPY, DO_NVENC, DO_QSV, DO_AMF, DO_MF, DO_CPU)
- SUCCESS / FAIL üzenetek

**`add_audio_to_mp4.bat`:**
- Üdvözlő fejléc
- Videó fájl bekérése + validálása + escape
- Zene fájl bekérése + validálása + escape
- Duration probe mindkettőre (`:PROBE_DURATION` hívással)
- Zene start időpont bekérése + validálása (`:HMS_TO_SEC` hívással)
- Feldolgozási mód választó
- Preset + codec választó
- GPU menü hívás (`:ASK_GPU_BACKEND`)
- Output prompt hívás (`:ASK_OUTPUT`)
- Tényleges FFmpeg parancsok (DO_COPY, DO_NVENC, DO_QSV, DO_AMF, DO_MF, DO_CPU)
- SUCCESS / FAIL üzenetek

---

## Hívási konvenciók

### Változók átadása és visszakapása

A batch „library call" szintaxis:
```bat
call "%~dp0lib\time.bat" :HMS_TO_SEC "%from_ts%" from_sec
```
- A library subroutine a saját `setlocal/endlocal` blokkjában dolgozik
- Az eredményt az `endlocal & set "%~2=<érték>"` mintával adja vissza (ez a meglévő kódban is így van)
- Errorlevel-t `exit /b 0` / `exit /b 1` állítja

### `%~dp0` – relatív elérési út

Minden fő script a saját mappájához képest hivatkozik a lib-re:
```bat
call "%~dp0lib\ffmpeg.bat" :ENSURE_FFMPEG
if errorlevel 1 goto END
```

### `setlocal` hatókör

- A fő script a teljes futás alatt `setlocal EnableExtensions EnableDelayedExpansion` alatt fut
- A library subroutine-ok saját `setlocal/endlocal`-t használnak ahol szükséges
- Az `FF` és `FFPROBE` változókat `:ENSURE_FFMPEG` a fő script scope-jában állítja be (nincs `setlocal` wrapper az egész hívás körül)

---

## Amit ez a refactor NEM változtat

- A scripts interaktív jellege és flow-ja azonos marad
- Az FFmpeg parancsok argumentumai nem változnak
- A felhasználói UX (menük, promptok szövege) azonos marad
- Nem kerül be új függőség

---

## Várható eredmény (becsült sorok)

| Fájl | Jelenleg | Refactor után |
|---|---|---|
| `convert_or_cut_to_mp4.bat` | ~590 sor | ~280 sor |
| `add_audio_to_mp4.bat` | ~640 sor | ~280 sor |
| `lib\ffmpeg.bat` | — | ~100 sor |
| `lib\time.bat` | — | ~55 sor |
| `lib\ui.bat` | — | ~120 sor |
| **Összesen** | **~1230 sor** | **~835 sor** |
