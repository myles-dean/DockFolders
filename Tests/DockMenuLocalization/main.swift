import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

guard let dock = Bundle(path: "/System/Library/CoreServices/Dock.app") else {
    fatalError("Run this regression test on macOS")
}

// Real Dock resources catch the original main-bundle language inheritance bug, as well as
// Apple's non-BCP-47 resource names (zh_CN / zh_TW instead of zh-Hans / zh-Hant).
let cases: [(String, String, String, String)] = [
    ("zh-Hans-CN", "选项", "在程序坞中保留", "从程序坞中移除"),
    ("zh-Hant-TW", "選項", "保留在Dock上", "從Dock中移除"),
    ("en", "Options", "Keep in Dock", "Remove from Dock"),
    ("ja", "オプション", "Dockに残す", "Dockから削除"),
]
for (language, options, keep, remove) in cases {
    guard let bundle = DockMenuLocalization.localizedBundle(in: dock, preferences: [language]) else {
        fatalError("Missing Dock localization: \(language)")
    }
    for (key, expected) in [("OPTIONS", options), ("KEEP_IN_DOCK", keep), ("REMOVE_FROM_DOCK", remove)] {
        let actual = bundle.localizedString(forKey: key, value: "missing", table: "DockMenus")
        expect(actual == expected, "\(language) \(key): expected \(expected), got \(actual)")
    }
}

let preferred = DockMenuLocalization.localizedBundle(in: dock, preferences: ["xx-Unknown", "zh-Hans-CN", "en"])
expect(preferred?.localizedString(forKey: "OPTIONS", value: nil, table: "DockMenus") == "选项",
       "Must respect the next supported language")
expect(DockMenuLocalization.title("DOCK_FOLDERS_MISSING_TEST_KEY", fallback: "Fallback") == "Fallback",
       "Unknown keys must retain their fallback")

print("PASS: Dock menu titles in simplified/traditional Chinese, English and Japanese; language priority and missing-key fallback")
