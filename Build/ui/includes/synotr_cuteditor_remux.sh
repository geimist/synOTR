#!/bin/sh
# synotr_cuteditor_remux.sh SRC_AVI DST_MP4
# OTRavi2mp4, Quelle bleibt (keep_src). Für CutEditor-Sidecar.

APPDIR=$(cd "$(dirname "$0")/.." || exit 1; pwd)
# shellcheck source=synotr_cuteditor_env.sh
. "${APPDIR}/includes/synotr_cuteditor_env.sh"
synotr_cuteditor_env "$APPDIR"

# shellcheck source=ensure_mp4.sh
[ -f "${APPDIR}/includes/ensure_mp4.sh" ] && . "${APPDIR}/includes/ensure_mp4.sh"

synotr_encode_audio() {
    _ae_in="$1"
    _ae_out="$2"
    _ae_opts="$3"
    # shellcheck disable=SC2086
    convertLOG=$("$ffmpeg" -threads 2 -loglevel "${ffloglevel:-error}" -i "$_ae_in" $_ae_opts "$_ae_out" 2>&1)
}

# shellcheck source=synotr_pipeline_otrkey.sh
. "${APPDIR}/includes/synotr_pipeline_otrkey.sh"

LOGlevel="${LOGlevel:-0}"
ffloglevel="error"
mp4boxloglevel="-quiet"
OLDIFS="${IFS}"
_otrkey_avi2mp4_keep_src=1
synotr_otrkey_avi2mp4 "$1" "$2"
exit $?
