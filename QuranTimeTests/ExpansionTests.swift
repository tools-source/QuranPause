import XCTest
import UserNotifications
@testable import QuranTime

final class ExpansionTests: XCTestCase {
    func testHourlyPlanCoversEveryHourWithinAppleLimit() {
        let windows = SchedulePlanner.windows(cadence: .hourly, slots: [])
        XCTAssertLessThanOrEqual(windows.count, 20)
        XCTAssertEqual(windows.flatMap(\.callbackMinutes).sorted(), Array(stride(from: 0, to: 1440, by: 60)))
    }
    func testHalfHourlyPlanCoversEveryHalfHourWithinAppleLimit() {
        let windows = SchedulePlanner.windows(cadence: .halfHourly, slots: [])
        XCTAssertEqual(windows.count, 12)
        XCTAssertEqual(windows.flatMap(\.callbackMinutes).sorted(), Array(stride(from: 0, to: 1440, by: 30)))
        XCTAssertTrue(windows.allSatisfy { ($0.endMinute - $0.startMinute + 1440) % 1440 >= 15 })
    }
    func testRepeatedHalfHourCallbacksDoNotDuplicateCommitments() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 12))!
        var state = AppState()
        state.lockCadence = .halfHourly
        state.scheduleEnabled = true
        state.scheduleEnabledAt = day
        state.reconcileSchedule(now: day.addingTimeInterval(86399), calendar: calendar)
        state.reconcileSchedule(now: day.addingTimeInterval(86399), calendar: calendar)
        XCTAssertEqual(state.sessions.count, 48)
        XCTAssertEqual(Set(state.sessions.map(\.id)).count, 48)
    }
    func testDailyAndTwiceDailyUseChosenTimes() {
        let slots = [LockTime(hour: 8, minute: 15), LockTime(hour: 20, minute: 45)]
        XCTAssertEqual(ScheduleCadence.daily.slots(custom: slots).map(\.minutes), [495])
        XCTAssertEqual(ScheduleCadence.twiceDaily.slots(custom: slots).map(\.minutes), [495, 1245])
    }
    func testFavoriteSurahPersistsIndependentlyOfAyahBookmarks() throws {
        var state = AppState()
        state.bookmarks = ["2:255"]
        state.toggleFavorite(55)
        state.toggleFavorite(1)
        let decoded = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded.favoriteSurahs, [55, 1])
        state.toggleFavorite(55)
        XCTAssertEqual(state.favoriteSurahs, [1])
        XCTAssertEqual(state.bookmarks, ["2:255"])
    }
    func testInvalidFavoriteIDsAreIgnored() {
        var state = AppState()
        state.toggleFavorite(0); state.toggleFavorite(115)
        XCTAssertTrue(state.favoriteSurahs.isEmpty)
    }
    func testLegacyDataMigrationPreservesRoutineAndProgress() throws {
        var old = AppState()
        old.durationMinutes = 25
        old.enqueue(id: "unfinished")
        old.credit(20)
        old.bookmarks = ["55:1"]
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        for key in ["favoriteSurahs", "lastPage", "lockCadence"] { object.removeValue(forKey: key) }
        var reminders = try XCTUnwrap(object["reminders"] as? [[String: Any]])
        for index in reminders.indices { for key in ["cadence", "secondHour", "secondMinute"] { reminders[index].removeValue(forKey: key) } }
        object["reminders"] = reminders
        let migrated = try JSONDecoder().decode(AppState.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(migrated.durationMinutes, 25)
        XCTAssertEqual(migrated.activeSession?.remaining, 1480)
        XCTAssertEqual(migrated.bookmarks, ["55:1"])
        XCTAssertEqual(migrated.lockCadence, .custom)
        XCTAssertEqual(migrated.reminders.first?.cadence, .daily)
        XCTAssertEqual(migrated.lastPage, 1)
        XCTAssertTrue(migrated.favoriteSurahs.isEmpty)
    }
    func testDailyNotificationKeepsCustomContentAndTime() throws {
        let reminder = ZikrReminder(title: "My zikr", text: "الحمد لله", hour: 7, minute: 23, enabled: true)
        let request = try XCTUnwrap(ReminderScheduler.requests(for: reminder).first)
        XCTAssertEqual(request.content.title, reminder.title)
        XCTAssertEqual(request.content.body, reminder.text)
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.dateComponents.hour, 7)
        XCTAssertEqual(trigger.dateComponents.minute, 23)
        XCTAssertTrue(trigger.repeats)
    }
    func testTwiceDailyNotificationHasDistinctStableIDs() throws {
        let reminder = ZikrReminder(id: "stable", title: "Zikr", text: "Test", hour: 8, minute: 10, enabled: true, cadence: .twiceDaily, secondHour: 19, secondMinute: 35)
        let requests = ReminderScheduler.requests(for: reminder)
        XCTAssertEqual(requests.map(\.identifier), ["zikr.stable.0", "zikr.stable.1"])
        let times = requests.compactMap { ($0.trigger as? UNCalendarNotificationTrigger)?.dateComponents }
        XCTAssertEqual(times.map(\.hour), [8, 19])
        XCTAssertEqual(times.map(\.minute), [10, 35])
    }
    func testHourlyNotificationRepeatsAtEveryHourBoundary() throws {
        let requests = ReminderScheduler.requests(for: ZikrReminder(title: "Zikr", text: "Test", enabled: true, cadence: .hourly))
        XCTAssertEqual(requests.count, 1)
        let trigger = try XCTUnwrap(requests.first?.trigger as? UNCalendarNotificationTrigger)
        XCTAssertNil(trigger.dateComponents.hour)
        XCTAssertEqual(trigger.dateComponents.minute, 0)
        XCTAssertTrue(trigger.repeats)
    }
    func testHalfHourNotificationsUseOnlyTwoRequestsForWholeDay() {
        let requests = ReminderScheduler.requests(for: ZikrReminder(title: "Zikr", text: "Test", enabled: true, cadence: .halfHourly))
        XCTAssertEqual(requests.count, 2)
        let triggers = requests.compactMap { $0.trigger as? UNCalendarNotificationTrigger }
        XCTAssertEqual(triggers.map { $0.dateComponents.minute }, [0, 30])
        XCTAssertTrue(triggers.allSatisfy { $0.dateComponents.hour == nil && $0.repeats })
    }
    func testDisabledReminderDoesNotRegisterNotifications() {
        XCTAssertTrue(ReminderScheduler.requests(for: ZikrReminder(title: "Zikr", text: "Test", enabled: false, cadence: .halfHourly)).isEmpty)
        XCTAssertEqual(ReminderScheduler.identifiers(for: "old"), ["zikr.old", "zikr.old.0", "zikr.old.1"])
    }
    func test604PagesContainEveryAyahExactlyOnceInOrder() {
        let library = QuranLibrary()
        XCTAssertNil(library.error)
        XCTAssertEqual(library.pages.map(\.id), Array(1...604))
        let keys = library.pages.flatMap(\.verses).map { "\($0.surah):\($0.ayah)" }
        let expected = library.surahs.flatMap { surah in surah.verses.map { "\(surah.id):\($0.id)" } }
        XCTAssertEqual(keys, expected)
        XCTAssertEqual(Set(keys).count, 6236)
        XCTAssertTrue(library.pages.allSatisfy { !$0.verses.isEmpty })
        XCTAssertEqual(library.pages[0].verses.count, 7)
        XCTAssertEqual(library.pages[41].verses.first?.ayah, 253)
    }
    func testEveryMushafPageMatchesItsVerifiedSnapshot() throws {
        let manifest = try XCTUnwrap(Mushaf.manifest)
        XCTAssertTrue(manifest.glyphs.contains("King Fahd Glorious Quran Printing Complex"))
        var surahHeaders: [Int] = []
        var basmalas: [Int] = []
        for number in 1...604 {
            // Checksums, line count, and the exact in-order glyph run of the page font.
            let page = try XCTUnwrap(Mushaf.page(number), "Page \(number) failed verification")
            XCTAssertEqual(page.layout.page, number)
            surahHeaders += page.layout.lines.filter { $0.type == "surah-header" }.compactMap(\.surah)
            basmalas += page.layout.lines.filter { $0.type == "basmala" }.compactMap(\.surah)
        }
        XCTAssertEqual(surahHeaders, Array(1...114))
        XCTAssertEqual(basmalas, Array(2...114).filter { $0 != 9 })
    }
    func testMushafRejectsAlteredLayouts() throws {
        let page = try XCTUnwrap(Mushaf.page(534))
        let glyphs = try XCTUnwrap(Mushaf.manifest?.pages[533].glyphs)
        XCTAssertTrue(Mushaf.isValid(page.layout, glyphs: glyphs))
        var lines = page.layout.lines
        // The glyphs that used to leak onto page 534's last line from page 533.
        lines[14] = .init(type: "text", content: "\u{FCCB}\u{FCCC}" + lines[14].content, surah: nil)
        XCTAssertFalse(Mushaf.isValid(.init(page: 534, lines: lines), glyphs: glyphs))
        XCTAssertFalse(Mushaf.isValid(.init(page: 534, lines: Array(page.layout.lines.dropLast())), glyphs: glyphs))
        XCTAssertFalse(Mushaf.isValid(.init(page: 534, lines: page.layout.lines + [page.layout.lines[0]]), glyphs: glyphs))
    }
    func testMushafMatchesPrintedPages() throws {
        func lines(_ number: Int) throws -> [Mushaf.Layout.Line] { try XCTUnwrap(Mushaf.page(number)).layout.lines }
        // Page 534 begins at Ar-Rahman 70; Al-Waqi'ah's heading and basmala are lines 7-8.
        XCTAssertEqual(Mushaf.manifest?.pages[533].firstAyah, "55:70")
        XCTAssertEqual(try lines(534).map(\.type)[6...7], ["surah-header", "basmala"])
        // An-Nisa's heading ends page 76 and its basmala opens page 77.
        XCTAssertEqual(try lines(76).last?.type, "surah-header")
        XCTAssertEqual(try lines(76).last?.surah, 4)
        XCTAssertEqual(try lines(77).first?.type, "basmala")
        // The marker of 84:21 (U+FCC1) follows its last word on page 589, line 14.
        XCTAssertTrue(try lines(589)[13].content.unicodeScalars.contains("\u{FCC1}"))
        XCTAssertEqual(try lines(1).count, 8)
        XCTAssertEqual(try lines(2).map(\.type)[0...1], ["surah-header", "basmala"])
    }
    func testPageIndexAgreesWithMushafPages() throws {
        let library = QuranLibrary()
        let manifest = try XCTUnwrap(Mushaf.manifest)
        let keys = library.surahs.flatMap { surah in surah.verses.map { "\(surah.id):\($0.id)" } }
        for (entry, page) in zip(manifest.pages, library.pages) {
            let starts = page.verses.map { "\($0.surah):\($0.ayah)" }
            // An ayah is indexed on the page where it starts, which may follow one continued from the page before.
            let continued = entry.page > 1 && manifest.pages[entry.page - 2].lastAyah == entry.firstAyah
            let firstStart = continued ? keys[try XCTUnwrap(keys.firstIndex(of: entry.firstAyah)) + 1] : entry.firstAyah
            XCTAssertEqual(starts.first, firstStart, "Page \(entry.page)")
            XCTAssertEqual(starts.last, entry.lastAyah, "Page \(entry.page)")
        }
        XCTAssertEqual(library.pages[533].verses.first.map { "\($0.surah):\($0.ayah)" }, "55:70")
        XCTAssertEqual(library.pages[591].verses.first.map { "\($0.surah):\($0.ayah)" }, "87:11")
    }
    func testEveryPageSplitsIntoItsAyahsForOnPageSelection() throws {
        let library = QuranLibrary()
        for number in 1...604 {
            let page = try XCTUnwrap(Mushaf.page(number))
            let runs = try XCTUnwrap(page.ayahRuns, "Page \(number) has no verified ayah map")
            let segments = try XCTUnwrap(Mushaf.segments(page), "Page \(number) could not be split into ayahs")
            // Splitting marks ayahs without changing a single printed glyph or its order.
            XCTAssertEqual(segments.map { $0.map(\.content).joined() }, page.layout.lines.map(\.content),
                           "Page \(number) changed when split")
            var keys: [String] = []
            for line in segments {
                for segment in line where segment.key != nil && segment.key != keys.last { keys.append(segment.key!) }
            }
            XCTAssertEqual(keys, runs.map(\.key), "Page \(number) ayah order")
            // The bar's ayah list and the printed page must agree, or the wrong ayah is copied.
            XCTAssertEqual(keys, library.pages[number - 1].selectableVerses.map(\.key), "Page \(number) selectable ayahs")
            let glyphs = segments.flatMap { $0 }.filter { $0.key != nil }
                .reduce(0) { $0 + $1.content.unicodeScalars.filter { !$0.properties.isWhitespace }.count }
            XCTAssertEqual(glyphs, try XCTUnwrap(Mushaf.manifest?.pages[number - 1].glyphs), "Page \(number) glyph count")
        }
    }
    func testAyahMapIsRejectedWhenItDoesNotMatchThePage() throws {
        let real = try XCTUnwrap(Mushaf.manifest?.pages[1])  // Page 2.
        func entry(glyphs: Int? = nil, firstAyah: String? = nil, lastAyah: String? = nil,
                   sha: String? = nil) throws -> Mushaf.Manifest.Page {
            let json = """
            {"page":2,"glyphs":\(glyphs ?? real.glyphs),"firstAyah":"\(firstAyah ?? real.firstAyah)",
             "lastAyah":"\(lastAyah ?? real.lastAyah)","layoutSHA256":"\(real.layoutSHA256)",
             "ayahsSHA256":"\(sha ?? real.ayahsSHA256)","fontSHA256":"\(real.fontSHA256)"}
            """
            return try JSONDecoder().decode(Mushaf.Manifest.Page.self, from: Data(json.utf8))
        }
        XCTAssertNotNil(Mushaf.ayahRuns(2, entry: try entry()))
        XCTAssertNil(Mushaf.ayahRuns(2, entry: try entry(glyphs: real.glyphs - 1)))
        XCTAssertNil(Mushaf.ayahRuns(2, entry: try entry(firstAyah: "2:2")))
        XCTAssertNil(Mushaf.ayahRuns(2, entry: try entry(lastAyah: "2:6")))
        XCTAssertNil(Mushaf.ayahRuns(2, entry: try entry(sha: String(repeating: "0", count: 64))))
        // A page whose map is unusable still prints, but without on-page selection.
        XCTAssertNil(Mushaf.segments(.init(layout: try XCTUnwrap(Mushaf.page(2)).layout,
                                           font: Data(), basmalaFont: nil, ayahRuns: nil)))
    }
    func testSavedPagePersists() throws {
        var state = AppState()
        state.lastPage = 42
        let decoded = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded.lastPage, 42)
    }
    func testCustomZikrMatchingTemplateIsNotRelocalizedAfterSaving() throws {
        let preset = ZikrReminder.defaults[0]
        let custom = ZikrReminder(title: preset.title, text: preset.text)
        let decoded = try JSONDecoder().decode(ZikrReminder.self, from: JSONEncoder().encode(custom))
        XCTAssertNil(decoded.presetKey)
        XCTAssertEqual(decoded.displayText, custom.text)
        XCTAssertEqual(decoded.displayTitle, custom.title)
    }
    func testArabicLocalizationResourcesExistAndTranslateCoreActions() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "ar", ofType: "lproj"))
        let bundle = try XCTUnwrap(Bundle(path: path))
        XCTAssertEqual(bundle.localizedString(forKey: "Favorites", value: nil, table: nil), "المفضلة")
        XCTAssertEqual(bundle.localizedString(forKey: "Every 30 minutes", value: nil, table: nil), "كل ٣٠ دقيقة")
        XCTAssertEqual(bundle.localizedString(forKey: "Allow notifications", value: nil, table: nil), "السماح بالإشعارات")
    }
    func testAppIsNamedQuranPauseInEnglishAndArabic() throws {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "QuranPause")
        // App Store Connect and archives use the bundle name, so it must match too.
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, "QuranPause")
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.quranpause.app")
        let bundle = try XCTUnwrap(Bundle(path: try XCTUnwrap(Bundle.main.path(forResource: "ar", ofType: "lproj"))))
        XCTAssertEqual(bundle.localizedString(forKey: "QuranPause", value: nil, table: nil), "وقفة قرآن")
        XCTAssertEqual(bundle.localizedString(forKey: "Welcome to QuranPause", value: nil, table: nil), "مرحبًا بك في وقفة قرآن")
        // The retired name is gone from every user-facing string, in both languages.
        for language in ["en", "ar"] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: language))
            let strings = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
            XCTAssertFalse(strings.contains { $0.key.contains("QuranTime") || $0.value.contains("QuranTime") }, language)
        }
    }
}
