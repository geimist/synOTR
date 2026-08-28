# shellcheck shell=sh
# shellcheck disable=SC2154
# synotr_ffmpeg_cut SRC DST
# Keyframe-Copy: ffmpeg demuxt Elementarströme; Mux mit Bento4 mp4mux (x86_64 und aarch64)
# oder Fallback MP4Box -add (i386). ffmpeg-Concat zittert bei HD-H.264.
# Erwartet (aus synOTR.sh): ffmpeg ffprobe mp4mux mp4box ffloglevel LOGlevel
#           mp4boxloglevel keep_times WORKDIR tmp AudioDelayMs AC_ffprobeInfo OLDIFS
# otr2-Keyframe (SMARTRENDERING=off). otrkey nutzt avisplit, nicht diese Funktion.

synotr_ffmpeg_cut() {
    _src="$1"
    _dst="$2"
    if [ -z "$_src" ] || [ ! -f "$_src" ] || [ -z "$_dst" ]; then
        echo "synotr_ffmpeg_cut: Quelle oder Ziel fehlt."
        return 1
    fi
    if [ -z "$keep_times" ]; then
        echo "synotr_ffmpeg_cut: keine Keep-Intervalle."
        return 1
    fi
    if [ -n "$mp4mux" ] && [ -f "$mp4mux" ] && [ ! -x "$mp4mux" ]; then
        chmod +x "$mp4mux" 2>/dev/null || true
    fi
    if [ -n "$mp4box" ] && [ -f "$mp4box" ] && [ ! -x "$mp4box" ]; then
        chmod +x "$mp4box" 2>/dev/null || true
    fi

    _segbase="${WORKDIR:-$tmp}"
    _segbase="${_segbase%/}"
    [ -n "$_segbase" ] && [ -d "$_segbase" ] || _segbase="${tmp%/}"
    # Unter tmp_synotr_cut, damit Crash-Reste im Arbeitsverzeichnis in einem Ordner liegen.
    _segdir="${tmp:-${_segbase}/tmp_synotr_cut}/ffcut"
    rm -rf "$_segdir"
    mkdir -p "$_segdir" || return 1

    _probe="$AC_ffprobeInfo"
    if [ -z "$_probe" ]; then
        _probe=$("$ffprobe" -v quiet -print_format json -show_format -show_streams "$_src" 2>&1)
        _probe="{ ${_probe#*\{}"
    fi
    _vcodec=$(echo "$_probe" | jq -r '[.streams[]? | select(.codec_type=="video") | .codec_name] | .[0] // empty')
    _acodec=$(echo "$_probe" | jq -r '[.streams[]? | select(.codec_type=="audio") | .codec_name] | .[0] // empty')
    _fr=$(echo "$_probe" | jq -r '[.streams[]? | select(.codec_type=="video") | .r_frame_rate] | .[0] // "25/1"')
    _fr1=$(echo "$_fr" | awk -F/ '{print $1}')
    _fr2=$(echo "$_fr" | awk -F/ '{print $2}')
    if [ -z "$_fr2" ] || [ "$_fr2" = "0" ]; then
        _fps="$_fr1"
    else
        _fps=$(gawk -v a="$_fr1" -v b="$_fr2" 'BEGIN { print a/b }')
    fi
    [ -n "$_fps" ] || _fps=25

    _vbsf=""
    _vext=h264
    _vtype=h264
    if [ "$_vcodec" = "h264" ]; then
        _vbsf="h264_mp4toannexb"
        _vext=h264
        _vtype=h264
    elif [ "$_vcodec" = "hevc" ] || [ "$_vcodec" = "h265" ]; then
        _vbsf="hevc_mp4toannexb"
        _vext=h265
        _vtype=h265
    else
        _vext=tmp.m4v
        _vtype=""
    fi
    _aext="${_acodec:-aac}"
    case "$_acodec" in
        ac3) _atype=ac3 ;;
        eac3|ec3) _atype=ec3 ;;
        *) _atype=aac ;;
    esac

    _use_mp4mux=0
    if [ -n "$mp4mux" ] && [ -x "$mp4mux" ] && [ -n "$_vtype" ]; then
        _use_mp4mux=1
    fi
    if [ "$_use_mp4mux" != "1" ] && { [ -z "$mp4box" ] || [ ! -x "$mp4box" ]; }; then
        echo "    FEHLER: weder mp4mux noch MP4Box. ffmpeg-Mux zittert bei HD-H.264."
        rm -rf "$_segdir"
        return 1
    fi

    _delay_ms=${AudioDelayMs:-0}
    [ -z "$_delay_ms" ] && _delay_ms=0
    _vdelay=""
    _adelay=""
    if echo "$_delay_ms" | grep -q '^-'; then
        _vdelay="#video:delay=${_delay_ms#-}"
        echo "    Audio-Video-Sync:     Video verzögert (MP4Box-Delay)"
    elif [ "$_delay_ms" != "0" ]; then
        _adelay="#audio:delay=${_delay_ms}"
        echo "    Audio-Video-Sync:     Audio um ${_delay_ms}ms verzögert (MP4Box-Delay)"
    fi
    if [ "$_use_mp4mux" = "1" ] && [ "$_delay_ms" != "0" ]; then
        echo "    Hinweis: AudioDelayMs greift bei mp4mux nicht (nur MP4Box #delay=)."
    fi

    _quiet="$mp4boxloglevel"
    if [ "$_use_mp4mux" = "1" ]; then
        echo "    Keyframe-Copy: ffmpeg-Demux, Bento4 mp4mux, fps=${_fps}"
        echo "    mp4mux:               $mp4mux"
    else
        echo "    Keyframe-Copy: ffmpeg-Demux, MP4Box -add, fps=${_fps}"
        echo "    MP4Box:               $mp4box"
    fi

    _n=0
    _ok=1
    # keep_times ist leerzeichengetrennt; Cut-Schleife kann IFS=Newline gesetzt haben.
    _ffcut_ifs=$IFS
    IFS=${OLDIFS:-' '}
    # shellcheck disable=SC2086
    set -- $keep_times
    IFS="$_ffcut_ifs"
    while [ $# -ge 2 ]; do
        _kstart=$1
        _kend=$2
        shift 2
        _n=$((_n + 1))
        _kdur=$(gawk -v e="$_kend" -v s="$_kstart" 'BEGIN { d=e-s; if (d < 0.04) d=0.04; printf "%.3f", d }')
        _vfile="${_segdir}/v${_n}.${_vext}"
        _afile="${_segdir}/a${_n}.${_aext}"
        echo "    Segment ${_n}: ${_kstart}s – ${_kend}s (${_kdur}s)"

        if [ -n "$_vbsf" ]; then
            _VLOG=$("$ffmpeg" -hide_banner -loglevel "$ffloglevel" -y \
                -ss "$_kstart" -i "$_src" -t "$_kdur" \
                -map 0:v:0 -an -c:v copy -bsf:v "$_vbsf" "$_vfile" 2>&1)
        else
            _VLOG=$("$ffmpeg" -hide_banner -loglevel "$ffloglevel" -y \
                -ss "$_kstart" -i "$_src" -t "$_kdur" \
                -map 0:v:0 -an -c:v copy "$_vfile" 2>&1)
        fi
        _ALOG=$("$ffmpeg" -hide_banner -loglevel "$ffloglevel" -y \
            -ss "$_kstart" -i "$_src" -t "$_kdur" \
            -map 0:a:0 -vn -c:a copy "$_afile" 2>&1)
        if [ "$LOGlevel" = "2" ]; then
            echo "ffmpeg-VideoDemux Segment ${_n}: $_VLOG"
            echo "ffmpeg-AudioDemux Segment ${_n}: $_ALOG"
        fi
        if [ ! -f "$_vfile" ] || [ ! -f "$_afile" ]; then
            echo "    Demux Segment ${_n} fehlgeschlagen."
            _ok=0
            break
        fi
    done

    if [ "$_ok" != "1" ] || [ "$_n" -lt 1 ]; then
        rm -rf "$_segdir"
        return 1
    fi

    rm -f "$_dst"
    if [ "$_use_mp4mux" = "1" ]; then
        _vall="${_segdir}/all.${_vext}"
        _aall="${_segdir}/all.${_aext}"
        : > "$_vall"
        : > "$_aall"
        _i=1
        while [ "$_i" -le "$_n" ]; do
            cat "${_segdir}/v${_i}.${_vext}" >> "$_vall"
            cat "${_segdir}/a${_i}.${_aext}" >> "$_aall"
            _i=$((_i + 1))
        done
        _MUXLOG=$("$mp4mux" \
            --track "${_vtype}:${_vall}#frame_rate=${_fps}" \
            --track "${_atype}:${_aall}" \
            "$_dst" 2>&1)
        if [ "$LOGlevel" = "2" ]; then
            echo "mp4mux LOG: $_MUXLOG"
        fi
        if [ ! -f "$_dst" ]; then
            echo "    mp4mux fehlgeschlagen."
            echo "$_MUXLOG"
            rm -rf "$_segdir"
            return 1
        fi
    else
        _i=1
        while [ "$_i" -le "$_n" ]; do
            _vfile="${_segdir}/v${_i}.${_vext}"
            _afile="${_segdir}/a${_i}.${_aext}"
            _seg=$(printf "%s/seg%03d.mp4" "$_segdir" "$_i")
            set -- "$mp4box"
            [ -n "$_quiet" ] && set -- "$@" "$_quiet"
            set -- "$@" \
                -add "${_vfile}${_vdelay}" \
                -add "${_afile}${_adelay}" \
                -fps "$_fps" \
                -tmp "$_segdir" \
                "$_seg"
            _BOXLOG=$("$@" 2>&1)
            if [ "$LOGlevel" = "2" ]; then
                echo "MP4Box -add Segment ${_i}: $_BOXLOG"
            fi
            if [ ! -f "$_seg" ]; then
                echo "    MP4Box -add Segment ${_i} fehlgeschlagen."
                echo "$_BOXLOG"
                rm -rf "$_segdir"
                return 1
            fi
            _i=$((_i + 1))
        done
        if [ "$_n" -eq 1 ]; then
            mv "${_segdir}/seg001.mp4" "$_dst"
        else
            set -- "$mp4box"
            if [ -n "$_quiet" ]; then
                set -- "$@" "$_quiet"
            fi
            _i=1
            while [ "$_i" -le "$_n" ]; do
                _seg=$(printf "%s/seg%03d.mp4" "$_segdir" "$_i")
                set -- "$@" -cat "$_seg"
                _i=$((_i + 1))
            done
            set -- "$@" -new "$_dst"
            _CATLOG=$("$@" 2>&1)
            if [ "$LOGlevel" = "2" ]; then
                echo "MP4Box -cat: $_CATLOG"
            fi
            if [ ! -f "$_dst" ]; then
                echo "    MP4Box -cat fehlgeschlagen."
                echo "$_CATLOG"
                rm -rf "$_segdir"
                return 1
            fi
        fi
    fi
    rm -rf "$_segdir"
    return 0
}

