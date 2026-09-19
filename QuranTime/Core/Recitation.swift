import AVFoundation
import MediaPlayer
import SwiftUI

/// A verified full-surah recitation from Quran Foundation. `scripts/download-recitations.py`
/// builds `recitations.json` only from reciters whose 114 files all pass its checks.
struct Reciter: Decodable, Identifiable, Hashable {
    struct Track: Decodable, Hashable {
        let surah: Int
        let url: URL
        let seconds: Double
    }
    let id: Int
    let name: String
    let arabicName: String
    let style: String
    let surahs: [Track]

    var displayName: String { I18n.isArabic ? arabicName : name }
    var styleName: String { I18n.text(style) }
    func track(_ surah: Int) -> Track? { surahs.indices.contains(surah - 1) ? surahs[surah - 1] : nil }
}

enum Recitations {
    static let audioHost = "download.quranicaudio.com"
    static let defaultReciterID = 7  // Mishari Rashid al-`Afasy

    static let catalog: [Reciter] = {
        struct File: Decodable { let reciters: [Reciter] }
        guard let url = Bundle.main.url(forResource: "recitations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let reciters = try? JSONDecoder().decode(File.self, from: data).reciters else { return [] }
        return reciters.filter(isValid)
    }()

    /// One HTTPS recording per surah, in order, from Quran Foundation's audio host.
    static func isValid(_ reciter: Reciter) -> Bool {
        reciter.surahs.map(\.surah) == Array(1...114) && reciter.surahs.allSatisfy {
            $0.url.scheme == "https" && $0.url.host == audioHost && $0.seconds > 0
        }
    }

    static func reciter(id: Int) -> Reciter? { catalog.first { $0.id == id } ?? catalog.first { $0.id == defaultReciterID } ?? catalog.first }
}

/// Streams recitations and reports only time that was actually heard.
@MainActor @Observable final class RecitationPlayer {
    private(set) var surah: Int?
    private(set) var ayah: Int?
    private(set) var reciter: Reciter?
    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var elapsed: Double = 0
    private(set) var duration: Double = 0

    @ObservationIgnored var beforePlayback: () -> Void = {}
    var title: String { surah.map { surahTitle($0) + (ayah.map { " · " + I18n.format("Ayah %lld", $0) } ?? "") } ?? "" }

    /// Seconds of recitation heard since the last call; audible playback only.
    @ObservationIgnored var onHeard: (Double) -> Void = { _ in }
    /// Called when audible playback starts or stops.
    @ObservationIgnored var onListeningChange: (Bool) -> Void = { _ in }
    /// The surah's display name, for the player bar and Lock Screen.
    @ObservationIgnored var surahTitle: (Int) -> String = { I18n.format("Surah %lld", $0) }
    /// Called with a user-facing message when a recitation cannot play.
    @ObservationIgnored var onError: (String) -> Void = { _ in }

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var clock = ListeningClock()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var itemObservation: NSKeyValueObservation?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    /// Ayahs still to play after the current one, for a selected range of ayahs.
    @ObservationIgnored private var queue: [(surah: Int, ayah: Int)] = []

