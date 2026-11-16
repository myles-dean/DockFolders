#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 Tests/Localization/audit.py
TEST_APP="$PWD/build/tests/LocalizationTests.app"
mkdir -p "$TEST_APP/Contents/MacOS" "$TEST_APP/Contents/Resources" build/tests/module-cache
cp -R Resources/en.lproj Resources/zh-Hans.lproj "$TEST_APP/Contents/Resources/"
cat > "$TEST_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.mylesdean.DockFolders.LocalizationTests</string><key>CFBundleExecutable</key><string>LocalizationTests</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
xcrun swiftc -swift-version 5 -sdk "${DF_TEST_SDK:-$(xcrun --show-sdk-path)}" -module-cache-path build/tests/module-cache \
    Sources/Agent/Localization.swift Tests/Localization/main.swift \
    -o "$TEST_APP/Contents/MacOS/LocalizationTests"
"$TEST_APP/Contents/MacOS/LocalizationTests" -interfaceLanguage zh-Hans
