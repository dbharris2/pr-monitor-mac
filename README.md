# PR Monitor

A macOS menu bar app for monitoring GitHub pull requests.

## Requirements

- macOS 14+
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Build & Run

```bash
# Install XcodeGen (if not already installed)
brew install xcodegen

# Generate Xcode project and build
xcodegen generate
xcodebuild -scheme PRMonitor -configuration Debug build

# Run the app
open ~/Library/Developer/Xcode/DerivedData/PRMonitor-*/Build/Products/Debug/PRMonitor.app
```

Or open in Xcode and press ⌘R:

```bash
xcodegen generate
open PRMonitor.xcodeproj
```

## Setup

1. Run the app (it appears in your menu bar)
2. Click the menu bar icon and go to **Settings**
3. Add your GitHub personal access token
   - Create one at GitHub → Settings → Developer settings → Personal access tokens
   - Needs `repo` scope for private repos

## Features

- **Needs your review** - PRs where you're a requested reviewer
- **Waiting for reviewers** - PRs you authored awaiting review
- **Approved** - PRs you authored that are approved
- **Reviewed** - PRs you've reviewed or PRs with changes requested

PRs with "changes requested" status show a red dot; others show orange.
