# shellcheck shell=sh
# shellcheck disable=SC2154,SC2034
# Herkunft der decodierten Datei (otrkey / otr2) in SQLite.
# Cutlist und Rename dürfen nicht über LIKE '${name%.*}%' die Pipeline wählen:
# WaitOfCutlist lässt Dateien in DECODIR liegen, HQ-cut ändert den Namen.

synotr_sql_escape() {
    printf '%s' "$1" | sed "s/'/''/g"
}

# Alter mitgelieferter TVDB-Default. Nur zum Erkennen/Entfernen, nie zum Login.
synotr_tvdb_bundled_default() {
    echo "6P0N9Q9NORS401P7" | tr 'A-Za-z' 'N-ZA-Mn-za-m'
}

synotr_tvdb_is_bundled_default() {
    [ -n "$1" ] && [ "$1" = "$(synotr_tvdb_bundled_default)" ]
}

# synotr_tvdb_purge_bundled_default
# Entfernt nur den alten Paket-Default aus der DB. User-Keys bleiben.
synotr_tvdb_purge_bundled_default() {
    [ -f "${APPDIR}/app/etc/synOTR.sqlite" ] || return 0
    _stored=$(sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "SELECT COALESCE(APIKEY,'') FROM tvdb WHERE rowid=1" 2>/dev/null)
    if synotr_tvdb_is_bundled_default "$_stored"; then
        sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "UPDATE tvdb SET APIKEY='', TOKEN='', day_created=$((today-1)), timestamp=(datetime('now','localtime')) WHERE rowid=1"
    fi
    unset _stored
}

synotr_db_clear_origin() {
    synotr_file_source=""
    synotr_file_encrypted=""
    synotr_file_original=""
    synotr_db_rowid=""
    synotr_db_otrtitle=""
    synotr_db_serie_season=""
    synotr_db_serie_episode=""
    synotr_file_orig_size=""
    synotr_cutlist_online=""
    synotr_file_editor_mp4=""
}

# _synotr_db_fill_from_row ROW (tab-separated)
_synotr_db_fill_from_row() {
    _row="$1"
    [ -n "$_row" ] || return 1
    synotr_db_rowid=$(printf '%s' "$_row" | awk -F'\t' '{print $1}')
    synotr_file_original=$(printf '%s' "$_row" | awk -F'\t' '{print $2}')
    synotr_file_source=$(printf '%s' "$_row" | awk -F'\t' '{print $3}')
    synotr_file_encrypted=$(printf '%s' "$_row" | awk -F'\t' '{print $4}')
    synotr_db_otrtitle=$(printf '%s' "$_row" | awk -F'\t' '{print $5}')
    synotr_db_serie_season=$(printf '%s' "$_row" | awk -F'\t' '{print $6}')
    synotr_db_serie_episode=$(printf '%s' "$_row" | awk -F'\t' '{print $7}')
    synotr_file_orig_size=$(printf '%s' "$_row" | awk -F'\t' '{print $8}')
    synotr_cutlist_online=$(printf '%s' "$_row" | awk -F'\t' '{print $9}')
    synotr_file_editor_mp4=$(printf '%s' "$_row" | awk -F'\t' '{print $10}')
    if [ -z "$synotr_file_source" ]; then
        case "$synotr_file_original" in
            *.avi|*.AVI) synotr_file_source="otrkey" ;;
            *.mp4|*.MP4) synotr_file_source="otr2" ;;
        esac
    fi
    return 0
}

_synotr_db_select_col() {
    _val="$1"
    _col="$2"
    _esc=$(synotr_sql_escape "$_val")
    _sql="SELECT rowid, file_original, COALESCE(file_source,''), COALESCE(file_encrypted,''), COALESCE(OTRtitle,''), COALESCE(serie_season,''), COALESCE(serie_episode,''), COALESCE(file_orig_size,''), COALESCE(cutlist_online,''), COALESCE(file_editor_mp4,'') FROM raw WHERE ${_col}='${_esc}' ORDER BY rowid DESC LIMIT 1"
    _row=$(sqlite3 -separator "$(printf '\t')" "${APPDIR}/app/etc/synOTR.sqlite" "$_sql" 2>/dev/null)
    if [ -n "$_row" ]; then
        _synotr_db_fill_from_row "$_row"
        return 0
    fi
    return 1
}

# synotr_db_lookup_origin BASENAME
# Nur exakter Name bzw. file_encrypted. Kein Wechsel AVI↔MP4 (sonst erbt
# ein liegengebliebenes .avi die otr2-Zeile von ….HQ.mp4).
synotr_db_lookup_origin() {
    synotr_db_clear_origin
    _q="$1"
    if [ -z "$_q" ] || [ ! -f "${APPDIR}/app/etc/synOTR.sqlite" ]; then
        return 1
    fi

    if _synotr_db_select_col "$_q" "file_original"; then
        return 0
    fi
    if _synotr_db_select_col "$_q" "file_encrypted"; then
        return 0
    fi

    _stem=${_q%.*}
    case "$_q" in
        *.avi|*.AVI)
            for _try in "${_q}.otrkey" "${_stem}.avi.otrkey" "${_stem}.otrkey"; do
                if _synotr_db_select_col "$_try" "file_encrypted"; then
                    return 0
                fi
            done
            ;;
        *.mp4|*.MP4)
            for _try in "${_q}.otr2" "${_stem}.mp4.otr2" "${_stem}.otr2"; do
                if _synotr_db_select_col "$_try" "file_encrypted"; then
                    return 0
                fi
            done
            ;;
        *)
            for _try in "${_q}.otrkey" "${_q}.otr2"; do
                if _synotr_db_select_col "$_try" "file_encrypted"; then
                    return 0
                fi
            done
            ;;
    esac
    # CutEditor/Umbenennung: Prefix own_ vor dem OTR-Dateinamen
    case "$_q" in
        own_*)
            _q_own="${_q#own_}"
            if [ -n "$_q_own" ] && synotr_db_lookup_origin "$_q_own"; then
                return 0
            fi
            synotr_db_clear_origin
            ;;
    esac
    return 1
}

