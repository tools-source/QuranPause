import SwiftUI
import FamilyControls
import DeviceActivity
import UserNotifications

@MainActor @Observable final class AppModel {
    var state = AppState()
    var isRunning = false
    var isForeground = false
    var isReadingQuran = false
    /// A recitation is playing; while it is, listening earns the time instead of reading.
    var isListening = false
    let recitation = RecitationPlayer()
    let prayers = PrayerModel()
    var errorMessage: String?
    var completedSession: FocusSession?
    var authorization = AuthorizationCenter.shared.authorizationStatus
    var notificationStatus: UNAuthorizationStatus = .notDetermined
    private var clock = ForegroundClock()
    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
    init() {
        update { _ in }
        prayers.beforeAzan = { [weak self] in self?.recitation.stop() }
        recitation.beforePlayback = { [weak self] in self?.prayers.stopAzan() }
        recitation.onHeard = { [weak self] seconds in self?.creditListening(seconds) }
        recitation.onListeningChange = { [weak self] listening in self?.setListening(listening) }
        recitation.onError = { [weak self] message in self?.errorMessage = message }
    }
    var canShield: Bool { authorization == .approved && !Self.isSimulator }
    /// Time is earned by reading on screen or by listening to a recitation, never both at once.
    var isEarningTime: Bool { isEarningByReading || (isRunning && isListening) }
    private var isEarningByReading: Bool { isForeground && isRunning && isReadingQuran && !isListening }
    var remainingText: String {
        let value = Int(ceil(state.activeSession?.remaining ?? Double(state.durationMinutes * 60)))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
    var todaySessions: [FocusSession] { state.sessions.filter { $0.completedAt.map { Calendar.current.isDateInToday($0) } ?? false } }
    var todayMinutes: Int { Int(todaySessions.reduce(0) { $0 + $1.target } / 60) }
    var upcomingLockTimes: [LockTime] {
        let now = Calendar.current.component(.hour, from: .now) * 60 + Calendar.current.component(.minute, from: .now)
        let times = state.effectiveLockTimes.sorted { $0.minutes < $1.minutes }
        return times.filter { $0.minutes > now } + times.filter { $0.minutes <= now }
    }
    var nextLock: LockTime? {
        let now = Calendar.current.component(.hour, from: .now) * 60 + Calendar.current.component(.minute, from: .now)
        let times = state.effectiveLockTimes.sorted { $0.minutes < $1.minutes }
        return times.first { $0.minutes > now } ?? times.first
    }
    func update(_ mutation: (inout AppState) -> Void) {
        do { state = try SharedStore.transaction(mutation) }
        catch { errorMessage = error.localizedDescription }
    }
    func setForeground(_ active: Bool) {
        if !active && isRunning && isForeground { tick() }
        isForeground = active
        authorization = AuthorizationCenter.shared.authorizationStatus
        if active {
            update { $0.reconcileSchedule() }
            if isEarningByReading { clock.resume(at: ProcessInfo.processInfo.systemUptime) }
            Task { await refreshNotifications(); await prayers.refreshAlerts() }
        } else { clock.pause() }
    }
    func tick() {
        apply(credit: isEarningByReading ? clock.tick(at: ProcessInfo.processInfo.systemUptime) : 0)
    }
    /// Listening credit arrives from the player, including while the app is in the background.
    func creditListening(_ seconds: Double) {
        guard isRunning, isListening else { return }
        apply(credit: seconds)
    }
    func setListening(_ listening: Bool) {
        guard listening != isListening else { return }
        if isEarningByReading { tick() }
        isListening = listening
        if isEarningByReading { clock.resume(at: ProcessInfo.processInfo.systemUptime) } else { clock.pause() }
    }
    private func apply(credit: Double) {
        let prior = state.activeSession
        update { state in
            state.reconcileSchedule()
            if credit > 0 { state.credit(credit) }
        }
        if let prior, let finished = state.sessions.first(where: { $0.id == prior.id && $0.completedAt != nil }) {
            completedSession = finished
            isRunning = false
            clock.pause()
        }
    }
    func beginSession() {
        if state.activeSession == nil {
            guard Self.isSimulator || canShield else { errorMessage = I18n.text("Connect Screen Time first to protect your focus session."); return }
            guard Self.isSimulator || state.selectionCount > 0 else { errorMessage = I18n.text("Choose the apps you want to lock in Settings first."); return }
            update { $0.enqueue(id: UUID().uuidString, practice: Self.isSimulator) }
        }
        guard state.activeSession != nil else { return }
        isRunning = true
        if isEarningByReading { clock.resume(at: ProcessInfo.processInfo.systemUptime) }
    }
    func pauseSession() { tick(); isRunning = false; clock.pause() }
    func setReadingQuran(_ reading: Bool) {
        if !reading && isEarningByReading { tick() }
        isReadingQuran = reading
        if isEarningByReading { clock.resume(at: ProcessInfo.processInfo.systemUptime) }
        else { clock.pause() }
    }
    func authorize() async {
        guard !Self.isSimulator else { errorMessage = I18n.text("Screen Time app selection is available on a physical iPhone. You can try a practice focus session here."); return }
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            authorization = AuthorizationCenter.shared.authorizationStatus
        } catch { errorMessage = I18n.text("Screen Time permission wasn’t granted.") + " " + error.localizedDescription }
    }
    func saveRoutine(minutes: Int, slots: [LockTime], enabled: Bool, cadence: ScheduleCadence = .custom) -> Bool {
        guard (1...120).contains(minutes), (1...8).contains(slots.count), Set(slots.map(\.minutes)).count == slots.count else {
            errorMessage = I18n.text("Choose 1–8 different lock times and a session of 1–120 minutes."); return false
        }
        guard !enabled || (canShield && state.selectionCount > 0) else {
            errorMessage = I18n.text(Self.isSimulator ? "Automatic app locking needs a physical iPhone. Save your routine with automatic locking off to try it later." : "Allow Screen Time and choose apps in Settings before enabling daily locks."); return false
        }
        let old = state
        do {
            let candidate = try SharedStore.transaction { state in
                state.durationMinutes = minutes
                state.lockCadence = cadence
                state.lockTimes = slots.sorted { $0.minutes < $1.minutes }
                state.scheduleEnabled = enabled
                // Applying a routine starts with its next occurrence, never a retroactive lock.
                state.scheduleEnabledAt = .now
            }
            try registerSchedule(candidate)
            state = candidate
            return true
        } catch {
            // Restore the previous plan on registration failure; preserve concurrent session changes.
            update { state in
                state.durationMinutes = old.durationMinutes
                state.lockCadence = old.lockCadence
                state.lockTimes = old.lockTimes
                state.scheduleEnabled = old.scheduleEnabled
                state.scheduleEnabledAt = old.scheduleEnabledAt
            }
            do { try registerSchedule(state) }
            catch { errorMessage = I18n.text("The routine could not be restored. Open Routine and save it again.") + " " + error.localizedDescription; return false }
            errorMessage = I18n.text("Your routine wasn’t saved.") + " " + error.localizedDescription
            return false
        }
    }
    private func registerSchedule(_ state: AppState) throws {
        let center = DeviceActivityCenter()
        center.stopMonitoring()
        guard state.scheduleEnabled else { return }
        for window in SchedulePlanner.windows(cadence: state.lockCadence, slots: state.lockTimes) {
            try center.startMonitoring(.init("quranpause.\(window.id)"), during: window.schedule)
        }
    }
    func refreshPresetNotifications() async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        do {
            for reminder in state.reminders where reminder.enabled && reminder.presetKey != nil {
                for request in ReminderScheduler.requests(for: reminder) { try await center.add(request) }
            }
        } catch { errorMessage = I18n.text("Couldn’t update reminder language.") + " " + error.localizedDescription }
    }
    func requestNotifications() async {
        do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]); await refreshNotifications() }
        catch { errorMessage = I18n.text("Couldn’t request notifications.") + " " + error.localizedDescription }
    }

    func refreshNotifications() async { notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
    func saveReminder(_ reminder: ZikrReminder) async -> Bool {
        await NotificationScheduleLock.acquire()
        defer { NotificationScheduleLock.release() }
        let center = UNUserNotificationCenter.current()
        guard reminder.cadence != .twiceDaily || reminder.hour != reminder.secondHour || reminder.minute != reminder.secondMinute else {
            errorMessage = I18n.text("Choose two different reminder times."); return false
        }
        let previous = state.reminders.first { $0.id == reminder.id }
        let replacement = ReminderScheduler.requests(for: reminder)
        let otherCount = state.reminders.filter { $0.id != reminder.id }.reduce(0) { $0 + ReminderScheduler.requests(for: $1).count }
        let pending = await center.pendingNotificationRequests()
        let prayerCount = pending.filter { $0.identifier.hasPrefix(PrayerSchedule.notificationPrefix) }.count
        guard otherCount + replacement.count + prayerCount <= 60 else {
            errorMessage = I18n.text("Your notification schedule is full. Disable another reminder or prayer alerts before adding more times."); return false
        }
        do {
            if reminder.enabled {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                await refreshNotifications()
                guard granted else { errorMessage = I18n.text("Notifications are turned off. Allow notifications in iPhone Settings to receive your zikr."); return false }
            }
            for request in replacement { try await center.add(request) }
            let retained = Set(replacement.map(\.identifier))
            center.removePendingNotificationRequests(withIdentifiers: ReminderScheduler.identifiers(for: reminder.id).filter { !retained.contains($0) })
            state = try SharedStore.transaction { state in
                if let index = state.reminders.firstIndex(where: { $0.id == reminder.id }) { state.reminders[index] = reminder }
                else { state.reminders.append(reminder) }
            }
            return true
        } catch {
            center.removePendingNotificationRequests(withIdentifiers: ReminderScheduler.identifiers(for: reminder.id))
            if let previous {
                do { for request in ReminderScheduler.requests(for: previous) { try await center.add(request) } }
                catch { errorMessage = I18n.text("The previous notification schedule could not be restored. Save the reminder again."); return false }
            }
            errorMessage = I18n.text("Couldn’t save your reminder.") + " " + error.localizedDescription
            return false
        }
    }
    func deleteReminder(_ reminder: ZikrReminder) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ReminderScheduler.identifiers(for: reminder.id))
        update { $0.reminders.removeAll { $0.id == reminder.id } }
    }
}
