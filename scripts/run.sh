#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOGS_DIR="$PROJECT_DIR/logs"
CRASH_LOGS_DIR=~/Library/Logs/DiagnosticReports

# Create the logs directory
mkdir -p "$LOGS_DIR"

# Log file name (with timestamp)
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOGS_DIR/shotshot_$TIMESTAMP.log"

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
echo "Log file: $LOG_FILE"
echo "---"

# Record the latest crash log before launch
BEFORE_CRASH=$(ls -t "$CRASH_LOGS_DIR" 2>/dev/null | grep -i shotshot | head -1)

# Output only to file (avoid TTY/pipe issues)
"$APP_PATH/Contents/MacOS/ShotShot" > "$LOG_FILE" 2>&1 &
APP_PID=$!
wait "$APP_PID"
EXIT_CODE=$?

# Check whether the app crashed
if [ $EXIT_CODE -ne 0 ]; then
    echo ""
    echo "=== App exited with code $EXIT_CODE ==="
    sleep 1  # Wait briefly for the crash log to be written

    AFTER_CRASH=$(ls -t "$CRASH_LOGS_DIR" 2>/dev/null | grep -i shotshot | head -1)

    if [ "$AFTER_CRASH" != "$BEFORE_CRASH" ] && [ -n "$AFTER_CRASH" ]; then
        CRASH_FILE="$CRASH_LOGS_DIR/$AFTER_CRASH"
        echo "=== Crash log found: $CRASH_FILE ==="
        echo ""
        # Show only the summary part of the crash log
        head -100 "$CRASH_FILE"
        echo ""
        echo "=== Full crash log: $CRASH_FILE ==="
    fi
fi
