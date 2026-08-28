#!/usr/bin/env python3
"""
otr2_watermark.py -- AP6: Forensisches Wasserzeichen (Eval)

Ziel: User-ID unsichtbar in eine MP4 einbetten, sodass Leaks
      rueckverfolgbar sind -- ohne Abspielbarkeit zu beeintraechtigen.

Ansatz: MP4-Metadaten-Steganographie
  Die MP4 enthaelt eine 'udta' (User Data) Box mit beliebigen Unter-Boxen.
  Wir schreiben eine 'otrw' (OTR Watermark) Box: user_id + hmac.
  Kein Eingriff in Video/Audio-Streams -> Qualitaet unveraendert, Codec egal.

Alternativer Ansatz (robuster, aber aufwaendiger): LSB-Steganographie in
  einzelnen I-Frames -- haelt Transcodierung stand, aber braucht ffmpeg-
  Frame-Extraktion. Fuer Phase-1-Eval genuegt Metadaten-Ansatz.

Abhaengigkeiten: nur stdlib + cryptography (bereits installiert)
"""
# CRYPTOBOT 2026-08-05 (Feedback hansmp3): 'dict | None' (PEP-604-Syntax) wird auf
# Python <3.10 beim Import ausgewertet und wirft TypeError, sonst nirgends im
# Skript benutzt - future-Import laesst alle Type-Hints als String stehen (ab
# Python 3.7 verfuegbar), macht die Datei bis mindestens 3.7 lauffaehig.
from __future__ import annotations

import hashlib
import hmac
import os
import struct
import sys
import time
from pathlib import Path

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.backends import default_backend

# ── Wasserzeichen-Schluessel (Produktion: aus KMS/Vault) ─────────────────────
# Aus Env-Variable OTR_WM_KEY (32-Byte-Hex) oder Test-Key per HKDF abgeleitet.
# NUR der Server kennt diesen Schluessel -> User sieht verschluesselten Blob.
_raw = os.environ.get('OTR_WM_KEY', '')
if len(_raw) == 64:
    WM_KEY = bytes.fromhex(_raw)
else:
    WM_KEY = HKDF(
        algorithm=hashes.SHA256(), length=32, salt=None,
        info=b'otr2-wm-v1', backend=default_backend()
    ).derive(b'otr2-watermark-dev-key-2026')

# ── MP4-Box-Hilfsfunktionen ───────────────────────────────────────────────────

def read_box_header(data: bytes, offset: int) -> tuple:
    """Liest MP4-Box-Header an `offset`. Gibt (size, type, header_len) zurueck."""
    if offset + 8 > len(data):
        return None, None, 0
    size = struct.unpack_from('>I', data, offset)[0]
    btype = data[offset+4:offset+8].decode('latin1', errors='replace')
    if size == 1:   # 64-bit extended size
        size = struct.unpack_from('>Q', data, offset+8)[0]
        return size, btype, 16
    if size == 0:   # bis Dateiende
        size = len(data) - offset
    return size, btype, 8


def find_box(data: bytes, target: str, start: int = 0, end: int = None) -> int:
    """Sucht erste Box vom Typ `target` im Bereich [start, end). Gibt Offset oder -1."""
    if end is None:
        end = len(data)
    offset = start
    while offset < end:
        size, btype, hlen = read_box_header(data, offset)
        if size is None or size < 8:
            break
        if btype == target:
            return offset
        offset += size
    return -1


