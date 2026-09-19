import Foundation

/// Prayer and zikr share iOS's pending-notification quota. Hold across await points
/// while replacing requests so two writers cannot both spend the same capacity.
@MainActor enum NotificationScheduleLock {
    private static var held = false
    private static var waiters: [CheckedContinuation<Void, Never>] = []
    static func acquire() async {
        if !held { held = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    static func release() {
        if waiters.isEmpty { held = false }
        else { waiters.removeFirst().resume() }
    }
}
