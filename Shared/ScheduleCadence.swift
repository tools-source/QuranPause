import Foundation
import DeviceActivity

enum ScheduleCadence: String, Codable, CaseIterable, Identifiable {
    case daily, twiceDaily, hourly, halfHourly, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .daily: return "Every day"
        case .twiceDaily: return "Twice a day"
        case .hourly: return "Every hour"
        case .halfHourly: return "Every 30 minutes"
        case .custom: return "Custom daily times"
        }
    }
    var isFrequent: Bool { self == .hourly || self == .halfHourly }
    func slots(custom: [LockTime]) -> [LockTime] {
        switch self {
        case .daily: return Array(custom.prefix(1))
        case .twiceDaily: return Array(custom.prefix(2))
        case .custom: return custom
        case .hourly, .halfHourly:
            return stride(from: 0, to: 1440, by: self == .hourly ? 60 : 30).map {
                LockTime(id: "\(rawValue)-\($0)", hour: $0 / 60, minute: $0 % 60)
            }
        }
    }
}

struct MonitorWindow {
    let id: String
    let startMinute: Int
    let endMinute: Int
    var warningMinutes: Int?
    var schedule: DeviceActivitySchedule {
        DeviceActivitySchedule(intervalStart: DateComponents(hour: startMinute / 60, minute: startMinute % 60),
                               intervalEnd: DateComponents(hour: endMinute / 60, minute: endMinute % 60), repeats: true,
                               warningTime: warningMinutes.map { DateComponents(minute: $0) })
    }
    /// Every callback triggers the same idempotent reconciliation, never a direct unlock.
    var callbackMinutes: Set<Int> {
        var values: Set<Int> = [startMinute, endMinute]
        if let warningMinutes {
            values.insert((startMinute - warningMinutes + 1440) % 1440)
            values.insert((endMinute - warningMinutes + 1440) % 1440)
        }
        return values
    }
}

enum SchedulePlanner {
    static func windows(cadence: ScheduleCadence, slots: [LockTime]) -> [MonitorWindow] {
        if cadence.isFrequent {
            // Twelve one-hour intervals generate 24 hourly callbacks. The half-hour
            // warning before each start/end adds the remaining 24 half-hour boundaries.
            // This stays below Apple's limit of 20 monitored activities.
            return stride(from: 0, to: 24, by: 2).map {
                MonitorWindow(id: "rhythm.\($0)", startMinute: $0 * 60, endMinute: ($0 + 1) * 60,
                              warningMinutes: cadence == .halfHourly ? 30 : nil)
            }
        }
        return cadence.slots(custom: slots).map {
            MonitorWindow(id: $0.id, startMinute: $0.minutes, endMinute: ($0.minutes + 1439) % 1440)
        }
    }
}
