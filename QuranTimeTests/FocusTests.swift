import XCTest
@testable import QuranTime

final class FocusTests: XCTestCase {
    func testBackgroundNeverEarnsTime() {
        var clock = ForegroundClock()
        clock.resume(at: 10)
        XCTAssertEqual(clock.tick(at: 11), 1)
        clock.pause()
        XCTAssertEqual(clock.tick(at: 1000), 0)
        clock.resume(at: 1000)
        XCTAssertEqual(clock.tick(at: 1001), 1)
    }
    func testSuspendedOrReversedClockDoesNotEarnCredit() {
        var clock = ForegroundClock()
        clock.resume(at: 10)
        XCTAssertEqual(clock.tick(at: 600), 0)
        XCTAssertEqual(clock.tick(at: 599), 0)
        XCTAssertEqual(clock.tick(at: 600), 1)
    }
    func testSessionOnlyCompletesAtTarget() {
        var state = AppState()
        state.durationMinutes = 1
        state.enqueue(id: "first")
        state.credit(59)
        XCTAssertEqual(state.activeSession?.remaining, 1)
        state.credit(1)
        XCTAssertNil(state.activeSession)
        XCTAssertNotNil(state.sessions[0].completedAt)
    }
    func testCompletionDoesNotSkipAnotherCommitment() {
        var state = AppState()
        state.durationMinutes = 1
        state.enqueue(id: "first")
        state.enqueue(id: "second")
        state.credit(100)
        XCTAssertEqual(state.activeSession?.id, "second")
        XCTAssertEqual(state.activeSession?.remaining, 60)
    }
    func testRepeatedCallbacksCannotDuplicateSessions() {
        var state = AppState()
        state.enqueue(id: "same")
        state.enqueue(id: "same")
        state.credit(600)
        state.enqueue(id: "same")
        XCTAssertEqual(state.sessions.count, 1)
    }
    func testPersistedSessionResumesFromRemainingTime() throws {
        var state = AppState()
        state.enqueue(id: "persistent")
        state.credit(12)
        let decoded = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded.activeSession?.remaining, 588)
    }
    func testInvalidCreditCannotChangeTimer() {
        var state = AppState()
        state.enqueue(id: "one")
        state.credit(-20); state.credit(.infinity); state.credit(.nan)
        XCTAssertEqual(state.activeSession?.remaining, 600)
    }
    func testScheduleReconciliationAndIdempotency() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 12))!
        var state = AppState()
        state.scheduleEnabled = true
        state.scheduleEnabledAt = day
        state.lockTimes = [LockTime(hour: 7, minute: 0), LockTime(hour: 13, minute: 0)]
        state.reconcileSchedule(now: day.addingTimeInterval(14 * 3600), calendar: calendar)
        state.reconcileSchedule(now: day.addingTimeInterval(15 * 3600), calendar: calendar)
        XCTAssertEqual(state.sessions.count, 2)
        state.reconcileSchedule(now: day.addingTimeInterval(32 * 3600), calendar: calendar)
        XCTAssertEqual(state.sessions.count, 3)
    }
    func testNewRoutineDoesNotRetroactivelyLock() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 12))!
        var state = AppState()
        state.scheduleEnabled = true
        state.scheduleEnabledAt = day.addingTimeInterval(12 * 3600)
        state.lockTimes = [LockTime(hour: 7, minute: 0), LockTime(hour: 13, minute: 0)]
        state.reconcileSchedule(now: day.addingTimeInterval(14 * 3600), calendar: calendar)
        XCTAssertEqual(state.sessions.count, 1)
    }
    func testDisabledSchedulePreservesExistingLock() {
        var state = AppState()
        state.enqueue(id: "existing")
        state.scheduleEnabled = false
        state.reconcileSchedule()
        XCTAssertEqual(state.sessions.count, 1)
        XCTAssertNotNil(state.activeSession)
    }
    func testChangingDurationDoesNotShortenExistingLock() {
        var state = AppState()
        state.durationMinutes = 30
        state.enqueue(id: "existing")
        state.durationMinutes = 1
        XCTAssertEqual(state.activeSession?.remaining, 1800)
    }
    func testOfflineQuranIntegrity() throws {
        let library = QuranLibrary()
        XCTAssertNil(library.error)
        XCTAssertEqual(library.surahs.count, 114)
        XCTAssertEqual(library.surahs.reduce(0) { $0 + $1.verses.count }, 6236)
        for (index, surah) in library.surahs.enumerated() {
            XCTAssertEqual(surah.id, index + 1)
            XCTAssertEqual(surah.verses.count, surah.total_verses)
            XCTAssertEqual(surah.verses.map(\.id), Array(1...surah.total_verses))
            XCTAssertTrue(surah.verses.allSatisfy { !$0.text.isEmpty && !$0.translation.isEmpty })
        }
    }
}
