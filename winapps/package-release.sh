#!/bin/sh
# Gera o WinApps-<versão>.dmg para o release do GitHub (e o instalador do witchmymac.com).
#
# Compila o app numa pasta temporária (build.sh <destino>), reassina com o certificado
# witchmymac se existir ~/Documents/VSCode/witchmymac-release/sign-app.sh (o macOS não
# esquece permissões entre versões); senão fica a assinatura ad hoc. Sem Hardened Runtime:
# o app abre em qualquer Mac sem conta paga de desenvolvedor.
#
# Uso: sh winapps/package-release.sh      → winapps/build/release/WinApps-<versão>.dmg
set -eu
cd "$(dirname "$0")"

OUT=build/release
rm -rf "$OUT"; mkdir -p "$OUT/app"
bash build.sh "$PWD/$OUT/app"
APP="$OUT/app/WinApps.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")

SIGN_APP="$HOME/Documents/VSCode/witchmymac-release/sign-app.sh"
if [ -f "$SIGN_APP" ]; then
  sh "$SIGN_APP" "$APP"
else
  echo "AVISO: $SIGN_APP não encontrado, o app fica com assinatura ad hoc" >&2
  codesign --force --deep --sign - "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"

STAGE="$OUT/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/WinApps.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname WinApps -srcfolder "$STAGE" -ov -format UDZO "$OUT/WinApps-$VERSION.dmg"
rm -rf "$STAGE" "$OUT/app"
# o build registra o app no LaunchServices: tira para não haver dois WinApps com o mesmo id
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$PWD/$APP" 2>/dev/null || true

echo; echo "Pronto em $OUT:"; shasum -a 256 "$OUT/WinApps-$VERSION.dmg"
