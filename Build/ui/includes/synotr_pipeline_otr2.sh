# shellcheck shell=sh
# shellcheck disable=SC2154,SC2034,SC2086
# otr2-Pipeline: natives MP4. Smartrendering = avcut 0.8 (ffmpeg8) → MKV, dann
# ffmpeg -c copy nach MP4 (Zeiten aus der MKV, Tonspuren nach OTRotr2audio).
# Nicht mp4mux: POC nach avcut-Spleiß ist unbrauchbar → composition delay 154 → Freeze.
# Keyframe = synotr_ffmpeg_cut (ffmpeg-Demux + mp4mux).
# Erwartet: film outputfile time keep_times SMARTRENDERING avcut_ffmpeg8
#           ffmpeg ffprobe APPDIR tmp WORKDIR LOGlevel ffloglevel OLDIFS OTRotr2audio

# OTRotr2audio: both | aac | ac3  (Default both)
synotr_otr2_audio_want() {
    case "${OTRotr2audio:-both}" in
        aac|AAC) synotr_otr2_a_want=aac ;;
        ac3|AC3|eac3|EAC3) synotr_otr2_a_want=ac3 ;;
        *) synotr_otr2_a_want=both ;;
    esac
}

synotr_otr2_is_aac() {
    [ "$1" = "aac" ]
}

synotr_otr2_is_ac3() {
    [ "$1" = "ac3" ] || [ "$1" = "eac3" ] || [ "$1" = "ec3" ]
}

# $1=wortliste $2=1-basierter Index → Wort
synotr_otr2_nth() {
    printf '%s\n' "$1" | awk -v n="$2" '{ print $n }'
}

# $1=nadel $2=wortliste → 0 wenn enthalten
synotr_otr2_list_has() {
    printf '%s\n' "$2" | awk -v n="$1" '{ for (i = 1; i <= NF; i++) if ($i == n) exit 0; exit 1 }'
}

# $1=codec → "ext kind" für mp4mux (ADTS/AC3-Rohstream)
synotr_otr2_audio_muxkind() {
    case "$1" in
        ac3) printf '%s %s\n' ac3 ac3 ;;
        eac3|ec3) printf '%s %s\n' eac3 ec3 ;;
        *) printf '%s %s\n' aac aac ;;
    esac
}

