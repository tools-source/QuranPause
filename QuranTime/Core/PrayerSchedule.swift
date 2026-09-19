import Adhan
import Foundation
import UserNotifications

struct PrayerPlace: Codable, Equatable {
    let name: String
    let latitude: Double
    let longitude: Double
    let timeZoneID: String
    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }
    var coordinates: Coordinates { Coordinates(latitude: latitude, longitude: longitude) }
}

enum PrayerMethod: String, CaseIterable, Identifiable, Codable {
    case northAmerica, muslimWorldLeague, egyptian, karachi, ummAlQura, moonsightingCommittee
    var id: String { rawValue }
    var title: String {
        switch self {
        case .northAmerica: "North America (ISNA)"
        case .muslimWorldLeague: "Muslim World League"
        case .egyptian: "Egyptian General Authority"
        case .karachi: "University of Karachi"
        case .ummAlQura: "Umm al-Qura, Makkah"
        case .moonsightingCommittee: "Moonsighting Committee"
        }
    }
    var parameters: CalculationParameters {
        switch self {
        case .northAmerica: CalculationMethod.northAmerica.params
        case .muslimWorldLeague: CalculationMethod.muslimWorldLeague.params
        case .egyptian: CalculationMethod.egyptian.params
        case .karachi: CalculationMethod.karachi.params
        case .ummAlQura: CalculationMethod.ummAlQura.params
        case .moonsightingCommittee: CalculationMethod.moonsightingCommittee.params
        }
    }
}

struct PrayerMoment: Identifiable {
    let name: String
    let date: Date
    let isPrayer: Bool
    var id: String { "\(name)-\(Int(date.timeIntervalSince1970))" }
}

enum PrayerSchedule {
    static let notificationPrefix = "quranpause.prayer."
    static func day(_ date: Date, place: PrayerPlace, method: PrayerMethod, hanafi: Bool) -> [PrayerMoment] {
        guard (-90...90).contains(place.latitude), (-180...180).contains(place.longitude) else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = place.timeZone
        var parameters = method.parameters
        parameters.madhab = hanafi ? .hanafi : .shafi
        // Umm al-Qura uses 120 minutes for Isha in Ramadan instead of 90.
        var islamic = Calendar(identifier: .islamicUmmAlQura)
        islamic.timeZone = place.timeZone
        if method == .ummAlQura && islamic.component(.month, from: date) == 9 { parameters.ishaInterval = 120 }
        guard let times = PrayerTimes(coordinates: place.coordinates,
                                      date: calendar.dateComponents([.year, .month, .day], from: date),
                                      calculationParameters: parameters) else { return [] }
        return [PrayerMoment(name: "Fajr", date: times.fajr, isPrayer: true),
                PrayerMoment(name: "Sunrise", date: times.sunrise, isPrayer: false),
                PrayerMoment(name: "Dhuhr", date: times.dhuhr, isPrayer: true),
                PrayerMoment(name: "Asr", date: times.asr, isPrayer: true),
                PrayerMoment(name: "Maghrib", date: times.maghrib, isPrayer: true),
                PrayerMoment(name: "Isha", date: times.isha, isPrayer: true)]
    }
    static func upcoming(from date: Date, place: PrayerPlace, method: PrayerMethod, hanafi: Bool, days: Int = 7) -> [PrayerMoment] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = place.timeZone
        return (0..<days).compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: date)) }
            .flatMap { day($0, place: place, method: method, hanafi: hanafi) }
            .filter { $0.isPrayer && $0.date > date }.sorted { $0.date < $1.date }
    }
    static func qibla(place: PrayerPlace) -> Double { Qibla(coordinates: place.coordinates).direction }
    static func relativeBearing(qibla: Double, heading: Double) -> Double {
        (qibla - heading + 540).truncatingRemainder(dividingBy: 360) - 180
    }
    static func request(for moment: PrayerMoment, place: PrayerPlace) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = I18n.text(moment.name)
        content.body = I18n.text("It’s time for prayer. Tap to listen to the full azan.")
        content.sound = UNNotificationSound(named: .init("azan-alert.wav"))
        content.userInfo = ["prayer": moment.name]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: moment.date)
        components.timeZone = calendar.timeZone
        return UNNotificationRequest(identifier: notificationPrefix + moment.id, content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
    }
}
