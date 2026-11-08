#!/bin/bash
# wv2run.sh <rótulo> [opções Chromium] → roda o wv2test no prefixo teste-wv2 por 25 s,
# (WV2ARGS="popup": abre também uma 2ª WebView numa janela pop-up após 15 s)
# lista as superfícies remotas (tipo 0 = GDI, 1 = GPU), conta travamentos e fotografa.
L="$1"; shift; T="$HOME/Library/Caches/WinApps/tests"; B="$HOME/Library/Application Support/WinApps"
R="$B/prefixes/teste-wv2/drive_c/users/$USER/AppData/Local/Temp/wv2test-data/EBWebView/Crashpad/reports"
export WINAPPS_PREFIX="$B/prefixes/teste-wv2" WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS="${NOFLAGS:+}${NOFLAGS:---disable-features=CalculateNativeWinOcclusion} $*"
eval "$("$B/bin/winapps" env)"; "$WINESERVER" -k 2>/dev/null; rm -rf "${TMPDIR:-/tmp}"/winemac-remote-*; sleep 1
n0=$(ls "$R" 2>/dev/null | wc -l)
( cd "$T" && "$(dirname "$WINESERVER")/wine" "$T/wv2test.exe" $WV2ARGS >"$T/log-$L.txt" 2>&1 & )
sleep ${WAIT:-25}
/usr/bin/python3 -I - <<'PY'
import glob,os,struct
for f in sorted(glob.glob(os.environ.get("TMPDIR","/tmp").rstrip("/")+"/winemac-remote-*/*/*.surf")):
    d=open(f,"rb").read(64); m,v,seq,vis,x,y,w,h,cid,kind,pid,fr=struct.unpack("<IIIIiiiiIIII",d[:48])
    print(" ",os.path.basename(f),"tipo",kind,"vis",vis,"pos",x,y,"tam",w,h,"ctx",cid,"pid",pid,"quadros",fr)
PY
pid=$(pgrep -f 'wv2test.exe' | head -1)
G=$(osascript -e "tell application \"System Events\" to tell (first process whose unix id is $pid) to get {position, size} of window 1" 2>/dev/null)
osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $pid) to true" >/dev/null 2>&1; sleep 1.5
wid=$("$T/winid" "$pid")   # só a janela do teste, sem o que estiver atrás
[ -n "$wid" ] && [ "$wid" != 0 ] && screencapture -x -o -l "$wid" "$T/shot-$L.png"
case "$WV2ARGS" in *popup*) screencapture -x -o -R 300,250,600,400 "$T/shot-$L-popup.png";; esac
echo "== $L: travamentos novos $(( $(ls "$R" 2>/dev/null | wc -l) - n0 )) foto: $T/shot-$L.png"
"$WINESERVER" -k 2>/dev/null
