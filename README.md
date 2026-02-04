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

### Menu Bar Status Indicators

The menu bar icon shows colored indicators for at-a-glance PR status:

- 🟢 **Green** - Your PRs that are approved and ready to merge
- 🟠 **Orange** - PRs that need your review
- 🔴 **Red** - Your PRs returned with changes requested

Choose between compact dots or colored numbers in Settings.

### PR Categories

- **Needs my review** - PRs where you're a requested reviewer
- **Waiting for review** - PRs you authored awaiting review
- **Approved** - PRs you authored that are approved
- **Returned to me** - Your PRs with changes requested
- **Reviewed** - PRs you've reviewed

### Other Features

- **Notifications** - Get notified when you receive new review requests, approvals, or change requests
- **Launch at login** - Start monitoring automatically when you log in
- **Configurable refresh interval** - Poll every 1, 5, 15, or 30 minutes
- **Global keyboard shortcut** - Toggle the menu from anywhere (default: ⌘⇧P)

## Development

### Linting & Formatting

```bash
# Install tools (version-locked via Mintfile)
brew install mint
mint bootstrap

# Run checks
mint run swiftlint              # Check for lint issues
mint run swiftformat . --lint   # Check formatting

# Auto-fix
mint run swiftlint --fix        # Fix lint issues
mint run swiftformat .          # Format code
```

Alternatively, install directly via Homebrew (versions may vary):
```bash
brew install swiftlint swiftformat
```

### Pre-commit Hook

To run checks automatically before each commit:

```bash
# For Sapling
echo -e "\n[hooks]\npre-commit = ./scripts/pre-commit" >> .sl/config

# For Git
ln -s ../../scripts/pre-commit .git/hooks/pre-commit
```
