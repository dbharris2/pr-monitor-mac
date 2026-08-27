#!/usr/bin/env bash
set -euo pipefail

swiftlint_version=$(grep '^realm/SwiftLint@' Mintfile | cut -d@ -f2)
swiftformat_version=$(grep '^nicklockwood/SwiftFormat@' Mintfile | cut -d@ -f2)

if [ -z "$swiftlint_version" ] || [ -z "$swiftformat_version" ]; then
    echo "Failed to parse versions from Mintfile" >&2
    exit 1
fi

curl -sL "https://github.com/realm/SwiftLint/releases/download/$swiftlint_version/portable_swiftlint.zip" -o swiftlint.zip
unzip -q swiftlint.zip -d swiftlint
sudo mv swiftlint/swiftlint /usr/local/bin/

curl -sL "https://github.com/nicklockwood/SwiftFormat/releases/download/$swiftformat_version/swiftformat.zip" -o swiftformat.zip
unzip -q swiftformat.zip
sudo mv swiftformat /usr/local/bin/

# macOS arm64 runners put Homebrew's /opt/homebrew/bin ahead of /usr/local/bin.
# Prepend the install directory so Xcode build scripts use these exact binaries.
export PATH="/usr/local/bin:$PATH"
if [ -n "${GITHUB_PATH:-}" ]; then
    echo "/usr/local/bin" >> "$GITHUB_PATH"
fi

swiftlint version
swiftformat --version
