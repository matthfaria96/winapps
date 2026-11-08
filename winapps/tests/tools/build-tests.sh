#!/bin/bash
# Compila os testes em ~/Library/Caches/WinApps/tests (baixa o SDK do WebView2 se faltar)
set -e
T="$HOME/Library/Caches/WinApps/tests"; SRC="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$T"; cd "$T"; export PATH="$(brew --prefix mingw-w64)/bin:$PATH"
if [ ! -f sdk/build/native/include/WebView2.h ]; then
  curl -sfL -o sdk.nupkg https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2
  unzip -q -o sdk.nupkg 'build/native/include/*' 'build/native/x64/WebView2Loader.dll' -d sdk
  cp sdk/build/native/x64/WebView2Loader.dll .
fi
[ -f setup-wv2.exe ] || curl -sfL -o setup-wv2.exe 'https://go.microsoft.com/fwlink/p/?LinkId=2124703'
x86_64-w64-mingw32-gcc -O2 -municode -mwindows -Isdk/build/native/include "$SRC/wv2test.c" -o wv2test.exe -lole32 2>/dev/null
x86_64-w64-mingw32-gcc -O2 -mwindows "$SRC/xproctest.c" -o xproctest.exe -ld3d11 -ldxgi -luuid
x86_64-w64-mingw32-gcc -O2 -mwindows "$SRC/d3d11test.c" -o d3d11test.exe -ld3d11 -ldxgi -ld3dcompiler -luuid
echo "ok: $T"
