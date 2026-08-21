# synOTR – offene Notizen / Follow-ups

## convert_audio_parallel

- **Status:** auskommentiert migriert, noch nicht produktiv umgesetzt
- **Marker im Code:** `TODO(convert_audio_parallel)` in `Build/ui/synOTR.sh` (Audio-Normalisierung / libfdk_aac)
- **Herkunft:** Live-Installation `@appstore/synOTR/ui/synOTR.sh` (Stand 2025-09-23)
- **Lokales Skript (NAS):** `/volume1/homes/admin/script/_funktionen/convert_audio_parallel.sh`
- **Ziel:** Hilfsfunktion ins Paket übernehmen (oder konfigurierbaren Pfad), parallele AAC-Konvertierung statt direktem `$ffmpeg`-Aufruf bei `normalizeAudio=on` / Encoder `libfdk_aac`
- **Aktuell aktiv:** weiterhin der direkte `$ffmpeg`-Aufruf

```bash
# vorgesehene Aktivierung (derzeit auskommentiert in synOTR.sh):
# source …/convert_audio_parallel.sh
# convertLOG=$(convert_audio_parallel "$audiofile" "$audiofile.m4a" "-c:a libfdk_aac -b:a ${OTRaacqal%k}k -af volume=${volumeinfo}dB" 2>&1)
```
