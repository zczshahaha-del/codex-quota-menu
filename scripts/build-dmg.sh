#!/bin/zsh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="${1:-$PROJECT_DIR/dist}"
APP_PATH="$OUTPUT_DIR/Codex 余量.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/Resources/Info.plist")"
DMG_PATH="$OUTPUT_DIR/Codex余量-$VERSION.dmg"
WORK_DIR="$(mktemp -d)"
STAGING_DIR="$WORK_DIR/staging"
RW_DMG_PATH="$WORK_DIR/CodexQuotaMenu-rw.dmg"
ATTACHED_DEVICE=""

cleanup() {
    if [[ -n "$ATTACHED_DEVICE" ]]; then
        hdiutil detach "$ATTACHED_DEVICE" >/dev/null 2>&1 || true
    fi
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR"
mkdir -p "$STAGING_DIR"
"$PROJECT_DIR/scripts/build-app.sh" "$OUTPUT_DIR"

ditto "$APP_PATH" "$STAGING_DIR/Codex 余量.app"
ln -s /Applications "$STAGING_DIR/Applications"
cp "$PROJECT_DIR/Resources/安装说明.txt" "$STAGING_DIR/安装说明.txt"

rm -f "$DMG_PATH" "$RW_DMG_PATH"
hdiutil create \
    -volname "Codex 余量" \
    -srcfolder "$STAGING_DIR" \
    -fs HFS+ \
    -format UDRW \
    -ov \
    "$RW_DMG_PATH" >/dev/null

ATTACH_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG_PATH")"
ATTACHED_DEVICE="$(print -r -- "$ATTACH_OUTPUT" | awk '/Apple_HFS/ { print $1; exit }')"

if [[ -z "$ATTACHED_DEVICE" ]]; then
    print -u2 "无法挂载 DMG 进行布局。"
    exit 1
fi

osascript <<'APPLESCRIPT'
tell application "Finder"
    tell disk "Codex 余量"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {220, 180, 740, 600}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set text size of viewOptions to 13
        set position of item "Codex 余量.app" of container window to {140, 145}
        set position of item "Applications" of container window to {380, 145}
        set position of item "安装说明.txt" of container window to {260, 275}
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$ATTACHED_DEVICE" >/dev/null
ATTACHED_DEVICE=""

hdiutil convert \
    "$RW_DMG_PATH" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_PATH" \
    -ov >/dev/null

print "$DMG_PATH"
