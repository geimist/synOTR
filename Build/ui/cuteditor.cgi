#!/bin/bash
# Nicht von DSM 3rdparty ausgeliefert (nur index.cgi). Fallback, falls jemand die Datei direkt aufruft.
# shellcheck disable=SC1091,SC2034,SC2154

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/syno/bin:/usr/syno/sbin

_ce_fail() {
	echo "Content-type: text/html; charset=utf-8"
	echo
	echo "<p>CutEditor: $1</p><p><a href=\"index.cgi?page=cuteditor\">Zur Liste</a></p>"
	exit 0
}

machinetyp=$(uname --machine)
if [ "$machinetyp" = "x86_64" ]; then
	include_synowebapi=synowebapi_x86_64
elif [ -x /usr/syno/bin/synowebapi ]; then
	include_synowebapi=""
	SYSTEM_SYNOWEBAPI=/usr/syno/bin/synowebapi
fi

app_name="synOTR"
app_home=$(echo /volume*/@appstore/${app_name}/ui)
[ ! -d "${app_home}" ] && _ce_fail "Paketpfad fehlt."

[[ "${REQUEST_METHOD}" == "POST" ]] && REQUEST_METHOD="GET" && OLD_REQUEST_METHOD="POST"
syno_login=$(/usr/syno/synoman/webman/login.cgi)
if echo "${syno_login}" | grep -q SynoToken ; then
	syno_token=$(echo "${syno_login}" | grep SynoToken | cut -d ":" -f2 | cut -d '"' -f2)
else
	_ce_fail "Keine DSM-Sitzung (SynoToken)."
fi
[ -z "${syno_token}" ] && _ce_fail "SynoToken leer."
[[ "${OLD_REQUEST_METHOD}" == "POST" ]] && REQUEST_METHOD="POST" && unset OLD_REQUEST_METHOD

syno_user=$(/usr/syno/synoman/webman/authenticate.cgi)
user_exist=$(grep -o "^${syno_user}:" /etc/passwd)
[ -n "${user_exist}" ] && user_exist="yes" || _ce_fail "Benutzer unbekannt."

dir="$app_home"
# shellcheck source=includes/synotr_cuteditor_env.sh
. "${dir}/includes/synotr_cuteditor_env.sh"
synotr_cuteditor_env "$dir"
export SYNOTR_CUTEDITOR_API="index.cgi?page=cuteditor-api"

export GATEWAY_INTERFACE="${GATEWAY_INTERFACE:-CGI/1.1}"
cd "$dir" || _ce_fail "cd fehlgeschlagen."
[ -x "$SYNOTR_PYTHON" ] || _ce_fail "Python3 fehlt."
exec "$SYNOTR_PYTHON" -m synotr_cuteditor
