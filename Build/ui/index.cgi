#!/bin/bash
# /usr/syno/synoman/webman/3rdparty/synOTR/index.cgi

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/syno/bin:/usr/syno/sbin

# System initiieren                                                      
# ---------------------------------------------------------------------
    machinetyp=$(uname --machine)
    if [ $machinetyp = "x86_64" ]; then
        include_synowebapi=synowebapi_x86_64
    elif [ $machinetyp = "i686" ]; then
        include_synowebapi=synowebapi_i686
    elif [ $machinetyp = "armv7" ]; then
        include_synowebapi=synowebapi_armv7
    fi

    app_name="synOTR"
    app_home=$(echo /volume*/@appstore/${app_name}/ui)
    [ ! -d "${app_home}" ] && exit

# Zurücksetzten möglicher Zugangsberechtigungen
    unset syno_login syno_token syno_user user_exist is_admin is_privileged


# DSM - SynoToken einlesen, überprüfen und an QUERY_STRING übergeben  
# ---------------------------------------------------------------------
# REQUEST_METHOD auf GET ändern, damit der SynoToken ausgewertet werden kann
    [[ "${REQUEST_METHOD}" == "POST" ]] && REQUEST_METHOD="GET" && OLD_REQUEST_METHOD="POST"

# Lokalisierung der login.cgi zum extrahieren des SynoToken
    syno_login=$(/usr/syno/synoman/webman/login.cgi)

# Auslesen des SynoToken aus der login.cgi
    if echo ${syno_login} | grep -q SynoToken ; then
        syno_token=$(echo "${syno_login}" | grep SynoToken | cut -d ":" -f2| cut -d '"' -f2)
    else
        exit
    fi

# Füge den SynoToken dem QUERY_STRING hinzu
    [ -z ${QUERY_STRING} ] && QUERY_STRING="SynoToken=${syno_token}" || QUERY_STRING="${QUERY_STRING}&SynoToken=${syno_token}"

# Prüfen, ob der SynoToken dem System übergeben wurde
    [ -z "${syno_token}" ] && exit

# REQUEST_METHOD wieder zurück auf POST setzen
    [[ "${OLD_REQUEST_METHOD}" == "POST" ]] && REQUEST_METHOD="POST" && unset OLD_REQUEST_METHOD



# DSM - Angemeldeten Benutzer einlesen und Berechtigung überprüfen       
# ---------------------------------------------------------------------
# Lokalisierung der authenticate.cgi zum extrahieren des angemeldeten Benutzers
    syno_user=$(/usr/syno/synoman/webman/authenticate.cgi)

# Prüfen, ob der Benutzer existiert
    user_exist=$(grep -o "^${syno_user}:" /etc/passwd)
    [ -n "${user_exist}" ] && user_exist="yes" || exit

# Prüfen, ob der lokale Benutzer der Gruppe "administrators" angehört
    if id -G "${syno_user}" | grep -q 101; then
        is_admin="yes"
    else
        is_admin="no"
    fi

# Prüfen, ob der Benutzer über die nötige Authentifizierung auf App-Ebene verfügt
    if [ -f "${app_home}/includes/$include_synowebapi" ] ; then
        rar_data=$($app_home/includes/$include_synowebapi --exec api=SYNO.Core.Desktop.Initdata method=get version=1 runner="$syno_user" | jq '.data.AppPrivilege')
        syno_privilege=$(echo "${rar_data}" | grep "SYNO.SDS.${app_name}.Application" | cut -d ":" -f2 | cut -d '"' -f2)
        if echo "${syno_privilege}" | grep -q "true"; then
            is_authenticated="yes"
        else
            is_authenticated="no"
        fi
    else
        is_authenticated="no"
        txtActivatePrivileg="<b>To enable app level authentication do...</b><br /><b>root@[local-machine]:~#</b> cp /usr/syno/bin/synowebapi /var/packages/${app_name}/target/ui/modules<br /><b>root@[local-machine]:~#</b> chown ${app_name}.${app_name} /var/packages/$MYPKG/target/ui/modules/synowebapi"
    fi

