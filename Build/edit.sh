#!/bin/bash
# edit.sh

if [[ "$page" == "edit-save" ]]; then
	"$set_var" "$dir/app/etc/Konfiguration.txt" "WORKDIR" "$WORKDIR"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "DESTDIR" "$DESTDIR"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "OTRkeydir" "$OTRkeydir"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "OTRkeydeldir" "$OTRkeydeldir"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "decoderactiv" "$decoderactiv"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "OTRuser" "$OTRuser"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "OTRpw" "$OTRpw"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "OTRcutactiv" "$OTRcutactiv"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "SMARTRENDERING" "$SMARTRENDERING"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "WaitOfCutlist" "$WaitOfCutlist"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "OTRlocalcutlistdir" "$OTRlocalcutlistdir"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "FrameversatzAnfangCut" "$FrameversatzAnfangCut"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "FrameversatzEndeCut" "$FrameversatzEndeCut"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "OTRrenameactiv" "$OTRrenameactiv"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "TVDBlang" "$TVDBlang"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "TVDB_APIKEY" "$TVDB_APIKEY"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "MOVIEDB_APIKEY" "$MOVIEDB_APIKEY"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "NameSyntax" "$NameSyntax"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "NameSyntaxSerientitel" "$NameSyntaxSerientitel"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "OTRavi2mp4active" "$OTRavi2mp4active"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "OTRaacqal" "$OTRaacqal"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "normalizeAudio" "$normalizeAudio"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "MP4BOX_DELAY" "$MP4BOX_DELAY"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "dsmtextnotify" "$dsmtextnotify"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "MessageTo" "$MessageTo"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "dsmbeepnotify" "$dsmbeepnotify"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "LOGlevel" "$LOGlevel"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "endgueltigloeschen" "$endgueltigloeschen"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "reindex" "$reindex"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "cutlistat_ID" "$cutlistat_ID"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "useallcutlistformat" "$useallcutlistformat"
#	"$set_var" "$dir/app/etc/Konfiguration.txt" "customizedConfig" "1"

	echo '<div class="Content_1Col_full">'
	echo '<br /><div class="info"><br /><p class="center" style="color:#0086E5;font-weight:normal; ">Änderungen wurden gespeichert</p><br /></div>'
	echo '<br /><p class="center"><button name="page" value="edit" class="blue_button">Weiter...</button></p><br />'
	echo '</div><div class="clear"></div>'
fi


if [[ "$page" == "edit-import-query" ]] || [[ "$page" == "edit-import" ]]; then
#        echo '<div class="Content_1Col_full">'
	if [[ "$page" == "edit-import-query" ]]; then
		echo '
	    <p class="center">
			Sollen die aktuellen Einstellungen überschrieben werden (Datenbank bleibt erhalten)?<br /><br />
			Um eine frühere Konfigurationsdatei zu importieren, lege zunächst in den <a href="index.cgi?page=edit" style="'$synotrred';">Einstellungen</a> 
			das Arbeitsverzeichnist fest. Die zu importierende Konfigurationsdatei muss den Namen "Konfiguration.txt" 
			haben und in das Arbeitsverzeichnis gelegt werden. Klicke dann auf weiter.<br /><br />
			<a href="index.cgi?page=edit-import" class="blue_button">Weiter</a>&nbsp;&nbsp;&nbsp;<a href="index.cgi?page=edit" class="button">Abbrechen</a></p>'  >> "$stop"
	elif [[ "$page" == "edit-import" ]]; then
    	if [ ! -z "$WORKDIR" ] && [ -d "$WORKDIR" ]; then
        #	"$dir/importconfig.sh" "$WORKDIR"
        #	echo '<p class="center"><br><b>Konfiguration wurde importiert.</b></p>'
            SOURCECONFIG="${WORKDIR%/}/Konfiguration.txt"
            if [ -f "$SOURCECONFIG" ] ; then
                source $SOURCECONFIG
    
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "WORKDIR" "$WORKDIR"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "DESTDIR" "$DESTDIR"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "OTRkeydir" "$OTRkeydir"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "OTRkeydeldir" "$OTRkeydeldir"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "decoderactiv" "$decoderactiv"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "OTRuser" "$OTRuser"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "OTRpw" "$OTRpw"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "OTRcutactiv" "$OTRcutactiv"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "SMARTRENDERING" "$SMARTRENDERING"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "WaitOfCutlist" "$WaitOfCutlist"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "OTRlocalcutlistdir" "$OTRlocalcutlistdir"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "FrameversatzAnfangCut" "$FrameversatzAnfangCut"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "FrameversatzEndeCut" "$FrameversatzEndeCut"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "OTRrenameactiv" "$OTRrenameactiv"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "TVDBlang" "$TVDBlang"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "TVDB_APIKEY" "$TVDB_APIKEY"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "MOVIEDB_APIKEY" "$MOVIEDB_APIKEY"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "NameSyntax" "$NameSyntax"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "NameSyntaxSerientitel" "$NameSyntaxSerientitel"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "OTRavi2mp4active" "$OTRavi2mp4active"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "OTRaacqal" "$OTRaacqal"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "normalizeAudio" "$normalizeAudio"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "MP4BOX_DELAY" "$MP4BOX_DELAY"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "dsmtextnotify" "$dsmtextnotify"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "MessageTo" "$MessageTo"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "dsmbeepnotify" "$dsmbeepnotify"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "LOGlevel" "$LOGlevel"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "endgueltigloeschen" "$endgueltigloeschen"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "reindex" "$reindex"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "cutlistat_ID" "$cutlistat_ID"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "useallcutlistformat" "$useallcutlistformat"
            
                # neue Konfiguration laden:
                source $dir/app/etc/Konfiguration.txt
                
    	        echo '<br /><p class="center">Die Konfiguration wurde importiert</p><br />' >> "$stop"
            else
                echo '<p class="center">Die Quellkonfiguration konnte nicht im angegebenen Verzeichnis gefunden werden!</p>' >> "$stop"
            fi
        else
        	echo '<p class="center"><br><b>Konfiguration konnte nicht importiert werden,
        	<br>da kein korrektes Arbeitsverzeichnis in den Einstellungen definiert wurde!</b></p>' >> "$stop"
        fi
    	echo '<br /><p class="center"><button name="page" value="edit" class="blue_button">Fertig ...</button></p><br />
            <div class="clear"></div>' >> "$stop"
    fi
