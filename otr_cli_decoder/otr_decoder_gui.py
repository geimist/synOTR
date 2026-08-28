#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
otr_decoder_gui.py -- grafische Oberflaeche fuer otr_cli_decoder.py (Linux/Mac/Windows)

Forum-Wunsch (asdfaejtzk, 09.08.2026): ein "dynamischer" Offline-Decoder mit GUI statt
Kommandozeile. Baut bewusst NICHT eigene Krypto/Netzwerk-Logik - importiert dieselben,
bereits produktiv genutzten Funktionen aus otr_cli_decoder.py/otr2lib.py/otr2_watermark.py
(muessen im selben Ordner liegen, wie beim CLI-Decoder auch). Nur die Bedienung ist neu.

Abhaengigkeiten: Tkinter gehoert bei den meisten Python-Installationen bereits dazu
(Windows/Mac-Installer von python.org haben es immer dabei). Auf manchen Linux-
Distributionen muss es separat nachinstalliert werden:
  Debian/Ubuntu:  sudo apt install python3-tk
  Fedora:         sudo dnf install python3-tkinter
  Arch:           sudo pacman -S tk
Sonst wie der CLI-Decoder: python3 -m pip install cryptography
(★13.08.2026: 'requests' wird NICHT mehr gebraucht - der Decoder nutzt urllib aus der
Standardbibliothek. Ein Paket weniger, das an PEP 668 scheitern kann.)

