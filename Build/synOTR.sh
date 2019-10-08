#!/bin/sh
# /usr/syno/synoman/webman/3rdparty/synOTR/synOTR.sh

###################################################################################

    echo "    -----------------------------------"
    echo "    |    ==> Installationsinfo <==    |"
    echo "    -----------------------------------"
    echo -e

    CLIENTVERSION=`get_key_value /var/packages/synOTR/INFO version`
    DevChannel="Release"        # beta

# ---------------------------------------------------------------------------------
#           GRUNDKONFIGRUATIONEN / INDIVIDUELLE ANPASSUNGEN / Standardwerte       |
#           (alle Werte können durch setzen in der Konifiguration.txt             |
#           überschrieben werden)                                                 |
# ---------------------------------------------------------------------------------
    SMARTRENDERING="on"         # Smartrendering profilaktisch aktivieren
    OTRlocalcutlistdir=""       # optionaler Ordner für lokale Cutlist => diese Cutlist werden geprüft und müssen daher direkt zum Film passen / bei Nichtnutzung leer lassen
    normalizeAudio="on"         # Audiospur normalisieren (nur in Verbindung mit avi2mp4)
    autoupdate="off"
    forceupdate="off"           # Updateaufruf ohne Prüfung erzwingen
    synotrdomain="geimist.eu"   # notwendig für Update, Konsitenzprüfung, DEV-Report und evtl. in Zukunft zum abfragen der API-Keys
    endgueltigloeschen="off"    # das endgültige Löschen der Quelldateien erst einmal grundsätzlich deaktivieren
    # Frameversatz, um Cuts manuell zu justieren (positive Werte verschieben den Cut nach hinten, negative nach vorn):
    FrameversatzAnfangCut=1     # = verschiebt den Beginn des gewünschten Filmteils beim framegenauen Schneiden
    FrameversatzEndeCut=1       # = verschiebt das Ende des gewünschten Filmteils beim framegenauen Schneiden
    MP4BOX_DELAY=""             # in Millisekunden / Feinabstimmung für den Audio-Video-Sync / Positive Werte verzögern den Ton; negative Werte 'holen den Ton nach vorn' 
    niceness=15                 # Die Priorität liegt im Bereich von -20 bis +19 (in ganzzahligen Schritten), wobei -20 die höchste Priorität (=meiste Rechenleistung) und 19 die niedrigste Priorität (=geringste Rechenleistung) ist. Die Standardpriorität ist 0. AUF NEGATIVE WERTE SOLLTE UNBEDINGT VERZICHTET WERDEN!
    reindex=1                   # Standard 1 - einamlige Reindexierung des Zielordners nach dem ersten Programmlauf des Tages
    needindex=0                 # wird bei einem fertigen Film auf 1 gesetzt um den Zielordnerindex für die VideoStation neu zuindexieren
    DEBUGINFO="on"              # ich bin dankbar, wenn der Wert auf 'on' gestellt bleibt - deaktivieren sofern keine anonyme Systeminfo an den Entwickler gesendet werden darf (Installationstrigger beinhaltet folgende anonymen Geräteinfos: DSM-Build / Prüfsumme der MAC-Adresse als Hardware-ID [anonyme Zahlenfolge um Installationen zu zählen] / Architektur / Geräte-Typ) 
    WaitOfCutlist="on"          # mit dem weiterverarbeiten eines Filmes wird so lange gewartet, bis eine Cutlist verfügbar ist
    useallcutlistformat=0       # Cutlits für alternative Formate berücksichtigen
    timediff=1                  # Abweichung der Dateiänderungszeit in Minuten um laufende FTP-Pushaufträge nicht zu decodieren
    TVDBlang="de"               # Sprache, in welcher nach Serien auf theTVDB.com gesucht werden soll
    TVDB_APIKEY=""              # eigenen API-Key für theTVDB.com verwenden
    today=`date +%d | sed -e 's/^0*//'` # Datum (Tag) ohne führende Null (lässt sich sonst nicht als Berechnungsgrundlage nutzen)
    regInt='^[0-9]+$'           # Vorlage: Regex check Integer

# an welchen User/Gruppe soll die DSM-Benachrichtigung gesendet werden :
# ---------------------------------------------------------------------
    synOTR_user=`whoami`; echo "synOTR-User:              $synOTR_user"
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
    APPDIR=$(cd $(dirname $0);pwd)
    cd ${APPDIR}

# Konfigurationsdatei einbinden:
# ---------------------------------------------------------------------
    CONFIG=app/etc/Konfiguration.txt
    . ./$CONFIG

# Variable "lastjob" für Benachrichtigung setzen:
# ---------------------------------------------------------------------
    if [ $OTRrenameactiv = "on" ] ; then
        lastjob=4
    elif [ $OTRavi2mp4active = "on" ] ; then
        lastjob=3
    elif [ $OTRcutactiv = "on" ] ; then
        lastjob=2
    else
        lastjob=1
    fi

# Aufgabenindex:
# ---------------------------------------------------------------------
    if [ $decoderactiv = "on" ] ; then  idx1=1 ; else  idx1=0 ; fi
    if [ $OTRcutactiv = "on" ] ; then  idx2=1 ; else  idx2=0 ; fi
    if [ $OTRavi2mp4active = "on" ];  then  idx3=1 ; else  idx3=0 ; fi
    if [ $OTRrenameactiv = "on" ];  then  idx4=1 ; else  idx4=0 ; fi
    idx=${idx1}${idx2}${idx3}${idx4}

# Systeminformation / LIBRARY_PATH anpassen / PATH anpassen:
# --------------------------------------------------------------------- 
    echo "synOTR-Version:           $CLIENTVERSION"
    machinetyp=`uname --machine`; echo "Architektur:              $machinetyp"
    dsmbuild=`uname -v | awk '{print $1}' | sed "s/#//g"`; echo "DSM-Build:                $dsmbuild"
    read MAC </sys/class/net/eth0/address
    sysID=`echo $MAC | cksum | awk '{print $1}'`; sysID="$(printf '%010d' $sysID)" #echo "Prüfsumme der MAC-Adresse als Hardware-ID: $sysID" 10-stellig
    device=`uname -a | awk -F_ '{print $NF}' | sed "s/+/plus/g" `; echo "Gerät:                    $device ($sysID)"	    #  | sed "s/ds//g"
    # für HD-Aufnahmen mit avcut mindestens 500 MB free:
    echo -n "                          RAM installiert:    "; RAMmax=`free -m | grep 'Mem:' | awk '{print $2}'`; echo "$RAMmax MB"	    # verbauter RAM
    echo -n "                          RAM verwendet:      "; RAMused=`free -m | grep 'Mem:' | awk '{print $3}'`;	echo "$RAMused MB"  # genutzter RAM
    echo -n "                          RAM verfügbar:      "; RAMfree=$(( $RAMmax - $RAMused )); 	echo "$RAMfree MB"

# synOTR Programmlauf auf die Hardware abstimmen:
# ---------------------------------------------------------------------
    save_ENV ()
    {
        # https://forum.ubuntuusers.de/post/2099580/
        # http://www.linux-praxis.de/lpic1/lpi101/1.102.4.html
        # man kann mit synOTR_ENV und restore_ENV zwischen den beiden ENV-Versionen wechseln
        export SAVED_PATH=$PATH
        export SAVED_LD_LIBRARY_PATH=$LD_LIBRARY_PATH
    }

    restore_ENV ()
    {
    #   echo "Die Standard-Pathvariablen werden geladen …"
        export PATH=$SAVED_PATH
        export LD_LIBRARY_PATH=$SAVED_LD_LIBRARY_PATH
    }
    
    save_ENV    

    if [ $machinetyp = "x86_64" ] && [ $dsmbuild -gt 7134 ]; then   # DSM-Build 7135 = DSM 6.0 BETA 1
        echo "                          System arbeitet mit DSM 6.0 oder höher. Der LD_LIBRARY_PATH wird angepasst."
        synOTR_LD_LIBRARY_PATH=${APPDIR}/app/lib:$LD_LIBRARY_PATH
        synOTR_PATH=$PATH:${APPDIR}/app/bin
        bsy="${APPDIR}/app/bin/busybox"
    #	ffmpeg="${APPDIR}/app/bin/ffmpeg"
        ffmpeg=`which ffmpeg` # mitgeliefertes ffmpeg läuft derzeit nicht korrekt
        avcut="${APPDIR}/app/bin/avcut64"
    elif [ `echo $machinetyp | grep "armv7" ` ] ; then
        synOTR_LD_LIBRARY_PATH=${APPDIR}/app/libARMv7l:$LD_LIBRARY_PATH
        synOTR_PATH=$PATH:${APPDIR}/app/binARMv7l:/opt/bin
        bsy="${APPDIR}/app/binARMv7l/busybox"
        ffmpeg="${APPDIR}/app/binARMv7l/ffmpeg"
        avcut="${APPDIR}/app/binARMv7l/avcut"
        if [[ `uname -a | grep "armadaxp" ` ]] ; then
        #if [ $device = "ds214" ] || [ $device = "ds414" ] ; then
            echo "                          alternative avcut-Version ohne asm wird verwendet"
            avcut="${APPDIR}/app/binARMv7l/avcut_disable-asm"
        fi
    elif [ $machinetyp = "i686" ] ; then
        bsy="${APPDIR}/app/bin/busybox"
    #	ffmpeg="${APPDIR}/app/bin/ffmpeg"
        ffmpeg=`which ffmpeg` # mitgeliefertes ffmpeg läuft derzeit nicht korrekt
        avcut="${APPDIR}/app/bin/avcut32"
        synOTR_LD_LIBRARY_PATH=$SAVED_LD_LIBRARY_PATH
        synOTR_PATH=$PATH:${APPDIR}/app/bin
    elif [ $machinetyp = "x86_64" ] ; then
        bsy="${APPDIR}/app/bin/busybox"
    #   ffmpeg="${APPDIR}/app/bin/ffmpeg"
        ffmpeg=`which ffmpeg` # mitgeliefertes ffmpeg läuft derzeit nicht korrekt
        avcut="${APPDIR}/app/bin/avcut64"
        synOTR_LD_LIBRARY_PATH=$SAVED_LD_LIBRARY_PATH
        synOTR_PATH=$PATH:${APPDIR}/app/bin
    else
        message="Deine CPU-Plattform [${machinetyp}] wird leider von synOTR nicht unterstützt oder ist nicht bekannt …"
        echo "$message"
        synodsmnotify $MessageTo "$message"
        exit
    fi

    synOTR_ENV ()
    {
    #   restore_ENV 
    #   echo "Die angepassten Pathvariablen werden geladen …"
        export PATH=$synOTR_PATH
        export LD_LIBRARY_PATH=$synOTR_LD_LIBRARY_PATH
    }

    synOTR_ENV

# Info der Datenbank auslesen:
# ---------------------------------------------------------------------
    if [ -f "${APPDIR}/app/etc/synOTR.sqlite" ] ; then
        rowcount=$(sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "SELECT COUNT(*) FROM raw")
        dbsize=$(ls -lh "${APPDIR}/app/etc/synOTR.sqlite" | awk '{ print $5 }')
        echo "DB-Größe:                 ${dbsize}Byte / $rowcount Datensätze"
    fi

# spezielle Programmpfade / sonstige Variablen anpassen :
# ---------------------------------------------------------------------
    # (oder andere gewünschte Version / nicht benötigte ggfs. auskommentieren)
    #   ffmpeg="${APPDIR}/app/bin/ffmpeg_fdk/ffmpeg"
    #   ffmpeg="${APPDIR}/app/bin/ffmpeg"
    #   ffmpeg=`which ffmpeg`   # erstes ffmpeg in PATH
    echo "ffmpeg-Version:           $ffmpeg"

# Konfiguration für LogLevel:
# ---------------------------------------------------------------------
    # LOGlevel:     0 => Logging inaktiv / 1 => normal / 2 => erweitert
    if [ $LOGlevel = "1" ] ; then
        echo "Loglevel:                 normal"
        ffloglevel="warning"        # ffmpeg LogLevel (https://ffmpeg.org/ffmpeg.html)
        mp4boxloglevel="-quiet"
        CUTloglevel="-w"
        cURLloglevel="-s"
        wgetloglevel="-q"
    elif [ $LOGlevel = "2" ] ; then
        echo "Loglevel:                 erweitert"
        ffloglevel="info"
        mp4boxloglevel=""
        CUTloglevel="-v"
        cURLloglevel="-v"
        wgetloglevel="-v"
    else
        ffloglevel="quiet"
        mp4boxloglevel="-quiet"
        CUTloglevel="-w"
    fi

# Verzeichnisse prüfen bzw. anlegen und anpassen:
# ---------------------------------------------------------------------
    echo "Anwendungsverzeichnis:    ${APPDIR}"
    
    # Variablenkorrektur für ältere Konfiguration.txt und Slash anpassen:
    if [ -d "$destdir" ] ; then
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

    if [ $endgueltigloeschen = "on" ] ; then
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

    if [ $OTRcutactiv = "off" ] ; then
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


