#!/bin/bash
# edit.sh
# shellcheck disable=SC2154

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
	"$set_var" "$dir/app/etc/Konfiguration.txt" "TVDB_PIN" "$TVDB_PIN"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "MOVIEDB_APIKEY" "$MOVIEDB_APIKEY"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "NameSyntax" "$NameSyntax"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "NameSyntaxSerientitel" "$NameSyntaxSerientitel"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "OTRavi2mp4active" "$OTRavi2mp4active"
	case "${OTRotr2audio:-both}" in
		aac|ac3) ;;
		*) OTRotr2audio="both" ;;
	esac
	"$set_var" "$dir/app/etc/Konfiguration.txt" "OTRotr2audio" "$OTRotr2audio"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "OTRaacqal" "$OTRaacqal"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "normalizeAudio" "$normalizeAudio"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "parallelAudioConvert" "$parallelAudioConvert"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "AudioDelayMs" "$AudioDelayMs"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "dsmtextnotify" "$dsmtextnotify"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "MessageTo" "$MessageTo"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "dsmbeepnotify" "$dsmbeepnotify"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "APPRISEURL" "$APPRISEURL"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "LOGlevel" "$LOGlevel"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "LOGmax" "$LOGmax"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "endgueltigloeschen" "$endgueltigloeschen"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "cutlistat_ID" "$cutlistat_ID"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "useallcutlistformat" "$useallcutlistformat"
#	"$set_var" "$dir/app/etc/Konfiguration.txt" "customizedConfig" "1"

	echo '<div class="Content_1Col_full synotr-flash">'
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
			Um eine frühere Konfigurationsdatei zu importieren, lege zunächst in den <a href="index.cgi?page=edit" style="'"$synotrred"';">Einstellungen</a> 
			das Arbeitsverzeichnist fest. Die zu importierende Konfigurationsdatei muss den Namen "Konfiguration.txt" 
			haben und in das Arbeitsverzeichnis gelegt werden. Klicke dann auf weiter.<br /><br />
			<a href="index.cgi?page=edit-import" class="blue_button">Weiter</a>&nbsp;&nbsp;&nbsp;<a href="index.cgi?page=edit" class="button">Abbrechen</a></p>'  >> "$stop"
	elif [[ "$page" == "edit-import" ]]; then
    	if [ ! -z "$WORKDIR" ] && [ -d "$WORKDIR" ]; then
        #	"$dir/importconfig.sh" "$WORKDIR"
        #	echo '<p class="center"><br><b>Konfiguration wurde importiert.</b></p>'
            SOURCECONFIG="${WORKDIR%/}/Konfiguration.txt"
            if [ -f "$SOURCECONFIG" ] ; then
                source "$SOURCECONFIG"
    
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
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "TVDB_PIN" "$TVDB_PIN"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "MOVIEDB_APIKEY" "$MOVIEDB_APIKEY"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "NameSyntax" "$NameSyntax"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "NameSyntaxSerientitel" "$NameSyntaxSerientitel"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "OTRavi2mp4active" "$OTRavi2mp4active"
            	case "${OTRotr2audio:-both}" in
            	    aac|ac3) ;;
            	    *) OTRotr2audio="both" ;;
            	esac
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "OTRotr2audio" "$OTRotr2audio"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "OTRaacqal" "$OTRaacqal"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "normalizeAudio" "$normalizeAudio"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "parallelAudioConvert" "$parallelAudioConvert"
            	if [ -n "$AudioDelayMs" ]; then
            	    "$set_var" "$dir/app/etc/Konfiguration.txt" "AudioDelayMs" "$AudioDelayMs"
            	elif [ -n "$MP4BOX_DELAY" ]; then
            	    "$set_var" "$dir/app/etc/Konfiguration.txt" "AudioDelayMs" "$MP4BOX_DELAY"
            	fi
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "dsmtextnotify" "$dsmtextnotify"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "MessageTo" "$MessageTo"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "dsmbeepnotify" "$dsmbeepnotify"
	            if [ -z "$APPRISEURL" ] && [ -n "$PBTOKEN" ]; then
	                case "$PBTOKEN" in
	                    *://*) APPRISEURL="$PBTOKEN" ;;
	                    *) APPRISEURL="pbul://${PBTOKEN}" ;;
	                esac
	            fi
	            "$set_var" "$dir/app/etc/Konfiguration.txt" "APPRISEURL" "$APPRISEURL"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "LOGlevel" "$LOGlevel"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "LOGmax" "$LOGmax"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "endgueltigloeschen" "$endgueltigloeschen"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "cutlistat_ID" "$cutlistat_ID"
            	"$set_var" "$dir/app/etc/Konfiguration.txt" "useallcutlistformat" "$useallcutlistformat"
            
                # neue Konfiguration laden:
                source "$dir/app/etc/Konfiguration.txt"
                
    	        echo '<div class="synotr-flash"><br /><p class="center">Die Konfiguration wurde importiert</p>
    	<br /><p class="center"><button name="page" value="edit" class="blue_button">Fertig ...</button></p><br />
            <div class="clear"></div></div>' >> "$stop"
            else
                echo '<p class="center">Die Quellkonfiguration konnte nicht im angegebenen Verzeichnis gefunden werden!</p>
    	<br /><p class="center"><button name="page" value="edit" class="blue_button">Fertig ...</button></p><br />
            <div class="clear"></div>' >> "$stop"
            fi
        else
        	echo '<p class="center"><br><b>Konfiguration konnte nicht importiert werden,
        	<br>da kein korrektes Arbeitsverzeichnis in den Einstellungen definiert wurde!</b></p>
    	<br /><p class="center"><button name="page" value="edit" class="blue_button">Fertig ...</button></p><br />
            <div class="clear"></div>' >> "$stop"
        fi
    fi
