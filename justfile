# PR Monitor macOS App

# List available recipes
default:
    @just --list

# Generate Xcode project from project.yml
generate:
    xcodegen generate

# Build the app (regenerates project first)
build: generate
    xcodebuild -scheme PRMonitor -configuration Debug build

# Run the app (builds first, kills existing instance)
run: build
    -pkill -x PRMonitor
    @open "$( xcodebuild -scheme PRMonitor -configuration Debug -showBuildSettings 2>/dev/null | grep -m1 'BUILT_PRODUCTS_DIR' | awk '{print $3}' )/PRMonitor.app"

# Open the app without rebuilding
open:
    -pkill -x PRMonitor
    @open "$( xcodebuild -scheme PRMonitor -configuration Debug -showBuildSettings 2>/dev/null | grep -m1 'BUILT_PRODUCTS_DIR' | awk '{print $3}' )/PRMonitor.app"

# Run SwiftFormat to auto-fix formatting
format:
    if command -v mint >/dev/null 2>&1 && test -f Mintfile; then mint run swiftformat .; else swiftformat .; fi

# Run SwiftLint with auto-fix
lint-fix:
    if command -v mint >/dev/null 2>&1 && test -f Mintfile; then mint run swiftlint --fix; else swiftlint --fix; fi

# Check formatting and linting without modifying files
lint:
    if command -v mint >/dev/null 2>&1 && test -f Mintfile; then mint run swiftformat . --lint; else swiftformat . --lint; fi
    if command -v mint >/dev/null 2>&1 && test -f Mintfile; then mint run swiftlint; else swiftlint; fi

# Run unit tests
test: generate
    xcodebuild -scheme PRMonitor -configuration Debug -destination 'platform=macOS' test

# Clean build artifacts
clean:
    xcodebuild -scheme PRMonitor -configuration Debug clean
    rm -rf ~/Library/Developer/Xcode/DerivedData/PRMonitor-*

# Open project in Xcode
xcode: generate
    open PRMonitor.xcodeproj
