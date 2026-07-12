#!/bin/bash
set -e

BINARY_NAME="HelloMac"
DISPLAY_NAME="HelloMac"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/HelloMac/Sources/HelloMac"
APP_PATH="$HOME/Downloads/$DISPLAY_NAME.app"
BINARY_PATH="$APP_PATH/Contents/MacOS/$BINARY_NAME"
ICON_SRC="$SCRIPT_DIR/phone.icns"

echo "🔨 Build το $DISPLAY_NAME..."

# Βρες το σωστό SDK
SDK_PATH=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || echo "/Library/Developer/CommandLineTools/SDKs/MacOSX13.3.sdk")
echo "📦 SDK: $SDK_PATH"

# Αρχιτεκτονική (Apple Silicon ή Intel)
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    TARGET="arm64-apple-macos11.0"
else
    TARGET="x86_64-apple-macos11.0"
fi
echo "🖥  Αρχιτεκτονική: $TARGET"

# Δημιουργία .app structure
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

# Compile όλα τα .swift αρχεία μαζί με το νέο Localizer.swift
swiftc \
    -sdk "$SDK_PATH" \
    -target "$TARGET" \
    -O \
    -framework AppKit \
    -framework Foundation \
    "$SRC_DIR/main.swift" \
    "$SRC_DIR/Localizer.swift" \
    "$SRC_DIR/Contact.swift" \
    "$SRC_DIR/AppDelegate.swift" \
    "$SRC_DIR/MainWindow.swift" \
    "$SRC_DIR/SettingsWindow.swift" \
    -o "$BINARY_PATH"

echo "✅ Compile OK"

if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$APP_PATH/Contents/Resources/AppIcon.icns"
    echo "🎨 Εικονίδιο OK"
else
    echo "⚠️  Εικονίδιο δεν βρέθηκε: $ICON_SRC"
fi

cat > "$APP_PATH/Contents/Info.plist" << PLIST
<?xml version="1.1" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.1//EN" "http://www.apple.com/DTDs/PropertyList-1.1.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${DISPLAY_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${DISPLAY_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.hellomac.telephone</string>
    <key>CFBundleVersion</key>
    <string>2.1.1</string>
    <key>CFBundleShortVersionString</key>
    <string>2.1.1</string>
    <key>CFBundleExecutable</key>
    <string>${BINARY_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
PLIST

chmod +x "$BINARY_PATH"

echo ""
echo "✅ Έτοιμο! Η εφαρμογή είναι στο: $APP_PATH"