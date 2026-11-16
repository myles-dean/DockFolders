#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests/module-cache
xcrun swiftc -sdk "${DF_TEST_SDK:-$(xcrun --show-sdk-path)}" -module-cache-path build/tests/module-cache \
    Sources/Agent/FolderView.swift Sources/Agent/DockGlass.swift Tests/HoverLabels/main.swift \
    -o build/tests/hover-labels
build/tests/hover-labels
