# synOTR – offene Notizen / Follow-ups

## Zwei Pipelines

- Herkunft in SQLite: `file_source` (`otrkey`|`otr2`), `file_encrypted` (Name mit `.otrkey`/`.otr2`). Lookup exakt, nicht LIKE.
- **otrkey x86:** altes avcut (`bin/avcut64`) oder avisplit, dann MP4Box (`includes/synotr_pipeline_otrkey.sh`). HD-AVI immer avisplit.
- **otrkey aarch64:** kein Schnitt.
- **otr2:** avcut 0.8 (`bin/avcut64_ffmpeg8`) → MKV, dann ffmpeg `-c copy` nach MP4; Keyframe `includes/ffmpeg_cut.sh`.
- avcut 0.8 Rebuild: `tools/build_avcut.sh` schreibt **nicht** nach `bin/avcut64`.

## avcut 0.8 Exit 139 (SIGSEGV) nach otr2-Schnitt

- **Status:** bekannt, nicht blockierend. Chicago Fire HQ.otr2 spielte nach ffmpeg-Copy einwandfrei (Dauer = Cutlist).
- **Wo:** dritter libx264-Open nach zwei fertigen GOP-Encodes (Anfang und Ende des Keep-Intervalls). Kommando `0 START END -`. Keine Frames mehr im dritten Encoder (`final ratefactor` ohne frame I/P), dann Absturz. Vermutlich Encoder-Reopen nach Drain, obwohl der Rest verworfen wird (`avcut.c` reopen nach flush).
- **Risiko:** Core-Dump (`core dumped`) kann auf der NAS Platz fressen. Andere Dateien könnten früher abstürzen und unvollständig sein.
- **Jetzt:** Warnung im Log, MKV trotzdem remuxen wenn sie da ist. Dauer gegen Cutlist prüfen, wenn etwas komisch wirkt.
- **Später (kein Jagdauftrag):** Reopen nach letztem Keep unterbinden, oder `ulimit -c 0` um avcut. Nicht die DTS-Glättung anfassen.

## GUI: Tonspur wählen (AC3 / AAC / beides)

- **Status:** offen, noch nicht gebaut
- **Anlass:** otr2-HQ hat oft AAC-Stereo **und** AC3-5.1. Ohne Auswahl fiel AC3 weg (252 MB statt ~366 MB bei gleicher Länge). QuickTime behielt beide.
- **Ziel:** In den Einstellungen festlegen, welche Tonspuren ins fertige MP4 sollen: nur AAC, nur AC3, oder beide.
- **Gilt für:** otr2-Remux nach avcut und Keyframe-Cut; später ggf. auch otrkey, sobald AC3 gemuxt ist.
- Default bis zur GUI: beide Spuren mitnehmen (`ffmpeg -map 0`), nicht still eine verwerfen.

## convert_audio_parallel

- **Status:** produktiv, GUI-Schalter `parallelAudioConvert` (Standard: `on`)
- **Pfad:** `Build/ui/includes/convert_audio_parallel.sh`
- **Aufruf:** `synotr_encode_audio` in `Build/ui/synOTR.sh` (AVI→MP4, MP3-Quellspur)
- **Jobs:** min(nproc−1, 4); Segment mind. 90 s, sonst sequentiell
- **Abschalten:** Einstellungen → „Audiospur parallel konvertieren“ / `parallelAudioConvert="off"`
