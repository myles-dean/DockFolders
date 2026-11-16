import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english = "en", simplifiedChinese = "zh-Hans"
    var id: String { rawValue }

    static func resolve(_ selection: AppLanguage, preferredLanguages: [String]) -> AppLanguage {
        guard selection == .system else { return selection }
        // This release translates simplified Chinese. Traditional Chinese keeps the English
        // fallback rather than silently presenting simplified Chinese as a traditional locale.
        for identifier in preferredLanguages {
            if identifier.hasPrefix("zh-Hans") || identifier == "zh" || identifier.hasPrefix("zh-CN") || identifier.hasPrefix("zh-SG") {
                return .simplifiedChinese
            }
            if identifier.hasPrefix("en") || identifier.hasPrefix("zh-Hant") || identifier.hasPrefix("zh-TW") || identifier.hasPrefix("zh-HK") {
                return .english
            }
        }
        return .english
    }
}

final class Localization: ObservableObject {
    static let shared = Localization()
    static let didChange = Notification.Name("DockFoldersLanguageDidChange")
    static let didConfirm = Notification.Name("DockFoldersLanguageDidConfirm")
    private let defaults: UserDefaults
    @Published private(set) var selection: AppLanguage
    private var localeObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selection = AppLanguage(rawValue: defaults.string(forKey: "interfaceLanguage") ?? "system") ?? .system
        localeObserver = NotificationCenter.default.addObserver(forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.selection == .system else { return }
            self.objectWillChange.send()
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    deinit { if let localeObserver { NotificationCenter.default.removeObserver(localeObserver) } }

    var hasChosen: Bool { defaults.bool(forKey: "interfaceLanguageConfirmed") }
    var effectiveLanguage: AppLanguage {
        let languages = defaults.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]
            ?? Locale.preferredLanguages
        return AppLanguage.resolve(selection, preferredLanguages: languages)
    }
    var locale: Locale { Locale(identifier: effectiveLanguage.rawValue) }

    func select(_ language: AppLanguage) {
        guard selection != language else { return }
        selection = language
        defaults.set(language.rawValue, forKey: "interfaceLanguage")
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    func confirm() {
        defaults.set(true, forKey: "interfaceLanguageConfirmed")
        NotificationCenter.default.post(name: Self.didConfirm, object: nil)
    }
}

enum L10n {
    static func text(_ key: String, fallback: String? = nil) -> String {
        text(key, language: Localization.shared.effectiveLanguage, bundle: .main, fallback: fallback)
    }

    static func text(_ key: String, language: AppLanguage, bundle: Bundle, fallback: String? = nil) -> String {
        guard let path = bundle.path(forResource: language.rawValue, ofType: "lproj"),
              let localized = Bundle(path: path) else { return fallback ?? key }
        return localized.localizedString(forKey: key, value: fallback ?? key, table: "Localizable")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Localization.shared.locale, arguments: arguments)
    }
}

/// Rebuild view-local labels on language changes while preserving the controllers' models and
/// persisted folder data. Locale also controls number formatting and SwiftUI's standard controls.
struct LocalizedRoot<Content: View>: View {
    @ObservedObject private var localization = Localization.shared
    private let content: () -> Content
    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }
    var body: some View {
        content()
            .environment(\.locale, localization.locale)
            .id(localization.effectiveLanguage)
    }
}

struct LanguagePicker: View {
    @ObservedObject private var localization = Localization.shared
    var body: some View {
        Picker(L10n.text("Language"), selection: Binding(get: { localization.selection }, set: { localization.select($0) })) {
            Text(L10n.text("System Default")).tag(AppLanguage.system)
            Text("English").tag(AppLanguage.english)
            Text("简体中文").tag(AppLanguage.simplifiedChinese)
        }
        .accessibilityLabel(L10n.text("Language"))
    }
}
