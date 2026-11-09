#!/bin/bash
# Prepara as ferramentas que vão embutidas no WinApps.app (pasta vendor/), para que
# quem baixar o app não precise de Homebrew:
#   - cabextract (universal arm64 + x86_64), usado pelo winetricks
#   - winetricks (versão fixa), que instala fontes, Visual C++, DirectX, .NET…
#   - módulos do motor com as nossas correções (se o engine/build-engine.sh já rodou)
set -euo pipefail
cd "$(dirname "$0")"
OUT="$PWD/vendor"
CAB_VER=1.11
WT_VER=20260125
ENGINE_VER=11.21
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"

if [ ! -x "$OUT/cabextract" ]; then
    echo "==> cabextract $CAB_VER (universal)"
    curl -fsSL -o "$TMP/cab.tar.gz" "https://www.cabextract.org.uk/cabextract-$CAB_VER.tar.gz"
    for arch in arm64 x86_64; do
        mkdir -p "$TMP/$arch" && tar xzf "$TMP/cab.tar.gz" -C "$TMP/$arch" --strip-components 1
        ( cd "$TMP/$arch" && ./configure --host="$arch-apple-darwin" CC="clang -arch $arch" \
              CFLAGS="-O2 -mmacosx-version-min=11.0" >/dev/null && make -j4 >/dev/null )
    done
    lipo -create -output "$OUT/cabextract" "$TMP/arm64/cabextract" "$TMP/x86_64/cabextract"
    codesign --force -s - "$OUT/cabextract" >/dev/null 2>&1
fi

if [ ! -x "$OUT/winetricks" ]; then
    echo "==> winetricks $WT_VER"
    curl -fsSL -o "$OUT/winetricks" "https://raw.githubusercontent.com/Winetricks/winetricks/$WT_VER/src/winetricks"
    chmod +x "$OUT/winetricks"
fi

DXMT_VER=0.80
if [ ! -d "$OUT/dxmt-v$DXMT_VER" ]; then
    echo "==> DXMT $DXMT_VER (Direct3D 10/11 -> Metal)"
    curl -fsSL -o "$TMP/dxmt.tar.gz" "https://github.com/3Shain/dxmt/releases/download/v$DXMT_VER/dxmt-v$DXMT_VER-builtin.tar.gz"
    mkdir -p "$OUT/dxmt-v$DXMT_VER"
    tar xzf "$TMP/dxmt.tar.gz" -C "$OUT/dxmt-v$DXMT_VER" --strip-components 1
fi

# DXMT com as correções do WinApps (engine/build-dxmt.sh): WebView2/Chromium aparece
# DXMT_BUILD força um build; sem ele, procura nos caminhos usados aqui (cache e volume)
if [ -z "${DXMT_BUILD:-}" ]; then
    for c in "$HOME/Library/Caches/WinApps/dxmt-build/out" \
             "$HOME/Library/Caches/WinApps/dxmt-official/out" \
             /Volumes/WinAppsDev/dxmt-official/out; do
        if [ -f "$c/x86_64-windows/d3d11.dll" ]; then DXMT_BUILD="$c"; break; fi
    done
fi
if [ -n "${DXMT_BUILD:-}" ] && [ -f "$DXMT_BUILD/x86_64-windows/d3d11.dll" ] \
        && [ -f "$DXMT_BUILD/x86_64-windows/dxgi.dll" ]; then
    echo "==> DXMT $DXMT_VER + correções do WinApps ($DXMT_BUILD)"
    cp "$DXMT_BUILD"/x86_64-windows/{dxgi,d3d11}.dll "$OUT/dxmt-v$DXMT_VER/x86_64-windows/"
    echo "patches/dxmt aplicados" >"$OUT/dxmt-v$DXMT_VER/WINAPPS-PATCHES"
elif [ -f "$OUT/dxmt-v$DXMT_VER/WINAPPS-PATCHES" ]; then
    echo "==> DXMT $DXMT_VER: build corrigido não encontrado, mantendo o de vendor/ (já corrigido)"
else
    echo "!! DXMT corrigido não encontrado (defina DXMT_BUILD=…/out ou rode: bash ../engine/build-dxmt.sh): WebView2 ficará em branco" >&2
fi

# módulos corrigidos do motor (gerados por engine/build-engine.sh [--build-only])
SRC="${ENGINE_SRC:-$HOME/Library/Caches/WinApps/build-$ENGINE_VER/src}/dlls"
UNIX_MODS="win32u/win32u.so winemac.drv/winemac.so ntdll/ntdll.so"
PE_MODS="dcomp/x86_64-windows/dcomp.dll secur32/x86_64-windows/secur32.dll mshtml/x86_64-windows/mshtml.dll ole32/x86_64-windows/ole32.dll ../programs/winecfg/x86_64-windows/winecfg.exe"
PE32_MODS="ole32/i386-windows/ole32.dll"   # 0002: RevokeDragDrop entre processos (RubinOT)
missing=""
for m in $UNIX_MODS $PE_MODS $PE32_MODS; do [ -f "$SRC/$m" ] || missing="$missing $m"; done
if [ -z "$missing" ]; then
    echo "==> motor corrigido $ENGINE_VER"
    rm -rf "$OUT/engine-$ENGINE_VER"
    mkdir -p "$OUT/engine-$ENGINE_VER/x86_64-unix" "$OUT/engine-$ENGINE_VER/x86_64-windows" "$OUT/engine-$ENGINE_VER/i386-windows"
    for m in $UNIX_MODS; do cp "$SRC/$m" "$OUT/engine-$ENGINE_VER/x86_64-unix/"; done
    for m in $PE_MODS; do cp "$SRC/$m" "$OUT/engine-$ENGINE_VER/x86_64-windows/"; done
    for m in $PE32_MODS; do cp "$SRC/$m" "$OUT/engine-$ENGINE_VER/i386-windows/"; done
else
    echo "!! motor corrigido incompleto (falta:$missing): rode antes  bash ../engine/build-engine.sh"
fi

lipo -archs "$OUT/cabextract"; ls -la "$OUT" "$OUT"/engine-* 2>/dev/null
