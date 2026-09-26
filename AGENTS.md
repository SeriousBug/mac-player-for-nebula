# Player for Nebula

Native macOS client for the Nebula video streaming service. macOS only.

## Stack

- Swift 6, SwiftUI, macOS 26+
- XcodeGen (`project.yml`) generates the Xcode project; `*.xcodeproj` is not committed
- `just` for build/run commands (see `justfile`)

## Layout

- `PlayerForNebula/`: app source, assets, entitlements
- `project.yml`: targets and build settings
