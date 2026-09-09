#!/bin/zsh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${1:-$PROJECT_DIR/dist}"
APP_DIR="$OUTPUT_DIR/Codex 余量.app"
ZIP_PATH="$OUTPUT_DIR/CodexQuotaMenu.zip"

mkdir -p "$OUTPUT_DIR"

swift build -c release --package-path "$PROJECT_DIR"
BIN_DIR="$(swift build -c release --package-path "$PROJECT_DIR" --show-bin-path)"

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

codesign --force --deep --sign - "$APP_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

print "$APP_DIR"
print "$ZIP_PATH"
