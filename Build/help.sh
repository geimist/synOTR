#!/bin/bash
# help.sh


echo '
	<div id="Content_1Col">
	<div class="Content_1Col_full">
	<div class="title">
	    synOTR Schnellstart
	</div>
	<ol style="list-style:decimal">
    <p>
    <li>Passe zunächst deine Installation in den <a href="index.cgi?page=edit" style="'$synotrred';">Einstellungen</a> an.
    </li></p>
    <p>
    <li>Um synOTR regelmäßig laufen zu lassen (was sich empfiehlt), erstelle als
      nächstes <br>einen automatisierten Programmaufruf.
      <div class="tab"><br>
      Dazu hast du 2 Möglichkeiten:<br>verwende den <a href="index.cgi?page=timer" style="'$synotrred';">Zeitplaner</a> für einen programmierten synOTR-Start.</p><hr>
      <p>Oder, erstelle alternativ im Aufgabenplaner einen neuen Task mit diesem
      Programmpfad<br>(zu empfehlen, sofern du kürzere Intervalle als "stündlich" benötigst):</p>
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
    </ol>
    <hr>
    <p>
    Weitere Hilfe findest du derzeit auf der synOTR Homepage: https://synotr.geimist.eu/faq/faq.html
    </p>'
echo '
		</div>
	</div><div class="clear"></div>'