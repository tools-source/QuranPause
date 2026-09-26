import SwiftUI
import Combine

@main struct QuranTimeApp: App {
    @AppStorage("appLanguage") private var language = AppLanguage.system.rawValue
    @AppStorage("appAppearance") private var appearance = AppAppearance.system.rawValue
    @State private var model = AppModel()
    @State private var library = QuranLibrary()
    var body: some Scene {
        WindowGroup {
            AppShell().environment(model).environment(library)
                .tint(QT.green)
                .appPresentation()
                .id(language)
                .onChange(of: language, initial: true) { _, value in
                    PresentationPreferences.save(language: (AppLanguage(rawValue: value) ?? .system).code, appearance: appearance)
                    Task { await model.refreshPresetNotifications() }
                }
                .onChange(of: appearance) { _, value in
                    PresentationPreferences.save(language: (AppLanguage(rawValue: language) ?? .system).code, appearance: value)
                }
        }
    }
}

struct AppShell: View {
    @Environment(AppModel.self) private var model
    @Environment(QuranLibrary.self) private var library
    @Environment(\.scenePhase) private var phase
    @State private var tab = 0
    @AppStorage("completedWelcome") private var completedWelcome = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    var body: some View {
        @Bindable var model = model
        TabView(selection: $tab) {
            NavigationStack { HomeView(selectedTab: $tab) }.safeAreaInset(edge: .bottom) { RecitationBar() }.tabItem { Label("Today", systemImage: "sun.max") }.tag(0)
            NavigationStack { QuranView() }.safeAreaInset(edge: .bottom) { RecitationBar() }.tabItem { Label("Quran", systemImage: "book") }.tag(1)
            NavigationStack { RoutineView() }.safeAreaInset(edge: .bottom) { RecitationBar() }.tabItem { Label("Routine", systemImage: "clock.arrow.2.circlepath") }.tag(2)
            NavigationStack { ZikrView() }.safeAreaInset(edge: .bottom) { RecitationBar() }.tabItem { Label("Zikr", systemImage: "sparkles") }.tag(3)
            NavigationStack { PrayerView() }.safeAreaInset(edge: .bottom) { RecitationBar() }.tabItem { Label("Prayer", systemImage: "moon.stars") }.tag(4)
        }
        .onChange(of: model.prayers.notificationDestination) { _, _ in openNotificationDestinationIfReady() }
        .onAppear {
            openNotificationDestinationIfReady()
            model.recitation.surahTitle = { [library] id in library.surahs.first { $0.id == id }?.displayName ?? I18n.format("Surah %lld", id) }
        }
        .onChange(of: phase, initial: true) { _, value in
            model.setForeground(value == .active)
            if value == .active { openNotificationDestinationIfReady() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            Task { await model.prayers.refreshAlerts() }
        }
        .onReceive(timer) { _ in if phase == .active { model.tick() } }
        .alert("QuranPause", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .fullScreenCover(isPresented: Binding(get: { !completedWelcome }, set: { if !$0 { completedWelcome = true } })) {
            WelcomeView().appPresentation()
        }
        .sheet(item: $model.completedSession) { session in CompletionView(session: session).appPresentation() }
    }
    private func openNotificationDestinationIfReady() {
        guard phase == .active, let destination = model.prayers.takeNotificationDestination() else { return }
        switch destination {
        case .prayer:
            tab = 4
            Task { @MainActor in
                await Task.yield()
                if !model.prayers.playingAzan { model.prayers.toggleAzan() }
            }
        case .zikr:
            tab = 3
        }
    }
}
struct CompletionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var celebrated = false
    let session: FocusSession
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                // Two soft rings open outward once, like a breath released.
                ForEach(0..<2) { ring in
                    Circle().stroke(QT.gold.opacity(0.5), lineWidth: 1.5).frame(width: 96, height: 96)
                        .scaleEffect(celebrated && !reduceMotion ? 1.9 + Double(ring) * 0.5 : 0.8)
                        .opacity(celebrated ? 0 : 0.8)
                        .animation(.easeOut(duration: 1.4).delay(0.15 + Double(ring) * 0.2), value: celebrated)
                }
                Circle().fill(QT.sage).frame(width: 110, height: 110)
                    .scaleEffect(celebrated || reduceMotion ? 1 : 0.6)
                Image(systemName: "checkmark.seal.fill").font(.system(size: 58, weight: .light)).foregroundStyle(QT.green)
                    .symbolEffect(.bounce, value: celebrated)
                    .scaleEffect(celebrated || reduceMotion ? 1 : 0.4)
            }
            .frame(height: 124)
            .opacity(celebrated ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.62), value: celebrated)
            Group {
                Text("Time well spent.").font(QT.serif(36)).reveal(1)
                Text("You made \(Int(session.target / 60)) minutes of space for the Quran.").multilineTextAlignment(.center).foregroundStyle(QT.muted)
                    .fixedSize(horizontal: false, vertical: true).reveal(2)
                Text(LocalizedStringKey(model.state.activeSession != nil ? "Another scheduled session is waiting. Your selected apps remain locked until all sessions are complete." : session.isPractice ? "Practice complete. No apps were blocked." : "Your selected apps are now unlocked."))
                    .font(.subheadline).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).reveal(3)
                PrimaryButton(title: "Alhamdulillah", symbol: "checkmark") { dismiss() }.reveal(4)
            }
        }
        .onAppear { celebrated = true }
        .sensoryFeedback(.success, trigger: celebrated).padding(32).frame(maxWidth: .infinity, maxHeight: .infinity).background(QT.paper).presentationDetents([.fraction(0.62), .large])
    }
}
