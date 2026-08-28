#!/bin/sh
# Legt die Python-venv fuer den OTR-CLI-Decoder an (cryptography, mutagen, apprise).
# Aufruf: setup_decoder_venv.sh <UI-Ordner>
#   z.B. /var/packages/synOTR/target/ui
#
# Interpreter: Python >= 3.8, DSM-/usr/bin/python3 bevorzugen (kein festes Maximum).
# cryptography und mutagen kommen als Wheel (--only-binary=:all:), Version je
# nach Python (siehe requirements.txt). Kein Source-Build (Rust fehlt auf der NAS).

set -e

UI_DIR="${1:-}"
if [ -z "${UI_DIR}" ] || [ ! -d "${UI_DIR}" ]; then
    echo "setup_decoder_venv.sh: UI-Ordner fehlt oder ungültig: ${UI_DIR}" >&2
    exit 1
fi

DECODER_DIR="${UI_DIR}/app/decoder"
VENV_DIR="${UI_DIR}/app/venv"
REQ="${DECODER_DIR}/requirements.txt"
GETPIP="${DECODER_DIR}/get-pip.py"

fail_venv() {
    msg="$1"
    echo "${msg}" >&2
    if [ -n "${SYNOPKG_TEMP_LOGFILE}" ]; then
        echo "${msg}" > "${SYNOPKG_TEMP_LOGFILE}"
    fi
    exit 1
}

python_version() {
    "$1" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null
}

python_ok() {
    [ -x "$1" ] || return 1
    ver=$(python_version "$1") || return 1
    major=${ver%.*}
    minor=${ver#*.}
    [ "$major" = "3" ] && [ "$minor" -ge 8 ]
}

find_python() {
    for p in \
        /usr/bin/python3 \
        /usr/bin/python3.8 \
        /usr/bin/python3.9 \
        /usr/bin/python3.10 \
        /usr/bin/python3.11 \
        /usr/bin/python3.12 \
        /usr/bin/python3.13 \
        /usr/bin/python3.14 \
        /usr/bin/python3.15 \
        /usr/local/bin/python3 \
        /usr/local/bin/python3.8 \
        /usr/local/bin/python3.9 \
        /usr/local/bin/python3.10 \
        /usr/local/bin/python3.11 \
        /usr/local/bin/python3.12 \
        /usr/local/bin/python3.13 \
        /usr/local/bin/python3.14 \
        /usr/local/bin/python3.15 \
        /var/packages/Python3/target/usr/local/bin/python3 \
        /var/packages/Python3.9/target/usr/bin/python3.9
    do
        if python_ok "$p"; then
            echo "$p"
            return 0
        fi
    done
    return 1
}

bootstrap_pip() {
    if [ -x "${VENV_DIR}/bin/pip" ]; then
        return 0
    fi
    if "${VENV_DIR}/bin/python3" -m ensurepip --upgrade --default-pip >/dev/null 2>&1; then
        [ -x "${VENV_DIR}/bin/pip" ] && return 0
    fi

    getpip_use="${GETPIP}"
    pyver=$(python_version "${VENV_DIR}/bin/python3") || pyver="3.8"
    pyminor=${pyver#*.}
    if [ "${pyminor}" -ge 9 ]; then
        tmpgetpip="${VENV_DIR}/.get-pip.py"
        if wget -q -O "${tmpgetpip}" "https://bootstrap.pypa.io/get-pip.py" \
            || curl -fsSL -o "${tmpgetpip}" "https://bootstrap.pypa.io/get-pip.py"; then
            getpip_use="${tmpgetpip}"
        fi
    fi
    "${VENV_DIR}/bin/python3" "${getpip_use}" --no-warn-script-location
    rm -f "${VENV_DIR}/.get-pip.py"
    [ -x "${VENV_DIR}/bin/pip" ]
}

if [ ! -f "${DECODER_DIR}/otr_cli_decoder.py" ] || [ ! -f "${REQ}" ] || [ ! -f "${GETPIP}" ]; then
    fail_venv "OTR-Decoder-Dateien fehlen unter ${DECODER_DIR}."
fi

PY=$(find_python) || fail_venv "Kein Python >= 3.8 gefunden (DSM: /usr/bin/python3). cryptography muss als Wheel zu dieser Version passen."

echo "OTR-Decoder: verwende ${PY} ($("${PY}" -c 'import sys; print(".".join(map(str, sys.version_info[:3])))'))"

rm -rf "${VENV_DIR}"
if ! "${PY}" -m venv "${VENV_DIR}" 2>/dev/null || [ ! -x "${VENV_DIR}/bin/python3" ]; then
    rm -rf "${VENV_DIR}"
    if ! "${PY}" -m venv --without-pip "${VENV_DIR}"; then
        fail_venv "Konnte die Python-Umgebung nicht anlegen (python3 -m venv)."
    fi
fi

if ! bootstrap_pip; then
    rm -rf "${VENV_DIR}"
    fail_venv "pip konnte nicht in die Decoder-Umgebung installiert werden (Netzwerk / get-pip.py)."
fi

if ! "${VENV_DIR}/bin/pip" install --disable-pip-version-check --no-input --only-binary=:all: -r "${REQ}"; then
    rm -rf "${VENV_DIR}"
    fail_venv "requirements.txt konnte nicht als Wheel installiert werden (Internetzugang, x86_64/aarch64, Python >= 3.8)."
fi

if ! "${VENV_DIR}/bin/python3" -c "from cryptography.hazmat.primitives.ciphers.aead import AESGCM"; then
    rm -rf "${VENV_DIR}"
    fail_venv "cryptography ist installiert, lässt sich aber nicht importieren."
fi

if ! "${VENV_DIR}/bin/python3" -c "from mutagen.mp4 import MP4"; then
    rm -rf "${VENV_DIR}"
    fail_venv "mutagen ist installiert, lässt sich aber nicht importieren."
fi

if ! "${VENV_DIR}/bin/python3" -c "import apprise"; then
    rm -rf "${VENV_DIR}"
    fail_venv "apprise ist installiert, lässt sich aber nicht importieren."
fi

echo "OTR-Decoder-Umgebung bereit: ${VENV_DIR}"
chmod -R a+rX "${VENV_DIR}" "${DECODER_DIR}"
exit 0