# synotr_otr2_audio_plan PROBE_JSON
# Setzt synotr_otr2_a_want/rel/codec/n/ident/note/fallback.
# rel = 0-basierte Audio-Indizes in Ausgabe-Reihenfolge (ffmpeg 0:a:N).
# ident=1: alle Tonspuren in Originalreihenfolge → ffmpeg -map 0 reicht.
synotr_otr2_audio_plan() {
    _probe="$1"
    synotr_otr2_audio_want
    synotr_otr2_a_rel=""
    synotr_otr2_a_codec=""
    synotr_otr2_a_n=0
    synotr_otr2_a_ident=0
    synotr_otr2_a_note=""
    synotr_otr2_a_fallback=0

    if [ -z "$_probe" ]; then
        return 1
    fi

    _src_n=$(printf '%s\n' "$_probe" | jq '[.streams[]? | select(.codec_type=="audio")] | length' 2>/dev/null)
    if [ -z "$_src_n" ] || [ "$_src_n" = "null" ]; then
        _src_n=0
    fi
    if ! echo "$_src_n" | grep -Eq '^[0-9]+$' || [ "$_src_n" -lt 1 ]; then
        unset _probe _src_n
        return 1
    fi

    _src_rel=""
    _src_codec=""
    _aac_rel=""
    _aac_codec=""
    _ac3_rel=""
    _ac3_codec=""
    _i=0
    while [ "$_i" -lt "$_src_n" ]; do
        _cod=$(printf '%s\n' "$_probe" | jq -r --arg i "$_i" '[.streams[]? | select(.codec_type=="audio")] | .[$i | tonumber].codec_name // empty' 2>/dev/null)
        [ -n "$_cod" ] || _cod="unknown"
        _src_rel="${_src_rel:+$_src_rel }$_i"
        _src_codec="${_src_codec:+$_src_codec }$_cod"
        if [ -z "$_aac_rel" ] && synotr_otr2_is_aac "$_cod"; then
            _aac_rel="$_i"
            _aac_codec="$_cod"
        fi
        if [ -z "$_ac3_rel" ] && synotr_otr2_is_ac3 "$_cod"; then
            _ac3_rel="$_i"
            _ac3_codec="$_cod"
        fi
        _i=$((_i + 1))
    done

    if [ "$_src_n" -eq 1 ]; then
        synotr_otr2_a_rel="$_src_rel"
        synotr_otr2_a_codec="$_src_codec"
        synotr_otr2_a_n=1
        synotr_otr2_a_ident=1
        synotr_otr2_a_note="eine Tonspur (${_src_codec})"
        unset _probe _src_n _src_rel _src_codec _aac_rel _aac_codec _ac3_rel _ac3_codec _i _cod
        return 0
    fi

    case "$synotr_otr2_a_want" in
        aac)
            if [ -n "$_aac_rel" ]; then
                synotr_otr2_a_rel="$_aac_rel"
                synotr_otr2_a_codec="$_aac_codec"
                synotr_otr2_a_n=1
                synotr_otr2_a_note="nur AAC (Stereo)"
            else
                synotr_otr2_a_rel=$(synotr_otr2_nth "$_src_rel" 1)
                synotr_otr2_a_codec=$(synotr_otr2_nth "$_src_codec" 1)
                synotr_otr2_a_n=1
                synotr_otr2_a_fallback=1
                synotr_otr2_a_note="nur AAC gewünscht, nicht vorhanden – Fallback ${synotr_otr2_a_codec}"
            fi
            ;;
        ac3)
            if [ -n "$_ac3_rel" ]; then
                synotr_otr2_a_rel="$_ac3_rel"
                synotr_otr2_a_codec="$_ac3_codec"
                synotr_otr2_a_n=1
                synotr_otr2_a_note="nur AC3 (5.1)"
            else
                synotr_otr2_a_rel=$(synotr_otr2_nth "$_src_rel" 1)
                synotr_otr2_a_codec=$(synotr_otr2_nth "$_src_codec" 1)
                synotr_otr2_a_n=1
                synotr_otr2_a_fallback=1
                synotr_otr2_a_note="nur AC3 gewünscht, nicht vorhanden – Fallback ${synotr_otr2_a_codec}"
            fi
            ;;
        *)
            _out_rel=""
            _out_codec=""
            _out_n=0
            if [ -n "$_aac_rel" ]; then
                _out_rel="$_aac_rel"
                _out_codec="$_aac_codec"
                _out_n=1
            fi
            if [ -n "$_ac3_rel" ]; then
                _out_rel="${_out_rel:+$_out_rel }$_ac3_rel"
                _out_codec="${_out_codec:+$_out_codec }$_ac3_codec"
                _out_n=$((_out_n + 1))
            fi
            if [ "$_out_n" -eq 0 ]; then
                synotr_otr2_a_rel="$_src_rel"
                synotr_otr2_a_codec="$_src_codec"
                synotr_otr2_a_n="$_src_n"
                synotr_otr2_a_ident=1
                synotr_otr2_a_note="beide gewünscht, weder AAC noch AC3 – alle Tonspuren"
                unset _probe _src_n _src_rel _src_codec _aac_rel _aac_codec _ac3_rel _ac3_codec _i _cod _out_rel _out_codec _out_n
                return 0
            fi
            _i=1
            while [ "$_i" -le "$_src_n" ]; do
                _r=$(synotr_otr2_nth "$_src_rel" "$_i")
                _c=$(synotr_otr2_nth "$_src_codec" "$_i")
                if ! synotr_otr2_list_has "$_r" "$_out_rel"; then
                    _out_rel="${_out_rel:+$_out_rel }$_r"
                    _out_codec="${_out_codec:+$_out_codec }$_c"
                    _out_n=$((_out_n + 1))
                fi
                _i=$((_i + 1))
            done
            synotr_otr2_a_rel="$_out_rel"
            synotr_otr2_a_codec="$_out_codec"
            synotr_otr2_a_n="$_out_n"
            if [ "$_out_rel" = "$_src_rel" ]; then
                synotr_otr2_a_ident=1
            fi
            if [ -n "$_aac_rel" ] && [ -n "$_ac3_rel" ]; then
                synotr_otr2_a_note="AAC Stereo + AC3 5.1"
            elif [ -n "$_aac_rel" ]; then
                synotr_otr2_a_note="beide gewünscht – nur AAC vorhanden"
            else
                synotr_otr2_a_note="beide gewünscht – nur AC3 vorhanden"
            fi
            unset _out_rel _out_codec _out_n _r _c
            ;;
    esac

    unset _probe _src_n _src_rel _src_codec _aac_rel _aac_codec _ac3_rel _ac3_codec _i _cod
    return 0
}

