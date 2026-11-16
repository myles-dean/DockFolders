# Dock pinning on non-English systems

## Cause

On a simplified-Chinese macOS 27.2 system, creating a populated folder or enabling
Show in Dock briefly showed its tile, then removed it. Dragging the generated
folder app from Finder to the Dock worked.

DockLive's log reported `no Options submenu`, although the recorded menu contained
`选项`. Calling `localizedString` on the Dock's bundle inherited this English-only
app's language: the bundle's preferred localization was `en`, while
`Locale.preferredLanguages` was `zh-Hans-CN`. Consequently Options, Keep in Dock
and Remove from Dock were all matched against English strings.

## Change

Select the Dock's `.lproj` explicitly using its AppleLanguages override, or the
user's preferred languages when no override exists. Foundation's localization
matching resolves language identifiers such as `zh-Hans-CN` to Apple's `zh_CN`
resource folder. Read the existing DockMenus strings from that bundle and retain
the English fallback when resources or keys are unavailable.

This fixes the language mismatch shared by folder pinning and app removal without
rewriting Dock preferences or restarting the Dock.

## Validation

Run `bash Tests/test-dock-menu-localization.sh` on macOS. It checks the real Dock
menu titles in simplified Chinese, traditional Chinese, English and Japanese,
unsupported-language priority, and the missing-key fallback.

To build with the installed macOS 26 SDK on a machine whose macOS 27 command-line
tools lack SwiftUIMacros, pass an explicit SDK via the existing build option:

```sh
DF_SWIFT_FLAGS="-sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk" ./build.sh
```

Manual acceptance checks (still required after granting the built app Accessibility
and App Management permissions):

1. On a Chinese system, create a populated folder in Settings. Its tile should stay
   after the temporary folder process exits, without dragging anything from Finder.
2. Toggle Show in Dock off, then on. The tile should disappear, then stay visible.
3. Combine two Dock apps into a folder; check the folder stays and the original app
   tiles are no longer pinned.
4. Repeat on an English system; also check a per-app language override for the Dock.

The regression test and a full build do not substitute for these UI checks.
