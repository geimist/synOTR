# shellcheck shell=sh
# shellcheck disable=SC2154,SC2034
# synotr_ensure_mp4 SRC
# Remuxt AVI (oder MP4 mit MP3 / ffmpeg-Lavf-H.264) nach MP4.
# H.264/HEVC ungeschnitten: ffmpeg-Demux + Bento4 mp4mux.
# avcut-HQ: Roh-H.264 + MP4Box -fps (OTRavi2mp4). avcut-Patch: gleiche SPS am Spleiß.
# MPEG-4/DivX: ffmpeg-Copy + mpeg4_unpack_bframes.
# Setzt synotr_mp4_path auf den resultierenden Pfad. Return 0/1.
# Erwartet (aus synOTR.sh): ffmpeg ffprobe mp4mux mp4box ffloglevel normalizeAudio OTRaacqal
#           AudioDelayMs endgueltigloeschen OTRkeydeldir LOGlevel OLDIFS WORKDIR mp4boxloglevel
# Natives MP4 mit AAC/AC3 ohne Lavf-Tag: unverändert (synotr_mp4_path=SRC).
# synotr_mp4_path wird vom Aufrufer gelesen (SC2034).
#
# OTRautocut setzt IFS auf Newline (Dateinamen mit Leerzeichen). Optionen wie
# -bsf:v mpeg4_unpack_bframes dürfen daher nicht in einer Variable stehen, die
# per Word-Splitting zerlegt werden muss – sonst nimmt ffmpeg 8 das als einen
# Stream-Specifier und bricht ab ("Trailing garbage ... mpeg4_unpack_bframes").

synotr_aac_encode_opts() {
    _encoders=$("$ffmpeg" -loglevel "$ffloglevel" -encoders 2>&1)
    if echo "$_encoders" | grep -q "libfdk_aac"; then
        echo "Erkannter Encoder:        fdk-aac [1.Wahl]"
        synotr_aac_opts="-c:a libfdk_aac -b:a ${OTRaacqal%k}k"
    elif echo "$_encoders" | grep -q "AAC (Advanced Audio Coding)"; then
        echo "Erkannter Encoder:        nativ (ffmpeg > 3.0) [2.Wahl]"
        synotr_aac_opts="-c:a aac -strict -2 -b:a ${OTRaacqal%k}k"
    elif echo "$_encoders" | grep -q libfaac; then
        echo "Erkannter Encoder:        libfaac [3.Wahl]"
        synotr_aac_opts="-acodec libfaac -ab ${OTRaacqal%k}k"
    else
        echo "  finde keinen ffmpeg-Audioencoder!"
        synotr_aac_opts=""
        return 1
    fi
    return 0
}

_synotr_remux_cleanup() {
    if [ -n "${_muxdir:-}" ] && [ -d "$_muxdir" ]; then
        rm -rf "${_muxdir:?}"
    fi
    if [ -n "${_audiofile:-}" ] && [ -f "$_audiofile" ]; then
        rm -f "$_audiofile"
    fi
}

_synotr_python3() {
    if [ -x "${APPDIR}/app/venv/bin/python3" ]; then
        echo "${APPDIR}/app/venv/bin/python3"
        return 0
    fi
    command -v python3 2>/dev/null
}

