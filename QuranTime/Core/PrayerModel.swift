import AVFoundation
import CoreLocation
import SwiftUI
import UserNotifications

enum QuranNotificationDestination: Equatable, Sendable {
    case prayer
    case zikr
}

@MainActor @Observable final class PrayerModel: NSObject, @preconcurrency CLLocationManagerDelegate, UNUserNotificationCenterDelegate, AVAudioPlayerDelegate {
    private(set) var place: PrayerPlace?
    private(set) var method = PrayerMethod.northAmerica
    private(set) var hanafi = false
    private(set) var alertsEnabled = false
    private(set) var moments: [PrayerMoment] = []
    private(set) var upcoming: [PrayerMoment] = []
    private(set) var heading: Double?
    private(set) var locating = false
    private(set) var searching = false
    private(set) var cityResults: [PrayerPlace] = []
    private(set) var playingAzan = false
    private(set) var scheduledThrough: Date?
    private(set) var notificationDenied = false
    var error: String?
    private(set) var notificationDestination: QuranNotificationDestination?
    @ObservationIgnored var beforeAzan: () -> Void = {}
    @ObservationIgnored private let locationManager = CLLocationManager()
    @ObservationIgnored private let geocoder = CLGeocoder()
    @ObservationIgnored private let cityGeocoder = CLGeocoder()
    @ObservationIgnored private var audio: AVAudioPlayer?
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var refreshAgain = false
    @ObservationIgnored private var wantsCompass = false
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?

