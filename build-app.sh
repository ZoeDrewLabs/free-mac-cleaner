#!/bin/zsh
# Compila e monta "Free Mac Cleaner + Video Compress.app" em ./dist
set -euo pipefail
cd "$(dirname "$0")"

APP="dist/Free Mac Cleaner + Video Compress.app"
swift build -c release

# Ícone (.icns) a partir do logo
if [[ ! -f Resources/AppIcon.icns || Resources/logo.webp -nt Resources/AppIcon.icns ]]; then
  SET=$(mktemp -d)/AppIcon.iconset
  mkdir -p "$SET"
  sips -s format png Resources/logo.webp --out "$SET/base.png" >/dev/null
  for s in 16 32 128 256 512; do
    sips -z $s $s "$SET/base.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d "$SET/base.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
  done
  rm "$SET/base.png"
  iconutil -c icns "$SET" -o Resources/AppIcon.icns
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/FreeMacCleaner "$APP/Contents/MacOS/FreeMacCleaner"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Free Mac Cleaner + Video Compress</string>
  <key>CFBundleDisplayName</key><string>Free Mac Cleaner + Video Compress</string>
  <key>CFBundleIdentifier</key><string>io.github.zoedrewlabs.FreeMacCleaner</string>
  <key>CFBundleExecutable</key><string>FreeMacCleaner</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleDevelopmentRegion</key><string>pt-BR</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSDownloadsFolderUsageDescription</key><string>Para encontrar downloads antigos que podem ir para a Lixeira.</string>
  <key>NSDesktopFolderUsageDescription</key><string>Para encontrar arquivos grandes esquecidos.</string>
  <key>NSDocumentsFolderUsageDescription</key><string>Para encontrar arquivos grandes esquecidos.</string>
</dict>
</plist>
PLIST

codesign --force --deep -s - "$APP"
echo "Pronto: $PWD/$APP"
