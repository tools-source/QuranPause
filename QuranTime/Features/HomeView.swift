import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(QuranLibrary.self) private var library
    @Binding var selectedTab: Int
    @State private var showSettings = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How much of the current session is complete, 0-1.
    private var sessionProgress: Double {
        guard let session = model.state.activeSession, session.target > 0 else { return 0 }
        return min(1, max(0, 1 - session.remaining / session.target))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(spacing: 10) {
                    BrandMark(size: 38)
                    Text("QuranPause").font(.system(size: 21, weight: .semibold, design: .serif))
                    Spacer()
                    Button { showSettings = true } label: {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 18)).frame(width: 44, height: 44)
                            .background(QT.surface.opacity(0.8), in: Circle()).overlay(Circle().stroke(QT.line))
                    }.buttonStyle(.pressable).accessibilityLabel("Settings")
                }.foregroundStyle(QT.ink).reveal(0)
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: "A little less scrolling. A little more soul.")
                    Text("Make room\nfor the Quran.").font(QT.serif(43)).tracking(I18n.isArabic ? 0 : -1.3).lineSpacing(-4).foregroundStyle(QT.ink)
                    Text("Small moments. A deeper connection.").font(.system(size: 15)).foregroundStyle(QT.muted)
                }.reveal(1)
                focusCard.reveal(2)
                HStack(spacing: 0) {
                    stat(value: "\(model.todayMinutes)", label: "MINUTES TODAY", icon: "leaf")
                    Rectangle().fill(QT.line).frame(width: 1, height: 38)
                    stat(value: "\(model.todaySessions.count)", label: "SESSIONS COMPLETE", icon: "checkmark.circle")
                }.padding(.vertical, 5).reveal(3)
                if let surah = library.surahs.first(where: { $0.id == model.state.lastSurah }) {
                    VStack(alignment: .leading, spacing: 13) {
                        sectionHeading("Your next page", trailing: "THE HOLY QURAN")
                        NavigationLink { QuranPagesView(initialPage: model.state.lastPage) } label: {
                            Card {
                                HStack(spacing: 15) {
                                    Image(systemName: "book.pages").font(.system(size: 25, weight: .light)).foregroundStyle(QT.green).frame(width: 48, height: 54).background(QT.sage, in: RoundedRectangle(cornerRadius: 13))
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(surah.displayName).font(.system(size: 17, weight: .semibold, design: .serif)).foregroundStyle(QT.ink)
                                        Text(I18n.format("Page %lld", model.state.lastPage)).font(.system(size: 12)).foregroundStyle(QT.muted)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.up.right").foregroundStyle(QT.green)
                                }
                            }
                        }.buttonStyle(.pressable)
                    }.reveal(4)
                }
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        Text("Your daily rhythm").font(QT.serif(23)).foregroundStyle(QT.ink)
                        Spacer()
                        Button("Edit") { selectedTab = 2 }.font(.system(size: 13, weight: .semibold))
                    }
                    HStack(spacing: 10) {
                        ForEach(Array(model.upcomingLockTimes.prefix(3).enumerated()), id: \.element.id) { index, slot in
                            VStack(alignment: .leading, spacing: 13) {
                                Image(systemName: slot.hour < 12 ? "sunrise" : slot.hour < 18 ? "sun.max" : "moon.stars").font(.system(size: 21, weight: .light)).foregroundStyle(QT.gold)
                                Text(slot.date, style: .time).font(.system(size: 15, weight: .semibold)).foregroundStyle(QT.ink)
                                Text("SESSION \(index + 1)").font(.system(size: 9, weight: .bold)).tracking(I18n.isArabic ? 0 : 1).foregroundStyle(QT.muted)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(15).background(QT.surface.opacity(0.8), in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(QT.line))
                        }
                    }
                    Label(LocalizedStringKey(model.state.scheduleEnabled ? "Automatic daily locks are on" : "Your routine is saved. Turn on daily locks in Routine."), systemImage: model.state.scheduleEnabled ? "checkmark.circle" : "info.circle")
                        .font(.system(size: 11)).foregroundStyle(QT.muted)
                }.reveal(5)
                VStack(spacing: 14) {
                    Eyebrow(text: "A moment of remembrance")
                    Text("سُبْحَانَ اللَّهِ وَبِحَمْدِهِ").font(.system(size: 29)).foregroundStyle(QT.green)
                    Text("Glory and praise be to Allah.").font(.system(size: 13)).foregroundStyle(QT.muted)
                    Button { selectedTab = 3 } label: { Label("Make remembrance a habit", systemImage: "bell").font(.system(size: 12, weight: .medium)) }
                }.frame(maxWidth: .infinity).padding(24).background(QT.sage.opacity(0.5), in: RoundedRectangle(cornerRadius: 22)).reveal(6)
                Text("A mindful moment is a meaningful beginning.").font(QT.serif(13)).italic().foregroundStyle(QT.muted).frame(maxWidth: .infinity).padding(.bottom, 12)
            }.padding(.horizontal, 24).padding(.top, 14)
        }.background(QT.paper).toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) { SettingsView().appPresentation() }
    }
    private var focusCard: some View {
        VStack(spacing: 0) {
            HStack {
                Label(LocalizedStringKey(model.state.activeSession == nil ? "YOUR QURAN MOMENT" : model.isRunning ? "FOCUS IN PROGRESS" : "READY WHEN YOU ARE"), systemImage: "sparkle")
                    .font(.system(size: 10, weight: .semibold)).tracking(I18n.isArabic ? 0 : 1.5)
                    .contentTransition(.opacity).id(model.isRunning)
                Spacer()
                Text(LocalizedStringKey(AppModel.isSimulator ? "PRACTICE" : model.state.activeSession == nil ? "FOCUS" : model.canShield ? "APPS LOCKED" : "SESSION WAITING"))
                    .font(.system(size: 8, weight: .bold)).tracking(I18n.isArabic ? 0 : 1).padding(.horizontal, 9).padding(.vertical, 6).background(.white.opacity(0.10), in: Capsule())
            }.foregroundStyle(Color(hex: 0xE0E8D6))
            ZStack {
                if model.isEarningTime && !reduceMotion {
                    // A slow breath while time is being earned.
                    PhaseAnimator([false, true]) { inhale in
                        Circle().fill(QT.gold.opacity(0.14)).frame(width: 186, height: 186)
                            .scaleEffect(inhale ? 1.1 : 0.94).opacity(inhale ? 0.2 : 0.75)
                    } animation: { _ in .easeInOut(duration: 2.6) }
                    .transition(.opacity)
                }
                Circle().stroke(.white.opacity(0.08), lineWidth: 1).frame(width: 186, height: 186)
                Circle().stroke(.white.opacity(0.1), style: StrokeStyle(lineWidth: 3, lineCap: .round)).frame(width: 163, height: 163)
                Circle().trim(from: 0, to: sessionProgress).stroke(QT.gold, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 163, height: 163).rotationEffect(.degrees(-90))
                    .shadow(color: QT.gold.opacity(0.45), radius: 6)
                    .animation(.easeInOut(duration: 0.8), value: sessionProgress)
                VStack(spacing: 8) {
                    Image(systemName: model.isListening && model.isRunning ? "headphones" : "book").font(.system(size: 27, weight: .ultraLight)).foregroundStyle(Color(hex: 0xDFD3AC))
                        .contentTransition(.symbolEffect(.replace))
                    Text(model.remainingText).font(.system(size: 43, weight: .light, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                        .contentTransition(.numericText(countsDown: true)).animation(.snappy, value: model.remainingText)
                    Text(LocalizedStringKey(model.state.activeSession == nil ? "MINUTES OF INTENTION" : "REMAINING")).font(.system(size: 8, weight: .semibold)).tracking(I18n.isArabic ? 0 : 2).foregroundStyle(Color(hex: 0xCDD9C7))
                }
            }.frame(height: 209).animation(.easeInOut(duration: 0.6), value: model.isEarningTime)
            Text("Give your attention to what matters.").font(QT.serif(18)).foregroundStyle(Color(hex: 0xF2EFDF))
            Text(LocalizedStringKey(model.isRunning ? "Your timer pauses when you stop reading or listening." : "Pause the distractions. Open the Quran.")).font(.system(size: 11)).foregroundStyle(Color(hex: 0xB7CABC)).padding(.top, 8)
                .contentTransition(.opacity).animation(QT.spring, value: model.isRunning)
            Button {
                model.beginSession()
                if model.isRunning { selectedTab = 1 }
            } label: {
                HStack {
                    Image(systemName: model.isRunning ? "book" : "play.fill").font(.system(size: 12)).contentTransition(.symbolEffect(.replace))
                    Text(LocalizedStringKey(model.isRunning ? "Continue reading" : model.state.activeSession == nil ? "Begin Quran time" : "Resume Quran time")).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Image(systemName: "arrow.right")
                }.foregroundStyle(QT.forest).padding(17).background(Color(hex: 0xF2F0E4), in: RoundedRectangle(cornerRadius: 13))
            }.buttonStyle(.pressable).padding(.top, 23)
                .sensoryFeedback(.impact(weight: .medium), trigger: model.isRunning)
        }.padding(23).background {
            ZStack {
                RoundedRectangle(cornerRadius: 27).fill(QT.forest.gradient)
                GeometryReader { geometry in
                    Path { path in
                        for i in 0..<6 {
                            let x = CGFloat(i) * 70 - 70
                            path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x + geometry.size.height, y: geometry.size.height))
                        }
                    }.stroke(.white.opacity(0.025), lineWidth: 1)
                }.clipShape(RoundedRectangle(cornerRadius: 27))
            }
        }
    }
    private func stat(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 15, weight: .light)).foregroundStyle(QT.gold)
                Text(value).font(QT.serif(29)).foregroundStyle(QT.ink).contentTransition(.numericText()).animation(QT.spring, value: value)
            }
            Text(LocalizedStringKey(label)).font(.system(size: 8, weight: .semibold)).tracking(I18n.isArabic ? 0 : 1.1).foregroundStyle(QT.muted)
        }.frame(maxWidth: .infinity)
    }
    private func sectionHeading(_ title: String, trailing: String) -> some View {
        HStack { Text(LocalizedStringKey(title)).font(QT.serif(23)).foregroundStyle(QT.ink); Spacer(); Text(LocalizedStringKey(trailing)).font(.system(size: 8, weight: .semibold)).tracking(I18n.isArabic ? 0 : 1).foregroundStyle(QT.muted) }
    }
}