fi


if [[ "$page" == "edit-export" ]]; then
    echo '<div class="Content_1Col_full">'
	if [ ! -z "$WORKDIR" ] ; then
    	cp "$dir/app/etc/Konfiguration.txt" "$WORKDIR/Konfiguration.txt"
    	cp "$dir/app/etc/synOTR.sqlite" "$WORKDIR/synOTR.sqlite"
    	echo '<div class="synotr-flash">'
    	echo '<br /><div class="info"><br /><p class="center" style="color:#0086E5;font-weight:normal; ">Konfigurationsdatei und die synOTR-Datenbank<br>wurde in das Arbeitsverzeichnis gesichert.</p><br /></div>'
    else
    	echo '<br /><div class="warning"><br /><p class="center">Konfigurationsdatei und die synOTR-Datenbank<br>konnte nicht in das Arbeitsverzeichnis gesichert werden,
    	<br>da kein Arbeitsverzeichnis in den Einstellungen definiert wurde!</p><br /></div>'
    fi
	echo '<br /><p class="center"><button name="page" value="edit" class="blue_button">Weiter...</button></p><br />'
	if [ ! -z "$WORKDIR" ] ; then
		echo '</div>'
	fi
	echo '
	</div>
	<div class="clear"></div>'
fi


if [[ "$page" == "edit-restore-query" ]] || [[ "$page" == "edit-restore" ]]; then
	if [[ "$page" == "edit-restore-query" ]]; then
		echo '
	    <p class="center" style="'"$synotrred"';">
			Sollen die Werkseinstellungen geladen werden (Datenbank bleibt erhalten)?<br /><br /><br />
			<a href="index.cgi?page=edit-restore" class="red_button">Ja</a>&nbsp;&nbsp;&nbsp;<a href="index.cgi?page=edit" class="button">Nein</a></p>'  >> "$stop"
	elif [[ "$page" == "edit-restore" ]]; then
    	if [ -f "$dir/app/etc/Konfiguration.txt" ]; then
    		rm "$dir/app/etc/Konfiguration.txt"
    		cp "$dir/usersettings/Konfiguration_org.txt" "$dir/app/etc/Konfiguration.txt"
    		chmod 755 "$dir/app/etc/Konfiguration.txt"
    	fi	
    	echo '<div class="synotr-flash"><p class="center" style="'"$green"';"><b>Werkseinstellungen wurden wiederhergestellt</b></p>
    	    <br /><p class="center"><button name="page" value="edit" class="blue_button">Weiter...</button></p><br /></div>' >> "$stop"
	fi
fi