fi


if [[ "$page" == "edit-export" ]]; then
    echo '<div class="Content_1Col_full">'
	if [ ! -z "$WORKDIR" ] ; then
    	cp "$dir/app/etc/Konfiguration.txt" "$WORKDIR/Konfiguration.txt"
    	cp "$dir/app/etc/synOTR.sqlite" "$WORKDIR/synOTR.sqlite"
    	echo '<br /><div class="info"><br /><p class="center" style="color:#0086E5;font-weight:normal; ">Konfigurationsdatei und die synOTR-Datenbank<br>wurde in das Arbeitsverzeichnis gesichert.</p><br /></div>'
    else
    	echo '<br /><div class="warning"><br /><p class="center">Konfigurationsdatei und die synOTR-Datenbank<br>konnte nicht in das Arbeitsverzeichnis gesichert werden,
    	<br>da kein Arbeitsverzeichnis in den Einstellungen definiert wurde!</p><br /></div>'
    fi
	echo '<br /><p class="center"><button name="page" value="edit" class="blue_button">Weiter...</button></p><br />'
	echo '
	</div>
	<div class="clear"></div>'
fi


if [[ "$page" == "edit-restore-query" ]] || [[ "$page" == "edit-restore" ]]; then
	if [[ "$page" == "edit-restore-query" ]]; then
		echo '
	    <p class="center" style="'$synotrred';">
			Sollen die Werkseinstellungen geladen werden (Datenbank bleibt erhalten)?<br /><br /><br />
			<a href="index.cgi?page=edit-restore" class="red_button">Ja</a>&nbsp;&nbsp;&nbsp;<a href="index.cgi?page=edit" class="button">Nein</a></p>'  >> "$stop"
	elif [[ "$page" == "edit-restore" ]]; then
    	if [ -f "$dir/app/etc/Konfiguration.txt" ]; then
    		rm "$dir/app/etc/Konfiguration.txt"
    		cp "$dir/usersettings/Konfiguration_org.txt" "$dir/app/etc/Konfiguration.txt"
    		chmod 755 "$dir/app/etc/Konfiguration.txt"
    	fi	
    	echo '<p class="center" style="'$green';"><b>Werkseinstellungen wurden wiederhergestellt</b></p>
    	    <br /><p class="center"><button name="page" value="edit" class="blue_button">Weiter...</button></p><br />' >> "$stop"
	fi
fi


if [[ "$page" == "edit" ]]; then
	# Dateiinhalt einlesen für Variablenverwertung
	if [ -f "$dir/app/etc/Konfiguration.txt" ]; then
		source "$dir/app/etc/Konfiguration.txt"
	fi

	echo '
	<div id="Content_1Col">
	<div class="Content_1Col_full">
    	<div class="title">
    	    synOTR Einstellungen
    	</div>
    	Trage hier deine Einstellungen ein und passe die Pfade an.
	    <br>Hilfe für die einzelnen Felder erhältst du über das blaue Info-Symbol am rechten Rand.
	    <br>
	    <br>Achte unbedingt darauf, die kompletten Pfade inkl. Volume (z.B. <code>/volume1/…</code>) einzutragen. 
	    Das sicherste ist, wenn du in der Filestation den gewünschten Ordner suchst und du dir über Rechtsklick die Eigenschaften anzeigen lässt. 
	    In diesem Dialog kannst du dir den korrekten Pfad kopieren.
	    <br><br>'

	# -> Abschnitt Allgemein
	
