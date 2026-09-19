import SwiftUI

struct QuranView: View {
    @Environment(QuranLibrary.self) private var library
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var filter = QuranFilter.all
    private var filtered: [Surah] {
        library.surahs.filter { surah in
            (search.isEmpty || "\(surah.id) \(surah.transliteration) \(surah.translation) \(surah.name)".localizedCaseInsensitiveContains(search)) &&
            (filter != .favorites || model.state.favoriteSurahs.contains(surah.id))
        }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                PageHeading(eyebrow: "Read. Reflect. Reconnect.", title: "The Holy Quran", subtitle: "All 114 surahs, always with you. Available offline.").reveal(0)
                if model.state.activeSession != nil { FocusBanner().reveal(1) }
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(QT.muted)
                    TextField("Find a surah", text: $search).autocorrectionDisabled()
                    if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("Clear search") }
                }.padding(16).background(QT.surface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(QT.line.opacity(0.7))).reveal(1)
                NavigationLink { QuranPagesView(initialPage: model.state.lastPage) } label: {
                    Card {
                        HStack(spacing: 14) {
                            Image(systemName: "book.pages").font(.title2).foregroundStyle(QT.gold)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Continue reading").font(.headline)
                                Text("604 pages · Continue at page \(model.state.lastPage)").font(.caption).foregroundStyle(QT.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.forward")
                        }.foregroundStyle(QT.green)
                    }
                }.buttonStyle(.pressable).reveal(2)
                Picker("Quran library", selection: $filter) {
                    ForEach(QuranFilter.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                }.pickerStyle(.segmented).padding(.vertical, 6).reveal(3)
                    .sensoryFeedback(.selection, trigger: filter)
                if let error = library.error { ContentUnavailableView("Unable to load Quran", systemImage: "book.closed", description: Text(error)) }
                else if filtered.isEmpty { ContentUnavailableView(LocalizedStringKey(filter == .favorites ? "No favorite surahs yet" : "No matching surahs"), systemImage: filter == .favorites ? "heart" : "magnifyingglass", description: Text(LocalizedStringKey(filter == .favorites ? "Tap a heart to keep a surah here." : "Try a name or surah number."))) }
                ForEach(filtered) { surah in
                    HStack(spacing: 10) {
                    NavigationLink {
                        QuranPagesView(initialPage: firstPage(of: surah.id))
                    } label: {
                        HStack(spacing: 15) {
                            ZStack { RoundedRectangle(cornerRadius: 10).stroke(QT.gold.opacity(0.4)).frame(width: 36, height: 36).rotationEffect(.degrees(45)); Text("\(surah.id)").font(.system(size: 12, weight: .medium)).foregroundStyle(QT.green) }.frame(width: 48, height: 48)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(surah.displayName).font(.system(size: 17, weight: .medium, design: .serif)).foregroundStyle(QT.ink)
                                Text(surah.descriptionLine).font(.system(size: 11)).foregroundStyle(QT.muted)
                            }
                            Spacer(minLength: 4)
                            if !I18n.isArabic { Text(surah.name).font(.system(size: 23)).foregroundStyle(QT.green) }
                        }.padding(.vertical, 10)
                    }.buttonStyle(.pressableRow)
                    SurahPlayButton(surahID: surah.id)
                    FavoriteSurahButton(surahID: surah.id)
                    }
                    Rectangle().fill(QT.line).frame(height: 1)
                }
            }.padding(24)
                .animation(QT.spring, value: filtered.map(\.id))
        }.background(QT.paper).navigationBarTitleDisplayMode(.inline)
    }
    private func firstPage(of surahID: Int) -> Int {
        library.pages.first(where: { page in page.verses.contains { $0.surah == surahID } })?.id ?? 1
    }
}

struct FocusBanner: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: model.isRunning ? "hourglass" : "pause.circle").foregroundStyle(QT.gold)
                .contentTransition(.symbolEffect(.replace)).symbolEffect(.pulse, isActive: model.isEarningTime)
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(AppModel.isSimulator ? "Practice session" : "Quran time")).font(.system(size: 13, weight: .semibold))
                Text(LocalizedStringKey(model.isRunning && model.isListening ? "Listening · the timer keeps running." : model.isEarningTime ? "Stay here. Let the world wait." : model.isRunning ? "Read or listen to continue the timer." : "Paused · your progress is saved")).font(.system(size: 10)).foregroundStyle(QT.muted)
            }
            Spacer()
            Text(model.remainingText).font(.system(size: 19, weight: .medium, design: .rounded)).monospacedDigit()
                .contentTransition(.numericText(countsDown: true)).animation(.snappy, value: model.remainingText)
            Button { model.isRunning ? model.pauseSession() : model.beginSession() } label: {
                Image(systemName: model.isRunning ? "pause.fill" : "play.fill").contentTransition(.symbolEffect(.replace))
                    .frame(width: 34, height: 34).background(QT.sage, in: Circle())
            }.buttonStyle(.pressable).accessibilityLabel(model.isRunning ? "Pause timer" : "Resume timer")
                .sensoryFeedback(.impact(weight: .light), trigger: model.isRunning)
        }.foregroundStyle(QT.green).padding(15).background(QT.surface, in: RoundedRectangle(cornerRadius: 17)).overlay(RoundedRectangle(cornerRadius: 17).stroke(model.isEarningTime ? QT.gold.opacity(0.5) : QT.line))
            .animation(QT.spring, value: model.isEarningTime)
    }
}

