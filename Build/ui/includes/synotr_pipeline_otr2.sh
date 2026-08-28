# shellcheck shell=sh
# shellcheck disable=SC2154,SC2034,SC2086
# otr2-Pipeline: natives MP4. Smartrendering = avcut 0.8 (ffmpeg8) → MKV, dann
# ffmpeg -c copy nach MP4 (Zeiten und alle Spuren aus der MKV). Nicht mp4mux:
# POC nach avcut-Spleiß ist unbrauchbar → composition delay 154 → Freeze.
# Keyframe = synotr_ffmpeg_cut (ffmpeg-Demux + mp4mux).
# Erwartet: film outputfile time keep_times SMARTRENDERING avcut_ffmpeg8
#           ffmpeg ffprobe APPDIR tmp WORKDIR LOGlevel ffloglevel OLDIFS

# avcut schreibt nur MKV zuverlässig (MP4-Muxer bricht ab). Zeiten nicht neu setzen.
synotr_otr2_mkv_to_mp4() {
    _src="$1"
    _dst="$2"
    if [ -z "$_src" ] || [ ! -f "$_src" ] || [ -z "$_dst" ]; then
        echo "synotr_otr2_mkv_to_mp4: Quelle oder Ziel fehlt."
        return 1
    fi

    echo "    avcut-MKV → MP4 (ffmpeg -c copy, alle Spuren, Zeiten aus MKV)"
    rm -f "$_dst"
    _COPYLOG=$("$ffmpeg" -hide_banner -loglevel "$ffloglevel" -y \
        -i "$_src" -map 0 -c copy -movflags +faststart "$_dst" 2>&1)
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
    if [ -f "$_dst" ] && [ -n "$_dstsz" ] && [ "$_dstsz" -gt 1048576 ]; then
        return 0
    fi
    echo "    ffmpeg-Copy fehlgeschlagen (${_dstsz:-0} Byte)."
    echo "$_COPYLOG"
    rm -f "$_dst"
    return 1
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
