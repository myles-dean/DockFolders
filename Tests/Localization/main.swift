import Foundation

final class MemoryDefaults: UserDefaults, @unchecked Sendable {
    var values: [String: Any] = [:]
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func persistentDomain(forName name: String) -> [String: Any]? {
        name == UserDefaults.globalDomain ? ["AppleLanguages": ["zh-Hans-CN", "en"]] : nil
    }
}

let defaults = MemoryDefaults(suiteName: "DockFoldersLocalizationTests")!
let language = Localization(defaults: defaults)
precondition(language.selection == .system && language.effectiveLanguage == .simplifiedChinese)
precondition(!language.hasChosen)
language.select(.english)
precondition(language.effectiveLanguage == .english)
precondition(!language.hasChosen, "Selecting a language must not bypass Continue")
precondition(Localization(defaults: defaults).selection == .english, "Selection must survive relaunch")
language.confirm()
precondition(Localization(defaults: defaults).hasChosen)
language.select(.simplifiedChinese)
precondition(language.effectiveLanguage == .simplifiedChinese)
language.select(.system)
precondition(language.effectiveLanguage == .simplifiedChinese)
precondition(AppLanguage.resolve(.system, preferredLanguages: ["en-US", "zh-Hans"]) == .english)
precondition(AppLanguage.resolve(.system, preferredLanguages: ["zh-CN"]) == .simplifiedChinese)
precondition(AppLanguage.resolve(.system, preferredLanguages: ["zh-Hant-TW", "en"]) == .english)
precondition(AppLanguage.resolve(.system, preferredLanguages: ["fr", "zh-Hans-CN"]) == .simplifiedChinese)
precondition(L10n.text("General", language: .simplifiedChinese, bundle: .main) == "通用")
precondition(L10n.text("General", language: .english, bundle: .main) == "General")
precondition(L10n.text("missing", language: .simplifiedChinese, bundle: .main, fallback: "Fallback") == "Fallback")
let folder = "100% \"Demo\""
precondition(L10n.format("Delete “%@”?", folder) == "要删除“\(folder)”吗？")
print("PASS: language resolution, persistence, confirmation gating, switching, resource loading and formatted user content")
