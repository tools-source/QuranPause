import XCTest
@testable import QuranTime

final class RecitationTests: XCTestCase {
    func testListeningCreditsOnlyAudibleProgress() {
        var clock = ListeningClock()
        XCTAssertEqual(clock.tick(uptime: 10, media: 0, audible: true), 0)
        XCTAssertEqual(clock.tick(uptime: 11, media: 1, audible: true), 1)
        // Never more than the time that passed, even if the media jumped ahead.
        XCTAssertEqual(clock.tick(uptime: 12, media: 30, audible: true), 1)
        // Silence earns nothing, and resuming starts a fresh interval.
        XCTAssertEqual(clock.tick(uptime: 13, media: 31, audible: false), 0)
        XCTAssertEqual(clock.tick(uptime: 14, media: 32, audible: true), 0)
        XCTAssertEqual(clock.tick(uptime: 15, media: 33, audible: true), 1)
    }
    func testListeningClockRejectsStallsAndBackwardJumps() {
        var clock = ListeningClock()
        _ = clock.tick(uptime: 0, media: 100, audible: true)
        XCTAssertEqual(clock.tick(uptime: 30, media: 130, audible: true), 0)
        XCTAssertEqual(clock.tick(uptime: 31, media: 20, audible: true), 0)
        XCTAssertEqual(clock.tick(uptime: 32, media: 20.5, audible: true), 0.5)
        clock.pause()
        XCTAssertEqual(clock.tick(uptime: 33, media: 21.5, audible: true), 0)
    }
    func testBundledRecitersAreVerifiedAndComplete() throws {
        let catalog = Recitations.catalog
        XCTAssertEqual(catalog.count, 10)
        XCTAssertTrue(catalog.allSatisfy(Recitations.isValid))
        XCTAssertEqual(Set(catalog.map(\.id)).count, catalog.count)
        // Broken catalogue entries stay out: Minshawi Mujawwad (404s) and al-Tablawi (mislabeled files).
        XCTAssertFalse(catalog.contains { [8, 11].contains($0.id) })
        let alafasy = try XCTUnwrap(Recitations.reciter(id: Recitations.defaultReciterID))
        XCTAssertEqual(alafasy.track(1)?.url.absoluteString, "https://download.quranicaudio.com/qdc/mishari_al_afasy/murattal/1.mp3")
        XCTAssertNil(alafasy.track(115))
        XCTAssertEqual(Recitations.reciter(id: 999)?.id, Recitations.defaultReciterID)
        for reciter in catalog { XCTAssertFalse(I18n.text(reciter.style).isEmpty) }
    }
    @MainActor func testListeningEarnsTimeOnlyDuringARunningSession() throws {
        let model = AppModel()
        defer { model.pauseSession(); model.setListening(false); model.update { $0.sessions.removeAll { $0.isPractice } } }
        model.update { $0.sessions.removeAll { $0.isPractice } }
        try XCTSkipUnless(AppModel.isSimulator && model.state.activeSession == nil, "Needs the simulator without a real commitment")

        model.beginSession()
        let start = try XCTUnwrap(model.state.activeSession?.remaining)
        model.creditListening(5)
        XCTAssertEqual(model.state.activeSession?.remaining, start, "No credit without audible playback")

        model.setListening(true)
        XCTAssertTrue(model.isEarningTime)
        model.creditListening(5)
        XCTAssertEqual(model.state.activeSession?.remaining, start - 5)

        // Reading while listening is not counted twice.
        model.setForeground(true)
        model.setReadingQuran(true)
        model.tick()
        XCTAssertEqual(model.state.activeSession?.remaining, start - 5)

        model.pauseSession()
        model.creditListening(5)
        XCTAssertEqual(model.state.activeSession?.remaining, start - 5, "A paused session earns nothing")
        model.setReadingQuran(false)
    }
}