# synotr_db_lookup_origin_cut BASENAME
# Cut-Ausgabe (Name.HQ-cut.mp4, Name.LQ-cut.mp4, Name-cut.mp4) auf file_original.
# Kein LIKE – nur rekonstruierte exakte Namen (otr2 und otrkey).
synotr_db_lookup_origin_cut() {
    _cut="$1"
    if [ -z "$_cut" ]; then
        synotr_db_clear_origin
        return 1
    fi
    if synotr_db_lookup_origin "$_cut"; then
        return 0
    fi

    case "$_cut" in
        *-cut.mp4|*-cut.mkv|*-cut.avi)
            _unstem="${_cut%-cut.mp4}"
            _unstem="${_unstem%-cut.mkv}"
            _unstem="${_unstem%-cut.avi}"
            # otr2 LQ bisher: Name.LQ.mp4-cut.mp4 → Name.LQ.mp4
            if synotr_db_lookup_origin "$_unstem"; then
                return 0
            fi
            if synotr_db_lookup_origin "${_unstem}.mp4"; then
                return 0
            fi
            if synotr_db_lookup_origin "${_unstem}.avi"; then
                return 0
            fi
            case "$_unstem" in
                *.HQ)
                    _base="${_unstem%.HQ}"
                    synotr_db_lookup_origin "${_base}.HQ.mp4" && return 0
                    synotr_db_lookup_origin "${_base}.mpg.HQ.avi" && return 0
                    synotr_db_lookup_origin "${_base}.mpg.HQ.mp4" && return 0
                    ;;
                *.HD)
                    _base="${_unstem%.HD}"
                    synotr_db_lookup_origin "${_base}.HD.mp4" && return 0
                    synotr_db_lookup_origin "${_base}.mpg.HD.avi" && return 0
                    synotr_db_lookup_origin "${_base}.mpg.HD.mp4" && return 0
                    ;;
                *.LQ)
                    _base="${_unstem%.LQ}"
                    synotr_db_lookup_origin "${_unstem}.mp4" && return 0
                    synotr_db_lookup_origin "${_base}.LQ.mp4" && return 0
                    synotr_db_lookup_origin "${_base}.mpg.mp4" && return 0
                    ;;
                *)
                    synotr_db_lookup_origin "${_unstem}.mpg.avi" && return 0
                    synotr_db_lookup_origin "${_unstem}.mpg.mp4" && return 0
                    ;;
            esac
            ;;
    esac
    synotr_db_clear_origin
    return 1
}

# Ohne DB-Zeile: Endung. .avi immer otrkey. .mp4 = otr2-Pipeline
# (natives .otr2 oder ältere Datei/eigene Cutlist ohne file_source).
# Kein AVI↔MP4-Stammtausch in der DB – nur Laufzeit-Herkunft für den Schnitt.
synotr_db_infer_origin_from_name() {
    _n="$1"
    case "$_n" in
        *.avi|*.AVI)
            synotr_file_source="otrkey"
            return 0
            ;;
        *.mp4|*.MP4)
            synotr_file_source="otr2"
            return 0
            ;;
        *)
            synotr_file_source=""
            return 1
            ;;
    esac
}

# Editor-MP4: DECODIR/STEM.mp4 (nach Remux; AVI im Papierkorb). Fallback _cuteditor/.
synotr_resolve_editor_sidecar() {
    _fn="$1"
    case "$_fn" in
        *.avi|*.AVI) ;;
        *) return 1 ;;
    esac
    if [ -n "${synotr_file_editor_mp4:-}" ] && [ -f "$synotr_file_editor_mp4" ]; then
        return 0
    fi
    _st=${_fn%.*}
    _try="${DECODIR%/}/${_st}.mp4"
    if [ -n "$DECODIR" ] && [ -f "$_try" ]; then
        synotr_file_editor_mp4="$_try"
        unset _fn _st _try
        return 0
    fi
    _try="${DECODIR%/}/_cuteditor/${_st}.mp4"
    if [ -n "$DECODIR" ] && [ -f "$_try" ]; then
        synotr_file_editor_mp4="$_try"
        unset _fn _st _try
        return 0
    fi
    synotr_file_editor_mp4=""
    unset _fn _st _try
    return 1
}

synotr_db_set_cutlist_online() {
    _st="$1"
    case "$_st" in
        none|found|unset) ;;
        *) unset _st; return 1 ;;
    esac
    if [ -z "${synotr_db_rowid:-}" ]; then
        unset _st
        return 1
    fi
    sqlite3 "${APPDIR}/app/etc/synOTR.sqlite" "UPDATE raw SET cutlist_online='${_st}' WHERE rowid='${synotr_db_rowid}'" 2>/dev/null || true
    synotr_cutlist_online="$_st"
    unset _st
    return 0
}

synotr_cut_archive_source() {
    _src="$1"
    if [ -n "$_src" ] && [ -f "$_src" ]; then
        if [ "$endgueltigloeschen" = "on" ]; then
            rm -f "$_src"
        else
            mv "$_src" "$OTRkeydeldir"
        fi
    fi
    if [ -n "$LOCAL_CUTLIST" ] && [ -f "$LOCAL_CUTLIST" ]; then
        if [ "$endgueltigloeschen" = "on" ]; then
            rm -f "$LOCAL_CUTLIST"
        else
            mv "$LOCAL_CUTLIST" "$OTRkeydeldir"
        fi
    fi
}
