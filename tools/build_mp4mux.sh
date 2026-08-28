#!/bin/sh
# Baut statisches Bento4 mp4mux für linux-musl x86_64 und aarch64 (Zig).
# Voraussetzung: zig, cmake, llvm-ar (Homebrew: zig, cmake, llvm@21)
# Quelle: https://github.com/axiomatic-systems/Bento4  Tag v1.6.0-641
#
# Aufruf: ./build_mp4mux.sh
# schreibt nach Build/ui/app/bin/mp4mux und Build/ui/app/binAArch64/mp4mux

set -e
REPO_ROOT="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
SRC="${BENTO4_SRC:-/tmp/bento4-synotr}"
TAG="${BENTO4_TAG:-v1.6.0-641}"
ZIG="${ZIG:-$(command -v zig)}"
AR="${AR:-/opt/homebrew/opt/llvm@21/bin/llvm-ar}"
RANLIB="${RANLIB:-/opt/homebrew/opt/llvm@21/bin/llvm-ranlib}"
STRIP="${STRIP:-/opt/homebrew/opt/llvm@21/bin/llvm-strip}"

if [ -z "$ZIG" ] || [ ! -x "$ZIG" ]; then
    echo "zig fehlt (brew install zig)" >&2
    exit 1
fi
if [ ! -x "$AR" ]; then
    echo "llvm-ar fehlt: $AR" >&2
    exit 1
fi

if [ ! -d "$SRC/.git" ]; then
    git clone --depth 1 --branch "$TAG" https://github.com/axiomatic-systems/Bento4.git "$SRC"
fi
# Immer den Tag + GOP-Split am IDR (nicht an POC=0 – avcut-Spleiße).
git -C "$SRC" fetch --depth 1 origin "refs/tags/${TAG}:refs/tags/${TAG}" 2>/dev/null || true
git -C "$SRC" checkout -f "$TAG"
git -C "$SRC" reset --hard "$TAG"
git -C "$SRC" clean -fd
patch -d "$SRC" -p1 --forward < "$REPO_ROOT/tools/mp4mux-idr-gop.patch"

WRAP="$SRC/zigwrap"
mkdir -p "$WRAP"
for arch in aarch64 x86_64; do
    cat > "$WRAP/cc-$arch" << EOF
#!/bin/sh
exec $ZIG cc -target ${arch}-linux-musl -static "\$@"
EOF
    cat > "$WRAP/cxx-$arch" << EOF
#!/bin/sh
exec $ZIG c++ -target ${arch}-linux-musl -static "\$@"
EOF
    chmod +x "$WRAP/cc-$arch" "$WRAP/cxx-$arch"
done

build_one() {
    arch="$1"
    bdir="$SRC/build-$arch"
    rm -rf "$bdir"
    cmake -S "$SRC" -B "$bdir" \
        -DCMAKE_SYSTEM_NAME=Linux \
        -DCMAKE_SYSTEM_PROCESSOR="$arch" \
        -DCMAKE_C_COMPILER="$WRAP/cc-$arch" \
        -DCMAKE_CXX_COMPILER="$WRAP/cxx-$arch" \
        -DCMAKE_AR="$AR" \
        -DCMAKE_RANLIB="$RANLIB" \
        -DCMAKE_C_COMPILER_WORKS=1 \
        -DCMAKE_CXX_COMPILER_WORKS=1 \
        -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES="" \
        -DBUILD_APPS=ON
    cmake --build "$bdir" --target mp4mux -j "$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
    "$STRIP" "$bdir/mp4mux"
    file "$bdir/mp4mux"
}

build_one aarch64
build_one x86_64

mkdir -p "$REPO_ROOT/Build/ui/app/bin" "$REPO_ROOT/Build/ui/app/binAArch64"
cp "$SRC/build-x86_64/mp4mux" "$REPO_ROOT/Build/ui/app/bin/mp4mux"
cp "$SRC/build-aarch64/mp4mux" "$REPO_ROOT/Build/ui/app/binAArch64/mp4mux"
chmod 755 "$REPO_ROOT/Build/ui/app/bin/mp4mux" "$REPO_ROOT/Build/ui/app/binAArch64/mp4mux"
echo "fertig: bin/mp4mux (x86_64) und binAArch64/mp4mux (aarch64)"
