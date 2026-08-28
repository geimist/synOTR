#!/bin/sh
# /usr/syno/synoman/webman/3rdparty/synOTR/synOTR.sh

###################################################################################

    echo "    -----------------------------------"
    echo "    |    ==> Installationsinfo <==    |"
    echo "    -----------------------------------"
    echo -e

    CLIENTVERSION=$(get_key_value /var/packages/synOTR/INFO version)
    set -E -o functrace         # for function failure()

# ---------------------------------------------------------------------------------
#           GRUNDKONFIGRUATIONEN / INDIVIDUELLE ANPASSUNGEN / Standardwerte       |
#           (alle Werte können durch setzen in der Konifiguration.txt             |
#           überschrieben werden)                                                 |
# ---------------------------------------------------------------------------------
    SMARTRENDERING="on"         # Smartrendering profilaktisch aktivieren
    OTRlocalcutlistdir=""       # optionaler Ordner für lokale Cutlists (zusätzlich zu Dekodier-/Downloadordner); gefunden = immer nutzen
    normalizeAudio="on"         # Audiospur normalisieren (nur in Verbindung mit avi2mp4)
    parallelAudioConvert="on"   # AAC-Konvertierung parallel (nproc-1 Jobs; nur avi2mp4 / MP3-Quellspur)
    OTRotr2audio="both"         # otr2-Tonspuren im fertigen MP4: both | aac | ac3
    endgueltigloeschen="off"    # das endgültige Löschen der Quelldateien erst einmal grundsätzlich deaktivieren
    # Frameversatz, um Cuts manuell zu justieren (positive Werte verschieben den Cut nach hinten, negative nach vorn):
    FrameversatzAnfangCut=1     # = verschiebt den Beginn des gewünschten Filmteils beim framegenauen Schneiden
    FrameversatzEndeCut=1       # = verschiebt das Ende des gewünschten Filmteils beim framegenauen Schneiden
    AudioDelayMs=0              # Tonversatz in ms beim ffmpeg-Remux (positiv = Ton später); leer/unset fällt auf MP4BOX_DELAY zurück
    niceness=15                 # Die Priorität liegt im Bereich von -20 bis +19 (in ganzzahligen Schritten), wobei -20 die höchste Priorität (=meiste Rechenleistung) und 19 die niedrigste Priorität (=geringste Rechenleistung) ist. Die Standardpriorität ist 0. AUF NEGATIVE WERTE SOLLTE UNBEDINGT VERZICHTET WERDEN!
    WaitOfCutlist="on"          # mit dem weiterverarbeiten eines Filmes wird so lange gewartet, bis eine Cutlist verfügbar ist
    useallcutlistformat=0       # Cutlits für alternative Formate berücksichtigen
    timediff=1                  # Abweichung der Dateiänderungszeit in Minuten um laufende FTP-Pushaufträge nicht zu decodieren
    TVDBlang="de"               # Sprache, in welcher nach Serien auf theTVDB.com gesucht werden soll (de/deu)
    TVDB_APIKEY=""              # API v4-Key für theTVDB.com (nur aus den Einstellungen, kein Default)
    TVDB_PIN=""                 # optional: Subscriber-PIN zum v4-Key
    today=$(date +%d | sed -e 's/^0*//') # Datum (Tag) ohne führende Null (lässt sich sonst nicht als Berechnungsgrundlage nutzen)
    regInt='^[0-9]+$'           # Vorlage: Regex check Integer

# an welchen User/Gruppe soll die DSM-Benachrichtigung gesendet werden :
# ---------------------------------------------------------------------
    synOTR_user=$(whoami); echo "synOTR-User:              $synOTR_user"
    if cat /etc/group | grep administrators | grep -q "$synOTR_user"; then
        isAdmin=yes
    else
        isAdmin=no
    fi
    MessageTo="@administrators" # Administratoren (Standardeinstellung)
    #MessageTo="$synOTR_user"   # User, welche synOTR aufgerufen hat (funktioniert natürlich nicht bei root, da root kein DSM-GUI-LogIn hat und die Message ins leere läuft)

# Arbeitsverzeichnis auslesen und hineinwechseln:
# ---------------------------------------------------------------------
    OLDIFS=$IFS	                # ursprünglichen Fieldseparator sichern
    UNIXTIME=$(date +%s)
    APPDIR=$(cd "$(dirname "$0")" || exit 1; pwd)
    cd "${APPDIR}" || exit 1

# Konfigurationsdatei einbinden:
# ---------------------------------------------------------------------
    CONFIG=app/etc/Konfiguration.txt
    # shellcheck source=app/etc/Konfiguration.txt
    # shellcheck disable=SC1090,SC1091
    . "./${CONFIG}"
    if [ -z "$AudioDelayMs" ] && [ -n "$MP4BOX_DELAY" ]; then
        AudioDelayMs="$MP4BOX_DELAY"
    fi
    AudioDelayMs="${AudioDelayMs:-0}"
    case "${OTRotr2audio:-both}" in
        aac|ac3|both) ;;
        *) OTRotr2audio="both" ;;
    esac
    if [ -z "$APPRISEURL" ] && [ -n "$PBTOKEN" ]; then
        case "$PBTOKEN" in
            *://*) APPRISEURL="$PBTOKEN" ;;
            *) APPRISEURL="pbul://${PBTOKEN}" ;;
        esac
    fi

# Variable "lastjob" für Benachrichtigung setzen:
# ---------------------------------------------------------------------
    if [ "$OTRrenameactiv" = "on" ] ; then
        lastjob=4
    elif [ "$OTRavi2mp4active" = "on" ] ; then
        lastjob=3
    elif [ "$OTRcutactiv" = "on" ] ; then
        lastjob=2
    else
        lastjob=1
    fi

# DSM 7 wie synOCR: i18n-Keys plus Freitext als 5. Argument.
# Der Text erscheint nur, wenn der String {0} enthält (ExtJS-Platzhalter).
synotr_dsmnotify()
{
    [ -n "$MessageTo" ] || return 0
    synodsmnotify -c "SYNO.SDS.synOTR.Application" "$MessageTo" "synOTR:app:app_name" "synOTR:app:${1}" "${2}"
}

# Push über Apprise (Decoder-venv). Leer = aus. URL nicht ins Log.
synotr_apprise_notify()
{
    _body="$1"
    [ -n "$APPRISEURL" ] || return 0
    _apprise_log=""
    _apprise_rc=1
    if [ -x "${APPDIR}/app/venv/bin/apprise" ]; then
        if _apprise_log=$("${APPDIR}/app/venv/bin/apprise" -t "synOTR" -b "$_body" "$APPRISEURL" 2>&1); then
            _apprise_rc=0
        else
            _apprise_rc=$?
        fi
    elif [ -x "${APPDIR}/app/venv/bin/python3" ]; then
        if _apprise_log=$(APPRISE_BODY="$_body" APPRISE_URL="$APPRISEURL" "${APPDIR}/app/venv/bin/python3" -c '
import os, sys
try:
    import apprise
except ImportError:
    sys.stderr.write("apprise ist nicht installiert (Decoder-venv).\n")
    sys.exit(2)
url = os.environ.get("APPRISE_URL", "")
body = os.environ.get("APPRISE_BODY", "")
a = apprise.Apprise()
if not a.add(url):
    sys.stderr.write("Apprise-URL ungültig.\n")
    sys.exit(1)
sys.exit(0 if a.notify(title="synOTR", body=body) else 1)
' 2>&1); then
            _apprise_rc=0
        else
            _apprise_rc=$?
        fi
    else
        echo "        Apprise: Decoder-venv fehlt – keine Push-Benachrichtigung."
        unset _body
        return 1
    fi
    if [ "$_apprise_rc" -eq 0 ]; then
        if [ "$LOGlevel" = "2" ]; then
            echo "        Apprise: gesendet"
            [ -n "$_apprise_log" ] && echo "$_apprise_log"
        fi
    else
        echo "        Apprise-Error (exit ${_apprise_rc})"
        [ -n "$_apprise_log" ] && echo "$_apprise_log"
    fi
    unset _body _apprise_log _apprise_rc
}

# Systeminformation / LIBRARY_PATH anpassen / PATH anpassen:
# --------------------------------------------------------------------- 
    echo "synOTR-Version:           $CLIENTVERSION"
    machinetyp=$(uname --machine); echo "Architektur:              $machinetyp"
    dsmbuild=$(uname -v | awk '{print $1}' | sed "s/#//g"); echo "DSM-Build:                $dsmbuild"
    device=$(uname -a | awk -F_ '{print $NF}' | sed "s/+/plus/g" ); echo "Gerät:                    $device"
    # HD-otrkey: immer avisplit. otr2: avcut 0.8 bzw. ffmpeg-Keyframe.
    echo -n "                          RAM installiert:    "; RAMmax=$(free -m | grep 'Mem:' | awk '{print $2}'); echo "$RAMmax MB"	    # verbauter RAM
    echo -n "                          RAM verwendet:      "; RAMused=$(free -m | grep 'Mem:' | awk '{print $3}');	echo "$RAMused MB"  # genutzter RAM
    echo -n "                          RAM verfügbar:      "; RAMfree=$(( RAMmax - RAMused )); 	echo "$RAMfree MB"

# synOTR Programmlauf auf die Hardware abstimmen:
# ---------------------------------------------------------------------
    save_ENV ()
    {
        # https://forum.ubuntuusers.de/post/2099580/
        # http://www.linux-praxis.de/lpic1/lpi101/1.102.4.html
        # man kann mit synOTR_ENV und restore_ENV zwischen den beiden ENV-Versionen wechseln
        export SAVED_PATH="$PATH"
        export SAVED_LD_LIBRARY_PATH="$LD_LIBRARY_PATH"
    }

    restore_ENV ()
    {
    #   echo "Die Standard-Pathvariablen werden geladen …"
        export PATH="$SAVED_PATH"
        export LD_LIBRARY_PATH="$SAVED_LD_LIBRARY_PATH"
    }
    
    save_ENV    

    if [ "$machinetyp" = "x86_64" ]; then
        echo "                          x86_64: otrkey-Schnitt avcut 4.3.1 / avisplit, dann MP4Box; otr2 avcut 0.8 oder ffmpeg+mp4mux."
        synOTR_LD_LIBRARY_PATH="${APPDIR}/app/lib:${LD_LIBRARY_PATH}"
        synOTR_PATH="${PATH}:${APPDIR}/app/bin"
        avcut_otrkey="${APPDIR}/app/bin/avcut64"
        avcut_ffmpeg8="${APPDIR}/app/bin/avcut64_ffmpeg8"
        avisplit="${APPDIR}/app/bin/avisplit"
        avimerge="${APPDIR}/app/bin/avimerge"
        ionice="${APPDIR}/app/bin/ionice64"
        mp4mux="${APPDIR}/app/bin/mp4mux"
        mp4box="${APPDIR}/app/bin/mp4box"
        if [ ! -f "$mp4mux" ]; then
            echo "                          Hinweis: mp4mux fehlt unter app/bin/ – Fallback MP4Box."
            mp4mux=""
        fi
    elif [ "$machinetyp" = "aarch64" ] || echo "$machinetyp" | grep -q "armv8" ; then
        echo "                          armv8/aarch64: .otrkey ohne Schnitt (nur MP4Box); .otr2 avcut 0.8 oder ffmpeg+mp4mux."
        synOTR_LD_LIBRARY_PATH="$SAVED_LD_LIBRARY_PATH"
        synOTR_PATH="${APPDIR}/app/binAArch64:${APPDIR}/app/binARMv7l:${PATH}:${APPDIR}/app/bin"
        avcut_otrkey=""
        avcut_ffmpeg8="${APPDIR}/app/binAArch64/avcut"
        avisplit=""
        avimerge=""
        ionice=$(command -v ionice 2>/dev/null || echo ":")
        mp4mux="${APPDIR}/app/binAArch64/mp4mux"
        mp4box="${APPDIR}/app/binAArch64/mp4box"
        if [ ! -f "$mp4mux" ]; then
            echo "                          FEHLER: mp4mux fehlt unter app/binAArch64/"
            mp4mux=""
        fi
        if [ ! -f "$mp4box" ]; then
            echo "                          Hinweis: MP4Box fehlt unter app/binAArch64/ – otr2-Mux per mp4mux."
            mp4box=""
        fi
    else
        message="Deine CPU-Plattform [${machinetyp}] wird leider von synOTR nicht unterstützt oder ist nicht bekannt …"
        echo "$message"
        synotr_dsmnotify error "$message"
        exit
    fi

    synOTR_ENV ()
    {
    #   restore_ENV 
    #   echo "Die angepassten Pathvariablen werden geladen …"
        export PATH="$synOTR_PATH"
        export LD_LIBRARY_PATH="$synOTR_LD_LIBRARY_PATH"
    }

    synOTR_ENV

    # SynoCommunity ffmpeg/ffprobe (versionierte Links, kein unversioniertes ffmpeg)
    ffmpeg=""
    ffprobe=""
    for _ffver in 8 7 6; do
        if [ -x "/usr/local/bin/ffmpeg${_ffver}" ] && [ -x "/usr/local/bin/ffprobe${_ffver}" ]; then
            ffmpeg="/usr/local/bin/ffmpeg${_ffver}"
            ffprobe="/usr/local/bin/ffprobe${_ffver}"
            break
        fi
    done
    unset _ffver
    if [ -z "$ffmpeg" ] || [ -z "$ffprobe" ]; then
        message="Kein SynoCommunity-ffmpeg gefunden (ffmpeg8, ffmpeg7 oder ffmpeg6 unter /usr/local/bin). Installiere z.B. https://synocommunity.com/package/ffmpeg8"
        echo "$message"
        synotr_dsmnotify error "$message"
        exit 1
    fi

# alle Kommandos und Kindprozesse des Skriptes mit niedrigst möglicher Priorität ausgeführen:
    echo "Priorität anpassen:       $(renice -n 19 -p $$)"
    echo "                          $("$ionice" -c 2 -n 7 -p $$)"

# Info der Datenbank auslesen:
# ---------------------------------------------------------------------
    if [ -f "${APPDIR}/app/etc/synOTR.sqlite" ] ; then
        rowcount=$(sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "SELECT COUNT(*) FROM raw")
        dbsize=$(ls -lh "${APPDIR}/app/etc/synOTR.sqlite" | awk '{ print $5 }')
        echo "DB-Größe:                 ${dbsize}Byte / $rowcount Datensätze"
    fi

# spezielle Programmpfade / sonstige Variablen anpassen :
# ---------------------------------------------------------------------
    echo "ffmpeg:                   $ffmpeg"
    echo "                          $("$ffmpeg" -version 2>/dev/null | head -n 1)"
    echo "ffprobe:                  $ffprobe"

    # avcut 0.8 ist dynamisch gegen ffmpeg8 (libavcodec.so.62) gelinkt; 4.3.1-avcut ist statisch.
    FFMPEG8_LIB="/var/packages/ffmpeg8/target/lib"
    if [ -d "$FFMPEG8_LIB" ]; then
        synOTR_LD_LIBRARY_PATH="${FFMPEG8_LIB}:${synOTR_LD_LIBRARY_PATH}"
        export LD_LIBRARY_PATH="$synOTR_LD_LIBRARY_PATH"
    fi
    if [ -n "$avcut_otrkey" ] && [ -f "$avcut_otrkey" ]; then
        chmod +x "$avcut_otrkey" 2>/dev/null || true
        echo "avcut (otrkey/4.3.1):     $avcut_otrkey"
    else
        echo "avcut (otrkey/4.3.1):     fehlt"
        avcut_otrkey=""
    fi
    if ! echo "$ffmpeg" | grep -q 'ffmpeg8$'; then
        if [ -n "$avcut_ffmpeg8" ] && [ -f "$avcut_ffmpeg8" ]; then
            echo "avcut (otr2/0.8):         übersprungen (braucht ffmpeg8, gefunden: $ffmpeg)"
        fi
        avcut_ffmpeg8=""
    elif [ -z "$avcut_ffmpeg8" ] || [ ! -f "$avcut_ffmpeg8" ]; then
        echo "avcut (otr2/0.8):         fehlt"
        avcut_ffmpeg8=""
    else
        chmod +x "$avcut_ffmpeg8" 2>/dev/null || true
        echo "avcut (otr2/0.8):         $avcut_ffmpeg8 (dynamisch ffmpeg8)"
    fi
    if [ -n "$avisplit" ] && [ -f "$avisplit" ]; then
        chmod +x "$avisplit" 2>/dev/null || true
        echo "avisplit:                 $avisplit"
    fi
    if [ -n "$avimerge" ] && [ -f "$avimerge" ]; then
        chmod +x "$avimerge" 2>/dev/null || true
    fi
    # Kompatibilität: $avcut = Smartrendering-Binary der jeweiligen Pipeline
    avcut="$avcut_otrkey"
    [ -n "$avcut_ffmpeg8" ] && avcut="$avcut_ffmpeg8"

# AAC-Konvertierung: sequentiell oder parallel (includes/convert_audio_parallel.sh)
# ---------------------------------------------------------------------
    synotr_encode_audio() {
        _ae_in="$1"
        _ae_out="$2"
        _ae_opts="$3"
        _ae_saved_ifs=$IFS
        IFS=${OLDIFS:-' '}
        if [ "${parallelAudioConvert:-on}" = "on" ] && [ -f "${APPDIR}/includes/convert_audio_parallel.sh" ] && [ -x /bin/bash ]; then
            echo "Audio-Konvertierung:      parallel"
            ffmpeg="$ffmpeg" ffprobe="$ffprobe" ffloglevel="$ffloglevel" WORKDIR="$WORKDIR" \
                /bin/bash "${APPDIR}/includes/convert_audio_parallel.sh" "$_ae_in" "$_ae_out" "$_ae_opts"
            convertLOG=""
            # Reste paralleler Audiokonvertierung (falls Cleanup im Hilfsskript ausblieb)
            if [ -n "$WORKDIR" ] && [ -d "$WORKDIR" ]; then
                for _ae_tmp in "${WORKDIR%/}"/.audio_parallel.* "${WORKDIR%/}"/tmp_synotr_audio_parallel.*; do
                    [ -d "$_ae_tmp" ] || continue
                    rm -rf "$_ae_tmp"
                done
                unset _ae_tmp
            fi
        else
            echo "Audio-Konvertierung:      sequentiell"
            # shellcheck disable=SC2086
            convertLOG=$("$ffmpeg" -threads 2 -loglevel "$ffloglevel" -i "$_ae_in" $_ae_opts "$_ae_out" 2>&1)
        fi
        IFS="$_ae_saved_ifs"
    }

# Konfiguration für LogLevel:
# ---------------------------------------------------------------------
    # LOGlevel:     0 => Logging inaktiv / 1 => normal / 2 => erweitert
    if [ "$LOGlevel" = "1" ] ; then
        echo "Loglevel:                 normal"
        ffloglevel="warning"        # ffmpeg LogLevel (https://ffmpeg.org/ffmpeg.html)
        CUTloglevel="-w"
        cURLloglevel="-s"
        wgetloglevel="-q"
    elif [ "$LOGlevel" = "2" ] ; then
        echo "Loglevel:                 erweitert"
        ffloglevel="info"
        CUTloglevel="-v"
        cURLloglevel="-v"
        wgetloglevel="-v"
    else
        ffloglevel="quiet"
        CUTloglevel="-w"
    fi
    if [ "$LOGlevel" = "2" ]; then
        mp4boxloglevel=""
    else
        mp4boxloglevel="-quiet"
    fi
    if [ -n "$mp4mux" ] && [ -f "$mp4mux" ]; then
        chmod +x "$mp4mux" 2>/dev/null || true
        echo "mp4mux (Bento4):          $mp4mux"
    fi
    if [ -n "$mp4box" ] && [ -f "$mp4box" ]; then
        chmod +x "$mp4box" 2>/dev/null || true
        echo "MP4Box:                   $mp4box"
    fi

    if [ -f "${APPDIR}/includes/ensure_mp4.sh" ]; then
        # shellcheck source=includes/ensure_mp4.sh
        . "${APPDIR}/includes/ensure_mp4.sh"
    fi
    if [ -f "${APPDIR}/includes/ffmpeg_cut.sh" ]; then
        # shellcheck source=includes/ffmpeg_cut.sh
        . "${APPDIR}/includes/ffmpeg_cut.sh"
    fi
    if [ -f "${APPDIR}/includes/synotr_db.sh" ]; then
        # shellcheck source=includes/synotr_db.sh
        . "${APPDIR}/includes/synotr_db.sh"
    fi
    if [ -f "${APPDIR}/includes/synotr_pipeline_otrkey.sh" ]; then
        # shellcheck source=includes/synotr_pipeline_otrkey.sh
        . "${APPDIR}/includes/synotr_pipeline_otrkey.sh"
    fi
    if [ -f "${APPDIR}/includes/synotr_pipeline_otr2.sh" ]; then
        # shellcheck source=includes/synotr_pipeline_otr2.sh
        . "${APPDIR}/includes/synotr_pipeline_otr2.sh"
    fi

# Verzeichnisse prüfen bzw. anlegen und anpassen:
# ---------------------------------------------------------------------
    echo "Anwendungsverzeichnis:    ${APPDIR}"
    
    # Variablenkorrektur für ältere Konfiguration.txt und Slash anpassen:
    if [ -d "${destdir:-}" ] ; then
        DESTDIR="${destdir%/}/"
    fi
    if [ -d "$DESTDIR" ] ; then
        DESTDIR="${DESTDIR%/}/"
    fi
    if [ -d "$OTRkeydeldir" ] ; then
        OTRkeydeldir="${OTRkeydeldir%/}/"
    fi
    if [ -d "$WORKDIR" ] ; then
        WORKDIR="${WORKDIR%/}/"
    fi

    if [ "$endgueltigloeschen" = "on" ] ; then
        echo "Endgültiges Löschen ist aktiviert!"
    else
        if [ -d "$OTRkeydeldir" ]; then
            echo "Löschverzeichnis:         $OTRkeydeldir"
        else
            mkdir -p "$OTRkeydeldir"
            echo "Löschverzeichnis wurde erstellt [$OTRkeydeldir]"
        fi
    fi

    if [ -z "$WORKDIR" ] ; then
        WORKDIR="${DESTDIR}"
        useWORKDIR="no"
        echo "Variable WORKDIR nicht gesetzt. Es wird im Zielverzeichnis gearbeitet!"
    elif [ "${WORKDIR}" = "${DESTDIR}" ] ; then
        useWORKDIR="no"
        echo "Variable WORKDIR entspricht dem Zielverzeichnis. Es wird im Zielverzeichnis gearbeitet!"
    else
        useWORKDIR="yes"
    fi

    if [ -d "$OTRkeydir" ] ; then
        echo "Quellverzeichnis:         $OTRkeydir"
    else
        echo "kein gültiges Quellverzeichnis gefunden!"
    fi

    if [ -d "$DESTDIR" ] ; then
        echo "Zielverzeichnis:          $DESTDIR"
    else
        mkdir -p "$DESTDIR"
        echo "Zielverzeichnis [$DESTDIR] wurde erstellt"
    fi

    if [ -d "$WORKDIR" ]; then
        echo "Arbeitsverzeichnis:       $WORKDIR"
    else
        mkdir -p "$WORKDIR"
        echo "Arbeitsverzeichnis [$WORKDIR] wurde erstellt."
    fi

    if [ "$OTRcutactiv" = "off" ] ; then
        DECODIR="$WORKDIR"
        echo "Decodierverzeichnis:      $DECODIR"
    else
        DECODIR="${WORKDIR%/}/_decodiert"
        if [ -d "$DECODIR" ]; then
            echo "Decodierverzeichnis:      $DECODIR"
        else
            mkdir -p "$DECODIR"
            echo "Decodierverzeichnis [$DECODIR] wurde erstellt"
        fi
    fi

#################################################################################################
#        _______________________________________________________________________________        #
#       |                                                                               |       #
#       |                           BEGINN DER FUNKTIONEN                               |       #
#       |_______________________________________________________________________________|       #
#                                                                                               #
#################################################################################################


failure()
{
# this function show error line
# --------------------------------------------------------------
    # https://unix.stackexchange.com/questions/462156/how-do-i-find-the-line-number-in-bash-when-an-error-occured
    local lineno=$1
    local msg=$2
    echo "Failed at $lineno: $msg"
}
trap 'failure ${LINENO} "$BASH_COMMAND"' ERR


sec_to_time() 
{
#########################################################################################
# diese Funktion wandelt einen Sekundenwert nach hh:mm                                  #
# Aufruf: sec_to_time "string"                                                          #
# https://blog.jkip.de/in-bash-sekunden-umrechnen-in-stunden-minuten-und-sekunden/      #
#########################################################################################
    local seconds=$1
    local sign=""
    if [[ ${seconds:0:1} == "-" ]]; then
        seconds=${seconds:1}
        sign="-"
    fi
    local hours=$(( seconds / 3600 ))
    local minutes=$(( (seconds % 3600) / 60 ))
    seconds=$(( seconds % 60 ))
    printf "%s%02d:%02d:%02d" "$sign" $hours $minutes $seconds
}


MovieDB_query() 
{
#########################################################################################
# Diese Funktion sucht auf theTVDB.com nach Serieninformationen                         #
#########################################################################################

    echo -e
    echo "MovieDB_query ==> nicht implementiert …"

}


# synotr_tvdb_lang3 LANG
# TVDB v4 erwartet ISO-639-3 (deu, eng). Einstellungen haben oft de/en.
synotr_tvdb_lang3()
{
    _l=$(printf '%s' "${1:-de}" | tr 'A-Z' 'a-z')
    case "$_l" in
        de|ger|deu) printf '%s\n' deu ;;
        en|eng) printf '%s\n' eng ;;
        fr|fre|fra) printf '%s\n' fra ;;
        it|ita) printf '%s\n' ita ;;
        es|spa) printf '%s\n' spa ;;
        nl|nld|dut) printf '%s\n' nld ;;
        ???) printf '%s\n' "$_l" ;;
        *) printf '%s\n' deu ;;
    esac
}