if [[ "$page" == "edit" ]]; then
	# Dateiinhalt einlesen für Variablenverwertung
	if [ -f "$dir/app/etc/Konfiguration.txt" ]; then
		source "$dir/app/etc/Konfiguration.txt"
	fi

	# shellcheck source=includes/folderpicker.sh
	# shellcheck disable=SC1091
	[ -f "$dir/includes/folderpicker.sh" ] && . "$dir/includes/folderpicker.sh"

	synotr_html_attr() {
		printf '%s' "${1-}" | sed 's/&/\&amp;/g; s/"/\&quot;/g; s/</\&lt;/g'
	}

	synotr_form_help_btn() {
		if [ -z "$2" ]; then
			echo '<span class="synotr-help-btn"></span>'
			return
		fi
		echo '<label for="'"$1"'-info" class="synotr-help-btn"><img src="images/icon_information_mini@geimist.svg" height="25" width="25" alt=""/></label>'
	}

	synotr_form_hint() {
		[ -z "$2" ] && return
		echo '<input type="checkbox" id="'"$1"'-info" class="synotr-help-check" tabindex="-1"/>
		<div class="synotr-hint-card">'"$2"'</div>'
	}

	synotr_field_open() {
		if [ -n "$1" ]; then
			if [ "$2" = "hidden" ]; then
				echo '<div class="synotr-field" id="'"$1"'" style="display:none;">'
			else
				echo '<div class="synotr-field" id="'"$1"'">'
			fi
		else
			echo '<div class="synotr-field">'
		fi
	}

	# name label value help [wrap_id] [hidden]
	synotr_form_text() {
		local _n="$1" _l="$2" _v="$3" _h="$4"
		local _esc
		_esc=$(synotr_html_attr "$_v")
		synotr_field_open "$5" "$6"
		echo '<div class="synotr-form-row">
			<label for="'"$_n"'">'"$_l"'</label>
			<input type="text" class="synotr-form-control" name="'"$_n"'" id="'"$_n"'" value="'"$_esc"'" />'
		synotr_form_help_btn "$_n" "$_h"
		echo '</div>'
		synotr_form_hint "$_n" "$_h"
		echo '</div>'
	}

	# name label value help [wrap_id] [hidden] — Pfadfeld mit FileStation-Picker
	synotr_form_path() {
		local _n="$1" _l="$2" _v="$3" _h="$4"
		local _esc
		_esc=$(synotr_html_attr "$_v")
		synotr_field_open "$5" "$6"
		echo '<div class="synotr-form-row">
			<label for="'"$_n"'">'"$_l"'</label>
			<div class="synotr-path-wrap">
				<input type="text" class="synotr-form-control synotr-path-input" name="'"$_n"'" id="'"$_n"'" value="'"$_esc"'" spellcheck="false"/>
				<button type="button" class="synotr-path-pick" data-synotr-pick="'"$_n"'" title="Ordner auswählen" aria-label="Ordner auswählen">
					<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/></svg>
				</button>
			</div>'
		synotr_form_help_btn "$_n" "$_h"
		echo '</div>'
		synotr_form_hint "$_n" "$_h"
		echo '</div>'
	}

	synotr_chip_pin() {
		printf '<span draggable="true" class="synotr-namesyntax-palette-item" data-token="%s" title="%s">%s</span>\n' "$1" "$1" "$2"
	}

	# name label value help
	synotr_form_namesyntax() {
		local _n="$1" _l="$2" _v="$3" _h="$4"
		local _esc
		_esc=$(synotr_html_attr "$_v")
		synotr_field_open
		echo '<div class="synotr-form-row synotr-namesyntax-row">
			<label for="'"$_n"'-visual">'"$_l"'</label>
			<div class="synotr-namesyntax-editor-wrap">
				<input type="hidden" name="'"$_n"'" id="'"$_n"'" value="'"$_esc"'" />
				<div id="'"$_n"'-visual" class="synotr-form-control synotr-namesyntax-editor" contenteditable="true" role="textbox" aria-multiline="false" spellcheck="false" tabindex="0" data-synotr-chip-hidden="'"$_n"'" data-synotr-chip-palette="synotr-namesyntax-palette"></div>
			</div>'
		synotr_form_help_btn "$_n" "$_h"
		echo '</div>'
		synotr_form_hint "$_n" "$_h"
		echo '</div>'
	}

	# name label current help [on] [off] [wrap_id] [hidden]
	synotr_form_switch() {
		local _n="$1" _l="$2" _c="$3" _h="$4" _on="${5:-on}" _off="${6:-off}"
		local _chk="" _val="$_off"
		if [[ "$_c" == "$_on" ]]; then
			_chk=" checked"
			_val="$_on"
		fi
		synotr_field_open "$7" "$8"
		echo '<div class="synotr-form-row">
			<label for="'"$_n"'-switch">'"$_l"'</label>
			<div class="synotr-switch-wrap">
				<input type="hidden" name="'"$_n"'" id="'"$_n"'" value="'"$_val"'"/>
				<input class="synotr-switch" type="checkbox" role="switch" id="'"$_n"'-switch" data-synotr-switch="'"$_n"'" data-on="'"$_on"'" data-off="'"$_off"'"'"$_chk"'/>
			</div>'
		synotr_form_help_btn "$_n" "$_h"
		echo '</div>'
		synotr_form_hint "$_n" "$_h"
		echo '</div>'
	}

	# name label help options_html
	synotr_form_select() {
		local _n="$1" _l="$2" _h="$3" _o="$4"
		synotr_field_open
		echo '<div class="synotr-form-row">
			<label for="'"$_n"'">'"$_l"'</label>
			<select class="synotr-form-control" name="'"$_n"'" id="'"$_n"'">'"$_o"'</select>'
		synotr_form_help_btn "$_n" "$_h"
		echo '</div>'
		synotr_form_hint "$_n" "$_h"
		echo '</div>'
	}

	synotr_option() {
		if [[ "$3" == "$1" ]]; then
			printf '<option value="%s" selected>%s</option>' "$1" "$2"
		else
			printf '<option value="%s">%s</option>' "$1" "$2"
		fi
	}

	synotr_int() {
		local _n="${1-0}"
		_n="${_n#"${_n%%[![:space:]]*}"}"
		_n="${_n%"${_n##*[![:space:]]}"}"
		[[ "$_n" =~ ^[+-]?[0-9]+$ ]] || _n=0
		printf '%s' "$_n"
	}

	synotr_clamp() {
		awk -v v="$1" -v lo="$2" -v hi="$3" -v st="${4:-1}" 'BEGIN {
			v = int(v); lo = int(lo); hi = int(hi); st = int(st);
			if (st < 1) st = 1;
			if (v < lo) v = lo;
			if (v > hi) v = hi;
			v = lo + int((v - lo) / st + 0.5) * st;
			if (v > hi) v = hi;
			if (v < lo) v = lo;
			printf "%d", v;
		}'
	}

	synotr_step_index() {
		awk -v v="$1" -v s="$2" 'BEGIN {
			n = split(s, a, ",");
			best = 0;
			bestd = 1e9;
			for (i = 1; i <= n; i++) {
				d = a[i] - v;
				if (d < 0) d = -d;
				if (d < bestd) { bestd = d; best = i - 1; }
			}
			printf "%d", best;
		}'
	}

	# name label value help min max step unit signed(0|1)
	synotr_form_range() {
		local _n="$1" _l="$2" _v="$3" _h="$4" _min="$5" _max="$6" _step="$7" _unit="$8" _signed="${9:-0}"
		local _num _show
		_num=$(synotr_int "$_v")
		_num=$(synotr_clamp "$_num" "$_min" "$_max" "$_step")
		if [ "$_signed" = "1" ] && [ "$_num" -gt 0 ]; then
			_show="+${_num}"
		else
			_show="${_num}"
		fi
		[ -n "$_unit" ] && _show="${_show} ${_unit}"
		synotr_field_open
		echo '<div class="synotr-form-row">
			<label for="'"$_n"'-range">'"$_l"'</label>
			<div class="synotr-range-wrap">
				<input type="hidden" name="'"$_n"'" id="'"$_n"'" value="'"$_num"'"/>
				<input type="range" class="synotr-range" id="'"$_n"'-range" min="'"$_min"'" max="'"$_max"'" step="'"$_step"'" value="'"$_num"'" data-synotr-range="'"$_n"'" data-synotr-unit="'"$_unit"'" data-synotr-signed="'"$_signed"'"/>
				<span class="synotr-range-value" id="'"$_n"'-value">'"$_show"'</span>
			</div>'
		synotr_form_help_btn "$_n" "$_h"
		echo '</div>'
		synotr_form_hint "$_n" "$_h"
		echo '</div>'
	}

	# name label value help steps_csv unit suffix
	synotr_form_range_steps() {
		local _n="$1" _l="$2" _v="$3" _h="$4" _steps="$5" _unit="$6" _suf="${7-}"
		local _num _idx _nsteps _show
		_num=$(synotr_int "${_v%k}")
		_idx=$(synotr_step_index "$_num" "$_steps")
		_nsteps=$(awk -v s="$_steps" 'BEGIN { printf "%d", split(s, a, ",") - 1 }')
		_num=$(awk -v s="$_steps" -v i="$_idx" 'BEGIN { split(s, a, ","); printf "%s", a[i+1] }')
		_show="${_num}"
		[ -n "$_unit" ] && _show="${_show} ${_unit}"
		synotr_field_open
		echo '<div class="synotr-form-row">
			<label for="'"$_n"'-range">'"$_l"'</label>
			<div class="synotr-range-wrap">
				<input type="hidden" name="'"$_n"'" id="'"$_n"'" value="'"${_num}${_suf}"'"/>
				<input type="range" class="synotr-range" id="'"$_n"'-range" min="0" max="'"$_nsteps"'" step="1" value="'"$_idx"'" data-synotr-range="'"$_n"'" data-synotr-steps="'"$_steps"'" data-synotr-unit="'"$_unit"'" data-synotr-suffix="'"$_suf"'"/>
				<span class="synotr-range-value" id="'"$_n"'-value">'"$_show"'</span>
			</div>'
		synotr_form_help_btn "$_n" "$_h"
		echo '</div>'
		synotr_form_hint "$_n" "$_h"
		echo '</div>'
	}

	echo '
	<div id="Content_1Col">
	<div class="Content_1Col_full synotr-form-page">
    	<div class="title">
    	    synOTR Einstellungen
    	</div>
    	Trage hier deine Einstellungen ein und passe die Pfade an.
	    <br>Hilfe für die einzelnen Felder erhältst du über das blaue Info-Symbol am rechten Rand.
	    <br>
	    <br>Achte unbedingt darauf, die kompletten Pfade inkl. Volume (z.B. <code>/volume1/…</code>) einzutragen.
	    Am einfachsten wählst du den Ordner über das Ordnersymbol im jeweiligen Feld. Alternativ kopierst du in der Filestation über Rechtsklick → Eigenschaften den Pfad.
	    <br><br>'

	# -> Abschnitt Allgemein
	echo '<fieldset>
	<hr style="border-style: dashed; size: 1px;">
	<br />
    <details>
    <summary>
        <span class="detailsitem">Allgemein</span>
    </summary>
    <div>'

	synotr_form_path "WORKDIR" "Arbeitsverzeichnis" "$WORKDIR" \
		'Das Arbeitsverzeichnis ist zunächst einmal optional, ist aber sehr zu empfehlen. Z.B. werden bei aktivierter MP4-Konvertierung alle avi-Dateien im Arbeitsverzeichnis konvertiert. Setzt man kein spezielles Arbeitsverzeichnis ein, so ist das Zielverzeichnis das Arbeitsverzeichnis und alle darin enthaltenen avi-Dateien werden konviertiert!<br><br>(wird ggf. erstellt)'

	synotr_form_path "DESTDIR" "Zielverzeichnis" "$DESTDIR" \
		'Ausgabeverzeichnis der fertigen Filme'

	synotr_form_path "OTRkeydir" "Quellverzeichnis (.otrkey / .otr2)" "$OTRkeydir" \
		'Verzeichnis mit den .otrkey- und .otr2-Dateien'

	synotr_form_path "OTRkeydeldir" "Papierkorb" "$OTRkeydeldir" \
		'Löschverzeichnis der Quelldateien<br><br>! ! ! ACHTUNG ! ! !<br>gleichnamige vorhandene Dateien in dem Verzeichnis werden überschrieben'

	synotr_form_switch "endgueltigloeschen" "Dateien endgültig löschen" "$endgueltigloeschen" \
		'ein =&gt; alle Quelldateien endgültig löschen<br>aus =&gt; Papierkorb verwenden (Pfad siehe oben)'

	echo '
    </div>
    </details>
	    </fieldset>'


	# -> Abschnitt Decoder:
	echo '<fieldset>
	<hr style="border-style: dashed; size: 1px;">
	<br />
	<details>
    <summary>
        <span class="detailsitem">Decodieren</span>
    </summary>
    <div>'

	synotr_form_switch "decoderactiv" "soll decodiert werden?" "$decoderactiv" \
		'ein =&gt; decodieren aktiv<br>aus =&gt; decodieren inaktiv'

	synotr_form_text "OTRuser" "OTR Benutzername" "$OTRuser" ""

	synotr_form_text "OTRpw" "OTR Kennwort" "$OTRpw" ""

	echo '
    </div>
    </details>
	    </fieldset>'

	# -> Abschnitt .avi's schneiden
	echo '<fieldset>
	<hr style="border-style: dashed; size: 1px;">
	<br />
	<details>
    <summary>
        <span class="detailsitem">Filme schneiden</span>
    </summary>
    <div>'

	synotr_form_switch "OTRcutactiv" "automatisch schneiden?" "$OTRcutactiv" \
		'ein =&gt; schneiden aktiv<br>aus =&gt; schneiden inaktiv'

	synotr_form_switch "SMARTRENDERING" "Smartrendering" "$SMARTRENDERING" \
		'ein =&gt; Smartrendering<br>aus =&gt; Cut an Keyframes<br><br>.otrkey (AVI, x86_64): Smartrendering = altes avcut wie 4.3.1, dann ffmpeg-Demux + MP4Box. Keyframe = avisplit/avimerge, dann ebenfalls MP4Box. HD-AVI immer avisplit.<br>aarch64: .otrkey wird nicht geschnitten, nur nach MP4 (MP4Box).<br><br>.otr2 (natives MP4): Smartrendering = avcut 0.8 (ffmpeg8, MKV, dann mp4mux). Keyframe = ffmpeg-Demux + Bento4 mp4mux. Schnittbeginn rastet am Keyframe ein.<br><br>Frameversatz gilt für beide avcut-Pfade. Mindestens 500 MB RAM für Smartrendering.'

	synotr_form_switch "WaitOfCutlist" "auf Cutlist warten" "$WaitOfCutlist" \
		'ein =&gt; Film wartet so lange im Arbeitsverzeichnis, bis eine passende Cutlist verfügbar ist<br>aus =&gt; der Film wird ohne warten weiterverarbeitet'

	synotr_form_switch "useallcutlistformat" "Cutlist für andere Formate nutzen" "$useallcutlistformat" \
		'Es können auch Cutlits für andere Qualitäten gefunden werden (z.B. wird für einen HD-Film, für den es keine Cutlist gibt, die entsprechende Cutlist des HQ-Formats verwendet).<br><br>Es können derzeit nur alternative Cutlits mit zeitbasierten Schnitten verwendet werden. Die Schnitte können allerdings ungenau werden. Daher ist eine objektive Bewertung schlecht möglich weshalb die Cuts nicht über die persönliche Benutzer-ID geladen werden – sie erscheinen daher auch nicht im Benutzerkonto von cutlist.at' \
		"1" "0"

	synotr_form_path "OTRlocalcutlistdir" "Ordner für lokale Cutlist (optional)" "$OTRlocalcutlistdir" \
		'optionaler Ordner für lokale Cutlists<br>(Dateiname = Filmname plus .cutlist, Qualität LQ/HQ/HD ist egal)<br>Gesucht wird zuerst neben dem Film (Dekodier- und Downloadordner), danach in diesem Pfad.<br><br>Eine lokale Cutlist wird nur für diese Sendung verwendet, aber ohne Qualitätsdifferenzierung – Error-Flags wie MissingEnding sind kein Veto.<br>Die Einstellung „auch für Alternativformate“ gilt nur für cutlist.at.<br><br>Bei Nichtnutzung leer lassen'

	synotr_form_text "cutlistat_ID" "Benutzer-ID von cutlist.at" "$cutlistat_ID" \
		'Bitte registriert euch bei Cutlist.at und tragt hier die 64 Zeichen lange ID ein (ohne http://cutlist.at/ und ohne abschließenden Slash).<br>Eure geladenen Cutlists werden in eurem persönlichen Bereich auf cutlist.at aufgelistet. Bitte bewertet sie dort.<br><br>Bei Nichtnutzung leer lassen'

	synotr_form_range "FrameversatzAnfangCut" "Frameversatz Anfang-Cut" "$FrameversatzAnfangCut" \
		'Frameversatz, um Cuts manuell zu justieren (positive Werte verschieben jeden Cut nach hinten, negative nach vorn).<br>Bereich ±25 Frames.<br><br>=&gt; dieser Wert verschiebt den <b>Beginn</b> der gewünschten Filmteile beim framegenauen Schneiden<br><br>(greift für avcut: .otrkey 4.3.1 und .otr2 0.8)' \
		"-25" "25" "1" "Frames" "1"

	synotr_form_range "FrameversatzEndeCut" "Frameversatz Ende-Cut" "$FrameversatzEndeCut" \
		'Frameversatz, um Cuts manuell zu justieren (positive Werte verschieben jeden Cut nach hinten, negative nach vorn).<br>Bereich ±25 Frames.<br><br>=&gt; dieser Wert verschiebt das <b>Ende</b> der gewünschten Filmteile beim framegenauen Schneiden<br><br>(greift für avcut: .otrkey 4.3.1 und .otr2 0.8)' \
		"-25" "25" "1" "Frames" "1"

	echo '
    </div>
    </details>
	    </fieldset>'

	# -> Abschnitt .avi's / .mp4's umbenennen
	echo '<fieldset>
	<hr style="border-style: dashed; size: 1px;">
	<br />
	<details>
    <summary>
        <span class="detailsitem">Filme umbenennen</span>
    </summary>
    <div>'

	synotr_form_switch "OTRrenameactiv" "automatisch umbenennen?" "$OTRrenameactiv" \
		'ein =&gt; umbenennen aktiv<br>aus =&gt; umbenennen inaktiv'

	synotr_form_text "TVDBlang" "TVDB Sprachcode" "$TVDBlang" \
		'Sprache für theTVDB API v4 (z. B. de oder deu). Zweibuchstaben-Codes werden intern auf ISO-639-3 abgebildet.'

	synotr_form_text "TVDB_APIKEY" "TVDB API-Key (v4)" "$TVDB_APIKEY" \
		'API-v4-Key von thetvdb.com (Dashboard). Ohne Key keine Serienabfrage. Alte v2/v3-Keys funktionieren nicht.'

	synotr_form_text "TVDB_PIN" "TVDB PIN (optional)" "$TVDB_PIN" \
		'Nur nötig für nutzergebundene / Subscriber-Keys. Projekt-Keys ohne PIN leer lassen.'

	_synotr_help=$(cat <<'EOF'
Die Pins unten per Klick oder Drag &amp; Drop in das Namensfeld setzen. Trennzeichen und beliebigen Text dazwischen einfach eintippen (Sonderzeichen möglichst vermeiden).<br>
Klick auf einen Pin trifft das zuletzt angeklickte Namensfeld.
<br><br>Ein Beispiel:
<br>aus<br>
<i>&quot;Die_Sendung_14.11.21_22-40_orf3_30_TVOON_DE.mpg.HQ.avi&quot;</i>
<br>wird mit der Syntax<br>
<i>&quot;<b>§tit</b> [<b>§ylong</b>-<b>§mon</b>-<b>§day</b> <b>§hou</b>-<b>§min</b> <b>§cha</b> <b>§height</b>p <b>§redur</b>min <b>§ac01</b>] autocut&quot;</i>
<br>der Zieldateiname<br>
<i>&quot;Die Sendung [2014-11-21 22-40 ORF3 576p 24min] autocut.avi&quot;</i>
<br><br>§ac01 wird zu &quot; ac3&quot;, wenn irgendeine Tonspur AC3/E-AC3 ist, sonst leer. §dur ist die EPG-Länge (inkl. Werbung), §redur die reale Filmlänge.
<br><br>Standardvorgabe folgt dem üblichen Serien-Dateinamen (Titel.S01.E01 Episode)
<br>Info Plex: https://forums.plex.tv/discussion/135388/anleitung-deutsche-filmtitel-und-bessere-beschreibung-2
EOF
)
	synotr_form_namesyntax "NameSyntax" "Name-Syntax" "$NameSyntax" "$_synotr_help"

	synotr_form_namesyntax "NameSyntaxSerientitel" "Name-Syntax für Serientitel" "$NameSyntaxSerientitel" \
		'Gleicher Aufbau wie &quot;Name-Syntax&quot; (Pins und Freitext).<br>Wird eine Serie erkannt, so wird der Titel (§tit) durch die hier eingetragene Syntax ersetzt.'

	echo '<div class="synotr-field synotr-namesyntax-palette-field">
		<p class="synotr-namesyntax-palette-intro">Pins per Klick oder Drag &amp; Drop in das Namensfeld setzen (das zuletzt angeklickte Feld nimmt den Pin auf). Trennzeichen dazwischen eintippen.</p>
		<div id="synotr-namesyntax-palette" class="synotr-namesyntax-palette">
			<span class="synotr-namesyntax-palette-caption">aus dem Dateinamen</span>'
	synotr_chip_pin "§tit" "Titel"
	synotr_chip_pin "§dur" "Filmlänge [EPG]"
	synotr_chip_pin "§ylong" "Jahr [4]"
	synotr_chip_pin "§yshort" "Jahr [2]"
	synotr_chip_pin "§mon" "Monat"
	synotr_chip_pin "§day" "Tag"
	synotr_chip_pin "§hou" "Stunde"
	synotr_chip_pin "§min" "Minute"
	synotr_chip_pin "§cha" "Sender"
	synotr_chip_pin "§qua" "Qualität"
	echo '			<span class="synotr-namesyntax-palette-caption">Serie</span>'
	synotr_chip_pin "§sertit" "Serientitel"
	synotr_chip_pin "§epitit" "Episodentitel"
	synotr_chip_pin "§sta" "Staffel"
	synotr_chip_pin "§epi" "Episode"
	echo '			<span class="synotr-namesyntax-palette-caption">technisch</span>'
	synotr_chip_pin "§fps" "Framerate"
	synotr_chip_pin "§redur" "Filmlänge [real]"
	synotr_chip_pin "§height" "Höhe"
	synotr_chip_pin "§width" "Breite"
	synotr_chip_pin "§asra" "Seitenverhältnis"
	synotr_chip_pin "§acod" "Audiocodec"
	synotr_chip_pin "§vcod" "Videocodec"
	synotr_chip_pin "§ac01" "AC3"
	echo '
		</div>
	</div>'

	echo '
    </div>
    </details>
	    </fieldset>'

	unset _synotr_help

	# -> Abschnitt .avi's in native MP4's umwandeln
	echo '<fieldset>
	<hr style="border-style: dashed; size: 1px;">
	<br />
	<details>
    <summary>
        <span class="detailsitem">AVI-Filme in native MP4-Filme umwandeln</span>
    </summary>
    <div>'

	_synotr_mp4_hidden=""
	[[ "$OTRcutactiv" == "on" ]] && _synotr_mp4_hidden="hidden"
	synotr_form_switch "OTRavi2mp4active" "Ausgabe immer MP4" "$OTRavi2mp4active" \
		'ein =&gt; Rest-AVI nach MP4 (ffmpeg-Demux + MP4Box, wie OTRavi2mp4 in 4.3.1)<br>aus =&gt; AVI bleibt AVI<br><br>Gilt nur, wenn Schneiden aus ist. Beim Schneiden wird die Ausgabe immer MP4 (.otrkey über MP4Box, .otr2 bleibt MP4 bzw. wird nach dem Cut gemuxt).<br>.otr2-MP4 ohne Schnitt bleibt unverändert, außer unter „otr2-Tonspuren“ ist nicht „beide“ gewählt.' \
		"on" "off" "row_OTRavi2mp4active" "$_synotr_mp4_hidden"
	unset _synotr_mp4_hidden

	_synotr_a="${OTRotr2audio:-both}"
	case "$_synotr_a" in
		aac|ac3) ;;
		*) _synotr_a="both" ;;
	esac
	_synotr_opts="$(synotr_option "both" "AAC und AC3 (beide)" "$_synotr_a")$(synotr_option "aac" "nur AAC (Stereo)" "$_synotr_a")$(synotr_option "ac3" "nur AC3 (5.1)" "$_synotr_a")"
	synotr_form_select "OTRotr2audio" "otr2-Tonspuren" \
		'Welche Tonspuren ins fertige MP4 sollen, wenn die .otr2-Quelle mehrere hat (typisch HQ: AAC-Stereo und AC3-5.1).<br><br>beide =&gt; AAC und AC3, AAC bleibt die Standardspur (wie QuickTime)<br>nur AAC =&gt; kleinere Datei, maximale Kompatibilit&auml;t<br>nur AC3 =&gt; Surround, falls vorhanden<br><br>Fehlt die gewählte Spur, bleibt die vorhandene. Gilt für Smartrendering, Keyframe-Schnitt und – wenn Schneiden aus ist – für ungeschnittene .otr2-MP4. AAC-Bitrate und Normalisierung unten betreffen nur otrkey (MP3→AAC).' \
		"$_synotr_opts"
	unset _synotr_opts _synotr_a

	synotr_form_range_steps "OTRaacqal" "Bitrate der AAC-Tonspur" "$OTRaacqal" \
		'Ziel-Bitrate der AAC-Audiospur. Der Regler rastet auf üblichen Stereo-Stufen ein: 32, 48, 64, 80, 96, 112, 128, 160, 192, 256 kBit/s. Standard: 80 kBit/s. AC3 bleibt unverändert.' \
		"32,48,64,80,96,112,128,160,192,256" "kBit/s" "k"

	synotr_form_switch "normalizeAudio" "Audiospur normalisieren" "$normalizeAudio" \
		'Normalisierung der Audiospur (ja / nein)<br>nur in Verbindung mit avi2mp4-Konvertierung bei mp3-Quellspur'

	_synotr_par="$parallelAudioConvert"
	[[ "$_synotr_par" != "off" ]] && _synotr_par="on"
	synotr_form_switch "parallelAudioConvert" "Audiospur parallel konvertieren" "$_synotr_par" \
		'Beschleunigt die AAC-Umwandlung durch parallele Kodierung (höchstens 4 Jobs, ein Kern bleibt frei, Segmente mind. ca. 90s). Nur bei AVI-zu-MP4 mit MP3-Quellspur. Kurze Dateien und 1–2-Kern-NAS laufen sequentiell. Bei seltenen Knacksern an den Nahtstellen abschalten.'
	unset _synotr_par

	_delay_show="$AudioDelayMs"
	if [ -z "$_delay_show" ] && [ -n "$MP4BOX_DELAY" ]; then
		_delay_show="$MP4BOX_DELAY"
	fi
	[ -z "$_delay_show" ] && _delay_show="0"
	synotr_form_range "AudioDelayMs" "manueller Tonspurversatz" "$_delay_show" \
		'Feinabstimmung für den Audio-Video-Sync beim ffmpeg-Remux (−500 bis +500 ms, 10-ms-Schritte).<br>Positive Werte verzögern den Ton; negative Werte verzögern das Bild.<br>Standard für Neuinstallationen: 0' \
		"-500" "500" "10" "ms" "1"
	unset _delay_show

	echo '
    </div>
    </details>
	    </fieldset>'

	# -> Abschnitt DSM-Benachrichtigung und sonstige Einstellungen
	echo '<fieldset>
	<hr style="border-style: dashed; size: 1px;">
	<br />
	<details>
    <summary>
        <span class="detailsitem">DSM-Benachrichtigung und sonstige Einstellungen</span>
    </summary>
    <div>'

	synotr_form_switch "dsmtextnotify" "Systembenachrichtigung (Text)" "$dsmtextnotify" \
		'ein =&gt; Benachrichtigung per Text aktiv im Benachrichtigungszentrum<br>aus =&gt; keine Textbenachrichtigung'

	synotr_form_text "MessageTo" "Benachrichtigung an User" "$MessageTo" \
		'User, an den die Benachrichtigungen gesendet werden.<br>Auf diese Art kann man sich in Verbindung mit dem Paket &quot;Notification Forwarder&quot; über synOTR-Ereignisse z.B. über einen Pushdienst benachrichtigen lassen.<br>Bleibt der Wert leer, so wird die Gruppe &quot;administrators&quot; benachrichtigt.'

	_apprise_show="$APPRISEURL"
	if [ -z "$_apprise_show" ] && [ -n "$PBTOKEN" ]; then
		case "$PBTOKEN" in
			*://*) _apprise_show="$PBTOKEN" ;;
			*) _apprise_show="pbul://${PBTOKEN}" ;;
		esac
	fi
	synotr_form_text "APPRISEURL" "Apprise-URL" "$_apprise_show" \
		'Eine Apprise-URL für Push (Telegram, ntfy, Discord, Pushover, …).<br>Beispiele: tgram://BOTTOKEN/CHATID &nbsp; ntfy://ntfy.sh/mein-topic &nbsp; pbul://TOKEN<br>Mehrere Ziele: URLs mit Komma trennen.<br>Wiki: https://github.com/caronc/apprise/wiki<br>Bei Nichtgebrauch leer lassen.'
	unset _apprise_show

	synotr_form_switch "dsmbeepnotify" "Systembenachrichtigung (Piep)" "$dsmbeepnotify" \
		'Ein kurzer Piep, sobald ein Film fertig bearbeitet wurde.'

	_synotr_opts="$(synotr_option "0" "aus" "$LOGlevel")$(synotr_option "1" "1 (standard)" "$LOGlevel")$(synotr_option "2" "2 (erweitert)" "$LOGlevel")"
	synotr_form_select "LOGlevel" "LOGlevel (0,1,2)" \
		'0 =&gt; es wird keine Log-Datei erstellt<br>1 =&gt; normales Log (standard)<br>2 =&gt; erweitertes Log<br>Die Logs befinden sich im Dekodierverzeichnis/_LOGsynOTR/' \
		"$_synotr_opts"
	unset _synotr_opts

	synotr_form_text "LOGmax" "max. Anzahl LOGfiles" "$LOGmax" \
		'LOG-Files können automatisch gelöscht werden, indem hier die maximal gewünschte Anzahl angegeben wird.<br>Sobald hier ein Wert vergeben wird, werden grundsätzlich alle leeren LOGs gelöscht.<br>(Die Anzahl bezieht sich also nur auf LOGs mit Einträgen)'

	echo '
    </div>
        </details>
    	<br><hr style="border-style: dashed; size: 1px;">
	</fieldset>'

	if type synotr_folderpicker_emit >/dev/null 2>&1; then
		synotr_folderpicker_emit
	fi

	echo '
	</div>
	</div><div class="clear"></div>
	<div id="minheight"></div>
	<script type="text/javascript">
	(function () {
		var switches = document.querySelectorAll("input.synotr-switch[data-synotr-switch]");
		var i;
		for (i = 0; i < switches.length; i++) {
			(function (sw) {
				var hidden = document.getElementById(sw.getAttribute("data-synotr-switch"));
				if (!hidden) return;
				function syncHidden() {
					hidden.value = sw.checked ? (sw.getAttribute("data-on") || "on") : (sw.getAttribute("data-off") || "off");
				}
				sw.addEventListener("change", syncHidden);
			})(switches[i]);
		}
		var cut = document.getElementById("OTRcutactiv-switch");
		var row = document.getElementById("row_OTRavi2mp4active");
		function syncAvi2mp4Row() {
			if (!cut || !row) return;
			row.style.display = cut.checked ? "none" : "";
		}
		if (cut) {
			cut.addEventListener("change", syncAvi2mp4Row);
			syncAvi2mp4Row();
		}
		var ranges = document.querySelectorAll("input.synotr-range[data-synotr-range]");
		for (i = 0; i < ranges.length; i++) {
			(function (el) {
				var hid = document.getElementById(el.getAttribute("data-synotr-range"));
				var badge = document.getElementById(el.getAttribute("data-synotr-range") + "-value");
				if (!hid) return;
				function syncRange() {
					var stepsAttr = el.getAttribute("data-synotr-steps");
					var unit = el.getAttribute("data-synotr-unit") || "";
					var suffix = el.getAttribute("data-synotr-suffix") || "";
					var signed = el.getAttribute("data-synotr-signed") === "1";
					var val;
					var show;
					var idx;
					var steps;
					if (stepsAttr) {
						steps = stepsAttr.split(",");
						idx = parseInt(el.value, 10);
						if (isNaN(idx) || idx < 0) idx = 0;
						if (idx >= steps.length) idx = steps.length - 1;
						val = steps[idx];
						hid.value = val + suffix;
						show = val;
					} else {
						val = el.value;
						hid.value = val;
						show = val;
						if (signed && parseInt(val, 10) > 0) show = "+" + val;
					}
					if (badge) {
						badge.textContent = unit ? (show + " " + unit) : show;
					}
				}
				el.addEventListener("input", syncRange);
				el.addEventListener("change", syncRange);
			})(ranges[i]);
		}
	})();
	</script>
'
fi
