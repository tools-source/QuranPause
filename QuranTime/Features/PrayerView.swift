import SwiftUI

struct PrayerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var phase
    @State private var choosingCity = false
    @State private var enablingAlerts = false
    private var prayers: PrayerModel { model.prayers }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeading(eyebrow: "A rhythm of remembrance", title: "Prayer", subtitle: "Prayer times, azan, and your direction to the Kaaba.")
                locationCard
                if let place = prayers.place {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        schedule(place: place, now: context.date)
                            .task(id: dayKey(context.date, place: place)) { await prayers.refreshAlerts() }
                    }
                    qiblaCard(place: place)
                    preferences
                } else {
                    ContentUnavailableView("Set your prayer location", systemImage: "location.circle",
                        description: Text("Use your location or choose a city to see prayer times and Qibla. Your saved times work offline."))
                }
                if let error = prayers.error {
                    Label(error, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(QT.muted)
                }
            }.padding(24).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }
        .background(QT.paper).navigationTitle("Prayer").navigationBarTitleDisplayMode(.inline)
        .onAppear { prayers.startCompass() }
        .onDisappear { prayers.stopCompass() }
        .onChange(of: phase) { _, value in value == .active ? prayers.startCompass() : prayers.stopCompass() }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in prayers.updateOrientation() }
        .sheet(isPresented: $choosingCity) { PrayerCityChooser(prayers: prayers).appPresentation() }
    }
    private var locationCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Label(prayers.place?.name ?? I18n.text("Choose your location"), systemImage: "location.fill").font(.headline).foregroundStyle(QT.green)
                if let place = prayers.place {
                    Text(place.timeZoneID).font(.caption).foregroundStyle(QT.muted)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) { locationButtons }
                    VStack(alignment: .leading, spacing: 12) { locationButtons }
                }
            }
        }
    }
    @ViewBuilder private var locationButtons: some View {
        Button { prayers.locate() } label: {
            Label(LocalizedStringKey(prayers.locating ? "Finding location…" : "Use my location"), systemImage: "location")
        }.disabled(prayers.locating).frame(minHeight: 44)
        Button { choosingCity = true } label: { Label("Choose city", systemImage: "magnifyingglass") }.frame(minHeight: 44)
    }
    private func schedule(place: PrayerPlace, now: Date) -> some View {
        let next = prayers.upcoming.first { $0.date > now }
        return VStack(alignment: .leading, spacing: 16) {
            if let next {
                VStack(alignment: .leading, spacing: 10) {
                    Text("NEXT PRAYER").font(.caption.weight(.semibold)).tracking(1.5)
                    HStack(alignment: .firstTextBaseline) {
                        Text(LocalizedStringKey(next.name)).font(QT.serif(34))
                        Spacer()
                        Text(time(next.date, place: place)).font(.title2.weight(.semibold)).monospacedDigit()
                    }
                    Text(dayLabel(next.date, place: place)).font(.subheadline)
                }.foregroundStyle(.white).padding(24).frame(maxWidth: .infinity, alignment: .leading)
                    .background(QT.green, in: RoundedRectangle(cornerRadius: 24))
            }
            Card {
                VStack(spacing: 16) {
                    Text(dayLabel(now, place: place))
                        .font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                    if prayers.moments.isEmpty {
                        Text("Prayer times are unavailable for this date and location. Check with your local mosque.")
                            .font(.subheadline).foregroundStyle(QT.muted)
                    }
                    ForEach(prayers.moments) { moment in
                        HStack {
                            Text(LocalizedStringKey(moment.name))
                            if !moment.isPrayer { Text("No azan").font(.caption).foregroundStyle(QT.muted) }
                            Spacer()
                            Text(time(moment.date, place: place)).monospacedDigit()
                        }.font(.body.weight(moment.id == next?.id ? .semibold : .regular))
                            .foregroundStyle(moment.id == next?.id ? QT.green : QT.ink)
                            .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
    private func qiblaCard(place: PrayerPlace) -> some View {
        let bearing = PrayerSchedule.qibla(place: place)
        let relative = prayers.heading.map { PrayerSchedule.relativeBearing(qibla: bearing, heading: $0) }
        return Card {
            VStack(spacing: 18) {
                HStack { Label("Qibla", systemImage: "location.north.circle").font(.headline); Spacer(); Text("\(Int(bearing.rounded()))°").monospacedDigit() }.foregroundStyle(QT.green)
                if let relative {
                    ZStack {
                        Circle().stroke(QT.line, lineWidth: 2).frame(width: 160, height: 160)
                        Image(systemName: "location.north.fill").font(.system(size: 66)).foregroundStyle(QT.green)
                            .rotationEffect(.degrees(relative)).environment(\.layoutDirection, .leftToRight)
                    }.accessibilityLabel("Qibla direction").accessibilityValue(Text("\(Int(relative.rounded()))°"))
                    Text(LocalizedStringKey(abs(relative) < 8 ? "You’re facing the Qibla" : "Turn until the arrow points straight ahead"))
                        .font(.subheadline.weight(.medium)).multilineTextAlignment(.center)
                } else {
                    Image(systemName: "safari").font(.system(size: 52, weight: .light)).foregroundStyle(QT.gold).padding(12)
                    Text("Compass unavailable or calibrating. Use the bearing from true north.")
                        .font(.subheadline).multilineTextAlignment(.center)
                }
                Text("Bearing from true north for your selected location. Keep the device flat, away from magnets. For a live compass, allow location and move the device gently to calibrate.")
                    .font(.caption).foregroundStyle(QT.muted).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity)
        }
    }
    private var preferences: some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                Text("Prayer settings").font(.headline)
                Picker("Calculation method", selection: Binding(get: { prayers.method }, set: { prayers.setMethod($0) })) {
                    ForEach(PrayerMethod.allCases) { method in Text(LocalizedStringKey(method.title)).tag(method) }
                }.pickerStyle(.menu)
                Toggle("Hanafi Asr time", isOn: Binding(get: { prayers.hanafi }, set: { prayers.setHanafi($0) }))
                Text("Choose the method used by your local mosque. Standard Asr follows Shafi, Maliki, and Hanbali; Hanafi uses a later time.")
                    .font(.caption).foregroundStyle(QT.muted)
                Divider()
                Toggle("Azan alerts", isOn: Binding(get: { prayers.alertsEnabled }, set: { enabled in
                    enablingAlerts = true
                    Task { await prayers.setAlerts(enabled); enablingAlerts = false }
                })).disabled(enablingAlerts)
                if prayers.notificationDenied {
                    Button("Allow notifications in Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
                }
                if let through = prayers.scheduledThrough {
                    Text(I18n.text("Alerts scheduled through") + " " + through.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: Locale(identifier: I18n.isArabic ? "ar" : "en"), timeZone: prayers.place?.timeZone ?? .current)))
                        .font(.caption).foregroundStyle(QT.muted)
                }
                if prayers.alertsEnabled {
                    Button("Refresh prayer alerts") { Task { await prayers.refreshAlerts() } }.frame(minHeight: 44)
                }
                Text("Alerts play a short azan. Tap the notification for the full azan. Silent mode and Focus may silence alerts. Open the app weekly and after travel to refresh the schedule.")
                    .font(.caption).foregroundStyle(QT.muted)
                Button { prayers.toggleAzan() } label: {
                    Label(LocalizedStringKey(prayers.playingAzan ? "Stop azan" : "Listen to azan"), systemImage: prayers.playingAzan ? "stop.circle.fill" : "play.circle.fill")
                }.frame(minHeight: 44)
                Text("Azan by Andrewler · CC BY-SA 4.0. Converted to MP3; alert is a 28-second excerpt.").font(.caption2).foregroundStyle(QT.muted)
                Link("Azan source & license", destination: URL(string: "https://commons.wikimedia.org/wiki/File:Azan.ogg")!).font(.caption)
            }
        }
    }
    private func dayLabel(_ date: Date, place: PrayerPlace) -> String {
        date.formatted(Date.FormatStyle(date: .complete, time: .omitted, locale: Locale(identifier: I18n.isArabic ? "ar" : "en"), timeZone: place.timeZone))
    }
    private func time(_ date: Date, place: PrayerPlace) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: I18n.isArabic ? "ar" : "en")
        formatter.timeZone = place.timeZone; formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    private func dayKey(_ date: Date, place: PrayerPlace) -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = place.timeZone
        return "\(calendar.startOfDay(for: date))-\(place.timeZoneID)"
    }
}

private struct PrayerCityChooser: View {
    let prayers: PrayerModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("City and country", text: $query).textContentType(.addressCity).submitLabel(.search)
                        .onSubmit { Task { await prayers.searchCity(query) } }
                    Button { Task { await prayers.searchCity(query) } } label: {
                        HStack { Text("Search cities"); if prayers.searching { Spacer(); ProgressView() } }
                    }.disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || prayers.searching)
                } footer: { Text("City search needs internet. Your selected location is saved on this device for offline calculations.") }
                ForEach(Array(prayers.cityResults.enumerated()), id: \.offset) { _, place in
                    Button { prayers.select(place); dismiss() } label: {
                        VStack(alignment: .leading, spacing: 6) { Text(place.name); Text(place.timeZoneID).font(.caption).foregroundStyle(QT.muted) }
                    }
                }
                if let error = prayers.error { Text(error).foregroundStyle(QT.muted) }
            }.navigationTitle("Choose city").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
