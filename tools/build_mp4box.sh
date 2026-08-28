#!/bin/sh
# Statisches GPAC-MP4Box für linux-musl aarch64 (Zig).
# x86_64 behält das bewährte i386-Binary (GPAC 0.5.1) unter app/bin/mp4box.
# Voraussetzung: zig, llvm-ar/strip (Homebrew: zig, llvm@21)
# Quelle: https://github.com/gpac/gpac  Tag v2.4.0
#
# Aufruf: ./build_mp4box.sh
# schreibt nach Build/ui/app/binAArch64/mp4box

set -e
REPO_ROOT="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
SRC="${GPAC_SRC:-/tmp/gpac-synotr}"
ZLIB_SRC="${ZLIB_SRC:-/tmp/zlib-synotr}"
TAG="${GPAC_TAG:-v2.4.0}"
ZLIB_TAG="${ZLIB_TAG:-v1.3.1}"
ZIG="${ZIG:-$(command -v zig)}"
AR="${AR:-/opt/homebrew/opt/llvm@21/bin/llvm-ar}"
RANLIB="${RANLIB:-/opt/homebrew/opt/llvm@21/bin/llvm-ranlib}"
STRIP="${STRIP:-/opt/homebrew/opt/llvm@21/bin/llvm-strip}"
NCPU="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

if [ -z "$ZIG" ] || [ ! -x "$ZIG" ]; then
    echo "zig fehlt (brew install zig)" >&2
    exit 1
fi
if [ ! -x "$AR" ]; then
    echo "llvm-ar fehlt: $AR" >&2
    exit 1
fi

if [ ! -d "$ZLIB_SRC/.git" ]; then
    git clone --depth 1 --branch "$ZLIB_TAG" https://github.com/madler/zlib.git "$ZLIB_SRC"
fi
git -C "$ZLIB_SRC" fetch --depth 1 origin "refs/tags/${ZLIB_TAG}:refs/tags/${ZLIB_TAG}" 2>/dev/null || true
git -C "$ZLIB_SRC" checkout -f "$ZLIB_TAG"
git -C "$ZLIB_SRC" reset --hard "$ZLIB_TAG"

if [ ! -d "$SRC/.git" ]; then
    git clone --depth 1 --branch "$TAG" https://github.com/gpac/gpac.git "$SRC"
fi
git -C "$SRC" fetch --depth 1 origin "refs/tags/${TAG}:refs/tags/${TAG}" 2>/dev/null || true
git -C "$SRC" checkout -f "$TAG"
git -C "$SRC" reset --hard "$TAG"
git -C "$SRC" clean -fdx

arch=aarch64
prefix="/tmp/gpac-synotr-prefix-$arch"
zlibp="/tmp/zlib-synotr-prefix-$arch"
rm -rf "$prefix" "$zlibp"
mkdir -p "$zlibp" "$prefix"

echo ">>> zlib $arch"
(
    cd "$ZLIB_SRC"
    make distclean >/dev/null 2>&1 || true
    CC="$ZIG cc -target ${arch}-linux-musl" AR="$AR" RANLIB="$RANLIB" \
        CHOST="${arch}-linux" ./configure --static --prefix="$zlibp"
    make -j "$NCPU"
    make install
)

echo ">>> GPAC $arch"
WRAP="/tmp/gpac-zigwrap"
mkdir -p "$WRAP"
cat > "$WRAP/cc-$arch" << EOF
#!/bin/sh
exec $ZIG cc -target ${arch}-linux-musl -static "\$@"
EOF
chmod +x "$WRAP/cc-$arch"

(
    cd "$SRC"
    CC="$WRAP/cc-$arch" AR="$AR" RANLIB="$RANLIB" \
        ./configure \
            --prefix="$prefix" \
            --static-bin \
            --target-os=Linux \
            --cpu="$arch" \
            --use-zlib="$zlibp" \
            --use-freetype=no \
            --use-png=no \
            --use-ssl=no \
            --use-ffmpeg=no \
            --use-sdl=no \
            --use-jpeg=no \
            --use-faad=no \
            --use-mad=no \
            --use-xvid=no \
            --use-ogg=no \
            --use-vorbis=no \
            --use-theora=no \
            --extra-cflags="-I${zlibp}/include" \
            --extra-ldflags="-L${zlibp}/lib -static"
    # Zig/lld: keine GNU-ld-Flags
    sed -i.bak -e 's/-Wl,--warn-common//g' -e 's/-Wl,-z,defs//g' config.mak
    make -j "$NCPU" -C src
    make -j "$NCPU" -C applications/mp4box
)

BIN="$SRC/bin/gcc/MP4Box"
"$STRIP" "$BIN"
file "$BIN"
mkdir -p "$REPO_ROOT/Build/ui/app/binAArch64"
cp "$BIN" "$REPO_ROOT/Build/ui/app/binAArch64/mp4box"
chmod 755 "$REPO_ROOT/Build/ui/app/binAArch64/mp4box"
echo "fertig: binAArch64/mp4box (aarch64)"