# Zugangsberechtigungen und Privilegien zum Schutz auf "readonly" setzen oder leeren
    unset syno_login rar_data syno_privilege
    readonly syno_token syno_user user_exist is_admin is_authenticated

# ---------------------------------------------------------------------
	# Benutzerordner initiieren
	dir=$(echo /volume*/@appstore/synOTR/ui) || exit
	get_var=$(which get_key_value) || exit
	set_var=$(which synosetkeyvalue) || exit
	usersettings="$dir/usersettings"
	var="$dir/usersettings/var.txt"

#	var="$usersettings/var.txt"
#	stop="$usersettings/stop.txt"
	stop="$dir/usersettings/stop.txt"
	black="color: #000000"
	green="color: #00B10D"
	red="color: #DF0101"
	synotrred="color: #BD0010"
	blue="color: #2A588C"
	orange="color: #FFA500"
	grey="color: #424242"
	grey1="color: #53657D"
	grey2="color: #374355"
    
    # Konfiguration laden:
    source $dir/app/etc/Konfiguration.txt
    
    # MAC-Adresse auslesen (um DEV-Seiten zu verstecken)
    read MAC </sys/class/net/eth0/address
	sysID=`echo $MAC | cksum | awk '{print $1}'`; sysID="$(printf '%010d' $sysID)" #echo "Prüfsumme der MAC-Adresse als Hardware-ID: $sysID" 10-stellig


if [ -z "$backifs" ]; then
	backifs="$IFS"
	readonly backifs
fi

IFS="&"
set -- $QUERY_STRING
IFS='
'

