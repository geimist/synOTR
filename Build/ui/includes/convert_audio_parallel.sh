#!/bin/bash
# convert_audio_parallel IN OUT "ffmpeg-opts"
# Beispiel: convert_audio_parallel "audio.mp3" "final.m4a" "-c:a aac -b:a 128k"
#
# Kodiert die Audiodatei in bis zu CONVERT_AUDIO_MAX_JOBS parallelen Jobs
# (höchstens nproc-1, Segment mind. CONVERT_AUDIO_MIN_SEGMENT_SEC Sekunden)
# und fügt die AAC-Segmente zusammen.
# Nutzt $ffmpeg / $ffprobe falls gesetzt und ausführbar, sonst Resolve (8 → 7 → 6).
#
# ToDo: an Stille nach Segmentlänge teilen, um Knackser an den Nähten zu vermeiden
#       (nächstes Segment muss innerhalb der Gesamtlänge bleiben).

CONVERT_AUDIO_MAX_JOBS="${CONVERT_AUDIO_MAX_JOBS:-4}"
CONVERT_AUDIO_MIN_SEGMENT_SEC="${CONVERT_AUDIO_MIN_SEGMENT_SEC:-90}"
CONVERT_AUDIO_MIN_FILE_BYTES="${CONVERT_AUDIO_MIN_FILE_BYTES:-4096}"

#########################################################################
# resolve_media_tool NAME [SCRIPT_DIR]                                  #
#   Preferiert: name8 → name7 → name6 → name (Pfad, PATH, Script-Dir)  #
#########################################################################
resolve_media_tool() {
    local name="$1"
    local script_dir="${2:-}"
    local cand found suffix
    local -a candidates=()

    candidates+=(
        "/usr/local/bin/${name}8"
        "/usr/local/bin/${name}7"
        "/usr/local/bin/${name}6"
        "/usr/local/bin/${name}"
    )

    for suffix in 8 7 6 ""; do
        found=$(command -v "${name}${suffix}" 2>/dev/null) || true
        [[ -n "$found" ]] && candidates+=("$found")
    done

    if [[ -n "$script_dir" ]]; then
        candidates+=(
            "${script_dir}/${name}8"
            "${script_dir}/${name}7"
            "${script_dir}/${name}6"
            "${script_dir}/${name}"
        )
    fi

    for cand in "${candidates[@]}"; do
        if [[ -n "$cand" && -x "$cand" ]]; then
            printf '%s\n' "$cand"
            return 0
        fi
    done
    return 1
}

_file_big_enough() {
    local f="$1"
    local min="${2:-$CONVERT_AUDIO_MIN_FILE_BYTES}"
    local sz
    [[ -f "$f" ]] || return 1
    sz=$(wc -c < "$f")
    sz=${sz//[[:space:]]/}
    [[ "$sz" =~ ^[0-9]+$ ]] || return 1
    (( sz >= min ))
}

_probe_duration() {
    local bin="$1"
    local f="$2"
    "$bin" -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$f" 2>/dev/null
}

_duration_ok() {
    local val="$1"
    [[ "$val" =~ ^[0-9]+([.][0-9]+)?$ ]] && awk -v d="$val" 'BEGIN { exit !(d > 0) }'
}

_duration_close() {
    local expected="$1"
    local actual="$2"
    local tol="$3"
    awk -v a="$expected" -v b="$actual" -v t="$tol" 'BEGIN {
        d = a - b
        if (d < 0) d = -d
        exit !(d <= t)
    }'
}

# Global, damit EXIT/INT den Ordner auch nach return aus der Funktion löschen.
CONVERT_AUDIO_TMP=""
CONVERT_AUDIO_PIDS=()

