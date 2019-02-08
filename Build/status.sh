#!/bin/bash
# status.sh

#    APPDIR=$(cd $(dirname $0);pwd)
#    CONFIG=app/etc/Konfiguration.txt
#    source ${APPDIR}/${CONFIG}
	if [ -z "$WORKDIR" ] ; then
	    WORKDIR="${DESTDIR}"
    fi
    if [ $OTRcutactiv = "off" ] ; then
		DECODIR="$WORKDIR"
	else
	    DECODIR="${WORKDIR%/}/_decodiert"
    fi
    
# last Log:  (ToDo: nicht nur letztes Log, sondern per ListBox beliebiges Logfile auswählen)
# ---------------------------------------------------------------------
func_main_LastLog () {
    if [ -z $WORKDIR ] ; then
        WORKDIR="${DESTDIR%/}/"
    else
        WORKDIR="${WORKDIR%/}/"
    fi
	DECODIR="${WORKDIR%/}/_decodiert"
    if [ $OTRcutactiv = "off" ] ; then
		DECODIR="$WORKDIR"
		echo "ist off"
	fi

	lastLog=`ls -tr ${DECODIR%/}/_LOGsynOTR | grep ".log" | tail -1`
	lastLogPath="${DECODIR%/}/_LOGsynOTR/$lastLog"
}


# Info der Datenbank auslesen:
# ---------------------------------------------------------------------
    ColorLQ="#990099"
    ColorSD="#3366CC"
    ColorHQ="#DC3912"
    ColorHD="#FF9900"
    ColorAC3="#109618"
    
    dbpath="/usr/syno/synoman/webman/3rdparty/synOTR/app/etc/synOTR.sqlite"
    if [ -f "$dbpath" ] ; then
    	firstrun=$(sqlite3 "$dbpath" "SELECT timestamp FROM raw WHERE rowid=1")
    	rowcount=$(sqlite3 "$dbpath" "SELECT COUNT(*) FROM raw")
    	dbsize=$(ls -lh "$dbpath" | awk '{ print $5 }')
        
    # Anzahl HD-Filme:    
		#sSQL="SELECT count(rowid) FROM raw WHERE file_original LIKE '%HD.avi' OR file_original LIKE '%HD.mp4' "
		CountHD=0
#		sSQL="SELECT count(rowid) FROM raw WHERE format='HD' "
        sSQL="SELECT count(rowid) FROM raw WHERE format='HD' OR ((file_original LIKE '%HD.avi' OR file_original LIKE '%HD.mp4') AND format IS NULL) "
		CountHD=`sqlite3 -separator $'\t' "$dbpath" "$sSQL"`
        
    # Anzahl AC3-Filme:    
		CountAC3=0
		sSQL="SELECT count(rowid) FROM raw WHERE file_original LIKE '%HD.ac3' "
		CountAC3=`sqlite3 -separator $'\t' "$dbpath" "$sSQL"`
        
    # Anzahl HQ-Filme:    
		CountHQ=0
		sSQL="SELECT count(rowid) FROM raw WHERE format='HQ' OR ((file_original LIKE '%HQ.avi' OR file_original LIKE '%HQ.mp4') AND format IS NULL) "
		CountHQ=`sqlite3 -separator $'\t' "$dbpath" "$sSQL"`
        
    # Anzahl Standard-Filme:    
		CountSD=0
		#sSQL="SELECT count(rowid) FROM raw WHERE format='SD' "
		sSQL="SELECT count(rowid) FROM raw WHERE format='SD' OR (file_original LIKE '%mpg.avi' AND format IS NULL) "
		CountSD=`sqlite3 -separator $'\t' "$dbpath" "$sSQL"`
        
    # Anzahl LQ-Filme:    
		CountLQ=0
		#sSQL="SELECT count(rowid) FROM raw WHERE format='LQ' "
		sSQL="SELECT count(rowid) FROM raw WHERE format='LQ' OR (file_original LIKE '%mpg.mp4' AND format IS NULL) "
		CountLQ=`sqlite3 -separator $'\t' "$dbpath" "$sSQL"`
        
    # Anzahl Serien (Episoden):    
		CountEpisode=0
		sSQL="SELECT count(rowid) FROM raw WHERE serie_episode <> '' " # OR (file_original LIKE '%mpg.mp4' AND format IS NULL) "
		CountEpisode=`sqlite3 -separator $'\t' "$dbpath" "$sSQL"`
    fi
    

