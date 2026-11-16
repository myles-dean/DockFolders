#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests/module-cache
xcrun swiftc -module-cache-path build/tests/module-cache \
    Sources/Agent/FolderPrefs.swift Sources/Agent/FolderLeaveTimer.swift Tests/HoverDelay/main.swift \
    -o build/tests/hover-delay
build/tests/hover-delay
