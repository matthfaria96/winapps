#!/bin/bash
# devinstall.sh win32u|winemac|ntdll... → instala módulos recém-compilados em ~/Library/Caches/WinApps/build-11.21
# (mesmos ajustes do engine/build-engine.sh). Desfazer: winapps engine-patch (volta ao vendor).
U="$HOME/Library/Application Support/WinApps/motor/engine/Contents/Resources/wine/lib/wine/x86_64-unix"
SRC="$HOME/Library/Caches/WinApps/build-11.21/src/dlls"
rp() { otool -l "$1" | awk '/LC_RPATH/{f=1} f&&/ path /{print $2; f=0}'; }
for m in "$@"; do
  case $m in win32u) new="$SRC/win32u/win32u.so"; so=win32u.so;; winemac) new="$SRC/winemac.drv/winemac.so"; so=winemac.so;;
    ntdll) new="$SRC/ntdll/ntdll.so"; so=ntdll.so;; *) continue;; esac
  orig="$U/$so.orig"; [ -e "$orig" ] || cp "$U/$so" "$orig"
  install_name_tool -id "$(otool -D "$orig" | tail -1)" "$new" 2>/dev/null
  for ref in $(otool -L "$new" | tail -n +3 | awk '{print $1}'); do case "$ref" in /*|@*) ;; *) install_name_tool -change "$ref" "@rpath/$ref" "$new" 2>/dev/null;; esac; done
  for r in $(rp "$orig"); do rp "$new" | grep -qx "$r" || install_name_tool -add_rpath "$r" "$new"; done
  codesign --force -s - "$new" >/dev/null 2>&1
  cp "$new" "$U/$so.new" && mv -f "$U/$so.new" "$U/$so" && echo "instalado $so"
done
