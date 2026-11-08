#!/bin/bash
# Instala dxgi.dll/d3d11.dll compilados em ~/Library/Caches/WinApps/dxmt-src/build-win64 no motor.
# Voltar ao DXMT oficial: winapps dxmt on
B="$HOME/Library/Caches/WinApps/dxmt-src/build-win64/src"
L="$HOME/Library/Application Support/WinApps/motor/engine/Contents/Resources/wine/lib/wine/x86_64-windows"
export PATH="$(brew --prefix mingw-w64)/bin:$PATH"
for f in dxgi/dxgi.dll d3d11/d3d11.dll; do
  n=$(basename $f); x86_64-w64-mingw32-strip -o "$L/$n.new" "$B/$f" && "$HOME/Library/Caches/WinApps/build-11.21/src/tools/winebuild/winebuild" --builtin "$L/$n.new" && mv -f "$L/$n.new" "$L/$n" && echo "instalado $n ($(stat -f %z "$L/$n") bytes)"
done
