import Foundation

/// Names a new folder after its apps' App Store categories, like iOS does: two games make
/// "Games"; a drawing app and a video app make "Creativity".
enum FolderNaming {
    static func name(for apps: [URL]) -> String {
        let categories = apps.compactMap(category(of:))
        guard let first = categories.first else { return FolderActions.folderName }
        if categories.allSatisfy({ $0 == first }) { return title(of: first) }
        // Different categories that belong together get their group's name (as in the App Library).
        if let group = groups[first], categories.allSatisfy({ groups[$0] == group }) {
            return L10n.text("categoryGroup." + group, fallback: group)
        }
        // Otherwise, the category of the app it was dropped onto.
        return title(of: first)
    }

    /// The app's declared category ("games" for any kind of game), from its Info.plist.
    static func category(of app: URL) -> String? {
        let prefix = "public.app-category."
        guard let raw = Bundle(url: app)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String,
              raw.hasPrefix(prefix) else { return nil }
        let name = String(raw.dropFirst(prefix.count)).lowercased()
        return name.hasSuffix("-games") ? "games" : name
    }

    static func title(of category: String) -> String {
        let fallback = titles[category] ?? category.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
        return L10n.text("category." + category, fallback: fallback)
    }

    private static let titles: [String: String] = [
        "business": "Business", "developer-tools": "Developer Tools", "education": "Education",
        "entertainment": "Entertainment", "finance": "Finance", "games": "Games",
        "graphics-design": "Graphics & Design", "healthcare-fitness": "Health & Fitness",
        "lifestyle": "Lifestyle", "medical": "Medical", "music": "Music", "news": "News",
        "photography": "Photography", "productivity": "Productivity", "reference": "Reference",
        "social-networking": "Social", "sports": "Sports", "travel": "Travel",
        "utilities": "Utilities", "video": "Video", "weather": "Weather", "books": "Books",
    ]

    private static let groups: [String: String] = [
        "productivity": "Productivity & Finance", "business": "Productivity & Finance", "finance": "Productivity & Finance",
        "graphics-design": "Creativity", "photography": "Creativity", "video": "Creativity",
        "entertainment": "Entertainment", "music": "Entertainment",
        "news": "Information & Reading", "reference": "Information & Reading", "books": "Information & Reading",
        "weather": "Information & Reading", "education": "Information & Reading",
        "healthcare-fitness": "Health & Fitness", "medical": "Health & Fitness", "sports": "Health & Fitness",
        "utilities": "Utilities", "developer-tools": "Utilities",
        "travel": "Travel", "lifestyle": "Travel",
    ]
}
