import Foundation

/// Time spent outside the folder, its Dock tile and the path between them. Re-entering any
/// protected area cancels the pending close; zero delay closes on the first outside sample.
struct FolderLeaveTimer {
    private var awaySince: Date?
    private var pointerEngaged: Bool

    /// Pointer-triggered openings already count as a visit, even if the pointer leaves before
    /// the first display-link sample. Keyboard openings wait until the pointer actually enters.
    init(pointerInitiated: Bool = true) {
        pointerEngaged = pointerInitiated
    }

    mutating func shouldClose(pointerInside: Bool = false, protected: Bool, delay: TimeInterval, now: Date = Date()) -> Bool {
        if pointerInside { pointerEngaged = true }
        if protected || pointerInside || !pointerEngaged {
            awaySince = nil
            return false
        }
        let start = awaySince ?? now
        awaySince = start
        return now.timeIntervalSince(start) >= delay
    }
}
