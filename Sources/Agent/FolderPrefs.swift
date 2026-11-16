import AppKit

/// How folders look and behave, from Settings → General.
enum FolderPrefs {
    private static var defaults: UserDefaults { .standard }

    /// Under each app in a folder: its name (like Launchpad), or the Dock's running indicator.
    static var showsNames: Bool {
        get { defaults.bool(forKey: "showNames") }
        set { defaults.set(newValue, forKey: "showNames") }
    }

    /// Folders open when the pointer rests on them in the Dock, not only when clicked. Off by default.
    static var opensOnHover: Bool {
        get { defaults.bool(forKey: "openOnHover") }
        set { defaults.set(newValue, forKey: "openOnHover"); FolderHover.shared.update() }
    }

    static let hoverDelayRange: ClosedRange<Double> = 0...2
    static let defaultHoverDelay: TimeInterval = 0.3

    static func clampedHoverDelay(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite else { return defaultHoverDelay }
        return min(max(value, hoverDelayRange.lowerBound), hoverDelayRange.upperBound)
    }

    /// Seconds before a hovered folder opens. Zero removes the intentional wait.
    static var hoverDelay: TimeInterval {
        get {
            guard let value = defaults.object(forKey: "hoverDelay") as? NSNumber else { return defaultHoverDelay }
            return clampedHoverDelay(value.doubleValue)
        }
        set { defaults.set(clampedHoverDelay(newValue), forKey: "hoverDelay") }
    }

    /// Seconds after leaving a folder before closing it, whether opened by hover or click.
    static var closeDelay: TimeInterval {
        get {
            guard let value = defaults.object(forKey: "closeDelay") as? NSNumber else { return defaultHoverDelay }
            return clampedHoverDelay(value.doubleValue)
        }
        set { defaults.set(clampedHoverDelay(newValue), forKey: "closeDelay") }
    }

    /// How many apps fit on one page of a folder: 3, 6, 9 or 16.
    static let pageSizes = [3, 6, 9, 16]
    static var appsPerPage: Int {
        get { let value = defaults.integer(forKey: "appsPerPage"); return pageSizes.contains(value) ? value : 9 }
        set { defaults.set(newValue, forKey: "appsPerPage") }
    }

    /// Icon size inside folders, in points. Unset: the same size as the Dock's icons.
    static var customIconSize: CGFloat? {
        get { (defaults.object(forKey: "iconSize") as? NSNumber).map { CGFloat($0.doubleValue) } }
        set {
            if let newValue { defaults.set(Double(newValue), forKey: "iconSize") } else { defaults.removeObject(forKey: "iconSize") }
        }
    }

    static var dockIconSize: CGFloat { DockGeometry.tileSize ?? 52 }
    static var iconSize: CGFloat { customIconSize ?? dockIconSize }
    static let iconSizeRange: ClosedRange<CGFloat> = 32...128

    /// Whether icons grow under the pointer. Starts out matching the Dock's Magnification setting.
    static var magnifies: Bool {
        get { (defaults.object(forKey: "magnify") as? NSNumber)?.boolValue ?? DockGeometry.dockMagnifies }
        set { defaults.set(newValue, forKey: "magnify") }
    }

    /// How much bigger the icon under the pointer gets (0.2 = 20% bigger).
    static var magnification: CGFloat {
        get { (defaults.object(forKey: "magnification") as? NSNumber).map { CGFloat($0.doubleValue) } ?? DockGeometry.defaultFolderGrowth }
        set { defaults.set(Double(newValue), forKey: "magnification") }
    }

    static let magnificationRange: ClosedRange<CGFloat> = 0.05...0.5

    /// Largest icon scale under the pointer; 1 when magnification is off.
    static var magnificationScale: CGFloat { magnifies ? 1 + magnification : 1 }
}
