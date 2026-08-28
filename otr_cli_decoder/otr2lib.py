"""
otr2lib — Gemeinsame Crypto-/Format-Kernfunktionen fuer OTR2.

Format-Spec: infra/crypto-agent/otr2_format.md
Kein produktiver Einsatz ohne GC-Freigabe.
"""

import hashlib
import json
import os
import struct
import time
from dataclasses import dataclass, asdict
from typing import Optional

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend

# ── Format-Konstanten ────────────────────────────────────────────────────────

MAGIC          = b'\x8fOTR2\x0d\x0a\x1a'   # 8 Bytes
VERSION_1_0    = 0x0001
PREAMBLE_SIZE  = 20                          # magic(8) + version(2) + flags(2) + hlen(4) + reserved(4)
BODY_ALIGNMENT = 64                          # Body-Start auf 64-Byte-Grenze
IO_CHUNK       = 4 * 1024 * 1024            # 4 MB I/O-Puffer

FLAG_HAS_MAC     = 0x0001                   # v1.1: Header-HMAC
FLAG_FW_READY    = 0x0002                   # Forensisches Wasserzeichen vorbereitet

SCHEME_AES256CTR = "AES-256-CTR"
MAX_BLOCK_COUNTER = 0xFFFFFFFF              # 32-bit Counter → max 64 GB pro Datei


# ── Header-Datenklasse ───────────────────────────────────────────────────────

@dataclass
class Otr2Header:
    scheme:       str   = SCHEME_AES256CTR
    rec:          str   = ""                 # Recording-UUID
    iv:           str   = ""                 # Nonce als Hex-String (12 Bytes = 24 Zeichen)
    size:         int   = 0                  # Plaintext-Groesse in Bytes
    broadcast_ts: int   = 0                  # Unix-Timestamp der Ausstrahlung
    content_type: str   = "video/mp4"
    created_ts:   int   = 0
    kek_id:       str   = "kek-2026-01"

    def to_bytes(self) -> bytes:
        d = {k: v for k, v in asdict(self).items() if v != 0 or k in ('size', 'broadcast_ts')}
        return json.dumps(d, separators=(',', ':')).encode('utf-8')

    @staticmethod
    def from_bytes(data: bytes) -> 'Otr2Header':
        d = json.loads(data.decode('utf-8'))
        h = Otr2Header()
        for k, v in d.items():
            if hasattr(h, k):
                setattr(h, k, v)
        return h

    def nonce_bytes(self) -> bytes:
        nb = bytes.fromhex(self.iv)
        if len(nb) != 12:
            raise ValueError(f"IV muss 12 Bytes sein, ist {len(nb)}")
        return nb


# ── Preamble ─────────────────────────────────────────────────────────────────

def build_preamble(hlen: int, flags: int = 0) -> bytes:
    return (
        MAGIC
        + struct.pack('<H', VERSION_1_0)
        + struct.pack('<H', flags)
        + struct.pack('<I', hlen)
        + b'\x00' * 4
    )


def parse_preamble(data: bytes) -> dict:
    if len(data) < PREAMBLE_SIZE:
        raise ValueError(f"Zu wenige Bytes fuer Preamble: {len(data)}")
    if data[:8] != MAGIC:
        raise ValueError(
            f"Keine OTR2-Datei (Magic: {data[:8].hex()}, erwartet: {MAGIC.hex()})"
        )
    version = struct.unpack_from('<H', data, 8)[0]
    flags   = struct.unpack_from('<H', data, 10)[0]
    hlen    = struct.unpack_from('<I', data, 12)[0]
    if version not in (VERSION_1_0,):
        raise ValueError(f"Unbekannte OTR2-Version: 0x{version:04x}")
    if hlen == 0 or hlen > 64 * 1024:
        raise ValueError(f"Unplausibler Header-Laenge: {hlen}")
    return {'version': version, 'flags': flags, 'hlen': hlen}


def body_offset(hlen: int) -> int:
    raw = PREAMBLE_SIZE + hlen
    pad = (BODY_ALIGNMENT - raw % BODY_ALIGNMENT) % BODY_ALIGNMENT
    return raw + pad


# ── AES-256-CTR ──────────────────────────────────────────────────────────────

def _ctr_cipher(cek: bytes, nonce12: bytes, block_index: int = 0):
    """
    AES-256-CTR.  IV = nonce12(96 Bit) || block_index(32 Bit, big-endian).
    block_index = byte_offset // 16  fuer Random-Access/Seeking.
    """
    if len(cek) != 32:
        raise ValueError(f"CEK muss 32 Bytes sein, ist {len(cek)}")
    if len(nonce12) != 12:
        raise ValueError(f"Nonce muss 12 Bytes sein, ist {len(nonce12)}")
    if block_index > MAX_BLOCK_COUNTER:
        raise ValueError(f"Block-Index {block_index} > 32-bit-Limit (max ~64 GB)")
    iv128 = nonce12 + block_index.to_bytes(4, 'big')
    return Cipher(algorithms.AES(cek), modes.CTR(iv128), backend=default_backend())