Start:  python otr_decoder_gui.py
"""
import os
import queue
import sys
import threading
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

try:
    from otr_cli_decoder import (
        DEFAULT_API_BASE, DEFAULT_KEYSERVER, DEFAULT_QUELLE_URL,
        OtrCliError, _load_config, _save_config, _session,
        fetch_cek_otr2, fetch_key_otrkey, gen_client_keypair, get_ticket,
        login, otrkey_output_name, parse_otrkey_header, read_otr2_header,
        otr2_vollstaendigkeit,
    )
    from otr2lib import decrypt_file
    from otr2_watermark import embed_watermark, embed_watermark_datei
    from otrkey_blowfish import otr_ecb_decrypt  # noqa: F401  (indirekt ueber decode_otrkey_file gebraucht)
    from otr_cli_decoder import decode_otrkey_file
except ImportError as e:
    root = tk.Tk(); root.withdraw()
    messagebox.showerror(
        "otr_decoder_gui.py",
        "Konnte otr_cli_decoder.py/otr2lib.py/otr2_watermark.py/otrkey_blowfish.py nicht "
        "laden. Diese Datei muss im SELBEN Ordner liegen wie die anderen vier "
        "(gleiches Download-Paket wie der bisherige Kommandozeilen-Decoder).\n\n"
        "Fehler: %s" % e,
    )
    sys.exit(1)


class DecoderGUI:
    def __init__(self, root):
        self.root = root
        root.title("OTR Decoder")
        root.geometry("720x560")

        self.queue = queue.Queue()
        self.worker = None
        self.stop_requested = False

        cfg = _load_config()

        pad = {"padx": 8, "pady": 4}

        frm_login = ttk.LabelFrame(root, text="1 · Zugangsdaten")
        frm_login.pack(fill="x", **pad)
        ttk.Label(frm_login, text="E-Mail:").grid(row=0, column=0, sticky="e", **pad)
        self.email_var = tk.StringVar(value=cfg.get("email", ""))
        ttk.Entry(frm_login, textvariable=self.email_var, width=35).grid(row=0, column=1, sticky="w", **pad)
        ttk.Label(frm_login, text="Passwort:").grid(row=0, column=2, sticky="e", **pad)
        self.pw_var = tk.StringVar(value=cfg.get("password", ""))
        ttk.Entry(frm_login, textvariable=self.pw_var, width=25, show="*").grid(row=0, column=3, sticky="w", **pad)
        self.save_login_var = tk.BooleanVar(value=False)
        ttk.Checkbutton(frm_login, text="Fuer naechstes Mal speichern (otr_login.txt)",
                         variable=self.save_login_var).grid(row=1, column=0, columnspan=4, sticky="w", **pad)

        frm_paths = ttk.LabelFrame(root, text="2 · Ordner")
        frm_paths.pack(fill="x", **pad)
        ttk.Label(frm_paths, text="Quelle:").grid(row=0, column=0, sticky="e", **pad)
        self.src_var = tk.StringVar(value=cfg.get("quellordner", str(Path.cwd())))
        ttk.Entry(frm_paths, textvariable=self.src_var, width=50).grid(row=0, column=1, sticky="we", **pad)
        ttk.Button(frm_paths, text="Durchsuchen ...", command=self.pick_src).grid(row=0, column=2, **pad)
        ttk.Label(frm_paths, text="Ziel:").grid(row=1, column=0, sticky="e", **pad)
        self.dst_var = tk.StringVar(value="")
        ttk.Entry(frm_paths, textvariable=self.dst_var, width=50).grid(row=1, column=1, sticky="we", **pad)
        ttk.Button(frm_paths, text="Durchsuchen ...", command=self.pick_dst).grid(row=1, column=2, **pad)
        ttk.Label(frm_paths, text="(Ziel leer lassen = gleicher Ordner wie Quelle)",
                  foreground="#666").grid(row=2, column=1, sticky="w", **pad)
        frm_paths.columnconfigure(1, weight=1)

        frm_opts = ttk.LabelFrame(root, text="3 · Optionen")
        frm_opts.pack(fill="x", **pad)
        self.force_var = tk.BooleanVar(value=False)
        ttk.Checkbutton(frm_opts, text="Vorhandene Ausgabedateien ueberschreiben (--force)",
                         variable=self.force_var).pack(anchor="w", **pad)
        self.no_watermark_var = tk.BooleanVar(value=False)
        ttk.Checkbutton(frm_opts, text="Kein Wasserzeichen bei .otr2 (--no-watermark)",
                         variable=self.no_watermark_var).pack(anchor="w", **pad)
        self.fehler_ignorieren_var = tk.BooleanVar(value=False)
        ttk.Checkbutton(frm_opts, text="Unvollstaendige Dateien so weit wie moeglich retten "
                                       "(--fehler-ignorieren)",
                         variable=self.fehler_ignorieren_var).pack(anchor="w", **pad)
        self.delete_source_var = tk.BooleanVar(value=False)
        ttk.Checkbutton(frm_opts, text="Quelldatei nach Erfolg loeschen (--delete-source)",
                         variable=self.delete_source_var).pack(anchor="w", **pad)

        frm_run = ttk.Frame(root)
        frm_run.pack(fill="x", **pad)
        self.start_btn = ttk.Button(frm_run, text="Entschluesseln starten", command=self.start)
        self.start_btn.pack(side="left", **pad)
        self.stop_btn = ttk.Button(frm_run, text="Abbrechen", command=self.stop, state="disabled")
        self.stop_btn.pack(side="left", **pad)
        self.progress = ttk.Progressbar(frm_run, mode="determinate")
        self.progress.pack(side="left", fill="x", expand=True, **pad)

        frm_log = ttk.LabelFrame(root, text="Verlauf")
        frm_log.pack(fill="both", expand=True, **pad)
        self.log_txt = tk.Text(frm_log, height=14, state="disabled", wrap="word")
        self.log_txt.pack(fill="both", expand=True, side="left", **pad)
        scroll = ttk.Scrollbar(frm_log, command=self.log_txt.yview)
        scroll.pack(side="right", fill="y")
        self.log_txt["yscrollcommand"] = scroll.set

        self.root.after(100, self._poll_queue)

    def pick_src(self):
        d = filedialog.askdirectory(title="Quellordner waehlen")
        if d:
            self.src_var.set(d)

    def pick_dst(self):
        d = filedialog.askdirectory(title="Zielordner waehlen")
        if d:
            self.dst_var.set(d)

    def log(self, msg):
        self.queue.put(("log", msg))

    def progress_update(self, done, total):
        self.queue.put(("progress", done, total))

    def _poll_queue(self):
        try:
            while True:
                item = self.queue.get_nowait()
                if item[0] == "log":
                    self.log_txt["state"] = "normal"
                    self.log_txt.insert("end", item[1] + "\n")
                    self.log_txt.see("end")
                    self.log_txt["state"] = "disabled"
                elif item[0] == "progress":
                    done, total = item[1], item[2]
                    self.progress["maximum"] = max(total, 1)
                    self.progress["value"] = done
                elif item[0] == "done":
                    self.start_btn["state"] = "normal"
                    self.stop_btn["state"] = "disabled"
                    self.progress["value"] = 0
        except queue.Empty:
            pass
        self.root.after(100, self._poll_queue)

    def start(self):
        if self.worker and self.worker.is_alive():
            return
        email = self.email_var.get().strip()
        password = self.pw_var.get()
        src = self.src_var.get().strip()
        if not email or not password:
            messagebox.showerror("OTR Decoder", "Bitte E-Mail und Passwort eingeben.")
            return
        if not src or not Path(src).exists():
            messagebox.showerror("OTR Decoder", "Quellordner nicht gefunden.")
            return
        if self.save_login_var.get():
            try:
                _save_config(email, password, src)
            except Exception:
                pass
        self.stop_requested = False
        self.start_btn["state"] = "disabled"
        self.stop_btn["state"] = "normal"
        self.log_txt["state"] = "normal"
        self.log_txt.delete("1.0", "end")
        self.log_txt["state"] = "disabled"
        self.worker = threading.Thread(target=self._run_worker, args=(
            email, password, src, self.dst_var.get().strip() or None,
            self.force_var.get(), self.no_watermark_var.get(), self.delete_source_var.get(),
        ), daemon=True)
        self.worker.start()

    def stop(self):
        self.stop_requested = True
        self.log("Abbruch angefordert - wird nach der aktuellen Datei gestoppt ...")

    def _run_worker(self, email, password, quellordner, zielordner, force, no_watermark, delete_source):
        try:
            src = Path(quellordner).expanduser().resolve()
            dst = Path(zielordner).expanduser().resolve() if zielordner else src
            dst.mkdir(parents=True, exist_ok=True)
            otr2_files = sorted(src.glob("*.otr2"))
            otrkey_files = sorted(src.glob("*.otrkey"))
            total = len(otr2_files) + len(otrkey_files)
            if not total:
                self.log("Keine .otr2/.otrkey-Dateien in %s gefunden." % src)
                self.queue.put(("done",))
                return
            self.log("%d Datei(en): %d .otr2, %d .otrkey" % (total, len(otr2_files), len(otrkey_files)))

            sess = _session()
            jwt = ticket = priv = pub_b64 = user = None
            ticket_exp = 0

            def ensure_otr2_session():
                nonlocal jwt, ticket, priv, pub_b64, user, ticket_exp
                if priv is None:
                    priv, pub_b64 = gen_client_keypair()
                if jwt is None:
                    self.log("Login ...")
                    data = login(sess, DEFAULT_API_BASE, email, password)
                    jwt, user = data["token"], data.get("user", {})
                    self.log("Login OK (uid=%s)" % user.get("id", "?"))
                if ticket is None or __import__("time").time() > ticket_exp - 30:
                    t = get_ticket(sess, DEFAULT_API_BASE, jwt)
                    ticket, ticket_exp = t["ticket"], t.get("exp", __import__("time").time() + 3000)

            done = skipped = errors = 0
            idx = 0
            for path in otr2_files:
                idx += 1
                if self.stop_requested:
                    self.log("Abgebrochen.")
                    break
                self.log("[%d/%d] %s" % (idx, total, path.name))
                out = dst / (path.stem + ".mp4")
                if out.exists() and not force:
                    self.log("    Existiert bereits - uebersprungen.")
                    skipped += 1
                    continue
                try:
                    ensure_otr2_session()
                    hdr = read_otr2_header(path)
                    # ★15.08.2026 (#1945): dieselbe Sperre wie in der Kommandozeilenfassung -
                    # eine unvollstaendig geladene Datei kostet sonst eine Dekodierung, obwohl
                    # das Entschluesseln danach zwangslaeufig scheitert.
                    _voll, _ist, _soll = otr2_vollstaendigkeit(path, hdr)
                    if not _voll and not self.fehler_ignorieren_var.get():
                        self.log("    UNVOLLSTAENDIG: nur %.1f von %.1f MB (%.1f %%) - "
                                 "kein Schluessel angefordert, keine Dekodierung abgezogen."
                                 % (_ist / 1e6, _soll / 1e6, 100.0 * _ist / max(1, _soll)))
                        self.log("    Bitte die Datei erneut herunterladen. Zum Retten des "
                                 "Bruchstuecks: Haekchen 'Fehler ignorieren' setzen.")
                        skipped += 1
                        continue
                    cek = fetch_cek_otr2(sess, DEFAULT_KEYSERVER, hdr.rec, ticket, priv, pub_b64)
                    stats = decrypt_file(str(path), str(out), cek,
                                         progress_cb=self.progress_update,
                                         bei_abbruch=('weiter' if self.fehler_ignorieren_var.get()
                                                      else 'fehler'))
                    if not no_watermark and user.get("id") is not None:
                        try:
                            # ★13.08.2026: dateibasiert statt read_bytes()/write_bytes().
                            # Der alte Weg hielt die fertige MP4 dreifach im Speicher
                            # (bei 4 GB ueber 12 GB); jetzt wird nur die moov-Box geladen.
                            embed_watermark_datei(out, int(user["id"]), hdr.rec)
                        except Exception as e:
                            self.log("    Wasserzeichen fehlgeschlagen (ignoriert): %s" % e)
                    self.log("    OK  %s  %.1f MB" % (out.name, stats["dst_size"] / 1e6))
                    done += 1
                    if delete_source:
                        try:
                            path.unlink()
                            self.log("    Quelldatei geloescht: %s" % path.name)
                        except OSError as e:
                            self.log("    Quelldatei konnte nicht geloescht werden: %s" % e)
                except (OtrCliError, Exception) as e:
                    self.log("    FEHLER: %s" % e)
                    errors += 1
                    if out.exists():
                        out.unlink()

            for path in otrkey_files:
                idx += 1
                if self.stop_requested:
                    self.log("Abgebrochen.")
                    break
                self.log("[%d/%d] %s" % (idx, total, path.name))
                out = dst / otrkey_output_name(path.name)
                if out.exists() and not force:
                    self.log("    Existiert bereits - uebersprungen.")
                    skipped += 1
                    continue
                try:
                    fields = parse_otrkey_header(path)
                    fn, oh = fields.get("FN", path.name), fields.get("OH", "")
                    if not oh:
                        raise OtrCliError("OTR-Hash nicht aus Header lesbar.")
                    key_hex = fetch_key_otrkey(sess, DEFAULT_QUELLE_URL, email, password, fn, oh)
                    size = decode_otrkey_file(path, out, key_hex)
                    self.log("    OK  %s  %.1f MB" % (out.name, size / 1e6))
                    done += 1
                    if delete_source:
                        try:
                            path.unlink()
                            self.log("    Quelldatei geloescht: %s" % path.name)
                        except OSError as e:
                            self.log("    Quelldatei konnte nicht geloescht werden: %s" % e)
                except Exception as e:
                    self.log("    FEHLER: %s" % e)
                    errors += 1
                    if out.exists():
                        out.unlink()

            self.log("")
            self.log("Fertig: %d entschluesselt, %d uebersprungen, %d Fehler." % (done, skipped, errors))
        except Exception as e:
            self.log("FEHLER (unerwartet, Lauf abgebrochen): %s" % e)
        finally:
            self.queue.put(("done",))


def main():
    root = tk.Tk()
    DecoderGUI(root)
    root.mainloop()


if __name__ == "__main__":
    main()