# avcut mischt SPS. avc1 speichert nur die erste → DSM hängt.
# Optional _mp4mux_sps_from = Originaldatei (SPS/PPS daher).
_synotr_h264_unify_sps() {
    _h264="$1"
    _script="${APPDIR}/includes/h264_keep_first_sps.py"
    _py=$(_synotr_python3)
    if [ -z "$_py" ] || [ ! -x "$_py" ] || [ ! -f "$_script" ]; then
        echo "    Python/h264_keep_first_sps.py fehlt – keine SPS-Vereinheitlichung."
        return 1
    fi
    _ref=""
    _refh264=""
    if [ -n "${_mp4mux_sps_from:-}" ] && [ -f "$_mp4mux_sps_from" ]; then
        _refh264="${_muxdir}/sps_ref.h264"
        _REFLOG=$("$ffmpeg" -hide_banner -loglevel "$ffloglevel" -y \
            -t 2 -i "$_mp4mux_sps_from" -map 0:v:0 -an -c:v copy \
            -bsf:v h264_mp4toannexb -f data "$_refh264" 2>&1)
        if [ "$LOGlevel" = "2" ]; then
            echo "ffmpeg-SPS-Referenz LOG:  $_REFLOG"
        fi
        [ -f "$_refh264" ] && _ref="$_refh264"
    fi
    # nicht _out: das ist das MP4-Ziel in _synotr_ensure_mp4_run
    _uniout="${_h264}.uni"
    echo "    SPS/PPS vereinheitlichen (gleiche Sets vor jedem IDR, für stss)"
    if [ -n "${_mp4mux_sps_from:-}" ] && [ -z "$_ref" ]; then
        echo "    SPS-Referenz aus dem Original fehlt."
        return 1
    fi
    if [ -n "$_ref" ]; then
        "$_py" "$_script" "$_h264" "$_uniout" "$_ref" || return 1
    else
        "$_py" "$_script" "$_h264" "$_uniout" || return 1
    fi
    mv -f "$_uniout" "$_h264" || return 1
    rm -f "$_refh264"
    unset _uniout
    return 0
}

# Rohstream ($_vfile) + AAC ($_audiofile) → $_tmpout (mp4mux-Fallback nach avcut).
_synotr_mp4mux_es() {
    if [ -z "${mp4mux:-}" ] || [ ! -x "$mp4mux" ]; then
        return 1
    fi
    if [ -z "${_vfile:-}" ] || [ ! -f "$_vfile" ] || [ -z "${_audiofile:-}" ] || [ ! -f "$_audiofile" ]; then
        echo "    mp4mux: Rohstream oder AAC fehlt."
        return 1
    fi
    _vparams="frame_rate=${_fps}"
    _atrack="mp4:${_audiofile}#track=audio"
    if [ "${_dsec:-0}" != "0" ] && [ "${_dsec:-0}" != "0.000" ]; then
        _afile="${_muxdir}/a_delay.m4a"
        if [ "${_delay_neg:-0}" = "1" ]; then
            _ALOG=$("$ffmpeg" -hide_banner -loglevel "$ffloglevel" -y \
                -itsoffset "-$_dsec" -i "$_audiofile" -c:a copy "$_afile" 2>&1)
        else
            _ALOG=$("$ffmpeg" -hide_banner -loglevel "$ffloglevel" -y \
                -itsoffset "$_dsec" -i "$_audiofile" -c:a copy "$_afile" 2>&1)
        fi
        if [ "$LOGlevel" = "2" ]; then
            echo "ffmpeg-AudioDelay LOG:    $_ALOG"
        fi
        if [ ! -f "$_afile" ]; then
            echo "    Audio-Delay für mp4mux fehlgeschlagen."
            return 1
        fi
        _atrack="mp4:${_afile}#track=audio"
    fi
    _vparams="frame_rate=${_fps}"
    if [ "${_mp4mux_inband:-0}" = "1" ]; then
        _vparams="${_vparams},format=avc3"
        echo "    mp4mux:               $mp4mux  fps=${_fps}  avc3 (in-band SPS)"
    else
        echo "    mp4mux:               $mp4mux  fps=${_fps} (Rohstream)"
    fi
    rm -f "$_tmpout"
    _MUXLOG=$("$mp4mux" \
        --track "h264:${_vfile}#${_vparams}" \
        --track "$_atrack" \
        "$_tmpout" 2>&1)
    _delayline=$(printf '%s\n' "$_MUXLOG" | grep 'composition delay' || true)
    [ -n "$_delayline" ] && echo "    $_delayline"
    if [ "$LOGlevel" = "2" ]; then
        echo "mp4mux LOG:              $_MUXLOG"
    fi
    if [ ! -f "$_tmpout" ]; then
        echo "    mp4mux fehlgeschlagen."
        echo "$_MUXLOG"
        return 1
    fi
    _kcount=$("$ffprobe" -v error -select_streams v:0 -show_entries packet=flags -of csv=p=0 "$_tmpout" 2>/dev/null | awk 'index($0,"K"){c++} END{print c+0}')
    echo "    MP4-Keyframes (Index):  ${_kcount}"
    return 0
}

