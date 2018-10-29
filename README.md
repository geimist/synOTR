# synOTR

SynOTR liefert einen Workflow für TV-Aufnahmen von onlineTVrecorder (OTR) auf Synology NAS. 

synOTR übernimmt 
- decodieren 
- AC3-muxing (BETA) 
- schneiden 
- MP4-Konvertierung 
- Umbenennung 

## Installation:
- benutze bitte das fertige und signierte Paket von [cphub.net](https://www.cphub.net/?id=37#synOTR)
- um ein eigenes SPK aus dem aktuellen master-branch zu bauen, nutze das Buildskript: build_spk.sh. Lege das Buildskript in einen leeren Ordner und rufe es als root auf. Das Skript setzt eine git-Installation voraus, mit welcher das repository als Grundlage geklont wird. Gewünschte Version kann man dem Skript als Parameter übergeben (z.B. build_spk.sh 4.0.7). Wird kein Parameter übergeben, bzw. ist dieser ungültig, wird der master-branch verwendet.