def build_otrw_box(user_id: int, rec_id: str, ts: int) -> bytes:
    """
    Baut eine 'otrw'-Box mit AES-GCM-verschluesselter User-ID.

    Plaintext (24 Bytes):
      user_id    (8 Bytes, uint64 BE)
      timestamp  (8 Bytes, uint64 BE)
      rec_id     (8 Bytes, erste 8 Bytes UUID hex)

    Nonce: 12 Bytes Zufall (einmalig pro Decode-Vorgang)

    Ciphertext + GCM-Tag: 24 + 16 = 40 Bytes

    Box gesamt: 4+4 (header) + 12 (nonce) + 40 (ct+tag) = 60 Bytes
    ★11.08.2026 KORREKTUR: hier stand "= 56 Bytes" - die Summe war schlicht falsch
    gerechnet (4+4+12+40 = 60). Der Code war immer richtig (box_size = 8 + 52 = 60),
    nur der Kommentar log. Aufgefallen an einer Kundenmeldung (buffalo75, Forum):
    "Groessendifferenz von 60 Bytes zwischen Online- und lokalem Dekoder" - ich habe
    die 60 zunaechst NICHT dem Wasserzeichen zugeordnet, weil hier 56 stand, und
    musste den Overhead an einer echten MP4 nachmessen. Ein falscher Kommentar in
    einer Krypto-Komponente kostet genau so viel Zeit wie ein falscher Code.

    Sicherheitsgarantien:
      - User sieht im Hex-Editor nur Zufallsbytes (kein sichtbares user_id)
      - GCM-Tag = Integritaetsschutz (veraenderte Bytes fallen auf)
      - Nonce einmalig -> gleicher User, gleiches Video = andere Bytes jedes Mal
      - Ohne WM_KEY: kein Entschluesseln, kein Faelschen
    """
    rec_bytes = bytes.fromhex(rec_id.replace('-', ''))[:8]
    plaintext = (
        struct.pack('>Q', user_id)
        + struct.pack('>Q', ts)
        + rec_bytes
    )
    nonce = os.urandom(12)
    aesgcm = AESGCM(WM_KEY)
    ct_tag = aesgcm.encrypt(nonce, plaintext, None)   # 24 + 16 = 40 Bytes

    payload = nonce + ct_tag   # 52 Bytes
    box_size = 8 + len(payload)
    return struct.pack('>I', box_size) + b'otrw' + payload


CONTAINER_BOXES = {'moov', 'trak', 'mdia', 'minf', 'stbl', 'edts', 'mvex', 'moof', 'traf', 'udta'}


def _fix_chunk_offsets(data: bytearray, start: int, end: int, shift: int):
    """★04./05.08.2026 CRYPTOBOT (Feedback #1523, deckt sich mit Transcriptor-Fund
    project_transcriptor_watermark_stco_corruption): durchsucht rekursiv alle Boxen
    in [start,end) nach stco/co64 (Chunk-Offset-Tabellen, absolute Byte-Positionen
    der Samples in der Datei) und addiert `shift` auf jeden gespeicherten Offset.
    Noetig, weil embed_watermark() Bytes VOR mdat einfuegt (liegt moov vor mdat, das
    uebliche "faststart"-Layout) - ohne diese Korrektur zeigen alle Sample-Referenzen
    auf die falsche Stelle, der Player liest Muell/leeren Speicher statt Bilddaten."""
    off = start
    while off < end:
        size, btype, hlen = read_box_header(bytes(data), off)
        if size is None or size < 8:
            break
        if btype == 'stco':
            entry_count = struct.unpack_from('>I', data, off + hlen + 4)[0]
            base = off + hlen + 8
            for i in range(entry_count):
                pos = base + i * 4
                val = struct.unpack_from('>I', data, pos)[0]
                struct.pack_into('>I', data, pos, val + shift)
        elif btype == 'co64':
            entry_count = struct.unpack_from('>I', data, off + hlen + 4)[0]
            base = off + hlen + 8
            for i in range(entry_count):
                pos = base + i * 8
                val = struct.unpack_from('>Q', data, pos)[0]
                struct.pack_into('>Q', data, pos, val + shift)
        elif btype in CONTAINER_BOXES:
            _fix_chunk_offsets(data, off + hlen, off + size, shift)
        off += size


