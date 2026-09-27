project := "PlayerForNebula.xcodeproj"
scheme := "PlayerForNebula"
derived := "build"
app_name := "Player for Nebula"

default: run

generate:
    xcodegen generate

build configuration="Debug": generate
    xcodebuild -project {{project}} -scheme {{scheme}} -configuration {{configuration}} -derivedDataPath {{derived}} -destination 'platform=macOS' build

# LaunchServices can reject the launch with error -609 right after the old instance exits.
run configuration="Debug": (build configuration)
    -pkill -x "{{app_name}}"
    while pgrep -x "{{app_name}}" >/dev/null; do sleep 0.1; done
    for i in 1 2 3 4 5; do open "{{derived}}/Build/Products/{{configuration}}/{{app_name}}.app" && exit 0; sleep 0.5; done; exit 1

open: generate
    open {{project}}

clean:
    rm -rf {{derived}} {{project}}

# Builds a universal Release DMG with an Applications shortcut for drag-and-drop install.
dmg: generate
    xcodebuild -project {{project}} -scheme {{scheme}} -configuration Release -derivedDataPath {{derived}} -destination 'generic/platform=macOS' build
    rm -rf {{derived}}/dmg "{{derived}}/{{scheme}}.dmg"
    mkdir -p {{derived}}/dmg
    cp -R "{{derived}}/Build/Products/Release/{{app_name}}.app" {{derived}}/dmg/
    ln -s /Applications {{derived}}/dmg/Applications
    hdiutil create -volname "{{app_name}}" -srcfolder {{derived}}/dmg -fs HFS+ -format UDZO "{{derived}}/{{scheme}}.dmg"
