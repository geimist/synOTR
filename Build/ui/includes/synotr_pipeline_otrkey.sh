# shellcheck shell=sh
# shellcheck disable=SC2154,SC2034,SC2086
# otrkey-Pipeline (4.3.1): AVI-Schnitt mit altem avcut bzw. avisplit, danach
# OTRavi2mp4 (ffmpeg-Demux + MP4Box). Nicht avcut 0.8, nicht mp4mux-avc3.
# Erwartet: film outputfile time SMARTRENDERING avcut_otrkey avisplit ffmpeg
#           ffprobe mp4box fps AudioDelayMs OTRaacqal normalizeAudio LOGlevel
#           ffloglevel mp4boxloglevel WORKDIR tmp OLDIFS APPDIR

# synotr_otrkey_avi2mp4 SRC [DST]
# Video-Copy + MP3→AAC, Mux per MP4Box -add -fps. Setzt synotr_mp4_path.
# _otrkey_avi2mp4_keep_src=1: Quelle nicht nach OTRkeydeldir verschieben.
synotr_otrkey_avi2mp4() {
    _src="$1"
    _dst="$2"
    synotr_mp4_path=""
    if [ -z "$_src" ] || [ ! -f "$_src" ]; then
        echo "synotr_otrkey_avi2mp4: Quelldatei fehlt."
        return 1
    fi
    _srcdir=$(dirname "$_src")
    _srcdir="${_srcdir%/}/"
    _base=$(basename "$_src")
    _stem=${_base%.*}
    if [ -z "$_dst" ]; then
        _dst="${_srcdir}${_stem}.mp4"
    fi
    if [ -z "${mp4box:-}" ] || [ ! -f "$mp4box" ]; then
        echo "    MP4Box fehlt – AVI bleibt unkonvertiert."
        return 1
    fi
    [ -x "$mp4box" ] || chmod +x "$mp4box" 2>/dev/null || true
    if [ ! -x "$mp4box" ]; then
        echo "    MP4Box nicht ausführbar."
        return 1
    fi

    _muxdir="${WORKDIR:-$_srcdir}"
    _muxdir="${_muxdir%/}/tmp_synotr_remux"
    rm -rf "$_muxdir"
    mkdir -p "$_muxdir" || return 1

    _probe=$("$ffprobe" -v quiet -print_format json -show_format -show_streams "$_src" 2>&1)
    _probe="{ ${_probe#*\{}"

    _audiocodec=$(echo "$_probe" | jq -r '[.streams[]? | select(.codec_type=="audio") | .codec_name] | .[0] // "null"')
    _vcodec=$(echo "$_probe" | jq -r '[.streams[]? | select(.codec_type=="video") | .codec_name] | .[0] // "null"')
    _vtag=$(echo "$_probe" | jq -r '[.streams[]? | select(.codec_type=="video") | .codec_tag_string] | .[0] // "null"' | tr '[:upper:]' '[:lower:]')
    echo "Audiocodec:               $_audiocodec"
    echo "Videocodec:               $_vcodec ($_vtag)"

    if [ "$_audiocodec" = "null" ]; then
        _ffinfo=$("$ffmpeg" -i "$_src" 2>&1)
        if echo "$_ffinfo" | grep -q "Audio: ac3"; then
            _audiocodec=ac3
        elif echo "$_ffinfo" | grep -q "Audio: mp3"; then
            _audiocodec=mp3
        elif echo "$_ffinfo" | grep -q "Audio: aac"; then
            _audiocodec=aac
        else
            echo "Audiocodec nicht erkannt"
            rm -rf "${_muxdir:?}"
            return 1
        fi
        echo "Audiocodec (ffmpeg):      $_audiocodec"
    fi

    _vext=""
    case "$_vcodec" in
        h264) _vext=h264 ;;
        mpeg4|msmpeg4v3)
            _vext=tmp.m4v
            ;;
        *)
            case "$_vtag" in
                h264|avc1) _vext=h264 ;;
                mpeg4|divx|dx50|xvid) _vext=tmp.m4v ;;
            esac
            ;;
    esac
    if [ -z "$_vext" ]; then
        echo "Videoformat nicht erkannt."
        rm -rf "${_muxdir:?}"
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
    echo "Framerate:                $_fps"

    _audiofile="${_muxdir}/a.${_audiocodec}"
    _videofile="${_muxdir}/v.${_vext}"
    _AUDIODEMUX=$("$ffmpeg" -hide_banner -loglevel "$ffloglevel" -y -i "$_src" -c:a copy -vn "$_audiofile" 2>&1)
    if [ "$LOGlevel" = "2" ]; then
        echo "ffmpeg-AudioDemux LOG:    $_AUDIODEMUX"
    fi
    if [ ! -f "$_audiofile" ]; then
        echo "Audiodemux fehlgeschlagen."
        rm -rf "${_muxdir:?}"
        return 1
    fi

    if [ "$_audiocodec" = "mp3" ]; then
        echo -e; echo " > Konvertiere Audiospur nach AAC:"
        if ! synotr_aac_encode_opts; then
            rm -rf "${_muxdir:?}"
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
            rm -rf "${_muxdir:?}"
            return 1
        fi
    fi

    echo -e; echo " > Video extrahieren (Copy):"
    _VIDEODEMUX=$("$ffmpeg" -hide_banner -loglevel "$ffloglevel" -y -i "$_src" -an -c:v copy "$_videofile" 2>&1)
    if [ "$LOGlevel" = "2" ]; then
        echo "ffmpeg-VideoDemux LOG:"
        echo "$_VIDEODEMUX"
    fi
    if [ ! -f "$_videofile" ]; then
        echo "Videodemux fehlgeschlagen."
        rm -rf "${_muxdir:?}"
        return 1
    fi

    echo -e; echo " > MP4Box Remux:"
    _delay_ms=${AudioDelayMs:-0}
    [ -z "$_delay_ms" ] && _delay_ms=0
    _vspec="$_videofile"
    _aspec="$_audiofile"
    if echo "$_delay_ms" | grep -q '^-'; then
        _vspec="${_videofile}#video:delay=${_delay_ms#-}"
        echo "Audio-Video-Sync:         Video wird um ${_delay_ms#-}ms verzögert"
    elif [ "$_delay_ms" != "0" ]; then
        _aspec="${_audiofile}#audio:delay=${_delay_ms}"
        echo "Audio-Video-Sync:         Audio wird um ${_delay_ms}ms verzögert"
    fi

    _tmpout="${_muxdir}/out.mp4"
    rm -f "$_tmpout" "$_dst"
    # shellcheck disable=SC2086
    _BOXLOG=$("$mp4box" $mp4boxloglevel -add "$_vspec" -add "$_aspec" -fps "$_fps" -tmp "$_muxdir" "$_tmpout" 2>&1) || true
    if [ "$LOGlevel" = "2" ]; then
        echo "MP4Box LOG: $_BOXLOG"
    fi
    _dstsz=0
    if [ -f "$_tmpout" ]; then
        _dstsz=$(wc -c < "$_tmpout" | tr -d ' ')
    fi
    if [ ! -f "$_tmpout" ] || [ -z "$_dstsz" ] || [ "$_dstsz" -lt 1048576 ]; then
        echo "FEHLER: Zieldatei nicht gefunden (${_dstsz:-0} Byte)."
        echo "$_BOXLOG"
        rm -rf "${_muxdir:?}"
        return 1
    fi
    mv -f "$_tmpout" "$_dst"
    rm -rf "${_muxdir:?}"

    if [ "${_otrkey_avi2mp4_keep_src:-0}" != "1" ]; then
        if [ "$endgueltigloeschen" = "on" ]; then
            rm -f "$_src"
        else
            mv "$_src" "$OTRkeydeldir"
        fi
    fi
    echo -n "    L==> "
    echo "$(basename "$_dst") wurde erstellt"
    synotr_mp4_path="$_dst"
    return 0
}

