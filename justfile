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
