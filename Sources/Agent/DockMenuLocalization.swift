import Foundation

/// Resolve the Dock's language independently of this English-only app. A lookup on the Dock
/// bundle alone inherits the main bundle's localization and returns English even when the
/// Dock's actual Accessibility menu titles are Chinese (or another system language).
enum DockMenuLocalization {
    static let menuBundle: Bundle? = {
        guard let dock = Bundle(path: "/System/Library/CoreServices/Dock.app") else { return nil }
        // Respect a language override for the Dock, otherwise follow the user's language list.
        let preferences = UserDefaults.standard.persistentDomain(forName: "com.apple.dock")?["AppleLanguages"] as? [String]
            ?? Locale.preferredLanguages
        return localizedBundle(in: dock, preferences: preferences)
    }()

    static func localizedBundle(in bundle: Bundle, preferences: [String]) -> Bundle? {
        let localizations = Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: preferences)
        guard let localization = localizations.first,
              let path = bundle.path(forResource: localization, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    static func title(_ key: String, fallback: String) -> String {
        menuBundle?.localizedString(forKey: key, value: fallback, table: "DockMenus") ?? fallback
    }
}