# Schnitt am Original-AVI. $time muss bereits im passenden Format stehen
# (avcut: Sekunden + Rest verwerfen; avisplit: hh:mm:ss oder Frames).
synotr_otrkey_cut() {
    IFS=${OLDIFS:-' '}
    _cut_avi="${outputfile%.*}.avi"
    rm -f "$outputfile" "$_cut_avi"

    if [ "$SMARTRENDERING" = "on" ]; then
        echo "> Übergebe die Cuts an avcut (4.3.1, AVI)"
        if [ -z "${avcut_otrkey:-}" ] || [ ! -f "$avcut_otrkey" ]; then
            echo "    altes avcut fehlt."
            return 1
        fi
        _avcut_log="${tmp%/}/avcut_otrkey.log"
        _avcut_rc=0
        # shellcheck disable=SC2086
        "$avcut_otrkey" -p "${APPDIR}/includes/avcut_otr.profile" -i "$film" -o "$_cut_avi" $time > "$_avcut_log" 2>&1 || _avcut_rc=$?
        echo -e; echo -n "Die Schnittpunkte befinden sich"
        AVCUTPOINTS=$(grep "cutting points in" "$_avcut_log" 2>/dev/null | awk -F '"' '{print $3}' | sed -e 's/at: /an diesen Zeitmarken: \n    /g' | sed -e 's#s[)] #s\) \n    #g')
        echo -e "$AVCUTPOINTS"
        if [ "$LOGlevel" = "2" ]; then
            echo "avcut Command: $avcut_otrkey -i $film -o $_cut_avi $time (exit ${_avcut_rc})"
            echo "avcut LOG (letzte Zeilen):"
            tail -n 40 "$_avcut_log" 2>/dev/null
        fi
        unset _avcut_log _avcut_rc
    else
        echo "> Übergebe die Cuts an avisplit/avimerge"
        if [ -z "${avisplit:-}" ] || [ ! -f "$avisplit" ]; then
            echo "    avisplit fehlt."
            return 1
        fi
        [ -x "$avisplit" ] || chmod +x "$avisplit" 2>/dev/null || true
        if [ -n "${avimerge:-}" ] && [ -f "$avimerge" ]; then
            [ -x "$avimerge" ] || chmod +x "$avimerge" 2>/dev/null || true
        fi
        _avisplit_log="${tmp%/}/avisplit.log"
        # avisplit schreibt je Frame eine CR-Zeile "[Datei] (Start-Aktuell)" –
        # ungefiltert mehrere zehn MB im LOG. Header (avilib, Zeitraum, Frames) bleibt.
        # shellcheck disable=SC2086
        "$avisplit" -i "$film" -o "$_cut_avi" -t $time -c 2>&1 | tr '\r' '\n' | awk '!/\] \([0-9][0-9]*-[0-9][0-9]*)/' > "$_avisplit_log"
        if [ "$LOGlevel" = "2" ]; then
            echo "avisplit Command: avisplit -i $film -o $_cut_avi -t $time -c"
            echo "avisplit-LOG:"
            cat "$_avisplit_log" 2>/dev/null
        fi
        unset _avisplit_log
    fi

    if [ ! -f "$_cut_avi" ]; then
        if [ "$SMARTRENDERING" = "on" ]; then
            echo "avcut muss einen Fehler verursacht haben."
        else
            echo "Avisplit oder avimerge muss einen Fehler verursacht haben."
        fi
        return 1
    fi
    echo "    Schnitt-AVI: $(basename "$_cut_avi")"
    echo "    AVI → MP4 (ffmpeg-Demux, MP4Box – OTRavi2mp4)"
    _otrkey_avi2mp4_keep_src=1
    if ! synotr_otrkey_avi2mp4 "$_cut_avi" "$outputfile"; then
        unset _otrkey_avi2mp4_keep_src
        echo "    MP4-Konvertierung fehlgeschlagen – Schnitt bleibt AVI."
        outputfile="$_cut_avi"
        return 1
    fi
    unset _otrkey_avi2mp4_keep_src
    rm -f "$_cut_avi"
    outputfile="$synotr_mp4_path"
    return 0
}