# "$@" = ffmpeg-Argumente zwischen -y und -c:v (Inputs/Maps).
# $_vbsf = Filtername oder leer; -bsf:v ist immer ein eigenes Token.
_synotr_mp4_ffmpeg_mux() {
    # +genpts: OTR-AVI/H.264 hat oft keine Packet-PTS.
    if [ -n "$_vbsf" ]; then
        _MUXLOG=$("$ffmpeg" -hide_banner -loglevel "$ffloglevel" -fflags +genpts -y "$@" -c:v copy -bsf:v "$_vbsf" -c:a copy -sn -movflags +faststart "$_tmpout" 2>&1)
    else
        _MUXLOG=$("$ffmpeg" -hide_banner -loglevel "$ffloglevel" -fflags +genpts -y "$@" -c:v copy -c:a copy -sn -movflags +faststart "$_tmpout" 2>&1)
    fi
}

_synotr_ensure_mp4_ffmpeg_from_inputs() {
    _MUXLOG=""
    if [ -n "${_audiofile:-}" ] && [ -f "$_audiofile" ]; then
        if [ "$_delay_neg" = "1" ] && [ "$_dsec" != "0" ] && [ "$_dsec" != "0.000" ]; then
            _synotr_mp4_ffmpeg_mux -itsoffset "$_dsec" -i "$_src" -i "$_audiofile" -map 0:v:0 -map 1:a:0
        elif [ "$_dsec" != "0" ] && [ "$_dsec" != "0.000" ]; then
            _synotr_mp4_ffmpeg_mux -i "$_src" -itsoffset "$_dsec" -i "$_audiofile" -map 0:v:0 -map 1:a:0
        else
            _synotr_mp4_ffmpeg_mux -i "$_src" -i "$_audiofile" -map 0:v:0 -map 1:a:0
        fi
    else
        if [ "$_delay_neg" = "1" ] && [ "$_dsec" != "0" ] && [ "$_dsec" != "0.000" ]; then
            _synotr_mp4_ffmpeg_mux -itsoffset "$_dsec" -i "$_src" -i "$_src" -map 0:v:0 -map 1:a:0
        elif [ "$_dsec" != "0" ] && [ "$_dsec" != "0.000" ]; then
            _synotr_mp4_ffmpeg_mux -i "$_src" -itsoffset "$_dsec" -i "$_src" -map 0:v:0 -map 1:a:0
        else
            _synotr_mp4_ffmpeg_mux -i "$_src"
        fi
    fi
    if [ "$LOGlevel" = "2" ]; then
        echo "ffmpeg-Remux LOG:         $_MUXLOG"
    fi
}