# Dateistatus auslesen:
# ---------------------------------------------------------------------
    # .otrkey-Files:
    count_otrkey=$( ls -t "${OTRkeydir}" | egrep -o '.*.otrkey$' | wc -l ) # wie viele Dateien 

    # wait of cutlist:
    count_waitofcutlist=$( expr $( ls -t "${DECODIR}" | egrep -o '.*.avi$' | wc -l ) + $( ls -t "${DECODIR}" | egrep -o '.*.mp4$' | wc -l ) ) # wie viele Dateien 
    

# manueller synOTR-Start:
# ---------------------------------------------------------------------
if [[ "$page" == "status-run-synotr" ]]; then
	echo '
	<div class="Content_1Col_full">'
	    /usr/syno/synoman/webman/3rdparty/synOTR/synOTR-start.sh GUI
        func_main_LastLog
#	echo $refreshtime
	echo '<meta http-equiv="refresh" content="2; URL=index.cgi?page=status"></div>'
fi


# synOTR beenden erzwingen:
# ---------------------------------------------------------------------
if [[ "$page" == "status-kill-synotr" ]]; then
	killall synOTR.sh
	echo '<meta http-equiv="refresh" content="0; URL=index.cgi?page=status">'
fi


if [[ "$page" == "status" ]]; then
# Chart-JavaScript:
echo "<script type='text/javascript'>
    // https://developers.google.com/chart/interactive/docs/basic_customizing_chart
    
      // Load the Visualization API and the corechart package.
      google.charts.load('current', {'packages':['corechart']});

      // Set a callback to run when the Google Visualization API is loaded.
      google.charts.setOnLoadCallback(drawChart);

      // Callback that creates and populates a data table, instantiates the pie chart, passes in the data and draws it.
      function drawChart() {

        // Create the data table.
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

        // Set chart options
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

        // Instantiate and draw our chart, passing in some options.
        var chart = new google.visualization.PieChart(document.getElementById('chart_div'));
        chart.draw(data, options);
        }
    </script>"
    
# Body:
# ---------------------------------------------------------------------
echo '  <div class="Content_1Col_full">
    	<div class="title">'

if [[ "$count_otrkey" == 0 ]] && [[ "$count_waitofcutlist" == 0 ]]; then
    echo '<div class="image-right"> </div>
        <img class="imageStyle"
        src="images/status_green@geimist.svg"
        height="120"
        width="120"
        style="float:right;padding: 10px">'   	    
else	    
    echo '<div class="image-right"> </div>
        <img class="imageStyle"
        src="images/sanduhr_blue@geimist.svg"
        height="120"
        width="120"
        style="float:right;padding: 10px">'    	    
fi  	    
    
echo '  synOTR Statusseite</div>
    	<br><br><br><p class="center"><button name="page" class="blue_button" value="status-run-synotr">jetzt manuellen synOTR Durchlauf starten</button></p><br />'
	
# Abschnitt LOG-Protokoll:	
echo '<fieldset>
	<hr style="border-style: dashed; size: 1px;">
	<br />
	<details><p>
    <summary>
        <span class="detailsitem">LOG-Protokoll:</span>
    </summary></p>
        <p>
            Hier werden die LOGs zu finden sein …
            <br>(noch nicht implementiert)
	    </p>
    </details>
    </fieldset>'
	
# Abschnitt Status / Statistik:	
echo '<fieldset>
	<hr style="border-style: dashed; size: 1px;">
	<br />
	<details><p>
    <summary>
        <span class="detailsitem">Status:</span>
    </summary></p>'