# Umgebungsparameter initiieren
for i in "$@"; do
	IFS="$backifs"
	variable=${i%%=*}
	encode_value=${i##*=}
	decode_value=$(echo "$encode_value" | sed -f $dir/includes/decode.sed)
	"$set_var" "$var" "$variable" "$decode_value"
	"$set_var" "$var" "encode_$variable" "$encode_value"
done

if [ -f "$var" ]; then
	source "$var"
fi

mainpage=${page%%-*}
site=${page##*-}
sitemore=$(expr $site + 1)
siteless=$(expr $site - 1)

if [[ "$mainpage" == "start" ]]; then
	[ -f "$var" ] && rm "$var"
	[ -f "$stop" ] && rm "$stop"
	[ -f "$usersettings/stop2.txt" ] && rm "$usersettings/stop2.txt"
	mainpage="main"
fi

# Layout - Startseite definieren
if [ -z "$page" ]; then
	mainpage="main"
fi

"$set_var" "$var" "page" ""

# Layout - Grundgerüst öffnen inkl. Navigation -
echo "Content-type: text/html"
echo
echo '
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
	<title>synOTR</title>
	<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
	<meta name="viewport" content="width=device-width, initial-scale=1">
	
	<link rel="icon" type="image/svg+xml" href="images/synOTR-LOGO.svg" sizes="any">
	<!-- <link rel="shortcut icon" href="images/uh_32.png" type="image/x-icon" /> -->
	<link rel="stylesheet" type="text/css" href="css/synotr_4.0.3.css" />
	<!--Load the AJAX API-->
    <!--<script type="text/javascript" src="https://www.gstatic.com/charts/loader.js"></script>-->
    <script type="text/javascript" src="js/chartsloader.js"></script>
</head>
<body>'

echo '<div id="wrapper">'
echo '
<div id="navleft">
    <div id="navleftinbox">
    <ul class="li_blank">'
if [[ "$mainpage" == "main" ]]; then
	echo '
	<li><a class="navitemselc" href="index.cgi?page=start"><img class="svg" src="images/home_white@geimist.svg" height="25" width="25"/>Übersicht</a></li>'
else
	echo '
	<li><a class="navitem" href="index.cgi?page=start"><img class="svg" src="images/home_grey3@geimist.svg" height="25" width="25"/>Übersicht</a></li>'
fi

if [[ "$mainpage" == "edit" ]]; then
	echo '
	<li><a class="navitemselc" href="index.cgi?page=edit"><img class="svg" src="images/settings_white@geimist.svg" height="25" width="25"/>Konfiguration</a></li>'
else
	echo '
	<li><a class="navitem" href="index.cgi?page=edit"><img class="svg" src="images/settings_grey3@geimist.svg" height="25" width="25"/>Konfiguration</a></li>'
fi

#    #if [[ "$customizedConfig" == "1" ]]; then # Flag "$customizedConfig" soll beim speichern der Einstellungen automatisch in der Config gesetzt werden. Erst dann wird der Timer angezeigt
        if [[ "$mainpage" == "timer" ]] && [[ $(synogetkeyvalue /etc.defaults/VERSION majorversion) -lt 7 ]]; then
        	echo '
        	<li><a class="navitemselc" href="index.cgi?page=timer"><img class="svg" src="images/calendar_white@geimist.svg" height="25" width="25"/>Zeitplaner</a></li>'
        elif [[ $(synogetkeyvalue /etc.defaults/VERSION majorversion) -lt 7 ]]; then
        	echo '
        	<li><a class="navitem" href="index.cgi?page=timer"><img class="svg" src="images/calendar_grey3@geimist.svg" height="25" width="25"/>Zeitplaner</a></li>'
        fi
#    #fi

if [[ "$mainpage" == "help" ]]; then
	echo '
	<li><a class="navitemselc" href="index.cgi?page=help"><img class="svg" src="images/help_white@geimist.svg" height="25" width="25"/>Hilfe</a></li>'
else
	echo '
	<li><a class="navitem" href="index.cgi?page=help"><img class="svg" src="images/help_grey3@geimist.svg" height="25" width="25"/>Hilfe</a></li>'
fi

#if [[ "$sysID" -eq "3382110677" ]]; then # 3382110677 = DEV-ID
    if [[ "$mainpage" == "status" ]] ; then
    	echo '
    	<li><a class="navitemselc" href="index.cgi?page=status"><img class="svg" src="images/status_white@geimist.svg" height="25" width="25"/>Status</a></li>'
    else
    	echo '
    	<li><a class="navitem" href="index.cgi?page=status"><img class="svg" src="images/status_grey3@geimist.svg" height="25" width="25"/>Status</a></li>'
    fi
#fi

echo '</ul>
    </div>
    </div>'





echo '
<p style="padding: 15px;">
<div class="clear"></div>'

# Layout - Dynamischer Seitenaustausch
echo '
	<form action="index.cgi" method="get" autocomplete="on">'

	if [ -z "$mainpage" ]; then
		echo 'Die Seite konnte nicht geladen werden!'
	else
		script="$mainpage.sh"
		if [ -f "$script" ]; then
			. ./"$script"
		else
			. ./main.sh
		fi
	fi

# Fehlerausgabe
if [ -f "$usersettings/stop2.txt" ]; then
#<div id="Content_1Col">
	echo '
	<div class="Content_1Col_full">
    	<div class="warning">
        	<p class="center">'
        	IFS='
        	'
        	for i in $(< "$usersettings/stop2.txt"); do
        		IFS="$backifs"
        		echo ''$i''
        	done
        	[ -f "$stop" ] && rm "$stop"
        	[ -f "$usersettings/stop2.txt" ] && rm "$usersettings/stop2.txt"
        	echo '
        	</p>
    	</div>
    	<div id="lastLine"></div>
	</div><div class="clear"></div>'
#</div>
fi

if [ -f "$stop" ]; then
	cp "$stop" "$usersettings/stop2.txt"
	echo '<meta http-equiv="refresh" content="0; url=index.cgi?page='$(echo "$page" | sed 's/[[:digit:]]*$//')''$siteless'#lastLine">'
fi

# Footer
if [ -f "footer.sh" ] && [ ! -f "$stop" ]; then
	. ./footer.sh
fi

# Layout - Grundgerüst schließen -
echo '
	</form>
    </div>
</body>
</html>'