# synotr_tvdb_http_body CURL_ARGS...
# setzt synotr_tvdb_http und synotr_tvdb_body (HTTP-Code ans Body-Ende).
synotr_tvdb_http_body()
{
    restore_ENV
    # shellcheck disable=SC2086
    _tvdb_raw=$(curl ${cURLloglevel:--s} -w '\n%{http_code}' "$@")
    synOTR_ENV
    synotr_tvdb_http=$(printf '%s\n' "$_tvdb_raw" | tail -n 1)
    synotr_tvdb_body=$(printf '%s\n' "$_tvdb_raw" | sed '$d')
    unset _tvdb_raw
}

synotr_tvdb_login()
{
    echo "TVDB-Token wird erneuert (API v4) …"
    _tvdb_login_body=$(jq -nc --arg k "$TVDB_APIKEY" --arg p "${TVDB_PIN:-}" '
      if ($p | length) > 0 then {apikey: $k, pin: $p} else {apikey: $k} end
    ')
    synotr_tvdb_http_body -X POST --header 'Content-Type: application/json' --header 'Accept: application/json' -d "$_tvdb_login_body" 'https://api4.thetvdb.com/v4/login'
    unset _tvdb_login_body
    if echo "$synotr_tvdb_body" | grep -E -q "Connection timed out"; then
        echo "Serverfehler (Zeitüberschreitung)"
        synotr_tvdb_auth_fail=1
        return 1
    fi
    TVDB_TOKEN=$(printf '%s' "$synotr_tvdb_body" | jq -r '.data.token // empty')
    if [ -z "$TVDB_TOKEN" ] || [ "$TVDB_TOKEN" = "null" ]; then
        echo "TVDB-Login fehlgeschlagen (HTTP ${synotr_tvdb_http:-?}). API-v4-Key (und ggf. PIN) prüfen – v2/v3-Keys funktionieren nicht."
        if [ "$LOGlevel" = "2" ]; then
            echo "Abfrageergebnis: $synotr_tvdb_body"
        fi
        synotr_tvdb_auth_fail=1
        return 1
    fi
    _tvdb_esc=$(synotr_sql_escape "$TVDB_TOKEN")
    sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "UPDATE tvdb SET TOKEN='${_tvdb_esc}', day_created=${today}, timestamp=(datetime('now','localtime')) WHERE rowid=1"
    unset _tvdb_esc
    synotr_tvdb_auth_fail=0
    return 0
}

# true, wenn die Suchantwort keine Serien enthält (nicht auf das Wort Error prüfen).
synotr_tvdb_search_miss()
{
    [ -z "$TVDB_FilmID" ] && return 0
    echo "$TVDB_FilmID" | grep -E -q "Connection timed out" && return 0
    if echo "$TVDB_FilmID" | jq -e '.data | type == "array" and length > 0' >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

TVDB_query() 
{
#########################################################################################
# Diese Funktion sucht auf theTVDB.com nach Serieninformationen (API v4)                #
#########################################################################################

synotr_tvdb_auth_fail=0
synotr_tvdb_lang=$(synotr_tvdb_lang3 "${TVDBlang:-de}")

# Token aus der DB. Login-Key: Einstellungen, sonst User-Key in der DB (kein Paket-Default).
sSQL="SELECT day_created,TOKEN,APIKEY FROM tvdb WHERE rowid=1 "
sqlerg=$(sqlite3 -separator $'\t' ${APPDIR}/app/etc/synOTR.sqlite "$sSQL")
TOKEN_DAY_CREATED=$(echo "$sqlerg" | awk -F'\t' '{print $1}' )
TOKEN=$(echo "$sqlerg" | awk -F'\t' '{print $2}' )
_tvdb_stored=$(echo "$sqlerg" | awk -F'\t' '{print $3}' )

if [ "$LOGlevel" = "2" ] ; then
    echo "DB-Abfrageergebnis:       $sqlerg"
    echo "TVDB-Sprache (v4):        $synotr_tvdb_lang"
fi

if synotr_tvdb_is_bundled_default "$_tvdb_stored"; then
    sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "UPDATE tvdb SET APIKEY='', TOKEN='', day_created=$((today-1)), timestamp=(datetime('now','localtime')) WHERE rowid=1"
    _tvdb_stored=""
    TOKEN=""
    TOKEN_DAY_CREATED=""
fi

if [ -n "$TVDB_APIKEY" ] && [ "$TVDB_APIKEY" != "NULL" ]; then
    if [ "$_tvdb_stored" != "$TVDB_APIKEY" ]; then
        TOKEN=""
        TOKEN_DAY_CREATED=""
        _tvdb_esc=$(synotr_sql_escape "$TVDB_APIKEY")
        sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "UPDATE tvdb SET APIKEY='${_tvdb_esc}', TOKEN='', day_created=$((today-1)), timestamp=(datetime('now','localtime')) WHERE rowid=1"
        unset _tvdb_esc
    fi
elif [ -n "$_tvdb_stored" ] && [ "$_tvdb_stored" != "NULL" ]; then
    TVDB_APIKEY="$_tvdb_stored"
else
    echo "Kein TVDB-APIKEY in den Einstellungen – theTVDB-Abfrage übersprungen."
    unset _tvdb_stored
    return
fi
unset _tvdb_stored

if [ -z "$TOKEN_DAY_CREATED" ] || [ -z "$TOKEN" ] || [ "$TOKEN" = "NULL" ] || [ "$TOKEN_DAY_CREATED" -ne "$today" ]; then
    synotr_tvdb_login || return
fi

TVDB_TOKEN=$(sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "SELECT TOKEN FROM tvdb WHERE rowid=1")

if [ "$LOGlevel" = "2" ] ; then
    echo "TVDB_TOKEN: $TVDB_TOKEN"
fi

serietitletmp="${serietitle}"
synotr_tvdb_reauth=0
echo -e ;

    TVDB_seriesquery()
    {
    echo -n "Abfrage [$serietitletmp] an theTVDB.com ==> "
    # query/type reicht; language= filtert die Originalsprache und würde z. B. US-Serien auslassen.
    _tvdb_query=$(printf '%s' "$serietitletmp" | sed "s/_s_/'s_/g; s/ s /'s /g; s/_/ /g")
    synotr_tvdb_http_body -G \
        --header 'Accept: application/json' \
        --header "Authorization: Bearer ${TVDB_TOKEN}" \
        --data-urlencode "query=${_tvdb_query}" \
        --data-urlencode "type=series" \
        "https://api4.thetvdb.com/v4/search"
    TVDB_FilmID="$synotr_tvdb_body"
    if [ "$synotr_tvdb_http" = "401" ] && [ "$synotr_tvdb_reauth" != "1" ]; then
        synotr_tvdb_reauth=1
        echo "Token ungültig – Login wird wiederholt …"
        if synotr_tvdb_login; then
            synotr_tvdb_http_body -G \
                --header 'Accept: application/json' \
                --header "Authorization: Bearer ${TVDB_TOKEN}" \
                --data-urlencode "query=${_tvdb_query}" \
                --data-urlencode "type=series" \
                "https://api4.thetvdb.com/v4/search"
            TVDB_FilmID="$synotr_tvdb_body"
        fi
    fi
    unset _tvdb_query
    if echo "$TVDB_FilmID" | grep -E -q "Connection timed out"; then
        echo "Serverfehler (Zeitüberschreitung)"
    fi
    if [ "$LOGlevel" = "2" ]; then
        echo "HTTP ${synotr_tvdb_http:-?}"
    fi
    }

    TVDB_episodequery()
    {
    TVDB_SerieName=$(printf '%s' "$TVDB_FilmID" | jq -r --arg lang "$synotr_tvdb_lang" '.data[0] | (.translations[$lang] // .name_translated // .name // empty)' | sed "s/://g ; s/\?//g ; s/\*//g")
    echo "$TVDB_SerieName"
    title="$TVDB_SerieName"
    TVDB_FilmID=$(printf '%s' "$TVDB_FilmID" | jq -r '.data[0] | (.tvdb_id // .id) | tostring' | sed 's/^series-//')

    if echo "$TVDB_FilmID" | grep -q '^[[:digit:]]\+$'; then
        echo -e "Serie auf theTVDB.com gefunden - TVDB_FilmID: $TVDB_FilmID"
        _tvdb_season=$(printf '%s' "$season" | sed 's/^0*//')
        [ -z "$_tvdb_season" ] && _tvdb_season=0
        _tvdb_episode=$(printf '%s' "$episode" | sed 's/^0*//')
        [ -z "$_tvdb_episode" ] && _tvdb_episode=0
        synotr_tvdb_http_body -G \
            --header 'Accept: application/json' \
            --header "Authorization: Bearer ${TVDB_TOKEN}" \
            --data-urlencode "page=0" \
            --data-urlencode "season=${_tvdb_season}" \
            --data-urlencode "episodeNumber=${_tvdb_episode}" \
            "https://api4.thetvdb.com/v4/series/${TVDB_FilmID}/episodes/official"
        episodeninfo="$synotr_tvdb_body"
        if [ "$(printf '%s' "$episodeninfo" | jq -r '.data.episodes // [] | length')" = "0" ]; then
            synotr_tvdb_http_body -G \
                --header 'Accept: application/json' \
                --header "Authorization: Bearer ${TVDB_TOKEN}" \
                --data-urlencode "page=0" \
                --data-urlencode "season=${_tvdb_season}" \
                --data-urlencode "episodeNumber=${_tvdb_episode}" \
                "https://api4.thetvdb.com/v4/series/${TVDB_FilmID}/episodes/default"
            episodeninfo="$synotr_tvdb_body"
        fi
        unset _tvdb_season _tvdb_episode
        if echo "$episodeninfo" | grep -E -q "Connection timed out"; then
            echo "Serverfehler (Zeitüberschreitung)"
        fi
        if jq -e . >/dev/null 2>&1 <<<"$episodeninfo"; then
            episodetitle=$(printf '%s' "$episodeninfo" | jq -r '.data.episodes[0].name // empty' | sed "s/://g ; s/\?//g ; s/\*//g ; s/\///g")
            description=$(printf '%s' "$episodeninfo" | jq -r '.data.episodes[0].overview // empty')
            _tvdb_epid=$(printf '%s' "$episodeninfo" | jq -r '.data.episodes[0].id // empty')
            if [ -n "$_tvdb_epid" ] && [ "$synotr_tvdb_lang" != "eng" ]; then
                synotr_tvdb_http_body --header 'Accept: application/json' --header "Authorization: Bearer ${TVDB_TOKEN}" \
                    "https://api4.thetvdb.com/v4/episodes/${_tvdb_epid}/translations/${synotr_tvdb_lang}"
                _tvdb_tr_name=$(printf '%s' "$synotr_tvdb_body" | jq -r '.data.name // empty')
                _tvdb_tr_ov=$(printf '%s' "$synotr_tvdb_body" | jq -r '.data.overview // empty')
                if [ -n "$_tvdb_tr_name" ]; then
                    episodetitle=$(printf '%s' "$_tvdb_tr_name" | sed "s/://g ; s/\?//g ; s/\*//g ; s/\///g")
                fi
                if [ -n "$_tvdb_tr_ov" ]; then
                    description="$_tvdb_tr_ov"
                fi
                unset _tvdb_tr_name _tvdb_tr_ov
            fi
            unset _tvdb_epid
        else
            echo "Serverantwort konnte nicht verarbeitet werden (kein kompatibles JSON)"
        fi
        if [ -z "$episodetitle" ] || [ "$episodetitle" = "null" ] ; then
            echo -e "Die Serie wurde zwar auf theTVDB.com gefunden, allerdings keine passende Episode!"
            episodetitle=""
            if [ "$LOGlevel" = "2" ] ; then
                echo "Abfrageergebnis: $episodeninfo"
            fi
        fi
        missSeries=0
    else
        echo -e "Keine Serieninformationen auf theTVDB.com gefunden."
        if [ "$LOGlevel" = "2" ] ; then
            echo "Abfrageergebnis: $TVDB_FilmID"
        fi
    fi
    }

TVDB_seriesquery

if [ "$synotr_tvdb_auth_fail" = "1" ]; then
    echo "theTVDB-Abfrage abgebrochen (Login)."
    return
fi

if synotr_tvdb_search_miss; then # modifiziere die Abfrage (u.a. Großbuchstaben zusammenziehen)
    echo "Keine Serieninformationen auf theTVDB.com gefunden."
    if [ "$LOGlevel" = "2" ] ; then
        echo "Abfrageergebnis: $TVDB_FilmID"
    fi
    # einzelnstehende Großbuchstaben zusammenziehen / Unterstriche ersetzen:
    serietitletmp=$(echo $serietitletmp | sed 's/__/ - /g ; s/_/ /g ; s/  //g' | sed -e "s/ \([A-Z][a-z]\)/§tmp§\1/g ; s/\([A-Z]\) \([a-z]\)/\1§tmp§\2/g ; s/\([A-Z]\) /\1/g ; s/§tmp§/ /g ; s/[[:space:]]\{1,\}/ /g")
        #	Wenn Groß-klein, setze immer §tmp§ davor;                       s/ \([A-Z][a-z]\)/§tmp§\1/g
        #	Wenn Groß-Leerzeichen-klein, ersetze Leerzeichen durch §tmp§;   s/\([A-Z]\) \([a-z]\)/\1§tmp§\2/g
        #	Entferne alle Leerzeichen nach Großbuchstaben;                  s/\([A-Z]\) /\1/g
        #	Ersetze alle §tmp§ durch Leerzeichen;                           s/§tmp§/ /g
        #	Ersetze alle doppelten Leerzeichen durch je ein einziges;       s/[[:space:]]\{1,\}/ /g

    TVDB_seriesquery

    if synotr_tvdb_search_miss; then # versuche es mit Umlauten und Punkten zwischen einzeln stehenden Großbuchstaben
        echo "Keine Serieninformationen auf theTVDB.com gefunden."
        if [ "$LOGlevel" = "2" ] ; then
            echo "Abfrageergebnis: $TVDB_FilmID"
        fi
        # einzelnstehende Großbuchstaben mit Punkt trennen / Unterstriche ersetzen / Umlaute wiederherstellen (Umlautersetzung nur nach einem Konsonanten):
        serietitletmp=$(echo "${serietitle}" | sed 's/__/ - /g ; s/_/ /g ; s/  //g' | sed -e "s/\<ue/ü/g ; s/\<ae/ä/g ; s/\<oe/ö/g ; s/\<UE/Ü/g ; s/\<AE/Ä/g ; s/\<OE/Ö/g ; s/\([BCDFGHJKLMNPQRSTVWXYZ]\)\(ae\)/\1ä/g ; s/\([BCDFGHJKLMNPQRSTVWXYZ]\)\(ue\)/\1ü/g ; s/\([BCDFGHJKLMNPQRSTVWXYZ]\)\(oe\)/\1ö/g ; s/\([bcdfghjklmnpqrstvwxyz]\)\(oe\)/\1ö/g ; s/\([bcdfghjklmnpqrstvwxyz]\)\(ue\)/\1ü/g ; s/\([bcdfghjklmnpqrstvwxyz]\)\(ae\)/\1ä/g ; s/\([BCDFGHJKLMNPQRSTVWXYZ]\)\(AE\)/\1Ä/g ; s/\([BCDFGHJKLMNPQRSTVWXYZ]\)\(OE\)/\1Ö/g ; s/\([BCDFGHJKLMNPQRSTVWXYZ]\)\(UE\)/\1Ü/g" | sed -e "s/ \([A-Z][a-z]\)/§tmp§\1/g ; s/\([A-Z]\) \([a-z]\)/\1\. \2/g ; s/\([A-Z]\) /\1\./g ; s/§tmp§/ /g ; s/[[:space:]]\{1,\}/ /g" | sed -f ${APPDIR}/includes/textersetzung.txt)
        #	ersetze alle großen UE (> Ü) nach einem großen Konsonaten   s/\([BCDFGHJKLMNPQRSTVWXYZ]\)\(UE\)/\1Ü/g
        #	ersetze alle UE am Anfang der Zeile                         s/^UE/Ü/g
            #   > ersetzt durch: \< (= Anfang jedes Wortes)             s/\<UE/Ü/g

        TVDB_seriesquery

        if synotr_tvdb_search_miss; then # versuche es mit dem OTR-Metadatentitel
            echo "Keine Serieninformationen auf theTVDB.com gefunden."
            if [ "$LOGlevel" = "2" ] ; then
                echo "Abfrageergebnis: $TVDB_FilmID"
            fi
            if [ -n "$OTRtitle" ] && [ "$OTRtitle" != "null" ] ; then
                serietitletmp="$OTRtitle"
                TVDB_seriesquery

                if synotr_tvdb_search_miss; then
                    echo "Keine Serieninformationen auf theTVDB.com gefunden."
                    if [ "$LOGlevel" = "2" ] ; then
                        echo "Abfrageergebnis: $TVDB_FilmID"
                    fi
                else
                    TVDB_episodequery
                fi
            fi
        else
            TVDB_episodequery
        fi
    else
        TVDB_episodequery
    fi
else
    TVDB_episodequery
fi
}


OTRdecoder()
{
#########################################################################################
# Diese Funktion dekodiert heruntergeladene .otrkey- und .otr2-Dateien                  #
#########################################################################################

    AC3ReMux ()
    {
    #########################################################################################
    # Diese Funktion ersetzt die MP3-Audiospur durch eine heruntergeladene AC3-Audiospur    #                       
    #########################################################################################
    
    filetest=$(find "$DECODIR" -maxdepth 1 -name "*.ac3" -type f)
    if [ ! -z "$filetest" ] ; then
        echo -e ; echo -e
        echo "==> integriere AC3-Audiospur:"
        echo "    (Bitte beachte: die AC3-Funktion hat experimentellen Charakter."
        echo "    Es gibt immer wieder Filme, wo es nicht 100% passt, bzw. es zu Problemen kommt.)"
            
            IFS=$'\012'
            for i in $(find "$DECODIR" -maxdepth 1 -name "*.ac3" -type f)
                do
                    IFS=$OLDIFS
                    ac3filename=$(basename "$i")
                    videosource=$(find "$DECODIR" -maxdepth 1 -name "${ac3filename%.HD*}*" -type f -and ! -name "*.ac3" -type f)
                    videosourcefilename=$(basename "$videosource")
                    videosourcetitle=${videosourcefilename%.*}

                    muxerror=0  # nur für Log
                    if [ -f "${DECODIR}/${videosourcetitle}.avi" ]; then
                        echo -e; echo "MUXING:              ---> ${ac3filename}" #; echo -e
                        muxingLOG=$("$ffmpeg" -threads 2 -loglevel "$ffloglevel"  -i "${DECODIR}/${videosourcetitle}.avi" -i "$i"  -map 0:0 -map 1:0 -c:a copy -async 1 -c:v copy -sn -y "${DECODIR}/${videosourcetitle}.ac3tmp.avi" 2>&1)

                        if [ -f "${DECODIR}/${videosourcetitle}.ac3tmp.avi" ]; then
                            # Original löschen / umbenennen:
                            if [ "$endgueltigloeschen" = "on" ] ; then
                                rm "$i"
                                rm "${DECODIR}/${videosourcetitle}.avi"
                            else
                                mv "$i" "$OTRkeydeldir"
                                mv "${DECODIR}/${videosourcetitle}.avi" "${OTRkeydeldir}/${videosourcetitle}.mp3.avi"
                            fi
                            mv "${DECODIR}/${videosourcetitle}.ac3tmp.avi" "${DECODIR}/${videosourcetitle}.avi"
                            echo "                          L==> fertig"
                        else
                            echo "                          L==> muxen fehlgeschlagen [Datei im Zielverzeichnis nicht gefunden …]"; echo -e
                            echo "muxingLOG: $muxingLOG"
                            muxerror=1
                        fi
                    else
                        echo "    > keine passende Videodatei gefunden!"
                    fi
                    if [ "$LOGlevel" = "2" ] && [ "$muxerror" = "0" ] ; then
                        echo "LogLevelinfo:"
                        echo "muxingLOG: $muxingLOG"
                    fi
                done
            sleep 1
    fi
    }

filetest=$(find "${OTRkeydir}" -maxdepth 1 \( -name "*.otrkey" -o -name "*.otr2" \) -mmin +"$timediff" -type f)

if [ "$decoderactiv" = "on" ] && [ ! -z "$filetest" ] ; then
    echo -e ;
    echo "==> decodieren:"
    OTRkeydir="${OTRkeydir%/}/"

    if ! command -v otrdecoder >/dev/null 2>&1 ; then
        echo "    ! ! ! otrdecoder-Wrapper nicht im PATH (${APPDIR}/app/bin). Decodieren wird übersprungen."
        AC3ReMux
        return
    fi
    
    IFS=$'\012'	 # entspricht einem $'\n' Newline
    for i in $(find "${OTRkeydir}" -maxdepth 1 \( -name "*.otrkey" -o -name "*.otr2" \) -mmin +"$timediff" -type f)
        do
            IFS=$OLDIFS
            echo -e
            filename=$(basename "$i")
            case "$filename" in
                *.otr2)   decofilename="${filename%.otr2}.mp4" ;;
                *.otrkey) decofilename="${filename%.otrkey}" ;;
                *)        decofilename="${filename%.*}" ;;
            esac
            echo "    DECODIERE:       ---> $filename"
            echo -n "                          "; date

            otrdecoderLOG=$(otrdecoder --force --email "$OTRuser" --password "$OTRpw" --quellordner "$i" --zielordner "$DECODIR" 2>&1)
            deco_rc=$?

            if [ "$LOGlevel" = "2" ] ; then
                echo "OTRdecoder LOG (exit ${deco_rc}): $otrdecoderLOG"
            fi
            if [ "$deco_rc" -eq 2 ] ; then
                echo -e; echo "    ! ! ! OTR-Decoder: Zugangsdaten fehlen oder sind falsch. Datei wird übersprungen."
                echo -e; echo "OTRdecoder LOG:"; echo "$otrdecoderLOG"
                continue
            elif [ "$deco_rc" -eq 4 ] ; then
                echo -e; echo "    ! ! ! OTR-Decoder: kein Recht auf diese Aufnahme. Datei wird übersprungen."
                echo -e; echo "OTRdecoder LOG:"; echo "$otrdecoderLOG"
                continue
            elif [ "$deco_rc" -ne 0 ] ; then
                echo -e; echo "    ! ! ! OTR-Decoder fehlgeschlagen (exit ${deco_rc}). Datei wird übersprungen."
                echo -e; echo "OTRdecoder LOG:"; echo "$otrdecoderLOG"
                continue
            fi

            if [ -f "${DECODIR}/$decofilename" ]; then 	# nur löschen, wenn erfolgreich decodiert:
                if [ "$endgueltigloeschen" = "on" ] ; then
                    rm "$i"
                else
                    mv "$i" "$OTRkeydeldir"
                fi
                    
                    ffprobeSourceInfo=$("$ffprobe" -v quiet -print_format json -show_format -show_streams "${DECODIR}/$decofilename" 2>&1)
