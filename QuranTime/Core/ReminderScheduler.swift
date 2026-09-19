import UserNotifications

/// Pure request construction makes every recurrence and identifier testable.
enum ReminderScheduler {
    static func identifiers(for id: String) -> [String] { ["zikr.\(id)", "zikr.\(id).0", "zikr.\(id).1"] }
    static func requests(for reminder: ZikrReminder) -> [UNNotificationRequest] {
        guard reminder.enabled else { return [] }
        let components: [DateComponents]
        switch reminder.cadence {
        case .daily, .custom: components = [DateComponents(hour: reminder.hour, minute: reminder.minute)]
        case .twiceDaily:
            components = [DateComponents(hour: reminder.hour, minute: reminder.minute), DateComponents(hour: reminder.secondHour, minute: reminder.secondMinute)]
        case .hourly: components = [DateComponents(minute: 0)]
        case .halfHourly: components = [DateComponents(minute: 0), DateComponents(minute: 30)]
        }
        return components.enumerated().map { index, date in
            let content = UNMutableNotificationContent()
            content.title = reminder.displayTitle; content.body = reminder.displayText; content.sound = .default
            return UNNotificationRequest(identifier: "zikr.\(reminder.id).\(index)", content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: true))
        }
    }
}
