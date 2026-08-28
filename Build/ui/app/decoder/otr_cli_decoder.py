#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
otr_cli_decoder.py -- End-User-CLI-Decoder fuer OTR (.otr2 neu + .otrkey alt)

Aufruf (ein Login/Ticket fuer den ganzen Batch, EIN Quell-/Zielordner egal ob
1 oder 500 Dateien -- kein Ordner-Dialog pro Datei):

  python otr_cli_decoder.py --email user@beispiel.de --password ***** \
      --quellordner "C:\\Downloads" --zielordner "C:\\Videos"

--quellordner ist optional (Default: aktuelles Verzeichnis) und akzeptiert auch den
Pfad zu einer EINZELNEN .otr2/.otrkey-Datei statt eines Ordners.

Ablauf pro Format:
  .otr2   : Login -> JWT (apps/backend /api/auth/login)
            -> Ticket (GET /api/otr2/ticket, 1x pro Batch, rec-agnostisch)
            -> pro Datei: rec_id aus Header, POST keys.onlinetvrecorder.com/key
               {rec, token=ticket, client_pub} -> wrapped_cek (ECIES P-256)
            -> lokal entschluesselt (EC-Private bleibt IMMER lokal)
            -> AES-256-CTR-Body entschluesseln (otr2lib) + forensisches
               Wasserzeichen (otr2_watermark, wie otr2dec.py)
  .otrkey : pro Datei direkt POST quelle_web.php {email,password,FN,OH}
            -> random_key -> Blowfish-ECB-Body entschluesseln (otrkey_decode)

Sicherheit:
  - Passwort geht NUR per HTTPS an die eigenen Produktions-Endpunkte, wird
    nie geloggt/geschrieben.
  - EC-Schluesselpaar fuer die ECIES-Umhuellung ist pro Lauf frisch (Prozess-
    lokal, verlaesst den Rechner nie).
  - Cloudflare blockt Nicht-Browser-User-Agents (403/1010) -> alle Requests
    setzen einen Browser-User-Agent.

Abhaengigkeiten: nur 'cryptography' (python3 -m pip install cryptography).
★12.08.2026: 'requests' wird NICHT mehr gebraucht - HTTP laeuft ueber urllib
aus der Standardbibliothek. Ein Paket weniger, das an PEP 668 scheitern kann.
(otrkey_blowfish.py probiert fuer den .otrkey-Altpfad automatisch mehrere Blowfish-
Quellen: zuerst pycryptodome falls vorhanden, sonst cryptography selbst - ueber
BEIDE moeglichen Modulpfade (cryptography>=43 hat Blowfish nach hazmat.decrepit
verschoben, aeltere Versionen haben es noch unter hazmat.primitives). CRYPTOBOT
2026-08-05, Feedback verwirrt: ein fest verdrahteter 'from Crypto.Cipher import
Blowfish'-Import zwang zu pycryptodome UND brach bei neueren cryptography-Versionen
(Blowfish verschoben) - beides jetzt automatisch abgedeckt, pycryptodome bleibt
optional. Wer nur eine sehr alte cryptography-Version ohne Blowfish UND kein
pycryptodome hat, bekommt trotzdem eine klare Fehlermeldung statt Traceback.)
Freigegeben zur Redistribution (GC 2026-08-04): Download-Angebot unter
https://www.onlinetvrecorder.com/OTR_Decoder.html -> "CLI-Decoder (Python)",
gehostet unter /cli-dist/ auf .182. Spricht weiterhin Produktions-API.