# ffmpeg -c copy SRC→DST. ident=1: -map 0. Sonst Video + gewählte Tonspuren, AAC zuerst.
synotr_otr2_ffmpeg_copy() {
    _src="$1"
    _dst="$2"
    if [ -z "$_src" ] || [ ! -f "$_src" ] || [ -z "$_dst" ]; then
        echo "synotr_otr2_ffmpeg_copy: Quelle oder Ziel fehlt."
        return 1
    fi

    _probe=$("$ffprobe" -v quiet -print_format json -show_format -show_streams "$_src" 2>&1)
    _probe="{ ${_probe#*\{}"
    if ! synotr_otr2_audio_plan "$_probe"; then
        echo "    otr2-Tonspuren:       keine Audiospur in der Quelle."
        unset _probe
        return 1
    fi
    echo "    otr2-Tonspuren:       $synotr_otr2_a_note"

    set -- "$ffmpeg" -hide_banner -loglevel "$ffloglevel" -y -i "$_src"
    if [ "$synotr_otr2_a_ident" = "1" ]; then
        echo "    ffmpeg -c copy, alle Spuren, Zeiten aus der Quelle"
        set -- "$@" -map 0
    else
        echo "    ffmpeg -c copy, Video + ausgewählte Tonspuren"
        set -- "$@" -map 0:v:0
        _i=1
        while [ "$_i" -le "$synotr_otr2_a_n" ]; do
            _r=$(synotr_otr2_nth "$synotr_otr2_a_rel" "$_i")
            set -- "$@" -map "0:a:${_r}"
            _i=$((_i + 1))
        done
        set -- "$@" -disposition:a:0 default
        _i=1
        while [ "$_i" -lt "$synotr_otr2_a_n" ]; do
            set -- "$@" -disposition:a:"$_i" 0
            _i=$((_i + 1))
        done
    fi
    set -- "$@" -c copy -movflags +faststart "$_dst"

    rm -f "$_dst"
    _COPYLOG=$("$@" 2>&1)
    _dts_n=$(printf '%s\n' "$_COPYLOG" | grep -c 'Non-monotonic DTS' || true)
    _guess_n=$(printf '%s\n' "$_COPYLOG" | grep -c 'Invalid DTS:' || true)
    if [ "${_dts_n:-0}" -gt 0 ] || [ "${_guess_n:-0}" -gt 0 ]; then
        echo "    ffmpeg hat ${_dts_n} nicht-monotone DTS und ${_guess_n} DTS-Guess geglättet (avcut-Spleiß, Wiedergabe unkritisch)."
    fi
    if [ "$LOGlevel" = "2" ]; then
        echo "ffmpeg-Copy LOG (ohne DTS-Glättung):"
        printf '%s\n' "$_COPYLOG" | grep -v 'Non-monotonic DTS' | grep -v 'Invalid DTS:' || true
    fi
    _dstsz=0
    if [ -f "$_dst" ]; then
        _dstsz=$(wc -c < "$_dst" | tr -d ' ')
    fi
    unset _probe _i _r
    if [ -f "$_dst" ] && [ -n "$_dstsz" ] && [ "$_dstsz" -gt 1048576 ]; then
        unset _COPYLOG _dts_n _guess_n _dstsz
        return 0
    fi
    echo "    ffmpeg-Copy fehlgeschlagen (${_dstsz:-0} Byte)."
    echo "$_COPYLOG"
    rm -f "$_dst"
    unset _COPYLOG _dts_n _guess_n _dstsz
    return 1
}

# avcut schreibt nur MKV zuverlässig (MP4-Muxer bricht ab). Zeiten nicht neu setzen.
synotr_otr2_mkv_to_mp4() {
    _src="$1"
    _dst="$2"
    if [ -z "$_src" ] || [ ! -f "$_src" ] || [ -z "$_dst" ]; then
        echo "synotr_otr2_mkv_to_mp4: Quelle oder Ziel fehlt."
        return 1
    fi
    echo "    avcut-MKV → MP4 (ffmpeg -c copy, Zeiten aus MKV)"
    synotr_otr2_ffmpeg_copy "$_src" "$_dst"
}

