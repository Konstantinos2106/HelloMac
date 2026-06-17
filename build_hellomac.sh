#!/bin/bash
set -e

BINARY_NAME="ΗelloΜac"
DISPLAY_NAME="ΗelloΜac"
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
    TARGET="arm64-apple-macos12.0"
else
    TARGET="x86_64-apple-macos12.0"
fi
echo "🖥  Αρχιτεκτονική: $TARGET"

# Δημιουργία .app structure
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

# Compile όλα τα .swift αρχεία μαζί με swiftc
swiftc \
    -sdk "$SDK_PATH" \
    -target "$TARGET" \
    -O \
    -framework AppKit \
    -framework Foundation \
    "$SRC_DIR/main.swift" \
    "$SRC_DIR/Contact.swift" \
    "$SRC_DIR/AppDelegate.swift" \
    "$SRC_DIR/MainWindow.swift" \
    "$SRC_DIR/SettingsWindow.swift" \
    -o "$BINARY_PATH"

echo "✅ Compile OK"

# Αντιγραφή εικονιδίου
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$APP_PATH/Contents/Resources/AppIcon.icns"
    echo "🎨 Εικονίδιο OK"
else
    echo "⚠️  Εικονίδιο δεν βρέθηκε: $ICON_SRC"
fi

# Info.plist — CFBundleName = Τηλέφωνο για το menu bar
cat > "$APP_PATH/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${DISPLAY_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${DISPLAY_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.hellomac.telephone</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>${BINARY_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
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
echo ""
echo "📌 Επόμενα βήματα:"
echo "   1. Άνοιξε το Finder → Downloads"
echo "   2. Αντέγραψε το $DISPLAY_NAME.app στο φάκελο εφαρμογών του macOS"
echo "   3. Πανέτοιμο! Σύρε το $DISPLAY_NAME στο Dock για γρήγορη πρόσβαση"
