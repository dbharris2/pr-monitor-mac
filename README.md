# PR Monitor

A macOS menu bar app for monitoring GitHub pull requests.

## Requirements

- macOS 26+ (to build)
- Xcode 26+ (Swift 6.2)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- [GitHub CLI (`gh`)](https://cli.github.com), authenticated via `gh auth login`

The app runs on macOS 14+.

## Build & Run

```bash
# Install dependencies
brew install xcodegen just

# Build and run
just run
```

Or open in Xcode and press ⌘R:

```bash
just xcode
```

## Setup

PR Monitor uses your existing GitHub CLI authentication — no token setup in the app.

1. Install and sign in to the GitHub CLI:
   ```bash
   brew install gh
   gh auth login
   ```
2. Run PR Monitor (it appears in your menu bar). It picks up your `gh` credentials automatically.
3. If `gh` isn't installed or you're not signed in, the menu bar Settings panel will show install/sign-in instructions.

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

### Common Commands

All common tasks are available via [`just`](https://github.com/casey/just):

```bash
just          # List all available commands
just build    # Generate project + build
just run      # Build + launch app
just open     # Relaunch without rebuilding
just lint     # Check formatting + linting
just format   # Auto-fix formatting
just lint-fix # Auto-fix lint issues
just clean    # Remove build artifacts
just xcode    # Open project in Xcode
```

### Linting & Formatting

Lint tools are version-locked via Mintfile:

```bash
brew install mint
mint bootstrap
```

Alternatively, install directly via Homebrew (versions may vary):
```bash
brew install swiftlint swiftformat
```
