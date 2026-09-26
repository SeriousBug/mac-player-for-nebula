project := "PlayerForNebula.xcodeproj"
scheme := "PlayerForNebula"
derived := "build"
app_name := "Player for Nebula"

default: run

generate:
    xcodegen generate

build configuration="Debug": generate
    xcodebuild -project {{project}} -scheme {{scheme}} -configuration {{configuration}} -derivedDataPath {{derived}} -destination 'platform=macOS' build

run configuration="Debug": (build configuration)
    -pkill -x "{{app_name}}"
    open "{{derived}}/Build/Products/{{configuration}}/{{app_name}}.app"

open: generate
    open {{project}}

clean:
    rm -rf {{derived}} {{project}}