# H.264/HEVC: Rohstream + mp4mux (CFR). Audio als ADTS/AC3 oder MP4-Track.
_synotr_mp4mux_from_src() {
    _vtype=""
    _vext=""
    _vesbsf=""
    case "$_vcodec" in
        h264)
            _vtype=h264
            _vext=h264
            _vesbsf="h264_mp4toannexb"
            ;;
        hevc|h265)
            _vtype=h265
            _vext=h265
            _vesbsf="hevc_mp4toannexb"
            ;;
        *)
            return 1
            ;;
    esac

    _muxdir="${WORKDIR:-}"
    _muxdir="${_muxdir%/}"
    if [ -n "$_muxdir" ] && [ -d "$_muxdir" ]; then
        _muxdir="${_muxdir}/tmp_synotr_remux"
    else
        _muxdir="${_srcdir}tmp_synotr_remux"
    fi
    rm -rf "$_muxdir"
    mkdir -p "$_muxdir" || return 1

    _vfile="${_muxdir}/v.${_vext}"
    # -f data: nicht der H.264-Muxer (DTS-Prüfung → Paketverlust; setts=N → Standbild nach GOP 1).
    # igndts nur für OTR-AVI/Lavf (kaputte DTS). Bei avcut-MKV würde igndts B-Frames
    # in Anzeige- statt Decoderreihenfolge schreiben → Freeze/Ruckeln.
    # avc3/dump_extra: DSM spielt das nicht.
    _vbsf_chain="$_vesbsf"
    if [ "${_mp4mux_inband:-0}" = "1" ]; then
        _vbsf_chain="dump_extra=freq=keyframe,${_vesbsf}"
    fi
    if [ "${_mp4mux_aud:-0}" = "1" ] && [ "$_vtype" = "h264" ]; then
        _vbsf_chain="${_vbsf_chain},h264_metadata=aud=insert"
    fi
    if [ "${_mp4mux_keep_dts:-0}" = "1" ]; then
        _VLOG=$("$ffmpeg" -hide_banner -loglevel "$ffloglevel" -y \
            -i "$_src" -map 0:v:0 -an -c:v copy \
            -bsf:v "$_vbsf_chain" -f data "$_vfile" 2>&1)
    else
        _VLOG=$("$ffmpeg" -hide_banner -loglevel "$ffloglevel" -fflags +igndts -y \
            -i "$_src" -map 0:v:0 -an -c:v copy \
            -bsf:v "$_vbsf_chain" -f data "$_vfile" 2>&1)
    fi
    if [ "$LOGlevel" = "2" ]; then
        echo "ffmpeg-VideoDemux LOG:    $_VLOG"
    fi
    if [ ! -f "$_vfile" ]; then
        echo "    Video-Demux für mp4mux fehlgeschlagen."
        return 1
    fi
    if [ "$_vtype" = "h264" ] && [ "${_mp4mux_strip_sps:-0}" = "1" ]; then
        if ! _synotr_h264_unify_sps "$_vfile"; then
            echo "    SPS-Vereinheitlichung fehlgeschlagen."
            return 1
        fi
    fi

    _atrack=""
    _aoff=""
    if [ "$_delay_neg" = "1" ] && [ "$_dsec" != "0" ] && [ "$_dsec" != "0.000" ]; then
        _aoff="-$_dsec"
    elif [ "$_dsec" != "0" ] && [ "$_dsec" != "0.000" ]; then
        _aoff="$_dsec"
    fi

    if [ -n "${_audiofile:-}" ] && [ -f "$_audiofile" ]; then
        _afile="${_muxdir}/a.m4a"
        if [ -n "$_aoff" ]; then
            _ALOG=$("$ffmpeg" -hide_banner -loglevel "$ffloglevel" -y \
                -itsoffset "$_aoff" -i "$_audiofile" -c:a copy "$_afile" 2>&1)
        else
            _afile="$_audiofile"
            _ALOG=""
        fi
        _atrack="mp4:${_afile}#track=audio"
    elif [ "$_audiocodec" = "ac3" ]; then
        _afile="${_muxdir}/a.ac3"
        if [ -n "$_aoff" ]; then
            _ALOG=$("$ffmpeg" -hide_banner -loglevel "$ffloglevel" -y \
                -itsoffset "$_aoff" -i "$_src" -vn -c:a copy "$_afile" 2>&1)
        else
            _ALOG=$("$ffmpeg" -hide_banner -loglevel "$ffloglevel" -y \
                -i "$_src" -vn -c:a copy "$_afile" 2>&1)
        fi
        _atrack="ac3:${_afile}"
    elif [ "$_audiocodec" = "eac3" ]; then
        _afile="${_muxdir}/a.ec3"
        if [ -n "$_aoff" ]; then
            _ALOG=$("$ffmpeg" -hide_banner -loglevel "$ffloglevel" -y \
                -itsoffset "$_aoff" -i "$_src" -vn -c:a copy "$_afile" 2>&1)
        else
            _ALOG=$("$ffmpeg" -hide_banner -loglevel "$ffloglevel" -y \
                -i "$_src" -vn -c:a copy "$_afile" 2>&1)
        fi
        _atrack="ec3:${_afile}"
    else
        case "$_base" in
            *.mp4|*.MP4)
                if [ -z "$_aoff" ]; then
                    _atrack="mp4:${_src}#track=audio"
                    _ALOG=""
                else
                    _afile="${_muxdir}/a.m4a"
                    _ALOG=$("$ffmpeg" -hide_banner -loglevel "$ffloglevel" -y \
                        -itsoffset "$_aoff" -i "$_src" -vn -c:a copy "$_afile" 2>&1)
                    _atrack="mp4:${_afile}#track=audio"
                fi
                ;;
            *)
                _afile="${_muxdir}/a.aac"
                if [ -n "$_aoff" ]; then
                    _ALOG=$("$ffmpeg" -hide_banner -loglevel "$ffloglevel" -y \
                        -itsoffset "$_aoff" -i "$_src" -vn -c:a copy "$_afile" 2>&1)
                else
                    _ALOG=$("$ffmpeg" -hide_banner -loglevel "$ffloglevel" -y \
                        -i "$_src" -vn -c:a copy "$_afile" 2>&1)
                fi
                _atrack="aac:${_afile}"
                ;;
        esac
    fi
    if [ "$LOGlevel" = "2" ] && [ -n "$_ALOG" ]; then
        echo "ffmpeg-AudioDemux LOG:    $_ALOG"
    fi
    if [ -z "$_atrack" ]; then
        echo "    Audio-Track für mp4mux fehlt."
        return 1
    fi

    _fr=$(echo "$_probe" | jq -r '[.streams[]? | select(.codec_type=="video") | .r_frame_rate] | .[0] // "25/1"')
    _fr1=$(echo "$_fr" | awk -F/ '{print $1}')
    _fr2=$(echo "$_fr" | awk -F/ '{print $2}')
    if [ -z "$_fr2" ] || [ "$_fr2" = "0" ]; then
        _fps="$_fr1"
    else
        _fps=$(gawk -v a="$_fr1" -v b="$_fr2" 'BEGIN { print a/b }')
    fi
    [ -n "$_fps" ] || _fps=25

    _vparams="frame_rate=${_fps}"
    if [ "${_mp4mux_inband:-0}" = "1" ]; then
        if [ "$_vtype" = "h264" ]; then
            _vparams="${_vparams},format=avc3"
        else
            _vparams="${_vparams},format=hev1"
        fi
        echo "    mp4mux:               $mp4mux  fps=${_fps}  in-band SPS (${_vparams#*,})"
    else
        echo "    mp4mux:               $mp4mux  fps=${_fps}"
    fi
    rm -f "$_tmpout"
    _MUXLOG=$("$mp4mux" \
        --track "${_vtype}:${_vfile}#${_vparams}" \
        --track "$_atrack" \
        "$_tmpout" 2>&1)
    _delayline=$(printf '%s\n' "$_MUXLOG" | grep 'composition delay' || true)
    [ -n "$_delayline" ] && echo "    $_delayline"
    if [ "$LOGlevel" = "2" ]; then
        echo "mp4mux LOG:              $_MUXLOG"
    fi
    if [ ! -f "$_tmpout" ]; then
        echo "    mp4mux fehlgeschlagen."
        echo "$_MUXLOG"
        return 1
    fi
    _kcount=$("$ffprobe" -v error -select_streams v:0 -show_entries packet=flags -of csv=p=0 "$_tmpout" 2>/dev/null | awk 'index($0,"K"){c++} END{print c+0}')
    echo "    MP4-Keyframes (Index):  ${_kcount}"
    return 0
}