echo '<table style="width: 700px;" >
    <tr>   
        <th style="width: 1;"></th><th style="width: 250px;"></th><th></th><th style="width: 250px;"></th>
    </tr>
    <tr>
        <td class="td_color" colspan="2"><b>Offene Aufgaben:</b></td><td></td><td></td>
    </tr>'
 
    if [[ "$count_otrkey" == 0 ]]; then
        echo '<tr><td class="td_color"></td><td><span style="color:#0086E5;font-weight:normal; ">Dateien zu dekodieren: </span></td>
        <td><span style="color:green;font-weight: bold;">Alles erledigt</span></td></tr>'
    else
        echo '<tr><td class="td_color"></td><td><span style="color:#0086E5;font-weight:normal; ">Dateien zu dekodieren: </span></td>
        <td><span style="color:#BD0010;font-weight: bold;">'$count_otrkey'</span></td></tr>'
    fi
    
    if [[ "$count_waitofcutlist" == 0 ]]; then
        echo '<tr><td class="td_color"></td><td><span style="color:#0086E5;font-weight:normal; ">Filme, die auf Cutlist warten: </span></td>
        <td><span style="color:green;font-weight: bold;">Alles erledigt</span></td></tr>'
    else
        echo '<tr><td class="td_color"></td><td><span style="color:#0086E5;font-weight:normal; ">Filme, die auf Cutlist warten: </span></td>
        <td><span style="color:#BD0010;font-weight: bold;">'$count_waitofcutlist'</span></td></tr>'
    fi
    
if [[ "$rowcount" != "0" ]]; then
    echo '<tr><td class="td_color" colspan="2"><br><b>Auswertung der Datenbank:</b></td><td></td></tr>'
    echo '<tr><td class="td_color" bgcolor='$ColorLQ'></td><td><span style="color:#0086E5;font-weight:normal; ">Anzahl der LQ-Filme:</td><td><span style="color:green;font-weight: bold;">'$CountLQ'</span></td><td rowspan="8">
            <!--Div that will hold the pie chart-->
            <div id="chart_div"></div><noscript>Sie haben JavaScript deaktiviert. Daher ist hier kein Diagramm zu sehen.</noscript>
          </td></tr>'
    echo '<tr><td class="td_color" bgcolor='$ColorSD'></td><td><span style="color:#0086E5;font-weight:normal; ">Anzahl der SD-Filme:</td><td><span style="color:green;font-weight: bold;">'$CountSD'</span></td></tr>'
    echo '<tr><td class="td_color" bgcolor='$ColorHQ'></td><td><span style="color:#0086E5;font-weight:normal; ">Anzahl der HQ-Filme:</td><td><span style="color:green;font-weight: bold;">'$CountHQ'</span></td></tr>'
    echo '<tr><td class="td_color" bgcolor='$ColorHD'></td><td><span style="color:#0086E5;font-weight:normal; ">Anzahl der HD-Filme:</td><td><span style="color:green;font-weight: bold;">'$CountHD'</span></td></tr>'
    echo '<tr><td class="td_color" bgcolor='$ColorAC3'></td><td><span style="color:#0086E5;font-weight:normal; ">Anzahl der AC3-Filme:</td><td><span style="color:green;font-weight: bold;">'$CountAC3'</span></td></tr>'
#    echo '<tr><td></td></tr>'
    echo '<tr><td class="td_color" bgcolor=#fff></td><td><br><span style="color:#0086E5;font-weight:normal; ">Erkannte Serienepisoden:</td><td><br><span style="color:green;font-weight: bold;">'$CountEpisode'</span></td></tr>'
    echo '<tr><td class="td_color" bgcolor=#fff></td><td><span style="color:#0086E5;font-weight:normal; ">Gesamt seit '$firstrun':</td><td><span style="color:green;font-weight: bold;">'$rowcount'</span></td></tr>'
    echo '<tr><td class="td_color" bgcolor=#fff></td><td><span style="color:#0086E5;font-weight:normal; ">Datenbankgröße:</td><td><span style="color:green;font-weight: bold;">'$dbsize'B</span></td></tr>'
fi
        
    echo '
    </table>
        <!-- <p>Hier wird in Zukunft noch eine Statusübersicht / Statistik zu finden sein …<br>
        - https://developers.google.com/chart/interactive/docs/quick_start<br>
        - http://jsfiddle.net/api/post/jquery/1.6/ (http://elycharts.com/examples) </p>
        <br><div class="tab"><p>'$dbinfo'</p></div>-->
    
    </details>
    
    <br>
	<hr style="border-style: dashed; size: 1px;">
    </fieldset>'	
		
	echo '
		</div>
    </div>
    <br /></p><p style="text-align:center;"><br /><br /></p>'
			
    echo '</div><div class="clear"></div>'
fi
