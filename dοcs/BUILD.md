# 🛠️ Build & Development Guide

If you want to compile (build) **HelloMac** from source, the process has been fully automated via a bash script (`build_hellomac.sh`).

## 📋 System Requirements

For the build script to run successfully, your system must meet the following requirements:

- **Operating System:** macOS 11.0 (Big Sur) or later is required, as this is set as the minimum system during compilation. The process automatically supports both architectures: Apple Silicon (`arm64`) and Intel (`x86_64`).
- **Development Tools (Command Line Tools):** The Swift compiler (`swiftc`) and Apple system tools (`xcrun` for the macOS SDK, `codesign` for signing the app) are required. All are included in the **Xcode Command Line Tools** (see Step 1 below).
- **Frameworks:** The app uses Apple’s native frameworks (`AppKit`, `Foundation`, `Carbon`, `Contacts`, `UserNotifications`), which are automatically integrated by the macOS SDK.
- **Disk Space:** About 2 GB free space for the Command Line Tools.
- **Internet Connection:** Required only to download the tools and the source code.

> 💡 **You do not need** the full Xcode (10+ GB), Homebrew, or an Apple Developer account. The project has no external dependencies.

* * *

## 🚀 Build Process

Follow these simple steps:

### Step 1: Install Development Tools (once)

If you have not already installed the Xcode Command Line Tools, open **Terminal** and run:

```bash
xcode-select --install
```

A system window will appear. Click **“Install”**, accept the terms, and wait for the download to complete (usually 5–15 minutes, depending on your connection).

**Verify that the installation succeeded:**

```bash
swiftc --version
xcrun --sdk macosx --show-sdk-path
```

If both commands produce output (the Swift version and a path to the SDK) without error, you are ready. If the message `command line tools are already installed` appears, the tools already exist and you can proceed to the next step.

> ⚠️ **Note:** If the installation window does not appear or the download fails, you can download the Command Line Tools manually from [developer.apple.com/download/all](https://developer.apple.com/download/all/) (a free Apple ID is required).

### Step 2: Download the Source Code

Download the project folder from GitHub (green button **Code → Download ZIP**) and unzip it. Make sure the folder named `HelloMac` is in your Downloads folder (`Downloads`).

### Step 3: Open Terminal in the Project Folder

Open Terminal and navigate to the folder where the build file is located:

```bash
cd ~/Downloads/HelloMac
```

### Step 4: Grant Execute Permissions

Before running the script, you must give it the necessary execute permissions:

```bash
chmod +x build_hellomac.sh
```

### Step 5: Run the Script

Start the build process:

```bash
./build_hellomac.sh
```

### Step 6: Completion

The process will run automatically, compile the code, add the icons, and sign the app (ad-hoc code signing). Once complete, the ready, compiled **HelloMac** app (the `.app` file) will appear directly in your Downloads folder, ready to use!

* * *

## ▶️ First Launch of the App

Because the app is signed locally (ad-hoc) and not with an Apple Developer certificate, macOS may show a warning on first launch. This is normal.

1. **Right-click** on `HelloMac.app` → **Open** → **Open** again in the window that appears.
2. If macOS continues to block the app, go to **System Settings → Privacy & Security** and click **“Open Anyway”** at the bottom of the page.
3. When prompted, grant **access to Contacts** so that iCloud/iPhone sync can work.

* * *

## 🩺 Troubleshooting

| Error | Cause | Solution |
| --- | --- | --- |
| `swiftc: command not found` | Command Line Tools are not installed | Run `xcode-select --install` |
| `xcrun: error: invalid active developer path` | The tools need reinstalling (usually after a macOS upgrade) | Run `xcode-select --install` or `sudo xcode-select --reset` |
| `Permission denied: ./build_hellomac.sh` | The script does not have execute permissions | Run `chmod +x build_hellomac.sh` |
| `No such file or directory` for `.swift` files | The folder does not have the correct structure, or the script is not running from the correct location | Make sure the script is next to the `HelloMac/Sources/HelloMac/` folder |
| `⚠️ Icon not found` | `phone.icns` / `menubar_icon.png` are missing | Not critical: the app builds normally, just without icons. Place the files next to the script to include them |
| The app “cannot be opened because it is from an unidentified developer” | ad-hoc signing | See the “First Launch” section above |
