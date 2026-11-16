import AppKit

// Isolate the actual FolderPrefs implementation from the app's event monitors and Dock.
final class FolderHover { static let shared = FolderHover(); func update() {} }
enum DockGeometry {
    static let tileSize: CGFloat? = nil
    static let dockMagnifies = false
    static let defaultFolderGrowth: CGFloat = 0.1
}

let defaults = UserDefaults.standard
let previousArguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
defer { defaults.setVolatileDomain(previousArguments, forName: UserDefaults.argumentDomain) }

func checkStored(_ value: Any, expected: Double) {
    // An in-memory domain avoids changing the user's preferences during tests.
    for key in ["hoverDelay", "closeDelay"] {
        defaults.setVolatileDomain([key: value], forName: UserDefaults.argumentDomain)
        let actual = key == "hoverDelay" ? FolderPrefs.hoverDelay : FolderPrefs.closeDelay
        precondition(abs(actual - expected) < 0.000001, "\(key) stored \(value): expected \(expected), got \(actual)")
    }
}

checkStored("invalid", expected: 0.3)
checkStored(0.3, expected: 0.3)
checkStored(0.0, expected: 0) // Zero must not be mistaken for an unset preference.
checkStored(0.17, expected: 0.17) // Typed values need not match the slider's 0.05 step.
checkStored(-1.0, expected: 0)
checkStored(20.0, expected: 2)
checkStored(Double.nan, expected: 0.3)
checkStored(Double.infinity, expected: 0.3)
var timer = FolderLeaveTimer()
let start = Date(timeIntervalSinceReferenceDate: 0)
precondition(!timer.shouldClose(protected: false, delay: 0.3, now: start))
precondition(!timer.shouldClose(protected: false, delay: 0.3, now: start.addingTimeInterval(0.2)))
precondition(!timer.shouldClose(protected: true, delay: 0.3, now: start.addingTimeInterval(0.25)))
precondition(!timer.shouldClose(protected: false, delay: 0.3, now: start.addingTimeInterval(0.4)))
precondition(!timer.shouldClose(protected: false, delay: 0.3, now: start.addingTimeInterval(0.6)))
precondition(timer.shouldClose(protected: false, delay: 0.3, now: start.addingTimeInterval(0.8)))
precondition(!timer.shouldClose(protected: true, delay: 0, now: start.addingTimeInterval(1)))
precondition(timer.shouldClose(protected: false, delay: 0, now: start.addingTimeInterval(1)))

// Regression: a fast pass triggers hover opening, then leaves before the very first frame.
// No pointerInside sample will ever arrive; the folder must still time out and close.
var fastPass = FolderLeaveTimer(pointerInitiated: true)
precondition(!fastPass.shouldClose(protected: false, delay: 0.3, now: start))
precondition(fastPass.shouldClose(protected: false, delay: 0.3, now: start.addingTimeInterval(0.31)))
var immediatePass = FolderLeaveTimer(pointerInitiated: true)
precondition(immediatePass.shouldClose(protected: false, delay: 0, now: start))

// An opening requested without the mouse should stay until the pointer visits it.
var keyboard = FolderLeaveTimer(pointerInitiated: false)
precondition(!keyboard.shouldClose(protected: false, delay: 0.3, now: start))
precondition(!keyboard.shouldClose(protected: false, delay: 0.3, now: start.addingTimeInterval(10)))
precondition(!keyboard.shouldClose(pointerInside: true, protected: false, delay: 0.3, now: start.addingTimeInterval(11)))
precondition(!keyboard.shouldClose(protected: false, delay: 0.3, now: start.addingTimeInterval(12)))
precondition(keyboard.shouldClose(protected: false, delay: 0.3, now: start.addingTimeInterval(12.31)))

// Returning to the folder resets the timeout even after a missed initial pointer sample.
var returnVisit = FolderLeaveTimer(pointerInitiated: true)
precondition(!returnVisit.shouldClose(protected: false, delay: 0.3, now: start))
precondition(!returnVisit.shouldClose(pointerInside: true, protected: false, delay: 0.3, now: start.addingTimeInterval(0.2)))
precondition(!returnVisit.shouldClose(protected: false, delay: 0.3, now: start.addingTimeInterval(0.4)))
precondition(!returnVisit.shouldClose(protected: false, delay: 0.3, now: start.addingTimeInterval(0.6)))
precondition(returnVisit.shouldClose(protected: false, delay: 0.3, now: start.addingTimeInterval(0.71)))
print("PASS: delay preferences, leave timeout, fast hover/click pass, zero delay, keyboard opening and re-entry cancellation")
