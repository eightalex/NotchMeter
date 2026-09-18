#!/bin/bash
# Збирає NotchMeter.app без Xcode: SwiftPM дає виконуваний файл, решту
# бандла складаємо вручну.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-release}"
APP="$ROOT/build/NotchMeter.app"
BUNDLE_ID="com.alexanderkuzmenko.notchmeter"

cd "$ROOT"
swift build -c "$CONFIG" --build-system native

BIN="$(swift build -c "$CONFIG" --build-system native --show-bin-path)/NotchMeter"
[ -f "$BIN" ] || { echo "не знайдено виконуваний файл: $BIN" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NotchMeter"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc підпис: без нього Keychain відмовляє в доступі до чужого запису.
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP" >/dev/null

echo "готово: $APP"
