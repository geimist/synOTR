#!/bin/bash
# footer.sh
# shellcheck disable=SC2154

if [[ "$mainpage" == "edit" ]]; then
	echo '
	    <footer>
        <p>'
		# button:
	echo '
		<div style="text-align: right;">
	    <button name="page" value="edit-save" class="blue_button">Speichern</button>&nbsp;
	    <button name="page" value="edit-import-query">Import</button>&nbsp;
	    <button name="page" value="edit-export">Export</button>&nbsp;
	    <button name="page"><a href="app/etc/Konfiguration.txt" download="Konfiguration.txt">Download</a></button>&nbsp;
	    <button name="page" value="edit-restore-query" class="red_button">R E S E T</button>&nbsp;
	    </div>'
    echo '
        </p>
        </footer>'
	echo '
		<div class="clear"></div>'
fi
