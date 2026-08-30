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
	echo '<div class="Content_1Col_full synotr-flash">'
	echo '<br /><div class="info"><br /><p class="center" style="color:#0086E5;font-weight:normal; ">Filter gespeichert</p><br /></div>'
	echo '<button name="page" value="cuteditor" class="blue_button synotr-flash-go">Weiter</button>'
	echo '</div><div class="clear"></div>'
	return 0
fi

echo '
	<div id="Content_1Col">
	<div class="Content_1Col_full">
	<div class="title">CutEditor</div>
	<p>Dateien ohne passende Cutlist (nach Filter). Bestehende Online- oder lokale Listen laufen wie bisher durch die Pipeline.</p>
	<p><label for="CutEditorQueue">Warteliste</label>
	<select class="synotr-form-control" name="CutEditorQueue" id="CutEditorQueue">'
if [ "$CutEditorQueue" = "miss_both" ]; then
	echo '<option value="miss_both" selected>keine lokale und keine Online-Cutlist</option>'
else
	echo '<option value="miss_both">keine lokale und keine Online-Cutlist</option>'
fi
if [ "$CutEditorQueue" = "no_local" ]; then
	echo '<option value="no_local" selected>keine lokale Cutlist</option>'
else
	echo '<option value="no_local">keine lokale Cutlist</option>'
fi
if [ "$CutEditorQueue" = "all_uncut" ]; then
	echo '<option value="all_uncut" selected>alle ungeschnittenen</option>'
else
	echo '<option value="all_uncut">alle ungeschnittenen</option>'
fi
echo '</select></p>
	<p><label><input type="hidden" name="CutEditorOtrkeyMp4" value="off"/>'
if [ "$CutEditorOtrkeyMp4" = "on" ]; then
	echo '<input type="checkbox" name="CutEditorOtrkeyMp4" value="on" checked="checked"/>'
else
	echo '<input type="checkbox" name="CutEditorOtrkeyMp4" value="on"/>'
fi
echo ' otrkey-AVI für Eigengebrauch als MP4 (kein Upload nach cutlist.at)</label></p>
	<p><button class="blue_button" name="page" value="cuteditor-savequeue">Filter übernehmen</button></p>
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
print(json.dumps(list_waiting(load_config_from_env()), ensure_ascii=False))
' 2>/dev/null)

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
			echo '<tr><td>'"$_esc"'</td><td>'"$_src"'</td><td>'"$_on"'</td><td>'
			if [ "$_remux" = "true" ]; then
				echo '<a class="blue_button" href="index.cgi?page=cuteditor-api&amp;action=remux&amp;file='"$_fileq"'">Für Editor als MP4</a> '
			fi
			echo '<a href="index.cgi?page=cuteditor-api&amp;action=editor&amp;file='"$_fileq"'">Editor</a>'
			echo '</td></tr>'
			_i=$((_i + 1))
		done
	fi
else
	echo '<tr><td colspan="4">Warteliste konnte nicht geladen werden (Python/jq).</td></tr>'
fi

echo '
	</tbody></table>
	</div>
	<p class="ce-hint">otrkey-AVI: Remux kann mehrere Minuten dauern. Packed-Bitstream kann am Schnitt zittern – nur Eigengebrauch.</p>
	</div></div><div class="clear"></div>'
unset _ce_json _ce_items _n _i _file _src _on _remux _esc
