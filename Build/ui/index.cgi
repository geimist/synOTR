#!/bin/bash
# /usr/syno/synoman/webman/3rdparty/synOTR/index.cgi
# shellcheck disable=SC2034

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/syno/bin:/usr/syno/sbin

# System initiieren                                                      
# ---------------------------------------------------------------------
    machinetyp=$(uname --machine)
    if [ "$machinetyp" = "x86_64" ]; then
        include_synowebapi=synowebapi_x86_64
    elif [ -x /usr/syno/bin/synowebapi ]; then
        # armv8 / aarch64: System-synowebapi, die mitgelieferte x86_64-Binary läuft dort nicht
        include_synowebapi=""
        SYSTEM_SYNOWEBAPI=/usr/syno/bin/synowebapi
    fi

    app_name="synOTR"
    app_home=$(echo /volume*/@appstore/${app_name}/ui)
    [ ! -d "${app_home}" ] && exit

    # Cache-bust CSS/JS: Query ändert sich mit Datei-mtime (wie synOCR), auch ohne Versionsbump.
    synotr_asset_ver=0
    for _synotr_f in "${app_home}/css/synotr.css" "${app_home}/js/chartsloader.js" "${app_home}/js/synotr-folderpicker.js" "${app_home}/js/synotr-namesyntax-editor.js" "${app_home}/app/synotr_cuteditor/static/editor.js" "${app_home}/app/synotr_cuteditor/static/editor.css"; do
        [ -f "${_synotr_f}" ] || continue
        _synotr_m=$(stat -c %Y "${_synotr_f}" 2>/dev/null)
        [ -z "${_synotr_m}" ] && _synotr_m=$(stat -f %m "${_synotr_f}" 2>/dev/null)
        [ -z "${_synotr_m}" ] && _synotr_m=0
        [ "${_synotr_m}" -gt "${synotr_asset_ver}" ] && synotr_asset_ver=${_synotr_m}
    done
    [ "${synotr_asset_ver}" -eq 0 ] 2>/dev/null && synotr_asset_ver=$(date +%s)
    synotr_asset_q="?v=${synotr_asset_ver}"
    unset _synotr_f _synotr_m

# Zurücksetzten möglicher Zugangsberechtigungen
    unset syno_login syno_token syno_user user_exist is_admin is_privileged


# DSM - SynoToken einlesen, überprüfen und an QUERY_STRING übergeben  
# ---------------------------------------------------------------------
# REQUEST_METHOD auf GET ändern, damit der SynoToken ausgewertet werden kann
    [[ "${REQUEST_METHOD}" == "POST" ]] && REQUEST_METHOD="GET" && OLD_REQUEST_METHOD="POST"

# Lokalisierung der login.cgi zum extrahieren des SynoToken
    syno_login=$(/usr/syno/synoman/webman/login.cgi)

# Auslesen des SynoToken aus der login.cgi
    if echo "${syno_login}" | grep -q SynoToken ; then
        syno_token=$(echo "${syno_login}" | grep SynoToken | cut -d ":" -f2| cut -d '"' -f2)
    else
        exit
    fi
    # Session-ID (Cookie id=) für FileStation-Aufrufe als Fallback neben dem Cookie
    sid=$(echo "${syno_login}" | sed -n 's/.*Set-Cookie: id=\([^;]*\).*/\1/p' | head -n1)

# Füge den SynoToken dem QUERY_STRING hinzu
    [ -z "${QUERY_STRING}" ] && QUERY_STRING="SynoToken=${syno_token}" || QUERY_STRING="${QUERY_STRING}&SynoToken=${syno_token}"

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
    if [ -n "$include_synowebapi" ] && [ -f "${app_home}/includes/$include_synowebapi" ] ; then
        rar_data=$("${app_home}/includes/${include_synowebapi}" --exec api=SYNO.Core.Desktop.Initdata method=get version=1 runner="$syno_user" | jq '.data.AppPrivilege')
        syno_privilege=$(echo "${rar_data}" | grep "SYNO.SDS.${app_name}.Application" | cut -d ":" -f2 | cut -d '"' -f2)
        if echo "${syno_privilege}" | grep -q "true"; then
            is_authenticated="yes"
        else
            is_authenticated="no"
        fi
    elif [ -n "$SYSTEM_SYNOWEBAPI" ] && [ -x "$SYSTEM_SYNOWEBAPI" ]; then
        rar_data=$($SYSTEM_SYNOWEBAPI --exec api=SYNO.Core.Desktop.Initdata method=get version=1 runner="$syno_user" | jq '.data.AppPrivilege')
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
    readonly syno_token syno_user user_exist is_admin is_authenticated sid

