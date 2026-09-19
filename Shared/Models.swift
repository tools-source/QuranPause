import Foundation
import FamilyControls

struct LockTime: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var hour: Int
    var minute: Int
    var minutes: Int { hour * 60 + minute }
    var date: Date { Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now }
}

struct FocusSession: Codable, Identifiable {
    var id: String
    var target: Double
    var remaining: Double
    var createdAt = Date()
    var completedAt: Date?
    var isPractice = false
}

struct ZikrReminder: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var title: String
    var text: String
    var hour = 8
    var minute = 0
    var enabled = false
    var cadence: ScheduleCadence = .daily
    var secondHour = 20
    var secondMinute = 0
    var presetKey: String?
    var date: Date { Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now }
    var secondDate: Date { Calendar.current.date(from: DateComponents(hour: secondHour, minute: secondMinute)) ?? .now }
    enum CodingKeys: String, CodingKey { case id, title, text, hour, minute, enabled, cadence, secondHour, secondMinute, presetKey }
    init(id: String = UUID().uuidString, title: String, text: String, hour: Int = 8, minute: Int = 0, enabled: Bool = false, cadence: ScheduleCadence = .daily, secondHour: Int = 20, secondMinute: Int = 0, presetKey: String? = nil) {
        self.id = id; self.title = title; self.text = text; self.hour = hour; self.minute = minute
        self.enabled = enabled; self.cadence = cadence; self.secondHour = secondHour; self.secondMinute = secondMinute; self.presetKey = presetKey
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        text = try c.decode(String.self, forKey: .text)
        hour = try c.decodeIfPresent(Int.self, forKey: .hour) ?? 8
        minute = try c.decodeIfPresent(Int.self, forKey: .minute) ?? 0
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        cadence = try c.decodeIfPresent(ScheduleCadence.self, forKey: .cadence) ?? .daily
        secondHour = try c.decodeIfPresent(Int.self, forKey: .secondHour) ?? 20
        secondMinute = try c.decodeIfPresent(Int.self, forKey: .secondMinute) ?? 0
        presetKey = try c.decodeIfPresent(String.self, forKey: .presetKey)
        if !c.contains(.presetKey) {
            presetKey = Self.defaults.first { $0.title == title && $0.text == text }?.presetKey
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(title, forKey: .title); try c.encode(text, forKey: .text)
        try c.encode(hour, forKey: .hour); try c.encode(minute, forKey: .minute); try c.encode(enabled, forKey: .enabled)
        try c.encode(cadence, forKey: .cadence); try c.encode(secondHour, forKey: .secondHour); try c.encode(secondMinute, forKey: .secondMinute)
        // Explicit null distinguishes a user's copy from a legacy built-in template.
        if let presetKey { try c.encode(presetKey, forKey: .presetKey) } else { try c.encodeNil(forKey: .presetKey) }
    }
    static let defaults = [
        ZikrReminder(title: "A moment of gratitude", text: "الْحَمْدُ لِلَّهِ\nAlhamdulillah — All praise is for Allah.", presetKey: "gratitude"),
        ZikrReminder(title: "Remember Allah", text: "سُبْحَانَ اللَّهِ وَبِحَمْدِهِ\nSubhanAllahi wa bihamdihi — Glory and praise be to Allah.", hour: 17, presetKey: "remembrance"),
        ZikrReminder(title: "Seek forgiveness", text: "أَسْتَغْفِرُ اللَّهَ\nAstaghfirullah — I seek forgiveness from Allah.", hour: 21, presetKey: "forgiveness")
    ]
}

struct AppState: Codable {
    var durationMinutes = 10
    var scheduleEnabled = false
    var scheduleEnabledAt = Date()
    var lockTimes = [LockTime(hour: 7, minute: 0), LockTime(hour: 13, minute: 0), LockTime(hour: 20, minute: 0)]
    var selection = FamilyActivitySelection()
    var sessions: [FocusSession] = []
    var seenOccurrences: [String] = []
    var reminders = ZikrReminder.defaults
    var lastSurah = 1
    var lastVerse = 1
    var bookmarks: [String] = []
    var favoriteSurahs: [Int] = []
    var lastPage = 1
    var lockCadence: ScheduleCadence = .custom
    var effectiveLockTimes: [LockTime] { lockCadence.slots(custom: lockTimes) }

