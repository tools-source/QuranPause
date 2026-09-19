import DeviceActivity
import OSLog

final class ActivityMonitor: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        reconcile()
    }
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        reconcile()
    }
    override func intervalWillStartWarning(for activity: DeviceActivityName) {
        super.intervalWillStartWarning(for: activity)
        reconcile()
    }
    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
        reconcile()
    }
    private func reconcile() {
        do {
            try SharedStore.transaction { state in state.reconcileSchedule() }
        } catch {
            Logger(subsystem: "com.quranpause.app", category: "schedule").error("Unable to apply daily lock: \(error.localizedDescription, privacy: .public)")
        }
    }
    // An interval ending must never unlock apps: only completed foreground time does.
}
