<p align="center">
  <img src="docs/logo.png" width="160" height="160" alt="Dock Folders app icon: four app tiles in a dark rounded square">
</p>

<h1 align="center">Dock Folders</h1>

<p align="center">
  <b>iPhone-style app folders for the macOS Dock.</b><br>
  Group your apps into folders right in the Dock, open them in a Liquid Glass popup, and keep your Dock tidy.<br>
  Free and open source, made for macOS 26 Tahoe.
</p>

<p align="center">
  <a href="https://github.com/myles-dean/DockFolders/releases/latest/download/DockFolders.dmg"><b>⬇︎ Download Dock Folders (DMG)</b></a>
  &nbsp;·&nbsp; <a href="#features">Features</a>
  &nbsp;·&nbsp; <a href="#install">Install</a>
  &nbsp;·&nbsp; <a href="#how-to-use-it">How to use it</a>
  &nbsp;·&nbsp; <a href="#faq">FAQ</a>
</p>

<p align="center">
  <img alt="macOS 26 Tahoe or later" src="https://img.shields.io/badge/macOS-26%20Tahoe%2B-111111?logo=apple&logoColor=white">
  <img alt="For Macs with Apple silicon" src="https://img.shields.io/badge/Apple%20silicon-native-0a84ff">
  <img alt="Written in Swift" src="https://img.shields.io/badge/Swift-SwiftUI%20%2B%20AppKit-f05138?logo=swift&logoColor=white">
  <img alt="MIT License" src="https://img.shields.io/badge/license-MIT-34c759">
  <a href="https://github.com/myles-dean/DockFolders/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/myles-dean/DockFolders?label=release"></a>
</p>

<p align="center">
  <a href="https://ko-fi.com/mylesdean_"><img alt="Buy me a coffee on Ko-fi" src="https://img.shields.io/badge/Buy%20me%20a%20coffee-FF5E5B?style=for-the-badge&logo=kofi&logoColor=white"></a>
</p>

<p align="center">
  <img src="docs/demo.gif" width="872" alt="Dock Folders demo: the pointer moves to the Dock, hovers the Utilities folder and clicks it, and a Liquid Glass popup opens above it showing eight apps">
</p>

---

**Dock Folders** adds folders to the Mac Dock, the way folders work on an iPhone or iPad. Drag one
app onto another in the Dock to make a folder; click the folder to open its apps in a Liquid Glass
popup at the Dock's own icon size. It's a simple way to **organize your Dock**, **group apps in the
Dock**, and get back the **app folders Launchpad used to have**: macOS 26 Tahoe replaced Launchpad
with an Apps view that can't keep folders.

No menu bar icon, no screen recording, no network access. It runs quietly in the background and
starts at login.

## Features

- **Real folders in the Dock.** Each folder is a Dock icon showing its first four apps (2×2), with
  the Dock's own name label and a running dot while any app inside is open.
- **Liquid Glass popup.** Click a folder and its apps appear in clear macOS 26 glass, at the Dock's
  icon size and spacing, with Dock-style magnification. Pages of 3, 6, 9 or 16 apps, with
  two-finger swipes and page dots.
- **Drag and drop, like iOS.**
  - Drag an app onto another app and hold: **Create Folder**, named by category ("Games",
    "Productivity & Finance", "Creativity"…).
  - Drag an app onto a folder and hold: the folder springs open and the app goes in.
  - Drag a folder onto a folder to **merge** them.
  - Drag an app out of an open folder onto the Dock to put it back.
- **Right-click menus in glass.** Each app inside a folder gets its Dock menu (windows, Show All
  Windows, Hide, Quit, Force Quit). Folders get Edit Name, Add Apps, Empty Folder and Settings.
- **Live Dock changes.** Folders join and leave the Dock without restarting it (no wallpaper or menu
  bar flash).