    init() {}
    enum CodingKeys: String, CodingKey {
        case durationMinutes, scheduleEnabled, scheduleEnabledAt, lockTimes, selection, sessions, seenOccurrences, reminders, lastSurah, lastVerse, bookmarks, favoriteSurahs, lastPage, lockCadence
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        durationMinutes = try c.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? 10
        scheduleEnabled = try c.decodeIfPresent(Bool.self, forKey: .scheduleEnabled) ?? false
        scheduleEnabledAt = try c.decodeIfPresent(Date.self, forKey: .scheduleEnabledAt) ?? .now
        lockTimes = try c.decodeIfPresent([LockTime].self, forKey: .lockTimes) ?? lockTimes
        selection = try c.decodeIfPresent(FamilyActivitySelection.self, forKey: .selection) ?? selection
        sessions = try c.decodeIfPresent([FocusSession].self, forKey: .sessions) ?? []
        seenOccurrences = try c.decodeIfPresent([String].self, forKey: .seenOccurrences) ?? []
        reminders = try c.decodeIfPresent([ZikrReminder].self, forKey: .reminders) ?? ZikrReminder.defaults
        lastSurah = try c.decodeIfPresent(Int.self, forKey: .lastSurah) ?? 1
        lastVerse = try c.decodeIfPresent(Int.self, forKey: .lastVerse) ?? 1
        bookmarks = try c.decodeIfPresent([String].self, forKey: .bookmarks) ?? []
        favoriteSurahs = try c.decodeIfPresent([Int].self, forKey: .favoriteSurahs) ?? []
        lastPage = try c.decodeIfPresent(Int.self, forKey: .lastPage) ?? 1
        lockCadence = try c.decodeIfPresent(ScheduleCadence.self, forKey: .lockCadence) ?? .custom
    }
    mutating func toggleFavorite(_ surahID: Int) {
        guard (1...114).contains(surahID) else { return }
        if favoriteSurahs.contains(surahID) { favoriteSurahs.removeAll { $0 == surahID } }
        else { favoriteSurahs.append(surahID) }
    }
    var activeSession: FocusSession? { sessions.first { $0.completedAt == nil } }
    var selectionCount: Int { selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count }

    mutating func enqueue(id: String, practice: Bool = false, now: Date = .now) {
        guard !seenOccurrences.contains(id) else { return }
        seenOccurrences.append(id)
        sessions.append(FocusSession(id: id, target: Double(durationMinutes * 60), remaining: Double(durationMinutes * 60), createdAt: now, isPractice: practice))
        // Keep history bounded, retaining all unfinished commitments.
        if seenOccurrences.count > 2000 { seenOccurrences.removeFirst(seenOccurrences.count - 2000) }
        if sessions.count > 1000 { sessions.removeAll { $0.completedAt.map { now.timeIntervalSince($0) > 365 * 86400 } ?? false } }
    }

    mutating func reconcileSchedule(now: Date = .now, calendar: Calendar = .current) {
        guard scheduleEnabled else { return }
        let day = calendar.startOfDay(for: now)
        for slot in effectiveLockTimes.sorted(by: { $0.minutes < $1.minutes }) {
            guard let date = calendar.date(bySettingHour: slot.hour, minute: slot.minute, second: 0, of: day),
                  date >= scheduleEnabledAt, date <= now else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            enqueue(id: "\(parts.year!)-\(parts.month!)-\(parts.day!)-\(slot.id)", now: date)
        }
    }

    mutating func credit(_ seconds: Double, now: Date = .now) {
        guard seconds.isFinite, seconds > 0, let index = sessions.firstIndex(where: { $0.completedAt == nil }) else { return }
        sessions[index].remaining = max(0, sessions[index].remaining - seconds)
        if sessions[index].remaining == 0 { sessions[index].completedAt = now }
    }
}

/// Credits a recitation only as it is heard: the media time that actually advanced while
/// audible, never more than the monotonic time that passed, and nothing across stalls,
/// silence, or backward jumps.
struct ListeningClock {
    private var last: (uptime: Double, media: Double)?
    mutating func pause() { last = nil }
    mutating func tick(uptime: Double, media: Double, audible: Bool) -> Double {
        defer { last = audible ? (uptime, media) : nil }
        guard audible, let last else { return 0 }
        let wall = uptime - last.uptime, heard = media - last.media
        guard wall >= 0, wall <= 2.5, heard >= 0 else { return 0 }
        return min(wall, heard)
    }
}

/// Uses monotonic uptime, excludes inactive time, and never awards a long stalled tick.
struct ForegroundClock {
    private var lastUptime: Double?
    mutating func resume(at uptime: Double) { lastUptime = uptime }
    mutating func pause() { lastUptime = nil }
    mutating func tick(at uptime: Double) -> Double {
        guard let previous = lastUptime else { return 0 }
        lastUptime = uptime
        let elapsed = uptime - previous
        return elapsed >= 0 && elapsed <= 2.5 ? elapsed : 0
    }
}

extension AppState {
    var requiresLockdown: Bool { sessions.contains { $0.completedAt == nil && !$0.isPractice } }
}
