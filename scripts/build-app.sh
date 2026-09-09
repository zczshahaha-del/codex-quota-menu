#!/bin/zsh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${1:-$PROJECT_DIR/dist}"
APP_DIR="$OUTPUT_DIR/Codex 余量.app"
ZIP_PATH="$OUTPUT_DIR/CodexQuotaMenu.zip"
ICON_WORK_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$ICON_WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR"

swift build -c release --arch arm64 --arch x86_64 --package-path "$PROJECT_DIR"
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --package-path "$PROJECT_DIR" --show-bin-path)"

ICONSET_DIR="$ICON_WORK_DIR/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"
swift "$PROJECT_DIR/scripts/render-app-icon.swift" "$ICON_WORK_DIR/AppIcon-1024.png"
sips -z 16 16 "$ICON_WORK_DIR/AppIcon-1024.png" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_WORK_DIR/AppIcon-1024.png" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_WORK_DIR/AppIcon-1024.png" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_WORK_DIR/AppIcon-1024.png" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_WORK_DIR/AppIcon-1024.png" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_WORK_DIR/AppIcon-1024.png" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_WORK_DIR/AppIcon-1024.png" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_WORK_DIR/AppIcon-1024.png" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_WORK_DIR/AppIcon-1024.png" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$ICON_WORK_DIR/AppIcon-1024.png" "$ICONSET_DIR/icon_512x512@2x.png"
iconutil -c icns "$ICONSET_DIR" -o "$ICON_WORK_DIR/AppIcon.icns"

if [[ "$APP_DIR" != "$OUTPUT_DIR/"* ]]; then
    print -u2 "拒绝清理输出目录之外的路径：$APP_DIR"
    exit 1
fi

rm -rf "$APP_DIR"
rm -f "$ZIP_PATH"

mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/CodexQuotaMenu" "$APP_DIR/Contents/MacOS/CodexQuotaMenu"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ICON_WORK_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
    codesign --force --deep --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" "$APP_DIR"
else
    codesign --force --deep --sign - "$APP_DIR"
fi
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

print "$APP_DIR"
print "$ZIP_PATH"
