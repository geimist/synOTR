#!/bin/sh
# Baut avcut 0.8 dynamisch gegen SynoCommunity ffmpeg8 (libavcodec.so.62 usw.).
# Cross-Compile mit Zig; Link-Zeit: SONAME-Stubs mit den von avcut genutzten Symbolen.
# Die Stubs werden nicht mitgeliefert. Laufzeit: /var/packages/ffmpeg8/target/lib
#
# Voraussetzung: zig, llvm-strip, llvm-nm (Homebrew: zig, llvm@21)
# Aufruf: ./build_avcut.sh
# schreibt nach Build/ui/app/bin/avcut64_ffmpeg8 und Build/ui/app/binAArch64/avcut
# (bin/avcut64 bleibt das statische 4.3.1-avcut für .otrkey)

set -e
REPO_ROOT="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
WORKDIR="${AVCUT_BUILD:-/tmp/avcut-synotr}"
AVCUT_TAG="${AVCUT_TAG:-v0.8}"
FFMPEG_TAG="${FFMPEG_TAG:-n8.1.2}"
ZIG="${ZIG:-$(command -v zig)}"
STRIP="${STRIP:-/opt/homebrew/opt/llvm@21/bin/llvm-strip}"
NM="${NM:-/opt/homebrew/opt/llvm@21/bin/llvm-nm}"
READELF="${READELF:-/opt/homebrew/opt/llvm@21/bin/llvm-readelf}"
GLIBC="${GLIBC:-2.27}"
RPATH="/var/packages/ffmpeg8/target/lib"

if [ -z "$ZIG" ] || [ ! -x "$ZIG" ]; then
    echo "zig fehlt (brew install zig)" >&2
    exit 1
fi
if [ ! -x "$STRIP" ]; then
    echo "llvm-strip fehlt: $STRIP" >&2
    exit 1
fi
if [ ! -x "$NM" ]; then
    echo "llvm-nm fehlt: $NM" >&2
    exit 1
fi

mkdir -p "$WORKDIR"
AVCUT_SRC="$WORKDIR/avcut"
FFMPEG_SRC="$WORKDIR/ffmpeg"

if [ ! -d "$AVCUT_SRC/.git" ]; then
    git clone --depth 1 --branch "$AVCUT_TAG" https://github.com/anyc/avcut.git "$AVCUT_SRC"
fi
# Immer v0.8 + Decoder-Thread-Patch (FFmpeg-Default threads=1).
git -C "$AVCUT_SRC" reset --hard HEAD
git -C "$AVCUT_SRC" clean -fd
patch -d "$AVCUT_SRC" -p1 --forward < "$REPO_ROOT/tools/avcut-decoder-threads.patch"
patch -d "$AVCUT_SRC" -p1 --forward < "$REPO_ROOT/tools/avcut-copy-extradata.patch"
if [ ! -d "$FFMPEG_SRC/.git" ]; then
    git clone --depth 1 --branch "$FFMPEG_TAG" https://github.com/FFmpeg/FFmpeg.git "$FFMPEG_SRC"
fi

if [ ! -f "$FFMPEG_SRC/libavutil/avconfig.h" ]; then
    cat > "$FFMPEG_SRC/libavutil/avconfig.h" << 'EOF'
#ifndef AVUTIL_AVCONFIG_H
#define AVUTIL_AVCONFIG_H
#define AV_HAVE_BIGENDIAN 0
#define AV_HAVE_FAST_UNALIGNED 1
#endif
EOF
fi
if [ ! -f "$FFMPEG_SRC/libavutil/ffversion.h" ]; then
    cat > "$FFMPEG_SRC/libavutil/ffversion.h" << EOF
#ifndef AVUTIL_FFVERSION_H
#define AVUTIL_FFVERSION_H
#define FFMPEG_VERSION "${FFMPEG_TAG#n}"
#endif
EOF
fi

# Objekt nur zum Einsammeln der libav-Symbole (Zuordnung zu den echten SONAMEs)
mkdir -p "$WORKDIR/obj" "$WORKDIR/stubs"
"$ZIG" cc -target "x86_64-linux-gnu.${GLIBC}" -c \
    -O2 -Wall \
    -DAVCUT_VERSION=\"0.8\" \
    -DAVCUT_PROFILE_DIRECTORY=\"/usr/share/avcut/profiles/\" \
    -I "$FFMPEG_SRC" \
    "$AVCUT_SRC/avcut.c" \
    -o "$WORKDIR/obj/avcut.o"