def make_encryptor(cek: bytes, nonce12: bytes):
    return _ctr_cipher(cek, nonce12).encryptor()


def make_decryptor(cek: bytes, nonce12: bytes, block_index: int = 0):
    return _ctr_cipher(cek, nonce12, block_index).decryptor()


# ── Streaming Encrypt ────────────────────────────────────────────────────────

def encrypt_file(src_path: str, dst_path: str, cek: bytes, header: Otr2Header,
                 progress_cb=None) -> dict:
    """
    Verschluesselt src_path -> dst_path als .otr2.
    progress_cb(bytes_done, bytes_total): optionaler Fortschritts-Callback.
    Gibt Statistiken zurueck.
    """
    src_size = os.path.getsize(src_path)
    header.size       = src_size
    header.created_ts = int(time.time())

    hbytes  = header.to_bytes()
    hlen    = len(hbytes)
    boff    = body_offset(hlen)
    padding = boff - PREAMBLE_SIZE - hlen

    nonce12   = header.nonce_bytes()
    encryptor = make_encryptor(cek, nonce12)

    t0 = time.perf_counter()
    written = 0

    with open(src_path, 'rb') as src, open(dst_path, 'wb') as dst:
        dst.write(build_preamble(hlen))
        dst.write(hbytes)
        dst.write(b'\x00' * padding)

        while True:
            chunk = src.read(IO_CHUNK)
            if not chunk:
                break
            dst.write(encryptor.update(chunk))
            written += len(chunk)
            if progress_cb:
                progress_cb(written, src_size)

        dst.write(encryptor.finalize())

    elapsed = time.perf_counter() - t0
    return {
        'src_size':    src_size,
        'dst_size':    os.path.getsize(dst_path),
        'body_offset': boff,
        'elapsed_s':   elapsed,
        'mbps':        (src_size / 1e6) / max(elapsed, 1e-9),
    }


# ── Streaming Decrypt ────────────────────────────────────────────────────────

def decrypt_file(src_path: str, dst_path: str, cek: bytes,
                 progress_cb=None, bei_abbruch: str = 'fehler',
                 hinweis_cb=None) -> dict:
    """
    Entschluesselt .otr2 -> Plaintext (MP4).
    Gibt Header + Statistiken zurueck.

    bei_abbruch steuert, was bei einer ABGESCHNITTENEN Quelldatei passiert
    (abgebrochener Download, halbe Datei):
      'fehler' (Vorgabe, unveraendertes Verhalten) -> EOFError wie bisher
      'weiter'                                     -> rettet, was vorhanden ist,
        und meldet es ueber 'abgeschnitten' und 'erwartet' im Rueckgabewert.

    ★12.08.2026 CRYPTOBOT (Feedback #1372/#1730): die alten Decoder hatten
    "decodieren und Fehler ignorieren". Genau das fehlte hier - eine unvollstaendig
    geladene Aufnahme war bisher komplett verloren, obwohl AES-CTR blockweise
    unabhaengig ist und der vorhandene Teil sich einwandfrei entschluesseln laesst.
    """
    if bei_abbruch not in ('fehler', 'weiter'):
        raise ValueError("bei_abbruch muss 'fehler' oder 'weiter' sein")
    t0 = time.perf_counter()

    with open(src_path, 'rb') as src:
        pre   = parse_preamble(src.read(PREAMBLE_SIZE))
        hlen  = pre['hlen']
        hdr   = Otr2Header.from_bytes(src.read(hlen))

        if hdr.scheme != SCHEME_AES256CTR:
            raise ValueError(f"Unbekanntes Scheme: {hdr.scheme}")

        nonce12   = hdr.nonce_bytes()
        expected  = hdr.size
        boff      = body_offset(hlen)
        src.seek(boff)

        decryptor = make_decryptor(cek, nonce12)
        written   = 0

        abgeschnitten = False
        with open(dst_path, 'wb') as dst:
            while written < expected:
                to_read = min(IO_CHUNK, expected - written)
                chunk   = src.read(to_read)
                if not chunk:
                    if bei_abbruch == 'fehler':
                        raise EOFError(
                            f"Datei abgeschnitten: {written}/{expected} Bytes gelesen"
                        )
                    abgeschnitten = True
                    break
                plain = decryptor.update(chunk)
                dst.write(plain)
                written += len(plain)
                if progress_cb:
                    progress_cb(written, expected)
            dst.write(decryptor.finalize())
            # ★14.08.2026 CRYPTOBOT (Feedback #1933): die Fortschrittsanzeige zaehlt
            # Bytes, die ans BETRIEBSSYSTEM uebergeben wurden - nicht die, die auf der
            # Platte liegen. Gemessen fallen 39-54 % der Schreibzeit erst hier an, beim
            # Schliessen. Auf einer externen Platte mit mehreren GB sind das Minuten, in
            # denen der Nutzer nichts sieht. Deshalb VOR dem Warten ein Hinweis.
            if hinweis_cb:
                hinweis_cb('auf die Festplatte schreiben')
            dst.flush()
            try:
                os.fsync(dst.fileno())
            except OSError:
                pass

    elapsed = time.perf_counter() - t0
    return {
        'header':        hdr,
        'dst_size':      written,
        'erwartet':      expected,
        'abgeschnitten': abgeschnitten,
        'elapsed_s':     elapsed,
        'mbps':          (written / 1e6) / max(elapsed, 1e-9),
    }


