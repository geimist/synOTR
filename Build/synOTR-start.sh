#!/bin/sh
# /usr/syno/synoman/webman/3rdparty/synOTR/synOTR-start.sh
# wechselt in synOTR-Verzeichnis und startet synOTR mit bzw. ohne LOG (je nach Konfiguration)

# wurde das Skript von der GUI aufgerufen (Aufruf mit Parameter "GUI" für )?
    callFrom=$1
    if [ -z $callFrom ] ; then
        callFrom="shell"
    else
        callFrom="GUI"
    fi

# Arbeitsverzeichnis auslesen und hineinwechseln:
    APPDIR=$(cd $(dirname $0);pwd)
    cd ${APPDIR}

# Konfigurationsdatei einbinden:
    CONFIG=app/etc/Konfiguration.txt
    . ./$CONFIG

# check if script is already active
    #    ps x|grep synOTR.sh|grep -v grep >/dev/null
    #    if [ $? != "1" ] ; then
    #        echo "synOTR läuft bereits!"
    #        exit
    #    fi
    synOTR_pid=$( /bin/pidof synOTR.sh )

    if [ ! -z "$synOTR_pid" ] ; then
        if [ $callFrom = GUI ] ; then
            echo '<p class="center"><span style="color: #BD0010;"><b>synOTR läuft bereits!</b><br>(Prozess-ID: '$synOTR_pid')</span></p>'
            echo '<br /><p class="center"><button name="page" value="status-kill-synotr" style="color: #BD0010;">(Beenden erzwingen?)</button></p><br />'
        else
            echo "synOTR läuft bereits! (Prozess-ID: $synOTR_pid)"
        fi
        exit
    else
        if [ $callFrom = GUI ] ; then
            echo '<p class="title">synOTR wurde gestartet ...</p><br><br><br><br>
    	    <center><table id="system_msg" style="width: 40%;table-align: center;">
                <tr>   
                    <th style="width: 20%;"><img class="imageStyle" alt="status_loading" src="images/status_loading.gif" style="float:left;"></th>   
                    <th style="width: 80%;"><p class="center"><span style="color: #424242;font-weight:normal;">Bitte warten, bis die Dateien<br>fertig abgearbeitet wurden.</span></p></th>
                </tr>
            </table></center>'
        else
            echo "synOTR wurde gestartet ..."
            echo "Bitte warten, bis die Dateien fertig abgearbeitet wurden."
        fi
    fi

# Variablenkorrektur für ältere Konfiguration.txt und Slash anpassen:
    if [ -z $DESTDIR ] ; then
        DESTDIR="${destdir%/}/"
    fi

    if [ -z $WORKDIR ] ; then
        WORKDIR="${DESTDIR%/}/"     # Variable WORKDIR nicht gesetzt. Es wird im Ausgabeordner gearbeitet!
    else
        WORKDIR="${WORKDIR%/}/"
    fi

    umask 000   # damit Files auch von anderen Usern bearbeitet werden können / http://openbook.rheinwerk-verlag.de/shell_programmierung/shell_011_003.htm
	
# LOGlevel=0  => Logging inaktiv / 1 => normal / 2 => erweitert
    if [ $LOGlevel = "0" ] ; then
    	./synOTR.sh
    else
    	DECODIR="${WORKDIR%/}/_decodiert"
    	
        if [ ! -d "$DESTDIR" ] || [ "$DESTDIR" = "/" ]; then
            if [ $callFrom = GUI ] ; then
                echo '
               <p class="center"><span style="color: #BD0010;"><b>! ! ! Zielverzeichnis in der Konfiguration prüfen ! ! !</b><br>Programmlauf wird beendet.<br></span></p>'
        	else
                echo "! ! ! Zielverzeichnis in der Konfiguration prüfen ! ! !"
                echo "Programmlauf wird beendet."
        	fi
        	exit 1
    	fi
    	
        if [ $OTRcutactiv = "off" ] ; then
    		DECODIR="$WORKDIR"
    	fi
        
        mkdir -p "${DECODIR%/}/_LOGsynOTR"
        ./synOTR.sh >> ${DECODIR%/}/_LOGsynOTR/synOTR_`date +%Y`-`date +%m`-`date +%d`_`date +%H`-`date +%M`.log 2>&1
    fi
