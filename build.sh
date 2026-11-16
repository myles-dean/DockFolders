#!/bin/bash
# Builds "Dock Folders.app" into ./build.
#   ./build.sh           build only
#   ./build.sh install   build, copy to /Applications and (re)launch
#   ./build.sh release   Developer ID build (hardened runtime) packaged as build/DockFolders.dmg;
#                        with NOTARY_PROFILE=<notarytool keychain profile> it's notarized and stapled
set -euo pipefail
cd "$(dirname "$0")"
MODE="${1:-}"

BUILD="$PWD/build"
APP="$BUILD/Dock Folders.app"
STUB="$APP/Contents/Resources/FolderStub.app"
PLUGIN="$STUB/Contents/PlugIns/FolderTile.docktileplugin"
SWIFTC=(xcrun swiftc -target arm64-apple-macos26.0 -O -swift-version 5 ${DF_SWIFT_FLAGS:-})

if [[ "$MODE" == "release" ]]; then
    # What Gatekeeper and notarization need: Developer ID, the hardened runtime, a secure timestamp.
    IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')}"
    [[ -n "$IDENTITY" ]] || { echo "✗ No \"Developer ID Application\" certificate in your keychain" >&2; exit 1; }
    NESTED="$IDENTITY"
    SIGN=(--options runtime --timestamp)
else
    # A stable signing identity keeps the Accessibility permission across rebuilds.
    IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}"
    IDENTITY="${IDENTITY:--}"
    NESTED="-"
    SIGN=(--timestamp=none)
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" \
         "$STUB/Contents/MacOS" "$STUB/Contents/Resources" "$PLUGIN/Contents/MacOS"

# Changes to the stub or plug-in make the agent rebuild existing folder stubs on next launch
# (which restarts the Dock, so only real changes should). Bump STUB_BUILD when the way they're
# built changes; other edits to this script don't count.
STUB_BUILD=1
TEMPLATE_HASH=$( (cat Sources/Shared/*.swift Sources/Stub/*.swift Sources/TilePlugin/*.swift \
                    Resources/Stub-Info.plist Resources/TilePlugin-Info.plist; echo "$STUB_BUILD") | shasum -a 256 | cut -c1-16)

echo "→ Dock tile plug-in"
# The Dock only loads Mach-O bundles (MH_BUNDLE), not dylibs.
"${SWIFTC[@]}" -emit-executable -Xlinker -bundle -module-name FolderTile \
    Sources/Shared/*.swift Sources/TilePlugin/*.swift -o "$PLUGIN/Contents/MacOS/FolderTile"
cp Resources/TilePlugin-Info.plist "$PLUGIN/Contents/Info.plist"

echo "→ Folder stub"
"${SWIFTC[@]}" -module-name FolderStub Sources/Shared/*.swift Sources/Stub/main.swift -o "$STUB/Contents/MacOS/FolderStub"
cp Resources/Stub-Info.plist "$STUB/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :DFTemplateHash string $TEMPLATE_HASH" "$STUB/Contents/Info.plist"

echo "→ Dock Folders agent"
"${SWIFTC[@]}" -module-name DockFolders Sources/Shared/*.swift Sources/Agent/*.swift -o "$APP/Contents/MacOS/Dock Folders"
cp Resources/Agent-Info.plist "$APP/Contents/Info.plist"
cp -R Resources/en.lproj Resources/zh-Hans.lproj "$APP/Contents/Resources/"

echo "→ Dock helper (only used with System Integrity Protection partly off)"
# arm64e: on Apple silicon the loader signs a thread's start address for the Dock, and the
# payload runs inside the Dock (an arm64e process). Both need the -arm64e_preview_abi boot-arg.
HOOK="$APP/Contents/Resources/DockHook"
mkdir -p "$HOOK"
CLANG=(xcrun clang -fobjc-arc -O2 -mmacosx-version-min=26.0 -arch arm64e -arch x86_64 -Wall -Wno-unused-function)
"${CLANG[@]}" -dynamiclib Sources/DockHook/payload.m -framework Foundation -o "$HOOK/DockFoldersHook.dylib"
"${CLANG[@]}" Sources/DockHook/helper.m Sources/DockHook/loader.m -framework Foundation -o "$HOOK/DockFoldersHelper"
cp Sources/DockHook/install.sh Sources/DockHook/uninstall.sh Sources/DockHook/com.mylesdean.DockFolders.helper.plist "$HOOK/"

echo "→ Icons"
# From Resources/AppIcon.png (fitted to the macOS icon grid) when it's there.
ARTWORK=()
[[ -f Resources/AppIcon.png ]] && ARTWORK=("$PWD/Resources/AppIcon.png")
"$APP/Contents/MacOS/Dock Folders" --render-icon "$APP/Contents/Resources/AppIcon.icns" ${ARTWORK[@]+"${ARTWORK[@]}"}
cp "$APP/Contents/Resources/AppIcon.icns" "$STUB/Contents/Resources/AppIcon.icns"

echo "→ Signing ($IDENTITY)"
codesign --force --sign "$NESTED" "${SIGN[@]}" --entitlements Sources/DockHook/helper.entitlements "$HOOK/DockFoldersHelper"
codesign --force --sign "$NESTED" "${SIGN[@]}" "$HOOK/DockFoldersHook.dylib"
codesign --force --sign "$NESTED" "${SIGN[@]}" "$PLUGIN"
codesign --force --sign "$NESTED" "${SIGN[@]}" "$STUB"
codesign --force --sign "$IDENTITY" "${SIGN[@]}" "$APP"

echo "✓ Built $APP"

if [[ "$MODE" == "release" ]]; then
    echo "→ Disk image"
    DMG="$BUILD/DockFolders.dmg"
    STAGE="$BUILD/dmg"
    rm -rf "$STAGE" "$DMG"
    mkdir -p "$STAGE"
    ditto "$APP" "$STAGE/Dock Folders.app"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "Dock Folders" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
    rm -rf "$STAGE"
    codesign --force --sign "$IDENTITY" --timestamp "$DMG"
    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
        echo "→ Notarizing (a few minutes)"
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG"
        echo "✓ Notarized and stapled"
    else
        echo "  Not notarized. Once:  xcrun notarytool store-credentials DockFolders --apple-id <you> --team-id <team>"
        echo "  Then:                 NOTARY_PROFILE=DockFolders ./build.sh release"
    fi
    echo "✓ $DMG"
fi

if [[ "$MODE" == "install" ]]; then
    echo "→ Installing to /Applications"
    pkill -x "Dock Folders" 2>/dev/null || true
    sleep 0.5
    rm -rf "/Applications/Dock Folders.app"
    ditto "$APP" "/Applications/Dock Folders.app"
    # Only the installed copy should handle dockfolders:// links.
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$APP" 2>/dev/null || true
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/Dock Folders.app"
    open "/Applications/Dock Folders.app"
    echo "✓ Installed and launched"
fi
