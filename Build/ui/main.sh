#!/bin/bash
# main.sh – Übersicht inkl. Status
# shellcheck disable=SC2154

. ./status.sh

if [[ "$page" == "status-run-synotr" ]] || [[ "$page" == "status-kill-synotr" ]]; then
	return 0
fi

# Hinweise nur auf der Übersicht (ffmpeg, alter crontab-Eintrag).
synotr_gui_overview_notices() {
	_synotr_ffmpeg_found=""
	_synotr_show_ffmpeg_notice=""
	synotr_legacy_cron_lines=""
	if [ -r /etc/crontab ]; then
		synotr_legacy_cron_lines=$(grep -F 'synOTR-start.sh' /etc/crontab 2>/dev/null | grep -vE '^[[:space:]]*#' || true)
	fi
	# dieselbe Reihenfolge wie synOTR.sh: ffmpeg8, sonst 7, sonst 6
	if [ -x /usr/local/bin/ffmpeg8 ] && [ -x /usr/local/bin/ffprobe8 ]; then
		_synotr_ffmpeg_found="/usr/local/bin/ffmpeg8"
	else
		for _synotr_ffver in 7 6; do
			if [ -x "/usr/local/bin/ffmpeg${_synotr_ffver}" ] && [ -x "/usr/local/bin/ffprobe${_synotr_ffver}" ]; then
				_synotr_ffmpeg_found="/usr/local/bin/ffmpeg${_synotr_ffver}"
				break
			fi
		done
		unset _synotr_ffver
		_synotr_show_ffmpeg_notice=1
	fi
	if [ -z "$synotr_legacy_cron_lines" ] && [ "$_synotr_show_ffmpeg_notice" != "1" ]; then
		unset _synotr_ffmpeg_found _synotr_show_ffmpeg_notice
		return 0
	fi
	echo '
	<div class="notice-wrap">'
	if [ "$_synotr_show_ffmpeg_notice" = "1" ]; then
		if [ -z "$_synotr_ffmpeg_found" ]; then
			echo '
	<details class="notice" open>
		<summary>Kein SynoCommunity-ffmpeg gefunden</summary>
		<p>synOTR braucht <b>ffmpeg8</b> (empfohlen), ffmpeg7 oder ffmpeg6 von SynoCommunity unter <code>/usr/local/bin</code>. Ohne eines davon bricht jeder Lauf sofort ab.</p>'
		else
			echo '
	<details class="notice">
		<summary>ffmpeg8 von SynoCommunity fehlt</summary>
		<p>Aktuell: <code>'"$_synotr_ffmpeg_found"'</code>. Decodieren, Schneiden und MP4 funktionieren damit. .otr2-Smartrendering (avcut&nbsp;0.8) braucht ffmpeg8 und fällt sonst auf den Keyframe-Schnitt zurück.</p>'
		fi
		echo '
		<p>Im Paketzentrum unter Einstellungen die Quelle <code>https://packages.synocommunity.com/</code> eintragen und anschließend <b>ffmpeg8</b> installieren.</p>
		<p><a href="https://synocommunity.com/package/ffmpeg8" rel="external">synocommunity.com/package/ffmpeg8</a></p>
		<p>Diese Seite danach neu laden.</p>
	</details>'
	fi
	if [ -n "$synotr_legacy_cron_lines" ]; then
		echo '
	<details class="notice">
		<summary>Alter Zeitplaner-Eintrag in /etc/crontab</summary>
		<p>Der synOTR-Zeitplaner ist unter DSM&nbsp;7 entfernt. In <code>/etc/crontab</code> steht noch mindestens ein Eintrag, der synOTR unabhängig vom DSM-Aufgabenplaner startet:</p>
		<p><code>'
		while IFS= read -r _synotr_cronline; do
			[ -n "$_synotr_cronline" ] || continue
			_synotr_cronline=${_synotr_cronline//$'\t'/ }
			_synotr_cronline=$(printf '%s' "$_synotr_cronline" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
			echo "${_synotr_cronline}<br />"
		done <<< "$synotr_legacy_cron_lines"
		echo '</code></p>
		<p>Zum Entfernen eine <b>einmalige</b> Aufgabe im DSM-Aufgabenplaner als Benutzer <b>root</b> anlegen und ausführen:</p>
		<p><code>sed -i '"'"'/synOTR-start.sh/d'"'"' /etc/crontab</code></p>
		<p>Diese Seite danach neu laden. Den regelmäßigen Start bitte über den DSM-Aufgabenplaner einrichten (siehe Hilfe).</p>
	</details>'
		unset _synotr_cronline
	fi
	echo '
	</div>'
	unset _synotr_ffmpeg_found _synotr_show_ffmpeg_notice
}

if [ "$rowcount" != "0" ]; then
echo "<script type='text/javascript'>
      google.charts.load('current', {'packages':['corechart']});
      google.charts.setOnLoadCallback(function() {
        var d = document.getElementById('synotr-stats');
        if (d && d.open) { drawChart(); }
      });
      document.addEventListener('DOMContentLoaded', function() {
        var d = document.getElementById('synotr-stats');
        if (!d) { return; }
        d.addEventListener('toggle', function() {
          if (this.open) { drawChart(); }
        });
      });

      function drawChart() {
        if (typeof google === 'undefined' || !google.visualization) { return; }
        var el = document.getElementById('chart_div');
        if (!el) { return; }
        var data = new google.visualization.DataTable();
        data.addColumn('string', 'Filmtyp');
        data.addColumn('number', 'Anzahl');
        data.addRows([
            ['LQ-Filme', "$CountLQ" ],
            ['SD-Filme', "$CountSD" ],
            ['HQ-Filme', "$CountHQ" ],
            ['HD-Filme', "$CountHD" ],
            ['AC3-Filme', "$CountAC3" ]
        ]);
        var options = { 'title':'none',
                        'width':200,
                        'height':200,
                        'chartArea':{   left:20,
                                        top:10,
                                        width:'90%',
                                        height:'85%'
                                    },
                        'is3D':false,
                        'legend': 'none',
                        'pieSliceText': 'none',
                        'slices': { 0: {color: '"$ColorLQ"' },
                                    1: {color: '"$ColorSD"' },
                                    2: {color: '"$ColorHQ"' },
                                    3: {color: '"$ColorHD"' },
                                    4: {color: '"$ColorAC3"' }
                                  }
                      };
        var chart = new google.visualization.PieChart(el);
        chart.draw(data, options);
        }
    </script>"
fi

    echo '
	<div id="Content_1Col">
		<div class="Content_1Col_full">'
synotr_gui_overview_notices
echo '
    	<div class="title">'

if [ "$count_otrkey" = "0" ] && [ "$count_waitofcutlist" = "0" ]; then
    echo '<img class="imageStyle"
        src="images/status_green@geimist.svg"
        height="120"
        width="120"
        style="float:right;padding: 10px">'
else
    echo '<img class="imageStyle"
        src="images/sanduhr_blue@geimist.svg"
        height="120"
        width="120"
        style="float:right;padding: 10px">'
fi

echo '  synOTR</div>
        <p style="text-align:center"> <span style="color:#BD0010;font-weight:bold;font-size:1.1em; ">decodieren - schneiden - mp4 erstellen - umbenennen</span> </p>
    	<br /><p class="center"><button name="page" class="blue_button" value="status-run-synotr">jetzt manuellen synOTR Durchlauf starten</button></p><br />'

echo '<fieldset>
	<hr style="border-style: dashed; size: 1px;">
	<br />
    <details><p>
    <summary>
        <span class="detailsitem">Beschreibung</span>
    </summary></p>
        <p style="text-align:left;">
          SynOTR liefert einen kompletten Workflow für TV-Aufnahmen von <a href="http://www.onlinetvrecorder.com"
            rel="external">onlineTVrecorder</a>
          (OTR) auf einer Synology Diskstation (x86_64 / armv8). Es wurde
          gezielt auf Einfachheit hin entwickelt.</p>
        <p style="text-align:left;"> <a href="http://www.onlinetvrecorder.com"
            rel="external">onlineTVrecorder</a>
          (OTR) ist der freie Videorecorder im Internet, der rund um die Uhr
          ALLE Sendungen ALLER Sender aufzeichnet (naja, auf jeden Fall viele …
          ;-) ). Es werden über 100 TV-Sender aus Deutschland, USA, UK und
          anderen Ländern aufgenommen. Du kannst diese Filme später gratis
          herunterladen.<br>
          <br>
          <strong>Folgende Aufgaben werden durch synOTR automatisch
            abgearbeitet:</strong></p>
        <ul class="li_standard">
          <li><span style="color:#0086E5;font-weight:bold; ">Verschlüsselte .otrkey- und .otr2-Dateien dekodieren</span></li>
          <li><span style="color:#0086E5;font-weight:bold; ">automatische AC3-Tonspurintegration (BETA)</span></li>
          <li><span style="color:#0086E5;font-weight:bold; ">Filme schneiden</span> (Quelle: cutlist.at)</li>
          <li><span style="color:#0086E5;font-weight:bold; ">Filme nach eigenen Regeln umbenennen</span>
            <div class="tab">            Serien werden automatisch erkannt (SxxExx im Dateinamen oder aus der Cutlist) und der Sendungsname in einem
            üblichen Serienformat umbenannt (Serientitel.S01.E01
            Episodentitel … [individualisierbar]).<br>
            <br>
            Serieninformationen kommen von www.thetvdb.com (API v4), wenn in den Einstellungen ein API-Key hinterlegt ist.
            Bitte unterstützt diesen kostenlosen Service, indem ihr nach
            Möglichkeit Informationen und Grafiken beitragt und ergänzt.
            </div>
            </li>
          <li><span style="color:#0086E5;font-weight:bold; ">Konvertieren
              der AVI-Dateien in native MP4-Dateien</span> (Mac OS tauglich)<br>
            <div class="tab">Für den ersten Programmaufruf ist zu beachten, dass alle avi-Dateien
            im Zielordner konvertiert werden, was eine sehr lange Zeit erfordern
            kann. Das lässt sich vermeiden, wenn man in den Einstellungen auch
            den Arbeitsordner definiert.</div></li>
        </ul>
        <br>
        Lässt man sich fertige Aufnahmen per FTP-Push (z.B. Serien) auf das NAS
        übertragen, hat man ohne Zutun fertig geschnittene Aufnahmen.<br>
        <br>
        Mein Ziel war es, jetzt eine kompakte Lösung anbieten zu können, die für
        jedermann (vor allem auch Einsteiger) einfach nutzbar sein soll, ohne
        dass sich jeder in die Materie einarbeiten muss. Es ist also nichts an
        Skripten zu ändern, noch müssen zusätzliche Programme installiert
        werden. Alle entsprechenden Programme sind in dem Paket enthalten.
    </details>
    </fieldset>'

echo '<fieldset>
	<hr style="border-style: dashed; size: 1px;">
	<br />
	<details id="synotr-stats"><p>
    <summary>
        <span class="detailsitem">Status</span>
    </summary></p>'

echo '<table style="width: 700px;" >
    <tr>
        <th style="width: 1;"></th><th style="width: 250px;"></th><th></th><th style="width: 250px;"></th>
    </tr>
    <tr>
        <td class="td_color" colspan="2"><b>Offene Aufgaben:</b></td><td></td><td></td>
    </tr>'

    if [ "$count_otrkey" = "0" ]; then
        echo '<tr><td class="td_color"></td><td><span style="color:#0086E5;font-weight:normal; ">Dateien zu dekodieren: </span></td>
        <td><span style="color:green;font-weight: bold;">Alles erledigt</span></td></tr>'
    else
        echo '<tr><td class="td_color"></td><td><span style="color:#0086E5;font-weight:normal; ">Dateien zu dekodieren: </span></td>
        <td><span style="color:#BD0010;font-weight: bold;">'"$count_otrkey"'</span></td></tr>'
    fi

    if [ "$count_waitofcutlist" = "0" ]; then
        echo '<tr><td class="td_color"></td><td><span style="color:#0086E5;font-weight:normal; ">Filme, die auf Cutlist warten: </span></td>
        <td><span style="color:green;font-weight: bold;">Alles erledigt</span></td></tr>'
    else
        echo '<tr><td class="td_color"></td><td><span style="color:#0086E5;font-weight:normal; ">Filme, die auf Cutlist warten: </span></td>
        <td><span style="color:#BD0010;font-weight: bold;">'"$count_waitofcutlist"'</span></td></tr>'
    fi

if [ "$rowcount" != "0" ]; then
    echo '<tr><td class="td_color" colspan="2"><br><b>Auswertung der Datenbank:</b></td><td></td></tr>'
    echo '<tr><td class="td_color" style="background-color:'"$ColorLQ"';"></td><td><span style="color:#0086E5;font-weight:normal; ">Anzahl der LQ-Filme:</td><td><span style="color:green;font-weight: bold;">'"$CountLQ"'</span></td><td rowspan="8">
            <div id="chart_div"></div><noscript>Sie haben JavaScript deaktiviert. Daher ist hier kein Diagramm zu sehen.</noscript>
          </td></tr>'
    echo '<tr><td class="td_color" style="background-color:'"$ColorSD"';"></td><td><span style="color:#0086E5;font-weight:normal; ">Anzahl der SD-Filme:</td><td><span style="color:green;font-weight: bold;">'"$CountSD"'</span></td></tr>'
    echo '<tr><td class="td_color" style="background-color:'"$ColorHQ"';"></td><td><span style="color:#0086E5;font-weight:normal; ">Anzahl der HQ-Filme:</td><td><span style="color:green;font-weight: bold;">'"$CountHQ"'</span></td></tr>'
    echo '<tr><td class="td_color" style="background-color:'"$ColorHD"';"></td><td><span style="color:#0086E5;font-weight:normal; ">Anzahl der HD-Filme:</td><td><span style="color:green;font-weight: bold;">'"$CountHD"'</span></td></tr>'
    echo '<tr><td class="td_color" style="background-color:'"$ColorAC3"';"></td><td><span style="color:#0086E5;font-weight:normal; ">Anzahl der AC3-Filme:</td><td><span style="color:green;font-weight: bold;">'"$CountAC3"'</span></td></tr>'
    echo '<tr><td class="td_color"></td><td><br><span style="color:#0086E5;font-weight:normal; ">Erkannte Serienepisoden:</td><td><br><span style="color:green;font-weight: bold;">'"$CountEpisode"'</span></td></tr>'
    echo '<tr><td class="td_color"></td><td><span style="color:#0086E5;font-weight:normal; ">Gesamt seit '"$firstrun"':</td><td><span style="color:green;font-weight: bold;">'"$rowcount"'</span></td></tr>'
    echo '<tr><td class="td_color"></td><td><span style="color:#0086E5;font-weight:normal; ">Datenbankgröße:</td><td><span style="color:green;font-weight: bold;">'"$dbsize"'B</span></td></tr>'
fi

    echo '
    </table>
    </details>
    </fieldset>'

echo '<fieldset>
	<hr style="border-style: dashed; size: 1px;">
	<br />
	<details><p>
    <summary>
        <span class="detailsitem">LOG-Protokoll</span>
    </summary></p>
        <p>
            Hier werden die LOGs zu finden sein …
            <br>(noch nicht implementiert)
	    </p>
    </details>
    </fieldset>'

echo '
		</div>
	</div>
    <br /></p><p style="text-align:center;"><br /><br /></p>
	<div class="clear"></div>'
