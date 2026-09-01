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
    editor_state_from_cutlist,
    is_private_cutlist,
    parse_cutlist,
    write_cutlist,
)
from synotr_cuteditor.media import parse_keyframe_times  # noqa: E402
from synotr_cuteditor.paths import CutEditorConfig  # noqa: E402
from synotr_cuteditor.waiting import deco_play_mp4, item_for, list_waiting  # noqa: E402


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
            self.assertEqual(data["info"]["Author"], "me")
            self.assertIn("synOTR Eigengebrauch", data["info"]["UserComment"])
            self.assertEqual(data["info"]["EPGError"], "0")
            self.assertEqual(data["meta"]["GeneratedBy"], "synOTR CutEditor")
            self.assertEqual(len(data["cuts"]), 1)
            self.assertEqual(data["cuts"][0]["StartFrame"], "25")
            self.assertTrue(is_private_cutlist(p))

    def test_info_section_flags(self):
        with tempfile.TemporaryDirectory() as td:
            p = os.path.join(td, "b.mp4.cutlist")
            write_cutlist(
                p,
                apply_to="b.mp4",
                size_bytes=1,
                fps=25.0,
                keeps=[{"start": 0.0, "duration": 1.0}],
                author="nick",
                private=False,
                aspect="16:9",
                info={
                    "UserComment": "Werbung raus",
                    "RatingByAuthor": "4",
                    "EPGError": "1",
                    "SuggestedMovieName": "Sendung",
                    "MissingEnding": 1,
                },
            )
            with open(p, encoding="utf-8") as fh:
                data = parse_cutlist(fh.read())
            self.assertEqual(data["general"]["DisplayAspectRatio"], "16:9")
            self.assertEqual(data["info"]["UserComment"], "Werbung raus")
            self.assertEqual(data["info"]["RatingByAuthor"], "4")
            self.assertEqual(data["info"]["EPGError"], "1")
            self.assertEqual(data["info"]["MissingEnding"], "1")
            self.assertEqual(data["info"]["SuggestedMovieName"], "Sendung")
            self.assertFalse(is_private_cutlist(p))

    def test_editor_state_from_cutlist(self):
        text = (
            "[General]\nFramesPerSecond=25\nApplyToFile=a.mp4\n"
            "[Cut0]\nStart=10.5\nDuration=3\nStartFrame=262\nDurationFrames=75\n"
            "[Info]\nAuthor=x\nEPGError=1\n"
        )
        st = editor_state_from_cutlist(text)
        self.assertEqual(len(st["keeps"]), 1)
        self.assertEqual(st["keeps"][0]["start"], 10.5)
        self.assertEqual(st["keeps"][0]["duration"], 3.0)
        self.assertEqual(st["info"]["Author"], "x")
        self.assertEqual(st["info"]["EPGError"], "1")

    def test_parse_keyframe_times(self):
        text = "0.000000\n1.041667,1.041667\n1.041667\nn/a\n2.5\n"
        times = parse_keyframe_times(text)
        self.assertEqual(times, [0.0, 1.041667, 2.5])


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
            self.assertEqual(names, ["unset.HQ.mp4", "wait.HQ.mp4"])

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

    def test_item_local_cutlist(self):
        with tempfile.TemporaryDirectory() as td:
            cfg = self._env(td, "all_uncut", "off")
            it = item_for(cfg, "haslocal.HQ.mp4")
            self.assertTrue(it["has_local"])
            self.assertTrue(it["local_cutlist"].endswith("haslocal.HQ.mp4.cutlist"))

    def test_remuxed_mp4_in_deco(self):
        with tempfile.TemporaryDirectory() as td:
            cfg = self._env(td, "miss_both", "off")
            deco = cfg.deco_dir
            os.remove(os.path.join(deco, "film.mpg.HQ.avi"))
            with open(os.path.join(deco, "film.mpg.HQ.mp4"), "wb") as fh:
                fh.write(b"m" * 10)
            names = [i["file"] for i in list_waiting(cfg)]
            self.assertIn("film.mpg.HQ.mp4", names)
            it = item_for(cfg, "film.mpg.HQ.mp4")
            self.assertTrue(it["private"])
            self.assertFalse(it["needs_remux"])
            self.assertTrue(it["play_path"].endswith("film.mpg.HQ.mp4"))
            self.assertTrue((deco_play_mp4(cfg, "film.mpg.HQ.avi") or "").endswith("film.mpg.HQ.mp4"))
            self.assertTrue((deco_play_mp4(cfg, "film.mpg.HQ.mp4") or "").endswith("film.mpg.HQ.mp4"))
            via_avi = item_for(cfg, "film.mpg.HQ.avi")
            self.assertIsNotNone(via_avi)
            self.assertFalse(via_avi["needs_remux"])
            self.assertTrue(via_avi["play_path"].endswith("film.mpg.HQ.mp4"))

    def test_clear_frame_cache(self):
        with tempfile.TemporaryDirectory() as td:
            cfg = CutEditorConfig(deco_dir=td, sqlite_path="", workdir=td)
            cache = cfg.frame_cache_dir()
            os.makedirs(cache)
            with open(os.path.join(cache, "a.mp4_w160_1.000.jpg"), "wb") as fh:
                fh.write(b"x")
            self.assertEqual(cfg.clear_frame_cache(), 1)
            self.assertFalse(os.path.isdir(cache))
            self.assertEqual(cfg.clear_frame_cache(), 0)


if __name__ == "__main__":
    unittest.main()
