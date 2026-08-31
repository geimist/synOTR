#!/bin/sh
# synotr_cuteditor_remux.sh SRC_AVI DST_MP4
# Gleiche OTRavi2mp4-Pipeline wie synOTR (ffmpeg-Demux + AAC + MP4Box).
# Quelle bleibt (keep_src). Sidecar für den CutEditor.

APPDIR=$(cd "$(dirname "$0")/.." || exit 1; pwd)
# shellcheck source=synotr_cuteditor_env.sh
. "${APPDIR}/includes/synotr_cuteditor_env.sh"
synotr_cuteditor_env "$APPDIR"

# shellcheck source=ensure_mp4.sh
[ -f "${APPDIR}/includes/ensure_mp4.sh" ] && . "${APPDIR}/includes/ensure_mp4.sh"

# Wie synOTR.sh: AAC-Qualität, Lautstärke, Delay, parallele Audiokodierung.
OLDIFS="${IFS}"
LOGlevel="${LOGlevel:-0}"
ffloglevel="error"
mp4boxloglevel="-quiet"
OTRaacqal="${OTRaacqal:-192k}"
normalizeAudio="${normalizeAudio:-off}"
AudioDelayMs="${AudioDelayMs:-0}"
parallelAudioConvert="${parallelAudioConvert:-on}"

synotr_encode_audio() {
    _ae_in="$1"
    _ae_out="$2"
    _ae_opts="$3"
    _ae_saved_ifs=$IFS
    IFS=${OLDIFS:-' '}
    if [ "${parallelAudioConvert:-on}" = "on" ] && [ -f "${APPDIR}/includes/convert_audio_parallel.sh" ] && [ -x /bin/bash ]; then
        echo "Audio-Konvertierung:      parallel"
        ffmpeg="$ffmpeg" ffprobe="$ffprobe" ffloglevel="$ffloglevel" WORKDIR="$WORKDIR" \
            /bin/bash "${APPDIR}/includes/convert_audio_parallel.sh" "$_ae_in" "$_ae_out" "$_ae_opts"
        convertLOG=""
        if [ -n "$WORKDIR" ] && [ -d "$WORKDIR" ]; then
            for _ae_tmp in "${WORKDIR%/}"/.audio_parallel.* "${WORKDIR%/}"/tmp_synotr_audio_parallel.*; do
                [ -d "$_ae_tmp" ] || continue
                rm -rf "$_ae_tmp"
            done
            unset _ae_tmp
        fi
    else
        echo "Audio-Konvertierung:      sequentiell"
        # shellcheck disable=SC2086
        convertLOG=$("$ffmpeg" -threads 2 -loglevel "${ffloglevel:-error}" -i "$_ae_in" $_ae_opts "$_ae_out" 2>&1)
    fi
    IFS="$_ae_saved_ifs"
}

# shellcheck source=synotr_pipeline_otrkey.sh
. "${APPDIR}/includes/synotr_pipeline_otrkey.sh"

_otrkey_avi2mp4_keep_src=1
echo "CutEditor-Remux:          OTRavi2mp4 (MP4Box), AAC ${OTRaacqal}, parallelAudioConvert=${parallelAudioConvert}, normalizeAudio=${normalizeAudio}, AudioDelayMs=${AudioDelayMs}"
synotr_otrkey_avi2mp4 "$1" "$2"
exit $?
