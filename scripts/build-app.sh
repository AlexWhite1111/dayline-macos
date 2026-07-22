#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_ROOT=${SCRIPT_DIR:h}
CONFIGURATION=${1:-release}
APP_PATH="$PROJECT_ROOT/outputs/今日.app"

swift build --package-path "$PROJECT_ROOT" -c "$CONFIGURATION"
BIN_PATH=$(swift build --package-path "$PROJECT_ROOT" -c "$CONFIGURATION" --show-bin-path)

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_PATH/Dayline" "$APP_PATH/Contents/MacOS/Dayline"
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
if [[ -f "$PROJECT_ROOT/Resources/AppIcon.icns" ]]; then
    cp "$PROJECT_ROOT/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
fi

codesign --force --deep --sign - "$APP_PATH"

print "$APP_PATH"