    var reciterID: Int {
        get { UserDefaults.standard.object(forKey: "reciterID") as? Int ?? Recitations.defaultReciterID }
        set { UserDefaults.standard.set(newValue, forKey: "reciterID") }
    }

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.progress(time.seconds) }
        }
        statusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.statusChanged() }
        }
        configureRemoteCommands()
    }

    func isCurrent(_ surah: Int) -> Bool { self.surah == surah && ayah == nil }

    /// Plays the surah with the chosen reciter, or pauses/resumes it if it is already loaded.
    func toggle(surah: Int) {
        if self.surah == surah, ayah == nil, reciter?.id == reciterID {
            isPlaying || isLoading ? pause() : resume()
        } else {
            play(surah: surah)
        }
    }

    /// Plays a selected range of ayahs in order, stopping after the last one.
    func play(surah: Int, from first: Int, through last: Int) {
        play(surah: surah, ayah: first)
        queue = first < last ? ((first + 1)...last).map { (surah, $0) } : []
    }

    func toggle(surah: Int, ayah: Int) {
        if self.surah == surah, self.ayah == ayah, reciter?.id == reciterID {
            isPlaying || isLoading ? pause() : resume()
        } else { play(surah: surah, ayah: ayah) }
    }

    func toggleCurrent() { isPlaying || isLoading ? pause() : resume() }

    func play(surah: Int, ayah: Int? = nil) {
        queue = []
        guard let reciter = Recitations.reciter(id: reciterID), let track = reciter.track(surah) else {
            onError(I18n.text("This recitation isn’t available.")); return
        }
        let url: URL
        if let ayah {
            guard let verseURL = AyahAudio.url(surah: surah, ayah: ayah, reciterID: reciter.id) else {
                onError(I18n.text("This recitation isn’t available.")); return
            }
            url = verseURL
        } else { url = track.url }
        beforePlayback()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { onError(I18n.text("Audio couldn’t start.") + " " + error.localizedDescription); return }
        let item = AVPlayerItem(url: url)
        observeEnd(of: item)
        itemObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            DispatchQueue.main.async {
                guard let self, self.player.currentItem === item else { return }
                self.stop()
                self.onError(I18n.text("The recitation couldn’t load. Check your internet connection and try again."))
            }
        }
        clock.pause()
        self.surah = surah
        self.ayah = ayah
        self.reciter = reciter
        elapsed = 0
        duration = ayah == nil ? track.seconds : 0
        player.replaceCurrentItem(with: item)
        player.play()
        updateNowPlaying()
    }

    func resume() {
        guard player.currentItem != nil else { if let surah { play(surah: surah, ayah: ayah) }; return }
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
    }

    func pause() { player.pause() }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        queue = []
        clock.pause()
        surah = nil
        ayah = nil
        reciter = nil
        elapsed = 0
        duration = 0
        statusChanged()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Restarts the current surah with a newly chosen reciter.
    func reciterChanged() {
        if let surah, reciter?.id != reciterID { play(surah: surah, ayah: ayah) }
    }

    private var isAudible: Bool {
        player.timeControlStatus == .playing && player.rate > 0 && AVAudioSession.sharedInstance().outputVolume > 0
    }

    private func progress(_ seconds: Double) {
        guard seconds.isFinite else { return }
        elapsed = seconds
        if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 { duration = itemDuration }
        let heard = clock.tick(uptime: ProcessInfo.processInfo.systemUptime, media: seconds, audible: isAudible)
        if heard > 0 { onHeard(heard) }
    }

    private func statusChanged() {
        let playing = player.timeControlStatus == .playing
        let loading = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        if isPlaying != playing {
            isPlaying = playing
            if !playing { clock.pause() }
            onListeningChange(playing)
        }
        isLoading = loading
        updateNowPlaying()
    }

    private func observeEnd(of item: AVPlayerItem) {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.player.currentItem === item, let surah = self.surah else { return }
                if self.ayah != nil {
                    guard let next = self.queue.first else { self.stop(); return }
                    let rest = Array(self.queue.dropFirst())
                    self.play(surah: next.surah, ayah: next.ayah)
                    self.queue = rest
                    return
                }
                // Continue with the next surah so a listening session is not cut short.
                surah < 114 ? self.play(surah: surah + 1) : self.stop()
            }
        }
    }

    private func updateNowPlaying() {
        guard surah != nil, let reciter else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: reciter.displayName,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
    }

    private func configureRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.resume() }; return .success }
        commands.pauseCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.pause() }; return .success }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { guard let self else { return }; self.isPlaying ? self.pause() : self.resume() }
            return .success
        }
        // Seeking and speed changes are not offered, so heard time follows the recitation itself.
        commands.changePlaybackPositionCommand.isEnabled = false
        commands.skipForwardCommand.isEnabled = false
        commands.skipBackwardCommand.isEnabled = false
    }
}
