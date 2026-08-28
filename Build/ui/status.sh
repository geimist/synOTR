#!/bin/bash
# status.sh – Daten und Aktionen für die Übersicht (main.sh)
# shellcheck disable=SC2154

	if [ -z "$WORKDIR" ] ; then
	    WORKDIR="${DESTDIR}"
    fi
    if [ "$OTRcutactiv" = "off" ]; then
		DECODIR="$WORKDIR"
	else
	    DECODIR="${WORKDIR%/}/_decodiert"
    fi

# last Log:  (ToDo: nicht nur letztes Log, sondern per ListBox beliebiges Logfile auswählen)
# ---------------------------------------------------------------------
func_main_LastLog () {
    if [ -z "$WORKDIR" ] ; then
        WORKDIR="${DESTDIR%/}/"
    else
        WORKDIR="${WORKDIR%/}/"
    fi
	DECODIR="${WORKDIR%/}/_decodiert"
    if [ "$OTRcutactiv" = "off" ]; then
		DECODIR="$WORKDIR"
		echo "ist off"
	fi

	lastLog=$(ls -tr "${DECODIR%/}/_LOGsynOTR/"*.log 2>/dev/null | tail -1)
	lastLog=$(basename "$lastLog")
	lastLogPath="${DECODIR%/}/_LOGsynOTR/$lastLog"
}


# Info der Datenbank auslesen:
# ---------------------------------------------------------------------
    ColorLQ="#990099"
    ColorSD="#3366CC"
    ColorHQ="#DC3912"
    ColorHD="#FF9900"
    ColorAC3="#109618"
    CountHD=0
    CountAC3=0
    CountHQ=0
    CountSD=0
    CountLQ=0
    CountEpisode=0
    rowcount=0
    firstrun=""
    dbsize=""

    dbpath="/usr/syno/synoman/webman/3rdparty/synOTR/app/etc/synOTR.sqlite"
    if [ -f "$dbpath" ] ; then
    	firstrun=$(sqlite3 "$dbpath" "SELECT timestamp FROM raw WHERE rowid=1")
    	rowcount=$(sqlite3 "$dbpath" "SELECT COUNT(*) FROM raw")
    	dbsize=$(ls -lh "$dbpath" | awk '{ print $5 }')

        sSQL="SELECT count(rowid) FROM raw WHERE format='HD' OR ((file_original LIKE '%HD.avi' OR file_original LIKE '%HD.mp4') AND format IS NULL) "
		CountHD=$(sqlite3 -separator $'\t' "$dbpath" "$sSQL")

		sSQL="SELECT count(rowid) FROM raw WHERE file_original LIKE '%HD.ac3' "
		CountAC3=$(sqlite3 -separator $'\t' "$dbpath" "$sSQL")

		sSQL="SELECT count(rowid) FROM raw WHERE format='HQ' OR ((file_original LIKE '%HQ.avi' OR file_original LIKE '%HQ.mp4') AND format IS NULL) "
		CountHQ=$(sqlite3 -separator $'\t' "$dbpath" "$sSQL")

		sSQL="SELECT count(rowid) FROM raw WHERE format='SD' OR (file_original LIKE '%mpg.avi' AND format IS NULL) "
		CountSD=$(sqlite3 -separator $'\t' "$dbpath" "$sSQL")

		sSQL="SELECT count(rowid) FROM raw WHERE format='LQ' OR ((file_original LIKE '%mpg.mp4' OR file_original LIKE '%LQ.mp4') AND format IS NULL) "
		CountLQ=$(sqlite3 -separator $'\t' "$dbpath" "$sSQL")

		sSQL="SELECT count(rowid) FROM raw WHERE serie_episode <> '' "
		CountEpisode=$(sqlite3 -separator $'\t' "$dbpath" "$sSQL")
    fi
    CountHD=${CountHD:-0}
    CountAC3=${CountAC3:-0}
    CountHQ=${CountHQ:-0}
    CountSD=${CountSD:-0}
    CountLQ=${CountLQ:-0}
    CountEpisode=${CountEpisode:-0}
    rowcount=${rowcount:-0}


# Dateistatus auslesen:
# ---------------------------------------------------------------------
    count_otrkey=$(find "${OTRkeydir}" -maxdepth 1 \( -name '*.otrkey' -o -name '*.otr2' \) -type f 2>/dev/null | wc -l | tr -d ' ')

    count_waitofcutlist=$(find "${DECODIR}" -maxdepth 1 \( -name '*.avi' -o -name '*.mp4' \) -type f 2>/dev/null | wc -l | tr -d ' ')


# manueller synOTR-Start:
# ---------------------------------------------------------------------
if [[ "$page" == "status-run-synotr" ]]; then
	echo '
	<div class="Content_1Col_full">'
	    /usr/syno/synoman/webman/3rdparty/synOTR/synOTR-start.sh GUI
        func_main_LastLog
	echo '<meta http-equiv="refresh" content="2; URL=index.cgi?page=start"></div>'
fi


# synOTR beenden erzwingen:
# ---------------------------------------------------------------------
if [[ "$page" == "status-kill-synotr" ]]; then
	killall synOTR.sh
	echo '<meta http-equiv="refresh" content="0; URL=index.cgi?page=start">'
fi
