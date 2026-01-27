#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

CONFIGURATION="${1:-debug}"

case "$CONFIGURATION" in
    debug|Debug)
        CONFIGURATION="Debug"
        ;;
    release|Release)
        CONFIGURATION="Release"
        ;;
    *)
        echo "Usage: $0 [debug|release]"
        exit 1
        ;;
esac

echo "Building shotshot ($CONFIGURATION)..."

xcodebuild \
    -project shotshot.xcodeproj \
    -scheme shotshot \
    -configuration "$CONFIGURATION" \
    build \
    ONLY_ACTIVE_ARCH=YES

echo "Build completed successfully!"

if [ "$CONFIGURATION" == "Debug" ]; then
    APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "ShotShot.app" -path "*shotshot*Debug*" -type d 2>/dev/null | head -1)
else
    APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "ShotShot.app" -path "*shotshot*Release*" -type d 2>/dev/null | head -1)
fi

if [ -n "$APP_PATH" ]; then
    echo "App location: $APP_PATH"
fi