# ── Random-Access Seek-Decrypt ───────────────────────────────────────────────

def seek_decrypt(src_path: str, byte_start: int, length: int, cek: bytes) -> bytes:
    """
    Entschluesselt `length` Bytes ab Plaintext-Position `byte_start`.
    O(1) Compute dank CTR-Random-Access.
    """
    with open(src_path, 'rb') as src:
        pre  = parse_preamble(src.read(PREAMBLE_SIZE))
        hlen = pre['hlen']
        hdr  = Otr2Header.from_bytes(src.read(hlen))
        nonce12 = hdr.nonce_bytes()
        boff    = body_offset(hlen)

        block_idx  = byte_start // 16
        block_skip = byte_start % 16

        src.seek(boff + block_idx * 16)
        ct = src.read(block_skip + length)

    dec   = make_decryptor(cek, nonce12, block_index=block_idx)
    plain = dec.update(ct) + dec.finalize()
    return plain[block_skip: block_skip + length]


# ── Integritaets-Check ───────────────────────────────────────────────────────

def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(IO_CHUNK), b''):
            h.update(chunk)
    return h.hexdigest()


def verify_roundtrip(original: str, decrypted: str) -> tuple:
    h1 = sha256_file(original)
    h2 = sha256_file(decrypted)
    return h1 == h2, h1, h2


# ── Lokaler Key-Store (simuliert spaeter die DB) ─────────────────────────────

import json as _json

class LocalKeyStore:
    """
    Speichert CEKs lokal als JSON-Datei.
    Produktiv wird das durch den Key-Server (DB) ersetzt.

    Zwei Eintrags-Formen:
      - Klartext (PoC, Default ohne Tresor):
          { rec_id: { "cek": "<hex>", "broadcast_ts": <int>, "kek_id": "<str>" } }
      - Gewrappt (wenn ein KekVault uebergeben wird):
          { rec_id: { "cek_wrapped": "<hex>", "broadcast_ts": <int>, "kek_id": "<str>" } }

    Rueckwaertskompatibel: ohne `vault` exakt das alte Verhalten. Mit `vault`
    wird beim Schreiben unter dem aktiven KEK gewrappt und beim Lesen entpackt.
    Gemischte Stores (Alt-Klartext + neu gewrappt) werden beim Lesen toleriert.
    """

    def __init__(self, path: str, vault=None):
        self.path = path
        self.vault = vault
        self._data: dict = {}
        if os.path.exists(path):
            with open(path, 'r') as f:
                self._data = _json.load(f)

    def store(self, rec_id: str, cek: bytes, broadcast_ts: int, kek_id: str = "kek-2026-01"):
        if self.vault is not None:
            from otr2_kek import wrap_cek, aad_for
            use_kek = kek_id if self.vault.has(kek_id) else self.vault.active_id
            blob = wrap_cek(cek, self.vault.get(use_kek), aad_for(rec_id, use_kek))
            self._data[rec_id] = {
                'cek_wrapped':  blob.hex(),
                'broadcast_ts': broadcast_ts,
                'kek_id':       use_kek,
            }
        else:
            self._data[rec_id] = {
                'cek':          cek.hex(),
                'broadcast_ts': broadcast_ts,
                'kek_id':       kek_id,
            }
        self._save()

    def get_cek(self, rec_id: str) -> Optional[bytes]:
        entry = self._data.get(rec_id)
        if not entry:
            return None
        if 'cek_wrapped' in entry:
            if self.vault is None:
                raise ValueError(
                    f"Eintrag {rec_id} ist gewrappt, aber kein KEK-Tresor uebergeben")
            from otr2_kek import unwrap_cek, aad_for
            kek_id = entry['kek_id']
            blob   = bytes.fromhex(entry['cek_wrapped'])
            return unwrap_cek(blob, self.vault.get(kek_id), aad_for(rec_id, kek_id))
        return bytes.fromhex(entry['cek'])

    def get_entry(self, rec_id: str) -> Optional[dict]:
        """
        Gibt einen Eintrag als Klartext-Sicht zurueck (Feld 'cek' = hex), egal ob
        intern gewrappt oder Alt-Klartext. So bleibt das At-Rest-Wrapping fuer
        Aufrufer (Key-Server) transparent.
        """
        entry = self._data.get(rec_id)
        if not entry:
            return None
        cek = self.get_cek(rec_id)
        return {
            'cek':          cek.hex() if cek else None,
            'broadcast_ts': entry.get('broadcast_ts', 0),
            'kek_id':       entry.get('kek_id'),
        }

    def _save(self):
        with open(self.path, 'w') as f:
            _json.dump(self._data, f, indent=2)