# ---------------------------------------------------------------------
	# Benutzerordner initiieren
	dir=$(echo /volume*/@appstore/synOTR/ui) || exit
	get_var=$(which get_key_value) || exit
	set_var=$(which synosetkeyvalue) || exit
	usersettings="$dir/usersettings"
	# Request-Scratchpad im RAM (tmpfs). Eigenes Verzeichnis: CGI darf oft nicht
	# frei in /tmp anlegen; synosetkeyvalue-Meldungen auf stdout machen DSM-404.
	var="/tmp/synOTR/var.txt"
	if mkdir -p /tmp/synOTR 2>/dev/null && touch "$var" 2>/dev/null; then
		chmod 700 /tmp/synOTR 2>/dev/null
		chmod 600 "$var" 2>/dev/null
		[ -f "$usersettings/var.txt" ] && rm -f "$usersettings/var.txt"
	else
		var="$usersettings/var.txt"
		touch "$var" 2>/dev/null
	fi

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
    source "${dir}/app/etc/Konfiguration.txt"

if [ -z "$backifs" ]; then
	backifs="$IFS"
	readonly backifs
fi

IFS="&"
# shellcheck disable=SC2086
set -- $QUERY_STRING
IFS='
'

# Umgebungsparameter initiieren
_synotr_page_from_loop=""
for i in "$@"; do
	IFS="$backifs"
	variable=${i%%=*}
	encode_value=${i##*=}
	decode_value=$(echo "$encode_value" | sed -f "${dir}/includes/decode.sed")
	# SynoToken steht in jeder Query – nicht in die Datei, sonst killt source die CGI
	# (Sonderzeichen / readonly syno_token) noch vor dem Content-type → DSM-404.
	case "$variable" in
		SynoToken|encode_SynoToken|sid|encode_sid) continue ;;
	esac
	[[ "$variable" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
	if [ "$variable" = "page" ]; then
		_synotr_page_from_loop="$decode_value"
	fi
	printf -v "$variable" '%s' "$decode_value"
	printf -v "encode_$variable" '%s' "$encode_value"
	"$set_var" "$var" "$variable" "$decode_value" >/dev/null 2>&1
	"$set_var" "$var" "encode_$variable" "$encode_value" >/dev/null 2>&1
done

# Vorherige Request-Werte nachladen, aktuelle Query bleibt führend
if [ -f "$var" ] && bash -n "$var" 2>/dev/null; then
	source "$var"
	for i in "$@"; do
		IFS="$backifs"
		variable=${i%%=*}
		encode_value=${i##*=}
		decode_value=$(echo "$encode_value" | sed -f "${dir}/includes/decode.sed")
		case "$variable" in
			SynoToken|encode_SynoToken|sid|encode_sid) continue ;;
		esac
		[[ "$variable" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
		printf -v "$variable" '%s' "$decode_value"
		printf -v "encode_$variable" '%s' "$encode_value"
	done
fi

# page aus der aktuellen QUERY_STRING – geteilte tmp-Datei kann bei parallelen Requests veralten
if [ -n "$_synotr_page_from_loop" ]; then
	page="$_synotr_page_from_loop"
fi

mainpage=${page%%-*}
site=${page##*-}
sitemore=$(expr "$site" + 1 2>/dev/null || echo 1)
siteless=$(expr "$site" - 1 2>/dev/null || echo 0)

if [[ "$mainpage" == "start" ]]; then
	[ -f "$var" ] && rm -f "$var"
	[ -f "$stop" ] && rm -f "$stop"
	[ -f "$usersettings/stop2.txt" ] && rm -f "$usersettings/stop2.txt"
	mainpage="main"
fi

# Status ist in der Übersicht aufgegangen (alte Bookmarks: page=status)
if [[ "$mainpage" == "status" ]]; then
	mainpage="main"
fi

# Layout - Startseite definieren
if [ -z "$page" ]; then
	mainpage="main"
fi

# CutEditor JSON/Media/HTML: nur index.cgi ist unter DSM 3rdparty erreichbar.
# Ein zweites *.cgi liefert die DSM-404-Seite („Seite konnte nicht gefunden werden“).
if [ "$page" = "cuteditor-api" ]; then
	# shellcheck source=includes/synotr_cuteditor_env.sh
	. ./includes/synotr_cuteditor_env.sh
	synotr_cuteditor_env "$dir"
	export SYNOTR_CUTEDITOR_API="index.cgi?page=cuteditor-api"
	cd "$dir" || {
		echo "Content-type: text/html; charset=utf-8"
		echo
		echo "<p>CutEditor: Paketverzeichnis fehlt.</p>"
		exit 0
	}
	if [ ! -x "$SYNOTR_PYTHON" ]; then
		echo "Content-type: text/html; charset=utf-8"
		echo
		echo "<p>CutEditor: Python3 nicht gefunden.</p>"
		exit 0
	fi
	exec "$SYNOTR_PYTHON" -m synotr_cuteditor
fi

"$set_var" "$var" "page" "" >/dev/null 2>&1

# Layout - Grundgerüst öffnen inkl. Navigation -
echo "Content-type: text/html"
echo
echo '
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" class="synotr-boot">
<head>
	<title>synOTR</title>
	<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<meta name="syno-token" content="'"$(printf '%s' "${syno_token-}" | sed 's/&/\&amp;/g; s/"/\&quot;/g; s/</\&lt;/g')"'"/>
	<meta name="syno-sid" content="'"$(printf '%s' "${sid-}" | sed 's/&/\&amp;/g; s/"/\&quot;/g; s/</\&lt;/g')"'"/>
	
	<link rel="icon" type="image/svg+xml" href="images/synOTR-LOGO.svg" sizes="any">
	<!-- <link rel="shortcut icon" href="images/uh_32.png" type="image/x-icon" /> -->
	<link rel="stylesheet" type="text/css" href="css/synotr.css'"${synotr_asset_q}"'" />
	<!--Load the AJAX API-->
    <!--<script type="text/javascript" src="https://www.gstatic.com/charts/loader.js"></script>-->
    <script type="text/javascript" src="js/chartsloader.js'"${synotr_asset_q}"'"></script>
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

if [[ "$mainpage" == "cuteditor" ]]; then
	echo '
	<li><a class="navitemselc" href="index.cgi?page=cuteditor"><img class="svg" src="images/cut_white@geimist.svg" height="25" width="25"/>CutEditor</a></li>'
else
	echo '
	<li><a class="navitem" href="index.cgi?page=cuteditor"><img class="svg" src="images/cut_grey3@geimist.svg" height="25" width="25"/>CutEditor</a></li>'
fi

if [[ "$mainpage" == "edit" ]]; then
	echo '
	<li><a class="navitemselc" href="index.cgi?page=edit"><img class="svg" src="images/settings_white@geimist.svg" height="25" width="25"/>Konfiguration</a></li>'
else
	echo '
	<li><a class="navitem" href="index.cgi?page=edit"><img class="svg" src="images/settings_grey3@geimist.svg" height="25" width="25"/>Konfiguration</a></li>'
fi

if [[ "$mainpage" == "help" ]]; then
	echo '
	<li><a class="navitemselc" href="index.cgi?page=help"><img class="svg" src="images/help_white@geimist.svg" height="25" width="25"/>Hilfe</a></li>'
else
	echo '
	<li><a class="navitem" href="index.cgi?page=help"><img class="svg" src="images/help_grey3@geimist.svg" height="25" width="25"/>Hilfe</a></li>'
fi

echo '</ul>
    </div>
    </div>'





echo '
<div class="synotr-page">
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
	_synotr_stop_cls="warning"
	grep -q 'synotr-flash' "$usersettings/stop2.txt" 2>/dev/null && _synotr_stop_cls="info"
	echo '
	<div class="Content_1Col_full">
    	<div class="'"$_synotr_stop_cls"'">
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
	unset _synotr_stop_cls
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
    </div>
<script type="text/javascript">
(function () {
	function synotrUnboot() {
		document.documentElement.classList.remove("synotr-boot");
	}
	if (document.readyState === "loading") {
		document.addEventListener("DOMContentLoaded", function () {
			window.requestAnimationFrame(function () {
				window.requestAnimationFrame(synotrUnboot);
			});
		});
	} else {
		window.requestAnimationFrame(function () {
			window.requestAnimationFrame(synotrUnboot);
		});
	}
})();
(function () {
	var flash = document.querySelector(".synotr-flash");
	if (!flash) return;
	var delayMs = 3000;
	var fadeMs = 500;
	var reduced = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
	function findContinue(el) {
		var btn = el.querySelector("button.blue_button, a.blue_button, button.synotr-flash-go, a.synotr-flash-go");
		if (btn) return btn;
		var n = el.nextElementSibling;
		while (n) {
			if (n.matches && n.matches("button.blue_button, a.blue_button")) return n;
			btn = n.querySelector && n.querySelector("button.blue_button, a.blue_button");
			if (btn) return btn;
			n = n.nextElementSibling;
		}
		if (el.parentNode) {
			return el.parentNode.querySelector("button.blue_button, a.blue_button");
		}
		return null;
	}
	var goBtn = findContinue(flash);
	if (goBtn) goBtn.classList.add("synotr-flash-go");
	if (!flash.querySelector(".synotr-flash-bar")) {
		var bar = document.createElement("div");
		bar.className = "synotr-flash-bar";
		bar.setAttribute("aria-hidden", "true");
		var fill = document.createElement("span");
		fill.style.animationDuration = delayMs + "ms";
		bar.appendChild(fill);
		flash.appendChild(bar);
	}
	function go() {
		var btn = findContinue(flash);
		if (!btn) return;
		if (btn.tagName === "A" && btn.getAttribute("href")) {
			window.location.assign(btn.href);
			return;
		}
		var form = btn.form || document.querySelector("form");
		if (form && btn.tagName === "BUTTON" && typeof form.requestSubmit === "function") {
			try {
				form.requestSubmit(btn);
				return;
			} catch (e) { /* fall through */ }
		}
		btn.click();
	}
	window.setTimeout(function () {
		if (reduced) {
			go();
			return;
		}
		flash.classList.add("synotr-flash-out");
		window.setTimeout(go, fadeMs);
	}, delayMs);
})();
</script>'

if [[ "$mainpage" == "edit" ]]; then
	echo '<script type="text/javascript" src="js/synotr-folderpicker.js'"${synotr_asset_q}"'"></script>'
	echo '<script type="text/javascript" src="js/synotr-namesyntax-editor.js'"${synotr_asset_q}"'"></script>'
fi

echo '
</body>
</html>'