private enum QuranFilter: String, CaseIterable, Identifiable {
    case all = "All surahs", favorites = "Favorites"
    var id: String { rawValue }
}
/// Plays the surah with the reciter chosen in Settings, or pauses it.
struct SurahPlayButton: View {
    @Environment(AppModel.self) private var model
    let surahID: Int
    var body: some View {
        let player = model.recitation
        let isCurrent = player.isCurrent(surahID)
        Button { player.toggle(surah: surahID) } label: {
            ZStack {
                if isCurrent && player.isLoading { ProgressView().controlSize(.small).transition(.opacity) }
                else { Image(systemName: isCurrent && player.isPlaying ? "pause.circle.fill" : "play.circle").contentTransition(.symbolEffect(.replace)) }
            }
            .font(.system(size: 24)).frame(minWidth: 44, minHeight: 44)
            .foregroundStyle(isCurrent ? QT.gold : QT.green)
            .animation(QT.spring, value: player.isLoading)
        }.buttonStyle(.pressable)
            .sensoryFeedback(.impact(weight: .light), trigger: isCurrent && player.isPlaying)
            .accessibilityLabel(LocalizedStringKey(isCurrent && (player.isPlaying || player.isLoading) ? "Pause recitation" : "Play recitation"))
            .accessibilityValue(Text("Surah \(surahID)"))
    }
}

/// The recitation now playing, shown above the tab bar on every tab.
struct RecitationBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let player = model.recitation
        ZStack {
        if player.surah != nil {
            VStack(spacing: 0) {
                GeometryReader { proxy in
                    Capsule().fill(QT.gold).frame(width: proxy.size.width * min(1, player.duration > 0 ? player.elapsed / player.duration : 0))
                        .animation(.linear(duration: 1), value: player.elapsed)
                }.frame(height: 2).background(QT.line)
                HStack(spacing: 12) {
                    Image(systemName: "waveform").foregroundStyle(QT.gold).symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(player.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(QT.ink)
                        Text(player.reciter.map { "\($0.displayName) · \($0.styleName)" } ?? "").font(.system(size: 11)).foregroundStyle(QT.muted).lineLimit(1)
                    }
                    Spacer()
                    Text(Self.time(player.elapsed)).font(.system(size: 12)).monospacedDigit().foregroundStyle(QT.muted)
                    Button { player.toggleCurrent() } label: {
                        ZStack {
                            if player.isLoading { ProgressView().controlSize(.small) }
                            else { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").contentTransition(.symbolEffect(.replace)) }
                        }.frame(width: 38, height: 38).background(QT.sage, in: Circle())
                    }.buttonStyle(.pressable).accessibilityLabel(LocalizedStringKey(player.isPlaying || player.isLoading ? "Pause recitation" : "Play recitation"))
                    Button { player.stop() } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).frame(width: 32, height: 38) }
                        .buttonStyle(.pressable).accessibilityLabel("Stop recitation")
                }.foregroundStyle(QT.green).padding(.horizontal, 16).padding(.vertical, 10)
            }
            .background(QT.surface, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(QT.line))
            .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
            .padding(.horizontal, 14).padding(.bottom, 6)
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        }
        }.animation(QT.spring, value: player.surah)
    }
    private static func time(_ seconds: Double) -> String {
        let value = Int(max(0, seconds.isFinite ? seconds : 0))
        let text = value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%d:%02d", value / 60, value % 60)
        return I18n.isArabic ? text.map { $0.isNumber ? I18n.number(Int(String($0))!) : String($0) }.joined() : text
    }
}

struct FavoriteSurahButton: View {
    @Environment(AppModel.self) private var model
    let surahID: Int
    var showsLabel = false
    var title: String? = nil
    private var isFavorite: Bool { model.state.favoriteSurahs.contains(surahID) }
    var body: some View {
        Button { model.update { $0.toggleFavorite(surahID) } } label: {
            HStack(spacing: 8) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .contentTransition(.symbolEffect(.replace)).symbolEffect(.bounce, value: isFavorite)
                if let title {
                    Text(title)
                } else if showsLabel {
                    Text(LocalizedStringKey(isFavorite ? "Favorite surah" : "Add to favorites"))
                }
            }.font(.system(size: showsLabel ? 13 : 18)).frame(minWidth: 44, minHeight: 44)
                .foregroundStyle(isFavorite ? QT.gold : QT.muted)
        }.buttonStyle(.pressable)
            .sensoryFeedback(.selection, trigger: isFavorite)
            .accessibilityLabel(LocalizedStringKey(isFavorite ? "Remove favorite surah" : "Add favorite surah"))
            .accessibilityValue(Text("Surah \(surahID)"))
    }
}