# Aufklappbar:
	echo '<fieldset>
	<hr style="border-style: dashed; size: 1px;">
	<br />
    <details><p>
    <summary>
        <span class="detailsitem">Allgemein</span>
    </summary></p>
    <p>' #ab hier steht der Text, der auf- und zugeklappt werden soll.
    # <span style="color:#FFFFFF;">_</span>
    # <div id="ExpFieldset">    </div>

	# WORKDIR
	echo '
		<p>
		<label>Arbeitsverzeichnis</label>'
		if [ -n "$WORKDIR" ]; then
			echo '<input type="text" name="WORKDIR" value="'$WORKDIR'" />'
		else
			echo '<input type="text" name="WORKDIR" value="" />'
		fi
		echo '
			<a class="helpbox" href="#HELP">
			<img src="images/icon_information_mini@geimist.svg" height="25" width="25"/>
			<span>Das Arbeitsverzeichnis ist zunächst einmal optional, ist aber sehr zu empfehlen. Z.B. werden bei aktivierter MP4-Konvertierung alle avi-Dateien im Arbeitsverzeichnis konvertiert. Setzt man kein spezielles Arbeitsverzeichnis ein, so ist das Zielverzeichnis das Arbeitsverzeichnis und alle darin enthaltenen avi-Dateien werden konviertiert!<br><br>(wird ggf. erstellt)</span></a>
			</p>'
			
	# DESTDIR
	echo '
		<p>
		<label>Zielverzeichnis</label>'
		if [ -n "$DESTDIR" ]; then
			echo '<input type="text" name="DESTDIR" value="'$DESTDIR'" />'
		else
			echo '<input type="text" name="DESTDIR" value="" />'
		fi
	echo '
		<a class="helpbox" href="#HELP">
			<img src="images/icon_information_mini@geimist.svg" height="25" width="25"/>
			<span>Ausgabeverzeichnis der fertigen Filme</span></a>
		</p>'
	# OTRkeydir
	echo '
		<p>
		<label>Quellverzeichnis (.otrkeys)</label>'
		if [ -n "$OTRkeydir" ]; then
			echo '<input type="text" name="OTRkeydir" value="'$OTRkeydir'" />'
		else
			echo '<input type="text" name="OTRkeydir" value="" />'
		fi
	echo '
		<a class="helpbox" href="#HELP">
			<img src="images/icon_information_mini@geimist.svg" height="25" width="25"/>
			<span>Verzeichnis mit den OTRKEY-Dateien</span></a>
		</p>'
	# OTRkeydeldir
	echo '
		<p>
		<label>Papierkorb</label>'
		if [ -n "$OTRkeydeldir" ]; then
			echo '<input type="text" name="OTRkeydeldir" value="'$OTRkeydeldir'" />'
		else
			echo '<input type="text" name="OTRkeydeldir" value="" />'
		fi
	echo '
		<a class="helpbox" href="#HELP">
			<img src="images/icon_information_mini@geimist.svg" height="25" width="25"/>
			<span>Löschverzeichnis der Quelldateien<br><br>! ! ! ACHTUNG ! ! !<br>gleichnamige vorhandene Dateien in dem Verzeichnis werden überschrieben</span></a>
		</p>'
	# endgueltigloeschen
	echo '
		<p>
		<label>Dateien endgültig löschen</label>
		<select name="endgueltigloeschen">'
		if [[ "$endgueltigloeschen" == "off" ]]; then
			echo '<option value="off" selected>aus</option>'
		else
			echo '<option value="off">aus</option>'
		fi
		if [[ "$endgueltigloeschen" == "on" ]]; then
			echo '<option value="on" selected>ein</option>'
		else
			echo '<option value="on">ein</option>'
		fi
		
	echo '
		</select>
		<a class="helpbox" href="#HELP">
			<img src="images/icon_information_mini@geimist.svg" height="25" width="25"/>
			<span>ein => alle Quelldateien endgültig löschen<br>aus => Papierkorb verwenden (Pfad siehe oben)</span></a>
		</p>'
		
	echo '
    </details>
	    </fieldset>
	</p>'


	# -> Abschnitt Decoder:
	echo '<fieldset>
	<hr style="border-style: dashed; size: 1px;">
	<br />
	<details><p>
    <summary>
        <span class="detailsitem">Decodieren</span>
    </summary></p>
    <p>'		
		
		
	# decoderactiv
	echo '
		<p>
		<label>soll decodiert werden?</label>
		<select name="decoderactiv">'
		if [[ "$decoderactiv" == "off" ]]; then
			echo '<option value="off" selected>aus</option>'
		else
			echo '<option value="off">aus</option>'
		fi
		if [[ "$decoderactiv" == "on" ]]; then
			echo '<option value="on" selected>ein</option>'
		else
			echo '<option value="on">ein</option>'
		fi
	echo '
		</select>
		<a class="helpbox" href="#HELP">
			<img src="images/icon_information_mini@geimist.svg" height="25" width="25"/>
			<span>ein => decodieren aktiv<br>aus => decodieren inaktiv</span></a>
		</p>'
	# OTRuser
	echo '
		<p>
		<label>OTR Benutzername</label>'
		if [ -n "$OTRuser" ]; then
			echo '<input type="text" name="OTRuser" value="'$OTRuser'" />'
		else
			echo '<input type="text" name="OTRuser" value="" />'
		fi
	echo '
		</p>'
	# OTRpw
	echo '
		<p>
		<label>OTR Kennwort</label>'
		if [ -n "$OTRpw" ]; then
			echo '<input type="text" name="OTRpw" value="'$OTRpw'" />'
		else
			echo '<input type="text" name="OTRpw" value="" />'
		fi
	echo '
		</p>
	    </fieldset>
	</p>
    </details>'

	# -> Abschnitt .avi's schneiden
	echo '<fieldset>
	<hr style="border-style: dashed; size: 1px;">
	<br />
	<details><p>
    <summary>
        <span class="detailsitem">Filme schneiden</span>
    </summary></p>
    <p>'
			
			
			
	# OTRcutactiv
	echo '
		<p>
		<label>automatisch schneiden?</label>
		<select name="OTRcutactiv">'
		if [[ "$OTRcutactiv" == "off" ]]; then
			echo '<option value="off" selected>aus</option>'
		else
			echo '<option value="off">aus</option>'
		fi
		if [[ "$OTRcutactiv" == "on" ]]; then
			echo '<option value="on" selected>ein</option>'
		else
			echo '<option value="on">ein</option>'
		fi
	echo '
		</select>
		<a class="helpbox" href="#HELP">
			<img src="images/icon_information_mini@geimist.svg" height="25" width="25"/>
			<span>ein => schneiden aktiv<br>aus => schneiden inaktiv</span></a>
		</p>'
	# SMARTRENDERING
	echo '
		<p>
		<label>Smartrendering</label>
		<select name="SMARTRENDERING">'
		if [[ "$SMARTRENDERING" == "off" ]]; then
			echo '<option value="off" selected>aus</option>'
		else
			echo '<option value="off">aus</option>'
		fi
		if [[ "$SMARTRENDERING" == "on" ]]; then
			echo '<option value="on" selected>ein</option>'
		else
			echo '<option value="on">ein</option>'
		fi
	echo '
		</select>
		<a class="helpbox" href="#HELP">
			<img src="images/icon_information_mini@geimist.svg" height="25" width="25"/>
			<span>Für das Schneiden an Keyframes wird avisplit/avimerge aus Transcode verwendet. Diese Art geht sehr schnell (fast wie das Kopieren der Dateien auf der Festplatte). Der Nachteil ist, dass die Schnittübergänge um mehrere Sekunden ungenau sind und nur avi-Quelldateien scheidbar sind.
			<br><br>Für das framegenaue Schneiden wird das Programm avcut verwendet. Avcut schneidet im Gegensatz zu avisplit framegenau, allerdings ergeben sich daraus erhöhte Anforderungen an die CPU und RAM (min. installiert: 1GB für HD-Aufnahmen und 500MB für HQ-Aufnahmen). Framegenaue Schnitte sind zeitintensiv.
			<br><br>ACHTUNG: mit avcut geschnittene Filme werden derzeit sehr asynchron. Die Option der Konvertierung zu MP4 löst das Problem!</span></a>
		</p>'
	# WaitOfCutlist
	echo '
		<p>
		<label>auf Cutlist warten</label>
		<select name="WaitOfCutlist">'
		if [[ "$WaitOfCutlist" == "off" ]]; then
			echo '<option value="off" selected>aus</option>'
		else
			echo '<option value="off">aus</option>'
		fi
		if [[ "$WaitOfCutlist" == "on" ]]; then
			echo '<option value="on" selected>ein</option>'
		else
			echo '<option value="on">ein</option>'
		fi
	echo '
		</select>
		<a class="helpbox" href="#HELP">
			<img src="images/icon_information_mini@geimist.svg" height="25" width="25"/>
			<span>ein => Film wartet so lange im Arbeitsverzeichnis, bis eine passende Cutlist verfügbar ist<br>aus => der Film wird ohne warten weiterverarbeitet</span></a>
		</p>'
	# alternativeCutlist
	# useallcutlistformat
	echo '
		<p>
		<label>Cutlist für andere Formate nutzen</label>
		<select name="useallcutlistformat">'
		if [[ "$useallcutlistformat" == "0" ]]; then
			echo '<option value="0" selected>nur für Originalformat</option>'
		else
			echo '<option value="0">nur für Originalformat</option>'
		fi
		if [[ "$useallcutlistformat" == "1" ]]; then
			echo '<option value="1" selected>auch für Alternativformate</option>'
		else
			echo '<option value="1">auch für Alternativformate</option>'
		fi
	echo '
		</select>
		<a class="helpbox" href="#HELP">
			<img src="images/icon_information_mini@geimist.svg" height="25" width="25"/>
			<span>Es können auch Cutlits für andere Qualitäten gefunden werden (z.B. wird für einen HD-Film, für den es keine Cutlist gibt, die entsprechende Cutlist des HQ-Formats verwendet).<br><br>
			Es können derzeit nur alternative Cutlits mit zeitbasierten Schnitten verwendet werden. Die Schnitte können allerdings ungenau werden. 
			Daher ist eine objektive Bewertung schlecht möglich weshalb die Cuts nicht über die persönliche Benutzer-ID geladen werden
			 - sie erscheinen daher auch nicht im Benutzerkonto von cutlist.at</span></a>
		</p>'
	# OTRlocalcutlistdir
	echo '
		<p>
		<label>Ordner für lokale Cutlist (optional)</label>'
		if [ -n "$OTRlocalcutlistdir" ]; then
			echo '<input type="text" name="OTRlocalcutlistdir" value="'$OTRlocalcutlistdir'" />'
		else
			echo '<input type="text" name="OTRlocalcutlistdir" value="" />'
		fi
	echo '
		<a class="helpbox" href="#HELP">
			<img src="images/icon_information_mini@geimist.svg" height="25" width="25"/>
			<span>optionaler Ordner für lokale Cutlists<br>(lokale Cutlists müssen generell den kompletten Dateinamen des Films mit zusätzlicher Dateiendung .cutlist haben)<br>Standardmäßig werden lokalen Cutlist im Download- sowie im Dekodierordner gesucht und ungeprüft (d.h. auch wenn Error wie z.B. missing Ende enthalten sind) verwendet.<br><br>
		=> Cutlists in diesem Pfad werden geprüft und müssen daher direkt zum Film passen und dürfen keine Error definiert haben.<br><br>Bei Nichtnutzung leer lassen</span></a>
		</p>'
	# OTRcutlistserver-ID
	echo '
		<p>
		<label>Benutzer-ID von cutlist.at</label>'
		if [ -n "$cutlistat_ID" ]; then
			echo '<input type="text" name="cutlistat_ID" value="'$cutlistat_ID'" />'
		else
			echo '<input type="text" name="cutlistat_ID" value="" />'
		fi
	echo '
		<a class="helpbox" href="#HELP">
			<img src="images/icon_information_mini@geimist.svg" height="25" width="25"/>
			<span>Bitte registriert euch bei Cutlist.at und tragt hier die 64 Zeichen lange ID ein (ohne http://cutlist.at/ und ohne abschließenden Slash).
			<br>Eure geladenen Cutlists werden in eurem persönlichen Bereich auf cutlist.at aufgelistet. Bitte bewertet sie dort.<br><br>Bei Nichtnutzung leer lassen</span></a>
		</p>'
	# FrameversatzAnfangCut
	echo '
		<p>
		<label>Frameversatz Anfang-Cut</label>'
		if [ -n "$FrameversatzAnfangCut" ]; then
			echo '<input type="text" name="FrameversatzAnfangCut" value="'$FrameversatzAnfangCut'" />'
		else
			echo '<input type="text" name="FrameversatzAnfangCut" value="" />'
		fi
	echo '
		<a class="helpbox" href="#HELP">
			<img src="images/icon_information_mini@geimist.svg" height="25" width="25"/>
			<span>Frameversatz, um Cuts manuell zu justieren (positive Werte verschieben jeden Cut nach hinten, negative nach vorn)<br><br>=> dieser Wert verschiebt den <b>Beginn</b> der gewünschten Filmteile beim framegenauen Schneiden</span></a>
		</p>'
	# FrameversatzEndeCut
	echo '
		<p>
		<label>Frameversatz Ende-Cut</label>'
		if [ -n "$FrameversatzEndeCut" ]; then
			echo '<input type="text" name="FrameversatzEndeCut" value="'$FrameversatzEndeCut'" />'
		else
			echo '<input type="text" name="FrameversatzEndeCut" value="" />'
		fi
	echo '
		<a class="helpbox" href="#HELP">
			<img src="images/icon_information_mini@geimist.svg" height="25" width="25"/>
			<span>Frameversatz, um Cuts manuell zu justieren (positive Werte verschieben jeden Cut nach hinten, negative nach vorn)<br><br>=> dieser Wert verschiebt das <b>Ende</b> der gewünschten Filmteile beim framegenauen Schneiden</span></a>
		</p>
	    </fieldset>
	</p>
    </details>'

	# -> Abschnitt .avi's / .mp4's umbenennen
			
	echo '<fieldset>
	<hr style="border-style: dashed; size: 1px;">
	<br />
	<details><p>
    <summary>
        <span class="detailsitem">Filme umbenennen</span>
    </summary></p>
    <p>
		<div class="info">
			folgende Parameter stehen f&uuml;r die Umbenennung zur Verf&uuml;gung:<br /><br />
			<u><b>Parameter aus Dateinamen:</b></u><br />- <span style="color:#BD0010;">&sect;dur</span> (Filml&auml;nge [EPG]	- Filml&auml;nge laut EPG / inkl. Werbebl&ouml;cke)<br />- <span style="color:#BD0010;">&sect;tit</span> (Titel)<br />- <span style="color:#BD0010;">&sect;ylong</span> (Jahr [4stellig])<br />- <span style="color:#BD0010;">&sect;yshort</span> (Jahr [2stellig])<br />- <span style="color:#BD0010;">&sect;mon</span> (Monat)<br />- <span style="color:#BD0010;">&sect;day</span> (Tag)<br />- <span style="color:#BD0010;">&sect;hou</span> (Stunde)<br />- <span style="color:#BD0010;">&sect;min</span> (Minute)<br />- <span style="color:#BD0010;">&sect;cha</span> (Sender)<br />- <span style="color:#BD0010;">&sect;qua</span> (Qualtit&auml;t / Format)<br /><br />
			<u><b>Parameter f&uuml;r Serientitel:</b></u><br />- <span style="color:#BD0010;">&sect;sertit</span> (Serientitel)<br />- <span style="color:#BD0010;">&sect;epitit</span> (Episodentitel)<br />- <span style="color:#BD0010;">&sect;sta</span> (Staffel [2stellig])<br />- <span style="color:#BD0010;">&sect;epi</span> (Episode [2stellig])<br /><br />
			<u><b>technische Parameter:</b></u><br />- <span style="color:#BD0010;">&sect;fps</span> (Framerate)<br />- <span style="color:#BD0010;">&sect;redur</span> (Filml&auml;nge [real])<br />- <span style="color:#BD0010;">&sect;height</span> (Aufl&ouml;sung H&ouml;he)<br />- <span style="color:#BD0010;">&sect;width</span> (Aufl&ouml;sung Breite)<br />- <span style="color:#BD0010;">&sect;asra</span> (Seitenverh&auml;ltnis)<br />- <span style="color:#BD0010;">&sect;acod</span> (Audiocodec)<br />- <span style="color:#BD0010;">&sect;vcod</span> (Videocodec)<br />- <span style="color:#BD0010;">&sect;ac01</span> (AC3 vorhanden - Tonspur in AC3 ja ==> " AC3" sonst ==> "")</p>
		</div><br />'
	
	# OTRrenameactiv
	echo '
		<p>
		<label>automatisch umbenennen?</label>
		<select name="OTRrenameactiv">'
		if [[ "$OTRrenameactiv" == "off" ]]; then
			echo '<option value="off" selected>aus</option>'
		else
			echo '<option value="off">aus</option>'
		fi
		if [[ "$OTRrenameactiv" == "on" ]]; then
			echo '<option value="on" selected>ein</option>'
		else
			echo '<option value="on">ein</option>'
		fi
	echo '
		</select>
		<a class="helpbox" href="#HELP">
			<img src="images/icon_information_mini@geimist.svg" height="25" width="25"/>
			<span>ein => umbenennen aktiv<br>aus => umbenennen inaktiv</span></a>
		</p>'
	# TVDBlang
	echo '
		<p>
		<label>TVDB Sprachcode</label>'
		if [ -n "$TVDBlang" ]; then
			echo '<input type="text" name="TVDBlang" value="'$TVDBlang'" />'
		else
			echo '<input type="text" name="TVDBlang" value="" />'
		fi
	echo '
		<a class="helpbox" href="#HELP">
			<img src="images/icon_information_mini@geimist.svg" height="25" width="25"/>
			<span>Sprache (Ländercode), in welcher nach Serien auf theTVDB.com gesucht werden soll</span></a>
		</p>'
	# TVDB_APIKEY
	echo '
		<p>
		<label>eigener TVDB APIKEY (optional)</label>'
		if [ -n "$TVDB_APIKEY" ]; then
			echo '<input type="text" name="TVDB_APIKEY" value="'$TVDB_APIKEY'" />'
		else
			echo '<input type="text" name="TVDB_APIKEY" value="" />'
		fi
	echo '
		<a class="helpbox" href="#HELP">
			<img src="images/icon_information_mini@geimist.svg" height="25" width="25"/>
			<span>Falls du einen eigenen API-Key von thetvdb.com nutzen möchtest, kannst du ihn hier hinterlegen</span></a>
		</p>'
	# MOVIEDB_APIKEY
#	echo '
#		<p>
#		<label>eigener MOVIEDB APIKEY (optional)</label>'
#		if [ -n "$MOVIEDB_APIKEY" ]; then
#			echo '<input type="text" name="MOVIEDB_APIKEY" value="'$MOVIEDB_APIKEY'" />'
#		else
#			echo '<input type="text" name="MOVIEDB_APIKEY" value="" />'
#		fi
#	echo '
#		<a class="helpbox" href="#HELP"><img src="images/icon_information_mini@geimist.svg" height="25" width="25"/><span>Falls du einen eigenen API-Key von moviedb.com nutzen möchtest, kannst du ihn hier hinterlegen</span></a>
#		</p>'
	# NameSyntax
	echo '
		<p>
		<label>Name-Syntax</label>'
		if [ -n "$NameSyntax" ]; then
			echo '<input type="text" name="NameSyntax" value="'$NameSyntax'" />'
		else
			echo '<input type="text" name="NameSyntax" value="" />'
		fi
	echo '
		<a class="helpbox" href="#HELP">
			<img src="images/icon_information_mini@geimist.svg" height="25" width="25"/>
			<span>"Name-Syntax" beschreibt den zukünftigen Dateinamen indem du die verfügbaren Parameter als Platzhalter wie gewünscht zusammenstellst. Des weiteren kannst du beliebigen Text hinzufügen (Sonderzeichen können zu unvorhergesehen Verhalten führen und sollten möglichst vermieden werden)
            <br><br>Ein Beispiel:
            <br>aus<br>
            <i>"Die_Sendung_14.11.21_22-40_orf3_30_TVOON_DE.mpg.HQ.avi"</i>
            <br>wird mit der Syntax<br>
            <i>"<b>§tit</b> [<b>§ylong</b>-<b>§mon</b>-<b>§day</b> <b>§hou</b>-<b>§min</b> <b>§cha</b> <b>§height</b>p <b>§redur</b>min <b>§ac01</b>] autocut"</i>
            <br>der Zieldateiname<br>
            <i>"Die Sendung [2014-11-21 22-40 ORF3 576p 24min] autocut.avi"</i><br>
            <br>Standardvorgabe ist videostationkonform
            <br>Info VideoStation: https://www.synology.com/de-de/knowledgebase/DSM/help/VideoStation/category
            <br>Info Plex: https://forums.plex.tv/discussion/135388/anleitung-deutsche-filmtitel-und-bessere-beschreibung-2
        </span></a></p>'

	# NameSyntaxSerientitel
	echo '
		<p>
		<label>Name-Syntax für Serientitel</label>'
		if [ -n "$NameSyntaxSerientitel" ]; then
			echo '<input type="text" name="NameSyntaxSerientitel" value="'$NameSyntaxSerientitel'" />'
		else
			echo '<input type="text" name="NameSyntaxSerientitel" value="" />'
		fi
	echo '
		<a class="helpbox" href="#HELP">
			<img src="images/icon_information_mini@geimist.svg" height="25" width="25"/>
			<span>gleicher Aufbau wie "Name-Syntax".<br>Wird eine Serie erkannt, so wird der Titel (§tit) durch die hier eingetragene Syntax ersetzt.</span></a>
		</p>
	    </fieldset>
	</p>
    </details>'

	# -> Abschnitt .avi's in native MP4's (MAC OS tauglich) umwandeln
			
	echo '<fieldset>
	<hr style="border-style: dashed; size: 1px;">
	<br />
	<details><p>
    <summary>
        <span class="detailsitem">AVI-Filme in native MP4-Filme (macOS tauglich) umwandeln</span>
    </summary></p>
    <p>'
		
	# OTRavi2mp4active
	echo '
		<p>
		<label>soll nach MP4 konvertiert werden?</label>
		<select name="OTRavi2mp4active">'
		if [[ "$OTRavi2mp4active" == "off" ]]; then
			echo '<option value="off" selected>aus</option>'
		else
			echo '<option value="off">aus</option>'
		fi
		if [[ "$OTRavi2mp4active" == "on" ]]; then
			echo '<option value="on" selected>ein</option>'
		else
			echo '<option value="on">ein</option>'
		fi
	echo '
		</select>
		<a class="helpbox" href="#HELP">
			<img src="images/icon_information_mini@geimist.svg" height="25" width="25"/>
			<span>ein => konvertieren aktiv<br>aus => konvertieren inaktiv</span></a>
		</p>'
	# OTRaacqal
	echo '
		<p>
		<label>Bitrate der AAC-Tonspur (kBit/s)</label>'
		if [ -n "$OTRaacqal" ]; then
			echo '<input type="text" name="OTRaacqal" value="'$OTRaacqal'" />'
		else
			echo '<input type="text" name="OTRaacqal" value="" />'
		fi
	echo '
		<a class="helpbox" href="#HELP">
			<img src="images/icon_information_mini@geimist.svg" height="25" width="25"/>
			<span>Ziel-Bitrate der aac-Audiospur (80k also 80 kbit/s)<br>AC3 bleibt unverändert</span></a>
		</p>'
	# normalizeAudio
	echo '
		<p>
		<label>Audiospur normalisieren</label>
		<select name="normalizeAudio">'
		if [[ "$normalizeAudio" == "off" ]]; then
			echo '<option value="off" selected>aus</option>'
		else
			echo '<option value="off">aus</option>'
		fi
		if [[ "$normalizeAudio" == "on" ]]; then
			echo '<option value="on" selected>ein</option>'
		else
			echo '<option value="on">ein</option>'
		fi
	echo '
		</select>
		<a class="helpbox" href="#HELP">
			<img src="images/icon_information_mini@geimist.svg" height="25" width="25"/>
			<span>Normalisierung der Audiospur (ja / nein)<br>nur in Verbindung mit avi2mp4-Konvertierung bei mp3-Quellspur</span></a>
		</p>'
	# MP4BOX_DELAY
	echo '
		<p>
		<label>manueller Tonspurversatz (in ms)</label>'
		if [ -n "$MP4BOX_DELAY" ]; then
			echo '<input type="text" name="MP4BOX_DELAY" value="'$MP4BOX_DELAY'" />'
		else
			echo '<input type="text" name="MP4BOX_DELAY" value="" />'
		fi
	echo '
		<a class="helpbox" href="#HELP">
			<img src="images/icon_information_mini@geimist.svg" height="25" width="25"/>
			<span>in Millisekunden<br>Feinabstimmung für den Audio-Video-Sync<br>Positive Werte verzögern den Ton; negative Werte verzögern das Bild</span></a>
		</p>
	    </fieldset>
	</p>
    </details>'

	# -> Abschnitt DSM-Benachrichtigung und sonstige Einstellungen
			
	echo '<fieldset>
	<hr style="border-style: dashed; size: 1px;">
	<br />
	<details><p>
    <summary>
        <span class="detailsitem">DSM-Benachrichtigung und sonstige Einstellungen</span>
    </summary></p>
    <p>'
	
	
	
	
	# dsmtextnotify
	echo '
		<p>
		<label>Systembenachrichtigung (Text)</label>
		<select name="dsmtextnotify">'
		if [[ "$dsmtextnotify" == "off" ]]; then
			echo '<option value="off" selected>aus</option>'
		else
			echo '<option value="off">aus</option>'
		fi
		if [[ "$dsmtextnotify" == "on" ]]; then
			echo '<option value="on" selected>ein</option>'
		else
			echo '<option value="on">ein</option>'
		fi
	echo '
		</select>
		<a class="helpbox" href="#HELP">
			<img src="images/icon_information_mini@geimist.svg" height="25" width="25"/>
			<span>ein => Benachrichtigung per Text aktiv im Benachrichtigungszentrum<br>aus => keine Textbenachrichtigung</span></a>
		</p>'
	# MessageTo
	echo '
		<p>
		<label>Benachrichtigung an User</label>'
		if [ -n "$MessageTo" ]; then
			echo '<input type="text" name="MessageTo" value="'$MessageTo'" />'
		else
			echo '<input type="text" name="MessageTo" value="" />'
		fi
	echo '
		<a class="helpbox" href="#HELP">
			<img src="images/icon_information_mini@geimist.svg" height="25" width="25"/>
			<span>User, an den die Benachrichtigungen gesendet werden.
		    <br>Auf diese Art kann man sich in Verbindung mit dem Paket "Notification Forwarder" über synOTR-Ereignisse z.B. über einen Pushdienst benachrichtigen lassen.
		    <br>Bleibt der Wert leer, so wird die Gruppe "administrators" benachrichtigt.
		</span></a></p>'
	# dsmbeepnotify
	echo '
		<p>
		<label>Systembenachrichtigung (Piep)</label>
		<select name="dsmbeepnotify">'
		if [[ "$dsmbeepnotify" == "off" ]]; then
			echo '<option value="off" selected>aus</option>'
		else
			echo '<option value="off">aus</option>'
		fi
		if [[ "$dsmbeepnotify" == "on" ]]; then
			echo '<option value="on" selected>ein</option>'
		else
			echo '<option value="on">ein</option>'
		fi
	echo '
		</select>
		<a class="helpbox" href="#HELP">
			<img src="images/icon_information_mini@geimist.svg" height="25" width="25"/>
			<span>Ein kurzer Piep, sobald ein Film fertig bearbeitet wurde.</span></a>
		</p>'
	# LOGlevel
	echo '
		<p>
		<label>LOGlevel (0,1,2)</label>
		<select name="LOGlevel">'
		if [[ "$LOGlevel" == "0" ]]; then
			echo '<option value="0" selected>aus</option>'
		else
			echo '<option value="0">aus</option>'
		fi
		if [[ "$LOGlevel" == "1" ]]; then
			echo '<option value="1" selected>1 (standard)</option>'
		else
			echo '<option value="1">1 (standard)</option>'
		fi
		if [[ "$LOGlevel" == "2" ]]; then
			echo '<option value="2" selected>2 (erweitert)</option>'
		else
			echo '<option value="2">2 (erweitert)</option>'
		fi
		
	echo '
		</select>
		<a class="helpbox" href="#HELP">
			<img src="images/icon_information_mini@geimist.svg" height="25" width="25"/>
			<span>0  => es wird keine Log-Datei erstellt<br>1 => normales Log (standard)<br>2 => erweitertes Log
		<br>Die Logs befinden sich im Dekodierverzeichnis/_LOGsynOTR/</span></a>
		</p>'
	# reindex
	echo '
		<p>
		<label>tägliche Neuindexierung des Zielordners</label>
		<select name="reindex">'
		if [[ "$reindex" == "0" ]]; then
			echo '<option value="0" selected>aus</option>'
		else
			echo '<option value="0">aus</option>'
		fi
		if [[ "$reindex" == "1" ]]; then
			echo '<option value="1" selected>ein</option>'
		else
			echo '<option value="1">ein</option>'
		fi
		
	echo '
		</select>
		<a class="helpbox" href="#HELP">
			<img src="images/icon_information_mini@geimist.svg" height="25" width="25"/>
			<span>Gelöschte Filme bleiben teilweise noch länger im Videostationindex.
		Hier kann eingestellt werden, ob nach dem 1. Programmlauf des Tages (also in der Regel nachts) der Index der Videostation neu aufgebaut werden soll.
		<br><br>(angepasste Videoinformationen gehen dabei nicht verloren - nur der Dateiindex wird aktualisiert)</span></a>
		</p>'
		
	echo '
    	</p>
        </details>
    	<br><hr style="border-style: dashed; size: 1px;">
	</fieldset>'

	echo '
	</div>
	</div><div class="clear"></div>
	<div id="minheight"></div>
'
fi