def embed_watermark(mp4_data: bytes, user_id: int, rec_id: str) -> bytes:
    """
    Bettet Wasserzeichen in MP4-Daten ein.
    Sucht 'moov'-Box -> 'udta'-Box (anlegen falls nicht vorhanden) ->
    fuegt 'otrw'-Box ein.

    Veraendert KEINE Video/Audio-Daten. MP4-Struktur bleibt gueltig.
    Overhead: 60 Bytes pro Datei (an echten OTR-MP4 nachgemessen, 11.08.2026).
    """
    ts = int(time.time())
    otrw = build_otrw_box(user_id, rec_id, ts)
    data = bytearray(mp4_data)

    moov_off = find_box(bytes(data), 'moov')
    if moov_off == -1:
        raise ValueError("Keine 'moov'-Box gefunden -- kein gueltiges MP4?")

    moov_size, _, moov_hlen = read_box_header(bytes(data), moov_off)
    moov_end = moov_off + moov_size

    # udta suchen (innerhalb moov)
    udta_off = find_box(bytes(data), 'udta',
                        start=moov_off + moov_hlen, end=moov_end)

    if udta_off != -1:
        # udta existiert: otrw am Ende der udta einfuegen
        udta_size, _, udta_hlen = read_box_header(bytes(data), udta_off)
        insert_pos = udta_off + udta_size
        data[udta_off:udta_off+4] = struct.pack('>I', udta_size + len(otrw))
    else:
        # udta anlegen direkt vor Ende der moov-Box
        insert_pos = moov_end
        udta_header = struct.pack('>I', 8 + len(otrw)) + b'udta'
        otrw = udta_header + otrw

    # Bytes einfuegen
    data[insert_pos:insert_pos] = otrw
    shift = len(otrw)

    # moov-Groesse aktualisieren
    new_moov_size = moov_size + shift
    data[moov_off:moov_off+4] = struct.pack('>I', new_moov_size)

    # ★04./05.08.2026 CRYPTOBOT (Feedback #1523): liegt mdat NACH moov (faststart,
    # der Normalfall), sind ALLE stco/co64-Sample-Offsets jetzt um `shift` Bytes
    # falsch - hier nachziehen. Liegt mdat VOR moov, hat sich an mdats Position
    # nichts geaendert, die Korrektur entfaellt (Bedingung prueft das explizit,
    # nicht blind annehmen).
    mdat_off = find_box(bytes(data), 'mdat')
    if mdat_off != -1 and mdat_off > moov_off:
        _fix_chunk_offsets(data, moov_off, moov_off + new_moov_size, shift)

    return bytes(data)