# avcut-MKV → MP4 per MP4Box -add auf Rohstreams (i386). Die alte GPAC kann kein MKV
# („Unknown input file type“), legt aber trotzdem eine ~200-Byte-Hülle an – die zählt nicht.
# Kein mp4mux/ffmpeg-Copy (Freeze bzw. Ruckeln).
synotr_avcut_to_mp4() {
    _src="$1"
    _dst="$2"
    if [ -z "$_src" ] || [ ! -f "$_src" ] || [ -z "$_dst" ]; then
        echo "synotr_avcut_to_mp4: Quelle oder Ziel fehlt."
        return 1
    fi
    if [ -z "${mp4box:-}" ] || [ ! -f "$mp4box" ]; then
        echo "    MP4Box fehlt (i386, nur x86) – avcut-MKV bleibt."
        return 1
    fi
    [ -x "$mp4box" ] || chmod +x "$mp4box" 2>/dev/null || true
    if [ ! -x "$mp4box" ]; then
        echo "    MP4Box nicht ausführbar – avcut-MKV bleibt."
        return 1
    fi

    _boxdir="${tmp:-${WORKDIR:-.}}"
    _boxdir="${_boxdir%/}/mp4box_avcut"
    rm -rf "$_boxdir"
    mkdir -p "$_boxdir" || return 1
    rm -f "$_dst"

    _probe=$("$ffprobe" -v quiet -print_format json -show_format -show_streams "$_src" 2>&1)
    _probe="{ ${_probe#*\{}"
    _vcodec=$(echo "$_probe" | jq -r '[.streams[]? | select(.codec_type=="video") | .codec_name] | .[0] // empty')
    _acodec=$(echo "$_probe" | jq -r '[.streams[]? | select(.codec_type=="audio") | .codec_name] | .[0] // empty')
    _fr=$(echo "$_probe" | jq -r '[.streams[]? | select(.codec_type=="video") | .r_frame_rate] | .[0] // "25/1"')
    _fr1=$(echo "$_fr" | awk -F/ '{print $1}')
    _fr2=$(echo "$_fr" | awk -F/ '{print $2}')
    if [ -z "$_fr2" ] || [ "$_fr2" = "0" ]; then
        _fps="$_fr1"
    else
        _fps=$(gawk -v a="$_fr1" -v b="$_fr2" 'BEGIN { print a/b }')
    fi
    [ -n "$_fps" ] || _fps=25

    _vbsf=""
    _vext=h264
    if [ "$_vcodec" = "h264" ]; then
        _vbsf="h264_mp4toannexb"
        _vext=h264
    elif [ "$_vcodec" = "hevc" ] || [ "$_vcodec" = "h265" ]; then
        _vbsf="hevc_mp4toannexb"
        _vext=h265
    fi
    _vfile="${_boxdir}/v.${_vext}"
    _afile="${_boxdir}/a.m4a"

    echo "    avcut-Remux: MP4Box -add Rohstream fps=${_fps}"
    # -f data allein reicht bei ffmpeg 8 nicht: pts < dts am avcut-Spleiß → Paketverlust.
    # setts=N nur für den Muxer (monotones DTS); Reihenfolge bleibt Decoder-Order.
    # MP4Box setzt die Zeiten neu per fps. Kein igndts (sonst Anzeige- statt Decoderreihenfolge).
    _vbsf_chain="$_vbsf"
    if [ -n "$_vbsf_chain" ]; then
        _vbsf_chain="${_vbsf_chain},setts=pts=N:dts=N"
    else
        _vbsf_chain="setts=pts=N:dts=N"
    fi
    _VLOG=$("$ffmpeg" -hide_banner -loglevel "$ffloglevel" -y \
        -i "$_src" -map 0:v:0 -an -c:v copy -bsf:v "$_vbsf_chain" \
        -f data "$_vfile" 2>&1) || true
    if [ "$LOGlevel" = "2" ]; then
        echo "ffmpeg-VideoDemux MP4Box: $_VLOG"
    fi
    if [ ! -f "$_vfile" ]; then
        echo "    Video-Demux für MP4Box fehlgeschlagen."
        rm -rf "$_boxdir"
        return 1
    fi

    echo " > Konvertiere Audiospur nach AAC:"
    if ! synotr_aac_encode_opts; then
        rm -rf "$_boxdir"
        return 1
    fi
    if [ "$_acodec" = "aac" ]; then
        _ALOG=$("$ffmpeg" -hide_banner -loglevel "$ffloglevel" -y \
            -i "$_src" -map 0:a:0 -vn -c:a copy "$_afile" 2>&1) || true
    else
        _araw="${_boxdir}/a.${_acodec:-mp3}"
        _ALOG=$("$ffmpeg" -hide_banner -loglevel "$ffloglevel" -y \
            -i "$_src" -map 0:a:0 -vn -c:a copy "$_araw" 2>&1) || true
        if [ ! -f "$_araw" ]; then
            echo "Audiodemux fehlgeschlagen."
            rm -rf "$_boxdir"
            return 1
        fi
        if [ "$normalizeAudio" = "on" ]; then
            _volumeinfo=$("$ffmpeg" -i "$_araw" -af "volumedetect" -f null - 2>&1 | awk '-F: ' '/max_volume/ { gsub(/ .*/, "", $2); print $2 }' | sed 's/-//g')
            echo "Lautstärkeanhebung um:    ${_volumeinfo} dB"
            synotr_encode_audio "$_araw" "$_afile" "${synotr_aac_opts} -af volume=${_volumeinfo}dB"
        else
            synotr_encode_audio "$_araw" "$_afile" "${synotr_aac_opts}"
        fi
        rm -f "$_araw"
        if [ "$LOGlevel" = "2" ] && [ -n "${convertLOG:-}" ]; then
            echo "ffmpeg-AAC LOG:           $convertLOG"
        fi
    fi
    if [ ! -f "$_afile" ]; then
        echo "AAC-Konvertierung fehlgeschlagen – avcut-MKV bleibt."
        rm -rf "$_boxdir"
        return 1
    fi

    rm -f "$_dst"
    set -- "$mp4box" -add "$_vfile" -add "$_afile" -fps "$_fps" -tmp "$_boxdir" "$_dst"
    _BOXLOG=$("$@" 2>&1) || true
    echo "MP4Box -add ES: $_BOXLOG"
    rm -rf "$_boxdir"
    _dstsz=$(wc -c < "$_dst" 2>/dev/null | tr -d ' ')
    if [ ! -f "$_dst" ] || [ -z "$_dstsz" ] || [ "$_dstsz" -lt 1048576 ]; then
        echo "    MP4Box-Remux fehlgeschlagen (${_dstsz:-0} Byte)."
        rm -f "$_dst"
        return 1
    fi
    echo "    MP4Box-MP4: ${_dstsz} Byte"
    return 0
}
