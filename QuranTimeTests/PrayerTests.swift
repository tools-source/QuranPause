import XCTest
import UserNotifications
import AVFoundation
@testable import QuranTime

final class PrayerTests: XCTestCase {
    let raleigh = PrayerPlace(name: "Raleigh", latitude: 35.7750, longitude: -78.6336, timeZoneID: "America/New_York")
    func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    func testPrayerTimesMatchPublishedAdhanReference() {
        // Reference: Adhan Swift 1.4.0 Tests/AdhanTests.swift, testPrayerTimes.
        let moments = PrayerSchedule.day(date("2015-07-12T16:00:00Z"), place: raleigh, method: .northAmerica, hanafi: true)
        let formatter = DateFormatter(); formatter.timeZone = raleigh.timeZone; formatter.dateFormat = "HH:mm"
        XCTAssertEqual(moments.map { formatter.string(from: $0.date) }, ["04:42", "06:08", "13:21", "18:22", "20:32", "21:57"])
        XCTAssertEqual(moments.filter(\.isPrayer).count, 5)
    }
    func testSelectedLocationControlsCalendarDayNotDeviceZone() {
        let instant = date("2026-09-19T01:00:00Z") // Still September 18 in Raleigh.
        let moments = PrayerSchedule.day(instant, place: raleigh, method: .northAmerica, hanafi: false)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = raleigh.timeZone
        XCTAssertEqual(calendar.component(.day, from: moments[0].date), 18)
        let tomorrow = PrayerSchedule.upcoming(from: instant, place: raleigh, method: .northAmerica, hanafi: false)
        XCTAssertEqual(tomorrow.first?.name, "Fajr")
        XCTAssertEqual(calendar.component(.day, from: tomorrow[0].date), 19)
    }
    func testUpcomingAlertsAcrossDSTUseEachLocalDateAndExcludeSunrise() {
        let start = date("2026-03-07T05:00:00Z")
        let upcoming = PrayerSchedule.upcoming(from: start, place: raleigh, method: .northAmerica, hanafi: false)
        XCTAssertEqual(upcoming.count, 35)
        XCTAssertTrue(upcoming.allSatisfy { $0.date > start && $0.isPrayer && $0.name != "Sunrise" })
        XCTAssertEqual(Set(upcoming.map(\.id)).count, 35)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = raleigh.timeZone
        XCTAssertEqual(Set(upcoming.map { calendar.startOfDay(for: $0.date) }).count, 7)
        XCTAssertLessThan(upcoming[5].date.timeIntervalSince(upcoming[0].date), 24 * 3600)
    }
    func testHanafiOnlyMovesAsrLater() {
        let now = date("2026-09-18T12:00:00Z")
        let standard = PrayerSchedule.day(now, place: raleigh, method: .northAmerica, hanafi: false)
        let hanafi = PrayerSchedule.day(now, place: raleigh, method: .northAmerica, hanafi: true)
        XCTAssertGreaterThan(hanafi[3].date, standard[3].date)
        XCTAssertEqual(hanafi[0].date, standard[0].date)
        XCTAssertEqual(hanafi[4].date, standard[4].date)
    }
    func testQiblaAndCompassWrapCorrectly() {
        let ny = PrayerPlace(name: "New York", latitude: 40.7128, longitude: -74.0059, timeZoneID: "America/New_York")
        XCTAssertEqual(PrayerSchedule.qibla(place: ny), 58.481, accuracy: 0.001)
        XCTAssertEqual(PrayerSchedule.relativeBearing(qibla: 1, heading: 359), 2)
        XCTAssertEqual(PrayerSchedule.relativeBearing(qibla: 359, heading: 1), -2)
        XCTAssertEqual(PrayerSchedule.relativeBearing(qibla: 58, heading: 58), 0)
    }
    func testNotificationUsesAbsoluteTimeAndCustomSound() throws {
        let expected = date("2030-09-19T09:30:00Z")
        let moment = PrayerMoment(name: "Fajr", date: expected, isPrayer: true)
        let request = PrayerSchedule.request(for: moment, place: raleigh)
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertFalse(trigger.repeats)
        XCTAssertEqual(trigger.dateComponents.timeZone?.secondsFromGMT(), 0)
        XCTAssertEqual(trigger.nextTriggerDate(), expected)
        XCTAssertNotNil(request.content.sound)
        XCTAssertEqual(request.content.userInfo["prayer"] as? String, "Fajr")
        let sound = try AVAudioPlayer(contentsOf: XCTUnwrap(Bundle.main.url(forResource: "azan-alert", withExtension: "wav")))
        XCTAssertGreaterThan(sound.duration, 1)
        XCTAssertLessThan(sound.duration, 30)
        let full = try AVAudioPlayer(contentsOf: XCTUnwrap(Bundle.main.url(forResource: "azan", withExtension: "mp3")))
        XCTAssertGreaterThan(full.duration, 180)
    }
    func testNotificationTapsRouteOnlyDefaultActions() {
        XCTAssertEqual(PrayerModel.destination(for: "\(PrayerSchedule.notificationPrefix)Fajr", actionIdentifier: UNNotificationDefaultActionIdentifier), .prayer)
        XCTAssertEqual(PrayerModel.destination(for: "\(ReminderScheduler.notificationPrefix)morning.0", actionIdentifier: UNNotificationDefaultActionIdentifier), .zikr)
        XCTAssertNil(PrayerModel.destination(for: "unrelated", actionIdentifier: UNNotificationDefaultActionIdentifier))
        XCTAssertNil(PrayerModel.destination(for: "\(PrayerSchedule.notificationPrefix)Fajr", actionIdentifier: UNNotificationDismissActionIdentifier))
    }
    func testDeletionProtectionPersistsUntilAllRealSessionsFinish() throws {
        var state = AppState(); state.durationMinutes = 1
        XCTAssertFalse(state.requiresLockdown)
        state.enqueue(id: "first"); state.enqueue(id: "second")
        XCTAssertTrue(state.requiresLockdown)
        state.credit(60)
        state = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        XCTAssertTrue(state.requiresLockdown)
        state.scheduleEnabled = false
        XCTAssertTrue(state.requiresLockdown)
        state.credit(60)
        XCTAssertFalse(state.requiresLockdown)
        state.enqueue(id: "practice", practice: true)
        XCTAssertFalse(state.requiresLockdown)
    }
    func testAyahAudioUsesSelectedReciterAndExactVerse() throws {
        XCTAssertEqual(AyahAudio.url(surah: 2, ayah: 255, reciterID: 7)?.absoluteString, "https://everyayah.com/data/Alafasy_128kbps/002255.mp3")
        for reciter in Recitations.catalog {
            XCTAssertNotNil(AyahAudio.url(surah: 114, ayah: 6, reciterID: reciter.id))
        }
        XCTAssertNil(AyahAudio.url(surah: 0, ayah: 1, reciterID: 7))
        XCTAssertNil(AyahAudio.url(surah: 1, ayah: 1, reciterID: 999))
    }
    func testSelectablePageIncludesContinuedAyahAsUnicode() throws {
        let library = QuranLibrary()
        let page = try XCTUnwrap(library.pages.first { $0.id == 592 })
        XCTAssertEqual(page.verses.first?.key, "87:11")
        XCTAssertEqual(page.selectableVerses.first?.key, Mushaf.manifest?.pages[591].firstAyah)
        for page in library.pages {
            XCTAssertEqual(Set(page.selectableVerses.map(\.key)).count, page.selectableVerses.count)
            for ref in page.selectableVerses {
                XCTAssertNotNil(library.surahs.first { $0.id == ref.surah }?.verses.first { $0.id == ref.ayah })
            }
        }
    }
    func testDistributionMetadataAndTranslations() throws {
        // iOS strips device-suffixed keys from the runtime infoDictionary on iPhone,
        // so read the shipped Info.plist itself.
        let plistURL = try XCTUnwrap(Bundle.main.url(forResource: "Info", withExtension: "plist"))
        let plist = try XCTUnwrap(try PropertyListSerialization.propertyList(from: Data(contentsOf: plistURL), format: nil) as? [String: Any])
        let orientations = try XCTUnwrap(plist["UISupportedInterfaceOrientations~ipad"] as? [String])
        XCTAssertEqual(Set(orientations), Set(["UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"]))
        for name in ["ActivityMonitor", "ShieldConfiguration"] {
            let bundle = try XCTUnwrap(Bundle(url: Bundle.main.builtInPlugInsURL!.appendingPathComponent("\(name).appex")))
            XCTAssertFalse((bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "").isEmpty)
        }
        let arabic = try XCTUnwrap(Bundle(path: try XCTUnwrap(Bundle.main.path(forResource: "ar", ofType: "lproj"))))
        XCTAssertEqual(arabic.localizedString(forKey: "Prayer", value: nil, table: nil), "الصلاة")
        XCTAssertEqual(arabic.localizedString(forKey: "Clear selection", value: nil, table: nil), "إلغاء التحديد")
    }
}
