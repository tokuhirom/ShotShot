#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Find the latest build
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "ShotShot.app" -path "*shotshot*Debug*" -type d 2>/dev/null | head -1)

if [ -z "$APP_PATH" ]; then
    echo "ShotShot.app not found. Building first..."
    "$SCRIPT_DIR/build.sh" debug
    APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "ShotShot.app" -path "*shotshot*Debug*" -type d 2>/dev/null | head -1)
fi

if [ -z "$APP_PATH" ]; then
    echo "Error: Could not find or build ShotShot.app"
    exit 1
fi

echo "Running: $APP_PATH"
"$APP_PATH/Contents/MacOS/ShotShot"
