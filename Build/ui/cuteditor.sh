#!/bin/bash
# cuteditor.sh – Warteliste und Filter (Editor: index.cgi?page=cuteditor-api)
# shellcheck disable=SC2154

case "${CutEditorQueue:-miss_both}" in
	miss_both|no_local|all_uncut) ;;
	*) CutEditorQueue="miss_both" ;;
esac
case "${CutEditorOtrkeyMp4:-off}" in
	on|off) ;;
	*) CutEditorOtrkeyMp4="off" ;;
esac

if [[ "$page" == "cuteditor-savequeue" ]]; then
	# Nur speichern, wenn die Felder wirklich in der Query stehen (sonst setzt ein
	# leerer Aufruf CutEditorQueue auf miss_both und die Liste wird leer).
	case "$QUERY_STRING" in
		*CutEditorQueue=*) ;;
		*) page="cuteditor" ;;
	esac
fi
if [[ "$page" == "cuteditor-savequeue" ]]; then
	case "$CutEditorQueue" in
		miss_both|no_local|all_uncut) ;;
		*) CutEditorQueue="miss_both" ;;
	esac
	case "${CutEditorOtrkeyMp4:-off}" in
		on) CutEditorOtrkeyMp4="on" ;;
		*) CutEditorOtrkeyMp4="off" ;;
	esac
	"$set_var" "$dir/app/etc/Konfiguration.txt" "CutEditorQueue" "$CutEditorQueue"
	"$set_var" "$dir/app/etc/Konfiguration.txt" "CutEditorOtrkeyMp4" "$CutEditorOtrkeyMp4"
	page="cuteditor"
fi

# otrkey-AVI → Editor-MP4: HTML-Seite (Content-Type schon von index.cgi), Job im Hintergrund.
# Ein API-CGI ohne Header bis nach OTRavi2mp4 endet unter DSM als 404 oder nacktes JSON.
if [[ "$page" == "cuteditor-remux" ]] || [[ "$page" == "cuteditor-remuxwait" ]]; then
	# shellcheck source=includes/synotr_cuteditor_env.sh
	. ./includes/synotr_cuteditor_env.sh
	synotr_cuteditor_env "$dir"
	_ce_file=$(basename "${file:-}")
	_ce_esc=$(printf '%s' "$_ce_file" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/"/\&quot;/g')
	_ce_fileq=$(printf '%s' "$_ce_file" | "$SYNOTR_PYTHON" -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read().rstrip("\n"), safe=""))')
	_ce_lockdir="/tmp/synOTR"
	mkdir -p "$_ce_lockdir" 2>/dev/null || true
	_ce_tag=$(printf '%s' "$_ce_file" | sed 's/[^A-Za-z0-9._-]/_/g')
	_ce_state="${_ce_lockdir}/ce-remux.${_ce_tag}.state"
	_ce_log="${_ce_lockdir}/ce-remux.${_ce_tag}.log"
	_ce_pidf="${_ce_lockdir}/ce-remux.${_ce_tag}.pid"
	_ce_stem=${_ce_file%.avi}
	_ce_stem=${_ce_stem%.AVI}
	_ce_mp4="${DECODIR%/}/${_ce_stem}.mp4"
	_ce_mp4_legacy="${DECODIR%/}/_cuteditor/${_ce_stem}.mp4"
	if [ -f "$_ce_mp4_legacy" ] && { [ ! -f "$_ce_mp4" ] || [ "$(wc -c < "$_ce_mp4" 2>/dev/null | tr -d ' ')" -lt 1024 ]; }; then
		mv "$_ce_mp4_legacy" "$_ce_mp4" 2>/dev/null || true
	fi

	_ce_running=0
	if [ -f "$_ce_pidf" ]; then
		_ce_pid=$(cat "$_ce_pidf" 2>/dev/null || true)
		if [ -n "$_ce_pid" ] && kill -0 "$_ce_pid" 2>/dev/null; then
			_ce_running=1
		fi
	fi

	if [[ "$page" == "cuteditor-remux" ]] && [ -n "$_ce_file" ]; then
		if [ "$_ce_running" != "1" ] && { [ ! -f "$_ce_mp4" ] || [ "$(wc -c < "$_ce_mp4" 2>/dev/null | tr -d ' ')" -lt 1024 ]; }; then
			echo running > "$_ce_state"
			export SYNOTR_CE_REMUX_FILE="$_ce_file"
			export SYNOTR_CE_REMUX_STATE="$_ce_state"
			export SYNOTR_PYTHON
			# nohup/disown: sonst beendet DSM den Job mit dem CGI → 404 / abgebrochenes JSON.
			nohup /bin/bash -c '
				if "$SYNOTR_PYTHON" -m synotr_cuteditor remux "$SYNOTR_CE_REMUX_FILE"; then
					echo ok > "$SYNOTR_CE_REMUX_STATE"
				else
					echo fail > "$SYNOTR_CE_REMUX_STATE"
				fi
			' >>"$_ce_log" 2>&1 &
			echo $! > "$_ce_pidf"
			disown $! 2>/dev/null || true
		fi
	fi

	echo '<div class="Content_1Col_full">'
	echo '<div class="title">CutEditor</div>'
	if [ -z "$_ce_file" ]; then
		echo '<p>Keine Datei angegeben.</p><p><a href="index.cgi?page=cuteditor">Zur Liste</a></p>'
	elif [ -f "$_ce_mp4" ] && [ "$(wc -c < "$_ce_mp4" | tr -d ' ')" -gt 1024 ]; then
		_ce_mp4q=$(printf '%s' "${_ce_stem}.mp4" | "$SYNOTR_PYTHON" -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read().rstrip("\n"), safe=""))')
		echo '<p>MP4 für den Editor ist fertig (Dekodierordner). Die AVI liegt im Papierkorb.</p>'
		echo '<meta http-equiv="refresh" content="0; URL=index.cgi?page=cuteditor-api&amp;action=editor&amp;file='"$_ce_mp4q"'"/>'
		echo '<p><a class="blue_button synotr-ce-act" href="index.cgi?page=cuteditor-api&amp;action=editor&amp;file='"$_ce_mp4q"'">Zum Editor</a></p>'
	elif [ -f "$_ce_state" ] && grep -q '^fail$' "$_ce_state"; then
		echo '<p class="center" style="color:#BD0010;">Konvertierung fehlgeschlagen.</p>'
		echo '<pre class="synotr-scroll">'
		tail -n 40 "$_ce_log" 2>/dev/null | sed 's/&/\&amp;/g; s/</\&lt;/g'
		echo '</pre>'
		echo '<p><a href="index.cgi?page=cuteditor">Zur Liste</a></p>'
	else
		echo '<p>otrkey-AVI wird für den Editor nach MP4 gewandelt (kann mehrere Minuten dauern):</p>'
		echo '<p><code>'"$_ce_esc"'</code></p>'
		echo '<p>Diese Seite aktualisiert sich selbst. Bitte warten …</p>'
		echo '<meta http-equiv="refresh" content="4; URL=index.cgi?page=cuteditor-remuxwait&amp;file='"$_ce_fileq"'"/>'
		echo '<p><a class="blue_button synotr-ce-act" href="index.cgi?page=cuteditor-remuxwait&amp;file='"$_ce_fileq"'">Status neu laden</a></p>'
	fi
	echo '</div><div class="clear"></div>'
	unset _ce_file _ce_esc _ce_fileq _ce_lockdir _ce_tag _ce_state _ce_log _ce_pidf _ce_stem _ce_mp4 _ce_running _ce_pid _ec
	return 0
