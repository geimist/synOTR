#!/bin/bash
# shellcheck disable=SC2154
# Folder-Picker-Modal (einmal auf der Konfigurationsseite ausgeben).
# Öffnen: synotr_openPicker(inputId) bzw. Button data-synotr-pick="FELDNAME"

synotr_folderpicker_emit() {
	local _fp_lang
	if command -v jq >/dev/null 2>&1; then
		_fp_lang=$(jq -c -n \
			--arg title         "Ordner auswählen" \
			--arg select        "Übernehmen" \
			--arg abort         "Abbrechen" \
			--arg shares        "Verfügbare Freigaben" \
			--arg back          "Zurück zu den Freigaben" \
			--arg loading       "Lade …" \
			--arg failed_shares "Fehler beim Laden der Freigaben." \
			--arg failed_folders "Fehler beim Laden des Ordners." \
			--arg no_token      "SynoToken nicht verfügbar." \
			--arg not_available "Folder Picker nicht verfügbar" \
			--arg csrf          "Der Folder Picker kann innerhalb des DSM nicht verwendet werden, da der CSRF-Schutz aktiviert ist." \
			--arg csrf_fix      "Um das zu beheben: Systemsteuerung → Sicherheit → „Schutz gegen Cross-Site-Request-Forgery-Attacken verbessern“ deaktivieren, anschließend vom DSM ab- und wieder anmelden." \
			--arg alternative   "Alternativ synOTR in einem neuen Fenster öffnen oder den Pfad manuell eintragen." \
			'{title:$title,select:$select,abort:$abort,shares:$shares,back:$back,loading:$loading,failed_shares:$failed_shares,failed_folders:$failed_folders,no_token:$no_token,not_available:$not_available,csrf:$csrf,csrf_fix:$csrf_fix,alternative:$alternative}')
	else
		_fp_lang='{"title":"Ordner auswählen","select":"Übernehmen","abort":"Abbrechen","shares":"Verfügbare Freigaben","back":"Zurück zu den Freigaben","failed_shares":"Fehler beim Laden der Freigaben.","failed_folders":"Fehler beim Laden des Ordners.","no_token":"SynoToken nicht verfügbar.","not_available":"Folder Picker nicht verfügbar","csrf":"CSRF-Schutz aktiv.","csrf_fix":"","alternative":"Pfad manuell eintragen."}'
	fi

	echo '
	<div id="synotrFolderPickerModal" class="synotr-fp-modal" hidden="hidden" aria-hidden="true" role="dialog" aria-modal="true" aria-labelledby="synotrFolderPickerModalLabel">
		<div class="synotr-fp-dialog">
			<div class="synotr-fp-header">
				<h3 class="synotr-fp-title" id="synotrFolderPickerModalLabel">Ordner auswählen</h3>
				<button type="button" class="synotr-fp-x" data-synotr-fp-close="1" aria-label="Schließen">×</button>
			</div>
			<div id="synotrFolderPickerContent" class="synotr-fp-content"></div>
			<div class="synotr-fp-footer">
				<button type="button" class="synotr-fp-btn" data-synotr-fp-close="1">Abbrechen</button>
				<button type="button" class="synotr-fp-btn synotr-fp-btn-primary" id="synotrFolderPickerConfirm" disabled="disabled">Übernehmen</button>
			</div>
		</div>
	</div>
	<script type="application/json" id="synotr-folderpicker-lang">'"${_fp_lang}"'</script>'
}
