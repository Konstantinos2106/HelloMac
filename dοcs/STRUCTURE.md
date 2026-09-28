# 🗂️ Project Structure and Architecture

This document explains the repository structure and the purpose of each folder in the **HelloMac** project. It is aimed at developers and contributors who want to understand how the code and project files are organized.

## 🌳 File Tree

```text
HelloMac/
├── HelloMac/           # Main application source code (Swift project)
├── assets/             # Images, icons, banners, and screenshots
├── RetroPages/         # Retro versions of the website (Aqua, Classic Mac, IE)
├── admin/              # Sveltia CMS settings for content management
├── web/                # Web resources (Fonts, CSS) for the website
├── docs/               # Technical documentation (Build guides, structure)
├── index.html          # Official presentation website of the app
└── settings.json       # Special settings/parameters of the app
```

## 📂 Detailed Folder Explanation

### `HelloMac/` (Source Code)

This is the main folder containing the actual macOS application. The app is structured as a Swift Package.

- **Internal Code Structure:**
  ```text
  📁 HelloMac/
  ├── build_hellomac.sh
  ├── phone.icns
  ├── menubar_icon.png
  └── HelloMac/
      ├── Package.swift
      ├── Resources/
      │   └── Info.plist
      └── Sources/
          └── HelloMac/
              ├── main.swift
              ├── Localizer.swift
              ├── Contact.swift
              ├── ContactsSyncManager.swift
              ├── AccessibilityManager.swift
              ├── Reminders.swift
              ├── AppDelegate.swift
              ├── MainWindow.swift
              ├── SettingsWindow.swift
              ├── ImageCropPreviewWindow.swift
              └── MenuBarController.swift
  ```
- **Programming Language:** Swift
- **File Analysis:**
    - **`Sources/HelloMac/`**: Contains all the core application logic.
        - `AppDelegate.swift` & `main.swift`: The entry points of the application lifecycle.
        - `MainWindow.swift`, `MenuBarController.swift`, `SettingsWindow.swift`: Manage the main windows, the user interface (UI), and the menu bar icon.
        - `ContactsSyncManager.swift` & `Contact.swift`: Handle reading and syncing with macOS native Contacts (via iCloud).
        - `ImageCropWindow.swift` & `ImageCropPreviewWindow.swift`: Handle the logic for cropping and editing photos.
        - `AccessibilityManager.swift`, `Localizer.swift`, `Reminders.swift`: Utility classes for accessibility, translations, and setting reminders.
    - **`Resources/`**: Contains `Info.plist` (managing app permissions and settings).
    - **`Package.swift` & `build_hellomac.sh`**: The Swift package management files and the script for automatically building the app.
    - **Icons** (`phone.icns`, `menubar_icon.png`): The internal graphic files embedded into the app during compilation.

### `assets/`

Contains all static media used throughout the repository and the official website. It includes the app icon (`.icns` / `.png`), the main banner, and all screenshots (in Dark/Light Mode).

### `index.html`, `web/` & `RetroPages/`

These folders and files make up the official HelloMac presentation website, which is hosted on GitHub Pages.

- `index.html` is the official website.
- The **`web/`** folder contains necessary web resources, such as modern font files and the corresponding `CSS` for the page's appearance.
- The `RetroPages/` folder contains nostalgic versions of the page, designed to resemble older operating systems (such as Mac OS X Aqua, Classic Mac, IE).

### `admin/`

Contains the files for the operation of Sveltia CMS, which allows easy management of the presentation page content without requiring manual intervention in the code.

- `config.yml` defines the settings and data structure for the CMS.
- `index.html` serves as the entry point for the administrative interface.
