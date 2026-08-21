#!/bin/bash
#----------------------------------------------------------------------------------------
# Scriptaufruf:
#----------------------------------------------------------------------------------------
# erstellt das SPK aus dem aktuellen Branch (git pull + worktree):
# sh ./build_spk.sh
#
# erstellt das SPK aus dem als Parameter übergebenen Release/Tag:
# sh ./build_spk.sh 4.0.7
#
# erstellt das SPK aus den lokalen Dateien ohne git pull/worktree
# (inkl. uncommitteter Änderungen; sinnvoll auf macOS):
# sh ./build_spk.sh local
#
#----------------------------------------------------------------------------------------
# Ordnerstruktur:
#----------------------------------------------------------------------------------------
# ./APP / Build --> Arbeitsumgebung (erstellen/editieren/verschieben)
# ./PKG / Pack  --> Archivordner zum Aufbau des SPK (Startscripte etc.)
#

# Avoid macOS AppleDouble files/xattrs in tar archives (._privilege, ._resource, .DS_Store, ...).
export COPYFILE_DISABLE=1
export COPY_EXTENDED_ATTRIBUTES_DISABLE=1

set -euo pipefail
IFS=$'\n\t'

#######

project="synOTR"

#######

buildversion=${1:-latest}

if ! [ -x "$(command -v git)" ]; then
	if [ "$buildversion" = local ]; then
		echo "git is not installed – building from local files"
	else
		echo "git is not installed – falling back to local build" >&2
		buildversion=local
	fi
fi

if ! [ -x "$(command -v fakeroot)" ]; then
	if [ "$(whoami)" != "root" ]; then
		echo "WARNUNG: fakeroot ist nicht installiert und du bist auch nicht root!" >&2
		exit 1
	else
		FAKEROOT=""
	fi
else
	FAKEROOT=$(command -v fakeroot)
fi

# ustar is what DSM expects; macOS bsdtar defaults to pax with xattr headers.
# --help on Darwin omits --no-xattrs/--no-mac-metadata even though bsdtar supports them.
TAR_CREATE_OPTS=(--format=ustar)
if tar --help 2>&1 | awk '/--no-xattrs/ { found=1 } END { exit !found }' \
	|| [ "$(uname -s)" = Darwin ]; then
	TAR_CREATE_OPTS+=(--no-xattrs)
fi
if tar --help 2>&1 | awk '/--no-mac-metadata/ { found=1 } END { exit !found }' \
	|| [ "$(uname -s)" = Darwin ]; then
	TAR_CREATE_OPTS+=(--no-mac-metadata)
fi

# Arbeitsverzeichnis auslesen und hineinwechseln:
# ---------------------------------------------------------------------
# shellcheck disable=SC2086
APPDIR=$(cd "$(dirname $0)";pwd)
cd "${APPDIR}"

build_tmp=$(mktemp -d -t tmp.XXXXXXXXXX)

function finish {
	if [ "$buildversion" != local ]; then
		git worktree remove --force "$build_tmp" 2>/dev/null || true
	fi
	rm -rf "$build_tmp"
}
trap finish EXIT

echo " - INFO: Erstelle den temporären Buildordner und kopiere Sourcen hinein ..."

if [ "$buildversion" = local ]; then
	tar --exclude='./.git' --exclude='./*.spk' --exclude='.DS_Store' --exclude='._*' \
		-cf - . | tar -C "$build_tmp" -xf -
	# no parentheses: Homebrew fakeroot evals the command line
	set_spk_version="local_$(date +%Y-%m-%d_%H-%M)"
	if [ -x "$(command -v git)" ] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		set_spk_version="${set_spk_version}_$(git log -1 --format='%h')"
	fi
else
	git pull	# aktualisieren
	git worktree add --force "$build_tmp" "$(git rev-parse --abbrev-ref HEAD)"
	set_spk_version="$(git branch --show-current)_latest_$(date +%Y-%m-%d_%H-%M)_$(git log -1 --format='%h')"
fi

pushd "$build_tmp" >/dev/null

if [ "$buildversion" != local ]; then
	taggedversions=$(git tag)
	if echo "$taggedversions" | grep -Eq "$buildversion"; then
		echo "git checkout zu $buildversion"
		git checkout "$buildversion"
		set_spk_version="$buildversion"
	elif [ "$buildversion" != latest ]; then
		echo "ACHTUNG: Die gewünschte Version wurde im Repository nicht gefunden!"
		echo "Die $(git rev-parse --abbrev-ref HEAD)-branch wird verwendet!"
	fi
fi

# fallback to old app dir
if [ -d "$build_tmp"/Build ]; then
	APP=Build
else
	APP=APP
fi

# fallback to old pkg dir
if [ -d "$build_tmp"/Pack ]; then
	PKG=Pack
else
	PKG=PKG
fi

build_version=$(awk -F '"' '/^version=/ {print $2; exit}' "$build_tmp/$PKG/INFO")

echo " - INFO: Es wird folgende Version geladen und gebaut: $set_spk_version - BUILD-Version (INFO-File): $build_version"

# Ausführung: Erstellen des SPK
echo ""
echo "-----------------------------------------------------------------------------------"
echo "   SPK wird erstellt..."
echo "-----------------------------------------------------------------------------------"

# Falls versteckter Ordner /.helptoc vorhanden, diesen nach /helptoc umbenennen
if test -d "${build_tmp}/.helptoc"; then
	echo ""
	echo " - INFO: Versteckter Ordner /.helptoc wurde lokalisiert und nach /helptoc umbenannt"
	mv "${build_tmp}/.helptoc" "${build_tmp}/helptoc"
fi

# create empty dirs:
[ ! -d "${build_tmp}/$APP/cfg" ] && mkdir "${build_tmp}/$APP/cfg"
[ ! -d "${build_tmp}/$APP/log" ] && mkdir "${build_tmp}/$APP/log"

echo ""
echo " - INFO: Dateirechte anpassen ..."
chmod -R 755 "${build_tmp}/$APP/"
chmod -R 755 "${build_tmp}/$PKG/"

if command -v xattr >/dev/null 2>&1; then
	xattr -cr "${build_tmp}/$APP" "${build_tmp}/$PKG" 2>/dev/null || true
fi
find "${build_tmp}/$APP" "${build_tmp}/$PKG" \( -name '._*' -o -name '.DS_Store' \) -delete

# Packen und Ablegen der aktuellen Installation in den entsprechenden /Pack - Ordner
echo ""
echo " - INFO: Das Archiv package.tgz wird erstellt..."

$FAKEROOT tar "${TAR_CREATE_OPTS[@]}" -C "${build_tmp}/${APP}" \
	--exclude='.DS_Store' --exclude='._*' \
	-czf "${build_tmp}/${PKG}/package.tgz" .

# Wechsel in den Ablageort von package.tgz bezüglich Aufbau des SPK's
cd "${build_tmp}/${PKG}"

# Erstellen des eigentlichen SPK's
echo ""
echo " - INFO: Das SPK wird erstellt..."
spk_name="${project}_${set_spk_version}.spk"
$FAKEROOT tar "${TAR_CREATE_OPTS[@]}" \
	--exclude='.DS_Store' --exclude='._*' \
	-cf "${spk_name}" *
cp -f "${spk_name}" "${APPDIR}"

echo ""
echo "-----------------------------------------------------------------------------------"
echo "   Das SPK wurde erstellt und befindet sich unter..."
echo "-----------------------------------------------------------------------------------"
echo ""
echo "   ${APPDIR}/${spk_name}"
echo ""

exit 0