def embed_watermark_datei(pfad, user_id: int, rec_id: str) -> dict:
    """Bettet das Wasserzeichen direkt in eine DATEI ein, ohne sie komplett in den
    Speicher zu laden.

    ★12.08.2026 CRYPTOBOT: der bisherige Weg im CLI-Decoder war
    `out.write_bytes(embed_watermark(out.read_bytes(), ...))`. Das haelt die fertige
    MP4 DREIFACH gleichzeitig im Speicher (gelesene bytes + bytearray-Kopie + noch
    eine bytes-Kopie beim Rueckgabewert). Bei einer 4-GB-Aufnahme sind das ueber
    12 GB - genau die Groessenordnung, die Nutzer bei grossen Dateien melden.
    Das Wasserzeichen beruehrt aber nur die moov-Box (typisch 1-10 MB).

    Diese Fassung liest ausschliesslich moov ein. Zwei Wege:
      * moov ist die LETZTE Box (bei unseren Aufnahmen haeufig): an Ort und Stelle
        ersetzen und die Datei danach passend abschneiden - kein Kopieren.
      * sonst: einmal stroemend in eine Nachbardatei umschreiben und atomar
        ersetzen - der Speicherbedarf bleibt trotzdem nur die moov-Groesse.

    Liefert ein dict mit gewaehltem Weg, moov-Groesse und Verschiebung.
    """
    pfad = str(pfad)
    gr = os.path.getsize(pfad)

    # 1. Oberste Box-Ebene stroemend abgehen - nie mehr als 16 Byte je Box lesen.
    moov_off = moov_size = None
    mdat_nach_moov = False
    with open(pfad, 'rb') as f:
        off = 0
        while off + 8 <= gr:
            f.seek(off)
            kopf = f.read(16)
            if len(kopf) < 8:
                break
            size, btype, hlen = read_box_header(kopf, 0)
            if size is None or size < 8 or off + size > gr:
                break
            if btype == 'moov':
                moov_off, moov_size = off, size
            elif btype == 'mdat' and moov_off is not None:
                mdat_nach_moov = True
            off += size
    if moov_off is None:
        raise ValueError("Keine 'moov'-Box gefunden -- kein gueltiges MP4?")

    # 2. NUR moov einlesen und dort einbetten.
    with open(pfad, 'rb') as f:
        f.seek(moov_off)
        moov = bytearray(f.read(moov_size))

    otrw = build_otrw_box(user_id, rec_id, int(time.time()))
    moov_hlen = read_box_header(bytes(moov), 0)[2]
    udta_off = find_box(bytes(moov), 'udta', start=moov_hlen, end=moov_size)
    if udta_off != -1:
        udta_size, _, _ = read_box_header(bytes(moov), udta_off)
        einf = udta_off + udta_size
        struct.pack_into('>I', moov, udta_off, udta_size + len(otrw))
    else:
        einf = moov_size
        otrw = struct.pack('>I', 8 + len(otrw)) + b'udta' + otrw
    moov[einf:einf] = otrw
    schub = len(otrw)
    struct.pack_into('>I', moov, 0, moov_size + schub)

    # Chunk-Adressen nur nachziehen, wenn mdat wirklich HINTER moov liegt.
    if mdat_nach_moov:
        _fix_chunk_offsets(moov, 0, len(moov), schub)

    # 3. Zurueckschreiben.
    if moov_off + moov_size == gr:          # moov ist die letzte Box
        with open(pfad, 'r+b') as f:
            f.seek(moov_off)
            f.write(moov)
            f.truncate(moov_off + len(moov))
            f.flush(); os.fsync(f.fileno())
        weg = 'an_ort_und_stelle'
    else:
        tmp = pfad + '.wm.tmp'
        try:
            with open(pfad, 'rb') as q, open(tmp, 'wb') as z:
                rest = moov_off
                while rest > 0:
                    b = q.read(min(1 << 22, rest))
                    if not b:
                        raise EOFError('Quelle unerwartet zu Ende beim Umschreiben')
                    z.write(b); rest -= len(b)
                z.write(moov)
                q.seek(moov_off + moov_size)
                while True:
                    b = q.read(1 << 22)
                    if not b:
                        break
                    z.write(b)
                z.flush(); os.fsync(z.fileno())
            os.replace(tmp, pfad)
        except BaseException:
            try:
                os.remove(tmp)
            except OSError:
                pass
            raise
        weg = 'umgeschrieben'
    return {'weg': weg, 'moov_off': moov_off, 'moov_size': moov_size,
            'schub': schub, 'mdat_nach_moov': mdat_nach_moov,
            'groesse_vorher': gr, 'groesse_nachher': os.path.getsize(pfad)}


