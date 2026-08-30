# shellcheck shell=sh
# shellcheck disable=SC2154
# Gemeinsame Umgebung für CutEditor-CGI und Remux (DECODIR, ffmpeg, Python).

synotr_cuteditor_env() {
    _ce_ui="${1:-}"
    if [ -z "$_ce_ui" ]; then
        return 1
    fi
    APPDIR="$_ce_ui"
    CONFIG="${APPDIR}/app/etc/Konfiguration.txt"
    # shellcheck disable=SC1090
    [ -f "$CONFIG" ] && . "$CONFIG"

    if [ "${OTRcutactiv:-on}" = "off" ]; then
        DECODIR="${WORKDIR}"
    else
        DECODIR="${WORKDIR%/}/_decodiert"
    fi

    ffmpeg=""
    ffprobe=""
    for _ffver in 8 7 6; do
        if [ -x "/usr/local/bin/ffmpeg${_ffver}" ] && [ -x "/usr/local/bin/ffprobe${_ffver}" ]; then
            ffmpeg="/usr/local/bin/ffmpeg${_ffver}"
            ffprobe="/usr/local/bin/ffprobe${_ffver}"
            break
        fi
    done
    unset _ffver
    command -v ffmpeg >/dev/null 2>&1 && [ -z "$ffmpeg" ] && ffmpeg=$(command -v ffmpeg)
    command -v ffprobe >/dev/null 2>&1 && [ -z "$ffprobe" ] && ffprobe=$(command -v ffprobe)

    machinetyp=$(uname --machine 2>/dev/null || uname -m)
    mp4box=""
    if [ "$machinetyp" = "x86_64" ]; then
        [ -f "${APPDIR}/app/bin/mp4box" ] && mp4box="${APPDIR}/app/bin/mp4box"
    else
        [ -f "${APPDIR}/app/binAArch64/mp4box" ] && mp4box="${APPDIR}/app/binAArch64/mp4box"
    fi

    case "${CutEditorQueue:-miss_both}" in
        miss_both|no_local|all_uncut) ;;
        *) CutEditorQueue="miss_both" ;;
    esac
    case "${CutEditorOtrkeyMp4:-off}" in
        on|off) ;;
        *) CutEditorOtrkeyMp4="off" ;;
    esac

    if [ -x "${APPDIR}/app/venv/bin/python3" ]; then
        SYNOTR_PYTHON="${APPDIR}/app/venv/bin/python3"
    else
        SYNOTR_PYTHON=$(command -v python3 2>/dev/null || echo python3)
    fi

    export SYNOTR_DECODIR="$DECODIR"
    export SYNOTR_SQLITE="${APPDIR}/app/etc/synOTR.sqlite"
    export SYNOTR_WORKDIR="${WORKDIR}"
    export SYNOTR_FFMPEG="$ffmpeg"
    export SYNOTR_FFPROBE="$ffprobe"
    export SYNOTR_MP4BOX="$mp4box"
    export SYNOTR_LOCALCUTLIST="${OTRlocalcutlistdir:-}"
    export SYNOTR_OTRKEYDIR="${OTRkeydir:-}"
    export SYNOTR_CUTEDITOR_QUEUE="${CutEditorQueue:-miss_both}"
    export SYNOTR_CUTEDITOR_OTRKEYMP4="${CutEditorOtrkeyMp4:-off}"
    export SYNOTR_CUTLIST_AUTHOR="${cutlistat_ID:-}"
    export SYNOTR_CONFIG="$CONFIG"
    export SYNOTR_CUTEDITOR_REMUX="${APPDIR}/includes/synotr_cuteditor_remux.sh"
    export PYTHONPATH="${APPDIR}/app${PYTHONPATH:+:$PYTHONPATH}"
    unset _ce_ui
}
