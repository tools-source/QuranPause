import SwiftUI
import UserNotifications

struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("completedWelcome") private var completedWelcome = false
    @AppStorage("welcomeStep") private var step = 0
    @AppStorage("appLanguage") private var language = AppLanguage.system.rawValue
    @AppStorage("appAppearance") private var appearance = AppAppearance.system.rawValue
    @State private var requesting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private func advance() { withAnimation(QT.spring) { step = 1 } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    BrandMark(size: 58).reveal(0)
                    Spacer()
                    Menu {
                        Picker("Language", selection: $language) {
                            ForEach(AppLanguage.allCases) { Text(LocalizedStringKey($0.label)).tag($0.rawValue) }
                        }
                        Picker("Appearance", selection: $appearance) {
                            ForEach(AppAppearance.allCases) { Text(LocalizedStringKey($0.label)).tag($0.rawValue) }
                        }
                    } label: { Label("Language & appearance", systemImage: "globe").font(.caption) }
                }
                PageHeading(eyebrow: "Welcome to QuranPause", title: "A little time.\nA deeper connection.", subtitle: "Let’s make space for the Quran and remembrance in your day.").reveal(1)
                HStack(spacing: 8) {
                    Capsule().fill(step == 0 ? QT.green : QT.sage)
                    Capsule().fill(step == 1 ? QT.green : QT.sage)
                }.frame(height: 4).animation(QT.spring, value: step).reveal(2)
                Card {
                    VStack(alignment: .leading, spacing: 20) {
                        Image(systemName: step == 0 ? "lock.shield" : "bell.badge").font(.system(size: 45, weight: .light)).foregroundStyle(QT.gold)
                            .symbolEffect(.bounce, value: step)
                        Text(LocalizedStringKey(step == 0 ? "Protect your Quran time" : "A gentle nudge to remember")).font(QT.serif(29)).foregroundStyle(QT.ink)
                        Text(LocalizedStringKey(step == 0 ? "Allow Screen Time so QuranPause can lock the apps you choose until you complete your session. Your selections stay private." : "Allow notifications to receive the zikr you choose, at the times you choose. You can customize every reminder."))
                            .font(.body).foregroundStyle(QT.muted).lineSpacing(5)
                        if AppModel.isSimulator && step == 0 {
                            Label("Screen Time access requires an iPhone. This simulator offers practice sessions.", systemImage: "iphone").font(.footnote).foregroundStyle(QT.muted)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(step)
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                .reveal(3)
                PrimaryButton(title: requesting ? "Requesting permission…" : step == 0 ? (AppModel.isSimulator ? "Continue with practice" : "Allow Screen Time") : "Allow notifications", symbol: step == 0 ? "lock.shield" : "bell") {
                    requesting = true
                    Task {
                        if step == 0 {
                            if !AppModel.isSimulator { await model.authorize() }
                            advance()
                        } else {
                            await model.requestNotifications()
                            completedWelcome = true
                        }
                        requesting = false
                    }
                }.disabled(requesting).reveal(4)
                Button(LocalizedStringKey(step == 0 ? "Not now" : "Continue without notifications")) {
                    if step == 0 { advance() } else { completedWelcome = true }
                }.frame(maxWidth: .infinity).font(.subheadline).disabled(requesting)
                Text("You’re in control. You can change permissions at any time in Settings.").font(.footnote).foregroundStyle(QT.muted).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }.padding(28).padding(.vertical, 24)
        }.background(QT.paper).interactiveDismissDisabled()
            .alert("QuranPause", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK") { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
    }
}