TVDB_query() 
{
#########################################################################################
# Diese Funktion sucht auf theTVDB.com nach Serieninformationen                         #
#########################################################################################

#LOGlevel="2"
# Token erstellen, sofern nicht vorhanden oder älter als 24h:
sSQL="SELECT day_created,TOKEN,APIKEY FROM tvdb WHERE rowid=1 "
sqlerg=`sqlite3 -separator $'\t' ${APPDIR}/app/etc/synOTR.sqlite "$sSQL"`
TOKEN_DAY_CREATED=`echo "$sqlerg" | awk -F'\t' '{print $1}' `
TOKEN=`echo "$sqlerg" | awk -F'\t' '{print $2}' `
TVDB_APIKEY=`echo "$sqlerg" | awk -F'\t' '{print $3}' `

if [ $LOGlevel = "2" ] ; then
    echo "DB-Abfrageergebnis:       $sqlerg"
    #echo "APIKEY:                   $TVDB_APIKEY"
fi

if [ "$TOKEN_DAY_CREATED" -ne $today ] || [ "$TOKEN_DAY_CREATED" == "" ] || [ "$TOKEN" == "" ] || [ "$TOKEN" == "NULL" ]; then 
    echo "TVDB-Token wird erneuert …"
    
    if [ "$TVDB_APIKEY" == "" ] || [ "$TVDB_APIKEY" == "NULL" ] ; then # prüfen, ob der Updatedatensatz vorhanden ist, ggfls. einfügen
        echo "Kein TVDB-APIKEY gefunden! Belege die Variable \"TVDB_APIKEY=\" mit einem gültigen TVDB-APIKEY, oder wende dich an den Entwickler (synotr@$synotrdomain)"
    else
        restore_ENV
#        TVDB_TOKEN=`curl $cURLloglevel -X POST --header 'Content-Type: application/json' --header 'Accept: application/json' -d '{
#          "apikey": "'${TVDB_APIKEY}'"
#        }' 'https://api.thetvdb.com/login' | jq '.token' | sed "s/\"//g" 2>&1` #  | tr -d '"' 2>&1`
        TVDB_TOKEN=`curl $cURLloglevel -X POST --header 'Content-Type: application/json' --header 'Accept: application/json' -d '{
          "apikey": "'${TVDB_APIKEY}'"
        }' 'https://api.thetvdb.com/login' ` #| jq '.token' | sed "s/\"//g" 2>&1` #  | tr -d '"' 2>&1`
        
        if echo "$TVDB_TOKEN" | egrep -q "Connection timed out"; then
            echo "Serverfehler (Zeitüberschreitung)"
            continue
        else
            TVDB_TOKEN=`echo $TVDB_TOKEN | jq '.token' | sed "s/\"//g" 2>&1` 
        fi

        synOTR_ENV

        sSQLupdate="UPDATE tvdb SET TOKEN='$TVDB_TOKEN', day_created=$today, timestamp=(datetime('now','localtime')) WHERE rowid=1"
        sqlite3 ${APPDIR}/app/etc/synOTR.sqlite "$sSQLupdate"
    fi
fi

TVDB_TOKEN=$(sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "SELECT TOKEN FROM tvdb WHERE rowid=1")

if [ $LOGlevel = "2" ] ; then
    echo "TVDB_TOKEN: $TVDB_TOKEN"
fi

serietitletmp="${serietitle}"
echo -e ; 

    TVDB_seriesquery() 
    {
    echo -n "Abfrage [$serietitletmp] an theTVDB.com ==> "
    # URL-Encoding für String (https://de.wikipedia.org/wiki/URL-Encoding):
    serieTitleQuery=`echo "$serietitletmp" | sed "s/_s_/%27s_/g ; s/ s /%27s /g ; s/ /%20/g ; s/_/%20/g ; s/Ä/%C3%84/g ; s/ä/%C3%A4/g ; s/Ö/%C3%96/g ; s/ö/%C3%B6/g ; s/Ü/%C3%9C/g ; s/ü/%C3%BC/g ; s/ß/%C3%9F/g" | sed s/"("/%28/ | sed s/")"/%29/ ` # | sed 's/"("/%28/;s/")"/%29/' ` #| sed "s/\)/%29/g" | sed "s/\+/%2B/g" `

    #	Ä %C3%84
    #	ä %C3%A4
    #	Ö %C3%96
    #	ö %C3%B6
    #	Ü %C3%9C
    #	ü %C3%BC
    #	ß %C3%9F
    restore_ENV	# für curl unter ARMv7
    TVDB_FilmID=`curl $cURLloglevel -X GET --header 'Accept: application/json' --header "Accept-Language: $TVDBlang" --header "Authorization: Bearer $TVDB_TOKEN" "https://api.thetvdb.com/search/series?name=$serieTitleQuery" ` #| jq '.data[].id' | sed "s/\"//g"  | sed -n '1{p;q}' ` #| awk '{print $1}' `             #TVDB_FilmID=`echo "$TVDB_FilmID" | jq '.data[].id' | sed "s/\"//g" ` # ` #| tr -d '"' `
    synOTR_ENV

    if echo "$TVDB_FilmID" | egrep -q "Connection timed out"; then
        echo "Serverfehler (Zeitüberschreitung)"
    fi
    }

    TVDB_episodequery() 
    {
    TVDB_SerieName=` echo "$TVDB_FilmID" | jq '.data[].seriesName' | sed "s/\"//g"  | sed -n '1{p;q}' | sed "s/://g ; s/\?//g ; s/\*//g" `	# nur das erste Ergebnis wählen
    echo "$TVDB_SerieName"
    title="$TVDB_SerieName"	# verwende erkannten Serientitel als Filmtitel
    TVDB_FilmID=` echo "$TVDB_FilmID" | jq '.data[].id' | sed "s/\"//g"  | sed -n '1{p;q}'`

    if [[ `echo "$TVDB_FilmID" | grep [[:digit:]]` ]]; then # Test, ob Ergebnis eine Zahl ist / gültiges Ergebnis
        echo -e "Serie auf theTVDB.com gefunden - TVDB_FilmID: $TVDB_FilmID"
        restore_ENV	# für curl unter ARMv7
        episodeninfo=`curl $cURLloglevel -X GET --header 'Accept: application/json' --header "Accept-Language: $TVDBlang" --header "Authorization: Bearer $TVDB_TOKEN" "https://api.thetvdb.com/series/$TVDB_FilmID/episodes/query?airedSeason=0$season&airedEpisode=0$episode" `
        synOTR_ENV
        if echo "$episodeninfo" | egrep -q "Connection timed out"; then
            echo "Serverfehler (Zeitüberschreitung)"
        fi
        if jq -e . >/dev/null 2>&1 <<<"$episodeninfo"; then
            episodetitle=` echo $episodeninfo | jq '.data[].episodeName' | sed "s/\"//g ; s/://g ; s/\?//g ; s/\*//g ; s/\?//g" ` # | tr -d '"' `
            description=` echo $episodeninfo | jq '.data[].overview' | sed "s/\"//g" ` # | tr -d '"' `
        else
            echo "Serverantwort konnte nicht verarbeitet werden (kein kompatibles JSON)"
        fi
        if [ -z "$episodetitle" ] || [ "$episodetitle" == "null" ] ; then
            echo -e "Die Serie wurde zwar auf theTVDB.com gefunden, allerdings keine passende Episode!"
            episodetitle=""
            if [ $LOGlevel = "2" ] ; then
                echo "Abfrageergebnis: $episodeninfo"
            fi
        fi
        missSeries=0
        wget --timeout=30 --tries=2 $wgetloglevel -O - "http://${synotrdomain}/synOTR/synOTR_FILECOUNT_TVDB" >/dev/null 2>&1
    else
        echo -e "Keine Serieninformationen auf theTVDB.com gefunden."
        if [ $LOGlevel = "2" ] ; then
            echo "Abfrageergebnis: $TVDB_FilmID"
        fi
    fi
    }

TVDB_seriesquery

if echo "$TVDB_FilmID" | egrep -q "request|Error"; then # modifiziere die Abfrage (u.a. Großbuchstaben zusammenziehen)
    echo "Keine Serieninformationen auf theTVDB.com gefunden."
    if [ $LOGlevel = "2" ] ; then
        echo "Abfrageergebnis: $TVDB_FilmID"
    fi
    # einzelnstehende Großbuchstaben zusammenziehen / Unterstriche ersetzen:
    serietitletmp=`echo $serietitletmp | sed 's/__/ - /g ; s/_/ /g ; s/  //g' | sed -e "s/ \([A-Z][a-z]\)/§tmp§\1/g ; s/\([A-Z]\) \([a-z]\)/\1§tmp§\2/g ; s/\([A-Z]\) /\1/g ; s/§tmp§/ /g ; s/[[:space:]]\{1,\}/ /g"`
        #	Wenn Groß-klein, setze immer §tmp§ davor;                       s/ \([A-Z][a-z]\)/§tmp§\1/g
        #	Wenn Groß-Leerzeichen-klein, ersetze Leerzeichen durch §tmp§;   s/\([A-Z]\) \([a-z]\)/\1§tmp§\2/g
        #	Entferne alle Leerzeichen nach Großbuchstaben;                  s/\([A-Z]\) /\1/g
        #	Ersetze alle §tmp§ durch Leerzeichen;                           s/§tmp§/ /g
        #	Ersetze alle doppelten Leerzeichen durch je ein einziges;       s/[[:space:]]\{1,\}/ /g

    TVDB_seriesquery
    
    if echo "$TVDB_FilmID" | egrep -q "request|Error"; then # versuche es mit Umlauten und Punkten zwischen einzeln stehenden Großbuchstaben
        echo "Keine Serieninformationen auf theTVDB.com gefunden."
        if [ $LOGlevel = "2" ] ; then
            echo "Abfrageergebnis: $TVDB_FilmID"
        fi
        # einzelnstehende Großbuchstaben mit Punkt trennen / Unterstriche ersetzen / Umlaute wiederherstellen (Umlautersetzung nur nach einem Konsonanten):
        serietitletmp=`echo "${serietitle}" | sed 's/__/ - /g ; s/_/ /g ; s/  //g' | sed -e "s/\<ue/ü/g ; s/\<ae/ä/g ; s/\<oe/ö/g ; s/\<UE/Ü/g ; s/\<AE/Ä/g ; s/\<OE/Ö/g ; s/\([BCDFGHJKLMNPQRSTVWXYZ]\)\(ae\)/\1ä/g ; s/\([BCDFGHJKLMNPQRSTVWXYZ]\)\(ue\)/\1ü/g ; s/\([BCDFGHJKLMNPQRSTVWXYZ]\)\(oe\)/\1ö/g ; s/\([bcdfghjklmnpqrstvwxyz]\)\(oe\)/\1ö/g ; s/\([bcdfghjklmnpqrstvwxyz]\)\(ue\)/\1ü/g ; s/\([bcdfghjklmnpqrstvwxyz]\)\(ae\)/\1ä/g ; s/\([BCDFGHJKLMNPQRSTVWXYZ]\)\(AE\)/\1Ä/g ; s/\([BCDFGHJKLMNPQRSTVWXYZ]\)\(OE\)/\1Ö/g ; s/\([BCDFGHJKLMNPQRSTVWXYZ]\)\(UE\)/\1Ü/g" | sed -e "s/ \([A-Z][a-z]\)/§tmp§\1/g ; s/\([A-Z]\) \([a-z]\)/\1\. \2/g ; s/\([A-Z]\) /\1\./g ; s/§tmp§/ /g ; s/[[:space:]]\{1,\}/ /g" | sed -f ${APPDIR}/includes/textersetzung.txt`
        #	ersetze alle großen UE (> Ü) nach einem großen Konsonaten   s/\([BCDFGHJKLMNPQRSTVWXYZ]\)\(UE\)/\1Ü/g
        #	ersetze alle UE am Anfang der Zeile                         s/^UE/Ü/g
            #   > ersetzt durch: \< (= Anfang jedes Wortes)             s/\<UE/Ü/g

        TVDB_seriesquery

        if echo $TVDB_FilmID | egrep -q "request|Error" ; then # versuche es mit dem OTR-Metadatentitel
            echo "Keine Serieninformationen auf theTVDB.com gefunden."
            if [ $LOGlevel = "2" ] ; then
                echo "Abfrageergebnis: $TVDB_FilmID"
            fi
            if [ ! -z "$OTRtitle" ] && [ ! "$OTRtitle" == "null" ] ; then
                serietitletmp="$OTRtitle"
                TVDB_seriesquery

                if echo "$TVDB_FilmID" | egrep -q "request|Error"; then
                    echo "Keine Serieninformationen auf theTVDB.com gefunden."
                    if [ $LOGlevel = "2" ] ; then
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


OTRserien_query()
{
#########################################################################################
# Diese Funktion sucht nach Serieninformationen                                         #
# VIELEN DANK AN Daniel Dieth VON www.otr-serien.de                                     #
#########################################################################################

serieninfo=$(wget --timeout=60 --tries=2 -q -O - "http://www.otr-serien.de/myapi/reverseotrkeycheck.php?otrkey=$originalfilename&who=synOTR" )

if [ $LOGlevel = "2" ] ; then
    echo "  http://www.otr-serien.de/myapi/reverseotrkeycheck.php?otrkey=$originalfilename&who=synOTR" ; echo -e
    echo "Rückgabewert von otr-serien.de ==>"; echo "	$serieninfo" ; echo -e # Erfolglosmeldung Serieninfo: <!DOCTYPE html> Keine Serien zuordnung vorhanden
fi

serieninfo="{ ${serieninfo#*\{}" # 2018-02-13 Rückgabe von otr-serien.de wurde scheinbar geändert (vorgelagerte Infos vor jason-Container > werden jetzt abgeschnitten)
#	Zeichenkorrektur:
serieninfo=`echo $serieninfo | sed "s/<!DOCTYPE html>//g" | sed -f ${APPDIR}/includes/decode.sed `
OTRID=`echo "$serieninfo" | awk -F, '{print $1}' | awk -F: '{print $2}' | sed "s/\"//g"`

#echo "$serieninfo"
if echo "$serieninfo" | grep -q "Keine Serien zuordnung vorhanden"; then
    missSeries=1	# Trigger für fehlende Serieninformation in SQLite-DB
    echo -e "kein Suchergebnis"
elif echo "$serieninfo" | grep -q "Kein OTR DB Eintrag vorhanden"; then
    missSeries=1	# Trigger für fehlende Serieninformation in SQLite-DB
    echo -e "Film konnte von OTRserien nicht identifiziert werden (wahrscheinlich wurde der Film manuell umbenannt) --> Standardumbenennung wird verwendet"
#    elif echo "$serieninfo" | grep -q "Diese Datei ist nicht verfügbar"; then
#        missSeries=1	# Trigger für fehlende Serieninformation in SQLite-DB
#        echo -e "nicht vorhanden (vom Server gesperrt!)"
elif [ -z "$serieninfo" ] ; then
    echo -e ">>> Keine Serverantwort <<<"
#elif [ ! -z "$serieninfo" ] ; then     # ist nicht zuverlässig < 2018-06-14
elif [[ "$OTRID" =~ $regInt ]]; then    # Ist die OTR-Id eine echte Zahl?
    if jq -e . >/dev/null 2>&1 <<<"$serieninfo"; then   # prüfen, ob korrektes JSON-Format verarbeitet werden kann (https://stackoverflow.com/questions/46954692/check-if-string-is-a-valid-json-with-jq)
        echo -e "gefunden:"
        #   Zeichenkorrektur:
        #   serieninfo=`echo $serieninfo | sed "s/<!DOCTYPE html>//g" | sed 's/\\\u00e4/ä/g' | sed 's/\\\u00f6/ö/g' | sed 's/\\\u00c4/Ä/g' | sed 's/\\\u00d6/Ö/g' | sed 's/\\\u00fC/ü/g' | sed 's/\\\u00dC/Ü/g' | sed 's/\\\u00dF/ß/g' `
        #   serieninfo=`echo $serieninfo | sed "s/<!DOCTYPE html>//g" | sed -f ${APPDIR}/includes/decode.sed `
        #   OTRID=`echo "$serieninfo" | awk -F, '{print $1}' | awk -F: '{print $2}' | sed "s/\"//g"`

        missSeries=0	# Trigger für fehlende Serieninformation in SQLite-DB
        serietitle=`echo "$serieninfo" | jq -r '.Serie' | sed "s/://g" `
        season=`echo "$serieninfo" | awk -F, '{print $3}' | awk -F: '{print $2}' | sed "s/\"//g"`
        season="$(printf '%02d' "$season")"     # 2stellig mit führender Null
        episode=`echo "$serieninfo" | awk -F, '{print $4}' | awk -F: '{print $2}' | sed "s/\"//g"`
        episode="$(printf '%02d' "$episode")"	# 2stellig mit führender Null
        episodetitle=`echo "$serieninfo" | jq -r '.Folgenname' | sed "s/://g" | sed "s/\?//g" | sed "s/\*//g" | sed "s/\?//g" `
        description=`echo "$serieninfo" | jq -r '.Folgenbeschreibung' | sed "s/:/ -/g" `
        wget --timeout=30 --tries=2 -q -O - "http://${synotrdomain}/synOTR/synOTR_FILECOUNT_OTRSERIEN" >/dev/null 2>&1
    else
        # "Failed to parse JSON, or got false/null"
        missSeries=1	# Trigger für fehlende Serieninformation in SQLite-DB
        echo -e "Serverantwort konnte nicht verarbeitet werden (kein kompatibles JSON)"
    fi
else
    missSeries=1	# Trigger für fehlende Serieninformation in SQLite-DB
    echo -e "unbekannter Fehler …"
fi
}


OTRdecoder()
{
#########################################################################################
# Diese Funktion dekodiert heruntergeladene otrkey-Dateien                              #
#########################################################################################

    AC3ReMux ()
    {
    #########################################################################################
    # Diese Funktion ersetzt die MP3-Audiospur durch eine heruntergeladene AC3-Audiospur    #                       
    #########################################################################################
    
    filetest=`find "$DECODIR" -maxdepth 1 -name "*.ac3" -type f`
    if [ ! -z "$filetest" ] ; then
        echo -e ; echo -e
        echo "==> integriere AC3-Audiospur:"
        if [ $OTRcutactiv = "on" ] && [ "$SMARTRENDERING" != "on" ] ; then
            echo "    Bei aktiviertem Schneiden ist die AC3-Tonspurintegration nur in Verbindung mit aktiviertem Smartrendering möglich."
        else
            echo "    (Bitte beachte: die AC3-Funktion hat experimentellen Charakter."
            echo "    Es gibt immer wieder Filme, wo es nicht 100% passt, bzw. es zu Problemen kommt.)"
            
            IFS=$'\012'
            for i in $(find "$DECODIR" -maxdepth 1 -name "*.ac3" -type f)
                do
                    IFS=$OLDIFS
                    ac3filename=`basename "$i"`
                    videosource=`find "$DECODIR" -maxdepth 1 -name "${ac3filename%.HD*}*" -type f -and ! -name "*.ac3" -type f`
                    videosourcefilename=`basename "$videosource"`
                    videosourcetitle=${videosourcefilename%.*}

                    muxerror=0  # nur für Log
                    if [ -f "${DECODIR}/${videosourcetitle}.avi" ]; then
                        echo -e; echo "MUXING:              ---> ${ac3filename}" #; echo -e
                        muxingLOG=$(nice -n $niceness $ffmpeg -threads 2 -loglevel $ffloglevel  -i "${DECODIR}/${videosourcetitle}.avi" -i "$i"  -map 0:0 -map 1:0 -c:a copy -async 1 -c:v copy -sn -y "${DECODIR}/${videosourcetitle}.ac3tmp.avi" 2>&1)

                        if [ -f "${DECODIR}/${videosourcetitle}.ac3tmp.avi" ]; then
                            # Original löschen / umbenennen:
                            if [ $endgueltigloeschen = "on" ] ; then
                                rm "$i"
                                rm "${DECODIR}/${videosourcetitle}.avi"
                            else
                                mv "$i" "$OTRkeydeldir"
                                mv "${DECODIR}/${videosourcetitle}.avi" "${OTRkeydeldir}/${videosourcetitle}.mp3.avi"
                            fi
                            mv "${DECODIR}/${videosourcetitle}.ac3tmp.avi" "${DECODIR}/${videosourcetitle}.avi"
                            echo "                          L==> fertig"
                            wget --timeout=30 --tries=2 -q -O - "http://${synotrdomain}/synOTR/synOTR_FILECOUNT_AC3" >/dev/null 2>&1
                            needindex=1
                        else
                            echo "                          L==> muxen fehlgeschlagen [Datei im Zielverzeichnis nicht gefunden …]"; echo -e
                            echo "muxingLOG: $muxingLOG"
                            muxerror=1
                        fi
                    else
                        echo "    > keine passende Videodatei gefunden!"
                    fi
                    if [ $LOGlevel = "2" ] && [ $muxerror = "0" ] ; then
                        echo "LogLevelinfo:"
                        echo "muxingLOG: $muxingLOG"
                    fi
                done
            sleep 1
        fi
    fi
    }

filetest=`find "${OTRkeydir}" -maxdepth 1 -name "*.otrkey" -mmin +"$timediff" -type f`

if [ $decoderactiv = "on" ] && [ ! -z "$filetest" ] ; then
    echo -e ;
    echo "==> decodieren:"
    OTRkeydir="${OTRkeydir%/}/"
    
    IFS=$'\012'	 # entspricht einem $'\n' Newline
    for i in $(find "${OTRkeydir}" -maxdepth 1 -name "*.otrkey" -mmin +"$timediff" -type f)
        do
            IFS=$OLDIFS
            echo -e
            filename=`basename "$i"`
            decofilename=${filename%.*}
            echo "    DECODIERE:       ---> $filename"
            echo -n "                          "; date

            if [ $machinetyp = "x86_64" ]; then
                otrdecoderLOG=$(nice -n $niceness otrdecoder64 -q -i "$i" -o "$DECODIR" -e "$OTRuser" -p "$OTRpw" 2>&1)
            elif [ $machinetyp = "i686" ]; then
                otrdecoderLOG=$(nice -n $niceness otrdecoder32 -q -i "$i" -o "$DECODIR" -e "$OTRuser" -p "$OTRpw" 2>&1)
            elif [ `echo $machinetyp | grep "armv" ` ] ; then
                otrdecoderLOG=$(nice -n $niceness otrpidecoder -d "$i" -O "${DECODIR}/${decofilename}" -e "$OTRuser" -p "$OTRpw"  2>&1)
            fi

            if [ $LOGlevel = "2" ] ; then
                echo "OTRdecoder LOG: $otrdecoderLOG"
            fi
            if echo $otrdecoderLOG | grep -q "No connection to server" ; then 
                echo -e; echo "    ! ! ! OTRDecoder konnte keine Verbindung zum OTR-Server aufbauen. Datei wird übersprungen." # behält Quellvideo
                echo -e; echo "OTRdecoder LOG:"; echo "$otrdecoderLOG"
                continue ; 
            else 
                if [ -f "${DECODIR}/$decofilename" ]; then 	# nur löschen, wenn erfolgreich decodiert:
                    if [ $endgueltigloeschen = "on" ] ; then
                        rm "$i"
                    else
                        mv "$i" "$OTRkeydeldir"
                    fi
                    
                    ffprobeSourceInfo=$(ffprobe -v quiet -print_format json -show_format -show_streams "${DECODIR}/$decofilename" 2>&1)
#                   ffprobeSourceInfo=$(ffprobe -v quiet -print_format json -show_format -show_streams -show_programs "${DECODIR}/$decofilename" 2>&1)
                        # Errormeldung vor jason ab DSM 6.2 (wird hier abgeschnitten): ERROR: 
                        # ld.so: object 'openhook.so' from LD_PRELOAD cannot be preloaded (cannot open shared object file): ignored. { …
                        ffprobeSourceInfo="{ ${ffprobeSourceInfo#*\{}"  
                        
                    OTRtitle=`echo "$ffprobeSourceInfo" | jq '.format.tags.title' | sed "s/\" //g" | sed "s/\"//g" | sed "s/'/''/g" | sed "s/\"//g"  | uconv -f utf-8 -t utf-8 -x NFC `
                    OTRcomment=`echo "$ffprobeSourceInfo" | jq '.format.tags.comment' | sed "s/\" //g" | sed "s/\"//g" | sed "s/'/''/g" | sed "s/\"//g"  | uconv -f utf-8 -t utf-8 -x NFC `

                    if [ $LOGlevel = "2" ] ; then
                        echo -e; echo "        ------------------------->"
                        echo "    OTRtitle:   > $OTRtitle"
                        echo "    OTRcomment: > $OTRcomment"
                        echo -n "        Datenbank schreiben ==> "
                    fi
                    
                    sSQL="INSERT INTO raw ( file_original, OTRtitle, OTRcomment) VALUES ('$decofilename', '$OTRtitle', '$OTRcomment')"
                    # leider werden Umlaute und Sonderzeichen nicht korrekt codiert … !
                    sqlite3 ${APPDIR}/app/etc/synOTR.sqlite "$sSQL"
                    
                    if [ $LOGlevel = "2" ] ; then
                        echo "	sSQL: $sSQL"
                        echo "fertig"; echo "        <-------------------------"
                    fi
                    echo "                          L==> fertig"
                else
                    echo "                          L==> decodieren fehlgeschlagen [Datei im Zielverzeichnis nicht gefunden …]"; echo -e
                    echo "OTRdecoder LOG: $otrdecoderLOG"
                    continue
                fi
                
                if [ $lastjob -eq 1 ] && [ $useWORKDIR == "no" ] ; then
                    # füge Datei dem Index der Videostation hinzu:
                    synoindex -a "${DECODIR}/${decofilename}"
                    if [ $dsmtextnotify = "on" ] ; then
                        sleep 1
                        synodsmnotify $MessageTo "synOTR" "$filename ist fertig"
                        sleep 1
                    fi
                    if [ $dsmbeepnotify = "on" ] ; then
                        sleep 1
                        echo 2 > /dev/ttyS1 #short beep
                        sleep 1
                    fi
                    if [ ! -z $PBTOKEN ] ; then
                        PB_LOG=`curl $cURLloglevel --header "Access-Token:${PBTOKEN}" https://api.pushbullet.com/v2/pushes -d type=note -d title="synOTR" -d body="Film [$filename] ist fertig."`
                        if [ $LOGlevel = "2" ] ; then
                            echo "        PushBullet-LOG:"
                            echo "$PB_LOG"
                        elif echo "$PB_LOG" | grep -q "error"; then # für Loglevel 1 nur Errorausgabe
                            echo -n "        PushBullet-Error: "
                            echo "$PB_LOG" | jq -r '.error_code'
                        fi
                    else
                        echo "        (PushBullet-TOKEN nicht gesetzt)"
                    fi
                    wget --timeout=30 --tries=2 -q -O - "http://${synotrdomain}/synOTR/synOTR_FILECOUNT" >/dev/null 2>&1
                    needindex=1
                fi
            fi
        done
elif [ $decoderactiv = "off" ] ; then
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

filetest=`find "$DECODIR" -maxdepth 1 -name "*.avi" -o -name "*.mp4" -type f`

#if [ $OTRavi2mp4active = "on" ] && [ ! -z "$filetest" ] ; then
if [ -z "$filetest" ] ; then
    return
fi

if [ $OTRcutactiv = "on" ] ; then
    echo -e ; echo -e
    # Es wird geprüft, ob SmartRendering mit avcut überhaupt 
    # möglich ist, sonst Fallback auf avisplit:
    # ---------------------------------------------------------------------
    avisplitpath=`which avisplit`
    if [ ! -f "$avcut" ] && [ "$SMARTRENDERING" = "on" ] ; then 	# ist avcut vorhanden?
        SMARTRENDERING="off"
        echo "Smartrendierung (framegenaues Schneiden) nicht möglich, da das Programm \"avcut\" fehlt."
    fi

    if [ ! -f "$avisplitpath" ] && [ "$SMARTRENDERING" != "on" ]  ; then
        echo "avisplit wurde nicht gefunden - Schneiden wird übersprungen!"; echo "Installiere Transcode via iPKG/oPKG"; echo -e
        break
    else
        echo "==> schneiden:"

        if [ ${RAMmax} -lt 490 ]; then
            SMARTRENDERING="off"
            echo "Für das framegenaue Schneiden wird mindestens 500 MB installierter RAM benötigt ($RAMmax MB installiert)."
            echo "Smartrendering wird aufgrund fehlenden Arbeitsspeichers deaktivert"
            echo "Es wird mit der herkömmlichen Methode (avisplit) geschnitten."; echo -e
        fi

        tmp="${APPDIR}/app/tmp"
        server="http://cutlist.at/"

        AC_test ()
        {
        # Diese Funktion überprüft verschiedene Einstellungen:
        # ---------------------------------------------------------------------
        if [ -d "$tmp/otrcut" ] && [ -w "$tmp" ]; then
            AC_testLOG="Verwende $tmp/otrcut als tmp-Ausgabeordner."
            tmp="$tmp/otrcut"
        elif [ -d "$tmp" ] && [ ! -w "$tmp" ]; then
            AC_testLOG="Sie haben keine Schreibrechte in $tmp!"
        fi
        if [ $LOGlevel = "2" ] ; then
            echo "$AC_testLOG"
        fi
        }

        AC_ffprobe ()
        {
        # Diese Funktion ließt via ffprobe Dateiinformationen aus:
        # ---------------------------------------------------------------------
        AC_ffprobeInfo=$(ffprobe -v quiet -print_format json -show_format -show_streams "$i" 2>&1)
            
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

        if [ $LOGlevel = "2" ] ; then
                echo "$date_varLOG"
        fi
        }

        AC_name ()
        {
        # DIESE FUNKTION WIRD GERADE AUFGEGÄUMT …


        # Diese Funktion definiert den Cutlist- und Dateinamen
        # und üperprüft um welches Dateiformat es sich handelt:
        # ---------------------------------------------------------------------
        film="$i"                   # Der komplette Filmname und gegebenfalls der Pfad
        film_ohne_anfang="$i"
#       CUTLIST=`basename "$film"`  # Filmname ohne Pfad
#       filmname=$CUTLIST
#       filmname=`basename "$film"`
        AC_nameLOG="Überprüfe um welches Aufnahmeformat es sich handelt --> "



#   film_ohne_anfang nur hier
#   film_ohne_ende nur hier und in Rename auskommentiert
#   filmname nur hier
#   format nur hier im Sinn von Qualität



        if echo "$film_ohne_anfang" | grep -q ".HQ."; then	#Wenn es sich um eine "HQ" Aufnahme handelt
            film_ohne_ende=${film%%.mpg.HQ.avi}     # Filmname ohne Dateiendung
            CUTLIST=${CUTLIST/.avi/}.cutlist        # Der lokale Cutlistname
#           format=hq
            AC_nameLOG="${AC_nameLOG}HQ"
        elif echo "$film_ohne_anfang" | grep -q ".mp4"; then	#Wenn es sich um eine "mp4" Aufnahme handelt
            film_ohne_ende=${film%%.mpg.mp4}        # Filmname ohne Dateiendung
#           format=mp4
            CUTLIST=${CUTLIST/.mp4/}.cutlist        # Der lokale Cutlistname
            AC_nameLOG="${AC_nameLOG}mp4"
        else
            film_ohne_ende=${film%%.mpg.avi}        # Filmename ohne Dateiendung
#           format=avi
            CUTLIST=${CUTLIST/.avi/}.cutlist        # Der lokale Cutlistname
            AC_nameLOG="${AC_nameLOG}avi"
        fi


        if echo "$film" | grep / >> /dev/null; then # Wenn der Dateiname einen Pfad enthält
            film_ohne_anfang=${film##*/}            # Filmname ohne Pfad
            if echo "$film_ohne_anfang" | grep -q ".HQ."; then	#Wenn es sich um eine "HQ" Aufnahme handelt
                film_ohne_ende=${film_ohne_anfang%%.mpg.HQ.avi}
            #	format=hq
            elif echo "$film_ohne_anfang" | grep -q ".mp4"; then	#Wenn es sich um eine "mp4" Aufnahme handelt
                film_ohne_ende=${film_ohne_anfang%%.mpg.mp4}
            #	format=mp4
            else
                film_ohne_ende=${film_ohne_anfang%%.mpg.avi}
            #	format=avi
            fi
        fi


        if echo "$film_ohne_anfang" | grep -q ".HQ."; then
            outputfile="${WORKDIR}$film_ohne_ende.HQ-cut.avi"
#           outputfile="${WORKDIR}$film_ohne_ende.mpg.HQ-cut.avi"
        elif echo "$film_ohne_anfang" | grep -q ".mp4"; then
            outputfile="${WORKDIR}$film_ohne_ende-cut.mp4"
#           outputfile="${WORKDIR}$film_ohne_ende.mpg-cut.mp4"
        else
            outputfile="${WORKDIR}$film_ohne_ende-cut.avi"
#           outputfile="${WORKDIR}$film_ohne_ende.mpg-cut.avi"
        fi

        if [ $LOGlevel = "2" ] ; then
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
        #	vorhanden=no	## nehme erstmal an, es wurde keine Cutlist gefunden
        #	continue=1
        for f in $local_cutlists; do
            echo -n "Überprüfe ob eine der gefundenen Cutlists zum Film passt --> "
            if [ -z $f ]; then
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
            CUTLIST=$namelocal[$NUMBER]
            cp "$CUTLIST" "$tmp"
            vorhanden=yes
        fi
        }

        AC_getlocalcutlist_withCheck ()
        {
        # In dieser Funktion wird die lokale Cutlist überprüft (Input von Stafan Weiss)
        # Diese Methode greift, sobald die Variable '$OTRlocalcutlistdir' (in der Konfiguration.txt) gesetzt wurde:
        # ---------------------------------------------------------------------
        pushd "$OTRlocalcutlistdir" >> /dev/null
        filmOhnePfad=`basename "$film"`
        local_cutlists=$(ls *.cutlist 2>/dev/null)      # Variable mit allen Cutlists in $PWD
        filesize=$(ls -l "$film" | awk '{ print $5 }')  # Dateigröße des Filmes
        vorhanden=no	                                # nehme erstmal an, es wurde keine Cutlist gefunden
        continue=1
        ApplyToFile=no
        OriginalFileSizeBytes=no

        if [ -z "$local_cutlists" ]; then
            echo -e "Keine lokale Cutlist gefunden!"
        else
            echo "okey"
            echo -e "(localcutlistdir mit Prüfung ist aktiviert)"
            echo -e "Überprüfe ob eine der lokalen Cutlists zum Film passt:"

            for f in $local_cutlists; do
                echo -e -n "File: $f"
                OriginalFileSize=$(cat $f | grep OriginalFileSizeBytes | cut -d"=" -f2 | /usr/bin/tr -d "\r")	#Dateigröße des Films
                if cat $f | grep -q "$filmOhnePfad"; then	    # Wenn der Dateiname mit ApplyToFile übereinstimmt
                    echo -e -n " ApplyToFile passt."
                    ApplyToFile=yes
                fi
                if [ "$OriginalFileSize" == "$filesize" ]; then	# Wenn die Dateigröße mit OriginalFileSizeBytes übereinstimmt
                    echo -e -n " OriginalFileSizeBytes passt."
                    OriginalFileSizeBytes=yes
                fi
                if [ "$ApplyToFile" == "yes" ] || [ "$OriginalFileSizeBytes" = "yes" ]; then	# Wenn eine passende Cutlist vorhanden ist
                    echo
                    vorhanden=yes
                    continue=0
                    break;
                else
                    echo -e " passt nicht."
                    vorhanden=no
                    continue=1
                fi
            done

            if [ "$vorhanden" == "yes" ]; then
                echo "Es wurde eine passende Cutlist gefunden. Diese wird nun verwendet."
                CUTLIST="$f"
                cp "$CUTLIST" "$tmp"
            fi
        fi
        popd >> /dev/null
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

#       inputfilename="$filename"   # < 2018-06-12
#       filmdateiname=`basename $film` # < 2018-06-12

        continue=0
        filesize=$(ls -l "$film" | awk '{ print $5 }')
        filesizeMB=$(echo | gawk '{print '$filesize'/1000000}' | awk '{printf "%.2f\n", $1}')

        if [ $LOGlevel = "2" ] ; then
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
                    search=$(echo $filename | sed 's/.avi//g' | sed 's/.mpg//g' | sed 's/.HQ//g' | sed 's/.HD//g' | sed 's/.mp4//g' | sed 's/.ac3//g' | sed 's/DivFix++.//g' | sed 's/DivFix.//g' )
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
#           sed -i 's/	//g' "$tmp/search.xml"                                           # führende Tabs entfernen / brachte Parsing durcheinander - lag möglicherweise doch an Dos-Zeilenenden
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
                IFS=$'\n'   # den `Internal Field Separator` so verändern, dass Felder nur noch durch Zeilenumbrüche (und nicht zusätzlich durch Leerzeichen) getrennt werden.
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
            if [ $LOGlevel = "1" ] || [ $LOGlevel = "2" ] ; then
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
                if [ $LOGlevel = "1" ] || [ $LOGlevel = "2" ] ; then
                    cp "$tmp/$CUTLIST" "${DECODIR}/_LOGsynOTR/${CUTLIST}"
                fi

                #	------------------ ID der verwendeten Cutlist speichern:
                sSQL="SELECT rowid FROM raw WHERE file_original LIKE '${filename}%' ORDER BY rowid DESC LIMIT 1" 
                sqlerg=`sqlite3 -separator $'\t' ${APPDIR}/app/etc/synOTR.sqlite "$sSQL"`
                rowid=`echo "$sqlerg" | awk -F'\t' '{print $1}' `
                sSQL="UPDATE raw SET cutlist_ID='$id' WHERE rowid='$rowid'"
                sqlite3 ${APPDIR}/app/etc/synOTR.sqlite "$sSQL"
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
        IFS=$'\012'
        }

        AC_get_fps ()
        {
        # Hier wird geprüft, welche Bildrate der Film hat.
        # ---------------------------------------------------------------------
        echo -n "Framerate des Films:      "
        fps=""

        rframerate_1=`echo "$AC_ffprobeInfo" | jq '.streams[0].r_frame_rate' | sed "s/\"//g" | awk -F '/' '{print $1}'`
        rframerate_2=`echo "$AC_ffprobeInfo" | jq '.streams[0].r_frame_rate' | sed "s/\"//g" | awk -F '/' '{print $2}'`
        fps=$(echo | gawk '{print '$rframerate_1'/'$rframerate_2'}')

        if [ "$fps" == "" ]; then	#Wenn fps nicht per ffprobe gelesen werden konnte
            fps=`cat "$tmp/$CUTLIST" | grep "FramesPerSecond=" | sed "s/FramesPerSecond\=//g" | /usr/bin/tr -d "\r" ` #| awk -F. '{print $1}'`
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
        SuggestedMovieName=`cat "$tmp/$CUTLIST" | grep "SuggestedMovieName=" | sed "s/SuggestedMovieName\=//g;s/[0-9]\{2,4\}[.][0-9]\{1,2\}[.][0-9]\{1,2\}[ _][0-9]\{2\}[\-][0-9]\{2\}/Datum_Zeit/g;s/[0-9]\{2,4\}[.][0-9]\{1,2\}[.][0-9]\{1,2\}/Datum/g;s/_/ /g" | /usr/bin/tr -d "\r" ` #| awk -F. '{print $1}'` # Datum, Zeit im OTR-Format und Unterstriche werden entfernt
        usercomment=`cat "$tmp/$CUTLIST" | grep "UserComment=" | sed "s/UserComment\=//g;s/[0-9]\{2,4\}[.][0-9]\{1,2\}[.][0-9]\{1,2\}[ _][0-9]\{2\}[\-][0-9]\{2\}/Datum_Zeit/g;s/[0-9]\{2,4\}[.][0-9]\{1,2\}[.][0-9]\{1,2\}/Datum/g;s/_/ /g" | /usr/bin/tr -d "\r" ` #| awk -F. '{print $1}'`

        if echo "$SuggestedMovieName" | grep -q "[sST]\?[0-9]\{1,2\}[.\-xX]\?[eE]\?[0-9]\{1,2\}" ; then  # [[:space:]]  # S01E01 / S01.E01 / 01-01 / 01x01 / teilweise ohne führende Null
            #CL_serieninfo=$(parseRegex "$SuggestedMovieName" ".[sST]?[0-9]{1,2}[.\-xX]?[eE]?[0-9]{1,2}" | head -n1)    # head -n1: nur der erste Fund im String wird verwendet
            CL_serieninfo=$(echo "$SuggestedMovieName" | egrep -o "[sST]?[0-9]{1,2}[.\-xX]?[eE]?[0-9]{1,2}" | head -n1)
            CL_serieninfo_season=$(echo "$CL_serieninfo" | awk '{print toupper($0) }' | sed "s/S/ /g;s/T/ /g;s/E/ /g;s/X/ /g;s/-/ /g;s/\./ /g;s/  / /g" | awk '{print $1}')
            CL_serieninfo_episode=$(echo "$CL_serieninfo" | awk '{print toupper($0) }' | sed "s/S/ /g;s/T/ /g;s/E/ /g;s/X/ /g;s/-/ /g;s/\./ /g;s/  / /g" | awk '{print $2}')
            CL_serieninfofound=1
        elif echo "$usercomment" | grep -q "[sST]\?[0-9]\{1,2\}[.\-xX]\?[eE]\?[0-9]\{1,2\}" ; then 
            #CL_serieninfo=$(parseRegex "$usercomment" "[sST]?[0-9]{1,2}[.\-xX]?[eE]?[0-9]{1,2}" | head -n1)
            CL_serieninfo=$(echo "$usercomment" | egrep -o "[sST]?[0-9]{1,2}[.\-xX]?[eE]?[0-9]{1,2}" | head -n1)
            CL_serieninfo_season=$(echo "$CL_serieninfo" | awk '{print toupper($0) }' | sed "s/S/ /g;s/T/ /g;s/E/ /g;s/X/ /g;s/-/ /g;s/\./ /g;s/  / /g" | awk '{print $1}')
            CL_serieninfo_episode=$(echo "$CL_serieninfo" | awk '{print toupper($0) }' | sed "s/S/ /g;s/T/ /g;s/E/ /g;s/X/ /g;s/-/ /g;s/\./ /g;s/  / /g" | awk '{print $2}')
            CL_serieninfofound=1
        fi

        if [[ $CL_serieninfofound = 1 ]] && [[ "$CL_serieninfo_season" =~ $regInt ]] && [[ "$CL_serieninfo_episode" =~ $regInt ]]; then
            echo "Serieninfo aus Cutlist:   S${CL_serieninfo_season}E${CL_serieninfo_episode}"
            #	------------------ schreibe Serieninformation in DB:
            sSQL="UPDATE raw SET miss_series='0', serie_season='$CL_serieninfo_season', serie_episode='$CL_serieninfo_episode'  WHERE file_original='$filename'"
            if [ $LOGlevel = "2" ] ; then
                echo "sSQL Serieninfo:          $sSQL"
            fi
            sqlite3 ${APPDIR}/app/etc/synOTR.sqlite "$sSQL"
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
            while [ $cut_anzahl -gt 0 ]; do
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
        if [ $format == "zeit" ]; then
            head1=1
            echo "Es müssen $cut_anzahl Cuts umgerechnet werden"
            while [ $cut_anzahl -gt 0 ]; do
                #Die Sekunde in der der Cut startet
                time_seconds_start=$(cat "$tmp/$CUTLIST" | grep "Start=" | cut -d= -f2 | head -n$head1 | tail -n1 | cut -d"." -f1 | /usr/bin/tr -d "\r")
                ss=$time_seconds_start          # Setze die Skunden auf $time_seconds_start
                mm=0                            # Setze die Minuten auf 0
                hh=0                            # Setze die Stunden auf 0
                while [ $ss -ge "60" ]; do      # Wenn die Sekunden >= 60 sind
                    mm=$(( mm +  1))            # Zaehle Minuten um 1 hoch
                    ss=$(( ss - 60))            # Zaehle Sekunden um 60 runter
                    while [ $mm -ge "60" ]; do  # Wenn die Minuten >= 60 sind
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
                while [ $ss -ge "60" ]; do      # Wenn die Sekunden >= 60 sind
                    mm=$(( mm +  1 ))           # Zaehle Minuten um 1 hoch
                    ss=$(( ss - 60 ))           # Zaehle Sekunden um 60 runter
                    while [ $mm -ge "60" ]; do  # Wenn die Minuten >= 60 sind
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
        elif [ $format == "frames" ]; then
            head1=1
            echo "Es müssen $cut_anzahl Cuts umgerechnet werden"
            while [ $cut_anzahl -gt 0 ]; do
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
        framediff=$(echo | gawk '{print 1/'${fps}'}')   # Zeitdifferenz für genau 1 Frame, da avcut mit Zeitwerten arbeitet
        if [ $LOGlevel = "2" ] ; then
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
                time_seconds_start=$(echo | gawk '{print '$time_seconds_start'+('$FrameversatzAnfangCut'*'$framediff')}')
                echo "Startcut: $time_seconds_start Sekunden"
                time="${time}${time_seconds_start} "
                # Wie viele Sekunden der Cut dauert
                time_seconds_ende=$(cat "$tmp/$CUTLIST" | grep "Duration=" | cut -d"=" -f2 | head -n$head1 | tail -n1 | /usr/bin/tr -d "\r" )
                time_seconds_ende=$(echo | gawk '{print '$time_seconds_ende'+'$time_seconds_start'+('$FrameversatzEndeCut'*'$framediff')}')
                echo "Endcut: $time_seconds_ende Sekunden"
                time="${time}${time_seconds_ende} "
                head1=$(( head1 + 1 ))
                cut_anzahl=$(( cut_anzahl - 1 ))
            done
        elif [ "$format" == "frames" ]; then            # Wenn das verwendete Format "Frames" ist
            head1=1
            echo "Es müssen $cut_anzahl Cuts für avcut umgerechnet werden."
            while [ $cut_anzahl -gt 0 ]; do
                # Der Frame bei dem der Cut beginnt
                startframe=$(cat "$tmp/$CUTLIST" | grep "StartFrame=" | cut -d= -f2 | head -n$head1 | tail -n1 | /usr/bin/tr -d "\r" )
                echo "Startframe= $startframe"
                startframe=$(( $startframe + $FrameversatzAnfangCut ))              # mit manueller Framekorrektur
                time_seconds_start=$(echo | gawk '{print '$startframe'/'$fps'}')
                time="${time}${time_seconds_start} "
                # Wie viele Frames dauert der Cut
                stopframe=$(cat "$tmp/$CUTLIST" | grep "DurationFrames=" | cut -d= -f2 | head -n$head1 | tail -n1 | /usr/bin/tr -d "\r" )
                # Der Frame bei dem der Cut endet
                stopframe=$(( stopframe + startframe + $FrameversatzEndeCut ))      # mit manueller Framekorrektur
                echo "Endframe= $stopframe"
                time_seconds_ende=$(echo | gawk '{print '$stopframe'/'$fps'}')
                time="${time}${time_seconds_ende} "
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
        if [ "$SMARTRENDERING" = "on" ]; then
            echo "> Übergebe die Cuts an avcut"

            # für ARMv7 unterstützt avcut noch nicht die Operanten -i & -o ==> Abhilfe: avcut-0.4 für ARMv7 kompilieren (ohne Nachteil)
            if [ $machinetyp = "x86_64" ] || [ $machinetyp = "i686" ]; then
                AVCUTLOG=$(time nice -n $niceness $avcut -p "${APPDIR}/includes/avcut_otr.profile" -i "$film" -o "$outputfile" $time  2>&1)  # Befehl ausführen
            else 
                AVCUTLOG=$(time nice -n $niceness $avcut "$film" "$outputfile" $time  2>&1) # noch avcut v0.2 mit entsprechender Parameterangabe
            fi

            echo -e; echo -n "Die Schnittpunkte befinden sich"
            AVCUTPOINTS=`echo "$AVCUTLOG" | grep "cutting points in" | awk -F '"' '{print $3}'  | sed -e 's/at: /an diesen Zeitmarken: \n    /g' | sed -e 's#s[)] #s\) \n    #g'`
            echo -e "$AVCUTPOINTS"
            if [ $LOGlevel = "2" ] ; then
                echo "avcut Command: avcut $film $outputfile $time"
                echo "avcut LOG: $AVCUTLOG"
            fi
        else
            echo "> Übergebe die Cuts an avisplit/avimerge"
            AVISPLITLOG=$(nice -n $niceness avisplit -i "$film" -o "$outputfile" -t $time -c 1>/dev/null) # Hier wird avisplit gestartet, avimerge wird on-the-fly über den Parameter -c gestartet
            if [ $LOGlevel = "2" ] ; then
                echo "avisplit Command: avisplit -i $film -o $outputfile -t $time -c"
                echo "avisplit-LOG: $AVISPLITLOG"
            fi
        fi

        if [ -f "$outputfile" ]; then
            filedestname=`basename $outputfile`
            echo -n "    L==> "
            echo -e "$filedestname wurde erstellt"
            if [ $lastjob -eq 2 ] ; then
                if [ $dsmtextnotify = "on" ] ; then
                    synodsmnotify $MessageTo "synOTR" "$filedestname ist fertig"
                fi
                if [ $dsmbeepnotify = "on" ] ; then
                        echo 2 > /dev/ttyS1 #short beep
                fi
                if [ ! -z $PBTOKEN ] ; then
                    PB_LOG=`curl $cURLloglevel --header "Access-Token:${PBTOKEN}" https://api.pushbullet.com/v2/pushes -d type=note -d title="synOTR" -d body="Film [$filedestname] ist fertig."`
                    if [ $LOGlevel = "2" ] ; then
                        echo "        PushBullet-LOG:"
                        echo "$PB_LOG"
                    elif echo "$PB_LOG" | grep -q "error"; then # für Loglevel 1 nur Errorausgabe
                        echo -n "        PushBullet-Error: "
                        echo "$PB_LOG" | jq -r '.error_code'
                    fi
                else
                    echo "        (PushBullet-TOKEN nicht gesetzt)"
                fi
                wget --timeout=30 --tries=2 -q -O - "http://${synotrdomain}/synOTR/synOTR_FILECOUNT" >/dev/null 2>&1
                needindex=1
            fi

            if [ $endgueltigloeschen = "on" ] ; then
                if [ -f "$film" ]; then
                    rm "$film" 
                fi
                if [ -f "$LOCAL_CUTLIST" ]; then       # lokale Cutlist in Downloadordner oder Dekodierordner
                    rm "$LOCAL_CUTLIST" 
                fi

            else
                # echo "Verschiebe Quellvideo und Cutlist nach $OTRkeydeldir"
                mv "$film" "$OTRkeydeldir"
                if [ -f "$LOCAL_CUTLIST" ]; then       # lokale Cutlist in Downloadordner oder Dekodierordner
                    mv "$LOCAL_CUTLIST" "$OTRkeydeldir"
                fi
            fi
        else
            if [ "$SMARTRENDERING" = "on" ]; then
                echo -e "avcut muss einen Fehler verursacht haben."
            else
                echo -e "Avisplit oder avimerge muss einen Fehler verursacht haben."
            fi
            continue=1
        fi
        }

        AC_del_tmp ()
        {
        #Hier werden nun die temporären Dateien gelöscht
        # ---------------------------------------------------------------------
        if [ "$tmp" == "" ] || [ "$tmp" == "/" ] || [ "$tmp" == "/home" ]; then
            echo -e "Achtung, bitte überprüfe die Einstellung von \$tmp"
            exit 1
        else
            if [ -d "$tmp" ] ; then
                rm -rf "$tmp"/*
            fi
        fi
        }

        AC_check_software

        # -----------------------------------------------------------------------
        # Es folgt die eigentliche Schleife zum Abarbeiten der Videos:          |
        # -----------------------------------------------------------------------
        for i in $(find "$DECODIR" -maxdepth 1 -name "*.avi" -o -name "*.mp4" -type f)
            do
                error_found=0           # Fehlertrigger zurücksetzen
                continue=0              # Cut-Skript unterbrechen
                array=0
                cutlistWithError=""     # Cutlists die, einen Fehler haben auf Null setzen
                toprated=yes            # automatisch die Cutlist mit der besten User-Bewertung benutzen?
                format=""               # Um welches Format handelt es sich? AVI, HQ, mp4 - hier auf Null setzen
                UseLocalCutlist=no      # zurücksetzen
                filename=`basename "$i"`
                vorhanden=no
                useonlytimecuts=""      # aus alternativen Cutlists (für anderes Format) sollen nur Zeit-Cuts verwendet werden
                SMARTRENDERINGold=$SMARTRENDERING # bei nicht genügend RAM wird temporär Smartrendering deaktiviert und die ursprüngliche Einstellung hier gespeichert

                if [ "$SMARTRENDERING" != "on" ]; then # avisplit kann keine mp4-Videos verarbeiten
                    if echo "$filename" | grep -q ".mp4"; then
                        echo "$filename [.mp4-Datei] kann mit avisplit / avimerge nicht geschnitten werden und wird in Zielordner verschoben. Aktiviere alternativ Smartrendering in den Einstellungen."
                        mv "$i" "$WORKDIR"
                        continue		# nächste Datei
                    fi
                fi

                echo -e ; echo "    SCHNEIDE:        ---> $filename"
                echo -n "                          "; date; echo -e

                AC_ffprobe
                AC_test
                AC_del_tmp
                AC_name

                if [ "$SMARTRENDERING" = "on" ]; then # Ist genügend RAM zum Schneiden für diese Aufnahme vorhanden?
                    PXheight=`echo "$AC_ffprobeInfo" | jq '.streams[0].height' `
                    if [ "$PXheight" -ge 700 ] && [ ${RAMmax} -ge 1000 ]; then
                        echo "Es ist genügend RAM für HQ und HD-Schnitte vorhanden."; echo -e
                    elif [ "$PXheight" -ge 700 ] && [ ${RAMmax} -ge 500 ]; then
                        audiocodec=`echo "$AC_ffprobeInfo" | jq '.streams[1].codec_name' | sed "s/\"//g" `
                        # Filme mit AC3-Tonspur können nicht mit avisplit geschnitten werden (problemanfällig / endlose Temp-Datei bei mp4box / grobe Asynchronität) und werden ungeschnitten weiterverarbeitet
                        if [ $audiocodec = "null" ] || [ $audiocodec = "ac3" ]; then # 'null', da es bereits beim mergen auf kleinen Maschinen zu Problemen kam und die Spur nicht mehr auslesbar war.
                            echo "Der Film hat eine AC3-Tonspur und das Gerät verfügt nicht über genügend RAM für Smartrendering (>= 1GB nötig, aber nur $RAMmax MB RAM verfügbar)."
                            echo "Der Film wird ungeschnitten weiterverarbeitet."
                            mv "$i" "$WORKDIR"
                            continue    # nächste Datei
                        fi
                        SMARTRENDERING="off"
                        echo "Smartrendering wird für diesen Film vorrübergehend deaktiviert (HD-Film aber nur $RAMmax MB RAM)."
                        echo "Avcut benötigt für HD-Filme mindestens 1 GB RAM. Dieser Film wird mit avisplit geschnitten."; echo -e
                    fi
                else
                    audiocodec=`echo "$AC_ffprobeInfo" | jq '.streams[1].codec_name' | sed "s/\"//g" `
                    # Filme mit AC3-Tonspur können nicht mit avisplit geschnitten werden (problemanfällig / endlose Temp-Datei bei mp4box / grobe Asynchronität) und werden ungeschnitten weiterverarbeitet
                    if [ $audiocodec = "null" ] || [ $audiocodec = "ac3" ]; then # 'null', da es bereits beim mergen auf kleinen Maschinen zu Problemen kam und die Spur nicht mehr auslesbar war.
                        echo "Der Film hat eine AC3-Tonspur und das Gerät verfügt nicht über genügend RAM für Smartrendering (>= 1GB nötig, aber nur $RAMmax MB RAM verfügbar)."
                        echo "Der Film wird ungeschnitten weiterverarbeitet."
                        mv "$i" "$WORKDIR"
                        continue    # nächste Datei
                    fi
                fi

                # Es gibt zwei Methoden, um auf lokal vorhandene Cutlist zu testen
                # sollen AC3-Remuxte Filme mit eigener Cutlist geschnitten werden, ist vorzugsweise die Methode 2 zu wählen, 
                # d.h. die Variable "OTRlocalcutlistdir" in den Einstellungen nicht zu setzen (weil sich die Filmgröße geändert hat)
                echo -n "Suche nach einer lokalen Cutlist ---> "
                if [ -d "$OTRlocalcutlistdir" ]; then
                    # Methode 1:
                    #   hier werden nur Cutlist verwendet wo Filmgröße und Name übereinstimmen
                    #   Die Variable OTRlocalcutlistdir mit dem Quellordner der Cutlist muss gesetzt sein
                    AC_getlocalcutlist_withCheck
                else
                    # Methode 2:
                    # 	es findet keine Prüfung der Cutlist statt
                    if [ -f "${i}.cutlist" ]; then 	# die Cutlist muss sich im Dekodierordner befinden und den gleichen Namen wie der Film haben (inkl. Dateiendung .avi / .mp4 vor .cutlist)
                        echo "okey"
                        LOCAL_CUTLIST="${i}.cutlist"
                        AC_getlocalcutlist_withoutCheck
                    elif [ -f "${OTRkeydir}${filename}.cutlist" ]; then # die Cutlist muss sich im Downloadordner / Quellordner befinden und den gleichen Namen wie der Film haben (inkl. Dateiendung .avi / .mp4 vor .cutlist)
                        echo "okey"
                        LOCAL_CUTLIST="${OTRkeydir}${filename}.cutlist"
                        AC_getlocalcutlist_withoutCheck
                    else
                        echo -e "Keine lokale Cutlist gefunden!"
                    fi
                fi
                
                if [ "$UseLocalCutlist" == "no" ] || [ "$vorhanden" == "no" ]; then AC_getcutlist ; fi
                if [ "$continue" == "0" ]; then AC_get_CutlistFormat ; fi
                if [ "$continue" == "0" ]; then AC_get_fps ; fi
                if [ "$continue" == "0" ]; then AC_cutlist_seriencheck ; fi
                if [ "$continue" == "0" ] ; then AC_cutlist_error ; fi
                if [ "$error_found" == "1" ] && [ "$UseLocalCutlist" == "no" ] && [ "$toprated" == "yes" ]; then 
                    #break
                    if [ "$WaitOfCutlist" == "off" ]; then
                        mv "$i" "${WORKDIR}"
                        echo "    L=> Film wird ohne Schneiden weiterverarbeitet"
                    else
                        echo "    L=> Film wird übersprungen"
                    fi
                    continue
                fi
                if [ $continue == "0" ]; then
                    if [ "$SMARTRENDERING" = "on" ]; then
                        AC_time3
                    else
                        if [ "$date_okay" = "yes" ]; then
                            AC_time1
                        elif [ "$date_okay" = "no" ]; then
                            AC_time2
                        fi
                    fi
                    AC_split
                else
                    if [ "$WaitOfCutlist" == "off" ]; then
                        mv "$i" "${WORKDIR}"
                        echo "    L=> Film wird (entsprechend der Einstellung [WaitOfCutlist=\"off\"] ohne Schneiden weiterverarbeitet"
                    fi
                fi
                AC_del_tmp
                continue=0
                
                if [ $lastjob -eq 2 ] && [ $useWORKDIR == "no" ] ; then
                    # füge Datei dem Index der Videostation hinzu:
                    synoindex -a "$outputfile"
                    if [ $dsmtextnotify = "on" ] ; then
                        title=${filename%.*}
                        sleep 1
                        synodsmnotify $MessageTo "synOTR" "Film [$title] ist fertig"
                        sleep 1
                    fi
                    if [ $dsmbeepnotify = "on" ] ; then
                        sleep 1
                        echo 2 > /dev/ttyS1 #short beep
                        sleep 1
                    fi
                    if [ ! -z $PBTOKEN ] ; then
                        PB_LOG=`curl $cURLloglevel --header "Access-Token:${PBTOKEN}" https://api.pushbullet.com/v2/pushes -d type=note -d title="synOTR" -d body="Film [$title] ist fertig."`
                        if [ $LOGlevel = "2" ] ; then
                            echo "        PushBullet-LOG:"
                            echo "$PB_LOG"
                        elif echo "$PB_LOG" | grep -q "error"; then # für Loglevel 1 nur Errorausgabe
                            echo -n "        PushBullet-Error: "
                            echo "$PB_LOG" | jq -r '.error_code'
                        fi
                    else
                        echo "        (PushBullet-TOKEN nicht gesetzt)"
                    fi
                    wget --timeout=30 --tries=2 -q -O - "http://${synotrdomain}/synOTR/synOTR_FILECOUNT" >/dev/null 2>&1
                    needindex=1
                fi
                SMARTRENDERING=$SMARTRENDERINGold
        done
    fi
elif [ $OTRcutactiv = "off" ] ; then
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
# Diese Funktion konvertiert die Filmdateien in das MP4-Format                          #
#########################################################################################

cd "$WORKDIR"

filetest=`find "$WORKDIR" -maxdepth 1 -name "*.avi" -type f`

if [ $OTRavi2mp4active = "on" ] && [ ! -z "$filetest" ] ; then
    echo -e ; echo -e; echo "==> in MP4 konvertieren:"
    IFS=$'\012'
    for i in $(find "$WORKDIR" -maxdepth 1 -name "*.avi" -type f) #
        do
            IFS=$OLDIFS
            echo -e
            title=`basename "$i"`
            pfad=`dirname "$i"`
            pfad="$pfad/"
            echo -e 
            echo "    KONVERTIERE:     ---> $title"
            echo -n "                          "; date; echo -e

            title=${title%.*}
            fileinfo=$($ffmpeg -i "$i" 2>&1)
            ffprobeInfo=$(ffprobe -v quiet -print_format json -show_format -show_streams "$i" 2>&1)

            # Errormeldung vor jason ab DSM 6.2 (wird hier abgeschnitten): ERROR: 
            # ld.so: object 'openhook.so' from LD_PRELOAD cannot be preloaded (cannot open shared object file): ignored. { …
            ffprobeInfo="{ ${ffprobeInfo#*\{}"  

            # ------- AUDIOCODEC:
            audiocodec=`echo "$ffprobeInfo" | jq '.streams[1].codec_name' | sed "s/\"//g" `
            # Workaround, sofern "codec_name" nicht mit von ffprobe ausgegeben wird:
            if [ $audiocodec = "null" ]; then
                echo "keine Codec_name in ffprobeInfo gefunden / Audiocodec wird alternativ ausgelesen:"
                ffmpegaudioinfo=$(ffmpeg -i "$i" 2>&1)
                if echo "$ffmpegaudioinfo" | grep -q "Audio: ac3" ; then
                    audiocodec=ac3
                elif echo "$ffmpegaudioinfo" | grep -q "Audio: mp3" ; then
                    audiocodec=mp3
                elif echo "$ffmpegaudioinfo" | grep -q "Audio: aac" ; then
                    audiocodec=aac
                elif echo "$ffmpegaudioinfo" | grep -q "Audio: none" ; then	# sehr experimenteller Workaround … 
                    audiocodec=ac3
                    echo "ac3-Codec wird lediglich angenommen …"
                else
                    echo "Audiocodec nicht erkannt"
                    continue
                fi
            fi
            audiofile="${WORKDIR}$title.$audiocodec"
            echo "Audiocodec:               $audiocodec"

            #	------- VIDEOCODEC:
            videocodec=`echo "$fileinfo" | grep "Video:" | $bsy awk '{print $4}'` 
            if [ $videocodec = "mpeg4" ] ; then
                    videocodec="divx"
                    vExt="tmp.m4v"; 
                elif [ $videocodec = "h264" ]; then
                    videocodec="h264"
                    vExt="h264"
                else 
                    videocodec="unknown"
                    echo "Videoformat nicht erkannt. ==> springe zu nächster Datei:"
                    continue ; 
            fi
            echo "Videocodec:               $videocodec"
            videofile="${WORKDIR}$title.$vExt"

            #	------- FRAMERATE:
            rframerate_1=`echo "$ffprobeInfo" | jq '.streams[0].r_frame_rate' | sed "s/\"//g" | awk -F '/' '{print $1}'`
            rframerate_2=`echo "$ffprobeInfo" | jq '.streams[0].r_frame_rate' | sed "s/\"//g" | awk -F '/' '{print $2}'`
            fps=$(echo | gawk '{print '$rframerate_1'/'$rframerate_2'}')
            echo "Framerate:                $fps"

            #	------- DEMUX:
            #	------- Audio extrahieren / konvertieren:
            AUDIODEMUXINFO=$(nice -n $niceness $ffmpeg -loglevel $ffloglevel -i "$i" -c:a copy -vn "$audiofile"  2>&1)
            if [ $LOGlevel = "2" ] ; then	#aufgeblähtes LOG bei AC3-Audio …
                echo "ffmpeg-AudioDemux LOG:    $AUDIODEMUXINFO"
            fi

            if [ $audiocodec = "mp3" ] ; then
                #----------------------------------------------------------------------------------------
                #       HIER SIND INDIVIDUELLE PARAMETER FÜR VERSCHIEDENE AAC-Encoder ANZUPASSEN        |
                #       - libfdk_aac hat die beste Qualität, ist aber nicht in DSM enthalten            |
                #       - Native AAC encoder hat die 2.beste Qualität, ist aber nicht in DSM enthalten  |
                #       - libfaac ist in DSM-ffmpeg enthalten, hat aber die schlechteste Qualität       |
                #----------------------------------------------------------------------------------------

                echo -e; echo " > Konvertiere Audiospur:"
                encoders=`$ffmpeg -loglevel $ffloglevel -encoders 2>&1`     # Auflistung der installierten ffmpeg-Encoder

                if $(echo "$encoders" | grep -q "libfdk_aac" ); then        # für libfdk_aac
                    echo "Erkannter Encoder:        fdk-aac [1.Wahl]"
                    if [ $normalizeAudio = "on" ] ; then
                        #	------- Audio normalisieren:
                        volumeinfo=$(ffmpeg -i "$audiofile"  -af "volumedetect" -f null - 2>&1 | awk '-F: ' '/max_volume/ { gsub(/ .*/, "", $2); print $2 }' | sed 's/-//g') # |grep max_volume | awk -F: '{ print $2 }' | sed 's/ dB//g' | sed 's/ -//g') 
                        echo "Lautstärkeanhebung um:    $volumeinfo dB"
                        convertLOG=$(nice -n $niceness $ffmpeg -threads 2 -loglevel $ffloglevel -i "$audiofile" -c:a libfdk_aac -b:a "${OTRaacqal%k}k" -af "volume=$volumeinfo"dB "$audiofile.m4a" 2>&1)
                    else
                        convertLOG=$(nice -n $niceness $ffmpeg -threads 2 -loglevel $ffloglevel -i "$audiofile" -c:a libfdk_aac -b:a "${OTRaacqal%k}k" "$audiofile.m4a" 2>&1)
                    fi
                elif $(echo "$encoders" | grep -q "AAC (Advanced Audio Coding)" ) ; then        # Native FFmpeg AAC encoder
                    echo "Erkannter Encoder:        nativ (ffmpeg > 3.0) [2.Wahl]"
                    if [ $normalizeAudio = "on" ] ; then
                        #	------- Audio normalisieren:
                        volumeinfo=$(ffmpeg -i "$audiofile"  -af "volumedetect" -f null - 2>&1 | awk '-F: ' '/max_volume/ { gsub(/ .*/, "", $2); print $2 }' | sed 's/-//g') # |grep max_volume | awk -F: '{ print $2 }' | sed 's/ dB//g' | sed 's/ -//g') 
                        echo "Lautstärkeanhebung um:    $volumeinfo dB"
                        convertLOG=$(nice -n $niceness $ffmpeg -loglevel $ffloglevel -threads 2 -i "$audiofile" -c:a aac -strict -2 -b:a "${OTRaacqal%k}k" -af "volume=$volumeinfo"dB "$audiofile.m4a" 2>&1)
                    else
                        convertLOG=$(nice -n $niceness $ffmpeg -loglevel $ffloglevel -threads 2 -i "$audiofile" -c:a aac -strict -2 -b:a "${OTRaacqal%k}k" "$audiofile.m4a" 2>&1)
                    fi
                elif $(echo "$encoders" | grep -q libfaac ) ; then      # libfaac > syno-ffmpeg
                    echo "Erkannter Encoder:        libfaac [3.Wahl]"
                    if [ 128 -gt ${OTRaacqal%k}  ]; then
                        echo "	Die aac-Zielbitrate ist mit ${OTRaacqal%k}k für den libfaac-Encoder sehr gering. Erhöhe den Wert >OTRaacqal< in den Einstellungen für eine bessere Qualität."
                    fi
                    if [ $normalizeAudio = "on" ] ; then
                        #	------- Audio normalisieren:
                        volumeinfo=$(ffmpeg -i "$audiofile"  -af "volumedetect" -f null - 2>&1 | awk '-F: ' '/max_volume/ { gsub(/ .*/, "", $2); print $2 }' | sed 's/-//g') # |grep max_volume | awk -F: '{ print $2 }' | sed 's/ dB//g' | sed 's/ -//g') 
                        echo "Lautstärkeanhebung um:    $volumeinfo dB"
                        convertLOG=$(nice -n $niceness $ffmpeg -loglevel $ffloglevel -threads 2 -i "$audiofile" -acodec libfaac -ab "${OTRaacqal%k}k"  -af "volume=$volumeinfo"dB "$audiofile.m4a" 2>&1)
                    else
                        convertLOG=$(nice -n $niceness $ffmpeg -loglevel $ffloglevel -threads 2 -i "$audiofile" -acodec libfaac -ab "${OTRaacqal%k}k" "$audiofile.m4a" 2>&1)
                    fi
                else
                    echo "  finde keinen ffmpeg-Audioencoder!"; echo "  Gebe den Pfad zu einer aac-kompatiblen ffmpeg-Version an."
                fi

                if [ $LOGlevel = "2" ] ; then
                    echo "Encoderliste:"
                    echo "$encoders"
                    echo "Audio-Konverinfo:"
                    echo "$convertLOG"
                fi

                rm "$audiofile"
                audiofile="$audiofile.m4a"
            fi

            #	------- Video extrahieren:
            VIDEODEMUXINFO=$(nice -n $niceness $ffmpeg -loglevel $ffloglevel -i "$i" -an -c:v copy "$videofile"  2>&1)
            if [ $LOGlevel = "2" ] ; then	#aufgeblähtes LOG bei AC3-Audio …
                echo "ffmpeg-VideoDemux LOG:"
                echo "$VIDEODEMUXINFO"
            fi

#	-------REMUX:
            echo -e; echo " > mp4box Remux:"

            if [ $LOGlevel = "2" ] ; then
                echo "Audiodatei:    	        $audiofile"
                echo "Videodatei:    	        $videofile"
            fi

            # Audio-Video-Syncparameter anpassen:
            if [ ! -z "$MP4BOX_DELAY" ] ; then
                if echo "$MP4BOX_DELAY" | grep -q '-' ; then        # wenn ein negativer Wert:
                    VIDEODELAY=`echo "$MP4BOX_DELAY" | sed 's/-//g'`
                    videofiledelay="$videofile#video:delay=$VIDEODELAY"
                    echo "Audio-Video-Sync:         Video wird um ${VIDEODELAY}ms verzögert"
                    audiofiledelay="$audiofile"
                else
                    AUDIODELAY=`echo "$MP4BOX_DELAY" | sed 's/-//g'`
                    audiofiledelay="$audiofile#audio:delay=$AUDIODELAY"
                    echo "Audio-Video-Sync:         Audio wird um ${AUDIODELAY}ms verzögert"
                    videofiledelay="$videofile"
                fi
                nice -n $niceness mp4box $mp4boxloglevel -add "$videofiledelay" -add "$audiofiledelay" -fps $fps -tmp "$pfad" "${pfad}${title}.mp4"
            else
                nice -n $niceness mp4box $mp4boxloglevel -add "$videofile" -add "$audiofile" -fps $fps -tmp "$pfad" "${pfad}${title}.mp4"
            fi

            #	------- Temp löschen:
            rm "$videofile"
            rm "$audiofile"

            #	------- Original löschen:
            if [ -f "${pfad}${title}.mp4" ]; then 	# nur löschen, wenn erfolgreich konvertiert:
                if [ $endgueltigloeschen = "on" ] ; then
                    rm "$i"
                else
                    mv "$i" "$OTRkeydeldir"
                fi
            else
                echo "FEHLER: Zieldatei nicht gefunden!"
            fi
            
            if [ $lastjob -eq 3 ] && [ $useWORKDIR == "no" ] ; then
                # füge Datei dem Index der Videostation hinzu:
                synoindex -a "${pfad}${title}.mp4"
                if [ $dsmtextnotify = "on" ] ; then
                    sleep 1
                    synodsmnotify $MessageTo "synOTR" "Film [$title] ist fertig"
                    sleep 1
                fi
                if [ $dsmbeepnotify = "on" ] ; then
                    sleep 1
                    echo 2 > /dev/ttyS1 #short beep
                    sleep 1
                fi
                if [ ! -z $PBTOKEN ] ; then
                    PB_LOG=`curl $cURLloglevel --header "Access-Token:${PBTOKEN}" https://api.pushbullet.com/v2/pushes -d type=note -d title="synOTR" -d body="Film [$title] ist fertig."`
                    if [ $LOGlevel = "2" ] ; then
                        echo "        PushBullet-LOG:"
                        echo "$PB_LOG"
                    elif echo "$PB_LOG" | grep -q "error"; then # für Loglevel 1 nur Errorausgabe
                        echo -n "        PushBullet-Error: "
                        echo "$PB_LOG" | jq -r '.error_code'
                    fi
                else
                    echo "        (PushBullet-TOKEN nicht gesetzt)"
                fi
                wget --timeout=30 --tries=2 -q -O - "http://${synotrdomain}/synOTR/synOTR_FILECOUNT" >/dev/null 2>&1
                needindex=1
            fi
        done
    elif [ $OTRavi2mp4active = "off" ] ; then
        echo -e ; echo -e ; echo "==> in MP4 konvertieren ist deaktiviert"
fi
IFS=$OLDIFS
sleep 1
}


OTRrename()
{
#########################################################################################
# Diese Funktion sammelt techn. Metadaten zu einem Film und benennt die                 #
# Filme nach dem vorgegebenen Muster um                                                 #
#########################################################################################

filetest=`find "$WORKDIR" -maxdepth 1 -name "*TVOON*avi" -o -name "*TVOON*mp4" -type f`
if [ -z "$filetest" ]; then
    return
fi

echo -e ; echo -e
echo "==> Umbenennen nach Schema"; echo -e
echo "    [Umbenennungssyntax: $NameSyntax]"
echo "    [Umbenennungssyntax Serientitel: $NameSyntaxSerientitel]:"

IFS=$'\012'
for i in $(find "$WORKDIR" -maxdepth 1 -name "*TVOON*avi" -o -name "*TVOON*mp4" -type f)
    do
        IFS=$OLDIFS
        missSeries=1
        serietitle=""
        episodetitle=""
        description=""
        season=""
        episode=""
        filename=`basename "$i"`
        sourcename="$filename"
        echo -e ; 
        echo "    UMBENENNEN:      ---> $filename:" 
        echo -n "                          "; date; echo -e

        fileextension="${filename##*.}"
        filename=`echo $filename | sed 's/HQ-cut/mpg.HQ/g ; s/HD-cut/mpg.HD/g ; s/mpg.HD.avi-cut/mpg.HD/g ; s/-cut/.mpg/g'` # Korrektur für geschnittene Files

        #	------------------ frage für die alternative Suche auf theTVDB.com OTR-Metadaten-Titel aus der DB ab:
        sSQL="SELECT rowid,file_original,OTRtitle,serie_season,serie_episode FROM raw WHERE file_original LIKE '${filename%.*}%' ORDER BY rowid DESC LIMIT 1" 
        sqlerg=`sqlite3 -separator $'\t' ${APPDIR}/app/etc/synOTR.sqlite "$sSQL"`

        rowid=`echo "$sqlerg" | awk -F'\t' '{print $1}' `
        originalfilename=`echo "$sqlerg" | awk -F'\t' '{print $2}' `
        OTRtitle=`echo "$sqlerg" | awk -F'\t' '{print $3}' `
        serie_seasonDB=`echo "$sqlerg" | awk -F'\t' '{print $4}' `
        serie_episodeDB=`echo "$sqlerg" | awk -F'\t' '{print $5}' `

        echo "    [Original:            $originalfilename]"; echo -e 
        echo "Fileextension:            $fileextension"

        #	------------------ technische Filmdaten via ffmpeg und ffprobe auslesen:
        fileinfo=$(ffmpeg -i "$i" 2>&1)
        ffprobeInfo=$(ffprobe -v quiet -print_format json -show_format -show_streams "$i" 2>&1)

            # Errormeldung vor jason ab DSM 6.2 (wird hier abgeschnitten): ERROR: 
            # ld.so: object 'openhook.so' from LD_PRELOAD cannot be preloaded (cannot open shared object file): ignored. { …
            ffprobeInfo="{ ${ffprobeInfo#*\{}"  

        if [ $LOGlevel = "2" ] ; then
            echo "Dateiinformation von ffmpeg ausgelesen:"; echo "$fileinfo"; echo -e
            echo "Dateiinformation von ffprobe ausgelesen:"; echo "$ffprobeInfo"; echo -e
        fi

        #	------------------ FORMAT (QUALTIÄT):
        if echo "$originalfilename" | grep -q ".HQ.avi"; then
            format=HQ
        elif echo "$originalfilename" | grep -q ".HD.avi"; then
            format=HD
        elif echo "$originalfilename" | grep -q ".mpg.mp4"; then
            format=LQ
        elif echo "$originalfilename" | grep -q ".mpg.avi"; then
            format=SD
        fi
        echo "Format:                   $format"

        #	------------------ Referenzpunkt suchen:
        ersterpunkt=`echo $filename | awk '{print index($filename, ".")}'`
        #	------------------ Titel:
        titleend=$(($ersterpunkt-4))
        titleOTR=`echo $filename | cut -c -$titleend `
        title=`echo $titleOTR | sed 's/__+/ - /g' | sed 's/_/ /g' | sed "s/  +//g"`
        #	------------------ auf Serieninformation prüfen:
        if echo "$title" | grep -q "S[0-9][0-9]E[0-9][0-9]$" ; then
            serieInfo=${title##* }	# alles, bis zum letzten Leerzeichen
            echo "                          als Serie erkannt (Serieninfo: $serieInfo)"
            # serietitle=`echo $title | sed 's/ S[0-9][0-9]E[0-9][0-9]$//g'`
            serietitle=`echo $titleOTR | sed 's/_S[0-9][0-9]E[0-9][0-9]$//g'`
            season=`echo $serieInfo | cut -c 2-3 ` #| sed -e 's/^0*//'`    # ohne führende Null > nicht nötig
            episode=`echo $serieInfo | cut -c 5-6 ` #| sed -e 's/^0*//'`
            TVDB_query
            if [ $missSeries = "1" ] ; then
                echo -e ; echo -n "Check otr-serien.de  ---> "
                OTRserien_query
            else
                if [ ! -z "$TVDB_SerieName" ] ; then
                    # title="$TVDB_SerieName"
                    serietitle="$TVDB_SerieName"
                fi
            fi
        elif  [[ "$serie_episodeDB" =~ $regInt ]] ; then # wenn in der Cutlist Serieninfos gefunden wurden (Episode ist in der DB eine Zahl), wird mit diesen weitergearbeitet
            serieInfo=${title##* }	# alles, bis zum letzten Leerzeichen
            serietitle="$titleOTR"
            season=$(printf '%02d' ${serie_seasonDB})
            episode=$(printf '%02d' ${serie_episodeDB})
            echo "                          als Serie erkannt (aus Cutlist - Serieninfo: ${titleOTR}_S${season}E${episode})"
            TVDB_query
            if [ $missSeries = "1" ] ; then
                echo -e ; echo -n "Check otr-serien.de  ---> "
                OTRserien_query
            else
                if [ ! -z "$TVDB_SerieName" ] ; then
                    # title="$TVDB_SerieName"
                    serietitle="$TVDB_SerieName"
                fi
            fi
        else # auf otr-serien.de sind auch Episoden verzeichnet, die als solche nicht durch den Dateinamen identifizierbar sind
            echo -e ; echo -n "Check otr-serien.de  ---> "
            OTRserien_query
        fi

        echo "Staffel-Nr.:              $season"
        echo "Episoden-Nr.:             $episode"
        echo "Episodentitel:            $episodetitle"
        echo "Beschreibung:             $description"

        if [ $missSeries = "0" ] ; then
            title="$serietitle"
        else
            title=`echo "$title" | sed "s/__/ - /g ; s/_/ /g ; s/  / /g ; s/ s /\'s /g ; s/\"//g ; s/://g ; s/\?//g ; s/\*//g" | sed -e "s/\<ue/ü/g ; s/\<ae/ä/g ; s/\<oe/ö/g ; s/\<UE/Ü/g ; s/\<AE/Ä/g ; s/\<OE/Ö/g ; s/\([BCDFGHJKLMNPQRSTVWXYZ]\)\(ae\)/\1ä/g ; s/\([BCDFGHJKLMNPQRSTVWXYZ]\)\(ue\)/\1ü/g ; s/\([BCDFGHJKLMNPQRSTVWXYZ]\)\(oe\)/\1ö/g ; s/\([bcdfghjklmnpqrstvwxyz]\)\(oe\)/\1ö/g ; s/\([bcdfghjklmnpqrstvwxyz]\)\(ue\)/\1ü/g ; s/\([bcdfghjklmnpqrstvwxyz]\)\(ae\)/\1ä/g ; s/\([BCDFGHJKLMNPQRSTVWXYZ]\)\(AE\)/\1Ä/g ; s/\([BCDFGHJKLMNPQRSTVWXYZ]\)\(OE\)/\1Ö/g ; s/\([BCDFGHJKLMNPQRSTVWXYZ]\)\(UE\)/\1Ü/g" | sed -f ${APPDIR}/includes/textersetzung.txt `
            #	Umlauterkennung nur nach einem Konsonanten:
                #	ersetze alle großen UE (> Ü) nach einem großen Konsonaten	s/\([BCDFGHJKLMNPQRSTVWXYZ]\)\(UE\)/\1Ü/g
                #	ersetze alle UE am Anfang der Zeile                         s/^UE/Ü/g
                #   > ersetzt durch: \< (= Anfang jedes Wortes)                 s/\<UE/Ü/g
        fi
        echo "Titel:                    $title"
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
        realduration=`echo "$ffprobeInfo" | jq '.streams[0].duration' | sed "s/\"//g" | awk -F '.' '{print $1}' `
        realduration=$(($realduration/60))
        echo "Realdauer:                $realduration"
        #	------------------ Sender:
        Channel=$(echo "$filename" | awk -F '.' '{print $3}' | awk -F '_' '{print $3}' | awk '{ print toupper($0) }') # < 2018-06-16 | $bsy tr [:lower:] [:upper:])     # ? ! ? ! ?	systeminternes /usr/bin/tr verfälscht Zeichen vox => vpx
        echo "Sender:                   $Channel"
        #	------------------ Bildwiederholrate:
        rframerate_1=`echo "$ffprobeInfo" | jq '.streams[0].r_frame_rate' | sed "s/\"//g" | awk -F '/' '{print $1}'`
        rframerate_2=`echo "$ffprobeInfo" | jq '.streams[0].r_frame_rate' | sed "s/\"//g" | awk -F '/' '{print $2}'`
        fps=$(echo | gawk '{print '$rframerate_1'/'$rframerate_2'}')
        echo "Framerate:                $fps"
        #	------------------ ScanType:
            # http://www.aktau.be/2013/09/22/detecting-interlaced-video-with-ffmpeg/
        #	scantype=$($ffmpeg -filter:v idet -frames:v 10 -an -f rawvideo -y /dev/null -i "$i" 2>&1)
        #	scantype=$(echo "$fileinfo2" | grep "Scan type" | awk -F: '{print $2}' )
            if [ $(echo "$scantype" | grep "Progressive") ] ; then
                scantype="p"
            elif [ $(echo "$scantype" | grep "not interlaced") ] ; then
                scantype="p"
            elif [ $(echo "$scantype" | grep "is interlaced") ] ; then
                scantype="i"
            fi
        scantype=""	# deaktiviert
#       echo "Scantype:         ${scantype}"
        #	------------------ Auflösung:
        height=`echo "$ffprobeInfo" | jq '.streams[0].height' `
        echo "Auflösung Höhe:           ${height}"
        width=`echo "$ffprobeInfo" | jq '.streams[0].width' `
        echo "Auflösung Breite:         ${width}"
        #	------------------ Seitenverhältnis:
        aspect_ratio=`echo "$ffprobeInfo" | jq '.streams[0].display_aspect_ratio' | sed "s/\"//g"  | sed "s/\:/-/g" `
        echo "Seitenverhältnis:         ${aspect_ratio}"
        #	------------------ Audiocodec:
        a_codec=`echo "$ffprobeInfo" | jq '.streams[1].codec_name' | sed "s/\"//g" `
        echo "Audiocodec:               ${a_codec}"
        #	------------------ Videocodec:
        v_codec=`echo "$ffprobeInfo" | jq '.streams[0].codec_name' | sed "s/\"//g" `
        echo "Videocodec:               ${v_codec}"
        
        NewName=$NameSyntax     # Muster aus Konfiguration laden

        #	------------------ Neuer Name:
        if [ $missSeries = "0" ] ; then
            if [ ! -z "$NameSyntaxSerientitel" ] ; then # nur, wenn Serientitel angepasst / gesetzt wurde
                title="$NameSyntaxSerientitel"
            else
                title="$serietitle.S${season}.E${episode} $episodetitle"	# optimiert für VideoStation
            fi
        fi

        NewName=`echo $NewName | sed "s/§tit/${title}/g"`
        NewName=`echo $NewName | sed "s/§sertit/${serietitle}/g"`
        NewName=`echo $NewName | sed "s/§epitit/${episodetitle}/g"`
        NewName=`echo $NewName | sed "s/§sta/${season}/g"`
        NewName=`echo $NewName | sed "s/§epi/${episode}/g"`
        NewName=`echo $NewName | sed "s/§dur/${duration}/g"`
        NewName=`echo $NewName | sed "s/§ylong/${YYYY}/g"`
        NewName=`echo $NewName | sed "s/§yshort/${YY}/g"`
        NewName=`echo $NewName | sed "s/§mon/${Mo}/g"`
        NewName=`echo $NewName | sed "s/§day/${DD}/g"`
        NewName=`echo $NewName | sed "s/§hou/${HH}/g"`
        NewName=`echo $NewName | sed "s/§min/${Min}/g"`
        NewName=`echo $NewName | sed "s/§cha/${Channel}/g"`
        NewName=`echo $NewName | sed "s/§qua/${format}/g"`
        NewName=`echo $NewName | sed "s/§fps/${fps}/g"`
        NewName=`echo $NewName | sed "s/§redur/${realduration}/g"`
        NewName=`echo $NewName | sed "s/§scty/${scantype}/g"`
        NewName=`echo $NewName | sed "s/§height/${height}/g"`
        NewName=`echo $NewName | sed "s/§width/${width}/g"`
        NewName=`echo $NewName | sed "s/§asra/${aspect_ratio}/g"`
        NewName=`echo $NewName | sed "s/§acod/${a_codec}/g"`
        NewName=`echo $NewName | sed "s/§vcod/${v_codec}/g"`

        if [ $missSeries = "0" ] ; then
            title="$serietitle - S${season}E${episode} $episodetitle"	# Titel für DSM-Benachrichtigung generieren
        fi
        if [ $a_codec = "ac3" ] ; then
            NewName=`echo $NewName | sed "s/§ac01/ ${a_codec}/g"`
        else
            NewName=`echo $NewName | sed "s/§ac01//g"`
        fi

        NewName="$NewName.$fileextension"
        echo -e; echo "Neuer Dateiname:          $NewName" ; echo -e

        if [ $OTRrenameactiv = "on" ] ; then
            echo "==> umbenennen:"
            if [ -f "${WORKDIR}${NewName}" ]; then      # Prüfen, ob Zielname bereits vorhanden ist
                echo "Die Datei $NewName ist bereits vorhanden und $filename wird nicht umbenannt."
                touch -t $YY$Mo$DD$HH$Min "$i"          # Dateidatum auf Ausstrahlungsdatum setzen
            else
                mv -i "$i" "${WORKDIR}${NewName}"

                #	Tags schreiben (MP4 only):
                echo -n "    L==> Tags schreiben AtomicParsley (MP4 only):"
                if [ $fileextension = "mp4" ] ; then 
                    #  --TVNetwork    (string)     Set the TV Network name
                    #  --TVShowName   (string)     Set the TV Show name
                    #  --TVEpisode    (string)     Set the TV episode/production code
                    #  --TVSeasonNum  (number)     Set the TV Season number
                    #  --TVEpisodeNum (number)     Set the TV Episode number
                    #  --description 
                    #  --artwork
                    #  --genre 
                    AtomicParsleyLOG=$(nice -n $niceness AtomicParsley "${WORKDIR}${NewName}" --overWrite --TVNetwork "$Channel" --TVShowName "$serietitle" --TVEpisode "$episodetitle" --TVSeasonNum "$season" --TVEpisodeNum "$episode" --title "$title" 2>&1)
                    if [ $LOGlevel = "2" ] ; then
                        echo "  AtomicParsleyLOG= $AtomicParsleyLOG"
                    fi
                    echo -e "   ==> fertig"
                    touch -t $YY$Mo$DD$HH$Min "${WORKDIR}${NewName}"            # Dateidatum auf Ausstrahlungsdatum setzen
                else
                    touch -t $YY$Mo$DD$HH$Min "${WORKDIR}${NewName}"            # Dateidatum auf Ausstrahlungsdatum setzen
                fi
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

                if [ $LOGlevel = "2" ] ; then
                    echo "	sSQL= $sSQL"
                fi
                sqlite3 ${APPDIR}/app/etc/synOTR.sqlite "$sSQL"
                echo "  ==> fertig"; echo "  <-------------------------"

                if [ $lastjob -eq 4 ] && [ $useWORKDIR == "no" ] ; then
                    # füge Datei dem Index der Videostation hinzu:
                    synoindex -a "${WORKDIR}${NewName}"
                    if [ $dsmtextnotify = "on" ] ; then
                        sleep 1
                        synodsmnotify $MessageTo "synOTR" "Film [$title] ist fertig"
                        sleep 1
                    fi
                    if [ $dsmbeepnotify = "on" ] ; then
                        sleep 1
                        echo 2 > /dev/ttyS1 #short beep
                        sleep 1
                    fi
                    if [ ! -z $PBTOKEN ] ; then
                        PB_LOG=`curl --header "Access-Token:${PBTOKEN}" https://api.pushbullet.com/v2/pushes -d type=note -d title="synOTR" -d body="Filme [$film] ist fertig."`
                        if [ $LOGlevel = "2" ] ; then
                            echo "PushBullet-LOG:"
                            echo "$PB_LOG"
                        elif echo "$PB_LOG" | grep -q "error"; then # für Loglevel 1 nur Errorausgabe
                            echo -n "PushBullet-Error: "
                            echo "$PB_LOG" | jq -r '.error_code'
                        fi
                    else
                        echo "PushBullet-TOKEN nicht erkannt"
                    fi
                    wget --timeout=30 --tries=2 -q -O - "http://${synotrdomain}/synOTR/synOTR_FILECOUNT" >/dev/null 2>&1
                    needindex=1
                fi
            fi
        elif [ $OTRrenameactiv = "off" ] ; then
            echo -e ; echo -e ; echo "==> umbenennen ist deaktiviert"
        else
            echo "==> Variable für Renameaktivität falsch gesetzt ==> Wert >OTRrenameactiv< in den Einstellungen überprüfen!"
        fi
    done
sleep 1
}


OTRopenrename()
{
#########################################################################################
# Diese Funktion sucht in der DB nach noch nicht erkannten Fernsehserien                #
# und prüft erneut auf otr-serien.de auf evtl. Verfügbarkeit                            #
#########################################################################################

IFS=$'\n';              #   ==>	den 'Internal Field Separator' so verändern, dass Felder nur noch durch Zeilenumbrüche (und nicht [zusätzlich] durch Leerzeichen) getrennt werden.
NewName=$NameSyntax     #   Muster aus Konfiguration laden
if [ $OTRrenameactiv = "on" ] && [ $firstrunonday == "1" ] ; then
    echo -e ; echo -e
    echo "==> OTRopenrename via SQLite [Umbenennungssyntax: $NameSyntax]"
    echo "                             [Umbenennungssyntax Serientitel: $NameSyntaxSerientitel]:"
    echo "    undefinierte Serien suchen:"

    sSQL="SELECT rowid,file_rename,file_original,checkcount,format,titel,datum,zeit,dauer,sender,fps,realdauer,scantype,pix_height,pix_width,aspect_ratio,v_codec,a_codec  FROM raw WHERE miss_series=1 AND NOT lastcheckday=$today AND checkcount<8" 

    sqlerg=`sqlite3 -separator $'\t' ${APPDIR}/app/etc/synOTR.sqlite "$sSQL"`
    IFS=$'\012'
    for entry in $sqlerg; do
        IFS=$OLDIFS
        NewName=$NameSyntax     # Muster aus Konfiguration laden / vorherigen Schleifendurchlauf zurücksetzen
        # Datensatzfelder separieren:
        id=`echo "$entry" | awk -F'\t' '{print $1}' `
        file_rename=`echo "$entry" | awk -F'\t' '{print $2}' `
        filename=`echo "$entry" | awk -F'\t' '{print $3}' `
        checkcount=`echo "$entry" | awk -F'\t' '{print $4}' `
        format=`echo "$entry" | awk -F'\t' '{print $5}' `
        title=`echo "$entry" | awk -F'\t' '{print $6}' `
        YYYY=`echo "$entry" | awk -F'\t' '{print $7}' | awk -F'-' '{print $1}'`
        YY=`echo "$entry" | awk -F'\t' '{print $7}' | awk -F'-' '{print $1}' | cut -c 3-4`
        Mo=`echo "$entry" | awk -F'\t' '{print $7}' | awk -F'-' '{print $2}'`
        DD=`echo "$entry" | awk -F'\t' '{print $7}' | awk -F'-' '{print $3}'`
        HH=`echo "$entry" | awk -F'\t' '{print $8}' | awk -F':' '{print $1}'`
        Min=`echo "$entry" | awk -F'\t' '{print $8}' | awk -F':' '{print $2}'`
        duration=`echo "$entry" | awk -F'\t' '{print $9}' `
        Channel=`echo "$entry" | awk -F'\t' '{print $10}' `
        fps=`echo "$entry" | awk -F'\t' '{print $11}' `
        realduration=`echo "$entry" | awk -F'\t' '{print $12}' `
        scantype=`echo "$entry" | awk -F'\t' '{print $13}' `
        height=`echo "$entry" | awk -F'\t' '{print $14}' `
        width=`echo "$entry" | awk -F'\t' '{print $15}' `
        aspect_ratio=`echo "$entry" | awk -F'\t' '{print $16}' `
        v_codec=`echo "$entry" | awk -F'\t' '{print $17}' `
        a_codec=`echo "$entry" | awk -F'\t' '{print $18}' `

        fileextension="${file_rename##*.}"

        if [ -f "${DESTDIR}/$file_rename" ]; then
            if [ $LOGlevel = "1" ] ; then
                echo "    -> prüfe: "$filename
            elif [ $LOGlevel = "2" ] ; then
                echo "    -> SQL-Abfrage: "$sSQL
                echo "    -> prüfe Datei: "$filename
                echo "       ${DESTDIR}/$file_rename vorhanden"
                echo "    -> otr-serien Abfrage: http://www.otr-serien.de/myapi/reverseotrkeycheck.php?otrkey=$filename&who=synOTR" ; echo -e
            fi

            serieninfo=$(wget --timeout=60 --tries=2 -q -O - "http://www.otr-serien.de/myapi/reverseotrkeycheck.php?otrkey=$filename&who=synOTR" )

            if [ $LOGlevel = "2" ] ; then
                echo "       Rückgabewert von otr-serien.de ==>	$serieninfo" ; echo -e
            fi

            serieninfo="{ ${serieninfo#*\{}" # 2018-02-13 Rückgabe von otr-serien.de wurde scheinbar geändert (vorgelagerte Infos vor jason-Container > werden jetzt abgeschnitten)
            #	Zeichenkorrektur:
            serieninfo=`echo $serieninfo | sed "s/<!DOCTYPE html>//g" | sed -f ${APPDIR}/includes/decode.sed `
            OTRID=`echo "$serieninfo" | awk -F, '{print $1}' | awk -F: '{print $2}' | sed "s/\"//g"`

            if echo "$serieninfo" | grep -q "Keine Serien zuordnung vorhanden"; then
                echo -e "       L=> kein Suchergebnis"
                sSQLupdate="UPDATE raw SET lastcheckday=$today, checkcount=$(($checkcount+1)) WHERE rowid=$id"
                if [ $LOGlevel = "2" ] ; then
                    echo "       $serieninfo"
                    echo "    -> SQLupdate: $sSQLupdate"
                fi
                sqlite3 ${APPDIR}/app/etc/synOTR.sqlite "$sSQLupdate"
            elif echo "$serieninfo" | grep -q "Kein OTR DB Eintrag vorhanden"; then
                echo -e "       L=> Film konnte von OTRserien nicht identifiziert werden (wahrscheinlich wurde der Film manuell umbenannt) --> Standardumbenennung wird verwendet"
                sSQLupdate="UPDATE raw SET lastcheckday=$today, checkcount=$(($checkcount+1)) WHERE rowid=$id"
                if [ $LOGlevel = "2" ] ; then
                    echo "       $serieninfo"
                    echo "    -> SQLupdate: $sSQLupdate"
                fi
                sqlite3 ${APPDIR}/app/etc/synOTR.sqlite "$sSQLupdate"
            elif [ -z "$serieninfo" ] ; then
                echo -e "       >>> Keine Serverantwort <<<"
                sSQLupdate="UPDATE raw SET lastcheckday=$today, checkcount=$(($checkcount+1)) WHERE rowid=$id"
                if [ $LOGlevel = "2" ] ; then
                    echo "    -> SQLupdate: $sSQLupdate"
                fi
                sqlite3 ${APPDIR}/app/etc/synOTR.sqlite "$sSQLupdate"
#           elif [ ! -z "$serieninfo" ] ; then      # ist nicht zuverlässig < 2018-06-14
            elif [[ "$OTRID" =~ $regInt ]]; then    # Ist die OTR-Id eine echte Zahl?
                if jq -e . >/dev/null 2>&1 <<<"$serieninfo"; then   # prüfen, ob korrektes JSON-Format verarbeitet werden kann (https://stackoverflow.com/questions/46954692/check-if-string-is-a-valid-json-with-jq)
                    echo -e "gefunden:"
                    echo "OTRID:            $OTRID"
                    serietitle=`echo "$serieninfo" | jq -r '.Serie' | sed "s/://g" `
                    echo "serietitle:       $serietitle"
                    season=`echo "$serieninfo" | awk -F, '{print $3}' | awk -F: '{print $2}' | sed "s/\"//g"`
                    season="$(printf '%02d' "$season")"                     # 2stellig mit führender Null
                    echo "season:           $season"
                    episode=`echo "$serieninfo" | awk -F, '{print $4}' | awk -F: '{print $2}' | sed "s/\"//g"`
                    episode="$(printf '%02d' "$episode")"                   # 2stellig mit führender Null
                    echo "episode:          $episode"
                    episodetitle=`echo "$serieninfo" | jq -r '.Folgenname' | sed "s/://g" | sed "s/\?//g" `
                    echo "episodetitle:     $episodetitle"
                    description=`echo "$serieninfo" | jq -r '.Folgenbeschreibung' | sed "s/:/ -/g" `
                    echo "description:      $description"

                    if [ ! -z "$NameSyntaxSerientitel" ] ; then # nur, wenn Serientitel angepasst / gesetzt wurde
                        title="$NameSyntaxSerientitel"
                    else
                        title="$serietitle.S${season}.E${episode} $episodetitle"	# optimiert für VideoStation
                    fi

                    #	------------------ Neuer Name:
                    NewName=`echo $NewName | sed "s/§tit/${title}/g"`
                    title="$serietitle - S${season}E${episode} $episodetitle"	# Titel für DSM-Benachrichtigung generieren
                    NewName=`echo $NewName | sed "s/§dur/${duration}/g"`
                    NewName=`echo $NewName | sed "s/§tit/${title}/g"`
                    NewName=`echo $NewName | sed "s/§ylong/${YYYY}/g"`
                    NewName=`echo $NewName | sed "s/§yshort/${YY}/g"`
                    NewName=`echo $NewName | sed "s/§mon/${Mo}/g"`
                    NewName=`echo $NewName | sed "s/§day/${DD}/g"`
                    NewName=`echo $NewName | sed "s/§hou/${HH}/g"`
                    NewName=`echo $NewName | sed "s/§min/${Min}/g"`
                    NewName=`echo $NewName | sed "s/§cha/${Channel}/g"`
                    NewName=`echo $NewName | sed "s/§qua/${format}/g"`
                    NewName=`echo $NewName | sed "s/§fps/${fps}/g"`
                    NewName=`echo $NewName | sed "s/§redur/${realduration}/g"`
                    NewName=`echo $NewName | sed "s/§scty/${scantype}/g"`
                    NewName=`echo $NewName | sed "s/§height/${height}/g"`
                    NewName=`echo $NewName | sed "s/§width/${width}/g"`
                    NewName=`echo $NewName | sed "s/§asra/${aspect_ratio}/g"`
                    NewName=`echo $NewName | sed "s/§acod/${a_codec}/g"`
                    NewName=`echo $NewName | sed "s/§vcod/${v_codec}/g"`
                    NewName=`echo $NewName | sed "s/§sertit/${serietitle}/g"`
                    NewName=`echo $NewName | sed "s/§epitit/${episodetitle}/g"`
                    NewName=`echo $NewName | sed "s/§sta/${season}/g"`
                    NewName=`echo $NewName | sed "s/§epi/${episode}/g"`
                    if [ $a_codec = "ac3" ] ; then
                        NewName=`echo $NewName | sed "s/§ac01/ ${a_codec}/g"`
                    else
                        NewName=`echo $NewName | sed "s/§ac01//g"`
                    fi

                    NewName="$NewName.$fileextension"
                    echo -e; echo " Neuer Dateiname:         $NewName" ; echo -e
                    echo "  ==> umbenennen:"

                    if [ -f "${DESTDIR}/$NewName" ]; then       # Prüfen, ob Zielname bereits vorhanden ist
                        echo "      Die Datei $NewName ist bereits vorhanden und $file_rename wird nicht umbenannt."
                        sSQLupdate="UPDATE raw SET lastcheckday=$today, checkcount=$(($checkcount+1)), miss_series=0 WHERE rowid=$id"
                        sqlite3 ${APPDIR}/app/etc/synOTR.sqlite "$sSQLupdate"
                        if [ $LOGlevel = "2" ] ; then
                            echo "  sSQLupdate= $sSQLupdate"
                        fi
                    else
                        mv -i "${DESTDIR}/$file_rename" "${DESTDIR}/$NewName"

                        #	Tags schreiben (MP4 only):
                        echo -n "   L==> Tags schreiben AtomicParsley (MP4 only):"

                        if [ $fileextension = "mp4" ] ; then 
                            #  --TVNetwork    (string)     Set the TV Network name
                            #  --TVShowName   (string)     Set the TV Show name
                            #  --TVEpisode    (string)     Set the TV episode/production code
                            #  --TVSeasonNum  (number)     Set the TV Season number
                            #  --TVEpisodeNum (number)     Set the TV Episode number
                            #  --description 
                            #  --artwork
                            #  --genre 
                            AtomicParsleyLOG=$(nice -n $niceness AtomicParsley "${DESTDIR}/$NewName" --overWrite --TVNetwork "$Channel" --TVShowName "$serietitle" --TVEpisode "$episodetitle" --TVSeasonNum "$season" --TVEpisodeNum "$episode" --title "$title" 2>&1)
                            if [ $LOGlevel = "2" ] ; then
                                echo "  AtomicParsleyLOG= $AtomicParsleyLOG"
                            fi
                            echo -e " ==> fertig"
                            
                            touch -t $YY$Mo$DD$HH$Min "${DESTDIR}/$NewName"             # Dateidatum auf Ausstrahlungsdatum setzen
                        else
                            touch -t $YY$Mo$DD$HH$Min "${DESTDIR}/$NewName"             # Dateidatum auf Ausstrahlungsdatum setzen
                        fi

                        echo "   L==> umbenannt von"; echo "        $filename"; echo "      zu"; echo "         $NewName"
                        echo -e; echo " ------------------------->"; echo -n "	Datenbank schreiben ==> "
                        # Hochkommas für SQL-String maskieren (SQLite3 einfache Hochkommas maskieren durch hinzufügen eines weiteren):
                        NewNameMask=$( echo "$NewName" | sed "s/'/''/g" )
                        serietitleMask=$(echo "$serietitle" | sed "s/'/''/g")
                        episodetitleMask=$(echo "$episodetitle" | sed "s/'/''/g")
                        descriptionMask=$(echo "$description" | sed "s/'/''/g")

                        sSQLupdate="UPDATE raw SET file_rename='$NewNameMask', otrid='$OTRID', serie_titel='$serietitleMask', serie_season='$season', serie_episode='$episode', serie_episodentitel='$episodetitleMask', serie_episodebeschreibung='$descriptionMask',  lastcheckday=$today, checkcount=$(($checkcount+1)), miss_series=0 WHERE rowid=$id"

                        sqlite3 ${APPDIR}/app/etc/synOTR.sqlite "$sSQLupdate"
                        if [ $LOGlevel = "2" ] ; then
                            echo "	sSQLupdate= $sSQLupdate"
                        fi
                        echo "fertig"; echo "   <-------------------------"

                        if [ $lastjob -eq 4 ] ; then
                            # Videostation Index korrigieren:
                            synoindex -n "${DESTDIR}/$NewName" "${DESTDIR}/$filename"
                        
                            if [ $dsmtextnotify = "on" ] ; then
                                sleep 1
                                synodsmnotify $MessageTo "synOTR" "Film [$title] ist fertig"
                                sleep 1
                            fi
                            if [ $dsmbeepnotify = "on" ] ; then
                                sleep 1
                                echo 2 > /dev/ttyS1 #short beep
                                sleep 1
                            fi
                            wget --timeout=30 --tries=2 -q -O - "http://${synotrdomain}/synOTR/synOTR_FILECOUNT" >/dev/null 2>&1
                            needindex=1
                        fi
                        wget --timeout=30 --tries=2 -q -O - "http://${synotrdomain}/synOTR/synOTR_FILECOUNT_OTRSERIENopen" >/dev/null 2>&1
                    fi
                else
                    # JSON nicht lesbar
                    echo -e "Serverantwort konnte nicht verarbeitet werden (kein kompatibles JSON)"
                    echo "                  $serieninfo"
                    sSQLupdate="UPDATE raw SET lastcheckday=$today, checkcount=$(($checkcount+1)) WHERE rowid=$id"
                    if [ $LOGlevel = "2" ] ; then
                        echo "  ==> SQLupdate: $sSQLupdate"
                    fi
                    sqlite3 ${APPDIR}/app/etc/synOTR.sqlite "$sSQLupdate"
                fi
            else
                echo -e "unbekannter Fehler …"
                echo "                  $serieninfo"
                sSQLupdate="UPDATE raw SET lastcheckday=$today, checkcount=$(($checkcount+1)) WHERE rowid=$id"
                if [ $LOGlevel = "2" ] ; then
                    echo "  ==> SQLupdate: $sSQLupdate"
                fi
                sqlite3 ${APPDIR}/app/etc/synOTR.sqlite "$sSQLupdate"
            fi
            sleep 15 # Wartezeit in Sekunden, um die Serverlast auf otr-serien.de zu reduzieren
            # date
        else
            echo "    -> nicht gefunden: $file_rename"
            echo "       L==> Datei liegt nicht mehr im Zielordner [$WORKDIR]"
            sSQLupdate="UPDATE raw SET lastcheckday=$today, checkcount=$(($checkcount+1)), miss_series=0 WHERE rowid=$id"
            sqlite3 ${APPDIR}/app/etc/synOTR.sqlite "$sSQLupdate"
            if [ $LOGlevel = "2" ] ; then
                echo "       sSQLupdate= $sSQLupdate"
            fi
        fi
    done
fi
sleep 1
}


UPDATE()
{
#########################################################################################
# Diese Funktion sucht nach einer neuen Version und sorgt für die Dateiintegrität       #
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
        sqlinst="CREATE TABLE \"raw\" (\"timestamp\" timestamp NOT NULL  DEFAULT (CURRENT_TIMESTAMP) ,\"file_original\" varchar(500) ,\"file_rename\" varchar(500) ,\"miss_series\" tinyint(1) ,\"format\" varchar(5) ,\"titel\" varchar(500) ,\"datum\" date ,\"zeit\" time ,\"dauer\" int(5) ,\"sender\" varchar(100) ,\"otrid\" int(11) ,\"serie_titel\" varchar(500) ,\"serie_season\" int(11) ,\"serie_episode\" int(11) ,\"serie_episodentitel\" varchar(500) ,\"serie_episodebeschreibung\" varchar(10000) ,\"lastcheckday\" int(3) ,\"checkcount\" int(3) DEFAULT (null) ,\"fps\" Numeric(500) ,\"realdauer\" int(5) ,\"scantype\" varchar(2) ,\"pix_height\" int(5) ,\"pix_width\" int(5) ,\"aspect_ratio\" varchar(20) ,\"v_codec\" varchar(100) ,\"a_codec\" varchar(100) ,\"OTRtitle\" varchar(500) ,\"OTRcomment\" varchar(10000) ,\"cutlist_ID\" int(20) ); CREATE INDEX \"IDX_raw_check\" ON \"raw\" (\"lastcheckday\" ASC, \"checkcount\" ASC);"
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
        sqliteinfo=$(sqlite3 ${APPDIR}/app/etc/synOTR.sqlite "$sSQL")
        echo "    > Updatedatensatz eingefügt ($sqliteinfo)"
    fi

    sqlinstNewTable="CREATE TABLE IF NOT EXISTS \"tvdb\" (\"timestamp\" timestamp NOT NULL  DEFAULT (CURRENT_TIMESTAMP) ,\"APIKEY\" varchar(500) ,\"TOKEN\" varchar(2000) ,\"day_created\" int(3) ); "
    sqliteinfo=$(sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "$sqlinstNewTable")
    echo "    $sqliteinfo"

    sqlerg=$(sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "SELECT rowid FROM tvdb WHERE rowid=1")
    if [ "$sqlerg" == "" ] ; then # prüfen, ob der Datensatz vorhanden ist, ggfls. einfügen
        if [ "$TVDB_APIKEY" == "" ] ; then
            # voreingesteller API-Key, sofern kein persönlicher verwendet wird (Rot13):
            TVDB_APIKEY=`echo "6P0N9Q9NORS401P7" | tr [a-zA-Z] [n-za-mN-ZA-M]`
        fi
        sSQL="INSERT INTO tvdb ( APIKEY, timestamp, day_created) VALUES  ( '$TVDB_APIKEY', datetime('now','localtime'), $(($today-1)) )"
        sqliteinfo=$(sqlite3 ${APPDIR}/app/etc/synOTR.sqlite "$sSQL")
    fi

    # Prüfen (und ggf. einfügen) der Spalten OTRtitle und OTRcomment:
    sqlerg=`sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "SELECT * FROM sqlite_master WHERE TYPE='table' AND tbl_name = 'raw' AND SQL LIKE '%OTRtitle%' "` 
    
    if [ "$sqlerg" == "" ] ; then 
        echo "    > Spalten (OTRtitle, OTRcomment) werden hinzugefügt"
        sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "ALTER TABLE raw ADD COLUMN \"OTRtitle\" VARCHAR "
        sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "ALTER TABLE raw ADD COLUMN \"OTRcomment\" VARCHAR "
    fi
    
    # Prüfen (und ggf. einfügen) der Spalte cutlist_ID:
    sqlerg=`sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "SELECT * FROM sqlite_master WHERE TYPE='table' AND tbl_name = 'raw' AND SQL LIKE '%cutlist_ID%' "` 
    
    if [ "$sqlerg" == "" ] ; then 
        echo "    > Spalte (cutlist_ID) wird hinzugefügt"
        sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "ALTER TABLE raw ADD COLUMN \"cutlist_ID\" VARCHAR "
    fi

    IFS=$OLDIFS
    sleep 1
    }

CREATEDB

# Installationstrigger beinhaltet folgende anonymen Geräteinfos:
# DSM-Build / Prüfsumme der MAC-Adresse als Hardware-ID [anonyme Zahlenfolge 
# um Installationen zu zählen] / Architektur / Geräte-Typ / synOTR-Version) 
# ---------------------------------------------------------------------
    if [ $DEBUGINFO = "on" ] ; then
        restore_ENV
        curl --max-time 60 -i -X POST -d '{"requests":["?idsite=11&url=http://'${synotrdomain}'/synOTR/installwatch.php&dimension1='${machinetyp}'&dimension2='${dsmbuild}'&dimension3='${sysID}_${device}'&dimension4='${device}'&dimension5='${CLIENTVERSION}'&rec=1&uid='${sysID}_${device}'&action_name=synOTR Shell-run/'${sysID}_${device}_${dsmbuild}_${machinetyp}_idx${idx}_synOTR${CLIENTVERSION}-${DevChannel}'&ua=curl/7.9.8 (i686-pc-linux-gnu)&new_visit=1"]}' http://$synotrdomain/piwik/piwik.php &>/dev/null 	#  http://developer.piwik.org/api-reference/tracking-api	# curl an dieser Stelle, da nach Einbindung der Librarys auf ARM eine Inkompatibilität vorhanden ist. ==> Alternative: Library-Path sichern und an späterer Stelle temporär rückspielen
        synOTR_ENV
    fi

# Versionsdaten aus DB lesen: 
# Versionscheck wird für das Update (SPK) nicht mehr verwendet,
# aber die Ermittlung des ersten Programmlauf des Tages
# ---------------------------------------------------------------------
sSQL="SELECT rowid,VERSIONcurrent,VERSIONserver,lastcheckday FROM checkversion WHERE rowid=1 "
sqlerg=`sqlite3 -separator $'\t' ${APPDIR}/app/etc/synOTR.sqlite "$sSQL"`

lastcheckday=`echo "$sqlerg" | awk -F'\t' '{print $4}' `

ONLINEVERSION=$(wget --timeout=30 --tries=2 -q -O - http://$synotrdomain/synOTR/VERSION2 | /usr/bin/tr -d "\r")
ONLINEVERSION=`echo "$ONLINEVERSION" | grep "$DevChannel" | awk -F" " '{print $1}'`

# Beim ersten Programmlauf des Tages auf Update prüfen: 
# ---------------------------------------------------------------------
#if ( [ "$lastcheckday" -ne $today ] || [ "$lastcheckday" == "" ] )  || ( [ $forceupdate == "on" ] ); then
if [ "$lastcheckday" -ne $today ] || [ "$lastcheckday" == "" ] ; then
    firstrunonday=1     # Der erste Programmlauf des Tages > Trigger u.a. für Videostation Reindexierung, openrename …
    IFS=$'\012'

    # Datenbank aktualisieren:
#   sSQLupdate="UPDATE checkversion SET VERSIONcurrent='$CLIENTVERSION', VERSIONserver='$ONLINEVERSION', lastcheckday=$today, timestamp=(datetime('now','localtime')) WHERE rowid=1"
    sSQLupdate="UPDATE checkversion SET VERSIONcurrent='$CLIENTVERSION', VERSIONserver='SPK', lastcheckday=$today, timestamp=(datetime('now','localtime')) WHERE rowid=1"
    sqlite3 ${APPDIR}/app/etc/synOTR.sqlite "$sSQLupdate"

else
    firstrunonday=0
fi

IFS=$OLDIFS
sleep 1
}


MOVE2DESTDIR()
{
#########################################################################################
# Diese Funktion verschiebt die fertigen Filme in den Zielordner                        #
#########################################################################################

filetest=`find "${WORKDIR}" -maxdepth 1 -name "*.avi" -o -name "*.mp4" -type f`
if [ $useWORKDIR == "yes" ] && [ ! -z "$filetest" ]; then
    echo -e; echo "==> Verschiebe fertige Filme in Zielordner"
    IFS=$'\012'
    for i in $(find "${WORKDIR}" -maxdepth 1 -name "*.avi" -o -name "*.mp4" -type f)
        do
            IFS=$OLDIFS
            filename=`basename "$i"`

            if [ ! -f "${DESTDIR}/${filename}" ]; then
                mv "$i" "${DESTDIR}"
                echo "    L=> verschiebe ${filename}"
                # füge Datei dem Index der Videostation hinzu:
                synoindex -a "${DESTDIR}/${filename}"
                
                if [ $dsmtextnotify = "on" ] ; then
                    sleep 1
                    synodsmnotify $MessageTo "synOTR" "Film [$filename] ist fertig"
                    sleep 1
                fi
                if [ $dsmbeepnotify = "on" ] ; then
                    sleep 1
                    echo 2 > /dev/ttyS1 #short beep
                    sleep 1
                fi
                if [ ! -z $PBTOKEN ] ; then
                    PB_LOG=`curl $cURLloglevel --header "Access-Token:${PBTOKEN}" https://api.pushbullet.com/v2/pushes -d type=note -d title="synOTR" -d body="Film [$filename] ist fertig."`
                    if [ $LOGlevel = "2" ] ; then
                        echo "        PushBullet-LOG:"
                        echo "$PB_LOG"
                    elif echo "$PB_LOG" | grep -q "error"; then # für Loglevel 1 nur Errorausgabe
                        echo -n "        PushBullet-Error: "
                        echo "$PB_LOG" | jq -r '.error_code'
                    fi
                else
                    echo "        (PushBullet-TOKEN nicht gesetzt)"
                fi

                wget --timeout=30 --tries=2 -q -O - "http://${synotrdomain}/synOTR/synOTR_FILECOUNT" >/dev/null 2>&1
                needindex=1
            else
                # prüfen und zählen von gleichnamigen Filmen in der DB:
                # ToDo: evtl. mit einer Zählschleife von Dateinamen im Zielordner realisieren => wäre von DB unabhängig und sicherer
                filenameMask=$(echo "$filename" | sed "s/'/''/g")
                sSQL="SELECT count(rowid) FROM raw WHERE file_rename='$filenameMask' "
                
                FilenameCount=`sqlite3 -separator $'\t' ${APPDIR}/app/etc/synOTR.sqlite "$sSQL"`

                if [ "$FilenameCount" == "0" ] || [ -z "$FilenameCount" ]; then
                    echo "    Film [$filename] kann nicht in Zielordner verschoben werden, da er darin bereits vorhanden ist und in der Datenbank kein Zählgrundlage gefunden wurde!"
                else
                    filename=`echo "$filename" | sed "s/.avi/ \(${FilenameCount}\).avi/g" | sed "s/.mp4/ \(${FilenameCount}\).mp4/g" `
                    echo "    Dateiname wird um einen Zähler ergänzt (${FilenameCount}), da die Datei bereits im Zielordner existiert."
                    if [ ! -f "${DESTDIR}/${filename}" ]; then
                        mv "$i" "${DESTDIR}/${filename}"
                        echo "    L=> verschiebe ${filename}"
                        # füge Datei dem Index der Videostation hinzu:
                        synoindex -a "${DESTDIR}//${filename}"

                        if [ $dsmtextnotify = "on" ] ; then
                            sleep 1
                            synodsmnotify $MessageTo "synOTR" "Film [$filename] ist fertig"
                            sleep 1
                        fi
                        if [ $dsmbeepnotify = "on" ] ; then
                            sleep 1
                            echo 2 > /dev/ttyS1 #short beep
                            sleep 1
                        fi
                        if [ ! -z $PBTOKEN ] ; then
                            PB_LOG=`curl $cURLloglevel --header "Access-Token:${PBTOKEN}" https://api.pushbullet.com/v2/pushes -d type=note -d title="synOTR" -d body="Film [$filename] ist fertig."`
                            if [ $LOGlevel = "2" ] ; then
                                echo "        PushBullet-LOG:"
                                echo "$PB_LOG"
                            elif echo "$PB_LOG" | grep -q "error"; then # für Loglevel 1 nur Errorausgabe
                                echo -n "        PushBullet-Error: "
                                echo "$PB_LOG" | jq -r '.error_code'
                            fi
                        else
                            echo "        (PushBullet-TOKEN nicht gesetzt)"
                        fi
                        wget --timeout=30 --tries=2 -q -O - "http://${synotrdomain}/synOTR/synOTR_FILECOUNT" >/dev/null 2>&1
                        needindex=1
                    else
                        echo "    Alternativer Dateiname [$filename] ebenfalls bereits vergeben …"
                    fi
                fi
            fi
        done
fi

#   DEV:
#        echo "run FileBot:"
#        filebot -script 'fn:amc' /volume1/video/_synOTR/FileBot_input --output '/volume1/video/+NEU' --action move --conflict index --lang de --def 'music=y' 'unsorted=y' 'deleteAfterExtract=y' 'minFileSize=0' 'seriesFormat={n}.S{s.pad(2)+'\''.E'\''}{e.pad(2)} - {t}' 'animeFormat={n} ({y}){ext}' 'movieFormat={n} ({y})' 'musicFormat={n} ({y}){ext}' 'unsortedFormat={fn}.{ext}' --log all --log-file '/volume1/@appstore/filebot-node/data/filebot.log'
}


FRESHUPMEDIAINDEX()
{
#########################################################################################
# Diese Funktion startet die Medienindexierung nach Bedarf                              #
# INFO: http://www.synology-wiki.de/index.php/Problembehebung_DLNA-Server_(Index)       #
#########################################################################################

if [ -f "/usr/syno/bin/synoindex" ] && [ $firstrunonday == "1" ] && [ $reindex == "1" ] ; then # prüfen, ob Mediaserver/VideoStation installiert und Reindexierung nötig ist
    echo -e; echo "==> vollständige Aktualisierung des Zielordner-Indexes für die VideoStation / MediaServer"
    synoindex -R video:"$DESTDIR"
fi
}


PURGELOG()
{
#########################################################################################
# Diese Funktion löscht zu erst alle leeren Logs und anschließend die überzähligen      #
#########################################################################################

if [ -z $LOGmax ]; then
    return
fi

logdir="${DECODIR}/_LOGsynOTR/"

# leere Logs löschen:
for i in `ls -tr "${logdir}" | egrep -o '^synOTR.*.log$' `                   # Auflistung aller LOG-Dateien
    do
        if [ $( cat "${logdir}$i" | tail -n9 | head -n4 | wc -c ) -le 15 ] && cat "${logdir}$i" | grep -q "synOTR ENDE" ; then
        #if [ $( cat "${LOGDIR}$i" | sed -n "/Funktionsaufrufe/,/synOCR ENDE/p" | wc -c ) -le 210 ] && cat "${LOGDIR}$i" | grep -q "synOCR ENDE" ; then
            if [ $endgueltigloeschen = "on" ] ; then
                rm "${logdir}$i"
            else
                mv "${logdir}$i" "$OTRkeydeldir"
            fi
        fi
    done

# überzählige Logs löschen:
count2del=$( expr $( ls -t "${logdir}" | egrep -o '^synOTR.*.log$' | wc -l ) - $LOGmax ) # wie viele Dateien sind überzählig
if [ $count2del -ge 0 ]; then
    for i in `ls -tr "${logdir}" | egrep -o '^synOTR.*.log$' | head -n${count2del} `
        do
            if [ $endgueltigloeschen = "on" ] ; then
                rm "${logdir}$i"
            else
                mv "${logdir}$i" "$OTRkeydeldir"
            fi
        done
fi

# überzählige searches löschen:
count2del=$( expr $(ls -t "${logdir}" | egrep -o '^search.*.xml$' | wc -l) - $LOGmax )
if [ ${count2del} -ge 0 ]; then
    for i in `ls -tr "${logdir}" | egrep -o '^search.*.xml$' | head -n${count2del} `
        do
            if [ $endgueltigloeschen = "on" ] ; then
                rm "${logdir}$i"
            else
                mv "${logdir}$i" "$OTRkeydeldir"
            fi
        done
fi

# überzählige cutlists löschen:
count2del=$( expr $(ls -t "${logdir}" | egrep -o '.*.cutlist$' | wc -l) - $LOGmax )
if [ ${count2del} -ge 0 ]; then
    for i in `ls -tr "${logdir}" | egrep -o '.*.cutlist$' | head -n${count2del} `
        do
            if [ $endgueltigloeschen = "on" ] ; then
                rm "${logdir}$i"
            else
                mv "${logdir}$i" "$OTRkeydeldir"
            fi
        done
fi

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
#   OTRopenrename	# 2019-10 deaktivert, da otr-serien.de die Pflege neuer Serien eingestellt hat
    MOVE2DESTDIR
    FRESHUPMEDIAINDEX
    PURGELOG

    echo -e; echo -e
    echo "    -----------------------------------"
    echo "    |       ==> synOTR ENDE <==       |"
    echo "    -----------------------------------"
    echo -e; echo "    Gesamtzeit: $(sec_to_time $(expr $(date +%s)-${UNIXTIME}) )"

exit
