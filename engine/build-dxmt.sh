#!/bin/bash
# Compila o DXMT (Direct3D 10/11 -> Metal) com as correções do WinApps (patches/dxmt):
#   0001  build sem o compilador Metal (usa o metallib do pacote oficial, embutido)
#   0002  swapchains de composição (CreateSwapChainForComposition), usadas pelo
#         Chromium/WebView2 via DirectComposition (com o patch 0007 do motor)
#   0003  a swapchain de composição continua "ligável" depois do bind
#   0004  SwapDeviceContextState mínimo (o Direct2D do motor chama; antes abortava)
#
# Gera só dxgi.dll e d3d11.dll (x86_64, marcadas como "builtin" do Wine). O resto do
# DXMT (winemetal, d3d10core, i386…) vem do pacote oficial; o vendor.sh junta os dois.
# Precisa da árvore do motor já configurada (engine/build-engine.sh), por causa do winebuild.
#
# Uso: bash engine/build-dxmt.sh   → $WORK/out/x86_64-windows/{dxgi,d3d11}.dll
set -euo pipefail

VER=0.80
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK:-$HOME/Library/Caches/WinApps/dxmt-build}"
WINE_BUILD="${WINE_BUILD:-$HOME/Library/Caches/WinApps/build-11.21/src}"
JOBS="$(sysctl -n hw.ncpu)"

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mErro:\033[0m %s\n' "$*" >&2; exit 1; }

[ -x "$WINE_BUILD/tools/winebuild/winebuild" ] || die "rode antes: bash engine/build-engine.sh (falta $WINE_BUILD)"
command -v brew >/dev/null || die "Homebrew não encontrado"
for f in meson ninja mingw-w64; do brew list "$f" >/dev/null 2>&1 || brew install "$f"; done
export PATH="$(brew --prefix mingw-w64)/bin:$PATH"

mkdir -p "$WORK"; cd "$WORK"
say "Baixando o DXMT v${VER}…"
rm -rf src build out
git clone -q --branch "v${VER}" --depth 1 --recurse-submodules --shallow-submodules \
    https://github.com/3Shain/dxmt.git src
for p in "$HERE"/patches/dxmt/*.patch; do
    say "Aplicando $(basename "$p")"
    git -C src apply "$p" || die "patch não aplicou: $p"
done

cat >cross-win64.txt <<'EOF'
[binaries]
c = 'x86_64-w64-mingw32-gcc'
cpp = 'x86_64-w64-mingw32-g++'
ar = 'x86_64-w64-mingw32-ar'
strip = 'x86_64-w64-mingw32-strip'
windres = 'x86_64-w64-mingw32-windres'

[properties]
needs_exe_wrapper = true

[host_machine]
system = 'windows'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF
# só as DLLs Windows são compiladas: a parte nativa (LLVM/airconv) não é usada
mkdir -p fake-llvm/bin fake-llvm/include fake-llvm/lib

say "Configurando…"
meson setup build src --cross-file cross-win64.txt -Dbuildtype=release \
    -Dnative_llvm_path="$WORK/fake-llvm" -Dwine_build_path="$WINE_BUILD" >meson.log 2>&1 \
    || die "meson falhou (veja $WORK/meson.log)"
say "Compilando dxgi.dll e d3d11.dll…"
ninja -C build -j"$JOBS" src/dxgi/dxgi.dll src/d3d11/d3d11.dll >ninja.log 2>&1 \
    || die "ninja falhou (veja $WORK/ninja.log)"

mkdir -p out/x86_64-windows
for f in dxgi d3d11; do
    x86_64-w64-mingw32-strip -o "out/x86_64-windows/$f.dll" "build/src/$f/$f.dll"
    "$WINE_BUILD/tools/winebuild/winebuild" --builtin "out/x86_64-windows/$f.dll"
    [ "$(dd if="out/x86_64-windows/$f.dll" bs=1 skip=64 count=16 2>/dev/null)" = "Wine builtin DLL" ] \
        || die "$f.dll sem a marca builtin"
done
say "Pronto: $WORK/out/x86_64-windows ($(ls out/x86_64-windows | tr '\n' ' '))"