# avcut-HQ: ffmpeg .h264, mp4mux avc3 (in-band SPS pro IDR), Fallback MP4Box.
_synotr_mp4box_from_es() {
    if [ -z "${_audiofile:-}" ] || [ ! -f "$_audiofile" ]; then
        echo "    AAC-Datei für HQ-Remux fehlt."
        return 1
    fi

    _vext=h264
    if [ "$_vcodec" = "hevc" ] || [ "$_vcodec" = "h265" ]; then
        _vext=h265
    elif [ "$_vcodec" != "h264" ]; then
        echo "    HQ-Remux nur für H.264/HEVC."
        return 1
    fi

    _fr=$(echo "$_probe" | jq -r '[.streams[]? | select(.codec_type=="video") | .r_frame_rate] | .[0] // "25/1"')
    _fr1=$(echo "$_fr" | awk -F/ '{print $1}')
    _fr2=$(echo "$_fr" | awk -F/ '{print $2}')
    if [ -z "$_fr2" ] || [ "$_fr2" = "0" ]; then
        _fps="$_fr1"
    else
        _fps=$(gawk -v a="$_fr1" -v b="$_fr2" 'BEGIN { print a/b }')
    fi
    [ -n "$_fps" ] || _fps=25

    _muxdir="${WORKDIR:-}"
    _muxdir="${_muxdir%/}"
    if [ -n "$_muxdir" ] && [ -d "$_muxdir" ]; then
        _muxdir="${_muxdir}/tmp_synotr_remux"
    else
        _muxdir="${_srcdir}tmp_synotr_remux"
    fi
    rm -rf "$_muxdir"
    mkdir -p "$_muxdir" || return 1

    _vfile="${_muxdir}/v.${_vext}"
    _VLOG=$("$ffmpeg" -hide_banner -loglevel "$ffloglevel" -y \
        -i "$_src" -an -c:v copy "$_vfile" 2>&1)
    if [ "$LOGlevel" = "2" ]; then
        echo "ffmpeg-VideoDemux HQ:     $_VLOG"
    fi
    if [ ! -f "$_vfile" ]; then
        echo "    Video-Demux fehlgeschlagen."
        return 1
    fi

    # avcut mischt x264- und Original-SPS. avc1 (MP4Box) speichert nur die erste
    # → Stillstand am 2. IDR (~9 s). avc3 hält SPS in-band (wie MKV).
    if [ "$_vext" = "h264" ] && [ "${_mp4mux_ok:-0}" = "1" ]; then
        echo -e; echo " > avcut-HQ Remux (mp4mux avc3, in-band SPS):"
        _mp4mux_inband=1
        if _synotr_mp4mux_es; then
            unset _mp4mux_inband
            return 0
        fi
        unset _mp4mux_inband
        rm -f "$_tmpout"
        echo "    mp4mux avc3 fehlgeschlagen – Fallback MP4Box."
    fi

    if [ -z "${mp4box:-}" ] || [ ! -f "$mp4box" ]; then
        echo "    MP4Box fehlt."
        return 1
    fi
    [ -x "$mp4box" ] || chmod +x "$mp4box" 2>/dev/null || true
    if [ ! -x "$mp4box" ]; then
        echo "    MP4Box nicht ausführbar."
        return 1
    fi

    _vspec="$_vfile"
    _aspec="$_audiofile"
    if echo "${_delay_ms:-0}" | grep -q '^-'; then
        _vspec="${_vfile}#video:delay=${_delay_ms#-}"
    elif [ "${_delay_ms:-0}" != "0" ]; then
        _aspec="${_audiofile}#audio:delay=${_delay_ms}"
    fi

    echo "    MP4Box:               $mp4box  -add ${_vext} -add AAC -fps=${_fps} (OTRavi2mp4)"
    rm -f "$_tmpout"
    # shellcheck disable=SC2086
    _BOXLOG=$("$mp4box" $mp4boxloglevel -add "$_vspec" -add "$_aspec" -fps "$_fps" -tmp "$_muxdir" "$_tmpout" 2>&1) || true
    echo "MP4Box -add ES: $_BOXLOG"
    _dstsz=0
    if [ -f "$_tmpout" ]; then
        _dstsz=$(wc -c < "$_tmpout" | tr -d ' ')
    fi
    if [ ! -f "$_tmpout" ] || [ -z "$_dstsz" ] || [ "$_dstsz" -lt 1048576 ]; then
        echo "    MP4Box-Rohimport fehlgeschlagen (${_dstsz:-0} Byte)."
        rm -f "$_tmpout"
        return 1
    fi
    _kcount=$("$ffprobe" -v error -select_streams v:0 -show_entries packet=flags -of csv=p=0 "$_tmpout" 2>/dev/null | awk 'index($0,"K"){c++} END{print c+0}')
    echo "    MP4-Keyframes (Index):  ${_kcount}"
    return 0
}

