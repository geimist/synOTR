#!/bin/bash
# help.sh
# shellcheck disable=SC2154


echo '
	<div id="Content_1Col">
	<div class="Content_1Col_full">
	<div class="title">
	    synOTR Schnellstart
	</div>
	<ol style="list-style:decimal">
    <p>
    <li>Passe zunächst deine Installation in den <a href="index.cgi?page=edit" style="'"$synotrred"';">Einstellungen</a> an.
    <br>FFmpeg kommt von SynoCommunity (<a href="https://synocommunity.com/package/ffmpeg8" style="'"$synotrred"';">ffmpeg8</a> bevorzugt; ffmpeg7/ffmpeg6 gehen ebenfalls).
    </li></p>
    <p>
    <li>Um synOTR regelmäßig laufen zu lassen (was sich empfiehlt), erstelle als
      nächstes <br>einen automatisierten Programmaufruf im DSM-Aufgabenplaner:
    <p style="margin-left: 40px;"><code>/usr/syno/synoman/webman/3rdparty/synOTR/synOTR-start.sh</code></p>
    <h3>Öffne dazu im DSM die Systemsteuerung </h3>
        <ul class="li_standard">
        <li>Aufgabenplaner </li>
        <li>Schaltfläche <i>Erstellen</i> </li>
        <li><i>geplante Aufgabe</i> </li>
        <li><i>Benutzerdefiniertes Skript</i></li>
        </ul><br>
    <h3>Registerkarte "Allgemein":</h3>
        <ul class="li_standard">
        <li>Benutzer root</li>
        <li>ein beliebiger Name unter <i>Vorgang</i></li>
        <li>Haken bei <i>aktiviert</i></li>
        </ul><br>
    <h3>Registerkarte "Zeitplan":</h3>
        <ul class="li_standard">
        <li>hier gewünschtes Intervall (z.B. stündlich)</li>
        </ul><br>
    <h3>Registerkarte "Aufgabeneinstellung":</h3>
        <ul class="li_standard">
        <li>hier den nachstehenden Pfad hineinkopieren:</li><br>
        <code><span style="background-color:#cccccc;font-hight:1.1em;">/usr/syno/synoman/webman/3rdparty/synOTR/synOTR-start.sh</span></code>
      </ul><br>
    </li></p>
    </ol>
    <hr>
    <p>
    <b>CutEditor:</b> Unter „CutEditor“ in der Seitenleiste kannst du für wartende otr2-MP4 (und optional remuxte otrkey-AVI) Cutlists setzen.
    Filter und otrkey-MP4-Schalter stehen auch in den Einstellungen. Der Filter steuert nur, welche Dateien in der CutEditor-Liste stehen – synOTR schneidet unabhängig davon, sobald eine lokale Cutlist da ist.
    Private Cutlists sind nicht für cutlist.at gedacht. Standard-Warteliste: keine lokale Cutlist und keine bekannte Online-Cutlist
    (frisch dekodiert zählt mit; „gefunden“ kommt vom synOTR-Lauf). Nach dem Speichern einer Cutlist kannst du „Jetzt schneiden“ wählen (gleicher Lauf wie auf der Übersicht).
    Cutlist-Infos (Autor, Kommentar, Fehlerflags, vorgeschlagener Name) folgen dem Format von cutlist.at.
    otrkey-Schnitte im Editor sind nur für den Eigengebrauch, nicht für cutlist.at.
    otrkey-AVI wird mit OTRavi2mp4 ins Dekodierverzeichnis gewandelt (wie ungeschnittene Filme); die AVI wandert in den Papierkorb.
    Im Editor: Klick ins Keep setzt die Playhead dort (Schere teilt), Keyframes per « KF » / Pfeiltasten.
    </p>
    <p>
    Weitere Hilfe findest du derzeit auf der synOTR Homepage: https://synotr.geimist.eu/faq/faq.html
    </p>'
echo '
		</div>
	</div><div class="clear"></div>'