fi

# shellcheck source=includes/synotr_form.sh
. ./includes/synotr_form.sh

echo '
	<div id="Content_1Col">
	<div class="Content_1Col_full synotr-form-page">
	<div class="title">CutEditor</div>
	<p>Dateien ohne passende Cutlist (nach Filter). Bestehende Online- oder lokale Listen laufen wie bisher durch die Pipeline.</p>'

_ce_q_opts="$(synotr_option "miss_both" "keine lokale und keine Online-Cutlist" "${CutEditorQueue:-miss_both}")$(synotr_option "no_local" "keine lokale Cutlist" "${CutEditorQueue:-miss_both}")$(synotr_option "all_uncut" "alle ungeschnittenen" "${CutEditorQueue:-miss_both}")"
synotr_form_select "CutEditorQueue" "Warteliste" \
	'Welche Dateien der CutEditor anbietet (nur die Warteliste, nicht ob synOTR schneidet). Standard: keine lokale Cutlist und keine bekannte Online-Cutlist.<br>Private/Eigengebrauch-Cutlists sind nicht für cutlist.at gedacht.' \
	"$_ce_q_opts"

synotr_form_switch "CutEditorOtrkeyMp4" "otrkey-AVI als MP4" "${CutEditorOtrkeyMp4:-off}" \
	'ein =&gt; AVI ohne Cutlist können für den Eigengebrauch nach MP4 remuxt und im CutEditor geschnitten werden (OTRavi2mp4). Die MP4 liegt im Dekodierordner, die AVI wandert in den Papierkorb. Cutlists sind privat und nicht für cutlist.at gedacht.<br>aus =&gt; nur otr2-MP4.<br><br>Kein Stammtausch AVI↔MP4 in der Datenbank. Packed-Bitstream kann zittern.'

