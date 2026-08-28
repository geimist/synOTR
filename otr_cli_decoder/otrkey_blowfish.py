#!/usr/bin/env python3
"""
otrkey_blowfish.py -- OTRKEY-Blowfish-Engine (Recovery, AP8/5B)

Portiert aus AltDecoderSource/OMR/UDecoder/OperatorBlowFish.cpp.

KERNBEFUND (verifiziert am C++-Source):
  - Standard-Blowfish (Pi-Konstanten 0x243f6a88...), Standard-S-Boxen/P-Array.
  - F-Funktion + Key-Schedule = STANDARD (dank #define LITTLE_ENDIAN +
    umgedrehter Bitfield-Reihenfolge ist byte.zero = MSB).
  - EINZIGE Abweichung von Referenz-Blowfish: die 8-Byte-Datenblöcke werden
    als ZWEI LITTLE-ENDIAN 32-bit-Wörter geladen/gespeichert (Referenz: big-endian).
    (OperatorBlowFish.cpp: `Work = (DWord*)pBlockBuf` auf little-endian x86.)
  - ECB default, CBC optional (m_bCBCMode).
  - Schlüssel: rohe Bytes (aus Hex-String vom Server), max 56 Bytes.

PORT-STRATEGIE: pycryptodome-Blowfish (Standard, big-endian-Block) + swap32 der
4-Byte-Gruppen vor und nach ECB → ergibt exakt OTRs little-endian-Block-Variante.

  otr_ecb_decrypt(data, key) = swap32( BF_decrypt_std( swap32(data) ) )
"""

try:
    import numpy as _np
    _HAS_NUMPY = True
except ImportError:
    _HAS_NUMPY = False


# ── Blowfish-Backend: mehrere Quellen probieren, keine an ein Paket/Version
# gebunden (CRYPTOBOT 2026-08-05, Feedback verwirrt: cryptography>=43 hat
# Blowfish nach cryptography.hazmat.decrepit.ciphers.algorithms verschoben,
# aeltere Versionen haben es noch unter primitives.ciphers.algorithms - ein
# Nutzer patchte lokal auf den neuen Pfad, aber der naechste Decoder-Self-
# Update ueberschrieb den Patch wieder mit dem alten pycryptodome-Import.
# Reihenfolge: pycryptodome zuerst (schnellster/simpelster Pfad, falls
# installiert), sonst cryptography ueber beide moeglichen Modulpfade -
# automatisch, kein Versionscheck noetig, kein manueller Patch mehr faellig.
_BACKEND = None
_bf_new = None

try:
    from Crypto.Cipher import Blowfish as _PyCryptoBlowfish

    def _bf_new(key):
        return _PyCryptoBlowfish.new(key, _PyCryptoBlowfish.MODE_ECB)

    _BACKEND = 'pycryptodome'
except ImportError:
    pass

if _bf_new is None:
    _BFAlgo = None
    for _modpath in (
        'cryptography.hazmat.decrepit.ciphers.algorithms',   # cryptography >= 43
        'cryptography.hazmat.primitives.ciphers.algorithms',  # cryptography < 43
    ):
        try:
            _mod = __import__(_modpath, fromlist=['Blowfish'])
            _BFAlgo = _mod.Blowfish
            break
        except (ImportError, AttributeError):
            continue
    if _BFAlgo is not None:
        from cryptography.hazmat.primitives.ciphers import Cipher as _CgCipher, modes as _cg_modes

        class _CgBlowfishECB:
            """Bildet die pycryptodome-.encrypt()/.decrypt()-Schnittstelle auf
            cryptography's Cipher/encryptor/decryptor-API ab, damit der Rest
            dieser Datei backend-unabhaengig bleibt."""
            def __init__(self, key):
                self._key = key

            def encrypt(self, data):
                enc = _CgCipher(_BFAlgo(self._key), _cg_modes.ECB()).encryptor()
                return enc.update(data) + enc.finalize()

            def decrypt(self, data):
                dec = _CgCipher(_BFAlgo(self._key), _cg_modes.ECB()).decryptor()
                return dec.update(data) + dec.finalize()

        def _bf_new(key):
            return _CgBlowfishECB(key)

        _BACKEND = 'cryptography'

if _bf_new is None:
    raise ImportError(
        "Keine Blowfish-Implementierung gefunden (fuer .otrkey-Dateien noetig). "
        "Bitte installieren: 'pip install pycryptodome' ODER 'pip install cryptography' "
        "(jede Version - alt und neu >=43 werden automatisch erkannt)."
    )


import array as _array

# 'I' ist auf allen von uns bedienten Plattformen 4 Byte, aber das ist nicht vom
# Standard garantiert - deshalb geprüft statt angenommen.
_SWAP_TYP = None
for _t in ('I', 'L'):
    try:
        if _array.array(_t).itemsize == 4:
            _SWAP_TYP = _t
            break
    except ValueError:
        continue


