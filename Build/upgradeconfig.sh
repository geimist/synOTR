#!/bin/sh
# prüft die benutzerangepasste Datei Konfiguration.txt auf neue Variablen und ergänzt ggf. selbige
# /volume1/@appstore/synOTR/upgradeconfig.sh

# Arbeitsverzeichnis auslesen und hineinwechseln:
# ---------------------------------------------------------------------
	APPDIR=$(cd $(dirname $0);pwd)
	cd ${APPDIR}
	
	CONFIG=app/etc/Konfiguration.txt

    lastrow=`cat ./$CONFIG | tail -n1`  # letzte Zeile eine Leerzeile?
#    [ ! "$lastrow" == "" ] && echo -e "\n" >> ./$CONFIG

    if [ ! -z "$lastrow" ]; then
        echo -e "\n" >> ./$CONFIG
    fi
    
    # Prüfe die Konfiguration.txt auf fehlende Parameter:
    # ---------------------------------------------------------------------
    # allgemeine Parameter:
    	if ! cat ./$CONFIG | grep -q "dsmtextnotify" ; then
    	    echo "dsmtextnotify=\"on\"" >> ./$CONFIG
        fi
    	if ! cat ./$CONFIG | grep -q "MessageTo" ; then
    	    echo "MessageTo=\"admin\"" >> ./$CONFIG
        fi
    	if ! cat ./$CONFIG | grep -q "dsmbeepnotify" ; then
    	    echo "dsmbeepnotify=\"on\"" >> ./$CONFIG
        fi
    	if ! cat ./$CONFIG | grep -q "LOGlevel" ; then
    	    echo "LOGlevel=\"1\"" >> ./$CONFIG
        fi
    	if ! cat ./$CONFIG | grep -q "reindex" ; then
    	    echo "reindex=\"1\"" >> ./$CONFIG
        fi
    	if ! cat ./$CONFIG | grep -q "WORKDIR" ; then
    	    echo "WORKDIR=\"/volume1/video/_synOTR/\"" >> ./$CONFIG
        fi
#    	if ! cat ./$CONFIG | grep -q "customizedConfig" ; then
#    	    echo "customizedConfig=0" >> ./$CONFIG
#       fi

    # Dekodieren:
    	if ! cat ./$CONFIG | grep -q "endgueltigloeschen" ; then
    	    echo "endgueltigloeschen=\"off\"" >> ./$CONFIG
        fi
    	
    # Schneiden:
    	if ! cat ./$CONFIG | grep -q "OTRcutactiv" ; then
    	    echo "OTRcutactiv=\"on\"" >> ./$CONFIG
        fi
    	if ! cat ./$CONFIG | grep -q "SMARTRENDERING" ; then
    	    echo "SMARTRENDERING=\"on\"" >> ./$CONFIG
        fi
    	if ! cat ./$CONFIG | grep -q "WaitOfCutlist" ; then
    	    echo "WaitOfCutlist=\"on\"" >> ./$CONFIG
        fi
    	if ! cat ./$CONFIG | grep -q "OTRlocalcutlistdir" ; then
    	    echo "OTRlocalcutlistdir=\"/volume1/…\"" >> ./$CONFIG
        fi
    	if ! cat ./$CONFIG | grep -q "FrameversatzAnfangCut" ; then
    	    echo "FrameversatzAnfangCut=1" >> ./$CONFIG
    	    echo "FrameversatzEndeCut=-1" >> ./$CONFIG
        fi
    	if ! cat ./$CONFIG | grep -q "cutlistat_ID" ; then
    	    echo "cutlistat_ID=\"\"" >> ./$CONFIG
        fi
    	if ! cat ./$CONFIG | grep -q "useallcutlistformat" ; then
    	    echo "useallcutlistformat=1" >> ./$CONFIG
        fi
    	
    # MP4-Konvertierung:	
    	if ! cat ./$CONFIG | grep -q "OTRavi2mp4active" ; then
    	    echo "OTRavi2mp4active=\"on\"" >> ./$CONFIG
        fi
    	if ! cat ./$CONFIG | grep -q "OTRaacqal" ; then
    	    echo "OTRaacqal=\"80k\"" >> ./$CONFIG
        fi
    	if ! cat ./$CONFIG | grep -q "normalizeAudio" ; then
    	    echo "normalizeAudio=\"on\"" >> ./$CONFIG
        fi
    	if ! cat ./$CONFIG | grep -q "MP4BOX_DELAY" ; then
    	    echo "MP4BOX_DELAY=\"100\"" >> ./$CONFIG
        fi
    
    # Umbenennen:
    	if ! cat ./$CONFIG | grep -q "TVDBlang" ; then
    	    echo "TVDBlang=\"de\"" >> ./$CONFIG
        fi
    	if ! cat ./$CONFIG | grep -q "TVDB_APIKEY" ; then
    	    echo "TVDB_APIKEY=\"\"" >> ./$CONFIG
        fi
    	if ! cat ./$CONFIG | grep -q "MOVIEDB_APIKEY" ; then
    	    echo "MOVIEDB_APIKEY=\"\"" >> ./$CONFIG
        fi
        

exit 0