    override init() {
        super.init()
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "prayerPlace") { place = try? JSONDecoder().decode(PrayerPlace.self, from: data) }
        method = PrayerMethod(rawValue: defaults.string(forKey: "prayerMethod") ?? "") ?? .northAmerica
        hanafi = defaults.bool(forKey: "prayerHanafi")
        alertsEnabled = defaults.bool(forKey: "prayerAlerts")
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        UNUserNotificationCenter.current().delegate = self
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopAzan() }
        }
        calculate()
    }
    func calculate(now: Date = .now) {
        guard let place else { moments = []; upcoming = []; return }
        moments = PrayerSchedule.day(now, place: place, method: method, hanafi: hanafi)
        upcoming = PrayerSchedule.upcoming(from: now, place: place, method: method, hanafi: hanafi)
    }
    func setMethod(_ value: PrayerMethod) {
        method = value
        UserDefaults.standard.set(value.rawValue, forKey: "prayerMethod")
        calculate(); Task { await refreshAlerts() }
    }
    func setHanafi(_ value: Bool) {
        hanafi = value
        UserDefaults.standard.set(value, forKey: "prayerHanafi")
        calculate(); Task { await refreshAlerts() }
    }
    func select(_ value: PrayerPlace) {
        // Choosing a city wins over any outstanding device-location request.
        locating = false; locationManager.stopUpdatingLocation(); geocoder.cancelGeocode()
        place = value
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: "prayerPlace")
        cityResults = []; error = nil
        calculate(); Task { await refreshAlerts() }
    }
    func locate() {
        error = nil
        switch locationManager.authorizationStatus {
        case .notDetermined: locating = true; locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: locating = true; locationManager.requestLocation()
        default: error = I18n.text("Allow location in Settings, or choose a city.")
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if locating { manager.requestLocation() }
            if wantsCompass { manager.startUpdatingHeading() }
        case .denied, .restricted:
            heading = nil
            if locating { locating = false; error = I18n.text("Allow location in Settings, or choose a city.") }
        default: break
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard locating else { return }
        guard let location = locations.last, location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) < 300 else {
            locating = false; error = I18n.text("Couldn’t find your location. Choose a city or try again."); return
        }
        Task {
            do {
                let marks = try await geocoder.reverseGeocodeLocation(location)
                guard locating else { return }
                guard let mark = marks.first, let zone = mark.timeZone else {
                    locating = false; error = I18n.text("Couldn’t find the local time zone. Choose a city or try again."); return
                }
                select(PrayerPlace(name: mark.locality ?? mark.administrativeArea ?? I18n.text("Current location"),
                                   latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                                   timeZoneID: zone.identifier))
            } catch {
                guard locating else { return }
                locating = false; self.error = I18n.text("Couldn’t find your location. Choose a city or try again.")
            }
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard locating else { return }
        locating = false; self.error = I18n.text("Couldn’t find your location. Choose a city or try again.")
    }
    func searchCity(_ query: String) async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !searching else { return }
        searching = true; error = nil; cityResults = []
        defer { searching = false }
        do {
            let marks = try await cityGeocoder.geocodeAddressString(query)
            cityResults = marks.compactMap { mark in
                guard let coordinate = mark.location?.coordinate, let zone = mark.timeZone else { return nil }
                return PrayerPlace(name: [mark.locality ?? mark.name, mark.administrativeArea, mark.country].compactMap { $0 }.joined(separator: ", "),
                                   latitude: coordinate.latitude, longitude: coordinate.longitude, timeZoneID: zone.identifier)
            }
            if cityResults.isEmpty { error = I18n.text("No city found. Try the city and country name.") }
        } catch { self.error = I18n.text("City search needs an internet connection. Please try again.") }
    }
    func startCompass() {
        wantsCompass = true
        updateOrientation()
        if CLLocationManager.headingAvailable() { locationManager.startUpdatingHeading() }
    }
    func stopCompass() { wantsCompass = false; locationManager.stopUpdatingHeading(); heading = nil }
    func updateOrientation() {
        let orientation = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.interfaceOrientation
        switch orientation {
        case .landscapeLeft: locationManager.headingOrientation = .landscapeLeft
        case .landscapeRight: locationManager.headingOrientation = .landscapeRight
        case .portraitUpsideDown: locationManager.headingOrientation = .portraitUpsideDown
        default: locationManager.headingOrientation = .portrait
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Never label magnetic north as true north; show a numeric bearing if unavailable.
        heading = newHeading.headingAccuracy >= 0 && newHeading.headingAccuracy <= 25 && newHeading.trueHeading >= 0 ? newHeading.trueHeading : nil
    }
    func setAlerts(_ enabled: Bool) async {
        if enabled {
            do {
                guard try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) else {
                    notificationDenied = true; return
                }
            } catch { self.error = I18n.text("Couldn’t enable prayer alerts. Please try again."); return }
        }
        alertsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "prayerAlerts")
        await refreshAlerts()
    }
    /// Serializes refreshes so changes cannot leave stale prayer alerts behind.
    func refreshAlerts() async {
        if refreshing { refreshAgain = true; return }
        refreshing = true
        await NotificationScheduleLock.acquire()
        defer { refreshing = false; NotificationScheduleLock.release() }
        repeat {
            refreshAgain = false
            calculate()
            let center = UNUserNotificationCenter.current()
            let status = await center.notificationSettings().authorizationStatus
            notificationDenied = status == .denied
            let pending = await center.pendingNotificationRequests()
            let owned = pending.filter { $0.identifier.hasPrefix(PrayerSchedule.notificationPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: owned.map(\.identifier))
            scheduledThrough = nil
            guard alertsEnabled, status == .authorized || status == .provisional, let place else { continue }
            // Leave four slots free and share the limit with existing zikr reminders.
            let capacity = max(0, 60 - (pending.count - owned.count))
            let requests = upcoming.prefix(capacity).map { ($0, PrayerSchedule.request(for: $0, place: place)) }
            if requests.isEmpty && !upcoming.isEmpty { error = I18n.text("No room for prayer alerts. Disable a zikr reminder and try again.") }
            do {
                for (moment, request) in requests { try await center.add(request); scheduledThrough = moment.date }
            } catch { self.error = I18n.text("Some prayer alerts couldn’t be scheduled. Please try again.") }
        } while refreshAgain
    }
    func toggleAzan() {
        if playingAzan { stopAzan(); return }
        guard let url = Bundle.main.url(forResource: "azan", withExtension: "mp3") else {
            error = I18n.text("The azan recording is unavailable."); return
        }
        beforeAzan()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            audio = try AVAudioPlayer(contentsOf: url)
            audio?.delegate = self
            playingAzan = audio?.play() == true
            if !playingAzan { error = I18n.text("Audio couldn’t start.") }
        } catch { self.error = I18n.text("Audio couldn’t start.") }
    }
    func stopAzan() {
        guard audio != nil else { return }
        audio?.stop(); audio = nil; playingAzan = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func takeNotificationDestination() -> QuranNotificationDestination? {
        defer { notificationDestination = nil }
        return notificationDestination
    }
    nonisolated static func destination(for identifier: String, actionIdentifier: String) -> QuranNotificationDestination? {
        guard actionIdentifier == UNNotificationDefaultActionIdentifier else { return nil }
        if identifier.hasPrefix(PrayerSchedule.notificationPrefix) { return .prayer }
        if identifier.hasPrefix(ReminderScheduler.notificationPrefix) { return .zikr }
        return nil
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in stopAzan() }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Keep UIKit's notification completion on the main actor. The async delegate
        // bridge can resume on a cooperative queue during scene restoration.
        Task { @MainActor in completionHandler([.banner, .sound, .list]) }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let destination = Self.destination(for: response.notification.request.identifier,
                                           actionIdentifier: response.actionIdentifier)
        Task { @MainActor [weak self] in
            self?.notificationDestination = destination
            completionHandler()
        }
    }
}