#                   ffprobeSourceInfo=$("$ffprobe" -v quiet -print_format json -show_format -show_streams -show_programs "${DECODIR}/$decofilename" 2>&1)
                        # Errormeldung vor jason ab DSM 6.2 (wird hier abgeschnitten): ERROR: 
                        # ld.so: object 'openhook.so' from LD_PRELOAD cannot be preloaded (cannot open shared object file): ignored. { …
                        ffprobeSourceInfo="{ ${ffprobeSourceInfo#*\{}"  
                        
                    OTRtitle=$(echo "$ffprobeSourceInfo" | jq '.format.tags.title' | sed "s/\" //g" | sed "s/\"//g" | sed "s/'/''/g" | sed "s/\"//g"  | uconv -f utf-8 -t utf-8 -x NFC )
                    OTRcomment=$(echo "$ffprobeSourceInfo" | jq '.format.tags.comment' | sed "s/\" //g" | sed "s/\"//g" | sed "s/'/''/g" | sed "s/\"//g"  | uconv -f utf-8 -t utf-8 -x NFC )

                    if [ "$LOGlevel" = "2" ] ; then
                        echo -e; echo "        ------------------------->"
                        echo "    OTRtitle:   > $OTRtitle"
                        echo "    OTRcomment: > $OTRcomment"
                        echo -n "        Datenbank schreiben ==> "
                    fi
                    
                    _sql_deco=$(printf '%s' "$decofilename" | sed "s/'/''/g")
                    _sql_enc=$(printf '%s' "$filename" | sed "s/'/''/g")
                    _file_source="otrkey"
                    case "$filename" in
                        *.otr2) _file_source="otr2" ;;
                    esac
                    sSQL="INSERT INTO raw ( file_original, file_encrypted, file_source, OTRtitle, OTRcomment) VALUES ('$_sql_deco', '$_sql_enc', '$_file_source', '$OTRtitle', '$OTRcomment')"
                    unset _sql_deco _sql_enc _file_source
                    # leider werden Umlaute und Sonderzeichen nicht korrekt codiert … !
                    sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "$sSQL"
                    
                    if [ "$LOGlevel" = "2" ] ; then
                        echo "	sSQL: $sSQL"
                        echo "fertig"; echo "        <-------------------------"
                    fi
                    echo "                          L==> fertig"
                else
                    echo "                          L==> decodieren fehlgeschlagen [Datei im Zielverzeichnis nicht gefunden …]"; echo -e
                    echo "OTRdecoder LOG: $otrdecoderLOG"
                    continue
                fi
                
                if [ "$lastjob" -eq 1 ] && [ "$useWORKDIR" == "no" ] ; then
                    if [ "$dsmtextnotify" = "on" ] ; then
                        sleep 1
                        synotr_dsmnotify job_successful "$filename ist fertig"
                        sleep 1
                    fi
                    if [ "$dsmbeepnotify" = "on" ] ; then
                        sleep 1
                        echo 2 > /dev/ttyS1 #short beep
                        sleep 1
                    fi
                    synotr_apprise_notify "Film [$filename] ist fertig."
                fi
        done
elif [ "$decoderactiv" = "off" ] ; then
    echo -e ; echo -e ; echo "==> decodieren ist deaktiviert"
fi
sleep 1

AC3ReMux

}


