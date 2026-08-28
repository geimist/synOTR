#!/usr/bin/env bash
#
# Deploy-Sync: synOTR/ui (lokales Git-Repo) -> NAS (@appstore Mount)
#
# Aufruf:
#   ./deploy_synotr_ui.sh --dry-run   (oder -n)   -> nur anzeigen, nichts verändern
#   ./deploy_synotr_ui.sh --live                  -> tatsächlich syncen
#
# Für chown synOTR:synOTR auf dem NAS (per SSH):
#   export SYNOTR_DEPLOY_SSH="admin@dein-nas"
# Optional anderer Zielpfad auf dem NAS:
#   export SYNOTR_DEPLOY_REMOTE_DST="/var/packages/synOTR/target/ui"
#
# Vergleich erfolgt per Inhalt/Checksum (-c), NICHT per Zeitstempel/Größe.
# In der Ausgabe erscheinen NUR Dateien/Ordner, die wirklich übertragen,
# neu angelegt oder gelöscht werden (reine Attribut-Abgleiche wie Rechte/
# Zeitstempel ohne Inhaltsänderung werden ausgeblendet).
#
# Bleibt auf dem NAS unangetastet (weder überschreiben noch --delete):
#   app/etc     Konfiguration.txt + synOTR.sqlite (+ WAL/SHM)
#   app/venv    Python-Umgebung des OTR-CLI-Decoders
#   app/tmp     Laufzeitdaten

set -euo pipefail

SRC="/Users/stephangeisler/Documents/Computer/Code_Projekte/GitHub/synOTR/Build/ui"
DST="/Volumes/@appstore/synOTR/ui"


# chown synOTR:synOTR nur auf dem NAS möglich (nicht über den macOS-Mount).
# SSH-Host setzen, z.B. in ~/.zshrc: export SYNOTR_DEPLOY_SSH="admin@nas.local"
SSH_HOST="${SYNOTR_DEPLOY_SSH:-}"
REMOTE_DST="${SYNOTR_DEPLOY_REMOTE_DST:-/var/packages/synOTR/target/ui}"

MODE="${1:---dry-run}"

case "$MODE" in
  --dry-run|-n)
    DRYRUN=1
    echo "=== DRY RUN – es wird nichts verändert ==="
    ;;
  --live)
    DRYRUN=0
    echo "=== LIVE RUN – Dateien werden tatsächlich geschrieben/gelöscht ==="
    ;;
  *)
    echo "Unbekannte Option: $MODE"
    echo "Benutze --dry-run/-n oder --live"
    exit 1
    ;;
esac

# Prüfen, ob der NAS-Mount überhaupt eingehängt ist
if [[ ! -d "$DST" ]]; then
  echo "FEHLER: Zielpfad $DST nicht gefunden. Ist das Volume gemountet?"
  exit 1
fi

# -r = rekursiv
# -l = Symlinks als Symlinks kopieren
# -c = Checksum-Vergleich statt mtime/size (Inhalt entscheidet, nicht Zeitstempel)
# -i = itemize-changes (liefert die Codes, die wir unten filtern)
# --chmod = einheitliche Rechte 755 für Dateien und Verzeichnisse
# Bewusst OHNE -p/-t/-a, da sonst lokale Rechte/Zeitstempel übernommen werden
# oder ständig reine Attribut-Updates ohne echte Inhaltsänderung auftauchen.
RSYNC_OPTS=(-rlci --delete "--chmod=D755,F755")
if [[ "$DRYRUN" -eq 1 ]]; then
  RSYNC_OPTS+=(-n)
fi

# Zeigt nur Zeilen, bei denen wirklich etwas übertragen/angelegt/gelöscht
# wurde. Itemize-Zeilen, die mit "." beginnen, sind reine Attribut-Abgleiche
# (z.B. nur Rechte anders) OHNE Inhaltsänderung und werden ausgeblendet.
# > = empfangen/übertragen, c = lokale Neuanlage, * = Löschung
run_rsync() {
  local status=0
  set +e
  /opt/homebrew/bin/rsync "$@" | grep -E '^[>c*]'
  status=${PIPESTATUS[0]}
  set -e
  if [[ $status -ne 0 ]]; then
    echo "FEHLER: rsync ist mit Code $status abgebrochen." >&2
    exit "$status"
  fi
}

# Nach dem Sync: Eigentümer synOTR:synOTR und Rechte 755 auf dem NAS (per SSH)
fix_permissions() {
  local remote_cmd="sudo chown -R synOTR:synOTR '${REMOTE_DST}' && sudo chmod -R 755 '${REMOTE_DST}'"

  if [[ "$DRYRUN" -eq 1 ]]; then
    if [[ -n "$SSH_HOST" ]]; then
      echo ">>> (dry-run) Würde per SSH auf ${SSH_HOST} ausführen:"
      echo "    ${remote_cmd}"
    else
      echo ">>> (dry-run) SYNOTR_DEPLOY_SSH nicht gesetzt – chown/chmod auf NAS übersprungen"
      echo "    (rsync --chmod setzt 755 bereits beim Übertragen)"
    fi
    return
  fi

  if [[ -z "$SSH_HOST" ]]; then
    echo
    echo "WARNUNG: SYNOTR_DEPLOY_SSH nicht gesetzt – chown synOTR:synOTR übersprungen." >&2
    echo "         Rechte 755 wurden per rsync --chmod gesetzt." >&2
    echo "         Export setzen: export SYNOTR_DEPLOY_SSH=\"admin@dein-nas\"" >&2
    return
  fi

  echo
  echo ">>> Setze per SSH auf ${SSH_HOST}: synOTR:synOTR, 755 auf ${REMOTE_DST}"
  # remote_cmd ist lokal zusammengesetzt; SSH soll die Zeichenkette so ausführen.
  # shellcheck disable=SC2029
  ssh "$SSH_HOST" "$remote_cmd"
}

echo
echo ">>> Hauptsync: $SRC -> $DST"
echo "    (ausgenommen: app/etc, app/venv, app/tmp)"
run_rsync "${RSYNC_OPTS[@]}" \
  --exclude '.DS_Store' \
  --exclude '.git' \
  --exclude 'app/etc/' \
  --exclude 'app/venv/' \
  --exclude 'app/tmp/' \
  --exclude '*.sqlite' \
  --exclude '*.sqlite-wal' \
  --exclude '*.sqlite-shm' \
  --exclude '__pycache__/' \
  "$SRC/" "$DST/"

fix_permissions

echo
echo "Fertig."