: > "$WORKDIR/stubs/codec.c"
: > "$WORKDIR/stubs/format.c"
: > "$WORKDIR/stubs/util.c"
"$NM" -u "$WORKDIR/obj/avcut.o" | awk '{print $NF}' | while IFS= read -r sym; do
    [ -z "$sym" ] && continue
    case "$sym" in
        avcodec_*|av_bsf_*|av_packet_*|av_new_packet)
            echo "void ${sym}(void) {}" >> "$WORKDIR/stubs/codec.c"
            ;;
        avformat_*|avio_*|av_dump_format|av_guess_frame_rate|av_interleaved_write_frame|av_read_frame|av_write_trailer)
            echo "void ${sym}(void) {}" >> "$WORKDIR/stubs/format.c"
            ;;
        av_*)
            echo "void ${sym}(void) {}" >> "$WORKDIR/stubs/util.c"
            ;;
    esac
done

echo "Stub-Symbole: codec=$(wc -l < "$WORKDIR/stubs/codec.c") format=$(wc -l < "$WORKDIR/stubs/format.c") util=$(wc -l < "$WORKDIR/stubs/util.c")"

link_avcut() {
    arch="$1"
    out="$2"
    sdir="$WORKDIR/stubs/$arch"
    rm -rf "$sdir"
    mkdir -p "$sdir"
    "$ZIG" cc -target "${arch}-linux-gnu.${GLIBC}" -shared -fPIC \
        -Wl,-soname,libavcodec.so.62 \
        -o "$sdir/libavcodec.so.62" "$WORKDIR/stubs/codec.c"
    "$ZIG" cc -target "${arch}-linux-gnu.${GLIBC}" -shared -fPIC \
        -Wl,-soname,libavformat.so.62 \
        -o "$sdir/libavformat.so.62" "$WORKDIR/stubs/format.c"
    "$ZIG" cc -target "${arch}-linux-gnu.${GLIBC}" -shared -fPIC \
        -Wl,-soname,libavutil.so.60 \
        -o "$sdir/libavutil.so.60" "$WORKDIR/stubs/util.c"
    ln -sf libavcodec.so.62 "$sdir/libavcodec.so"
    ln -sf libavformat.so.62 "$sdir/libavformat.so"
    ln -sf libavutil.so.60 "$sdir/libavutil.so"

    "$ZIG" cc -target "${arch}-linux-gnu.${GLIBC}" -O2 -Wall \
        -DAVCUT_VERSION=\"0.8\" \
        -DAVCUT_PROFILE_DIRECTORY=\"/usr/share/avcut/profiles/\" \
        -I "$FFMPEG_SRC" \
        "$AVCUT_SRC/avcut.c" \
        -o "$out" \
        -L "$sdir" \
        -Wl,--no-as-needed \
        -lavcodec -lavformat -lavutil \
        -Wl,-rpath,"$RPATH"
    "$STRIP" "$out"
    file "$out"
    if [ -x "$READELF" ]; then
        "$READELF" -d "$out" | grep -E 'NEEDED|RPATH|RUNPATH' || true
    fi
}

mkdir -p "$WORKDIR/out"
link_avcut x86_64 "$WORKDIR/out/avcut-x86_64"
link_avcut aarch64 "$WORKDIR/out/avcut-aarch64"

mkdir -p "$REPO_ROOT/Build/ui/app/bin" "$REPO_ROOT/Build/ui/app/binAArch64"
cp "$WORKDIR/out/avcut-x86_64" "$REPO_ROOT/Build/ui/app/bin/avcut64_ffmpeg8"
cp "$WORKDIR/out/avcut-aarch64" "$REPO_ROOT/Build/ui/app/binAArch64/avcut"
chmod 755 "$REPO_ROOT/Build/ui/app/bin/avcut64_ffmpeg8" "$REPO_ROOT/Build/ui/app/binAArch64/avcut"
ls -lh "$REPO_ROOT/Build/ui/app/bin/avcut64_ffmpeg8" "$REPO_ROOT/Build/ui/app/binAArch64/avcut"
echo "fertig: bin/avcut64_ffmpeg8 (x86_64) und binAArch64/avcut (aarch64), dynamisch gegen ffmpeg8"