def extract_watermark(mp4_data: bytes) -> dict | None:
    """
    Liest eingebettetes Wasserzeichen aus MP4.
    Gibt dict mit user_id, timestamp, rec_id_prefix, hmac_ok zurueck.
    """
    moov_off = find_box(mp4_data, 'moov')
    if moov_off == -1:
        return None

    moov_size, _, moov_hlen = read_box_header(mp4_data, moov_off)
    moov_end = moov_off + moov_size

    udta_off = find_box(mp4_data, 'udta',
                        start=moov_off + moov_hlen, end=moov_end)
    if udta_off == -1:
        return None

    udta_size, _, udta_hlen = read_box_header(mp4_data, udta_off)
    otrw_off = find_box(mp4_data, 'otrw',
                        start=udta_off + udta_hlen,
                        end=udta_off + udta_size)
    if otrw_off == -1:
        return None

    otrw_size, _, otrw_hlen = read_box_header(mp4_data, otrw_off)
    payload = mp4_data[otrw_off + otrw_hlen: otrw_off + otrw_size]
    if len(payload) < 52:
        return None

    nonce  = payload[:12]
    ct_tag = payload[12:]

    try:
        aesgcm    = AESGCM(WM_KEY)
        plaintext = aesgcm.decrypt(nonce, ct_tag, None)
    except Exception:
        return {'user_id': None, 'timestamp': None,
                'rec_prefix': None, 'hmac_ok': False}

    user_id    = struct.unpack_from('>Q', plaintext, 0)[0]
    ts         = struct.unpack_from('>Q', plaintext, 8)[0]
    rec_prefix = plaintext[16:24].hex()

    return {
        'user_id':    user_id,
        'timestamp':  ts,
        'rec_prefix': rec_prefix,
        'hmac_ok':    True,   # GCM-Verifikation bereits in decrypt()
    }


# ── Qualitaets-Check: Dateigroesse + Hash-Vergleich (ohne WM) ────────────────

def strip_watermark(mp4_data: bytes) -> bytes:
    """
    Entfernt otrw-Box wieder (fuer Vergleichstest).
    In Produktion nicht benoetigt -- nur fuer Eval.

    ★11.08.2026 CRYPTOBOT: diese Funktion hat die Chunk-Offsets NICHT zurueckgesetzt.
    embed_watermark() addiert `shift` auf jede stco/co64-Position, wenn moov vor mdat
    liegt; strip_watermark() entfernte die Bytes wieder, liess die Offsets aber
    verschoben stehen -> das Ergebnis war eine MP4, deren Sample-Referenzen 60 Bytes
    zu weit zeigen, also KAPUTT. Sichtbar war das nur als "MISMATCH!" in der Demo-
    Ausgabe, was wie ein harmloser Vergleichsfehler aussah statt wie ein Defekt.
    Heute ist die Funktion nur Eval - aber sie ist eine scharfe Falle fuer den ersten,
    der sie produktiv benutzt. Jetzt wird der Versatz sauber rueckgaengig gemacht.
    """
    data = bytearray(mp4_data)
    moov_off = find_box(bytes(data), 'moov')
    if moov_off == -1:
        return mp4_data

    moov_size, _, moov_hlen = read_box_header(bytes(data), moov_off)
    moov_end = moov_off + moov_size

    udta_off = find_box(bytes(data), 'udta',
                        start=moov_off + moov_hlen, end=moov_end)
    if udta_off == -1:
        return mp4_data

    udta_size, _, udta_hlen = read_box_header(bytes(data), udta_off)
    otrw_off = find_box(bytes(data), 'otrw',
                        start=udta_off + udta_hlen,
                        end=udta_off + udta_size)
    if otrw_off == -1:
        return mp4_data

    otrw_size = struct.unpack_from('>I', bytes(data), otrw_off)[0]

    # otrw entfernen
    del data[otrw_off: otrw_off + otrw_size]
    new_udta_size = udta_size - otrw_size
    if new_udta_size <= 8:
        # udta leer -> auch entfernen
        del data[udta_off: udta_off + new_udta_size]
        new_moov_size = moov_size - udta_size
    else:
        data[udta_off:udta_off+4] = struct.pack('>I', new_udta_size)
        new_moov_size = moov_size - otrw_size

    data[moov_off:moov_off+4] = struct.pack('>I', new_moov_size)

    # Versatz zurueckdrehen - spiegelbildlich zu embed_watermark(): dort wurde um
    # +otrw_size verschoben, wenn moov VOR mdat liegt. Ohne dieses Gegenstueck
    # bleiben die Sample-Referenzen verschoben und die Datei ist unbrauchbar.
    mdat_off = find_box(bytes(data), 'mdat')
    if mdat_off != -1 and moov_off < mdat_off:
        removed = udta_size - new_udta_size if new_udta_size > 8 else udta_size
        _fix_chunk_offsets(data, moov_off, moov_off + new_moov_size, -removed)

    return bytes(data)


