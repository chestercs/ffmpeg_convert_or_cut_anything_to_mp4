# TODO – Ismert bugok és teendők

## [KÉSZ] Megjavított bugok

## ~~[BUG-01]~~ Időpont input: üres Enter nem fogadja el a default 00:00:00 értéket

**Érintett script:** `convert_or_cut_to_mp4.bat`
**Hol:** vágás módban a FROM/TO időpont bekérőnél
**Viselkedés:** Ha a felhasználó csak Entert üt (üres input), a script hibaüzenetet ad és visszakér, holott az elvárás az lenne, hogy üres FROM = `00:00:00` defaultot fogadjon el.
**Elvárt viselkedés:** Üres FROM → default `00:00:00`. Üres TO → default = a médiafájl teljes hossza (`dur_hms`).

---

## ~~[BUG-02]~~ Auto timestamp fájlnév csak perc pontosságú → ütközés lehetséges

**Érintett fájl:** `lib\ui.bat` → `:_GEN_TIMESTAMP`
**Hol:** Ha a felhasználó nem ad meg fájlnevet és az auto timestamp fallback (`%DATE%`/`%TIME%`) fut le (wmic nem elérhető vagy nem működik)
**Viselkedés:** A fallback `!ts:~0,15!` truncation csak az óráig tart (pl. `Fri003272026_16`), így egy percen belül több exportnál a fájl felülíródhat.
**Elvárt viselkedés:** A timestamp minden esetben legalább másodperc pontosságú legyen (`YYYYMMDD_HHmmss` vagy ehhez hasonló egyedi formátum), akár wmic-alapú, akár fallback.