Selbst-Update: bei jedem Start wird (fail-open, kurzer Timeout) ein Manifest unter
UPDATE_MANIFEST_URL abgefragt. Bei neuer Version werden dieses Skript + seine drei
lokalen Abhaengigkeiten (otr2lib.py, otr2_watermark.py, otrkey_blowfish.py) sha256-
verifiziert geladen, ALLE zusammen erst nach vollstaendiger Verifikation atomar
geschrieben (kein Teil-Update moeglich) und der Prozess mit denselben Argumenten neu
gestartet. --no-update-check schaltet das ab (z.B. fuer Offline-Nutzung/Tests).
"""

import argparse
import base64
import getpass
import http.cookiejar
# ★json wurde bisher NIE selbst importiert - der Code hat ausschliesslich
# r.json() von requests benutzt. Beim Umstieg auf urllib faellt das sofort auf
# die Fuesse (NameError beim ersten Serveraufruf); mein Testlauf hat genau das
# gefangen, bevor es zu einem Kunden kam.
import json
import urllib.error
import urllib.parse
import urllib.request
import hashlib
import os
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))


def _own_console_window():
    """True wenn ein Mensch tatsaechlich an einer Konsole sitzt (Doppelklick
    ODER aus einer bestehenden Shell heraus gestartet) - dann lohnt sich das
    Warten auf Enter am Ende, sonst sieht der Nutzer weder Status noch Fehler-
    meldungen (Feedback buffalo75 2026-08-05). False nur bei echter Umleitung
    (Datei/Pipe/Automatisierung).
    ★06.08. KORREKTUR: die vorherige Fassung pruefte GetConsoleProcessList()
    (Anzahl Prozesse an der Konsole) - das lieferte unter Windows Terminal/
    ConPTY (Windows-11-Standard) irrefuehrende Werte, die Pause blieb trotz
    eigenem Fenster aus (Feedback buffalo75 2026-08-05, Build .4 selbst
    gemeldet). sys.stdin.isatty() ist die Standard-Pruefung fuer "haengt ein
    echtes Terminal dran" und bleibt unter ConPTY zuverlaessig, weil sie den
    Handle-TYP prueft statt Prozesse an der Konsole zu zaehlen."""
    if os.name != 'nt':
        return False
    try:
        return sys.stdin.isatty()
    except Exception:
        return False


def _read_password_windows(prompt):
    """Maskierte Passwort-Eingabe direkt ueber msvcrt statt getpass.getpass().
    ★06.08. (Feedback MrR): getpass.getpass() nahm bei manchen Nutzern unter
    Windows 11 gar keine Tastendruecke an (E-Mail per input() ging, Passwort
    per getpass() nicht) - vermutlich dasselbe Konsolen-Kompatibilitaets-
    problem wie bei buffalo75s Pause-Bug (vgl. _own_console_window), diesmal
    in getpass()s eigener Low-Level-Implementierung statt in unserem Code.
    Diese Fassung liest direkt einzelne Tasten ueber msvcrt.getwch() und
    maskiert selbst mit '*' - unabhaengig von getpass()s interner Moduswahl,
    die unter Windows Terminal/ConPTY offenbar nicht zuverlaessig greift."""
    import msvcrt
    sys.stdout.write(prompt)
    sys.stdout.flush()
    chars = []
    while True:
        ch = msvcrt.getwch()
        if ch in ('\r', '\n'):
            sys.stdout.write('\n')
            break
        elif ch == '\x03':
            raise KeyboardInterrupt
        elif ch == '\x1a':   # Strg+Z = EOF unter Windows
            raise EOFError
        elif ch in ('\x08', '\x7f'):   # Backspace
            if chars:
                chars.pop()
                sys.stdout.write('\b \b')
                sys.stdout.flush()
        elif ch == '\x00' or ch == '\xe0':
            msvcrt.getwch()   # Sondertaste (Pfeile/F-Tasten) - zweites Codewort verwerfen
        else:
            chars.append(ch)
            sys.stdout.write('*')
            sys.stdout.flush()
    return ''.join(chars)


def _prompt_password(prompt):
    """getpass.getpass() mit Fallback auf die eigene msvcrt-Eingabe (Windows)
    bzw. auf sichtbare input()-Eingabe, falls beides scheitert - besser eine
    sichtbare Eingabe als eine, die gar keine Tasten annimmt."""
    if os.name == 'nt':
        try:
            return _read_password_windows(prompt)
        except ImportError:
            pass
    try:
        return getpass.getpass(prompt)
    except Exception:
        print('(Hinweis: maskierte Eingabe nicht moeglich - Passwort wird sichtbar eingegeben.)')
        return input(prompt)


# CRYPTOBOT 2026-08-05 (Feedback verwirrt/hansmp3): ein rohes ImportError/
# ModuleNotFoundError hier zeigt Einsteigern nur einen Python-Traceback statt
# einer klaren Handlungsanweisung (welches der zwei benoetigten Pakete fehlt).
# Klarer Hinweis statt Traceback, exit(1) statt weiterlaufen mit halb-geladenem
# Modul.
try:
    from cryptography.hazmat.primitives.asymmetric.ec import (
        ECDH, EllipticCurvePublicKey, SECP256R1, generate_private_key,
    )
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.kdf.hkdf import HKDF
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM

    from otr2lib import (
        Otr2Header, decrypt_file, parse_preamble, PREAMBLE_SIZE, body_offset,
    )
    from otr2_watermark import embed_watermark, embed_watermark_datei
    from otrkey_blowfish import otr_ecb_decrypt
except ImportError as _e:
    print(f'FEHLER: Abhaengigkeit fehlt ({_e}).', file=sys.stderr)
    print('Bitte einmalig installieren:', file=sys.stderr)
    print('  python3 -m pip install cryptography', file=sys.stderr)
    print('(deckt .otr2 UND .otrkey ab. Nur wenn danach immer noch ein '
          'Blowfish-Fehler kommt: zusaetzlich "pip install pycryptodome".)',
          file=sys.stderr)
    if _own_console_window():
        try: input('\nZum Beenden Enter druecken ...')
        except (EOFError, KeyboardInterrupt): pass
    sys.exit(1)

OTRKEY_MAGIC = b'OTRKEYFILE'
OTRKEY_HEADER_SIZE = 512
OTRKEY_DATA_OFFSET = len(OTRKEY_MAGIC) + OTRKEY_HEADER_SIZE  # 522
OTRKEY_HARD_KEY = bytes([
    0xEF, 0x3A, 0xB2, 0x9C, 0xD1, 0x9F, 0x0C, 0xAC,
    0x57, 0x59, 0xC7, 0xAB, 0xD1, 0x2C, 0xC9, 0x2B,
    0xA3, 0xFE, 0x0A, 0xFE, 0xBF, 0x96, 0x0D, 0x63,
    0xFE, 0xBD, 0x0F, 0x45,
])

DEFAULT_API_BASE   = 'https://api.onlinetvrecorder.com'
DEFAULT_KEYSERVER  = 'https://keys.onlinetvrecorder.com'
# quelle_web.php (JSON: {random_key} / {error,message}), NICHT quelle.php.
# quelle.php ist der alte Blowfish-"code"-Endpunkt und liefert rohen Text
# ("MessageToBePrintedInDecoder...") -> r.json() scheitert. Genau das war der
# "kein JSON"-Blocker, der den .otrkey-Pfad auf HOLD legte (verifiziert 23.07.:
# quelle_web.php POST {email,password,FN,OH} -> application/json). quelle_web.php
# nimmt email+password direkt entgegen (kein Session-Zwang), wie das V3-Backend.
DEFAULT_QUELLE_URL = 'https://www.onlinetvrecorder.com/quelle_web.php'
BROWSER_UA = ('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36')
HKDF_INFO = b'otr2-key-wrapping-v1'   # muss exakt otr2_keyserver_core.ecies_encrypt spiegeln

__version__ = '2026-08-17.1'
UPDATE_MANIFEST_URL = 'https://www.onlinetvrecorder.com/cli-dist/otr_cli_decoder_manifest.json'
# ★13.08.2026: otr_decoder_gui.py kam dazu. Sie lag seit dem 09.08. auf dem Server, war
# aber in KEINEM Paket enthalten - Kundenmeldung "die GUI gibt es nicht im Paket" war
# schlicht richtig. Reihenfolge beim Ausliefern beachten: erst muss das Manifest die
# Datei fuehren, dann darf ein Client sie hier verlangen (sonst bricht seine
# Selbst-Aktualisierung mit "Manifest unvollstaendig" ab).
UPDATE_FILES = ('otr_cli_decoder.py', 'otr2lib.py', 'otr2_watermark.py',
                'otrkey_blowfish.py', 'otr_decoder_gui.py')


def self_update(manifest_url: str = UPDATE_MANIFEST_URL) -> bool:
    """Fail-open: jeder Fehler (kein Netz, Server down, kaputtes Manifest, kein
    Schreibrecht) beendet NUR das Update, nie den eigentlichen Entschluesselungslauf.
    Gibt True zurueck, wenn ein Update geschrieben wurde (der Aufrufer re-exec't dann)."""
    try:
        req = urllib.request.Request(
            manifest_url, headers={'User-Agent': BROWSER_UA, 'Accept-Encoding': 'identity'})
        with urllib.request.urlopen(req, timeout=5) as r:
            if r.status >= 400:
                return False
            manifest = json.loads(r.read().decode('utf-8', 'replace'))
    except Exception:
        return False   # kein Netz / Server nicht erreichbar -> mit aktueller Version weiterlaufen
    if manifest.get('version') == __version__:
        return False
    files = manifest.get('files', {})
    missing = [f for f in UPDATE_FILES if f not in files]
    if missing:
        print(f'Update-Manifest unvollstaendig (fehlt: {", ".join(missing)}) -- ignoriert.',
              file=sys.stderr)
        return False
    staged = {}
    for fname in UPDATE_FILES:
        meta = files[fname]
        try:
            content = base64.b64decode(meta['b64'])
        except Exception as e:
            print(f'Update abgebrochen ({fname} nicht dekodierbar): {e}', file=sys.stderr)
            return False
        if hashlib.sha256(content).hexdigest() != meta.get('sha256'):
            print(f'Update abgebrochen: sha256-Mismatch bei {fname}.', file=sys.stderr)
            return False
        staged[fname] = content
    here = Path(__file__).resolve().parent
    try:
        # Alle Dateien sind sha256-verifiziert -- erst jetzt schreiben, damit ein
        # Netzabbruch mitten im Schreiben nie eine der vier Dateien halb aktualisiert
        # und die anderen alt laesst (inkonsistenter Stand waere schwerer zu finden
        # als gar kein Update).
        for fname, content in staged.items():
            target = here / fname
            tmp = here / (fname + '.update-tmp')
            tmp.write_bytes(content)
            os.replace(tmp, target)
    except OSError as e:
        print(f'Update verfuegbar ({manifest.get("version")}), aber nicht schreibbar '
              f'({e}) -- bitte manuell aktualisieren.', file=sys.stderr)
        return False
    print(f'Aktualisiert: {__version__} -> {manifest.get("version")} -- starte neu ...')
    return True


class OtrCliError(Exception):
    pass


def _error_text(r) -> str:
    """Extrahiert eine lesbare Fehlermeldung aus einer JSON- oder Text-Antwort."""
    try:
        data = r.json()
    except ValueError:
        return r.text[:200] if r.text else f'HTTP {r.status_code}'
    if isinstance(data, dict):
        if isinstance(data.get('issues'), dict):
            fe = data['issues'].get('fieldErrors', {}) or {}
            parts = [f'{k}: {", ".join(v)}' for k, v in fe.items() if v]
            if parts:
                return '; '.join(parts)
        for key in ('error', 'message'):
            if data.get(key):
                return str(data[key])
        return str(data)
    return str(data)


def _friendly_http_error(r, context: str) -> OtrCliError:
    """Baut aus einer Fehlerantwort eine lesbare OtrCliError statt rohem HTTPError/Traceback."""
    return OtrCliError(f'{context} (HTTP {r.status_code}): {_error_text(r)}')


# ── HTTP ohne Fremdpakete ────────────────────────────────────────────────────
# ★12.08.2026 CRYPTOBOT (Kundenmeldung gruenzeugs): frueher "import requests".
# Der CLI-Decoder verlangte damit zwei nachzuinstallierende Pakete, und genau
# daran scheitern aktuelle Systeme: seit PEP 668 lehnt Debian 12+/Ubuntu 23.04+/
# Fedora ein "pip install" ins System mit "externally-managed-environment" ab.
# Fuer den Nutzer sieht das aus, als verlange das Programm eine Python-Umgebung,
# die es nicht mehr gibt. Da wir von requests nur vier Aufrufe und vier
# Antwort-Eigenschaften benutzen, ist die Standardbibliothek voellig ausreichend.
# Bewusst als Ersatz mit GLEICHER Schnittstelle gebaut, damit keine einzige
# Aufrufstelle angefasst werden muss - das haelt die Aenderung klein und pruefbar.
#
# ★Nebeneffekt, der einen alten Fehler mit erledigt: wir fordern die Antwort
# jetzt unkomprimiert an (Accept-Encoding: identity). Der zstd-Absturz aus
# Feedback #1676 entstand, weil urllib3 dem Server automatisch "zstd" anbot,
# sobald das optionale zstandard-Paket vorhanden war. Diese Verhandlung gibt es
# hier nicht mehr - unsere Antworten sind JSON und ein paar Kilobyte gross.
class _Antwort:
    """Das Wenige, was der Code von einer requests-Antwort braucht."""
    __slots__ = ('status_code', 'content', 'url', 'headers')

    def __init__(self, status_code, content, url, headers):
        self.status_code = status_code
        self.content = content
        self.url = url
        self.headers = headers

    @property
    def text(self):
        lade = (self.headers or {}).get('Content-Type', '') if self.headers else ''
        m = re.search(r'charset=([\w-]+)', lade or '', re.I)
        return self.content.decode(m.group(1) if m else 'utf-8', 'replace')

    def json(self):
        # json.JSONDecodeError ist eine Unterklasse von ValueError - die
        # bestehenden "except ValueError"-Stellen greifen also unveraendert.
        return json.loads(self.text)

    def raise_for_status(self):
        if self.status_code >= 400:
            raise OtrCliError(f'HTTP {self.status_code} bei {self.url}')


class _Sitzung:
    """Ersatz fuer requests.Session - nur der benutzte Ausschnitt."""

    def __init__(self):
        self.headers = {}
        # Cookie-Speicher wie bei requests.Session. Wird von unseren Endpunkten
        # nicht gebraucht (Token-Auth), kostet aber nichts und haelt das
        # Verhalten gleich, falls ein Server doch einmal ein Cookie setzt.
        self._opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

    def _anfrage(self, methode, url, json_daten=None, data=None, headers=None, timeout=15):
        koerper = None
        kopf = dict(self.headers)
        kopf['Accept-Encoding'] = 'identity'
        if json_daten is not None:
            koerper = json.dumps(json_daten).encode('utf-8')
            kopf['Content-Type'] = 'application/json'
        elif data is not None:
            koerper = urllib.parse.urlencode(data).encode('utf-8')
            kopf['Content-Type'] = 'application/x-www-form-urlencoded'
        if headers:
            kopf.update(headers)
        req = urllib.request.Request(url, data=koerper, headers=kopf, method=methode)
        try:
            with self._opener.open(req, timeout=timeout) as r:
                return _Antwort(r.status, r.read(), r.geturl(), dict(r.headers))
        except urllib.error.HTTPError as e:
            # WICHTIG: nicht weiterwerfen. Der bestehende Code prueft ueberall
            # "r.status_code >= 400" und baut daraus eine lesbare Meldung - er
            # erwartet also auch bei 401/403/500 ein Antwortobjekt, keine Ausnahme.
            try:
                inhalt = e.read()
            except Exception:
                inhalt = b''
            return _Antwort(e.code, inhalt, url, dict(e.headers or {}))

    def get(self, url, headers=None, timeout=15, **_):
        return self._anfrage('GET', url, headers=headers, timeout=timeout)

    def post(self, url, json=None, data=None, headers=None, timeout=15, **_):
        return self._anfrage('POST', url, json_daten=json, data=data,
                              headers=headers, timeout=timeout)


def _session():
    s = _Sitzung()
    # ★2026-08-10 (Feedback #1676, "zstd.ZstdDecompressor object has no attribute
    # 'eof'"): urllib3 2.x bietet dem Server automatisch "zstd" als Encoding an,
    # WENN das optionale zstandard-Paket installiert ist -- bei manchen Versionen
    # davon crasht das interne Dekomprimieren dann mitten in requests, ohne dass
    # dieser Code je "zstd" erwaehnt. gzip/deflate reichen fuer unsere JSON-
    # Antworten voellig aus, daher zstd hier explizit aus der Verhandlung nehmen.
    s.headers.update({'User-Agent': BROWSER_UA, 'Accept-Encoding': 'gzip, deflate'})
    return s


# ── .otr2 -- Login/Ticket/ECIES ──────────────────────────────────────────────

def login(sess, api_base: str, email: str, password: str) -> dict:
    r = sess.post(f'{api_base.rstrip("/")}/api/auth/login',
                  json={'email': email, 'password': password}, timeout=15)
    if r.status_code == 401:
        raise OtrCliError('Login fehlgeschlagen: falsche Zugangsdaten.')
    if r.status_code >= 400:
        raise _friendly_http_error(r, 'Login fehlgeschlagen')
    data = r.json()
    if 'token' not in data:
        raise OtrCliError('Login-Antwort enthaelt kein Token.')
    return data


def get_ticket(sess, api_base: str, jwt: str) -> dict:
    r = sess.get(f'{api_base.rstrip("/")}/api/otr2/ticket',
                 headers={'Authorization': f'Bearer {jwt}'}, timeout=15)
    if r.status_code == 401:
        raise OtrCliError('Ticket-Anfrage abgelehnt (Login abgelaufen?).')
    if r.status_code >= 400:
        raise _friendly_http_error(r, 'Ticket-Anfrage fehlgeschlagen')
    return r.json()   # {ticket, plan, exp}


def gen_client_keypair():
    priv = generate_private_key(SECP256R1())
    pub_der = priv.public_key().public_bytes(
        serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
    return priv, base64.b64encode(pub_der).decode()


def ecies_decrypt(wrapped: bytes, priv) -> bytes:
    """Kehrt otr2_keyserver_core.ecies_encrypt um: eph_pub(65)||nonce(12)||ct+tag."""
    eph_pub_bytes, nonce, ct = wrapped[:65], wrapped[65:77], wrapped[77:]
    eph_pub = EllipticCurvePublicKey.from_encoded_point(SECP256R1(), eph_pub_bytes)
    shared = priv.exchange(ECDH(), eph_pub)
    key = HKDF(algorithm=hashes.SHA256(), length=32, salt=None,
               info=HKDF_INFO).derive(shared)
    return AESGCM(key).decrypt(nonce, ct, None)


def fetch_cek_otr2(sess, keyserver: str, rec_id: str, ticket: str,
                    priv, pub_b64: str) -> bytes:
    r = sess.post(f'{keyserver.rstrip("/")}/key',
                  json={'rec': rec_id, 'token': ticket, 'client_pub': pub_b64},
                  timeout=15)
    if r.status_code == 403:
        raise OtrCliError(f'Kein Recht: {_error_text(r)}')
    if r.status_code == 404:
        raise OtrCliError('Aufnahme nicht auf dem Schluesselserver registriert (404).')
    if r.status_code >= 400:
        raise _friendly_http_error(r, 'Schluesselabruf fehlgeschlagen')
    data = r.json()
    return ecies_decrypt(base64.b64decode(data['wrapped_cek']), priv)


def read_otr2_header(path: Path) -> Otr2Header:
    with open(path, 'rb') as f:
        pre = parse_preamble(f.read(PREAMBLE_SIZE))
        return Otr2Header.from_bytes(f.read(pre['hlen']))


def otr2_vollstaendigkeit(path: Path, hdr: Otr2Header):
    """Prueft OHNE Schluessel, ob die .otr2-Datei vollstaendig heruntergeladen ist.

    Moeglich, weil die Datei ihre eigene Sollgroesse mitbringt: der Header nennt die
    Klartextgroesse, und AES-256-CTR ist laengenerhaltend. Eine vollstaendige Datei hat
    also exakt `body_offset(hlen) + header.size` Bytes.

    ★15.08.2026 CRYPTOBOT, Rueckmeldung #1945: Die Dekodierung wird beim ABHOLEN des
    Schluessels gezaehlt, nicht bei Erfolg. Wer eine unvollstaendig geladene Datei
    entschluesselte, bekam bisher trotzdem einen Abzug - der Abbruch fiel erst NACH dem
    Schluesselabruf auf (decrypt_file -> stats['abgeschnitten']). Diese Pruefung sitzt
    davor, damit fuer eine kaputte Quelldatei erst gar kein Schluessel angefordert wird.

    Liefert (vollstaendig, ist_bytes, soll_bytes). Bei unbekannter Sollgroesse (size=0,
    Altbestand) wird bewusst NICHT blockiert - fail-open, damit die Pruefung nie eine
    entschluesselbare Datei verhindert.
    """
    with open(path, 'rb') as f:
        pre = parse_preamble(f.read(PREAMBLE_SIZE))
    soll_nutz = int(getattr(hdr, 'size', 0) or 0)
    if soll_nutz <= 0:
        return True, path.stat().st_size, 0
    soll = body_offset(pre['hlen']) + soll_nutz
    return path.stat().st_size >= soll, path.stat().st_size, soll


# ── .otrkey -- Legacy quelle_web.php ─────────────────────────────────────────────

def parse_otrkey_header(path: Path) -> dict:
    data = path.read_bytes()
    if data[:10] != OTRKEY_MAGIC:
        raise OtrCliError(f'Kein OTRKEYFILE-Magic in {path.name}')
    dec = otr_ecb_decrypt(data[10:10 + OTRKEY_HEADER_SIZE], OTRKEY_HARD_KEY)
    text = dec.split(b'\x00', 1)[0].decode('latin-1', 'replace')
    fields = {}
    for part in text.split('&'):
        if '=' in part:
            k, v = part.split('=', 1)
            fields[k] = v
    return fields


def fetch_key_otrkey(sess, quelle_url: str, email: str, password: str,
                      filename: str, otr_hash: str) -> str:
    r = sess.post(quelle_url, data={'email': email, 'password': password,
                                     'FN': filename, 'OH': otr_hash}, timeout=20)
    try:
        data = r.json()
    except ValueError:
        data = None
    if isinstance(data, dict) and 'error' in data:
        raise OtrCliError(f'Schluesseldienst: {data["error"]}')
    if r.status_code >= 400:
        raise _friendly_http_error(r, 'Schluesseldienst-Anfrage fehlgeschlagen')
    if not isinstance(data, dict) or 'random_key' not in data:
        raise OtrCliError('Schluesseldienst-Antwort ohne random_key.')
    return data['random_key']


def decode_otrkey_file(path: Path, dst: Path, key_hex: str) -> int:
    # ★2026-08-10 (Feedback #1765, RAM auf 20GB+ bei einer HD-otrkey): die alte
    # Fassung las die komplette Datei in den Speicher (read_bytes) und baute das
    # Ergebnis nochmal komplett neu zusammen (Konkatenation) -- bei einer
    # Mehr-GB-Datei leicht das 2-3fache der Dateigroesse gleichzeitig im RAM.
    # ECB ist blockweise unabhaengig (kein Chaining-State), daher ist Chunking
    # verlustfrei moeglich: RAM-Bedarf ist ab jetzt CHUNK_SIZE, unabhaengig von
    # der Dateigroesse.
    key = bytes.fromhex(key_hex)
    CHUNK_SIZE = 8 * 1024 * 1024  # Vielfaches von 8, RAM-Deckel unabhaengig von Dateigroesse
    total = 0
    with path.open('rb') as fin, dst.open('wb') as fout:
        fin.read(OTRKEY_DATA_OFFSET)  # Header ueberspringen, nicht Teil der Ausgabe
        while True:
            chunk = fin.read(CHUNK_SIZE)
            if not chunk:
                break
            n8 = (len(chunk) // 8) * 8
            if n8:
                fout.write(otr_ecb_decrypt(chunk[:n8], key))
                total += n8
            tail = chunk[n8:]
            if tail:
                fout.write(tail)
                total += len(tail)
    return total


# ── Gemeinsame Ablaufsteuerung ────────────────────────────────────────────────

def progress_bar(done: int, total: int, width: int = 30):
    pct = done / total if total else 0
    filled = int(width * pct)
    bar = '#' * filled + '-' * (width - filled)
    print(f'\r    [{bar}] {done/1e6:6.0f}/{total/1e6:.0f} MB', end='', flush=True)


def otrkey_output_name(name: str) -> str:
    return name[:-len('.otrkey')] if name.lower().endswith('.otrkey') else name + '.dec'


def _schreib_hinweis(was):
    """Sichtbarer Hinweis fuer den Schritt, der bisher stumm war.

    ★14.08.2026 CRYPTOBOT (Feedback #1933 Punkt 2): die Fortschrittsanzeige ist bei
    100 %, wenn alle Bytes ans Betriebssystem uebergeben sind - nicht, wenn sie auf der
    Platte stehen. Gemessen fallen 39-54 % der Schreibzeit danach an. Bei mehreren GB
    auf einer externen Platte sind das Minuten, in denen der Nutzer nichts sieht und
    denkt, das Programm haenge.
    """
    print('\n    %s ... (bei grossen Dateien dauert das einen Moment)' % was, flush=True)


def run(args):
    prot = Protokoll(getattr(args, 'protokoll', None))
    # ★13.08.2026 (Feedback #1888 Punkt 2): die WIRKSAMEN Werte protokollieren, nicht nur
    # das Ergebnis. Genau daran haette sich Punkt 1 sofort zeigen lassen: im Protokoll
    # haette 'zielordner: (wie Quelle)' gestanden, obwohl die Datei einen nennt.
    prot.zeile('Quellordner : %s' % args.quellordner)
    prot.zeile('Zielordner  : %s' % (args.zielordner or '(wie Quelle)'))
    prot.zeile('Schalter    : %s' % (', '.join(
        [n for n, an in (('--force', args.force),
                         ('--no-watermark', args.no_watermark),
                         ('--delete-source', args.delete_source),
                         ('--fehler-ignorieren', getattr(args, 'fehler_ignorieren', False)),
                         ('--nicht-warten', getattr(args, 'nicht_warten', False)),
                         ('--kein-dialog', getattr(args, 'kein_dialog', False)),
                         ('--no-update-check', args.no_update_check)) if an]) or '(keine)'))
    prot.zeile('Einstellungsdatei: %s' % (INI_FILE if INI_FILE.exists()
                                          else (CONFIG_FILE if CONFIG_FILE.exists() else '(keine)')))
    # Drag&Drop / Verknuepfung mit Dateien oder EINEM Ordner als Ziel: Windows/Explorer
    # haengt die abgelegten Pfade als normale Kommandozeilen-Argumente an (positional,
    # kein --quellordner). Ein einzelner Ordner verhaelt sich wie --quellordner; eine
    # oder mehrere Dateien werden direkt als Auswahl genommen (Mehrfachauswahl moeglich).
    paths = [Path(p).expanduser().resolve() for p in (args.pfade or [])]
    if len(paths) == 1 and paths[0].is_dir():
        args.quellordner = str(paths[0])
        paths = []

    if paths:
        missing = [p for p in paths if not p.is_file()]
        if missing:
            raise OtrCliError('Datei(en) nicht gefunden: ' + ', '.join(str(p) for p in missing))
        dst = Path(args.zielordner).expanduser().resolve() if args.zielordner else paths[0].parent
        dst.mkdir(parents=True, exist_ok=True)
        otr2_files = [p for p in paths if p.suffix.lower() == '.otr2']
        otrkey_files = [p for p in paths if p.suffix.lower() == '.otrkey']
        andere = [p for p in paths if p not in otr2_files and p not in otrkey_files]
        if andere:
            print('Ignoriert (keine .otr2/.otrkey-Datei): ' + ', '.join(p.name for p in andere))
        if not otr2_files and not otrkey_files:
            raise OtrCliError('Keine .otr2/.otrkey-Datei in der Auswahl.')
    else:
        src = Path(args.quellordner).expanduser().resolve()
        if src.is_file():
            # Einzelne Datei statt Ordner: Ziel-Default ist dann der Ordner der Datei,
            # nicht die Datei selbst (sonst wuerde mkdir() auf einer Datei scheitern).
            dst = Path(args.zielordner).expanduser().resolve() if args.zielordner else src.parent
            dst.mkdir(parents=True, exist_ok=True)
            ext = src.suffix.lower()
            if ext == '.otr2':
                otr2_files, otrkey_files = [src], []
            elif ext == '.otrkey':
                otr2_files, otrkey_files = [], [src]
            else:
                raise OtrCliError(f'Keine .otr2/.otrkey-Datei: {src}')
        elif src.is_dir():
            dst = Path(args.zielordner or args.quellordner).expanduser().resolve()
            dst.mkdir(parents=True, exist_ok=True)
            otr2_files = sorted(src.glob('*.otr2'))
            otrkey_files = sorted(p for p in src.glob('*.otrkey'))
            if not otr2_files and not otrkey_files:
                print(f'Keine .otr2/.otrkey-Dateien in {src}')
                prot.zeile('Keine .otr2/.otrkey-Dateien in %s' % src)
                prot.schluss(0, 0, 0)
                return EXIT_KEINE_DATEIEN
        else:
            raise OtrCliError(f'Quellordner/-datei nicht gefunden: {src}')

    sess = _session()
    jwt = ticket = priv = pub_b64 = user = None
    ticket_exp = 0

    def ensure_otr2_session():
        nonlocal jwt, ticket, priv, pub_b64, user, ticket_exp
        if priv is None:
            priv, pub_b64 = gen_client_keypair()
        if jwt is None:
            print('Login ...', end=' ', flush=True)
            data = login(sess, args.api_base, args.email, args.password)
            jwt, user = data['token'], data.get('user', {})
            print(f'OK (uid={user.get("id","?")})')
        if ticket is None or time.time() > ticket_exp - 30:
            t = get_ticket(sess, args.api_base, jwt)
            ticket, ticket_exp = t['ticket'], t.get('exp', time.time() + 3000)

    done = skipped = errors = 0
    total = len(otr2_files) + len(otrkey_files)
    print(f'{total} Datei(en): {len(otr2_files)} .otr2, {len(otrkey_files)} .otrkey')
    print(f'Ziel: {dst}')
    print()

    kein_recht = [False]   # Merker fuer den Rueckgabewert (Feedback #1566 Punkt 5)
    # ── .otr2 ──
    for i, path in enumerate(otr2_files, 1):
        print(f'[{i}/{total}] {path.name}')
        out = dst / (path.stem + '.mp4')
        if out.exists() and not args.force:
            print('    Existiert bereits -- uebersprungen (--force zum Ueberschreiben).')
            prot.datei(path.name, 'uebersprungen', 'Ausgabedatei existiert bereits')
            skipped += 1
            continue
        try:
            ensure_otr2_session()
            hdr = read_otr2_header(path)
            # ★15.08.2026 (#1945): VOR dem Schluesselabruf pruefen, ob die Quelldatei
            # ueberhaupt vollstaendig ist. Ein Schluesselabruf kostet eine Dekodierung -
            # auch dann, wenn das Entschluesseln danach an der kaputten Datei scheitert.
            _voll, _ist, _soll = otr2_vollstaendigkeit(path, hdr)
            if not _voll and not args.fehler_ignorieren:
                print(f'    ★ QUELLDATEI UNVOLLSTAENDIG -- kein Schluessel angefordert.')
                print(f'      vorhanden: {_ist/1e6:.1f} MB von {_soll/1e6:.1f} MB '
                      f'({100.0*_ist/max(1,_soll):.1f} %).')
                print( '      Der Download ist abgebrochen. Bitte laden Sie die Datei erneut '
                       'herunter; es wurde KEINE Dekodierung abgezogen.')
                print( '      (Wer den unvollstaendigen Teil trotzdem retten will: '
                       '--fehler-ignorieren -- das kostet dann eine Dekodierung.)')
                prot.datei(path.name, 'uebersprungen',
                           'Quelldatei unvollstaendig (%d von %d Byte), kein Schluesselabruf'
                           % (_ist, _soll))
                skipped += 1
                continue
            cek = fetch_cek_otr2(sess, args.keyserver, hdr.rec, ticket, priv, pub_b64)
            t0 = time.perf_counter()
            stats = decrypt_file(str(path), str(out), cek, progress_cb=progress_bar,
                                 bei_abbruch=('weiter' if args.fehler_ignorieren else 'fehler'),
                                 hinweis_cb=_schreib_hinweis)
            elapsed = time.perf_counter() - t0
            if stats.get('abgeschnitten'):
                print(f'\n    ★ QUELLDATEI UNVOLLSTAENDIG: es waren nur '
                      f'{stats["dst_size"]/1e6:.1f} von {stats["erwartet"]/1e6:.1f} MB vorhanden '
                      f'({100.0*stats["dst_size"]/max(1,stats["erwartet"]):.1f} %).')
                print('      Das Ergebnis wurde trotzdem behalten (--fehler-ignorieren). Es '
                      'laesst sich meist noch abspielen bzw. mit ffmpeg reparieren,')
                print('      der Schluss fehlt aber. Wer die vollstaendige Sendung will, laedt '
                      'die Quelldatei bitte erneut herunter.')
            if not args.no_watermark and user.get('id') is not None:
                try:
                    # ★12.08.2026: dateibasiert statt read_bytes()/write_bytes() - das hielt die
                    # fertige MP4 dreifach im Speicher (bei 4 GB ueber 12 GB). Jetzt wird nur die
                    # moov-Box geladen.
                    embed_watermark_datei(out, int(user['id']), hdr.rec)
                except Exception as e:
                    print(f'\n    Wasserzeichen fehlgeschlagen (ignoriert): {e}')
            print(f'\n    OK  {out.name}  {stats["dst_size"]/1e6:.1f} MB  {elapsed:.1f}s')
            prot.datei(path.name, 'ok', '%.1f MB in %.1fs%s' % (
                stats['dst_size']/1e6, elapsed,
                ', UNVOLLSTAENDIG gerettet' if stats.get('abgeschnitten') else ''))
            done += 1
            if args.delete_source:
                try:
                    path.unlink()
                    print(f'    Quelldatei geloescht: {path.name}')
                    # ★13.08.2026 (Feedback #1888 Punkt 3): stand nur im Fenster, nicht im
                    # Protokoll. Eine Loeschung ist genau das, was man spaeter nachlesen will.
                    prot.zeile('geloescht  %s (Quelldatei, --delete-source)' % path.name)
                except OSError as e:
                    print(f'    Quelldatei konnte nicht geloescht werden (ignoriert): {e}')
        except OtrCliError as e:
            print(f'\n    FEHLER: {e}')
            prot.datei(path.name, 'FEHLER', str(e))
            if 'Kein Recht' in str(e):
                kein_recht[0] = True
            errors += 1
            if out.exists():
                out.unlink()
        except Exception as e:
            print(f'\n    FEHLER (unerwartet): {e}')
            prot.datei(path.name, 'FEHLER', repr(e))
            errors += 1
            if out.exists():
                out.unlink()

    # ── .otrkey ──
    for i, path in enumerate(otrkey_files, 1):
        idx = len(otr2_files) + i
        print(f'[{idx}/{total}] {path.name}')
        out = dst / otrkey_output_name(path.name)
        if out.exists() and not args.force:
            print('    Existiert bereits -- uebersprungen (--force zum Ueberschreiben).')
            prot.datei(path.name, 'uebersprungen', 'Ausgabedatei existiert bereits')
            skipped += 1
            continue
        try:
            fields = parse_otrkey_header(path)
            fn, oh = fields.get('FN', path.name), fields.get('OH', '')
            if not oh:
                raise OtrCliError('OTR-Hash nicht aus Header lesbar.')
            key_hex = fetch_key_otrkey(sess, args.quelle_url, args.email,
                                        args.password, fn, oh)
            t0 = time.perf_counter()
            size = decode_otrkey_file(path, out, key_hex)
            elapsed = time.perf_counter() - t0
            print(f'    OK  {out.name}  {size/1e6:.1f} MB  {elapsed:.1f}s')
            prot.datei(path.name, 'ok', '%.1f MB in %.1fs' % (size/1e6, elapsed))
            done += 1
            if args.delete_source:
                try:
                    path.unlink()
                    print(f'    Quelldatei geloescht: {path.name}')
                    # ★13.08.2026 (Feedback #1888 Punkt 3): stand nur im Fenster, nicht im
                    # Protokoll. Eine Loeschung ist genau das, was man spaeter nachlesen will.
                    prot.zeile('geloescht  %s (Quelldatei, --delete-source)' % path.name)
                except OSError as e:
                    print(f'    Quelldatei konnte nicht geloescht werden (ignoriert): {e}')
        except OtrCliError as e:
            print(f'    FEHLER: {e}')
            prot.datei(path.name, 'FEHLER', str(e))
            if 'Kein Recht' in str(e):
                kein_recht[0] = True
            errors += 1
            if out.exists():
                out.unlink()
        except Exception as e:
            print(f'    FEHLER (unerwartet): {e}')
            prot.datei(path.name, 'FEHLER', repr(e))
            errors += 1
            if out.exists():
                out.unlink()

    print()
    print(f'Fertig: {done} entschluesselt, {skipped} uebersprungen, {errors} Fehler.')
    prot.schluss(done, skipped, errors)
    if errors and kein_recht[0] and done == 0:
        return EXIT_KEIN_RECHT
    return EXIT_FEHLER if errors else EXIT_OK


def _app_dir() -> Path:
    """Ordner der laufenden .exe (frozen) bzw. dieses Skripts -- dort wird otr_login.txt
    gesucht/angelegt, damit sie bei einer Verknuepfung/einem Doppelklick zuverlaessig
    gefunden wird (unabhaengig vom Arbeitsverzeichnis, das bei Verknuepfungen variiert)."""
    if getattr(sys, 'frozen', False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent


CONFIG_FILE = _app_dir() / 'otr_login.txt'
INI_FILE = _app_dir() / 'otr_decoder.ini'

# ── Rueckgabewerte (ERRORLEVEL) ──────────────────────────────────────────────
# ★13.08.2026 CRYPTOBOT (Feedback #1566 Punkt 5): bisher gab es nur 0 und 1, damit
# liess sich in einem Skript nicht unterscheiden, WARUM ein Lauf scheiterte.
# Die Werte sind in --help beschrieben und aendern sich nicht mehr rueckwaerts.
EXIT_OK            = 0   # alles entschluesselt
EXIT_FEHLER        = 1   # allgemeiner Fehler / mindestens eine Datei misslungen
EXIT_ZUGANG        = 2   # keine/falsche Zugangsdaten
EXIT_KEINE_DATEIEN = 3   # nichts zu tun gefunden
EXIT_KEIN_RECHT    = 4   # Schluessel verweigert (kein Recht auf die Aufnahme)
EXIT_ABGEBROCHEN   = 5   # vom Nutzer abgebrochen (Strg+C)


def _load_config() -> dict:
    """Liest die Einstellungen. Zwei Dateien, INI hat Vorrang:

      otr_decoder.ini   [otr]-Abschnitt, Standard-INI-Format (Wunsch #1547/#1566)
      otr_login.txt     einfache key=value-Zeilen (bisheriges Format)

    ★13.08.2026: die INI kam auf Kundenwunsch dazu ("Keine TEXT-Datei bitte"), weil
    sich dort spaeter weitere Optionen unterbringen lassen. Die alte .txt wird
    WEITER gelesen - wer sie hat, muss nichts umstellen. Fehlt beides oder ist es
    unlesbar: leeres dict, NIE ein Fehler - Kommandozeile und Eingabe bleiben der
    massgebliche Weg.
    """
    cfg = {}
    try:
        for line in CONFIG_FILE.read_text(encoding='utf-8').splitlines():
            line = line.strip()
            if not line or line.startswith('#') or '=' not in line:
                continue
            k, v = line.split('=', 1)
            cfg[k.strip().lower()] = v.strip()
    except OSError:
        pass
    try:
        import configparser
        cp = configparser.ConfigParser()
        # Gross-/Kleinschreibung der Schluessel egal, Werte unveraendert lassen
        cp.optionxform = str.lower
        if cp.read(INI_FILE, encoding='utf-8'):
            for abschnitt in ('otr', 'OTR', 'DEFAULT'):
                if cp.has_section(abschnitt) or abschnitt == 'DEFAULT':
                    for k, v in cp[abschnitt].items():
                        if v.strip():
                            cfg[k.strip().lower()] = v.strip()
    except Exception:
        pass   # kaputte INI darf den Lauf nie verhindern
    return cfg


def _save_config(email, password, quellordner=None):
    lines = [f'email={email}', f'password={password}']
    if quellordner:
        lines.append(f'quellordner={quellordner}')
    try:
        CONFIG_FILE.write_text('\n'.join(lines) + '\n', encoding='utf-8')
        print(f'Gespeichert in {CONFIG_FILE.name} (liegt neben dem Programm) -- '
              f'naechstes Mal ohne erneute Eingabe.')
    except OSError as e:
        print(f'Konnte {CONFIG_FILE.name} nicht schreiben ({e}) -- Eingabe wird diesmal '
              f'trotzdem verwendet, muss aber beim naechsten Mal wieder erfolgen.')


class Protokoll:
    """Schreibt ein Sitzungsprotokoll mit Datum und Uhrzeit im Dateinamen.

    ★13.08.2026 CRYPTOBOT (Feedback #1566 Punkt 2): "Welche Datei wurde erfolgreich
    dekodiert und welche nicht und warum ist das so?" - genau das steht jetzt drin,
    eine Zeile je Datei, plus eine Zusammenfassung am Schluss. Ohne --protokoll
    passiert nichts (kein ungefragtes Schreiben in fremde Ordner).

    Faellt still auf "kein Protokoll" zurueck, wenn sich die Datei nicht anlegen
    laesst - ein nicht schreibbarer Ordner darf das Entschluesseln nie verhindern.
    """

    def __init__(self, ziel=None):
        self.pfad = None
        self.f = None
        if ziel is None:
            return
        p = Path(ziel)
        if p.is_dir() or str(ziel).endswith(('/', '\\')):
            p = p / time.strftime('otr_decoder_%Y-%m-%d_%H-%M-%S.log')
        try:
            p.parent.mkdir(parents=True, exist_ok=True)
            self.f = p.open('w', encoding='utf-8')
            self.pfad = p
            self.zeile('OTR CLI-Decoder %s' % __version__)
            self.zeile('Start: %s' % time.strftime('%Y-%m-%d %H:%M:%S'))
        except OSError as e:
            print('Protokoll konnte nicht angelegt werden (%s) - der Lauf geht '
                  'trotzdem weiter.' % e)
            self.f = None

    def zeile(self, text):
        if not self.f:
            return
        try:
            self.f.write('%s  %s\n' % (time.strftime('%H:%M:%S'), text))
            self.f.flush()
        except OSError:
            pass

    def datei(self, name, ergebnis, grund=''):
        self.zeile('%-9s %s%s' % (ergebnis.upper(), name, ('  -- ' + grund) if grund else ''))

    def schluss(self, done, skipped, errors):
        self.zeile('Ende: %s' % time.strftime('%Y-%m-%d %H:%M:%S'))
        self.zeile('Ergebnis: %d entschluesselt, %d uebersprungen, %d misslungen'
                   % (done, skipped, errors))
        if self.f:
            try:
                self.f.close()
            except OSError:
                pass
            print('Protokoll geschrieben: %s' % self.pfad)


def _dateien_per_dialog():
    """Oeffnet ein Dateiauswahl-Fenster und liefert die gewaehlten Pfade.

    ★12.08.2026 CRYPTOBOT (Forum BlackRaiden 21:34: "der Decoder: den kann ich
    anklicken wie ich will, es startet IMMER CMD"):
    Das Programm ist ein Konsolenprogramm und sucht Aufnahmen im EIGENEN Ordner.
    Wer es aus "Downloads" doppelklickt und seine .otrkey woanders liegen hat,
    tippt seine Zugangsdaten ein und bekommt danach "keine Dateien gefunden" --
    von aussen sieht das aus, als tue das Programm gar nichts. Genau dieser Fall
    bekommt jetzt ein Auswahlfenster statt einer Sackgasse.

    Faellt still auf [] zurueck, wenn es keine Oberflaeche gibt (Server ohne
    Bildschirm, tkinter nicht vorhanden) -- dann greift der bisherige Weg.
    """
    try:
        import tkinter
        from tkinter import filedialog
    except Exception:
        return []
    fenster = None
    try:
        fenster = tkinter.Tk()
        fenster.withdraw()
        try:
            fenster.attributes('-topmost', True)   # sonst oeffnet es HINTER der Konsole
        except Exception:
            pass
        namen = filedialog.askopenfilenames(
            title='OTR-Aufnahmen zum Entschluesseln auswaehlen',
            filetypes=[('OTR-Aufnahmen', '*.otrkey *.otr2'),
                       ('Nur .otrkey', '*.otrkey'),
                       ('Nur .otr2', '*.otr2'),
                       ('Alle Dateien', '*.*')])
        return [str(n) for n in (namen or ())]
    except Exception:
        return []
    finally:
        if fenster is not None:
            try:
                fenster.destroy()
            except Exception:
                pass


def _quelle_ist_leer(quellordner, pfade):
    """True, wenn nichts zu tun ist: keine Pfade uebergeben UND im Quellordner
    liegt keine passende Datei."""
    if pfade:
        return False
    src = Path(quellordner)
    if not src.is_dir():
        return not src.exists()
    return not (any(src.glob('*.otr2')) or any(src.glob('*.otrkey')))


def main():
    p = argparse.ArgumentParser(
        description='OTR CLI-Decoder (.otr2 + .otrkey) -- ein Login/Ordner fuer beliebig viele Dateien',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Beispiel:
  python otr_cli_decoder.py --email user@beispiel.de --password ***** \\
      --quellordner "C:\\Downloads" --zielordner "C:\\Videos"

Ohne --email/--password wird otr_login.txt (liegt neben dem Programm) gelesen,
bei Bedarf interaktiv nachgefragt (mit Angebot, es dort zu speichern) - passend
zum Doppelklick/Verknuepfung-Aufruf ohne Kommandozeile.

Dateien oder EIN Ordner koennen auch per Drag&Drop auf die .exe/Verknuepfung
gezogen werden, statt --quellordner zu tippen.

Einstellungsdatei (neben dem Programm), beides wird gelesen, INI hat Vorrang:
  otr_decoder.ini   [otr]
                    email = user@beispiel.de
                    password = *****
                    quellordner = C:\\Downloads
                    zielordner = C:\\Videos
  otr_login.txt     email=...  (bisheriges Format, funktioniert weiter)

Rueckgabewerte (ERRORLEVEL), fuer Skripte auswertbar:
  0  alles entschluesselt
  1  allgemeiner Fehler oder mindestens eine Datei misslungen
  2  keine oder falsche Zugangsdaten
  3  nichts zu tun gefunden (keine .otr2/.otrkey)
  4  kein Recht auf die Aufnahme (Schluessel verweigert), keine Datei gelungen
  5  vom Nutzer abgebrochen (Strg+C)

Version dieses Programms: """ + __version__ + """
        """)
    p.add_argument('pfade', nargs='*', help=argparse.SUPPRESS)
    p.add_argument('--email', help='OTR-Login-Email (sonst otr_login.txt / Eingabe)')
    p.add_argument('--password', help='OTR-Login-Passwort (sonst otr_login.txt / Eingabe)')
    p.add_argument('--quellordner', '--src', dest='quellordner', default='.',
                   help='Ordner mit .otr2/.otrkey-Dateien, oder Pfad zu einer einzelnen Datei '
                        '(weglassen = aktuelles Verzeichnis)')
    p.add_argument('--zielordner', '--dst', dest='zielordner',
                   help='Ausgabeordner (default: gleicher Ordner wie Quelle)')
    p.add_argument('--force', action='store_true', help='Vorhandene Ausgabedateien ueberschreiben')
    p.add_argument('--no-watermark', action='store_true',
                   help='Forensisches Wasserzeichen bei .otr2 NICHT einbetten')
    p.add_argument('--delete-source', action='store_true',
                   help='Erfolgreich entschluesselte .otr2/.otrkey-Quelldatei danach loeschen '
                        '(wie beim alten Decoder) - nur bei echtem Erfolg, NIE bei Fehler/Abbruch')
    p.add_argument('--version', '-v', action='version', version=f'otr_cli_decoder.py {__version__}')
    p.add_argument('--api-base', default=DEFAULT_API_BASE, help=argparse.SUPPRESS)
    p.add_argument('--keyserver', default=DEFAULT_KEYSERVER, help=argparse.SUPPRESS)
    p.add_argument('--quelle-url', default=DEFAULT_QUELLE_URL, help=argparse.SUPPRESS)
    p.add_argument('--no-update-check', action='store_true',
                    help='Automatischen Update-Check beim Start ueberspringen')
    p.add_argument('--kein-dialog', '--no-dialog', dest='kein_dialog', action='store_true',
                   help='Kein Dateiauswahl-Fenster oeffnen, auch wenn nichts gefunden wurde')
    p.add_argument('--fehler-ignorieren', '--ignore-errors', dest='fehler_ignorieren',
                   action='store_true',
                   help='Unvollstaendige Quelldateien so weit wie moeglich entschluesseln, '
                        'statt sie zu verwerfen (wie "decodieren und Fehler ignorieren" der '
                        'alten Decoder) - rettet abgebrochene Downloads')
    p.add_argument('--protokoll', '--log', dest='protokoll', nargs='?', const=str(_app_dir()),
                   help='Sitzungsprotokoll schreiben: je Datei Erfolg/Fehler samt Grund. '
                        'Ohne Angabe neben dem Programm, sonst in den angegebenen Ordner '
                        '(oder unter dem angegebenen Dateinamen). Der Name enthaelt Datum '
                        'und Uhrzeit.')
    p.add_argument('--nicht-warten', '--no-pause', dest='nicht_warten', action='store_true',
                   help='Am Ende NICHT auf die Eingabetaste warten (fuer Skripte/Aufgaben'
                        'planung)')
    args = p.parse_args()
    if getattr(args, 'nicht_warten', False):
        globals()['_NICHT_WARTEN'] = True

    # Als PyInstaller-exe (getattr(sys,'frozen',False)) uebernimmt otr_decoder_launcher.py
    # das Aktualisieren (Datei-Selbstersatz einer LAUFENDEN .exe geht unter Windows nicht) --
    # der Datei-basierte Selbst-Update-Weg hier ist nur fuer den reinen .py-Lauf gedacht und
    # wuerde in einer frozen exe ohnehin nur im Temp-Extraktionsordner herumschreiben.
    if not getattr(sys, 'frozen', False) and not args.no_update_check \
            and not os.environ.get('OTR_CLI_NO_REEXEC'):
        if self_update():
            os.environ['OTR_CLI_NO_REEXEC'] = '1'   # verhindert Exec-Schleife bei Schreibfehlern
            py = sys.executable or 'python3'
            os.execv(py, [py, str(Path(__file__).resolve())] + sys.argv[1:])

    # Zugangsdaten: --email/--password > otr_login.txt > interaktive Eingabe (nur wenn ein
    # Terminal dran haengt - beim Doppelklick der .exe ist das dank console=True der Fall).
    cfg = _load_config()
    if args.quellordner == '.' and not args.pfade and cfg.get('quellordner'):
        args.quellordner = cfg['quellordner']
    # ★13.08.2026 (Feedback #1888 Punkt 1): `zielordner` wurde aus der Einstellungsdatei
    # zwar GELESEN, aber nie angewandt - die Ausgabe landete weiter im Quellordner.
    # Reihenfolge wie ueberall sonst: Kommandozeile schlaegt Datei.
    if not args.zielordner and cfg.get('zielordner'):
        args.zielordner = cfg['zielordner']

    # ★12.08.2026: Doppelklick ohne Aufnahmen im Ordner -> Auswahlfenster statt Sackgasse.
    # Nur wenn wirklich ein Mensch davorsitzt (isatty) und nichts uebergeben wurde;
    # Automatisierung/Skripte laufen hier nie hinein und bleiben unveraendert.
    # ★Die Weiche haengt an "gar keine Argumente uebergeben" - NICHT allein an
    # isatty(). Grund, gemessen und nicht vermutet: unter Windows meldet
    # sys.stdin.isatty() auch fuer das Nullgeraet (NUL) True. Eine geplante
    # Aufgabe mit umgeleiteter Eingabe waere damit in ein MODALES Fenster
    # gelaufen und haette dort unbegrenzt gewartet - ein Haenger, den niemand
    # sieht. "Keine Argumente" trifft dagegen genau den Doppelklick: jede
    # Automatisierung uebergibt mindestens --quellordner oder --email, und
    # Drag&Drop uebergibt die Dateien selbst.
    if not args.kein_dialog and len(sys.argv) == 1 \
            and _quelle_ist_leer(args.quellordner, args.pfade):
        interaktiv = False
        try:
            interaktiv = sys.stdin.isatty()
        except Exception:
            pass
        if interaktiv:
            print(f'Im Ordner "{Path(args.quellordner).resolve()}" liegt keine '
                  f'.otrkey- oder .otr2-Datei.')
            print('Es oeffnet sich jetzt ein Fenster, in dem Sie Ihre Aufnahmen auswaehlen '
                  'koennen ...')
            gewaehlt = _dateien_per_dialog()
            if gewaehlt:
                args.pfade = gewaehlt
                print(f'{len(gewaehlt)} Datei(en) ausgewaehlt.')
            else:
                print()
                print('Es wurde nichts ausgewaehlt. So kommen Sie ans Ziel:')
                print('  * Legen Sie Ihre .otrkey-/.otr2-Dateien in denselben Ordner wie')
                print('    dieses Programm und starten Sie es erneut, ODER')
                print('  * ziehen Sie die Dateien (oder einen ganzen Ordner) mit der Maus')
                print('    auf otr_decoder_launcher.exe, ODER')
                print('  * starten Sie es mit Ordnerangabe, z.B.:')
                print('      otr_decoder_launcher.exe --quellordner "C:\\Users\\Ich\\Videos"')
                sys.exit(1)
    just_asked = False
    if not args.email:
        args.email = cfg.get('email') or None
    if not args.password:
        args.password = cfg.get('password') or None
    if not args.email or not args.password:
        # isatty() ist die Haupt-Weiche (getpass.getpass() kann bei umgeleitetem/nicht-
        # interaktivem stdin HAENGEN statt sauber EOFError zu werfen, je nach Plattform -
        # deshalb wird getpass() erst gar nicht versucht, wenn kein echtes Terminal dran
        # haengt). Der try/except bleibt als zweite Absicherung fuer input() (das bei EOF
        # zuverlaessig EOFError wirft) und fuer Strg+C waehrend der Eingabe.
        if not sys.stdin.isatty():
            print('FEHLER: keine Zugangsdaten (--email/--password fehlen, otr_login.txt '
                  f'nicht gefunden/unvollstaendig unter {CONFIG_FILE}, kein Terminal fuer '
                  'interaktive Eingabe).', file=sys.stderr)
            sys.exit(EXIT_ZUGANG)
        try:
            print('Keine gespeicherten Zugangsdaten gefunden - bitte einmalig eingeben:')
            if not args.email:
                args.email = input('OTR E-Mail: ').strip()
            if not args.password:
                args.password = _prompt_password('OTR Passwort: ')
            just_asked = True
        except (EOFError, KeyboardInterrupt):
            print()
            print('FEHLER: keine Zugangsdaten (--email/--password fehlen, otr_login.txt '
                  f'nicht gefunden/unvollstaendig unter {CONFIG_FILE}, und keine interaktive '
                  'Eingabe moeglich).', file=sys.stderr)
            sys.exit(EXIT_ZUGANG)
        if not args.email or not args.password:
            print('FEHLER: E-Mail/Passwort leer.', file=sys.stderr)
            sys.exit(EXIT_ZUGANG)
    if just_asked:
        try:
            antwort = input('Fuer naechstes Mal in otr_login.txt speichern? [j/N] ').strip().lower()
        except (EOFError, KeyboardInterrupt):
            antwort = ''
        if antwort in ('j', 'ja', 'y', 'yes'):
            _save_config(args.email, args.password)

    try:
        sys.exit(run(args))
    except KeyboardInterrupt:
        print('\nAbgebrochen.', file=sys.stderr)
        sys.exit(EXIT_ABGEBROCHEN)
    except OtrCliError as e:
        print(f'FEHLER: {e}', file=sys.stderr)
        sys.exit(EXIT_ZUGANG if 'Zugangsdaten' in str(e) or 'Login' in str(e) else EXIT_FEHLER)


if __name__ == '__main__':
    # CRYPTOBOT 2026-08-05 (Feedback buffalo75): main() beendet sich ueber
    # sys.exit() an mehreren Stellen - finally faengt Erfolg UND jeden
    # Fehlerpfad gleichermassen ab, ohne jede einzelne Stelle einzeln
    # anzufassen, und behaelt den urspruenglichen Exitcode bei.
    try:
        main()
    finally:
        # ★13.08.2026 (Feedback #1566 Punkt 4): die Pause laesst sich jetzt mit
        # --nicht-warten abschalten. Ohne Terminal (Skript/Aufgabenplanung) kam sie
        # ohnehin nie - der Schalter ist fuer den Fall, dass jemand das Programm aus
        # einem Stapelverarbeitungsskript MIT Konsole aufruft und nicht warten will.
        if _own_console_window() and not globals().get('_NICHT_WARTEN'):
            try: input('\nZum Beenden Enter druecken ...')
            except (EOFError, KeyboardInterrupt): pass
