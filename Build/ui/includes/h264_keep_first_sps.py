#!/usr/bin/env python3
"""Annex-B: alle SPS/PPS durch die Referenz ersetzen, vor IDR belassen.

Fallback wenn avcut am Spleiß doch andere SPS schreibt. MP4/avc1 speichert nur
die erste. SPS/PPS vor jedem IDR lassen – sonst fehlt stss bei mp4mux.
"""
import sys


def _starts(buf):
    i = 0
    n = len(buf)
    while i < n - 3:
        j = buf.find(b"\x00\x00\x01", i)
        if j < 0:
            return
        if j > 0 and buf[j - 1] == 0:
            yield j - 1, 4
            i = j + 3
        else:
            yield j, 3
            i = j + 3


def _nalus(buf):
    marks = list(_starts(buf))
    for idx, (pos, sc_len) in enumerate(marks):
        end = marks[idx + 1][0] if idx + 1 < len(marks) else len(buf)
        payload = buf[pos + sc_len : end]
        if not payload:
            continue
        yield pos, sc_len, payload, payload[0] & 0x1F


def _first_sps_pps(buf):
    sps = pps = None
    for _pos, sc_len, payload, ntype in _nalus(buf):
        sc = b"\x00\x00\x00\x01" if sc_len == 4 else b"\x00\x00\x01"
        if ntype == 7 and sps is None:
            sps = sc + payload
        elif ntype == 8 and pps is None:
            pps = sc + payload
        if sps is not None and pps is not None:
            break
    return sps, pps


def unify(src, dst, ref=None):
    data = open(src, "rb").read()
    ref_buf = open(ref, "rb").read() if ref else data
    sps, pps = _first_sps_pps(ref_buf)
    if sps is None or pps is None:
        raise SystemExit("keine SPS/PPS in der Referenz")
    replaced = 0
    injected = 0
    have_sps = False
    have_pps = False
    out = bytearray()
    for _pos, sc_len, payload, ntype in _nalus(data):
        sc = b"\x00\x00\x00\x01" if sc_len == 4 else b"\x00\x00\x01"
        if ntype == 7:
            out += sps
            have_sps = True
            replaced += 1
            continue
        if ntype == 8:
            out += pps
            have_pps = True
            replaced += 1
            continue
        if ntype == 5 and not (have_sps and have_pps):
            out += sps
            out += pps
            have_sps = True
            have_pps = True
            injected += 1
        out += sc
        out += payload
        if ntype in (1, 5):
            have_sps = False
            have_pps = False
    with open(dst, "wb") as fh:
        fh.write(out)
    print(
        "h264_keep_first_sps: %d SPS/PPS ersetzt, %d vor IDR eingefügt, %d Byte"
        % (replaced, injected, len(out))
    )


def main():
    if len(sys.argv) < 3:
        print("usage: h264_keep_first_sps.py IN.h264 OUT.h264 [REF.h264]", file=sys.stderr)
        raise SystemExit(2)
    ref = sys.argv[3] if len(sys.argv) > 3 else None
    unify(sys.argv[1], sys.argv[2], ref)


if __name__ == "__main__":
    main()