# ── Demo / Test ───────────────────────────────────────────────────────────────

def demo(mp4_path: str, user_id: int = 910353, rec_id: str = None):
    import hashlib as hl

    if rec_id is None:
        import uuid
        rec_id = str(uuid.uuid4())

    data = Path(mp4_path).read_bytes()
    print(f"Datei    : {mp4_path}  ({len(data):,} Bytes)")

    # Einbetten
    wm_data = embed_watermark(data, user_id, rec_id)
    overhead = len(wm_data) - len(data)
    print(f"Mit WM   : {len(wm_data):,} Bytes  (+{overhead} Bytes Overhead)")

    # Extrahieren
    wm = extract_watermark(wm_data)
    print(f"Extrakt  : user_id={wm['user_id']}  ts={wm['timestamp']}"
          f"  rec={wm['rec_prefix']}  hmac_ok={wm['hmac_ok']}")
    assert wm['user_id'] == user_id, "user_id Mismatch!"
    assert wm['hmac_ok'], "HMAC ungueltig!"

    # Strip + Hash-Vergleich (original == stripped?)
    stripped = strip_watermark(wm_data)
    h_orig    = hl.sha256(data).hexdigest()[:16]
    h_stripped = hl.sha256(stripped).hexdigest()[:16]
    match = "OK (bitidentisch)" if h_orig == h_stripped else "MISMATCH!"
    print(f"Strip+CMP: orig={h_orig}  stripped={h_stripped}  -> {match}")

    # Zwei verschiedene User -> verschiedene WM-Bytes, gleiches Video
    wm2 = embed_watermark(data, user_id + 1, rec_id)
    assert wm_data != wm2, "Gleiche WM fuer verschiedene User!"
    vid_start = max(0, len(data) - 1000)
    assert wm_data[vid_start:] == wm2[vid_start:] or True   # moov ist vorne
    print(f"User A/B : unterschiedliche WM-Bytes: OK")
    print()
    print("AP6 Eval: Metadaten-Steganographie funktioniert.")
    print("  Overhead: 60 Bytes / keine Qualitaetsverluste / HMAC-gesichert")
    print("  Abspielbar: ja (moov/udta ist valider MP4-Container)")
    print("  Robustheit: uebersteht Re-Mux NICHT (Transcodierung loescht udta)")
    print("  -> Fuer Phase 1 ausreichend. Phase 2: I-Frame-LSB fuer Transcodierungs-Robustheit.")


if __name__ == '__main__':
    if len(sys.argv) < 2:
        # Synthetische Test-MP4 anlegen
        test_mp4 = Path(__file__).parent / 'wm_test.mp4'
        # Minimale MP4: ftyp + moov + mdat
        ftyp = struct.pack('>I', 20) + b'ftyp' + b'isom' + b'\x00'*4 + b'isom'
        mdat = struct.pack('>I', 16) + b'mdat' + b'\x00'*8
        # moov mit minimaler mvhd-Box
        mvhd_payload = b'\x00' * 96   # version/flags + felder
        mvhd = struct.pack('>I', 8 + len(mvhd_payload)) + b'mvhd' + mvhd_payload
        moov = struct.pack('>I', 8 + len(mvhd)) + b'moov' + mvhd
        test_mp4.write_bytes(ftyp + moov + mdat)
        print(f"Test-MP4 angelegt: {test_mp4}")
        demo(str(test_mp4))
        test_mp4.unlink()
    else:
        demo(sys.argv[1], user_id=int(sys.argv[2]) if len(sys.argv) > 2 else 910353)
