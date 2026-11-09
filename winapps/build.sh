#!/bin/bash
# Compila o WinApps.app e instala em ~/Applications (ou no destino passado).
# Uso: bash build.sh [pasta-destino]
set -euo pipefail
cd "$(dirname "$0")"
DEST="${1:-$HOME/Applications}"
APP="$DEST/WinApps.app"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# tabela de compatibilidade do repositório (gerada da mesma compat.json que vai no app)
python3 compat-md.py >/dev/null

echo "Compilando…"
swiftc -parse-as-library -O -swift-version 5 -target arm64-apple-macos14 \
       -o "$TMP/WinApps-arm64" WinApps.swift FileBrowser.swift
swiftc -parse-as-library -O -swift-version 5 -target x86_64-apple-macos14 \
       -o "$TMP/WinApps-x86_64" WinApps.swift FileBrowser.swift
lipo -create -output "$TMP/WinApps" "$TMP/WinApps-arm64" "$TMP/WinApps-x86_64"
# moldura dos ícones dos atalhos (placa branca no formato do macOS)
swiftc -O -target arm64-apple-macos14 -o "$TMP/icon-frame-arm64" icon-frame.swift
swiftc -O -target x86_64-apple-macos14 -o "$TMP/icon-frame-x86_64" icon-frame.swift
lipo -create -output "$TMP/icon-frame" "$TMP/icon-frame-arm64" "$TMP/icon-frame-x86_64"
# login Windows local (Power BI ↔ Analysis Services etc.)
clang -O2 -arch arm64 -arch x86_64 -o "$TMP/ntlm_auth" ntlm_auth.c

echo "Gerando ícone…"
swiftc -O -o "$TMP/make-icon" make-icon.swift
"$TMP/make-icon" "$TMP/icon.png"
mkdir -p "$TMP/AppIcon.iconset"
for s in 16 32 128 256 512; do
    sips -z $s $s "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$TMP/icon.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$TMP/AppIcon.iconset" -o "$TMP/AppIcon.icns"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$TMP/WinApps" "$APP/Contents/MacOS/WinApps"
cp "$TMP/AppIcon.icns" "$TMP/icon-frame" "$TMP/ntlm_auth" winapps exe-icon.py exe-kind.py compat.json "$APP/Contents/Resources/"
# guia e licenças: inglês (GUIDE/LICENSES) e português (GUIA/LICENCAS); o app escolhe pelo idioma
for doc in GUIDE.md GUIA.md LICENSES.md LICENCAS.md; do
    if [ -f "$doc" ]; then cp "$doc" "$APP/Contents/Resources/"; fi
done
# traduções da interface (inglês é o padrão; pt-BR quando o Mac está em português)
for lproj in Resources/*.lproj; do
    if [ -d "$lproj" ]; then cp -R "$lproj" "$APP/Contents/Resources/"; fi
done
# ferramentas e motor corrigido embutidos (gerados por vendor.sh)
[ -d vendor ] || { echo "Rode antes: bash vendor.sh"; exit 1; }
cp -R vendor "$APP/Contents/Resources/vendor"
chmod +x "$APP/Contents/Resources/winapps"

cat >"$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>WinApps</string>
  <key>CFBundleDisplayName</key><string>WinApps</string>
  <key>CFBundleIdentifier</key><string>com.winapps.launcher</string>
  <key>CFBundleExecutable</key><string>WinApps</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>2.1.1</string>
  <key>CFBundleVersion</key><string>210</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key>
  <array><string>en</string><string>pt-BR</string></array>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Matheus Faria. Free software under the GNU GPL v3.0.</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Windows Program</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Owner</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>com.microsoft.windows-executable</string>
        <string>com.microsoft.msi-installer</string>
      </array>
      <key>CFBundleTypeExtensions</key>
      <array><string>exe</string><string>msi</string></array>
    </dict>
    <!-- .zip e pastas de programas: só em "Abrir com" (não viram padrão) -->
    <dict>
      <key>CFBundleTypeName</key><string>Windows Program Archive or Folder</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array><string>public.zip-archive</string><string>public.folder</string></array>
    </dict>
  </array>
  <!-- o macOS não declara o tipo do .msi: sem isto ele cai no tipo de algum compactador -->
  <key>UTImportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key><string>com.microsoft.msi-installer</string>
      <key>UTTypeDescription</key><string>Windows Installer</string>
      <key>UTTypeConformsTo</key><array><string>public.data</string></array>
      <key>UTTypeTagSpecification</key>
      <dict><key>public.filename-extension</key><array><string>msi</string></array></dict>
    </dict>
  </array>
</dict></plist>
EOF

codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
echo "WinApps.app instalado em $APP"
