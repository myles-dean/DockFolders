#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests/module-cache
xcrun swiftc -module-cache-path build/tests/module-cache \
    Sources/Agent/DockMenuLocalization.swift Tests/DockMenuLocalization/main.swift \
    -o build/tests/dock-menu-localization
build/tests/dock-menu-localization
