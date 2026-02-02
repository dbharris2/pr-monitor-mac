# PR Monitor (macOS)

A macOS menu bar app for monitoring GitHub pull requests.

## Tech Stack

- SwiftUI with MenuBarExtra (macOS 14+)
- GitHub GraphQL API
- Keychain for secure token storage
- XcodeGen for project generation

## Setup

```bash
brew install xcodegen   # If not already installed
xcodegen generate       # Creates PRMonitor.xcodeproj
open PRMonitor.xcodeproj
```

## Project Structure

- `Sources/PRMonitor/` - Main app source code
  - `PRMonitorApp.swift` - App entry point with MenuBarExtra
  - `AppState.swift` - Observable app state and polling logic
  - `Models/` - Data models (PullRequest)
  - `Services/` - GitHub API service
  - `Views/` - SwiftUI views (PRSection, SettingsView)
  - `Utilities/` - Keychain helper
- `Resources/` - Info.plist, entitlements
- `project.yml` - XcodeGen project specification

## Key Patterns

- Uses `@MainActor` for thread-safe UI updates
- GitHub token stored in Keychain (not UserDefaults)
- Polling interval configurable in Settings
- `MenuBarExtra` with `.window` style for richer UI

## Building

```bash
xcodegen generate && xcodebuild -scheme PRMonitor -configuration Debug build
```

Or just open in Xcode and press ⌘R.
