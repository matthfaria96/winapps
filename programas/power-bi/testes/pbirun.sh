#!/bin/bash
# pbirun.sh [log] — DIAGNÓSTICO: abre o Power BI no prefixo teste-wv2, fecha o aviso inicial
# ("Something went wrong") via WM_CLOSE (KEEPDIALOG=1: para e mostra o HWND do aviso) e clica em "Blank report" (só se a janela do PBI estiver no topo).
T="$HOME/Library/Caches/WinApps/tests"; W=$(find "$HOME/Library/Application Support/WinApps/motor" -path "*bin/wine" | head -1)
export WINEPREFIX="$HOME/Library/Application Support/WinApps/prefixes/teste-wv2"
L=${1:-/Volumes/WinAppsDev/pbi.log}
"${W}server" -k; sleep 2
(WINEDEBUG=${WINEDEBUG:--all,err+all} "$W" "C:\\Program Files\\Microsoft Power BI Desktop\\bin\\PBIDesktop.exe" > "$L" 2>&1 &)
nap() { perl -e "select(undef,undef,undef,$1)"; }
for i in $(seq 1 80); do nap 3; O=$(WINEDEBUG=-all "$W" "$T/enumwin.exe" 2>/dev/null | grep "vis=1" | grep -v "^ "); echo "$O" | grep -q "went wrong" && break; done
H=$(echo "$O" | grep "went wrong" | awk '{print $1}' | sed 's/^0*//')
[ -n "$KEEPDIALOG" ] && { echo "dialogo $H"; exit 0; }
[ -n "$H" ] && WINEDEBUG=-all "$W" "$T/enumwin.exe" close $H
nap 8
P=$(pgrep -f PBIDesktop.exe | head -1)
osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $P) to true"; nap 1
for k in 1 2; do
  "$T/topat" 323 248 | grep -v " Dock " | head -1 | grep -q "Power BI Desktop" || { echo "PBI não está no topo; não cliquei"; exit 1; }
  "$T/click" 323 248; nap 4
done
echo "ok (pid $P)"