convert_audio_cleanup() {
    local d pid
    for pid in "${CONVERT_AUDIO_PIDS[@]}"; do
        [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
    done
    wait 2>/dev/null || true
    CONVERT_AUDIO_PIDS=()

    d="${CONVERT_AUDIO_TMP:-}"
    CONVERT_AUDIO_TMP=""
    unset TMPDIR

    [[ -n "$d" && -e "$d" ]] || return 0

    # kurz warten, falls ffmpeg Handles noch nicht frei hat
    sleep 0.2 2>/dev/null || true
    chmod -R u+w "$d" 2>/dev/null || true
    /bin/rm -rf -- "$d" 2>/dev/null || rm -rf -- "$d" 2>/dev/null || true

    if [[ -e "$d" ]]; then
        find "$d" -mindepth 1 -delete 2>/dev/null || true
        rmdir "$d" 2>/dev/null || /bin/rm -rf -- "$d" 2>/dev/null || true
    fi

    if [[ -e "$d" ]]; then
        echo "Temp-Verzeichnis konnte nicht gelöscht werden: $d" >&2
        return 1
    fi
    return 0
}

#########################################################################
# convert_audio_parallel IN OUT "ffmpeg-opts"                           #
#########################################################################
convert_audio_parallel() {
    local input="$1"
    local output="$2"
    local ffmpeg_opts="$3"
    local out_ext="${output##*.}"
    local ffmpeg_bin ffprobe_bin
    local threads jobs max_jobs min_seg max_by_dur workdir duration segment_len
    local i start idx out_seg list fail rc=0
    local loglevel="${ffloglevel:-error}"
    local -a pids=()
    local -a enc_opts=()
    local out_dur tol

    if [[ -z "$input" || -z "$output" ]]; then
        echo "Nutzung: convert_audio_parallel IN OUT \"ffmpeg-opts\"" >&2
        return 1
    fi
    if [[ ! -f "$input" ]]; then
        echo "Eingabedatei nicht gefunden: $input" >&2
        return 1
    fi

    if [[ -n "${ffmpeg:-}" && -x "${ffmpeg}" ]]; then
        ffmpeg_bin="${ffmpeg}"
    else
        ffmpeg_bin=$(resolve_media_tool ffmpeg) || {
            echo "ffmpeg nicht gefunden (weder ffmpeg8/7/6 noch ffmpeg)" >&2
            return 1
        }
    fi

    if [[ -n "${ffprobe:-}" && -x "${ffprobe}" ]]; then
        ffprobe_bin="${ffprobe}"
    else
        ffprobe_bin=$(resolve_media_tool ffprobe) || {
            echo "ffprobe nicht gefunden (weder ffprobe8/7/6 noch ffprobe)" >&2
            return 1
        }
    fi

    max_jobs="${CONVERT_AUDIO_MAX_JOBS}"
    min_seg="${CONVERT_AUDIO_MIN_SEGMENT_SEC}"
    [[ "$max_jobs" =~ ^[1-9][0-9]*$ ]] || max_jobs=4
    [[ "$min_seg" =~ ^[1-9][0-9]*$ ]] || min_seg=90

    threads=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 2)
    [[ "$threads" =~ ^[1-9][0-9]*$ ]] || threads=2
    jobs=$((threads - 1))
    (( jobs > max_jobs )) && jobs=$max_jobs
    (( jobs < 1 )) && jobs=1

    read -r -a enc_opts <<< "$ffmpeg_opts"

    _convert_audio_single() {
        unset TMPDIR
        "$ffmpeg_bin" -hide_banner -loglevel "$loglevel" -y -threads 2 -i "$input" "${enc_opts[@]}" "$output"
        rc=$?
        if (( rc == 0 )) && _file_big_enough "$output"; then
            echo "Ausgabe gespeichert in: $output"
            return 0
        fi
        echo "Einzelkonvertierung fehlgeschlagen (rc=${rc})" >&2
        (( rc != 0 )) || rc=1
        return "$rc"
    }

    _fallback_single() {
        echo "$1 – Fallback auf einzelne Konvertierung..."
        convert_audio_cleanup
        _convert_audio_single
        return $?
    }

    # 1–2 Kerne: parallele Jobs wären nur Overhead.
    if (( jobs <= 1 )); then
        echo "Parallele Konvertierung übersprungen (nur 1 Job) – einzelne Konvertierung..."
        _convert_audio_single
        return $?
    fi

    echo "Analysiere Dauer von '$input'..."
    duration=$(_probe_duration "$ffprobe_bin" "$input") || true

    if ! _duration_ok "$duration"; then
        _fallback_single "ffprobe-Dauer ungültig ('${duration:-leer}')"
        return $?
    fi

    max_by_dur=$(awk -v d="$duration" -v m="$min_seg" 'BEGIN { print int(d / m) }')
    [[ "$max_by_dur" =~ ^[0-9]+$ ]] || max_by_dur=1
    (( max_by_dur < 1 )) && max_by_dur=1
    (( jobs > max_by_dur )) && jobs=$max_by_dur

    if (( jobs <= 1 )); then
        echo "Parallele Konvertierung übersprungen (Dauer ${duration}s, min. ${min_seg}s je Segment) – einzelne Konvertierung..."
        _convert_audio_single
        return $?
    fi

    if [[ -n "${WORKDIR:-}" && -d "$WORKDIR" ]]; then
        for d in "${WORKDIR%/}"/.audio_parallel.* "${WORKDIR%/}"/tmp_synotr_audio_parallel.*; do
            [[ -d "$d" ]] || continue
            echo "Entferne liegengebliebenes Temp-Verzeichnis: $d"
            chmod -R u+w "$d" 2>/dev/null || true
            /bin/rm -rf -- "$d" 2>/dev/null || rm -rf -- "$d" 2>/dev/null || true
        done
        workdir=$(mktemp -d "${WORKDIR%/}/tmp_synotr_audio_parallel.XXXXXX") || workdir=""
    else
        workdir=$(mktemp -d) || workdir=""
    fi
    if [[ -z "$workdir" || ! -d "$workdir" ]]; then
        _fallback_single "Temp-Verzeichnis nicht anlegbar"
        return $?
    fi
    CONVERT_AUDIO_TMP="$workdir"
    export TMPDIR="$workdir"

    segment_len=$(awk -v d="$duration" -v j="$jobs" 'BEGIN { print d / j }')
    echo "Kodiere in $jobs parallelen Jobs à ca. ${segment_len}s (Kerne: $threads, max. $max_jobs, min. ${min_seg}s/Segment)..."

    pids=()
    for ((i = 0; i < jobs; i++)); do
        start=$(awk -v i="$i" -v s="$segment_len" 'BEGIN { print i * s }')
        idx=$(printf '%03d' "$i")
        out_seg="$workdir/converted_segment_${idx}.${out_ext}"
        if (( i == jobs - 1 )); then
            "$ffmpeg_bin" -hide_banner -loglevel "$loglevel" -y -ss "$start" -i "$input" \
                -vn -threads 1 "${enc_opts[@]}" "$out_seg" &
        else
            "$ffmpeg_bin" -hide_banner -loglevel "$loglevel" -y -ss "$start" -t "$segment_len" -i "$input" \
                -vn -threads 1 "${enc_opts[@]}" "$out_seg" &
        fi
        pids+=($!)
        CONVERT_AUDIO_PIDS+=($!)
    done

    fail=0
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            fail=1
        fi
    done

    for ((i = 0; i < jobs; i++)); do
        idx=$(printf '%03d' "$i")
        out_seg="$workdir/converted_segment_${idx}.${out_ext}"
        if ! _file_big_enough "$out_seg"; then
            echo "Segment ${idx} fehlt oder ist zu klein." >&2
            fail=1
        fi
    done

    if (( fail )); then
        _fallback_single "Parallele Kodierung unvollständig"
        return $?
    fi

    echo "Füge konvertierte Teile zusammen..."
    list="$workdir/converted_list.txt"
    : > "$list"
    for ((i = 0; i < jobs; i++)); do
        idx=$(printf '%03d' "$i")
        out_seg="$workdir/converted_segment_${idx}.${out_ext}"
        printf "file '%s'\n" "$out_seg" >> "$list"
    done

    if [[ ! -s "$list" ]]; then
        _fallback_single "Concat-Liste leer"
        return $?
    fi

    "$ffmpeg_bin" -hide_banner -loglevel "$loglevel" -y -f concat -safe 0 -i "$list" -c copy "$output"
    rc=$?
    if (( rc != 0 )) || ! _file_big_enough "$output"; then
        _fallback_single "Zusammenfügen fehlgeschlagen (rc=${rc})"
        return $?
    fi

    out_dur=$(_probe_duration "$ffprobe_bin" "$output") || true
    # etwas Luft für MP3-Seek und AAC-Encoder-Delay je Naht
    tol=$(awk -v j="$jobs" 'BEGIN { print 2 + (j * 0.5) }')
    if ! _duration_ok "$out_dur" || ! _duration_close "$duration" "$out_dur" "$tol"; then
        echo "Ausgabedauer weicht ab (Quelle ${duration}s, Ausgabe ${out_dur:-leer}s, Toleranz ${tol}s)." >&2
        _fallback_single "Dauerprüfung nach Concat"
        return $?
    fi

    echo "Ausgabe gespeichert in: $output"
    convert_audio_cleanup
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    trap convert_audio_cleanup EXIT
    trap 'convert_audio_cleanup; trap - EXIT; exit 130' INT
    trap 'convert_audio_cleanup; trap - EXIT; exit 143' TERM
    trap 'convert_audio_cleanup; trap - EXIT; exit 129' HUP
    convert_audio_parallel "$@"
    _cap_rc=$?
    convert_audio_cleanup
    trap - EXIT INT TERM HUP
    exit "$_cap_rc"
fi