- **Optional: open on hover.** Folders can open when the pointer rests on them. In Settings → General, adjust the open and close delays independently from 0 to 2 seconds with continuous sliders or numeric input (default: 0.3 seconds each). The close delay also applies to folders opened by clicking; returning to the folder or its Dock tile cancels the pending close.
- **App names on hover.** Point at an app inside a folder to show its name in a Dock-style glass callout above the icon, including while icons are magnified. Long names truncate to fit the visible screen area.
- **Optional: open apps only in their folders.** For Macs with System Integrity Protection partly
  off ([details below](#optional-open-apps-only-in-their-folders)).
- **Native and accessible.** Light, Dark and tinted appearances; Reduce Transparency makes it
  solid; works with a Dock on the bottom, left or right, auto-hiding or not.

## Install

1. **[Download DockFolders.dmg](https://github.com/myles-dean/DockFolders/releases/latest/download/DockFolders.dmg)**
   and drag **Dock Folders** into **Applications**.
2. Open it. A setup window walks you through two permissions in System Settings → Privacy &
   Security:
   - **Accessibility**, so it can see the Dock and open a folder when you click it.
   - **App Management**, because each folder in the Dock is a small app that Dock Folders makes and
     updates, and macOS only lets apps change other apps with this permission.
3. Drag an app onto another app in the Dock and hold it there until **Create Folder** appears.

Or with [Homebrew](https://brew.sh):

```bash
brew tap myles-dean/tap
brew trust myles-dean/tap
brew install --cask dock-folders
```

Requires **macOS 26 Tahoe** or later on a Mac with Apple silicon.

## How to use it

| To | Do this |
| --- | --- |
| Make a folder | Drag an app onto another app in the Dock and hold it until **Create Folder** appears, then let go; or **+** in Settings |
| Move a Dock app into a folder | Drag it onto the folder and hold it there until the folder opens, then let go (on the folder or inside it). An app lives in one folder at a time, so this moves it out of any other |
| Move an app from a folder to the Dock | Drag it out of the open folder and drop it on the Dock where you want it |
| Add any app | Drag it from Finder or the Apps window onto the folder in the Dock, or use **+** above the app list in Settings |
| Open / close a folder | Click it. Move off its sides or top (it closes at once, like moving off the Dock), move away for a moment, click outside, or launch an app to close it |
| Turn pages | Two-finger swipe, or click the dots |
| Rearrange apps in a folder | Drag an icon; hold it near the left/right edge to change pages |
| Rename a folder, add apps | Right-click the folder → **Edit Name…** (opens Settings with the name ready to type) or **Add Apps…** (opens Settings with the app picker) |
| Put a folder's apps back in the Dock | Right-click the folder → **Empty Folder** (the apps take the folder's place and the folder goes; one Dock refresh, since closed apps can only be added to the Dock that way) |
| Remove/reorder apps, show/hide a folder in the Dock, delete it, options | Right-click the folder → **Settings…** (or open Dock Folders from Spotlight) |
| Take an app out | Right-click it in the folder → Options → **Remove from Folder** or **Move to Dock** |
| Apps per page (3, 6, 9 or 16), names or running dots under apps, icon size, magnification | Settings → ⚙︎ General → **Inside Folders** |
| Rearrange folders in the Dock | Drag them like any other Dock icon |


Settings opens from a folder's right-click menu, or by opening Dock Folders again from Spotlight or
Applications. Under ⚙︎ General you'll find apps per page, names or running dots under icons, icon
size, magnification, **Open folders on hover**, and the optional feature below.

## FAQ

**Does Dock Folders change my apps?**
No. Your apps stay exactly as they are. Each folder is its own tiny app (in
`~/Library/Application Support/Dock Folders/Folders/`) that sits in the Dock in its place.

**Why does it need App Management?**
Making, renaming and removing a folder means making and updating that folder's little app, and
macOS asks before one app changes another. Dock Folders only ever touches its own folder apps.

**Why did macOS say a "Dock tile extension" was added?**
Each folder's icon is drawn by a small Dock tile plug-in, and macOS announces new ones. Folders
reuse a few slots, so you'll only see it the first few times.

**Why does the Dock sometimes refresh when my Mac locks?**
The Dock only reads new names (and apps added back while closed) when it starts, so Dock Folders
saves those for a moment you won't see it: when your Mac locks or its display sleeps. **Update Now**
in Settings does it right away.

**Can open apps show only inside their folder, not also on their own?**
macOS gives every open app its own Dock icon and only lets the Dock itself hide one. Dock Folders
can do it if you turn part of System Integrity Protection off; see below.

**Does it collect data or use the internet?**
No. It has no network code at all.

**How do I uninstall it?**
Right-click each folder → **Empty Folder** to put its apps back in the Dock, quit Dock Folders from
Settings, then move it to the Trash and delete `~/Library/Application Support/Dock Folders`. If you
used the optional Dock helper, click **Remove Helper…** in Settings first.

## Optional: open apps only in their folders

**Settings → General → Open apps only in their folders** keeps an open app's own icon out of the
Dock when the app lives in a folder: it shows only inside its folder, and keeps its menu bar,
⌘-Tab entry and Force Quit listing. macOS only lets the Dock itself do that, so this needs System
Integrity Protection partly off, like [yabai](https://github.com/koekeishiya/yabai)'s scripting
addition. Settings walks you through it:

1. In Recovery, run `csrutil enable --without fs --without debug --without nvram`, then restart.
2. On Apple silicon, run `sudo nvram boot-args=-arm64e_preview_abi`, then restart again.
3. Turn the option on. Dock Folders asks for an administrator password once to install a small
   helper (`/Library/PrivilegedHelperTools/com.mylesdean.DockFolders.helper`, a launchd daemon).

The helper loads `DockFoldersHook.dylib` into the Dock each time it starts. Inside the Dock, it
stops running-app icons from being added for apps in folders, and hands icons already there to the
Dock's own "app went into the background" handling. If the Dock keeps quitting right after it
loads (after a macOS update, say), the helper pauses itself and Settings tells you. Turning the
option off restarts the Dock without it; **Remove Helper…** uninstalls it. To turn SIP back on,
run `csrutil enable` in Recovery (and `sudo nvram -d boot-args`).

> [!WARNING]
> SIP protects your Mac from malware; turning part of it off lowers that protection. This option
> is experimental: it has been checked against the Dock in macOS 26.6 by reading its code, but not
> yet run on a Mac with SIP off.

## Building from source

```bash
git clone https://github.com/myles-dean/DockFolders.git
cd DockFolders
./build.sh            # builds build/Dock Folders.app
./build.sh install    # also copies it to /Applications and opens it
./build.sh release    # Developer ID–signed build/DockFolders.dmg (set NOTARY_PROFILE to notarize)
```

Needs the Xcode 26 command-line tools; no Xcode project. Development builds are signed with your
"Apple Development" identity when there is one, so permissions survive rebuilds.

<details>
<summary><b>How it works</b> (technical details)</summary>

## How it works

No screen capturing, and (unless you turn on the optional feature below) no code inside the Dock:
everything uses system mechanisms.

- **Folder tiles.** Each folder is a tiny app bundle in
  `~/Library/Application Support/Dock Folders/Folders/`, added to the Dock's own app list.
  Its icon is drawn by a **Dock tile plug-in** (`NSDockTilePlugIn`, the mechanism Calendar uses for
  its date), so the 2×2 icon updates live. The agent renders the tile image; the plug-in shows it.
  macOS only loads a third-party Dock plug-in after the app has been launched once, so each new
  stub is launched once, invisibly, with `--register`.
- **Clicks.** A Quartz event tap sees clicks on folder tiles before the Dock does and opens the
  popup instead of launching the stub. Drags are replayed to the Dock, so rearranging still works.
  If Dock Folders isn't running, clicking a folder launches its stub, which starts Dock Folders and
  opens the folder.
- **Popup.** A non-activating panel (your current app stays frontmost) with SwiftUI's
  `glassEffect` in a custom callout shape, so it matches the Dock's light, dark or tinted glass.
- **Keeping the Dock up.** While the pointer is in the popup (or on its way there), the Dock is
  put into its keyboard-focus state through Accessibility. That holds an auto-hiding Dock on
  screen without turning auto-hide off, which would resize full-screen and tiled windows. Back on
  the Dock the hold is released, so the Dock's own hover and magnification carry on.
- **Following the tile.** Every frame the popup reads the folder tile's frame and places its
  pointer where the Dock draws that tile's name label (measured: 5 pt pointer, tip 7.5 pt inside
  the tile's top). That keeps it clear of the Dock and hides the Dock's own label behind it (the
  glass blurs it away; a faint neutral veil evens out what's left).
- **Empty folders.** Taking the last app out of a folder from the folder itself (dragging it out,
  **Move to Dock** or **Remove from Folder**) deletes the folder, like iOS. Empty folders made or
  emptied in Settings stay, out of the Dock, and join it when their first app is added (unless you
  turned **Show in Dock** off, which is remembered).
- **Changing the Dock without restarting it.** Restarting the Dock redraws the wallpaper and the
  menu bar, so Dock Folders avoids it. It changes the Dock through the Dock's own right-click menu
  instead (**Options ▸ Keep in Dock / Remove from Dock**, pressed through Accessibility, in the
  Mac's language); the menu shows for a moment. Folder tiles join silently: the folder's
  little app runs for a moment, so its tile is an ordinary running app's, which **Keep in Dock**
  keeps. Tiles leave with **Remove from Dock** and the Dock's usual poof (letting a running tile
  go instead would show a running dot first). New folders appear at the end of the Dock's apps.
- **Dragging an app into a folder.** The Dock owns drags of its tiles (and slides tiles aside to
  make room), so Dock Folders watches the drag through its event tap and remembers where each
  folder sat when it started. Hold the app there for a moment and the folder springs open,
  outlined; let go on the folder or inside it and the app goes in (the Dock removes its tile). A
  quick pass over a folder doesn't count, so rearranging the Dock works as usual.
- **Making a folder by dragging.** Holding a dragged app over another app shows a **Create
  Folder** tag above it, drawn like the Dock's own name tags. Let go and both apps' tiles leave the
  Dock together, then the folder comes in where they were: its little app runs, so the Dock adds it
  like any app that opens, and it's slid under the pointer with a drag sent only to the Dock (the
  Dock drops dragged tiles under the real pointer, so this needs the pointer still on the Dock).
  Moving an open app's tile also keeps it in the Dock, so no menu is involved.
- **Folder names.** New folders are named after their apps' App Store categories
  (`LSApplicationCategoryType`), like iOS: two games make "Games"; related categories get a group
  name ("Creativity", "Productivity & Finance", "Utilities"…); otherwise the category of the app
  it was dropped onto. Apps that don't declare one give "Folder".
- **Dragging an app out of a folder.** Once the icon is carried past the folder's edge it becomes
  a real drag of the app, like one from Finder, so the Dock makes room and adds it where you let go.
  It's offered only as a link, and only over the Dock: let go anywhere else and it slides back.
- **Saved for a quiet moment.** A few changes still need a restart: new names (the Dock only reads
  names when it starts) and putting an app that isn't running back in the Dock. They wait until your Mac locks or its display sleeps,
  so you never see the restart; **Update Now** in Settings does it straight away. If Dock Folders
  quits first, it picks pending names up again from the Dock.
- **Glass finish.** The popup is clear Liquid Glass over whatever is behind it, with the Dock's
  crisp 1 pt rim (brightest along the top); labels and menus also take the Dock's deeper tone in
  Dark Mode. With **Reduce Transparency** on, all of it turns solid, like the rest of macOS.
- **Menus.** Right-click menus are drawn in Liquid Glass rather than with `NSMenu`, because a
  native menu takes keyboard focus away from the Dock, which then slides away.

</details>

## Limitations

These come from what macOS lets other apps do with the Dock (changing them would need code
running inside the Dock, which needs System Integrity Protection turned off):

- **No "jiggle" mode.** The Dock draws its own icons; other apps can't animate them. Folders are
  made by dragging an app onto another and holding.
- **Nothing can be added to the Dock's own right-click menu** (for apps). A folder's own menu is
  drawn by Dock Folders in glass.
- **A one-time "Dock tile extension" notice.** Each folder's icon is drawn by a small Dock tile
  plug-in, and macOS announces a new one. Folders reuse a few identifiers ("slots"), so the notice
  only appears the first time a slot is used (about once per folder you keep at the same time),
  not every time you make one.
- **Open apps also appear in the Dock**, unless you use the [optional feature](#optional-open-apps-only-in-their-folders). macOS shows every
  running app there; only the Dock itself can leave one out.
- **The folder's tile is dimmed while its folder is open** (with an auto-hiding Dock). Keeping the
  Dock up means putting it in its keyboard mode, where it always marks one item: marking the
  folder's tile dims it; marking anything else shows a stray name label.
- **New names reach the Dock only when it restarts.** That happens when your Mac next locks or
  sleeps, so you don't see it, or straight away with **Update Now** in Settings. Moving an app that
  isn't open from a folder back to the Dock with **Move to Dock** waits for that too (dragging it
  onto the Dock doesn't).
- **Live Dock changes show the Dock's menu for a moment.** Apple's call for adding items to the
  Dock (`CoreDockAddFileToDock`) is reserved for Finder and Safari, so changes go through the
  Dock's own **Keep in Dock / Remove from Dock**; tiles leaving get the Dock's usual poof.
- **App-specific Dock menu items** (Music's playback controls, Notes' New Note) aren't available
  to other apps, so the in-folder menu has the standard items only.

## Project layout

```
Sources/Agent/       the background app (event tap, popup, menus, Dock and folder management)
Sources/Stub/        the small per-folder app that sits in the Dock
Sources/TilePlugin/  the Dock tile plug-in that draws a folder's icon
Sources/DockHook/    the optional Dock helper and payload (SIP partly off only)
Sources/Shared/      constants shared by the parts above
Resources/           Info.plists
docs/                images for this page
build.sh             builds, signs, installs and packages
```

Folder data lives in `~/Library/Application Support/Dock Folders/folders.json`.

## Contributing

Issues and pull requests are welcome. Dock Folders leans on how the macOS 26 Dock behaves, so
reports that include your macOS version and Dock settings (position, auto-hide, magnification)
help most.

## License

[MIT](LICENSE) © 2026 Myles Dean. The optional Dock helper's loader is adapted from
[yabai](https://github.com/koekeishiya/yabai) (MIT, © Åsmund Vikane), with its arm64e path based on
work by [Jeremy Legendre](https://github.com/jslegendre).