OTRautocut()
{
#########################################################################################
# Diese Funktion schneidet die Filme anhand einer lokalen Cutlist, oder                 #
# einer automatisch auf cutlist.at gefundenen Cutlist                                   #
#                                                                                       #
#                                                                                       #
#                                                                                       #
# Die meisten Cut-Funktionen stammen ursprünglich von:                                  #
#   Author:             Daniel Siegmanski                                               #
#   Homepage:           http://www.siggimania4u.de                                      #
#   OtrCut Download:    http://otrcut.siggimania4u.de                                   #
#   Source github.com:  https://github.com/adlerweb/otrcut.sh/blob/master/otrcut.sh     #
#########################################################################################

IFS=$'\012'

filetest=$(find "$DECODIR" -maxdepth 1 -name "*.avi" -o -name "*.mp4" -type f)

#if [ "$OTRavi2mp4active" = "on" ] && [ ! -z "$filetest" ] ; then
if [ -z "$filetest" ] ; then
    return
fi

if [ "$OTRcutactiv" = "on" ] ; then
    echo -e ; echo -e
    if [ "$SMARTRENDERING" = "on" ] && [ -z "$avcut_otrkey" ] && [ -z "$avcut_ffmpeg8" ]; then
        SMARTRENDERING="off"
        echo "Smartrendierung (framegenaues Schneiden) nicht möglich, da kein avcut gefunden wurde."
        echo "otrkey: avisplit (x86_64); otr2: ffmpeg+mp4mux an Keyframes."
    fi

    echo "==> schneiden:"

    if [ "${RAMmax}" -lt 490 ]; then
        SMARTRENDERING="off"
        echo "Für das framegenaue Schneiden wird mindestens 500 MB installierter RAM benötigt ($RAMmax MB installiert)."
        echo "Smartrendering wird aufgrund fehlenden Arbeitsspeichers deaktiviert."
        echo "otrkey: avisplit (x86_64); otr2: ffmpeg+mp4mux an Keyframes."; echo -e
    fi

    # Schnitt-Temp im Arbeitsverzeichnis (nicht versteckt, analog tmp_synotr_audio_parallel.*)
    tmp="${WORKDIR%/}/tmp_synotr_cut"
    if [ -d "$tmp" ]; then
        echo "Entferne liegengebliebenes Schnitt-Temp: $tmp"
        rm -rf "${tmp:?}"
    fi
    if [ -d "${WORKDIR%/}/.synotr_cut" ]; then
        echo "Entferne altes Schnitt-Temp: ${WORKDIR%/}/.synotr_cut"
        rm -rf "${WORKDIR%/}/.synotr_cut"
    fi
    if [ -d "${WORKDIR%/}/.synotr_ffcut" ]; then
        echo "Entferne liegengebliebenes Keyframe-Temp: ${WORKDIR%/}/.synotr_ffcut"
        rm -rf "${WORKDIR%/}/.synotr_ffcut"
    fi
    if [ -d "${WORKDIR%/}/.synotr_remux" ]; then
        echo "Entferne altes Remux-Temp: ${WORKDIR%/}/.synotr_remux"
        rm -rf "${WORKDIR%/}/.synotr_remux"
    fi
    if [ -d "${WORKDIR%/}/tmp_synotr_remux" ]; then
        echo "Entferne liegengebliebenes Remux-Temp: ${WORKDIR%/}/tmp_synotr_remux"
        rm -rf "${WORKDIR%/}/tmp_synotr_remux"
    fi
    mkdir -p "$tmp"
    echo "Schnitt-Temp:             $tmp"
    server="http://cutlist.at/"

        synotr_cutlist_stem ()
        {
        # Sendungs-Stamm ohne Container/Qualität, damit LQ/HQ/HD derselben Aufnahme zusammenpassen.
        # ---------------------------------------------------------------------
        _stem=$1
        _stem=${_stem##*/}
        _stem=${_stem%.cutlist}
        _stem=${_stem%.avi}
        _stem=${_stem%.mpg}
        _stem=${_stem%.mp4}
        _stem=${_stem%.mkv}
        _stem=${_stem%.ac3}
        _stem=$(echo "$_stem" | sed 's/\.HQ$//;s/\.HD$//;s/\.LQ$//;s/^DivFix++\.//;s/^DivFix\.//')
        echo "$_stem"
        }

        synotr_pick_local_cutlist ()
        {
        # $1 = Verzeichnis. Gleiche Sendung, Qualität egal. Error-Flags sind kein Veto.
        # Bei Treffer: Cutlist nach $tmp, vorhanden/UseLocalCutlist/continue gesetzt, _pick_why gesetzt.
        # ---------------------------------------------------------------------
        _cldir=${1%/}
        [ -n "$_cldir" ] && [ -d "$_cldir" ] || return 1

        _filmOhnePfad=$(basename "$film")
        _filesize=$(ls -l "$film" | awk '{ print $5 }')
        _film_stem=$(synotr_cutlist_stem "$_filmOhnePfad")
        _pick=""
        _pick_why=""

        if [ -f "${_cldir}/${_filmOhnePfad}.cutlist" ]; then
            _pick="${_cldir}/${_filmOhnePfad}.cutlist"
            _pick_why="Dateiname"
        fi

        if [ -z "$_pick" ]; then
            for f in "${_cldir}"/*.cutlist; do
                [ -f "$f" ] || continue
                _cl_apply=$(grep -m1 '^ApplyToFile=' "$f" | cut -d= -f2- | /usr/bin/tr -d "\r")
                _cl_size=$(grep -m1 '^OriginalFileSizeBytes=' "$f" | cut -d= -f2- | /usr/bin/tr -d "\r")
                if [ "$_cl_apply" = "$_filmOhnePfad" ]; then
                    _pick=$f
                    _pick_why="ApplyToFile"
                    break
                fi
                if [ -n "$_cl_size" ] && [ "$_cl_size" = "$_filesize" ]; then
                    _pick=$f
                    _pick_why="OriginalFileSizeBytes"
                    break
                fi
            done
        fi

        if [ -z "$_pick" ]; then
            for f in "${_cldir}"/*.cutlist; do
                [ -f "$f" ] || continue
                _cl_base=${f##*/}
                _cl_apply=$(grep -m1 '^ApplyToFile=' "$f" | cut -d= -f2- | /usr/bin/tr -d "\r")
                _cl_stem=$(synotr_cutlist_stem "$_cl_base")
                _cl_apply_stem=""
                if [ -n "$_cl_apply" ]; then
                    _cl_apply_stem=$(synotr_cutlist_stem "$_cl_apply")
                fi
                if [ "$_cl_stem" != "$_film_stem" ] && [ "$_cl_apply_stem" != "$_film_stem" ]; then
                    continue
                fi
                if grep -q '^Start=' "$f"; then
                    _pick=$f
                    _pick_why="gleiche Sendung (Qualität ignoriert)"
                    break
                fi
                echo "File: $_cl_base gleiche Sendung, aber nur Frame-Cuts – übersprungen."
            done
        fi

        if [ -z "$_pick" ]; then
            unset _cldir _filmOhnePfad _filesize _film_stem _pick _cl_apply _cl_size _cl_base _cl_stem _cl_apply_stem
            return 1
        fi

        CUTLIST=${_pick##*/}
        cp "$_pick" "$tmp/$CUTLIST"
        vorhanden=yes
        UseLocalCutlist=yes
        continue=0
        if [ "$LOGlevel" = "1" ] || [ "$LOGlevel" = "2" ]; then
            cp "$tmp/$CUTLIST" "${DECODIR}/_LOGsynOTR/${CUTLIST}"
        fi
        unset _cldir _filmOhnePfad _filesize _film_stem _pick _cl_apply _cl_size _cl_base _cl_stem _cl_apply_stem
        return 0
        }

        AC_test ()
        {
        # Schnitt-Temp liegt unter WORKDIR; nach Crash dort räumbar.
        # ---------------------------------------------------------------------
        tmp="${WORKDIR%/}/tmp_synotr_cut"
        if [ ! -d "$tmp" ]; then
            mkdir -p "$tmp"
        fi
        if [ -d "$tmp" ] && [ -w "$tmp" ]; then
            AC_testLOG="Verwende $tmp als Schnitt-Temp."
        else
            AC_testLOG="Keine Schreibrechte in $tmp"
        fi
        if [ "$LOGlevel" = "2" ] ; then
            echo "$AC_testLOG"
        fi
        }

        AC_ffprobe ()
        {
        # Diese Funktion ließt via ffprobe Dateiinformationen aus:
        # ---------------------------------------------------------------------
        AC_ffprobeInfo=$("$ffprobe" -v quiet -print_format json -show_format -show_streams "$i" 2>&1)
            
            # Errormeldung vor jason ab DSM 6.2 (wird hier abgeschnitten): 
            # ERROR: 
            # ld.so: object 'openhook.so' from LD_PRELOAD cannot be preloaded (cannot open shared object file): ignored. { …
            AC_ffprobeInfo="{ ${AC_ffprobeInfo#*\{}"  
        }

        AC_check_software ()
        {
        # Steht die 'date'-Funktion zum Umrechnen der Cuts zur Verfügung?:
        # ---------------------------------------------------------------------
        # Hier wird ueberprueft ob date zum umrechnen der Zeit benutzt werden kann
        date_varLOG="Überpruefe welche Methode zum Umrechnen der Zeit benutzt wird --> "
        date_var=$(date -u -d @120 +%T 2>/dev/null)
        if [ "$date_var" == "00:02:00" ]; then
            date_okay=yes
            date_varLOG="${date_varLOG} date"
        else
            date_okay=no
            date_varLOG="${date_varLOG} date"
        fi

        if [ "$LOGlevel" = "2" ] ; then
                echo "$date_varLOG"
        fi
        if [ "$SMARTRENDERING" != "on" ] && { [ -z "$avisplit" ] || [ ! -f "$avisplit" ]; }; then
            echo "avisplit wurde nicht gefunden – otrkey-Keyframe/HD auf x86_64 nicht möglich."
        fi
        }

        AC_name ()
        {
        # Diese Funktion definiert den Cutlist- und Dateinamen
        # und überprüft um welches Dateiformat es sich handelt:
        # ---------------------------------------------------------------------
        film="$i"                   # Der komplette Filmname und gegebenfalls der Pfad
        film_ohne_anfang="${film##*/}"
        AC_nameLOG="Überprüfe um welches Aufnahmeformat es sich handelt --> "

        if echo "$film_ohne_anfang" | grep -q ".mpg.HQ.mp4"; then
            film_ohne_ende=${film_ohne_anfang%.mpg.HQ.mp4}
            outputfile="${WORKDIR}${film_ohne_ende}.HQ-cut.mp4"
            AC_nameLOG="${AC_nameLOG}HQ.mp4"
        elif echo "$film_ohne_anfang" | grep -q ".mpg.HD.mp4"; then
            film_ohne_ende=${film_ohne_anfang%.mpg.HD.mp4}
            outputfile="${WORKDIR}${film_ohne_ende}.HD-cut.mp4"
            AC_nameLOG="${AC_nameLOG}HD.mp4"
        elif echo "$film_ohne_anfang" | grep -q ".HQ.mp4"; then
            film_ohne_ende=${film_ohne_anfang%.HQ.mp4}
            outputfile="${WORKDIR}${film_ohne_ende}.HQ-cut.mp4"
            AC_nameLOG="${AC_nameLOG}HQ.mp4"
        elif echo "$film_ohne_anfang" | grep -q ".HD.mp4"; then
            film_ohne_ende=${film_ohne_anfang%.HD.mp4}
            outputfile="${WORKDIR}${film_ohne_ende}.HD-cut.mp4"
            AC_nameLOG="${AC_nameLOG}HD.mp4"
        elif echo "$film_ohne_anfang" | grep -q ".LQ.mp4"; then
            film_ohne_ende=${film_ohne_anfang%.LQ.mp4}
            outputfile="${WORKDIR}${film_ohne_ende}.LQ-cut.mp4"
            AC_nameLOG="${AC_nameLOG}LQ.mp4"
        elif echo "$film_ohne_anfang" | grep -q ".mpg.HQ.avi"; then
            film_ohne_ende=${film_ohne_anfang%.mpg.HQ.avi}
            outputfile="${WORKDIR}${film_ohne_ende}.HQ-cut.mp4"
            AC_nameLOG="${AC_nameLOG}HQ"
        elif echo "$film_ohne_anfang" | grep -q ".mpg.HD.avi"; then
            film_ohne_ende=${film_ohne_anfang%.mpg.HD.avi}
            outputfile="${WORKDIR}${film_ohne_ende}.HD-cut.mp4"
            AC_nameLOG="${AC_nameLOG}HD"
        elif echo "$film_ohne_anfang" | grep -q ".mpg.mp4"; then
            film_ohne_ende=${film_ohne_anfang%.mpg.mp4}
            outputfile="${WORKDIR}${film_ohne_ende}.LQ-cut.mp4"
            AC_nameLOG="${AC_nameLOG}LQ.mp4"
        else
            film_ohne_ende=${film_ohne_anfang%.mpg.avi}
            outputfile="${WORKDIR}${film_ohne_ende}-cut.mp4"
            AC_nameLOG="${AC_nameLOG}avi"
        fi

        if [ "$LOGlevel" = "2" ] ; then
            echo "$AC_nameLOG"
        fi
        }

        AC_getlocalcutlist_CheckedVersion () # Nicht aktiv
        {
        #In dieser Funktion wird die lokale Cutlist überprüft:
        # ---------------------------------------------------------------------
        local_cutlists=$(ls *.cutlist 2>/dev/null)	#Variable mit allen Cutlists in $PWD
        match_cutlists=""	## passende Cutlisten zum Film
        filesize=$(ls -l "$film" | awk '{ print $5 }') #Dateigröße des Filmes
        goodCount=0 #Passende Cutlists
        arraylocal=1 #Nummer des Arrays
        for f in $local_cutlists; do
            echo -n "Überprüfe ob eine der gefundenen Cutlists zum Film passt --> "
            if [ -z "$f" ]; then
                echo -e "Keine Cutlist gefunden!"
                    vorhanden=no
                    continue=1
            fi
                
            OriginalFileSize=$(cat $f | grep OriginalFileSizeBytes | cut -d"=" -f2 | /usr/bin/tr -d "\r")	#Dateigröße des Films

            if cat $f | grep -q "$film"; then	#Wenn der Dateiname mit ApplyToFile übereinstimmt
                echo -e -n "ApplyToFile "
                ApplyToFile=yes
                vorhanden=yes
            fi
            if [ "$OriginalFileSize" == "$filesize" ]; then	#Wenn die Dateigröße mit OriginalFileSizeBytes übereinstimmt
                echo -e -n "OriginalFileSizeBytes"
                OriginalFileSizeBytes=yes
                vorhanden=yes
            fi
            if [ "$vorhanden" == "yes" ]; then	#Wenn eine passende Cutlist vorhanden ist
                goodCount=$(( goodCount + 1 ))
                namelocal[$arraylocal]="$f"
                arraylocal=$(( arraylocal + 1 ))
                continue=0
            else
                echo -e "false"
            fi
        done

        if [ "$goodCount" -eq 1 ]; then	#Wenn nur eine Cutlist gefunden wurde
            echo "Es wurde eine passende Cutlist gefunden. Diese wird nun verwendet."
            CUTLIST="$f"
            cp "$CUTLIST" "$tmp"
        elif [ "$goodCount" -gt 1 ]; then	#Wenn mehrere Cutlists gefunden wurden
            echo "Es wurden $goodCount Cutlists gefunden. Bitte wählen Sie aus:"
            echo ""
            number=1

            for (( i=1; i <= $goodCount ; i++ )); do
                echo "$number: ${namelocal[$number]}"
                number=$(( number + 1 ))
            done

            echo -n "Bitte die Nummer der zu verwendenden Cutlist eingeben:"
            read NUMBER

            while [ "$NUMBER" -gt "$goodCount" ]; do
                echo "false. Noch mal:"
                read NUMBER
            done

            echo "Verwende ${namelocal[$NUMBER]} als Cutlist."
            CUTLIST="${namelocal[$NUMBER]}"
            cp "$CUTLIST" "$tmp"
            vorhanden=yes
        fi
        }

        AC_getlocalcutlist_withCheck ()
        {
        # Optionales Cutlist-Verzeichnis – Zuordnung über synotr_pick_local_cutlist.
        # ---------------------------------------------------------------------
        synotr_pick_local_cutlist "$OTRlocalcutlistdir"
        }

        AC_getlocalcutlist_withoutCheck ()
        {
        #In dieser Funktion wird die lokale Cutlist ohne Prüfung gewählt (Standard):
        # ---------------------------------------------------------------------
        echo -n "Lade LOCALCUTLIST ${LOCAL_CUTLIST} --> "
        cp "${LOCAL_CUTLIST}" "$tmp"
        CUTLIST="${filename}.cutlist"
        continue=0
        UseLocalCutlist="yes"
        cutlist_okay=yes # wird hier ohne Prüfung angenommen

        if [ -f "${tmp}/$CUTLIST" ] && [ "$cutlist_okay" == "yes" ]; then
            echo -e "okay"
            echo "Es wird eine lokale Cutlist verwendet"
            echo -e
            continue=0
            cp "${tmp}/$CUTLIST" "${DECODIR}/_LOGsynOTR/${CUTLIST}"
            vorhanden="yes"
        else
            echo -e "false"
            echo "Es wurde zwar eine lokale Cutlist gefunden, aber leider wurde ein Fehler festgestellt"
            continue=1
        fi
        }

        AC_getcutlist ()
        {
        #In dieser Funktion wird versucht eine Cutlist aus den Internet zu laden
        # ---------------------------------------------------------------------

            AC_test_cutlist ()
            {
            #In dieser Funktion wird geprüft, ob die geladene Cutlist okay ist
            # ---------------------------------------------------------------------
            cutlist_size=$(ls -l "$tmp/$CUTLIST" | awk '{ print $5 }')
            if [ "$cutlist_size" -lt "100" ]; then
                cutlist_okay=no
                echo "Die Cutlist scheint beschädigt zu sein"
                if [ -f "$tmp/$CUTLIST" ]; then
                    rm -f "$tmp/$CUTLIST"
                fi
                return 1
            else
                cutlist_okay=yes
            fi
            return 0
            }

            parseXmlTag () 
            {
            #In dieser Funktion wird der gesucht Parameter einer XML-Zeile zurückgegeben
            # ---------------------------------------------------------------------
                sed -n '/<\/'$1'>/p' "$tmp/search.xml" | sed -n ''$2'p' | sed 's/<'$1'>//' | sed 's/<\/'$1'>//g' | sed 's/^[ \t]*//'
            }

        continue=0
        filesize=$(ls -l "$film" | awk '{ print $5 }')
        filesizeMB=$(gawk -v n="$filesize" 'BEGIN { printf "%.2f\n", n/1000000 }')

        if [ "$LOGlevel" = "2" ] ; then
            echo "Dateigröße:   $filesize Byte / $filesizeMB MB"
        fi

        echo -n "Suche anhand des Dateinamens     ---> "
        wget -U "synOTR/$CLIENTVERSION" --timeout=30 --tries=2 $wgetloglevel -O "$tmp/search.xml" "${server}getxml.php?name=$filename"

        if [ $? -eq 0 ] && grep -q '<id>' "$tmp/search.xml"; then
            echo -e "okay"
        else
            echo "Keine Cutlist anhand des Namens gefunden!"
            echo -n "Suche anhand der Dateigröße      ---> "
            wget -U "synOTR/$CLIENTVERSION" --timeout=30 --tries=2 $wgetloglevel -O "$tmp/search.xml" "${server}getxml.php?ofsb=$filesize"
            
            if [ $? -eq 0 ] && grep -q '<id>' "$tmp/search.xml"; then
                echo -e "okay"
            else
                echo -e "Keine Cutlist anhand der Dateigröße gefunden!"
                if [ "$useallcutlistformat" == "1" ]; then
                    # es werden Cutlists für andere Qualitäten gesucht. 
                    echo -n "Suche alternatives Cutlistformat ---> "
                    search=$(synotr_cutlist_stem "$filename")
                    wget -U "synOTR/$CLIENTVERSION" --timeout=30 --tries=2 $wgetloglevel -O "$tmp/search.xml" "${server}getxml.php?name=$search"
                
                    if ([ $? -eq 0 ] && grep -q '<id>' "$tmp/search.xml") && ( grep -q '<withtime>1</withtime>' "$tmp/search.xml" ); then # Aufgrund der unterschiedlichen Frameraten, werde derzeit nur Cutlists mit Zeitangaben verwendet
                        useonlytimecuts=1
                        echo -e "okay (eine alternative Cutlist kann ungenaue Schnitte erzeugen!)"
                    else
                        echo -e "Kein alternatives Cutlistformat gefunden!"
                        continue=1
                    fi
                else
                    continue=1
                fi
            fi
        fi

        # Hier wird die Suchanfrage überprüft
        if [ "$continue" == "1" ]; then
            echo -e "                                 L==> Es wurde leider keine Cutlist gefunden!"
        else
            sed -i 's/<rating><\/rating>/<rating>0.00<\/rating>/g' "$tmp/search.xml"     # fehlendes rating durch 0.00 ersetzen / -i ändert die Quelldatei
            sed -i $'s/\r$//' "$tmp/search.xml"                                          # convert Dos to Unix
            
            cutlist_anzahl=$(grep --text -c '/cutlist' "$tmp/search.xml" | /usr/bin/tr -d "\r") 

            echo -e
            echo "Anzahl gefunden:          $cutlist_anzahl"

            array=0

            if [ "$cutlist_anzahl" -ge "1" ] ; then # Wenn Cutlists gefunden wurden
                # schreibe ratings in je ein array:
                tail=1
                unset rating;
                unset ratingbyauthor;
                while [ "$cutlist_anzahl" -gt "0" ]; do 
                    # XML-Parsing über Funktion => macht ab dem 2. Film Probleme bei dem array "ratingbyauthor"
                    ratingbyauthor[$array]=$(parseXmlTag "ratingbyauthor" $tail ) 
                    rating[$array]=$(parseXmlTag "rating" $tail ) 

                    # direktes XML-Parsing:
                    #rating[$array]=$(grep --text "<rating>" "$tmp/search.xml" | cut -d">" -f2 | cut -d"<" -f1 | tail -n$tail | head -n1 | /usr/bin/tr -d "\r")
                    #ratingbyauthor[$array]=$(grep --text "<ratingbyauthor>" "$tmp/search.xml" | cut -d">" -f2 | cut -d"<" -f1 | tail -n$tail | head -n1 | /usr/bin/tr -d "\r")

                    tail=$((tail + 1))
                    cutlist_anzahl=$((cutlist_anzahl - 1))
                    array=$(( array + 1))
                    array1=array
                done

                # Sortieren / größten Wert ermitteln:
                IFS=$'\n'   # Internal Field Separator: Felder nur noch durch Zeilenumbrüche (nicht zusätzlich durch Leerzeichen) trennen.
                    maxuserrating=$(echo "${rating[*]}" | sort -nr | head -n1)
                    maxautorrating=$(echo "${ratingbyauthor[*]}" | sort -nr | head -n1)
                IFS=$OLDIFS

                echo "Max-Userrating:           ${maxuserrating}"
                echo "Max-Autorrating:          ${maxautorrating}"

                if [[ "$maxuserrating" == "0" ]] || [[ "$maxuserrating" == "0.00" ]] || [[ -z "$maxuserrating" ]]; then
                    echo "Auswahl aufgrund:         Autorbewertung"
                    maxrating=$maxautorrating
                    ratingsource=fromautor
                    cutlist_nummer=$(grep --text "<ratingbyauthor>" "$tmp/search.xml" | grep -n "<ratingbyauthor>${maxautorrating}" | cut -d: -f1 | head -n1 )
                    #echo "    cutlist-nummer: $cutlist_nummer"
                else
                    echo "Auswahl aufgrund:         Benutzerbewertung"
                    maxrating=$maxuserrating
                    ratingsource=fromuser
                    cutlist_nummer=$( grep --text "<rating>" "$tmp/search.xml" | grep -n "<rating>${maxuserrating}" | cut -d: -f1 | head -n1 )
                    #echo "    cutlist-nummer: $cutlist_nummer"
                fi

                #id=$(grep --text "<id>" "$tmp/search.xml" | head -n$cutlist_nummer | tail -n1 | cut -d">" -f2 | cut -d"<" -f1)     # ID der best bewertetsten Cutlist
                id=$(parseXmlTag "id" $cutlist_nummer)
                #downloadcount=$(grep --text "<downloadcount>" "$tmp/search.xml" | head -n$cutlist_nummer | tail -n1 | cut -d">" -f2 | cut -d"<" -f1)  
                downloadcount=$(parseXmlTag "downloadcount" $cutlist_nummer)
                #autor=$(grep --text "<author>" "$tmp/search.xml" | head -n$cutlist_nummer | tail -n1 | cut -d">" -f2 | cut -d"<" -f1) 
                autor=$(parseXmlTag "author" $cutlist_nummer)
                #CUTLIST=$(grep --text "<name>" "$tmp/search.xml" | head -n$cutlist_nummer | tail -n1 | cut -d">" -f2 | cut -d"<" -f1)
                CUTLIST=$(parseXmlTag "name" $cutlist_nummer)
                #	CUTLIST=$(grep --text "<name>" "$tmp/search.xml" | cut -d">" -f2 | cut -d"<" -f1 | head -n$cutlist_nummer | tail -n1 | /usr/bin/tr -d "\r") # Name der Cutlist
                #usercomment=$(grep --text "<usercomment>" "$tmp/search.xml" | head -n$cutlist_nummer | tail -n1 | cut -d">" -f2 | cut -d"<" -f1)
                usercomment=$(parseXmlTag "usercomment" $cutlist_nummer)
                SuggestedMovieName=$(parseXmlTag "filename" $cutlist_nummer)
                
                if  [ "$useonlytimecuts" == "1" ]; then
                   if [ ! $(parseXmlTag "withtime" $cutlist_nummer) == "1" ]; then
                       # ToDo:
                       # werden in der best bewertetsten Cutlist keine Zeit-Cuts gefunden, wird derzeit nicht in der nächst best bewertetsten gesucht
                       # durch eine zusätzliche Umrechnung der Cuts von Frame auf Zeit könnten noch mehr alternative Cutlists gefunden werden
                       echo "Die alternative Cutlist basiert auf Frameangaben und kann daher nicht ohne Umrechnung verwendet werden."
                       continue=1
                   fi
                fi

                if [ -z "$autor" ]; then
                    autorinfo=""
                else
                    autorinfo=" / Autor: ${autor}"
                fi

                # Benachrichtigung / LOG-Info erstellen:	    
                if [ "$ratingsource" = "fromuser" ]; then
                    ratingcount=$(grep --text "<ratingcount>" "$tmp/search.xml" | head -n$cutlist_nummer | tail -n1 | cut -d">" -f2 | cut -d"<" -f1)
                    cutlistinfo="Bewertungdetails:         ${ratingcount}x bewertet / ${downloadcount}x geladen${autorinfo}"
                else
                    cutlistinfo="Bewertungdetails:         ${downloadcount}x geladen${autorinfo}"
                fi
            fi
        fi

        if [ "$toprated" == "yes" ] && [ "$continue" == "0" ]; then
            echo "Autor-Kommentar:          $usercomment"
            echo "SuggestedMovieName:       $SuggestedMovieName"
            echo "$cutlistinfo"
            echo -e
            if [ "$LOGlevel" = "1" ] || [ "$LOGlevel" = "2" ] ; then
                cp "$tmp/search.xml" "${DECODIR}/_LOGsynOTR/search_${filename}.xml"
            fi
        fi

        if [ "$continue" == "0" ]; then
            if [ $(echo -n "$cutlistat_ID" | wc -c) -ne 64 ] || [ "$useonlytimecuts" == "1" ] ; then # auch alternative Cutlisten ohne Userangaben laden, da eine Bewertung schlecht objektiv möglich ist
                server_tmp="${server}"
                if [ $(echo -n "$cutlistat_ID" | wc -c) -ne 64 ]; then
                    echo "ACHTUNG: deine Cutlist-ID ($cutlistat_ID) ist ungültig!"
                fi
            else
                server_tmp="${server}${cutlistat_ID}/"
            fi

            echo -n "Lade $CUTLIST (ID: $id) --> "

            wget --timeout=30 --tries=2 $wgetloglevel -O "$tmp/$CUTLIST" "${server_tmp}getfile.php?id=$id"

            if [ $? -eq 0 ] && AC_test_cutlist && [ -f "$tmp/$CUTLIST" ]; then
                echo -e "okay"
                continue=0
                if [ "$LOGlevel" = "1" ] || [ "$LOGlevel" = "2" ] ; then
                    cp "$tmp/$CUTLIST" "${DECODIR}/_LOGsynOTR/${CUTLIST}"
                fi

                #	------------------ ID der verwendeten Cutlist speichern:
                sSQL="SELECT rowid FROM raw WHERE file_original LIKE '${filename}%' ORDER BY rowid DESC LIMIT 1" 
                sqlerg=$(sqlite3 -separator $'\t' ${APPDIR}/app/etc/synOTR.sqlite "$sSQL")
                rowid=$(echo "$sqlerg" | awk -F'\t' '{print $1}' )
                sSQL="UPDATE raw SET cutlist_ID='$id' WHERE rowid='$rowid'"
                sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "$sSQL"
            else
                echo -e "false"
                continue=1
            fi
        fi

        }

        AC_get_CutlistFormat ()
        {
        #Hier wird überprüft um welches Cutlist-Format es sich handelt (Zeit / Frames)
        # ---------------------------------------------------------------------
        echo -n "Format der Cuts:          "
        if cat "$tmp/$CUTLIST" | grep "Start=" >> /dev/null; then
            echo -e "Zeit"
            format=zeit
            elif cat "$tmp/$CUTLIST" | grep "StartFrame=" >> /dev/null; then
                echo -e "Frames"
                format=frames
            else
                echo -e "false"
                echo -e "Wahrscheinlich wurde das Limit von '$server' überschritten!"
                continue=1
        fi
        }

        AC_cutlist_error ()
        {
        #Hier wir die Cutlist überprüft, auf z.B. EPGErrors, MissingEnding, MissingVideo, ...
        # ---------------------------------------------------------------------
        _ac_err_ifs=$IFS
        IFS=$OLDIFS
        # Diese Variable beinhaltet alle möglichen Fehler
        errors="EPGError MissingBeginning MissingEnding MissingVideo MissingAudio OtherError"
        for e in $errors; do
            error_check=$(cat "$tmp/$CUTLIST" | grep -m1 $e | cut -d"=" -f2 | /usr/bin/tr -d "\r")
            if [ "$error_check" == "1" ]; then
                echo -e ; echo -e "! ! ! [CUTLIST-INFO] Es wurde ein Fehler gefunden: \"$e\""
                error_yes=$e
                if [ "$error_yes" == "OtherError" ]; then
                    othererror=$(cat "$tmp/$CUTLIST" | grep "OtherErrorDescription")
                    othererror=${othererror##*=}
                    echo -e "Grund für \"OtherError\": \"$othererror\""
                fi
                if [ "$error_yes" == "EPGError" ]; then
                    epgerror=$(cat "$tmp/$CUTLIST" | grep "ActualContent")
                    epgerror=${epgerror##*=}
                    echo -e "ActualContent: $epgerror"
                fi
                error_found=1
                cutlistWithError="${cutlistWithError} $id"
            fi
        done
        IFS="$_ac_err_ifs"
        }

        AC_get_fps ()
        {
        # Hier wird geprüft, welche Bildrate der Film hat.
        # ---------------------------------------------------------------------
        echo -n "Framerate des Films:      "
        fps=""

        rframerate_1=$(echo "$AC_ffprobeInfo" | jq '.streams[0].r_frame_rate' | sed "s/\"//g" | awk -F '/' '{print $1}')
        rframerate_2=$(echo "$AC_ffprobeInfo" | jq '.streams[0].r_frame_rate' | sed "s/\"//g" | awk -F '/' '{print $2}')
        fps=$(gawk -v a="$rframerate_1" -v b="$rframerate_2" 'BEGIN { print a/b }')

        if [ "$fps" == "" ]; then	#Wenn fps nicht per ffprobe gelesen werden konnte
            fps=$(cat "$tmp/$CUTLIST" | grep "FramesPerSecond=" | sed "s/FramesPerSecond\=//g" | /usr/bin/tr -d "\r" ) #| awk -F. '{print $1}'
            echo "${fps}fps [Quelle: Cutlist]"
        else
            echo "${fps}fps [Quelle: ffprobe]"
        fi
        }

        AC_cutlist_seriencheck ()
        {
        # Hier wird geprüft, ob in der Cutlist Serieninfos zu finden sind und schreibt diese ggf. in die DB
        # -------------------------------------------------------------------------------------------------
        parseRegex () 
            {
            # NICHT MEHR BENUTZT ! ! !

            # In dieser Funktion wird der mit einem regulären Ausdruck beschriebene Teilstring zurückgegeben
            # Aufruf: parseRegex "string" "regex"
            # https://stackoverflow.com/questions/5536018/how-to-print-matched-regex-pattern-using-awk
            # --------------------------------------------------------------
            echo "$1" | awk '{
                for(i=1; i<=NF; i++) {
                    tmp=match($i, /'"${2}"'/)
                    if(tmp) {
                            print $i
                        }
                    }
                }'
            }    

# ToDo: entweder auf Titel beschränken, oder RegEx nicht auf Ende ($) beschränken! > gesamte Prüfung auskommentiert / vorhandene Daten werden eh priorisiert
#   if ! echo "$filename" | grep -q "S[0-9][0-9]E[0-9][0-9]$" ; then # nur weiter, wenn im Dateinamen keine Infos gefunden wurden
        SuggestedMovieName=""
        usercomment=""
        CL_serieninfofound=0
        SuggestedMovieName=$(cat "$tmp/$CUTLIST" | grep "SuggestedMovieName=" | sed "s/SuggestedMovieName\=//g;s/[0-9]\{2,4\}[.][0-9]\{1,2\}[.][0-9]\{1,2\}[ _][0-9]\{2\}[\-][0-9]\{2\}/Datum_Zeit/g;s/[0-9]\{2,4\}[.][0-9]\{1,2\}[.][0-9]\{1,2\}/Datum/g;s/_/ /g" | /usr/bin/tr -d "\r" ) #| awk -F. '{print $1}' # Datum, Zeit im OTR-Format und Unterstriche werden entfernt
        usercomment=$(cat "$tmp/$CUTLIST" | grep "UserComment=" | sed "s/UserComment\=//g;s/[0-9]\{2,4\}[.][0-9]\{1,2\}[.][0-9]\{1,2\}[ _][0-9]\{2\}[\-][0-9]\{2\}/Datum_Zeit/g;s/[0-9]\{2,4\}[.][0-9]\{1,2\}[.][0-9]\{1,2\}/Datum/g;s/_/ /g" | /usr/bin/tr -d "\r" ) #| awk -F. '{print $1}'

        if echo "$SuggestedMovieName" | grep -q "[sST]\?[0-9]\{1,2\}[.\-xX]\?[eE]\?[0-9]\{1,2\}" ; then  # [[:space:]]  # S01E01 / S01.E01 / 01-01 / 01x01 / teilweise ohne führende Null
            #CL_serieninfo=$(parseRegex "$SuggestedMovieName" ".[sST]?[0-9]{1,2}[.\-xX]?[eE]?[0-9]{1,2}" | head -n1)    # head -n1: nur der erste Fund im String wird verwendet
            CL_serieninfo=$(echo "$SuggestedMovieName" | grep -E -o "[sST]?[0-9]{1,2}[.\-xX]?[eE]?[0-9]{1,2}" | head -n1)
            CL_serieninfo_season=$(echo "$CL_serieninfo" | awk '{print toupper($0) }' | sed "s/S/ /g;s/T/ /g;s/E/ /g;s/X/ /g;s/-/ /g;s/\./ /g;s/  / /g" | awk '{print $1}')
            CL_serieninfo_episode=$(echo "$CL_serieninfo" | awk '{print toupper($0) }' | sed "s/S/ /g;s/T/ /g;s/E/ /g;s/X/ /g;s/-/ /g;s/\./ /g;s/  / /g" | awk '{print $2}')
            CL_serieninfofound=1
        elif echo "$usercomment" | grep -q "[sST]\?[0-9]\{1,2\}[.\-xX]\?[eE]\?[0-9]\{1,2\}" ; then 
            #CL_serieninfo=$(parseRegex "$usercomment" "[sST]?[0-9]{1,2}[.\-xX]?[eE]?[0-9]{1,2}" | head -n1)
            CL_serieninfo=$(echo "$usercomment" | grep -E -o "[sST]?[0-9]{1,2}[.\-xX]?[eE]?[0-9]{1,2}" | head -n1)
            CL_serieninfo_season=$(echo "$CL_serieninfo" | awk '{print toupper($0) }' | sed "s/S/ /g;s/T/ /g;s/E/ /g;s/X/ /g;s/-/ /g;s/\./ /g;s/  / /g" | awk '{print $1}')
            CL_serieninfo_episode=$(echo "$CL_serieninfo" | awk '{print toupper($0) }' | sed "s/S/ /g;s/T/ /g;s/E/ /g;s/X/ /g;s/-/ /g;s/\./ /g;s/  / /g" | awk '{print $2}')
            CL_serieninfofound=1
        fi

        if [[ "$CL_serieninfofound" = 1 ]] && [[ "$CL_serieninfo_season" =~ $regInt ]] && [[ "$CL_serieninfo_episode" =~ $regInt ]]; then
            echo "Serieninfo aus Cutlist:   S${CL_serieninfo_season}E${CL_serieninfo_episode}"
            #	------------------ schreibe Serieninformation in DB:
            sSQL="UPDATE raw SET miss_series='0', serie_season='$CL_serieninfo_season', serie_episode='$CL_serieninfo_episode'  WHERE file_original='$filename'"
            if [ "$LOGlevel" = "2" ] ; then
                echo "sSQL Serieninfo:          $sSQL"
            fi
            sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "$sSQL"
        fi
#   fi

        }

        AC_time1 ()
        {
        #Hier wird nun die Zeit ins richtige Format für avisplit umgerechnet
        # ---------------------------------------------------------------------
        time=""
        cut_anzahl=$(cat "$tmp/$CUTLIST" | grep "NoOfCuts" | cut -d"=" -f2 | /usr/bin/tr -d "\r")
        echo -e
        echo "---- Cuts ----"
        if [ "$format" == "zeit" ]; then	#Wenn das verwendete Format "Zeit" ist
            head1=1
            echo "Es müssen $cut_anzahl Cuts umgerechnet werden."
            while [ "$cut_anzahl" -gt "0" ]; do
                #Die Sekunde in der der Cut beginnen soll
                time_seconds_start=$(cat "$tmp/$CUTLIST" | grep "Start=" | cut -d"=" -f2 | head -n$head1 | tail -n1 | cut -d"." -f1 | /usr/bin/tr -d "\r")
                echo "Startcut: $time_seconds_start. Sekunde"
                time=${time}$(date -u -d @$time_seconds_start +%T-)	#Die Sekunden umgerechned in das Format hh:mm:ss
                #Wie viele Sekunden der Cut dauert
                time_seconds_ende=$(cat "$tmp/$CUTLIST" | grep "Duration=" | cut -d"=" -f2 | head -n$head1 | tail -n1 | cut -d"." -f1 | /usr/bin/tr -d "\r")
                time_seconds_ende=$(( time_seconds_ende + time_seconds_start )) #Die Sekunde in der der Cut endet
                echo "Endcut: $time_seconds_ende. Sekunde"
                time=${time}$(date -u -d @$time_seconds_ende +%T,)	#Die Endsekunde im Format hh:mm:ss
                head1=$(( head1 + 1 ))
                cut_anzahl=$(( cut_anzahl - 1 ))
                #In der Variable $time sind alle Cuts wie folgt aufgelistet:
                #hh:mm:ss-hh:mm:ss,hh:mm:ss-hh:mm:ss,...
                #$time: 00:00:59-00:26:25,00:34:12-00:51:34,00:59:42-01:05:12,
            done
        elif [ "$format" == "frames" ]; then	#Wenn das verwendete Format "Frames" ist
            head1=1
            echo "Es müssen $cut_anzahl Cuts umgerechnet werden."
            while [ "$cut_anzahl" -gt 0 ]; do
                #Der Frame bei dem der Cut beginnt
                startframe=$(cat "$tmp/$CUTLIST" | grep "StartFrame=" | cut -d= -f2 | head -n$head1 | tail -n1 | /usr/bin/tr -d "\r")
                echo "Startframe= $startframe"
                time="${time}$startframe-"
                #Wie viele Frames dauert der Cut
                stopframe=$(cat "$tmp/$CUTLIST" | grep "DurationFrames=" | cut -d= -f2 | head -n$head1 | tail -n1 | /usr/bin/tr -d "\r")
                stopframe=$(( stopframe + startframe ))	# Der Frame bei dem der Cut endet
                echo "Endframe= $stopframe"
                time="${time}$stopframe,"	#Auflistung alles Cuts
                head1=$(( head1 + 1 ))
                cut_anzahl=$(( cut_anzahl - 1 ))
            done
        fi

        echo "---- ENDE ----" ; echo -e
        sleep 1
        }

        AC_time2 ()
        {
        # Hier wird nun die Zeit ins richtige Format für avisplit umgerechnet, 
        # falls die date-Variante nicht funktioniert (fällt bald weg …)
        # ---------------------------------------------------------------------
        time=""
        cut_anzahl=$(cat "$tmp/$CUTLIST" | grep "NoOfCuts" | cut -d= -f2 | /usr/bin/tr -d "\r")
        echo -e
        echo "---- Cuts ----"
        if [ "$format" == "zeit" ]; then
            head1=1
            echo "Es müssen $cut_anzahl Cuts umgerechnet werden"
            while [ "$cut_anzahl" -gt 0 ]; do
                #Die Sekunde in der der Cut startet
                time_seconds_start=$(cat "$tmp/$CUTLIST" | grep "Start=" | cut -d= -f2 | head -n$head1 | tail -n1 | cut -d"." -f1 | /usr/bin/tr -d "\r")
                ss=$time_seconds_start          # Setze die Skunden auf $time_seconds_start
                mm=0                            # Setze die Minuten auf 0
                hh=0                            # Setze die Stunden auf 0
                while [ "$ss" -ge "60" ]; do      # Wenn die Sekunden >= 60 sind
                    mm=$(( mm +  1))            # Zaehle Minuten um 1 hoch
                    ss=$(( ss - 60))            # Zaehle Sekunden um 60 runter
                    while [ "$mm" -ge "60" ]; do  # Wenn die Minuten >= 60 sind
                        hh=$(( hh +  1 ))       # Zaehle Stunden um 1 hoch
                        mm=$(( mm - 60 ))       # Zaehle Minuten um 60 runter
                    done
                done
                time2_start=$hh:$mm:$ss         # Bringe die Zeit ins richtige Format
                echo "Startcut=	$time2_start"
                time="${time}${time2_start}-"   # Auflistung aller Zeiten
                #Sekunden wie lange der Cut dauert
                time_seconds_ende=$(cat "$tmp/$CUTLIST" | grep "Duration=" | cut -d= -f2 | head -n$head1 | tail -n1 | cut -d"." -f1 | /usr/bin/tr -d "\r")
                time_seconds_ende=$time_seconds_ende+$time_seconds_start	#Die Sekunde in der der Cut endet
                ss=$time_seconds_ende           # Setze die Sekunden auf $time_seconds_ende
                mm=0                            # Setze die Minuten auf 0
                hh=0                            # Setze die Stunden auf 0
                while [ "$ss" -ge "60" ]; do      # Wenn die Sekunden >= 60 sind
                    mm=$(( mm +  1 ))           # Zaehle Minuten um 1 hoch
                    ss=$(( ss - 60 ))           # Zaehle Sekunden um 60 runter
                    while [ "$mm" -ge "60" ]; do  # Wenn die Minuten >= 60 sind
                        hh=$(( hh +  1 ))       # Zaehle Stunden um 1 hoch
                        mm=$(( mm - 60 ))       # Zaehle Minuten um 60 runter
                    done
                done
                time2_ende=$hh:$mm:$ss          # Bringe die Zeit ins richtige Format
                echo "Endcut=		$time2_ende"
                time="${time}${time2_ende},"    # Auflistung alles Zeiten
                head1=$(( head1 + 1 ))
                cut_anzahl=$(( cut_anzahl - 1 ))
            done
        elif [ "$format" == "frames" ]; then
            head1=1
            echo "Es müssen $cut_anzahl Cuts umgerechnet werden"
            while [ "$cut_anzahl" -gt 0 ]; do
                # Der Frame bei dem der Cut beginnt
                startframe=$(cat "$tmp/$CUTLIST" | grep "StartFrame=" | cut -d= -f2 | head -n$head1 | tail -n1 | /usr/bin/tr -d "\r")
                echo "Startframe=	$startframe"
                time="${time}$startframe-"      # Auflistung der Cuts
                # Die Frames wie lange der Cut dauert
                stopframe=$(cat "$tmp/$CUTLIST" | grep "DurationFrames=" | cut -d= -f2 | head -n$head1 | tail -n1 | /usr/bin/tr -d "\r")
                stopframe=$(( stopframe + startframe))  # Der Frame bei dem der Cut endet
                echo "Endframe=	$stopframe"
                time="${time}$stopframe,"       # Auflistung der Cuts
                head1=$(( head1 + 1 ))
                cut_anzahl=$(( cut_anzahl - 1 ))
            done
        fi
        echo "---- ENDE ----" ; echo -e
        sleep 1
        }

        AC_time3 ()
        {
        # Hier wird nun die Zeit ins richtige Format für avcut umgerechnet
        # ---------------------------------------------------------------------
        time="0 "
        keep_times=""
        framediff=$(gawk -v f="${fps}" 'BEGIN { print 1/f }')   # Zeitdifferenz für genau 1 Frame, da avcut mit Zeitwerten arbeitet
        if [ "$LOGlevel" = "2" ] ; then
            echo "Zeitdifferenz für genau 1 Frame für die manuelle Cutlistkorrektur für avcut: $framediff"
            echo "FrameversatzAnfangCut: $FrameversatzAnfangCut"
            echo "FrameversatzEndeCut: $FrameversatzEndeCut"
        fi
        cut_anzahl=$(cat "$tmp/$CUTLIST" | grep "NoOfCuts" | cut -d"=" -f2 | /usr/bin/tr -d "\r")
        echo -e
        echo "---- Cuts ----"
        if [ "$format" == "zeit" ]; then                # Wenn das verwendete Format "Zeit" ist
            head1=1
            echo "Es müssen $cut_anzahl Cuts für avcut umgerechnet werden."
            while [ "$cut_anzahl" -gt "0" ]; do
                # Die Zeit, bei der der Cut beginnt
                time_seconds_start=$(cat "$tmp/$CUTLIST" | grep "Start=" | cut -d"=" -f2 | head -n$head1 | tail -n1 | /usr/bin/tr -d "\r" )
                time_seconds_start=$(gawk -v t="$time_seconds_start" -v f="$FrameversatzAnfangCut" -v d="$framediff" 'BEGIN { print t+(f*d) }')
                echo "Startcut: $time_seconds_start Sekunden"
                time="${time}${time_seconds_start} "
                # Wie viele Sekunden der Cut dauert
                time_seconds_ende=$(cat "$tmp/$CUTLIST" | grep "Duration=" | cut -d"=" -f2 | head -n$head1 | tail -n1 | /usr/bin/tr -d "\r" )
                time_seconds_ende=$(gawk -v e="$time_seconds_ende" -v s="$time_seconds_start" -v f="$FrameversatzEndeCut" -v d="$framediff" 'BEGIN { print e+s+(f*d) }')
                echo "Endcut: $time_seconds_ende Sekunden"
                time="${time}${time_seconds_ende} "
                keep_times="${keep_times}${time_seconds_start} ${time_seconds_ende} "
                head1=$(( head1 + 1 ))
                cut_anzahl=$(( cut_anzahl - 1 ))
            done
        elif [ "$format" == "frames" ]; then            # Wenn das verwendete Format "Frames" ist
            head1=1
            echo "Es müssen $cut_anzahl Cuts für avcut umgerechnet werden."
            while [ "$cut_anzahl" -gt 0 ]; do
                # Der Frame bei dem der Cut beginnt
                startframe=$(cat "$tmp/$CUTLIST" | grep "StartFrame=" | cut -d= -f2 | head -n$head1 | tail -n1 | /usr/bin/tr -d "\r" )
                echo "Startframe= $startframe"
                startframe=$(( $startframe + $FrameversatzAnfangCut ))              # mit manueller Framekorrektur
                time_seconds_start=$(gawk -v f="$startframe" -v p="$fps" 'BEGIN { print f/p }')
                time="${time}${time_seconds_start} "
                # Wie viele Frames dauert der Cut
                stopframe=$(cat "$tmp/$CUTLIST" | grep "DurationFrames=" | cut -d= -f2 | head -n$head1 | tail -n1 | /usr/bin/tr -d "\r" )
                # Der Frame bei dem der Cut endet
                stopframe=$(( stopframe + startframe + $FrameversatzEndeCut ))      # mit manueller Framekorrektur
                echo "Endframe= $stopframe"
                time_seconds_ende=$(gawk -v f="$stopframe" -v p="$fps" 'BEGIN { print f/p }')
                time="${time}${time_seconds_ende} "
                keep_times="${keep_times}${time_seconds_start} ${time_seconds_ende} "
                head1=$(( head1 + 1 ))
                cut_anzahl=$(( cut_anzahl - 1 ))
            done
        fi

        time="${time}- "    # Rest des Films verwerfen
        echo "---- ENDE ----" ; echo -e
        sleep 1
        }

        AC_split ()
        {
        # Hier wird nun das Video an das Cut-Programm übergeben:
        # ---------------------------------------------------------------------
        IFS=$OLDIFS
        _cut_ok=0
        if [ "$synotr_file_source" = "otrkey" ]; then
            if synotr_otrkey_cut; then
                _cut_ok=1
            fi
        elif [ "$synotr_file_source" = "otr2" ]; then
            if synotr_otr2_cut; then
                _cut_ok=1
            fi
        else
            echo "Unbekannte Dateiherkunft – Schnitt übersprungen."
        fi

        if [ "$_cut_ok" = "1" ] && [ -f "$outputfile" ]; then
            filedestname=$(basename "$outputfile")
            echo -n "    L==> "
            echo -e "$filedestname wurde erstellt"
            if [ "$lastjob" -eq 2 ] ; then
                if [ "$dsmtextnotify" = "on" ] ; then
                    synotr_dsmnotify job_successful "$filedestname ist fertig"
                fi
                if [ "$dsmbeepnotify" = "on" ] ; then
                        echo 2 > /dev/ttyS1 #short beep
                fi
                synotr_apprise_notify "Film [$filedestname] ist fertig."
            fi
            synotr_cut_archive_source "$film"
        else
            echo -e "Schnitt fehlgeschlagen."
            continue=1
        fi
        unset _cut_ok
        }

        AC_del_tmp ()
        {
        # Nur den Schnitt-Ordner unter WORKDIR leeren, nie das Arbeitsverzeichnis selbst.
        # ---------------------------------------------------------------------
        _cuttmp="${WORKDIR%/}/tmp_synotr_cut"
        if [ -z "$tmp" ] || [ "$tmp" = "/" ] || [ "$tmp" != "$_cuttmp" ]; then
            echo "Achtung, \$tmp zeigt nicht auf das Schnitt-Temp ($_cuttmp)."
            unset _cuttmp
            return 1
        fi
        if [ -d "$tmp" ]; then
            rm -rf "${tmp:?}"/*
        fi
        unset _cuttmp
        }

        AC_check_software

        # -----------------------------------------------------------------------
        # Es folgt die eigentliche Schleife zum Abarbeiten der Videos:          |
        # -----------------------------------------------------------------------
        SMARTRENDERINGold=$SMARTRENDERING
        for i in $(find "$DECODIR" -maxdepth 1 -name "*.avi" -o -name "*.mp4" -type f)
            do
                IFS=$OLDIFS
                error_found=0           # Fehlertrigger zurücksetzen
                continue=0              # Cut-Skript unterbrechen
                array=0
                cutlistWithError=""     # Cutlists die, einen Fehler haben auf Null setzen
                toprated=yes            # automatisch die Cutlist mit der besten User-Bewertung benutzen?
                format=""               # Um welches Format handelt es sich? AVI, HQ, mp4 - hier auf Null setzen
                UseLocalCutlist=no      # zurücksetzen
                filename=$(basename "$i")
                film="$i"
                vorhanden=no
                useonlytimecuts=""      # aus alternativen Cutlists (für anderes Format) sollen nur Zeit-Cuts verwendet werden
                SMARTRENDERING=$SMARTRENDERINGold
                origfile="$i"
                LOCAL_CUTLIST=""

                echo -e ; echo "    SCHNEIDE:        ---> $filename"
                echo -n "                          "; date; echo -e

                AC_ffprobe
                AC_test
                AC_del_tmp

                if ! synotr_db_lookup_origin "$filename"; then
                    synotr_db_infer_origin_from_name "$filename" || true
                fi
                # Decoder: otrkey → AVI, otr2 → MP4. Ein .avi nie über die otr2-MKV-Pipeline.
                case "$filename" in
                    *.avi|*.AVI)
                        if [ "$synotr_file_source" != "otrkey" ]; then
                            echo "    Hinweis: $filename ist AVI – Pipeline otrkey (DB: ${synotr_file_source:-leer})."
                            synotr_file_source="otrkey"
                        fi
                        ;;
                esac
                if [ -z "$synotr_file_source" ]; then
                    echo "    Keine DB-Herkunft für $filename (mehrdeutiges MP4 ohne file_source)."
                    echo "    Schnitt übersprungen – Datei neu decodieren oder Quelle in der DB prüfen."
                    if [ "$WaitOfCutlist" = "off" ]; then
                        mv "$i" "${WORKDIR}"
                        echo "    L=> Film wird ohne Schneiden weiterverarbeitet"
                    else
                        echo "    L=> Film wird übersprungen"
                    fi
                    continue
                fi
                echo "    Dateiherkunft:         $synotr_file_source${synotr_file_encrypted:+ ($synotr_file_encrypted)}"

                PXheight=$(echo "$AC_ffprobeInfo" | jq -r '[.streams[]? | select(.codec_type=="video") | .height] | .[0] // 0')
                audiocodec=$(echo "$AC_ffprobeInfo" | jq -r '[.streams[]? | select(.codec_type=="audio") | .codec_name] | .[0] // "null"')
                is_hd=0
                if echo "$filename" | grep -q ".HD."; then
                    is_hd=1
                fi
                if echo "$PXheight" | grep -Eq '^[0-9]+$' && [ "$PXheight" -ge 700 ]; then
                    is_hd=1
                fi

                if [ "$synotr_file_source" = "otrkey" ] && { [ "$machinetyp" = "aarch64" ] || echo "$machinetyp" | grep -q "armv8"; }; then
                    echo "    aarch64: .otrkey wird nicht geschnitten, nur nach MP4 (MP4Box)."
                    mv "$i" "${WORKDIR}"
                    continue
                fi

                # Lokale Cutlist: gleiche Sendung, Qualität egal, Error-Flags kein Veto.
                # Reihenfolge: neben dem Film, Downloadordner, dann optional OTRlocalcutlistdir.
                echo -n "Suche nach einer lokalen Cutlist ---> "
                _local_found=0
                _pick_why=""
                for _cldir in "$DECODIR" "$OTRkeydir" "$OTRlocalcutlistdir"; do
                    [ -n "$_cldir" ] && [ -d "$_cldir" ] || continue
                    if synotr_pick_local_cutlist "$_cldir"; then
                        _local_found=1
                        break
                    fi
                done
                if [ "$_local_found" = "1" ]; then
                    echo "okey"
                    echo "(lokale Cutlist wird verwendet, Error-Flags werden ignoriert)"
                    echo "File: $CUTLIST – ${_pick_why}."
                    echo "Es wurde eine passende Cutlist gefunden. Diese wird nun verwendet."
                else
                    echo -e "Keine lokale Cutlist gefunden!"
                fi
                unset _local_found _cldir
                
                # Online nur, wenn lokal nichts Passendes übernommen wurde.
                if [ "$vorhanden" != "yes" ]; then AC_getcutlist ; fi
                if [ "$continue" == "0" ]; then AC_get_CutlistFormat ; fi
                if [ "$continue" == "0" ]; then AC_get_fps ; fi
                if [ "$continue" == "0" ]; then AC_cutlist_seriencheck ; fi
                if [ "$continue" == "0" ] ; then AC_cutlist_error ; fi
                if [ "$error_found" == "1" ] && [ "$UseLocalCutlist" == "no" ] && [ "$toprated" == "yes" ]; then 
                    #break
                    if [ "$WaitOfCutlist" == "off" ]; then
                        echo " > ohne Cutlist / WaitOfCutlist=off: ungeschnitten nach WORKDIR"
                        mv "$i" "${WORKDIR}"
                        echo "    L=> Film wird ohne Schneiden weiterverarbeitet"
                    else
                        echo "    L=> Film wird übersprungen"
                    fi
                    continue
                fi
                if [ "$continue" == "0" ]; then
                    film="$i"
                    filename=$(basename "$i")
                    AC_name
                    if [ "$synotr_file_source" = "otrkey" ]; then
                        if [ "$is_hd" = "1" ]; then
                            SMARTRENDERING="off"
                            echo "    HD-otrkey (Höhe ${PXheight} / Name) – immer avisplit, dann MP4Box."
                        fi
                        if [ "$SMARTRENDERING" = "on" ] && { [ -z "$avcut_otrkey" ] || [ ! -f "$avcut_otrkey" ]; }; then
                            SMARTRENDERING="off"
                            echo "    altes avcut fehlt – Fallback avisplit."
                        fi
                        if [ "$SMARTRENDERING" != "on" ] && { [ "$audiocodec" = "ac3" ] || [ "$audiocodec" = "null" ]; }; then
                            echo "    AC3-Tonspur: avisplit ungeeignet – ungeschnitten nach WORKDIR."
                            mv "$i" "${WORKDIR}"
                            continue
                        fi
                        if [ "$SMARTRENDERING" = "on" ]; then
                            echo " > otrkey: altes avcut auf Original-AVI, dann MP4Box"
                            AC_time3
                        else
                            echo " > otrkey: avisplit/avimerge auf Original-AVI, dann MP4Box"
                            if [ "$date_okay" = "yes" ]; then
                                AC_time1
                            else
                                AC_time2
                            fi
                        fi
                        AC_split
                    else
                        if [ "$SMARTRENDERING" = "on" ] && { [ -z "$avcut_ffmpeg8" ] || [ ! -f "$avcut_ffmpeg8" ]; }; then
                            SMARTRENDERING="off"
                            echo "    avcut 0.8 fehlt – otr2-Keyframe (ffmpeg+mp4mux)."
                        fi
                        if [ "$SMARTRENDERING" = "on" ]; then
                            echo " > otr2: avcut 0.8 (MKV), dann mp4mux"
                        else
                            echo " > otr2: Keyframe-Cut (ffmpeg-Demux, mp4mux)"
                        fi
                        AC_time3
                        AC_split
                    fi
                else
                    if [ "$WaitOfCutlist" == "off" ]; then
                        echo " > ohne Cutlist / WaitOfCutlist=off: ungeschnitten nach WORKDIR"
                        mv "$i" "${WORKDIR}"
                        echo "    L=> Film wird (entsprechend der Einstellung [WaitOfCutlist=\"off\"] ohne Schneiden weiterverarbeitet"
                    fi
                fi
                AC_del_tmp
                continue=0
                
                if [ "$lastjob" -eq 2 ] && [ "$useWORKDIR" == "no" ] ; then
                    if [ "$dsmtextnotify" = "on" ] ; then
                        title=${filename%.*}
                        sleep 1
                        synotr_dsmnotify job_successful "Film [$title] ist fertig"
                        sleep 1
                    fi
                    if [ "$dsmbeepnotify" = "on" ] ; then
                        sleep 1
                        echo 2 > /dev/ttyS1 #short beep
                        sleep 1
                    fi
                    synotr_apprise_notify "Film [$title] ist fertig."
                fi
                SMARTRENDERING=$SMARTRENDERINGold
        done
        if [ -d "${WORKDIR%/}/tmp_synotr_cut" ]; then
            rm -rf "${WORKDIR%/}/tmp_synotr_cut"
        fi
        if [ -d "${WORKDIR%/}/.synotr_cut" ]; then
            rm -rf "${WORKDIR%/}/.synotr_cut"
        fi
elif [ "$OTRcutactiv" = "off" ] ; then
    echo -e ; echo -e ; echo "==> schneiden ist deaktiviert"
else
    echo "==> Variable für Cutaktivität falsch gesetzt ==> Wert >OTRcutactiv< in den Einstellungen überprüfen!"
fi
IFS=$OLDIFS
sleep 1
}


OTRavi2mp4()
{
#########################################################################################
# Rest-AVI → MP4 (Video-Copy, MP3→AAC, MP4Box). otrkey-Schnitt macht das bereits in    #
# OTRautocut. Ungeschnittenes .otr2-MP4 nur bei OTRotr2audio≠both (Tonspur-Filter).     #
#########################################################################################

cd "$WORKDIR"

if [ -d "${WORKDIR%/}/.synotr_remux" ]; then
    echo "Entferne altes Remux-Temp: ${WORKDIR%/}/.synotr_remux"
    rm -rf "${WORKDIR%/}/.synotr_remux"
fi
if [ -d "${WORKDIR%/}/tmp_synotr_remux" ]; then
    echo "Entferne liegengebliebenes Remux-Temp: ${WORKDIR%/}/tmp_synotr_remux"
    rm -rf "${WORKDIR%/}/tmp_synotr_remux"
fi

if type synotr_otr2_filter_uncut >/dev/null 2>&1; then
    synotr_otr2_filter_uncut
fi

filetest=$(find "$WORKDIR" -maxdepth 1 -name "*.avi" -type f)

if [ -n "$filetest" ] && { [ "$OTRcutactiv" = "on" ] || [ "$OTRavi2mp4active" = "on" ]; } ; then
    echo -e ; echo -e; echo "==> in MP4 konvertieren (ffmpeg-Demux, MP4Box):"
    IFS=$'\012'
    for i in $(find "$WORKDIR" -maxdepth 1 -name "*.avi" -type f)
        do
            IFS=$OLDIFS
            echo -e
            title=$(basename "$i")
            echo "    KONVERTIERE:     ---> $title"
            echo -n "                          "; date; echo -e
            if synotr_otrkey_avi2mp4 "$i"; then
                if [ "$lastjob" -eq 3 ] && [ "$useWORKDIR" == "no" ] ; then
                    if [ "$dsmtextnotify" = "on" ] ; then
                        sleep 1
                        synotr_dsmnotify job_successful "Film [${title%.*}] ist fertig"
                        sleep 1
                    fi
                    if [ "$dsmbeepnotify" = "on" ] ; then
                        sleep 1
                        echo 2 > /dev/ttyS1
                        sleep 1
                    fi
                    synotr_apprise_notify "Film [${title%.*}] ist fertig."
                fi
            else
                echo "FEHLER: Konvertierung nach MP4 fehlgeschlagen."
            fi
        done
elif [ -z "$filetest" ] && { [ "$OTRcutactiv" = "on" ] || [ "$OTRavi2mp4active" = "on" ]; } ; then
    mp4test=$(find "$WORKDIR" -maxdepth 1 -name "*.mp4" -type f)
    if [ -n "$mp4test" ] ; then
        echo -e ; echo -e; echo "==> in MP4 konvertieren: übersprungen (bereits MP4, z. B. aus .otr2 oder nach Schnitt)"
    fi
elif [ "$OTRcutactiv" != "on" ] && [ "$OTRavi2mp4active" = "off" ] ; then
    echo -e ; echo -e ; echo "==> in MP4 konvertieren ist deaktiviert"
fi
IFS=$OLDIFS
sleep 1
}

# Qualität (HQ/HD/LQ/SD) aus dem OTR-Dateinamen – nicht Cutlist-format (zeit/frames).
synotr_rename_set_format() {
    format=""
    _qn="$1"
    [ -n "$_qn" ] || return 1
    case "$_qn" in
        *.HQ.mp4|*.HQ.avi|*.HQ.otr2|*HQ-cut.mp4|*HQ-cut.mkv|*.mpg.HQ.*)
            format=HQ
            ;;
        *.HD.mp4|*.HD.avi|*.HD.otr2|*HD-cut.mp4|*HD-cut.mkv|*.mpg.HD.*)
            format=HD
            ;;
        *.LQ.mp4|*.LQ.otr2|*LQ-cut.mp4|*LQ-cut.mkv|*.LQ.mp4-cut.mp4|*.mpg.mp4|*.mpg.mp4-cut.mp4)
            # Altes OTR-MP4 (.mpg.mp4) und otr2-.LQ.mp4 – nicht mit SD-AVI vermengen.
            format=LQ
            ;;
        *.mpg.avi|*-cut.mp4|*-cut.mkv)
            format=SD
            ;;
        *)
            return 1
            ;;
    esac
    return 0
}

# synotr_mp4_write_tags FILE TITLE NETWORK SHOW EPISODE SEASON EPNUM
# iTunes-Atome in MP4 (mutagen in der Decoder-venv). Leere Felder werden übersprungen.
synotr_mp4_write_tags() {
    _tag_file="$1"
    _tag_script="${APPDIR}/includes/mp4_tags.py"
    _tag_py=""
    if [ -x "${APPDIR}/app/venv/bin/python3" ]; then
        _tag_py="${APPDIR}/app/venv/bin/python3"
    else
        _tag_py=$(command -v python3 2>/dev/null || true)
    fi
    if [ -z "$_tag_py" ] || [ ! -f "$_tag_script" ]; then
        echo " übersprungen (Python/mp4_tags.py fehlt)"
        return 1
    fi
    if _tag_log=$("$_tag_py" "$_tag_script" \
        --title "$2" \
        --tv-network "$3" \
        --tv-show "$4" \
        --tv-episode "$5" \
        --tv-season "$6" \
        --tv-episode-num "$7" \
        "$_tag_file" 2>&1)
    then
        if [ "$LOGlevel" = "2" ] && [ -n "$_tag_log" ]; then
            echo "  mp4_tags= $_tag_log"
        fi
        echo -e "   ==> fertig"
        return 0
    fi
    echo " fehlgeschlagen"
    if [ -n "$_tag_log" ]; then
        echo "  $_tag_log"
    fi
    return 1
}

OTRrename()
{
#########################################################################################
# Diese Funktion sammelt techn. Metadaten zu einem Film und benennt die                 #
# Filme nach dem vorgegebenen Muster um                                                 #
#########################################################################################

filetest=$(find "$WORKDIR" -maxdepth 1 \( -name "*TVOON*.avi" -o -name "*TVOON*.mp4" -o -name "*TVOON*.mkv" \) -type f)
if [ -z "$filetest" ]; then
    return
fi

echo -e ; echo -e
echo "==> Umbenennen nach Schema"; echo -e
echo "    [Umbenennungssyntax: $NameSyntax]"
echo "    [Umbenennungssyntax Serientitel: $NameSyntaxSerientitel]:"

IFS=$'\012'
for i in $(find "$WORKDIR" -maxdepth 1 \( -name "*TVOON*.avi" -o -name "*TVOON*.mp4" -o -name "*TVOON*.mkv" \) -type f)
    do
        IFS=$OLDIFS
        missSeries=1
        serietitle=""
        episodetitle=""
        description=""
        season=""
        episode=""
        OTRID=""
        format=""
        filename=$(basename "$i")
        sourcename="$filename"
        echo -e ; 
        echo "    UMBENENNEN:      ---> $filename:" 
        echo -n "                          "; date; echo -e

        fileextension="${filename##*.}"
        # Cut-Datei auf file_original (otr2: .HQ.mp4 / .LQ.mp4; otrkey: .mpg.HQ.avi)
        if ! synotr_db_lookup_origin_cut "$sourcename"; then
            synotr_db_lookup_origin "$filename" || true
        fi
        filename=$(echo $filename | sed 's/LQ-cut/LQ/g ; s/HQ-cut/mpg.HQ/g ; s/HD-cut/mpg.HD/g ; s/mpg.HD.avi-cut/mpg.HD/g ; s/-cut/.mpg/g') # Korrektur für geschnittene Files
        rowid="$synotr_db_rowid"
        originalfilename="$synotr_file_original"
        OTRtitle="$synotr_db_otrtitle"
        serie_seasonDB="$synotr_db_serie_season"
        serie_episodeDB="$synotr_db_serie_episode"

        echo "    [Original:            $originalfilename]"; echo -e 
        echo "Fileextension:            $fileextension"

        #	------------------ technische Filmdaten via ffmpeg und ffprobe auslesen:
        ffprobeInfo=$("$ffprobe" -v quiet -print_format json -show_format -show_streams "$i" 2>&1)

            # Errormeldung vor jason ab DSM 6.2 (wird hier abgeschnitten): ERROR: 
            # ld.so: object 'openhook.so' from LD_PRELOAD cannot be preloaded (cannot open shared object file): ignored. { …
            ffprobeInfo="{ ${ffprobeInfo#*\{}"  

        if [ "$LOGlevel" = "2" ] ; then
            echo "Dateiinformation von ffprobe ausgelesen:"; echo "$ffprobeInfo"; echo -e
        fi

        #	------------------ FORMAT (QUALITÄT), nicht Cutlist zeit/frames:
        synotr_rename_set_format "$originalfilename" \
            || synotr_rename_set_format "$sourcename" \
            || synotr_rename_set_format "$filename" \
            || true
        echo "Format:                   $format"

        #	------------------ Referenzpunkt suchen:
        ersterpunkt=$(echo $filename | awk '{print index($filename, ".")}')
        #	------------------ Titel:
        titleend=$(($ersterpunkt-4))
        titleOTR=$(echo $filename | cut -c -$titleend )
        title=$(echo $titleOTR | sed 's/__+/ - /g' | sed 's/_/ /g' | sed "s/  +//g")
        #	------------------ auf Serieninformation prüfen (Dateiname SxxExx oder Cutlist; Details von theTVDB):
        if echo "$title" | grep -q "S[0-9][0-9]E[0-9][0-9]$" ; then
            serieInfo=${title##* }	# alles, bis zum letzten Leerzeichen
            echo "                          als Serie erkannt (Serieninfo: $serieInfo)"
            serietitle=$(echo $titleOTR | sed 's/_S[0-9][0-9]E[0-9][0-9]$//g')
            season=$(echo $serieInfo | cut -c 2-3 ) #| sed -e 's/^0*//'    # ohne führende Null > nicht nötig
            episode=$(echo $serieInfo | cut -c 5-6 ) #| sed -e 's/^0*//'
            TVDB_query
            if [ "$missSeries" = "0" ] && [ -n "$TVDB_SerieName" ] ; then
                serietitle="$TVDB_SerieName"
            fi
        elif  [[ "$serie_episodeDB" =~ $regInt ]] ; then # Cutlist-Serieninfos (Episode in der DB eine Zahl)
            serieInfo=${title##* }	# alles, bis zum letzten Leerzeichen
            serietitle="$titleOTR"
            season=$(printf '%02d' ${serie_seasonDB})
            episode=$(printf '%02d' ${serie_episodeDB})
            echo "                          als Serie erkannt (aus Cutlist - Serieninfo: ${titleOTR}_S${season}E${episode})"
            TVDB_query
            if [ "$missSeries" = "0" ] && [ -n "$TVDB_SerieName" ] ; then
                serietitle="$TVDB_SerieName"
            fi
        fi

        echo "Staffel-Nr.:              $season"
        echo "Episoden-Nr.:             $episode"
        echo "Episodentitel:            $episodetitle"
        echo "Beschreibung:             $description"

        if [ "$missSeries" = "0" ] ; then
            title="$serietitle"
        else
            title=$(echo "$title" | sed "s/__/ - /g ; s/_/ /g ; s/  / /g ; s/ s /\'s /g ; s/\"//g ; s/://g ; s/\?//g ; s/\*//g" | sed -e "s/\<ue/ü/g ; s/\<ae/ä/g ; s/\<oe/ö/g ; s/\<UE/Ü/g ; s/\<AE/Ä/g ; s/\<OE/Ö/g ; s/\([BCDFGHJKLMNPQRSTVWXYZ]\)\(ae\)/\1ä/g ; s/\([BCDFGHJKLMNPQRSTVWXYZ]\)\(ue\)/\1ü/g ; s/\([BCDFGHJKLMNPQRSTVWXYZ]\)\(oe\)/\1ö/g ; s/\([bcdfghjklmnpqrstvwxyz]\)\(oe\)/\1ö/g ; s/\([bcdfghjklmnpqrstvwxyz]\)\(ue\)/\1ü/g ; s/\([bcdfghjklmnpqrstvwxyz]\)\(ae\)/\1ä/g ; s/\([BCDFGHJKLMNPQRSTVWXYZ]\)\(AE\)/\1Ä/g ; s/\([BCDFGHJKLMNPQRSTVWXYZ]\)\(OE\)/\1Ö/g ; s/\([BCDFGHJKLMNPQRSTVWXYZ]\)\(UE\)/\1Ü/g" | sed -f ${APPDIR}/includes/textersetzung.txt )
            #	Umlauterkennung nur nach einem Konsonanten:
                #	ersetze alle großen UE (> Ü) nach einem großen Konsonaten	s/\([BCDFGHJKLMNPQRSTVWXYZ]\)\(UE\)/\1Ü/g
                #	ersetze alle UE am Anfang der Zeile                         s/^UE/Ü/g
                #   > ersetzt durch: \< (= Anfang jedes Wortes)                 s/\<UE/Ü/g
        fi
        echo "Titel:                    $title"
        #	------------------ Datum im OTR-Namen: YY.MM.DD (zweistellige Jahreszahl zuerst, nicht TT.MM.JJ)
        #	------------------ Jahr:
        YY=$(echo "$filename" | awk -F '.' '{print $1}' | awk -F '_' '{print $NF}')
        echo "YY:                       $YY"
        YYYY="20$YY"
        echo "YYYY:                     $YYYY"
        #	------------------ Monat:
        Mo=$(echo "$filename" | awk -F '.' '{print $2}')
        echo "Monat:                    $Mo"
        #	------------------ Tag:
        DD=$(echo "$filename" | awk -F '.' '{print $3}' | awk -F '_' '{print $1}')
        echo "Tag:                      $DD"
        #	------------------ Stunde:
        HH=$(echo "$filename" | awk -F '.' '{print $3}' | awk -F '_' '{print $2}' | awk -F '-' '{print $1}')
        echo "Stunde:                   $HH"
        #	------------------ Minute:
        Min=$(echo "$filename" | awk -F '.' '{print $3}' | awk -F '_' '{print $2}' | awk -F '-' '{print $2}')
        echo "Minute:                   $Min"
        #	------------------ Dauer:
        duration=$(echo "$filename" | awk -F '.' '{print $3}' | awk -F '_' '{print $4}')
        echo "EPG-Dauer:                $duration"
        realduration=$(echo "$ffprobeInfo" | jq '.streams[0].duration' | sed "s/\"//g" | awk -F '.' '{print $1}' )
        realduration=$(($realduration/60))
        echo "Realdauer:                $realduration"
        #	------------------ Sender:
        Channel=$(echo "$filename" | awk -F '.' '{print $3}' | awk -F '_' '{print $3}' | awk '{ print toupper($0) }') # nicht /usr/bin/tr (verfälscht Zeichen, z. B. vox => vpx)
        echo "Sender:                   $Channel"
        #	------------------ Bildwiederholrate:
        rframerate_1=$(echo "$ffprobeInfo" | jq '.streams[0].r_frame_rate' | sed "s/\"//g" | awk -F '/' '{print $1}')
        rframerate_2=$(echo "$ffprobeInfo" | jq '.streams[0].r_frame_rate' | sed "s/\"//g" | awk -F '/' '{print $2}')
        fps=$(gawk -v a="$rframerate_1" -v b="$rframerate_2" 'BEGIN { print a/b }')
        echo "Framerate:                $fps"
        #	------------------ ScanType:
            # http://www.aktau.be/2013/09/22/detecting-interlaced-video-with-ffmpeg/
        #	scantype=$("$ffmpeg" -filter:v idet -frames:v 10 -an -f rawvideo -y /dev/null -i "$i" 2>&1)
        #	scantype=$(echo "$fileinfo2" | grep "Scan type" | awk -F: '{print $2}' )
            if [ $(echo "$scantype" | grep "Progressive") ] ; then
                scantype="p"
            elif [ $(echo "$scantype" | grep "not interlaced") ] ; then
                scantype="p"
            elif [ $(echo "$scantype" | grep "is interlaced") ] ; then
                scantype="i"
            fi
        scantype=""	# deaktiviert
        # echo "Scantype:         ${scantype}"
        #	------------------ Auflösung:
        height=$(echo "$ffprobeInfo" | jq '.streams[0].height' )
        echo "Auflösung Höhe:           ${height}"
        width=$(echo "$ffprobeInfo" | jq '.streams[0].width' )
        echo "Auflösung Breite:         ${width}"
        #	------------------ Seitenverhältnis:
        aspect_ratio=$(echo "$ffprobeInfo" | jq '.streams[0].display_aspect_ratio' | sed "s/\"//g"  | sed "s/\:/-/g" )
        echo "Seitenverhältnis:         ${aspect_ratio}"
        #	------------------ Audiocodec:
        a_codec=$(echo "$ffprobeInfo" | jq -r '[.streams[]? | select(.codec_type=="audio") | .codec_name] | .[0] // empty')
        echo "Audiocodec:               ${a_codec}"
        _has_ac3=$(echo "$ffprobeInfo" | jq '[.streams[]? | select(.codec_type=="audio") | .codec_name] | map(select(.=="ac3" or .=="eac3" or .=="ec3")) | length')
        #	------------------ Videocodec:
        v_codec=$(echo "$ffprobeInfo" | jq '.streams[0].codec_name' | sed "s/\"//g" )
        echo "Videocodec:               ${v_codec}"
        
        NewName=$NameSyntax     # Muster aus Konfiguration laden

        #	------------------ Neuer Name:
        if [ "$missSeries" = "0" ] ; then
            if [ ! -z "$NameSyntaxSerientitel" ] ; then # nur, wenn Serientitel angepasst / gesetzt wurde
                title="$NameSyntaxSerientitel"
            else
                title="$serietitle.S${season}.E${episode} $episodetitle"
            fi
        fi

        NewName=$(echo $NewName | sed "s/§tit/${title}/g")
        NewName=$(echo $NewName | sed "s/§sertit/${serietitle}/g")
        NewName=$(echo $NewName | sed "s/§epitit/${episodetitle}/g")
        NewName=$(echo $NewName | sed "s/§sta/${season}/g")
        NewName=$(echo $NewName | sed "s/§epi/${episode}/g")
        NewName=$(echo $NewName | sed "s/§dur/${duration}/g")
        NewName=$(echo $NewName | sed "s/§ylong/${YYYY}/g")
        NewName=$(echo $NewName | sed "s/§yshort/${YY}/g")
        NewName=$(echo $NewName | sed "s/§mon/${Mo}/g")
        NewName=$(echo $NewName | sed "s/§day/${DD}/g")
        NewName=$(echo $NewName | sed "s/§hou/${HH}/g")
        NewName=$(echo $NewName | sed "s/§min/${Min}/g")
        NewName=$(echo $NewName | sed "s/§cha/${Channel}/g")
        NewName=$(echo $NewName | sed "s/§qua/${format}/g")
        NewName=$(echo $NewName | sed "s/§fps/${fps}/g")
        NewName=$(echo $NewName | sed "s/§redur/${realduration}/g")
        NewName=$(echo $NewName | sed "s/§scty/${scantype}/g")
        NewName=$(echo $NewName | sed "s/§height/${height}/g")
        NewName=$(echo $NewName | sed "s/§width/${width}/g")
        NewName=$(echo $NewName | sed "s/§asra/${aspect_ratio}/g")
        NewName=$(echo $NewName | sed "s/§acod/${a_codec}/g")
        NewName=$(echo $NewName | sed "s/§vcod/${v_codec}/g")

        if [ "$missSeries" = "0" ] ; then
            title="$serietitle - S${season}E${episode} $episodetitle"	# Titel für DSM-Benachrichtigung generieren
        fi
        if echo "${_has_ac3:-0}" | grep -Eq '^[1-9][0-9]*$'; then
            NewName=$(echo $NewName | sed "s/§ac01/ ac3/g")
        else
            NewName=$(echo $NewName | sed "s/§ac01//g")
        fi
        unset _has_ac3

        NewName="$NewName.$fileextension"
        echo -e; echo "Neuer Dateiname:          $NewName" ; echo -e

        if [ "$OTRrenameactiv" = "on" ] ; then
            echo "==> umbenennen:"
            if [ -f "${WORKDIR}${NewName}" ]; then      # Prüfen, ob Zielname bereits vorhanden ist
                echo "Die Datei $NewName ist bereits vorhanden und $filename wird nicht umbenannt."
                touch -t $YY$Mo$DD$HH$Min "$i"          # Dateidatum auf Ausstrahlungsdatum setzen
            else
                mv -i "$i" "${WORKDIR}${NewName}"

                if [ "$fileextension" = "mp4" ]; then
                    echo -n "    L==> Tags schreiben (mutagen, MP4):"
                    synotr_mp4_write_tags "${WORKDIR}${NewName}" "$title" "$Channel" "$serietitle" "$episodetitle" "$season" "$episode" || true
                fi
                touch -t $YY$Mo$DD$HH$Min "${WORKDIR}${NewName}"
                echo "    L==> umbenannt von"; echo "         $filename"; echo "       zu"; echo "         $NewName"

                echo -e; echo "  ------------------------->"; echo -n "  Datenbank schreiben ==> "
                # Hochkommas für SQL-String maskieren:
                NewNameMask=$( echo "$NewName" | sed "s/'/''/g" )
                titleMask=$(echo "$title" | sed "s/'/''/g")
                serietitleMask=$(echo "$serietitle" | sed "s/'/''/g")
                episodetitleMask=$(echo "$episodetitle" | sed "s/'/''/g")
                descriptionMask=$(echo "$description" | sed "s/'/''/g")

                if [ ! -z "$rowid" ] ; then
                    echo -n "aktualisiere Datensatz $rowid"
                    sSQL="UPDATE raw SET file_rename='$NewNameMask', miss_series='$missSeries', format='$format', titel='$titleMask', datum='$YYYY-$Mo-$DD', zeit='$HH:$Min:00', dauer='$duration', sender='$Channel', otrid='$OTRID', serie_titel='$serietitleMask', serie_season='$season', serie_episode='$episode', serie_episodentitel='$episodetitleMask', serie_episodebeschreibung='$descriptionMask',  lastcheckday=$today, checkcount=0, fps='$fps', realdauer='$realduration', scantype='$scantype', pix_height='$height', pix_width='$width', aspect_ratio='$aspect_ratio', v_codec='$v_codec', a_codec='$a_codec' WHERE rowid=$rowid"
                else
                    echo -n "füge neuen Datensatz ein"
                    sSQL="INSERT INTO raw ( file_original, file_rename, miss_series, format, titel, datum, zeit, dauer, sender, otrid, serie_titel, serie_season, serie_episode, serie_episodentitel, serie_episodebeschreibung, lastcheckday, checkcount, fps, realdauer, scantype, pix_height, pix_width, aspect_ratio, v_codec, a_codec) VALUES  ('$filename', '$NewNameMask', '$missSeries', '$format', '$titleMask', '$YYYY-$Mo-$DD', '$HH:$Min:00', '$duration', '$Channel', '$OTRID', '$serietitleMask', '$season', '$episode', '$episodetitleMask', '$descriptionMask', '$today', '0', '$fps', '$realduration', '$scantype', '$height', '$width', '$aspect_ratio', '$v_codec', '$a_codec')"
                fi

                if [ "$LOGlevel" = "2" ] ; then
                    echo "	sSQL= $sSQL"
                fi
                sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "$sSQL"
                echo "  ==> fertig"; echo "  <-------------------------"

                if [ "$lastjob" -eq 4 ] && [ "$useWORKDIR" == "no" ] ; then
                    if [ "$dsmtextnotify" = "on" ] ; then
                        sleep 1
                        synotr_dsmnotify job_successful "Film [$title] ist fertig"
                        sleep 1
                    fi
                    if [ "$dsmbeepnotify" = "on" ] ; then
                        sleep 1
                        echo 2 > /dev/ttyS1 #short beep
                        sleep 1
                    fi
                    synotr_apprise_notify "Film [$title] ist fertig."
                fi
            fi
        elif [ "$OTRrenameactiv" = "off" ] ; then
            echo -e ; echo -e ; echo "==> umbenennen ist deaktiviert"
        else
            echo "==> Variable für Renameaktivität falsch gesetzt ==> Wert >OTRrenameactiv< in den Einstellungen überprüfen!"
        fi
    done
sleep 1
}


UPDATE()
{
#########################################################################################
# SQLite-DB prüfen/anlegen und lokale Versionsdaten aktualisieren                       #
#########################################################################################

    CREATEDB ()
    {
    #########################################################################################
    # Diese Funktion prüft, ob die SQLite-DB vorhanden ist und erstellt                     #
    # diese gegebenenfalls. Außerdem werden ältere DB-Versionen aktualisiert                #
    #########################################################################################
    IFS=$'\012'
    if [ ! -f "${APPDIR}/app/etc/synOTR.sqlite" ]; then
        echo "    Die synOTR-Datenbank ist nicht vorhanden und wird erstellt."
        # cp "${APPDIR}/app/etc/synOTR.sqlite_template" "${APPDIR}/app/etc/synOTR.sqlite"
        # ==>	DB nativ per SQL erzeugen:
        sqlinst="CREATE TABLE \"raw\" (\"timestamp\" timestamp NOT NULL  DEFAULT (CURRENT_TIMESTAMP) ,\"file_original\" varchar(500) ,\"file_encrypted\" varchar(500) ,\"file_source\" varchar(16) ,\"file_rename\" varchar(500) ,\"miss_series\" tinyint(1) ,\"format\" varchar(5) ,\"titel\" varchar(500) ,\"datum\" date ,\"zeit\" time ,\"dauer\" int(5) ,\"sender\" varchar(100) ,\"otrid\" int(11) ,\"serie_titel\" varchar(500) ,\"serie_season\" int(11) ,\"serie_episode\" int(11) ,\"serie_episodentitel\" varchar(500) ,\"serie_episodebeschreibung\" varchar(10000) ,\"lastcheckday\" int(3) ,\"checkcount\" int(3) DEFAULT (null) ,\"fps\" Numeric(500) ,\"realdauer\" int(5) ,\"scantype\" varchar(2) ,\"pix_height\" int(5) ,\"pix_width\" int(5) ,\"aspect_ratio\" varchar(20) ,\"v_codec\" varchar(100) ,\"a_codec\" varchar(100) ,\"OTRtitle\" varchar(500) ,\"OTRcomment\" varchar(10000) ,\"cutlist_ID\" int(20) ); CREATE INDEX \"IDX_raw_check\" ON \"raw\" (\"lastcheckday\" ASC, \"checkcount\" ASC);"
        sqliteinfo=$(sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "$sqlinst")
        echo "    $sqliteinfo"

        sqlinstNewTable="CREATE TABLE \"checkversion\" (\"timestamp\" timestamp NOT NULL  DEFAULT (CURRENT_TIMESTAMP) ,\"VERSIONcurrent\" varchar(500) ,\"VERSIONserver\" varchar(500) ,\"lastcheckday\" int(3) ); " # CREATE INDEX \"IDX_raw_check\" ON \"raw\" (\"lastcheckday\" ASC, \"checkcount\" ASC);"
        sqliteinfo=$(sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "$sqlinstNewTable")
        echo "    $sqliteinfo"

        sqlinstNewTable="CREATE TABLE \"tvdb\" (\"timestamp\" timestamp NOT NULL  DEFAULT (CURRENT_TIMESTAMP) ,\"APIKEY\" varchar(500) ,\"TOKEN\" varchar(2000) ,\"day_created\" int(3) ); "
        sqliteinfo=$(sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "$sqlinstNewTable")
        echo "    $sqliteinfo"
        if [ -f "${APPDIR}/app/etc/synOTR.sqlite" ]; then
            echo "    L==> DB erfolgreich erstellt [${APPDIR}/app/etc/synOTR.sqlite]"; echo -e
        else
            echo "    L==> fehlgeschlagen … !"; echo -e
        fi
    fi

    # Tabelle "checkversion" erstellen:
    sqlinstNewTable="CREATE TABLE IF NOT EXISTS \"checkversion\" (\"timestamp\" timestamp NOT NULL  DEFAULT (datetime('now','localtime')) ,\"VERSIONcurrent\" varchar(500) ,\"VERSIONserver\" varchar(500) ,\"lastcheckday\" int(3) ); " # CREATE INDEX \"IDX_raw_check\" ON \"raw\" (\"lastcheckday\" ASC, \"checkcount\" ASC);"
    sqliteinfo=$(sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "$sqlinstNewTable")
    echo "    $sqliteinfo"

    sqlerg=$(sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "SELECT rowid FROM checkversion WHERE rowid=1")
    if [ "$sqlerg" == "" ] ; then # prüfen, ob der Updatedatensatz vorhanden ist, ggfls. einfügen
        sSQL="INSERT INTO checkversion ( VERSIONcurrent, timestamp, lastcheckday) VALUES  ( '$CLIENTVERSION', datetime('now','localtime'), $(($today-1)) )"
        sqliteinfo=$(sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "$sSQL")
        echo "    > Updatedatensatz eingefügt ($sqliteinfo)"
    fi

    sqlinstNewTable="CREATE TABLE IF NOT EXISTS \"tvdb\" (\"timestamp\" timestamp NOT NULL  DEFAULT (CURRENT_TIMESTAMP) ,\"APIKEY\" varchar(500) ,\"TOKEN\" varchar(2000) ,\"day_created\" int(3) ); "
    sqliteinfo=$(sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "$sqlinstNewTable")
    echo "    $sqliteinfo"

    sqlerg=$(sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "SELECT rowid FROM tvdb WHERE rowid=1")
    if [ "$sqlerg" == "" ] ; then
        _tvdb_esc=$(synotr_sql_escape "${TVDB_APIKEY:-}")
        sSQL="INSERT INTO tvdb ( APIKEY, timestamp, day_created) VALUES  ( '${_tvdb_esc}', datetime('now','localtime'), $(($today-1)) )"
        sqliteinfo=$(sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "$sSQL")
        unset _tvdb_esc
    else
        synotr_tvdb_purge_bundled_default
        # User-Key aus den Einstellungen in die DB übernehmen – leere Config überschreibt keinen DB-User-Key.
        if [ -n "$TVDB_APIKEY" ]; then
            _tvdb_stored=$(sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "SELECT COALESCE(APIKEY,'') FROM tvdb WHERE rowid=1")
            if [ "$_tvdb_stored" != "$TVDB_APIKEY" ]; then
                _tvdb_esc=$(synotr_sql_escape "$TVDB_APIKEY")
                sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "UPDATE tvdb SET APIKEY='${_tvdb_esc}', TOKEN='', day_created=$((today-1)), timestamp=(datetime('now','localtime')) WHERE rowid=1"
                unset _tvdb_esc
            fi
            unset _tvdb_stored
        fi
    fi

    # Prüfen (und ggf. einfügen) der Spalten OTRtitle und OTRcomment:
    sqlerg=$(sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "SELECT * FROM sqlite_master WHERE TYPE='table' AND tbl_name = 'raw' AND SQL LIKE '%OTRtitle%' ") 
    
    if [ "$sqlerg" == "" ] ; then 
        echo "    > Spalten (OTRtitle, OTRcomment) werden hinzugefügt"
        sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "ALTER TABLE raw ADD COLUMN \"OTRtitle\" VARCHAR "
        sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "ALTER TABLE raw ADD COLUMN \"OTRcomment\" VARCHAR "
    fi
    
    # Prüfen (und ggf. einfügen) der Spalte cutlist_ID:
    sqlerg=$(sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "SELECT * FROM sqlite_master WHERE TYPE='table' AND tbl_name = 'raw' AND SQL LIKE '%cutlist_ID%' ") 
    
    if [ "$sqlerg" == "" ] ; then 
        echo "    > Spalte (cutlist_ID) wird hinzugefügt"
        sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "ALTER TABLE raw ADD COLUMN \"cutlist_ID\" VARCHAR "
    fi

    sqlerg=$(sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "SELECT * FROM sqlite_master WHERE TYPE='table' AND tbl_name = 'raw' AND SQL LIKE '%file_source%' ")
    if [ "$sqlerg" == "" ] ; then
        echo "    > Spalte (file_source) wird hinzugefügt"
        sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "ALTER TABLE raw ADD COLUMN \"file_source\" VARCHAR "
    fi
    sqlerg=$(sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "SELECT * FROM sqlite_master WHERE TYPE='table' AND tbl_name = 'raw' AND SQL LIKE '%file_encrypted%' ")
    if [ "$sqlerg" == "" ] ; then
        echo "    > Spalte (file_encrypted) wird hinzugefügt"
        sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "ALTER TABLE raw ADD COLUMN \"file_encrypted\" VARCHAR "
    fi

    IFS=$OLDIFS
    sleep 1
    }

CREATEDB

# Versionsdaten lokal in der DB halten (kein Online-Check).
# ---------------------------------------------------------------------
sSQL="SELECT rowid,VERSIONcurrent,VERSIONserver,lastcheckday FROM checkversion WHERE rowid=1 "
sqlerg=$(sqlite3 -separator $'\t' ${APPDIR}/app/etc/synOTR.sqlite "$sSQL")

lastcheckday=$(echo "$sqlerg" | awk -F'\t' '{print $4}' )

if [ "$lastcheckday" -ne $today ] || [ "$lastcheckday" == "" ] ; then
    sSQLupdate="UPDATE checkversion SET VERSIONcurrent='$CLIENTVERSION', VERSIONserver='SPK', lastcheckday=$today, timestamp=(datetime('now','localtime')) WHERE rowid=1"
    sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "$sSQLupdate"
fi

sleep 1
}


# synotr_prepare_target_path DESTDIR FILENAME
# Wie synOCR prepare_target_path: nächsten freien Namen im Zielordner bestimmen
# (Stamm, Stamm (1), Stamm (2), …). Setzt synotr_target_filename und
# synotr_target_count (leer, wenn der Originalname frei ist).
synotr_prepare_target_path()
{
    _dest="${1%/}"
    _name="$2"
    synotr_target_filename="$_name"
    synotr_target_count=""

    [ -n "$_dest" ] && [ -n "$_name" ] || return 1

    if [ ! -f "${_dest}/${_name}" ]; then
        unset _dest _name
        return 0
    fi

    case "$_name" in
        *.*)
            _ext="${_name##*.}"
            _base="${_name%.*}"
            ;;
        *)
            _ext=""
            _base="$_name"
            ;;
    esac

    # vorhandenen Zähler " (N)" am Stamm abstreifen, damit nicht (1) (2) entsteht
    _stripped=$(printf '%s' "$_base" | sed 's/ ([0-9][0-9]*)$//')
    _base="$_stripped"

    _n=1
    while [ "$_n" -le 9999 ]; do
        if [ -n "$_ext" ]; then
            _cand="${_base} (${_n}).${_ext}"
        else
            _cand="${_base} (${_n})"
        fi
        if [ ! -f "${_dest}/${_cand}" ]; then
            synotr_target_filename="$_cand"
            synotr_target_count="$_n"
            unset _dest _name _ext _base _stripped _n _cand
            return 0
        fi
        _n=$((_n + 1))
    done

    synotr_target_filename=""
    synotr_target_count=""
    unset _dest _name _ext _base _stripped _n _cand
    return 1
}


MOVE2DESTDIR()
{
#########################################################################################
# Diese Funktion verschiebt die fertigen Filme in den Zielordner                        #
#########################################################################################

filetest=$(find "${WORKDIR}" -maxdepth 1 -name "*.avi" -o -name "*.mp4" -type f)
if [ "$useWORKDIR" == "yes" ] && [ ! -z "$filetest" ]; then
    echo -e; echo "==> Verschiebe fertige Filme in Zielordner"
    IFS=$'\012'
    for i in $(find "${WORKDIR}" -maxdepth 1 -name "*.avi" -o -name "*.mp4" -type f)
        do
            IFS=$OLDIFS
            filename=$(basename "$i")

            if ! synotr_prepare_target_path "${DESTDIR}" "$filename" || [ -z "$synotr_target_filename" ]; then
                echo "    Film [$filename] kann nicht in Zielordner verschoben werden, da kein freier Dateiname gefunden wurde."
                continue
            fi
            if [ "$filename" != "$synotr_target_filename" ]; then
                echo "    Dateiname wird um einen Zähler ergänzt (${synotr_target_count}), da die Datei bereits im Zielordner existiert."
            fi

            mv "$i" "${DESTDIR}/${synotr_target_filename}"
            echo "    L=> verschiebe ${synotr_target_filename}"

            if [ "$dsmtextnotify" = "on" ] ; then
                sleep 1
                synotr_dsmnotify job_successful "Film [$synotr_target_filename] ist fertig"
                sleep 1
            fi
            if [ "$dsmbeepnotify" = "on" ] ; then
                sleep 1
                echo 2 > /dev/ttyS1 #short beep
                sleep 1
            fi
            synotr_apprise_notify "Film [$synotr_target_filename] ist fertig."
        done
fi

#   DEV:
#        echo "run FileBot:"
#        filebot -script 'fn:amc' /volume1/video/_synOTR/FileBot_input --output '/volume1/video/+NEU' --action move --conflict index --lang de --def 'music=y' 'unsorted=y' 'deleteAfterExtract=y' 'minFileSize=0' 'seriesFormat={n}.S{s.pad(2)+'\''.E'\''}{e.pad(2)} - {t}' 'animeFormat={n} ({y}){ext}' 'movieFormat={n} ({y})' 'musicFormat={n} ({y}){ext}' 'unsortedFormat={fn}.{ext}' --log all --log-file '/volume1/@appstore/filebot-node/data/filebot.log'
}



PURGELOG()
{
#########################################################################################
# Diese Funktion löscht zuerst alle leeren Logs und anschließend die überzähligen       #
#########################################################################################

if [ -z "$LOGmax" ]; then
    return
fi

logdir="${DECODIR%/}/_LOGsynOTR"
if [ ! -d "$logdir" ]; then
    return
fi

IFS=$OLDIFS

# synotr_purge_recycle FILE
synotr_purge_recycle() {
    if [ "$endgueltigloeschen" = "on" ]; then
        rm -f "$1"
    else
        mv "$1" "$OTRkeydeldir"
    fi
}

# synotr_purge_oldest DIR PATTERN  (PATTERN unquoted glob, z. B. synOTR_*.log)
synotr_purge_oldest() {
    _pdir="$1"
    _patt="$2"
    _n=0
    for _f in "$_pdir"/$_patt; do
        [ -f "$_f" ] || continue
        _n=$((_n + 1))
    done
    count2del=$((_n - LOGmax))
    if [ "$count2del" -gt 0 ]; then
        ls -tr "$_pdir"/$_patt 2>/dev/null | head -n "$count2del" | while IFS= read -r _old; do
            [ -f "$_old" ] || continue
            synotr_purge_recycle "$_old"
        done
    fi
    unset _pdir _patt _n _f _old
}

# synotr_log_is_idle FILE
# Fertiger Lauf ohne Datei-Job (Header/UPDATE/Reindex zählen nicht).
synotr_log_is_idle() {
    grep -q "synOTR ENDE" "$1" 2>/dev/null || return 1
    grep -E -q 'DECODIERE:|SCHNEIDE:|KONVERTIERE:|UMBENENNEN:|==> decodieren:|==> schneiden:|==> in MP4 konvertieren \(ffmpeg|==> Umbenennen nach Schema|==> Verschiebe fertige Filme|==> integriere AC3' "$1" && return 1
    return 0
}

# leere synOTR-Logs
for _log in "$logdir"/synOTR_*.log; do
    [ -f "$_log" ] || continue
    if synotr_log_is_idle "$_log"; then
        synotr_purge_recycle "$_log"
    fi
done
unset _log

synotr_purge_oldest "$logdir" "synOTR_*.log"
synotr_purge_oldest "$logdir" "search_*.xml"
synotr_purge_oldest "$logdir" "*.cutlist"

unset -f synotr_purge_recycle synotr_purge_oldest synotr_log_is_idle
}


#        _______________________________________________________________________________
#       |                                                                               |
#       |                           AUFRUF DER FUNKTIONEN                               |
#       |_______________________________________________________________________________|

    echo -e; echo -e
    echo "    ----------------------------------"
    echo "    |    ==> Funktionsaufrufe <==    |"
    echo "    ----------------------------------"

    UPDATE
    OTRdecoder
    OTRautocut
    OTRavi2mp4
    OTRrename
    MOVE2DESTDIR
    PURGELOG

    echo -e; echo -e
    echo "    -----------------------------------"
    echo "    |       ==> synOTR ENDE <==       |"
    echo "    -----------------------------------"
    echo -e; echo "    Gesamtzeit: $(sec_to_time $(( $(date +%s)-${UNIXTIME})))"

exit