def swap32(b: bytes) -> bytes:
    """Spiegelt jede 4-Byte-Gruppe (LE<->BE 32-bit-Wort). Länge muss durch 4 teilbar sein.

    ★2026-08-12 CRYPTOBOT (Nachgang zu Feedback #1765): der Rückfallweg ohne numpy
    war `b''.join(b[i:i+4][::-1] for i in range(0, len(b), 4))`. Das erzeugt pro
    8-MB-Block ZWEI MILLIONEN kleine bytes-Objekte, und swap32 läuft zweimal je
    Block (vor und nach dem Entschlüsseln). Das ist der eigentliche Grund für die
    stark schwankende Speicherbelegung und die geringe Geschwindigkeit auf Rechnern
    ohne numpy - die Blockgröße allein deckelt das nicht, weil der Speicher innerhalb
    eines Blocks in Millionen Einzelobjekten anfällt.

    array.byteswap() macht dasselbe in C, mit genau zwei Kopien und ohne ein einziges
    Objekt je Wort. numpy bleibt der schnellste Weg, wird aber nicht mehr gebraucht.
    """
    if len(b) % 4:
        raise ValueError("swap32: Länge nicht durch 4 teilbar")
    if _HAS_NUMPY and len(b) > 4096:
        # schneller Pfad für große Buffer (252 MB etc.)
        return _np.frombuffer(b, dtype=_np.uint8).reshape(-1, 4)[:, ::-1].tobytes()
    if _SWAP_TYP is not None:
        a = _array.array(_SWAP_TYP)
        a.frombytes(b)
        a.byteswap()
        return a.tobytes()
    # letzter Rückfallweg (Plattform ohne 4-Byte-Typ) - langsam, aber korrekt
    return b''.join(b[i:i+4][::-1] for i in range(0, len(b), 4))


def otr_ecb_decrypt(data: bytes, key: bytes) -> bytes:
    """
    OTRKEY-Blowfish ECB Entschlüsselung.
    data-Länge muss Vielfaches von 8 sein (Rest bleibt im Original unverschlüsselt).
    """
    if len(data) % 8:
        raise ValueError("otr_ecb_decrypt: Länge nicht durch 8 teilbar")
    c = _bf_new(key)
    return swap32(c.decrypt(swap32(data)))


def otr_ecb_encrypt(data: bytes, key: bytes) -> bytes:
    """Gegenstück (für Tests / Re-Encrypt-Verifikation)."""
    if len(data) % 8:
        raise ValueError("otr_ecb_encrypt: Länge nicht durch 8 teilbar")
    c = _bf_new(key)
    return swap32(c.encrypt(swap32(data)))


# ── Selbsttest ────────────────────────────────────────────────────────────────

def self_test():
    """
    1. Verifiziert, dass pycryptodome-Blowfish der Standard-Algorithmus ist
       (klassischer Schneier-Testvektor, big-endian Block).
    2. Verifiziert swap32-Roundtrip.
    """
    # Standard-Blowfish-Testvektoren (Schneier), big-endian Block:
    vectors = [
        ('0000000000000000', '0000000000000000', '4EF997456198DD78'),
        ('FFFFFFFFFFFFFFFF', 'FFFFFFFFFFFFFFFF', '51866FD5B85ECB8A'),
        ('3000000000000000', '1000000000000001', '7D856F9A613063F2'),
    ]
    print(f"1) Blowfish-Backend '{_BACKEND}' == Standard (big-endian Block):")
    ok = True
    for key_h, pt_h, ct_h in vectors:
        c = _bf_new(bytes.fromhex(key_h))
        got = c.encrypt(bytes.fromhex(pt_h)).hex().upper()
        match = got == ct_h
        ok &= match
        print(f"   key={key_h} pt={pt_h} -> {got} {'OK' if match else 'FAIL erwartet '+ct_h}")

    # swap32 Roundtrip + OTR-ECB Roundtrip
    print("2) swap32 + OTR-ECB Roundtrip:")
    key  = b'TestKey1'
    data = b'12345678ABCDEFGH'   # 16 Byte
    enc  = otr_ecb_encrypt(data, key)
    dec  = otr_ecb_decrypt(enc, key)
    rt   = dec == data
    print(f"   roundtrip {'OK' if rt else 'FAIL'}  (enc={enc.hex()[:24]}...)")
    ok &= rt

    print()
    print("Engine verifiziert." if ok else "ENGINE-FEHLER!")
    print("Hinweis: Die OTR-little-endian-Variante wird final an der echten")
    print("otrkey-Header-Dekodierung verifiziert (sobald Header-Key vorliegt).")
    return ok


if __name__ == '__main__':
    self_test()