echo '
	<div class="synotr-scroll">
	<table class="synotr-ce-table">
	<thead><tr><th>Datei</th><th>Quelle</th><th>Online</th><th>Aktion</th></tr></thead>
	<tbody>'

# shellcheck source=includes/synotr_cuteditor_env.sh
. ./includes/synotr_cuteditor_env.sh
synotr_cuteditor_env "$dir"
_ce_items=$("$SYNOTR_PYTHON" -c '
import json, os, sys
sys.path.insert(0, os.environ.get("PYTHONPATH","").split(":")[0])
from synotr_cuteditor.cli import load_config_from_env
from synotr_cuteditor.waiting import list_waiting
_cfg = load_config_from_env()
_cfg.clear_frame_cache()
print(json.dumps(list_waiting(_cfg), ensure_ascii=False))
' 2>/dev/null)

_ce_otrkey_tip="otrkey-AVI: Remux kann mehrere Minuten dauern. Packed-Bitstream kann am Schnitt zittern – nur Eigengebrauch, kein Upload nach cutlist.at."

if command -v jq >/dev/null 2>&1 && [ -n "$_ce_items" ]; then
	_n=$(printf '%s' "$_ce_items" | jq 'length')
	if [ "$_n" = "0" ]; then
		echo '<tr><td colspan="4">Keine Dateien für diesen Filter.</td></tr>'
	else
		_i=0
		while [ "$_i" -lt "$_n" ]; do
			_file=$(printf '%s' "$_ce_items" | jq -r --argjson i "$_i" '.[$i].file')
			_src=$(printf '%s' "$_ce_items" | jq -r --argjson i "$_i" '.[$i].source')
			_on=$(printf '%s' "$_ce_items" | jq -r --argjson i "$_i" '.[$i].cutlist_online')
			_remux=$(printf '%s' "$_ce_items" | jq -r --argjson i "$_i" '.[$i].needs_remux')
			_esc=$(printf '%s' "$_file" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/"/\&quot;/g')
			_fileq=$(printf '%s' "$_ce_items" | jq -r --argjson i "$_i" '.[$i].file | @uri')
			echo '<tr><td>'"$_esc"'</td><td>'
			printf '%s' "$_src"
			if [ "$_src" = "otrkey" ]; then
				echo ' <span class="synotr-ce-warn" title="'"$(printf '%s' "$_ce_otrkey_tip" | sed 's/"/\&quot;/g')"'">⚠️</span>'
			fi
			echo '</td><td>'"$_on"'</td><td class="synotr-ce-actions">'
			if [ "$_remux" = "true" ]; then
				echo '<a class="blue_button synotr-ce-act" href="index.cgi?page=cuteditor-remux&amp;file='"$_fileq"'">Für Editor konvertieren</a>'
			else
				echo '<a class="blue_button synotr-ce-act" href="index.cgi?page=cuteditor-api&amp;action=editor&amp;file='"$_fileq"'">Editor</a>'
			fi
			echo '</td></tr>'
			_i=$((_i + 1))
		done
	fi
else
	echo '<tr><td colspan="4">Warteliste konnte nicht geladen werden (Python/jq).</td></tr>'
fi

echo '
	</tbody></table>
	<p class="synotr-ce-hint">Nach der Konvertierung liegt die MP4 im Dekodierordner (wie andere ungeschnittene Filme). Die AVI wird in den Papierkorb verschoben.</p>
	</div>
	</div></div><div class="clear"></div>
	<script type="text/javascript">
	(function () {
		function submitQueue() {
			var form = document.querySelector("form");
			if (!form) return;
			var inp = document.createElement("input");
			inp.type = "hidden";
			inp.name = "page";
			inp.value = "cuteditor-savequeue";
			form.appendChild(inp);
			form.submit();
		}
		var sel = document.getElementById("CutEditorQueue");
		if (sel) sel.addEventListener("change", submitQueue);
		var switches = document.querySelectorAll("input.synotr-switch[data-synotr-switch]");
		var i;
		for (i = 0; i < switches.length; i++) {
			(function (sw) {
				var hidden = document.getElementById(sw.getAttribute("data-synotr-switch"));
				if (!hidden) return;
				sw.addEventListener("change", function () {
					hidden.value = sw.checked ? (sw.getAttribute("data-on") || "on") : (sw.getAttribute("data-off") || "off");
					submitQueue();
				});
			})(switches[i]);
		}
	})();
	</script>'
unset _ce_json _ce_items _n _i _file _src _on _remux _esc _ce_q_opts _ce_otrkey_tip
