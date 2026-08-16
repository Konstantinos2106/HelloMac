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

SDK_PATH=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || echo "/Library/Developer/CommandLineTools/SDKs/MacOSX13.3.sdk")
echo "📦 SDK: $SDK_PATH"

ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    TARGET="arm64-apple-macos11.0"
else
    TARGET="x86_64-apple-macos11.0"
fi
echo "🖥  Αρχιτεκτονική: $TARGET"

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources/el.lproj"
mkdir -p "$APP_PATH/Contents/Resources/en.lproj"

swiftc \
    -sdk "$SDK_PATH" \
    -target "$TARGET" \
    -O \
    -framework AppKit \
    -framework Foundation \
    -framework Carbon \
    -framework Contacts \
    -framework UserNotifications \
    "$SRC_DIR/main.swift" \
    "$SRC_DIR/Localizer.swift" \
    "$SRC_DIR/Contact.swift" \
    "$SRC_DIR/ContactsSyncManager.swift" \
    "$SRC_DIR/AccessibilityManager.swift" \
    "$SRC_DIR/Reminders.swift" \
    "$SRC_DIR/AppDelegate.swift" \
    "$SRC_DIR/MainWindow.swift" \
    "$SRC_DIR/SettingsWindow.swift" \
    "$SRC_DIR/ImageCropPreviewWindow.swift" \
    "$SRC_DIR/MenuBarController.swift" \
    -o "$BINARY_PATH"

echo "✅ Compile OK"

if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$APP_PATH/Contents/Resources/AppIcon.icns"
    echo "🎨 Εικονίδιο OK"
else
    echo "⚠️  Εικονίδιο δεν βρέθηκε: $ICON_SRC"
fi

MENU_ICON_SRC="$SCRIPT_DIR/menubar_icon.png"
if [ -f "$MENU_ICON_SRC" ]; then
    cp "$MENU_ICON_SRC" "$APP_PATH/Contents/Resources/menubar_icon.png"
    echo "🎨 Menu Bar Εικονίδιο OK"
else
    echo "⚠️  Menu Bar Εικονίδιο δεν βρέθηκε: $MENU_ICON_SRC"
fi

cat > "$APP_PATH/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
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
    <string>3.0.1</string>
    <key>CFBundleShortVersionString</key>
    <string>3.0.1</string>
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
    <key>NSContactsUsageDescription</key>
    <string>Απαιτείται πρόσβαση στις Επαφές για την εμφάνιση επαφών και την πραγματοποίηση κλήσεων. Τα δεδομένα επαφών αναγιγνώσκονται αποκλειστικά τοπικά και δεν αποστέλλονται πουθενά.</string>
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key>
            <dict>
                <key>default</key>
                <string>Κλήση με το HelloMac</string>
            </dict>
            <key>NSMessage</key>
            <string>callWithHelloMac</string>
            <key>NSPortName</key>
            <string>${DISPLAY_NAME}</string>
            <key>NSSendTypes</key>
            <array>
                <string>NSStringPboardType</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

chmod +x "$BINARY_PATH"

echo "🔏 Code signing (ad-hoc)..."
codesign --force --deep --sign - "$APP_PATH"
echo "✅ Code sign OK"

echo ""
echo "✅ Έτοιμο! Η εφαρμογή είναι στο: $APP_PATH"