_synotr_ensure_mp4_run() {
    _src="$1"
    synotr_mp4_path=""
    _audiofile=""
    _muxdir=""
    if [ -z "$_src" ] || [ ! -f "$_src" ]; then
        echo "synotr_ensure_mp4: Quelldatei fehlt."
        return 1
    fi

    _srcdir=$(dirname "$_src")
    _srcdir="${_srcdir%/}/"
    _base=$(basename "$_src")
    _stem=${_base%.*}
    _out="${_srcdir}${_stem}.mp4"

    _probe=$("$ffprobe" -v quiet -print_format json -show_format -show_streams "$_src" 2>&1)
    _probe="{ ${_probe#*\{}"

    _audiocodec=$(echo "$_probe" | jq -r '[.streams[]? | select(.codec_type=="audio") | .codec_name] | .[0] // "null"')
    _vcodec=$(echo "$_probe" | jq -r '[.streams[]? | select(.codec_type=="video") | .codec_name] | .[0] // "null"')
    _vtag=$(echo "$_probe" | jq -r '[.streams[]? | select(.codec_type=="video") | .codec_tag_string] | .[0] // "null"' | tr '[:upper:]' '[:lower:]')
    _fmtenc=$(echo "$_probe" | jq -r '.format.tags.encoder // .format.tags.ENCODER // empty')

    echo "Audiocodec:               $_audiocodec"
    echo "Videocodec:               $_vcodec ($_vtag)"

    _mp4mux_ok=0
    if [ -n "${mp4mux:-}" ] && [ -f "$mp4mux" ]; then
        [ -x "$mp4mux" ] || chmod +x "$mp4mux" 2>/dev/null || true
        [ -x "$mp4mux" ] && _mp4mux_ok=1
    fi
    _mp4box_ok=0
    if [ -n "${mp4box:-}" ] && [ -f "$mp4box" ]; then
        [ -x "$mp4box" ] || chmod +x "$mp4box" 2>/dev/null || true
        [ -x "$mp4box" ] && _mp4box_ok=1
    fi

    _lavf=0
    if [ -n "$_fmtenc" ] && echo "$_fmtenc" | grep -qi lavf; then
        _lavf=1
    fi

    case "$_base" in
        *.mp4|*.MP4)
            if [ "$_audiocodec" = "aac" ] || [ "$_audiocodec" = "ac3" ]; then
                if [ "$_mp4mux_ok" = "1" ] && [ "$_lavf" = "1" ] && { [ "$_vcodec" = "h264" ] || [ "$_vcodec" = "hevc" ] || [ "$_vcodec" = "h265" ]; }; then
                    echo "    L==> ffmpeg-MP4 (Lavf) – Remux per mp4mux gegen B-Frame-Zittern"
                else
                    echo "    L==> bereits MP4 mit ${_audiocodec} – Remux übersprungen"
                    synotr_mp4_path="$_src"
                    return 0
                fi
            fi
            ;;
    esac

    _vbsf=""
    if [ "$_vcodec" = "mpeg4" ] || [ "$_vtag" = "mpeg4" ] || [ "$_vtag" = "divx" ] || [ "$_vtag" = "dx50" ] || [ "$_vtag" = "xvid" ]; then
        _vbsf="mpeg4_unpack_bframes"
        echo "Packed-Bitstream:         mpeg4_unpack_bframes"
    fi

    _delay_ms=${AudioDelayMs:-0}
    [ -z "$_delay_ms" ] && _delay_ms=0
    _tmpout="${_srcdir}${_stem}.synotr.tmp.mp4"
    rm -f "$_tmpout"

    _dsec="0"
    _delay_neg=0
    if echo "$_delay_ms" | grep -q '^-'; then
        _delay_neg=1
        _dsec=$(gawk -v ms="$_delay_ms" 'BEGIN { printf "%.3f", -ms/1000 }')
    elif [ "$_delay_ms" != "0" ]; then
        _dsec=$(gawk -v ms="$_delay_ms" 'BEGIN { printf "%.3f", ms/1000 }')
    fi
    if [ "$_dsec" != "0" ] && [ "$_dsec" != "0.000" ]; then
        echo "Audio-Video-Sync:         AudioDelayMs=${_delay_ms} (${_dsec}s)"
    fi

    if [ "$_audiocodec" = "mp3" ]; then
        echo -e; echo " > Konvertiere Audiospur nach AAC:"
        if ! synotr_aac_encode_opts; then
            return 1
        fi
        _audiofile="${_srcdir}${_stem}.synotr.audio.mp3"
        _AUDIODEMUX=$("$ffmpeg" -hide_banner -loglevel "$ffloglevel" -y -i "$_src" -vn -c:a copy "$_audiofile" 2>&1)
        if [ "$LOGlevel" = "2" ]; then
            echo "ffmpeg-AudioDemux LOG:    $_AUDIODEMUX"
        fi
        if [ ! -f "$_audiofile" ]; then
            echo "Audiodemux fehlgeschlagen."
            return 1
        fi
        if [ "$normalizeAudio" = "on" ]; then
            _volumeinfo=$("$ffmpeg" -i "$_audiofile" -af "volumedetect" -f null - 2>&1 | awk '-F: ' '/max_volume/ { gsub(/ .*/, "", $2); print $2 }' | sed 's/-//g')
            echo "Lautstärkeanhebung um:    ${_volumeinfo} dB"
            synotr_encode_audio "$_audiofile" "${_audiofile}.m4a" "${synotr_aac_opts} -af volume=${_volumeinfo}dB"
        else
            synotr_encode_audio "$_audiofile" "${_audiofile}.m4a" "${synotr_aac_opts}"
        fi
        rm -f "$_audiofile"
        _audiofile="${_audiofile}.m4a"
        if [ ! -f "$_audiofile" ]; then
            echo "AAC-Konvertierung fehlgeschlagen."
            return 1
        fi
    fi

    _used_mp4mux=0
    _already_aac_mp4=0
    case "$_base" in
        *.mp4|*.MP4)
            if [ "$_audiocodec" = "aac" ] || [ "$_audiocodec" = "ac3" ]; then
                _already_aac_mp4=1
            fi
            ;;
    esac
    if [ "${_ensure_mp4_mp4box:-0}" = "1" ] && { [ "$_mp4mux_ok" = "1" ] || [ "$_mp4box_ok" = "1" ]; }; then
        echo -e; echo " > avcut-HQ Remux (mp4mux avc3 / MP4Box-Fallback):"
        if _synotr_mp4box_from_es; then
            _used_mp4mux=1
        else
            rm -f "$_tmpout"
            echo "    MP4Box fehlgeschlagen – Fallback mp4mux."
        fi
    fi
    if [ "$_used_mp4mux" != "1" ] && [ "$_mp4mux_ok" = "1" ] && { [ "$_vcodec" = "h264" ] || [ "$_vcodec" = "hevc" ] || [ "$_vcodec" = "h265" ]; }; then
        echo -e; echo " > Remux nach MP4 (ffmpeg-Demux, Bento4 mp4mux):"
        if _synotr_mp4mux_from_src; then
            _used_mp4mux=1
        else
            rm -f "$_tmpout"
            if [ "$_already_aac_mp4" = "1" ]; then
                echo "    mp4mux fehlgeschlagen – bestehende MP4 bleibt unverändert."
                _synotr_remux_cleanup
                synotr_mp4_path="$_src"
                return 0
            fi
            echo "    mp4mux fehlgeschlagen – Fallback ffmpeg-Mux (kann zittern)."
        fi
    fi
    if [ "$_used_mp4mux" != "1" ]; then
        if [ -n "${_audiofile:-}" ] && [ -f "$_audiofile" ]; then
            echo -e; echo " > ffmpeg Remux nach MP4:"
        else
            echo -e; echo " > ffmpeg Remux nach MP4 (Audio copy):"
        fi
        _synotr_ensure_mp4_ffmpeg_from_inputs
    fi

    if [ ! -f "$_tmpout" ]; then
        echo "FEHLER: Zieldatei nach Remux nicht gefunden!"
        _synotr_remux_cleanup
        return 1
    fi

    if [ "$_src" = "$_out" ]; then
        if [ "$endgueltigloeschen" = "on" ]; then
            rm -f "$_src"
        else
            mv "$_src" "${OTRkeydeldir}${_stem}.pre-remux.mp4"
        fi
        mv "$_tmpout" "$_out"
    else
        if [ "$endgueltigloeschen" = "on" ]; then
            rm -f "$_src"
        else
            mv "$_src" "${OTRkeydeldir}"
        fi
        mv "$_tmpout" "$_out"
    fi

    _synotr_remux_cleanup
    echo -n "    L==> "
    echo "$(basename "$_out") wurde erstellt"
    synotr_mp4_path="$_out"
    return 0
}

synotr_ensure_mp4() {
    _synotr_mp4_saved_ifs=$IFS
    IFS=${OLDIFS:-' '}
    _synotr_ensure_mp4_run "$1"
    _synotr_mp4_rc=$?
    IFS="$_synotr_mp4_saved_ifs"
    return "${_synotr_mp4_rc}"
}
