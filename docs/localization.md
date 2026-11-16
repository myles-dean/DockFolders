# Interface languages

Dock Folders supports English and simplified Chinese. The first launch asks for a
language before checking or requesting permissions. Settings → General → Language
offers System Default, English and 简体中文. Choosing a language updates the app's
views and menus immediately and persists across launches. The Continue button
confirms first-run selection separately; changing the picker alone does not skip
setup.

App-owned copy lives in `Resources/en.lproj/Localizable.strings` and
`Resources/zh-Hans.lproj/Localizable.strings`. `L10n.text` performs an explicit bundle
lookup, and `L10n.format` substitutes user content after translation. The build
copies both localization directories into the agent. It does not add localization
code to the folder stubs or the Dock plug-in.

Window/controller models survive language changes; SwiftUI view-local content is
rebuilt with the selected locale. The native main menu is rebuilt, and open custom
menus/popups are dismissed so their next presentation uses the new language.
Existing folder names, application names, window titles, paths and shell commands
are user/application data and are not rewritten. New automatically named folders
use localized category names. macOS-owned dialogs continue to use macOS's own
localization.

## Apple terminology

Shared actions use the installed simplified-Chinese macOS resources as the source
of truth, rather than translating English labels independently:

| Source | Examples |
| --- | --- |
| Dock.app, `zh_CN.lproj/DockMenus.strings` | 选项、在访达中显示、登录时打开、强制退出、在程序坞中保留 |
| AppKit, `MenuCommands.loctable` | 剪切、拷贝、粘贴、全选 |
| AppKit, `FunctionKeyNames.loctable` | 撤销、重做 |
| AppKit, `Common.loctable` and `SavePanel.loctable` | 取消、删除、好、保存 |
| SecurityPrivacyExtension, `Localizable.loctable` | App管理 |

Finder/other macOS terminology is used for 新建文件夹、重新命名、辅助功能、系统设置、
隐私与安全性、通用、放大、实用工具、终端 and macOS 恢复. App-specific descriptions
use the same terms consistently. App Store category keys are scoped separately;
the category Utilities is 工具, while the macOS Utilities folder is 实用工具.

The interface language setting does not change the system's Dock language or
rewrite `AppleLanguages`. Dock automation keeps using its existing language
resolution; the explicit Dock-language fix is tracked separately in PR #1.

## Validation

```sh
DF_TEST_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk bash Tests/test-localization.sh
```

When PR #1 is included, also run its `Tests/test-dock-menu-localization.sh`
regression check to verify the system menu matching independently of UI language.

The audit checks catalogue parity, app string coverage, format placeholders and
exact matches against Apple's installed terminology. The Swift test checks system
language resolution, saved selection, confirmation gating, language switching,
packaged resource loading, missing-key fallback and formatted user content.

For UI QA, inspect both languages on the first-run language page, permission page,
General and folder settings, including narrow windows and the disabled permission
state. Check switching languages from Settings, then open app/folder menus and
the Add Apps panel. Existing names should stay unchanged. Permission prompts must
not appear before Continue on the initial language page.
