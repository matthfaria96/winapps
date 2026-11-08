#!/bin/bash
# Instala/atualiza o RubinOT no ambiente Windows do WinApps (o mesmo de todos os
# programas) e aplica as bibliotecas de compatibilidade do cliente.
#
#   bash programas/rubinot/install.sh          (RUBINOT_PREFIX=<ambiente> para outro)
#
# O app do jogo (C:\RubinOT) é sincronizado pelo manifesto público do updater
# (size + sha256 de cada arquivo). Depois o emac-client64.dll real é guardado como
# .real e trocado pelo stub. O launcher (RubinOT.exe) NÃO é usado: ele exige o
# driver de kernel do EMAC (serviço EMACDRVGLTB) e morre com 1114/6 no Wine.
set -euo pipefail
# Mensagens em inglês ou português (WINAPPS_UI_LANG; sem ela, o 1º idioma do macOS)
case "${WINAPPS_UI_LANG:-$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2p' | tr -d ' ",')}" in
    pt*) UI_LANG=pt ;; *) UI_LANG=en ;;
esac
t() { if [ "$UI_LANG" = pt ]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }
HERE="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${RUBINOT_PREFIX:-$HOME/Library/Application Support/WinApps/prefixes/default}"
APP="$PREFIX/drive_c/RubinOT"
MANIFEST="${RUBINOT_MANIFEST:-https://updater.emac.ac/updater/@rubinot/v2}"

[ -d "$APP/bin/x64" ] || { echo "$(t "C:\\RubinOT doesn't exist yet in" 'C:\RubinOT não existe ainda em') $APP" >&2
    echo "$(t 'Extract the installer:' 'Extraia o instalador:') innoextract -e -d /tmp/rubinot ~/Downloads/Setup-RubinOT-*.exe" >&2
    echo "$(t 'and copy /tmp/rubinot/app/* to' 'e copie /tmp/rubinot/app/* para') $APP" >&2; exit 1; }

echo "==> $(t 'manifest' 'manifesto')"
curl -fsSL --max-time 30 "$MANIFEST?v=$(date +%s)" -o /tmp/rubinot-manifest.json
UI_LANG="$UI_LANG" python3 - "$APP" <<'PY'
import json, hashlib, os, subprocess, sys
base = sys.argv[1]
pt = os.environ.get("UI_LANG") == "pt"
tr = lambda en, p: p if pt else en
m = json.load(open('/tmp/rubinot-manifest.json'))
todo = []
for f in m['files']:
    # o emac-client64.dll é trocado de propósito pela biblioteca de compatibilidade (abaixo)
    if os.path.basename(f['path']).lower() == 'emac-client64.dll':
        continue
    p = os.path.join(base, f['path'])
    ok = os.path.exists(p) and os.path.getsize(p) == f['size'] and \
         hashlib.sha256(open(p, 'rb').read()).hexdigest() == f['sha256']
    if not ok:
        todo.append(f)
print("    " + tr(f"{len(m['files'])} files in the manifest, {len(todo)} to download",
                   f"{len(m['files'])} arquivos no manifesto, {len(todo)} para baixar"))
for f in todo:
    p = os.path.join(base, f['path']); os.makedirs(os.path.dirname(p), exist_ok=True)
    tmp = p + '.dl'
    r = subprocess.run(['curl', '-fsSL', '--retry', '3', '--max-time', '900', '-o', tmp, f['url']])
    if r.returncode != 0:
        print('    ' + tr('failed:', 'falhou:'), f['path']); continue
    if os.path.getsize(tmp) != f['size'] or hashlib.sha256(open(tmp,'rb').read()).hexdigest() != f['sha256']:
        print('    ' + tr('wrong sha256:', 'sha errado:'), f['path']); os.remove(tmp); continue
    os.replace(tmp, p); print('    ok', f['path'])
PY

echo "==> $(t 'compatibility library (emac-client64)' 'biblioteca de compatibilidade (emac-client64)')"
[ -f "$APP/bin/x64/emac-client64.dll.real" ] || cp "$APP/bin/x64/emac-client64.dll" "$APP/bin/x64/emac-client64.dll.real"
chflags nouchg "$APP/bin/x64/emac-client64.dll" 2>/dev/null || true
cp "$HERE/cliente/emac-client64-stub.dll" "$APP/bin/x64/emac-client64.dll"
# impeça o updater do launcher de repor a DLL real (ele confere o sha256 do manifesto)
chflags uchg "$APP/bin/x64/emac-client64.dll" 2>/dev/null || true

echo "==> $(t 'window size hook (avrt.dll)' 'hook de tamanho da janela (avrt.dll)')"
cp "$HERE/cliente/avrt.dll" "$APP/bin/x64/avrt.dll"

echo "==> $(t 'WebView2 (64-bit registry view)' 'WebView2 (registro na visão 64-bit)')"
WINE_BIN="$HOME/Library/Application Support/WinApps/motor/engine/Contents/Resources/wine/bin/wine"
RUNTIME="$(ls -d "$PREFIX/drive_c/Program Files (x86)/Microsoft/EdgeWebView/Application"/*/ 2>/dev/null | grep -v SetupMetrics | sort -V | tail -1 || true)"
if [ -n "$RUNTIME" ] && [ -x "$WINE_BIN" ]; then
    VER="$(basename "${RUNTIME%/}")"
    GUID='{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}'
    for root in "HKLM\\SOFTWARE\\Microsoft\\EdgeUpdate\\Clients\\$GUID" \
                "HKCU\\Software\\Microsoft\\EdgeUpdate\\Clients\\$GUID"; do
        WINEPREFIX="$PREFIX" WINEDEBUG=-all "$WINE_BIN" reg add "$root" /v name /t REG_SZ /d "Microsoft Edge WebView2 Runtime" /f >/dev/null 2>&1 || true
        WINEPREFIX="$PREFIX" WINEDEBUG=-all "$WINE_BIN" reg add "$root" /v location /t REG_SZ /d 'C:\Program Files (x86)\Microsoft\EdgeWebView\Application' /f >/dev/null 2>&1 || true
        WINEPREFIX="$PREFIX" WINEDEBUG=-all "$WINE_BIN" reg add "$root" /v pv /t REG_SZ /d "$VER" /f >/dev/null 2>&1 || true
    done
    echo "   $(t "runtime $VER registered (avoids the 'WebView2 Runtime Required' dialog)" "runtime $VER registrado (evita o diálogo 'WebView2 Runtime Required')")"
else
    echo "   $(t '(WebView2 runtime not found — run: winapps components webview2)' '(runtime WebView2 não encontrado — rode: winapps components webview2)')"
fi

echo "==> $(t 'watchdog (reopens the client when the session drops)' 'vigia (reabre o cliente quando a sessão cai)')"
pkill -f 'rubinot/watchdog.sh' 2>/dev/null || true
nohup "$HERE/watchdog.sh" >/dev/null 2>&1 &
echo "   $(t 'active (to turn it off:' 'ativo (desligar:') touch \"$PREFIX/.rubinot-sem-vigia\")"

echo "==> $(t 'shortcut' 'atalho')"
WINAPPS_PREFIX="$PREFIX" winapps shortcut "$APP/bin/x64/rubinot_dx.exe" RubinOT
echo "$(t 'Done: open ~/Applications/RubinOT.app' 'Pronto: abra ~/Applications/RubinOT.app')"
