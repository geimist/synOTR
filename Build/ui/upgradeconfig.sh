#!/bin/sh
# prüft die benutzerangepasste Datei Konfiguration.txt auf neue Variablen und ergänzt ggf. selbige
# /volume1/@appstore/synOTR/upgradeconfig.sh

# Arbeitsverzeichnis auslesen und hineinwechseln:
# ---------------------------------------------------------------------
	APPDIR=$(cd "$(dirname "$0")" || exit 1; pwd)
	cd "${APPDIR}" || exit 1
	
	CONFIG=app/etc/Konfiguration.txt

    lastrow=$(tail -n1 "./$CONFIG")  # letzte Zeile eine Leerzeile?
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
    	if ! grep -q '^APPRISEURL=' ./$CONFIG ; then
    	    _pbtoken=$(grep '^PBTOKEN=' ./$CONFIG | head -n1 | cut -d= -f2-)
    	    _pbtoken=$(printf '%s' "$_pbtoken" | sed 's/^"//; s/"$//')
    	    if [ -n "$_pbtoken" ]; then
    	        case "$_pbtoken" in
    	            *://*) echo "APPRISEURL=\"${_pbtoken}\"" >> ./$CONFIG ;;
    	            *) echo "APPRISEURL=\"pbul://${_pbtoken}\"" >> ./$CONFIG ;;
    	        esac
    	    else
    	        echo "APPRISEURL=\"\"" >> ./$CONFIG
    	    fi
    	    unset _pbtoken
        fi
    	if ! cat ./$CONFIG | grep -q "LOGlevel" ; then
    	    echo "LOGlevel=\"1\"" >> ./$CONFIG
        fi
    	if ! cat ./$CONFIG | grep -q "LOGmax" ; then
    	    echo "LOGmax=\"1\"" >> ./$CONFIG
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
    	if ! grep -q '^CutEditorQueue=' ./$CONFIG ; then
    	    echo "CutEditorQueue=\"miss_both\"" >> ./$CONFIG
        fi
    	if ! grep -q '^CutEditorOtrkeyMp4=' ./$CONFIG ; then
    	    echo "CutEditorOtrkeyMp4=\"off\"" >> ./$CONFIG
        fi
    	
    # MP4-Konvertierung:	
    	if ! cat ./$CONFIG | grep -q "OTRavi2mp4active" ; then
    	    echo "OTRavi2mp4active=\"on\"" >> ./$CONFIG
        fi
    	if ! cat ./$CONFIG | grep -q "OTRotr2audio" ; then
    	    echo "OTRotr2audio=\"both\"" >> ./$CONFIG
        fi
    	if ! cat ./$CONFIG | grep -q "OTRaacqal" ; then
    	    echo "OTRaacqal=\"80k\"" >> ./$CONFIG
        fi
    	if ! cat ./$CONFIG | grep -q "normalizeAudio" ; then
    	    echo "normalizeAudio=\"on\"" >> ./$CONFIG
        fi
    	if ! cat ./$CONFIG | grep -q "parallelAudioConvert" ; then
    	    echo "parallelAudioConvert=\"on\"" >> ./$CONFIG
        fi
    	if ! cat ./$CONFIG | grep -q "AudioDelayMs" ; then
    	    if grep -q '^MP4BOX_DELAY=' ./$CONFIG ; then
    	        _mp4box_delay=$(grep '^MP4BOX_DELAY=' ./$CONFIG | head -n1 | cut -d= -f2-)
    	        echo "AudioDelayMs=${_mp4box_delay}" >> ./$CONFIG
    	    else
    	        echo "AudioDelayMs=\"0\"" >> ./$CONFIG
    	    fi
        fi
    
    # Umbenennen:
    	if ! cat ./$CONFIG | grep -q "TVDBlang" ; then
    	    echo "TVDBlang=\"de\"" >> ./$CONFIG
        fi
    	if ! cat ./$CONFIG | grep -q "TVDB_APIKEY" ; then
    	    echo "TVDB_APIKEY=\"\"" >> ./$CONFIG
        fi
    	if ! cat ./$CONFIG | grep -q "TVDB_PIN" ; then
    	    echo "TVDB_PIN=\"\"" >> ./$CONFIG
        fi
    	if ! cat ./$CONFIG | grep -q "MOVIEDB_APIKEY" ; then
    	    echo "MOVIEDB_APIKEY=\"\"" >> ./$CONFIG
        fi
        

exit 0