# Ohne Schnitt: natives otr2-MP4 nur remuxen, wenn nicht „beide“.
# WaitOfCutlist-Dateien werden nicht angefasst (OTRcutactiv=on → kein Aufruf).
synotr_otr2_filter_uncut() {
    synotr_otr2_audio_want
    if [ "$OTRcutactiv" = "on" ]; then
        return 0
    fi
    if [ "$synotr_otr2_a_want" = "both" ]; then
        return 0
    fi
    if [ -z "${WORKDIR:-}" ] || [ ! -d "$WORKDIR" ]; then
        return 0
    fi

    _found=$(find "$WORKDIR" -maxdepth 1 \( -name "*.mp4" -o -name "*.MP4" \) -type f 2>/dev/null)
    if [ -z "$_found" ]; then
        unset _found
        return 0
    fi

    echo -e ; echo -e; echo "==> otr2-Tonspuren (ohne Schnitt):"
    _otr2n=0
    _filter_ifs=$IFS
    IFS=$'\012'
    # shellcheck disable=SC2044
    for _f in $(find "$WORKDIR" -maxdepth 1 \( -name "*.mp4" -o -name "*.MP4" \) -type f); do
        IFS=$_filter_ifs
        _bn=$(basename "$_f")
        case "$_bn" in
            *-cut.mp4|*-cut.MP4) continue ;;
        esac
        synotr_db_lookup_origin "$_bn" || true
        if [ "$synotr_file_source" != "otr2" ]; then
            continue
        fi
        _otr2n=$((_otr2n + 1))
        _probe=$("$ffprobe" -v quiet -print_format json -show_format -show_streams "$_f" 2>&1)
        _probe="{ ${_probe#*\{}"
        if ! synotr_otr2_audio_plan "$_probe"; then
            echo "    ${_bn}: keine Audiospur – übersprungen"
            continue
        fi
        if [ "$synotr_otr2_a_ident" = "1" ]; then
            echo "    ${_bn}: $synotr_otr2_a_note (unverändert)"
            continue
        fi
        echo "    ${_bn}:"
        _tmp="${WORKDIR%/}/tmp_synotr_otr2audio.mp4"
        rm -f "$_tmp"
        if synotr_otr2_ffmpeg_copy "$_f" "$_tmp"; then
            mv -f "$_tmp" "$_f"
        else
            rm -f "$_tmp"
            echo "    ${_bn}: Tonspur-Filter fehlgeschlagen – Original bleibt."
        fi
        IFS=$'\012'
    done
    IFS=$_filter_ifs
    if [ "$_otr2n" -eq 0 ]; then
        echo "    keine .otr2-MP4 im Arbeitsverzeichnis"
    fi
    unset _found _otr2n _filter_ifs _f _bn _probe _tmp
    return 0
}

synotr_otr2_cut() {
    IFS=${OLDIFS:-' '}
    rm -f "$outputfile"

    if [ "$SMARTRENDERING" = "on" ]; then
        if [ -z "${avcut_ffmpeg8:-}" ] || [ ! -f "$avcut_ffmpeg8" ]; then
            echo "    avcut 0.8 fehlt – Fallback Keyframe (ffmpeg+mp4mux)."
            SMARTRENDERING="off"
        fi
    fi

    if [ "$SMARTRENDERING" = "on" ]; then
        echo "> Übergebe die Cuts an avcut 0.8 (otr2, MKV)"
        _avcut_mkv="${tmp%/}/avcut_otr2.mkv"
        _avcut_log="${tmp%/}/avcut_otr2.log"
        rm -f "$_avcut_mkv"
        _avcut_rc=0
        # shellcheck disable=SC2086
        "$avcut_ffmpeg8" -p "${APPDIR}/includes/avcut_otr.profile" -i "$film" -o "$_avcut_mkv" $time > "$_avcut_log" 2>&1 || _avcut_rc=$?
        echo -e; echo -n "Die Schnittpunkte befinden sich"
        AVCUTPOINTS=$(grep "cutting points in" "$_avcut_log" 2>/dev/null | awk -F '"' '{print $3}' | sed -e 's/at: /an diesen Zeitmarken: \n    /g' | sed -e 's#s[)] #s\) \n    #g')
        echo -e "$AVCUTPOINTS"
        if [ "$LOGlevel" = "2" ]; then
            echo "avcut Command: $avcut_ffmpeg8 -i $film -o $_avcut_mkv $time (exit ${_avcut_rc})"
            echo "avcut LOG (letzte Zeilen):"
            tail -n 40 "$_avcut_log" 2>/dev/null
        fi
        if [ "$_avcut_rc" -ne 0 ]; then
            echo "    avcut Exit ${_avcut_rc} (z. B. Segmentation Fault) – MKV nur nutzen, wenn sie vollständig wirkt."
        fi
        if [ ! -f "$_avcut_mkv" ]; then
            echo "    avcut 0.8 hat keine MKV erzeugt – Fallback Keyframe."
            SMARTRENDERING="off"
        else
            echo "    avcut-MKV: $(basename "$_avcut_mkv")"
            if synotr_otr2_mkv_to_mp4 "$_avcut_mkv" "$outputfile"; then
                rm -f "$_avcut_mkv"
                unset _avcut_mkv _avcut_log _avcut_rc
                return 0
            fi
            echo "    MKV→MP4 fehlgeschlagen – Fallback Keyframe."
            SMARTRENDERING="off"
        fi
        unset _avcut_mkv _avcut_log _avcut_rc
    fi

    echo "> Übergebe die Cuts an mp4mux (ffmpeg-Demux, Bento4-Mux)"
    if ! synotr_ffmpeg_cut "$film" "$outputfile"; then
        echo "    ffmpeg+mp4mux-Schnitt fehlgeschlagen."
        return 1
    fi
    return 0
}
