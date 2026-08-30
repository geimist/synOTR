#!/usr/bin/env python3
import os
import sqlite3
import sys
import tempfile
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, ROOT)

from synotr_cuteditor.cutlist import (  # noqa: E402
    cutlist_stem,
    is_private_cutlist,
    parse_cutlist,
    write_cutlist,
)
from synotr_cuteditor.paths import CutEditorConfig  # noqa: E402
from synotr_cuteditor.waiting import list_waiting  # noqa: E402


class CutlistTests(unittest.TestCase):
    def test_stem(self):
        self.assertEqual(cutlist_stem("Show_20.01.01_20-15.HQ.mp4"), "Show_20.01.01_20-15")
        self.assertEqual(cutlist_stem("Show.mpg.HQ.avi.cutlist"), "Show.mpg")

    def test_roundtrip_private(self):
        with tempfile.TemporaryDirectory() as td:
            p = os.path.join(td, "a.mp4.cutlist")
            write_cutlist(
                p,
                apply_to="a.mp4",
                size_bytes=99,
                fps=25.0,
                keeps=[{"start": 1.0, "duration": 2.0, "start_frame": 25, "duration_frames": 50}],
                author="me",
                private=True,
            )
            with open(p, encoding="utf-8") as fh:
                data = parse_cutlist(fh.read())
            self.assertEqual(data["general"]["Private"], "1")
            self.assertEqual(data["general"]["ApplyToFile"], "a.mp4")
            self.assertEqual(data["general"]["OriginalFileSizeBytes"], "99")
            self.assertEqual(len(data["cuts"]), 1)
            self.assertEqual(data["cuts"][0]["StartFrame"], "25")
            self.assertTrue(is_private_cutlist(p))


class WaitingTests(unittest.TestCase):
    def _env(self, td, queue="miss_both", otrkey="off"):
        deco = os.path.join(td, "deco")
        os.mkdir(deco)
        db = os.path.join(td, "t.sqlite")
        con = sqlite3.connect(db)
        con.execute(
            "CREATE TABLE raw (file_original TEXT, file_encrypted TEXT, file_source TEXT, "
            "OTRtitle TEXT, titel TEXT, sender TEXT, file_orig_size INTEGER, "
            "cutlist_online TEXT, file_editor_mp4 TEXT)"
        )
        def _w(p, data, mode="wb"):
            with open(p, mode) as fh:
                fh.write(data)

        _w(os.path.join(deco, "wait.HQ.mp4"), b"x" * 10)
        _w(os.path.join(deco, "haslocal.HQ.mp4"), b"y" * 10)
        _w(
            os.path.join(deco, "haslocal.HQ.mp4.cutlist"),
            "[General]\nApplyToFile=haslocal.HQ.mp4\nStart=0\n",
            "w",
        )
        _w(os.path.join(deco, "unset.HQ.mp4"), b"z" * 10)
        con.execute(
            "INSERT INTO raw (file_original, file_source, cutlist_online) VALUES (?,?,?)",
            ("wait.HQ.mp4", "otr2", "none"),
        )
        con.execute(
            "INSERT INTO raw (file_original, file_source, cutlist_online) VALUES (?,?,?)",
            ("haslocal.HQ.mp4", "otr2", "none"),
        )
        con.execute(
            "INSERT INTO raw (file_original, file_source, cutlist_online) VALUES (?,?,?)",
            ("unset.HQ.mp4", "otr2", "unset"),
        )
        _w(os.path.join(deco, "film.mpg.HQ.avi"), b"a" * 10)
        con.execute(
            "INSERT INTO raw (file_original, file_source, cutlist_online) VALUES (?,?,?)",
            ("film.mpg.HQ.avi", "otrkey", "none"),
        )
        con.commit()
        con.close()
        return CutEditorConfig(
            deco_dir=deco,
            sqlite_path=db,
            workdir=td,
            queue=queue,
            otrkey_mp4=otrkey,
        )

    def test_miss_both(self):
        with tempfile.TemporaryDirectory() as td:
            cfg = self._env(td, "miss_both", "off")
            names = [i["file"] for i in list_waiting(cfg)]
            self.assertEqual(names, ["wait.HQ.mp4"])

    def test_no_local(self):
        with tempfile.TemporaryDirectory() as td:
            cfg = self._env(td, "no_local", "off")
            names = [i["file"] for i in list_waiting(cfg)]
            self.assertIn("wait.HQ.mp4", names)
            self.assertIn("unset.HQ.mp4", names)
            self.assertNotIn("haslocal.HQ.mp4", names)

    def test_all_uncut(self):
        with tempfile.TemporaryDirectory() as td:
            cfg = self._env(td, "all_uncut", "off")
            names = [i["file"] for i in list_waiting(cfg)]
            self.assertIn("haslocal.HQ.mp4", names)
            self.assertNotIn("film.mpg.HQ.avi", names)

    def test_otrkey_switch(self):
        with tempfile.TemporaryDirectory() as td:
            cfg = self._env(td, "miss_both", "on")
            names = [i["file"] for i in list_waiting(cfg)]
            self.assertIn("film.mpg.HQ.avi", names)
            avi = [i for i in list_waiting(cfg) if i["file"].endswith(".avi")][0]
            self.assertTrue(avi["needs_remux"])
            self.assertTrue(avi["private"])


if __name__ == "__main__":
    unittest.main()
