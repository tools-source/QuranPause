import SwiftUI
import FamilyControls

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("appLanguage") private var language = AppLanguage.system.rawValue
    @AppStorage("appAppearance") private var appearance = AppAppearance.system.rawValue
    @State private var showPicker = false
    @State private var selection = FamilyActivitySelection()
    @State private var authorizing = false
    @AppStorage("reciterID") private var reciterID = Recitations.defaultReciterID
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) { BrandMark(size: 56); VStack(alignment: .leading, spacing: 5) { Text("QuranPause").font(QT.serif(25)); Text("Make room for what matters.").font(.caption).foregroundStyle(QT.muted) } }.padding(.vertical, 10)
                }
                Section("Make it yours") {
                    Picker("Language", selection: $language) {
                        ForEach(AppLanguage.allCases) { Text(LocalizedStringKey($0.label)).tag($0.rawValue) }
                    }
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { Text(LocalizedStringKey($0.label)).tag($0.rawValue) }
                    }
                }
                Section {
                    Picker("Reciter", selection: $reciterID) {
                        ForEach(Recitations.catalog) { reciter in
                            Text("\(reciter.displayName) · \(reciter.styleName)").tag(reciter.id)
                        }
                    }
                    .onChange(of: reciterID) { _, _ in model.recitation.reciterChanged() }
                } header: { Text("Recitation") } footer: {
                    Text("Tap play beside any surah to listen. Listening counts toward Quran time while the recitation is playing and audible, even with the screen locked. Recitations stream from Quran Foundation and need an internet connection.")
                }
                Section {
                    LabeledContent("Screen Time", value: I18n.text(AppModel.isSimulator ? "Simulator practice" : model.canShield ? "Connected" : "Not connected"))
                    Button(LocalizedStringKey(authorizing ? "Connecting…" : "Connect Screen Time")) {
                        authorizing = true
                        Task { await model.authorize(); authorizing = false }
                    }.disabled(authorizing || model.canShield)
                    Button { selection = model.state.selection; showPicker = true } label: {
                        HStack { Text("Choose apps & websites"); Spacer(); Text("\(model.state.selectionCount) selected").foregroundStyle(QT.muted) }
                    }.disabled(!model.canShield || model.state.activeSession != nil)
                } header: { Text("Protect your focus") } footer: {
                    Text(LocalizedStringKey(AppModel.isSimulator ? "This simulator can test reading, reminders, and the focus timer. App blocking and app selection require a physical iPhone." : "Choose distracting apps, categories, and websites. Keep QuranPause out of your selection. Selections stay on your device. Complete any active session before changing protected apps."))
                }
                Section("Deletion protection") {
                    Label(LocalizedStringKey(model.state.requiresLockdown && model.canShield ? "Deletion restriction requested" : "Active during lockdown"), systemImage: "lock.shield")
                    Text("During lockdown, iOS is asked to prevent deleting apps, including QuranPause. This applies to all apps until every waiting session is complete. Screen Time permission can still be revoked in Settings.").font(.caption).foregroundStyle(QT.muted)
                }
                if AppModel.isSimulator && model.state.activeSession != nil {
                    Section("Simulator practice") {
                        Button("Reset practice session") {
                            model.pauseSession()
                            model.update { $0.sessions.removeAll { $0.isPractice } }
                        }
                        Text("Clears simulator practice progress. Real iPhone commitments must be completed.").font(.caption).foregroundStyle(QT.muted)
                    }
                }
                Section {
                    Button("Open notification settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
                } header: { Text("Zikr notifications") } footer: { Text("Enable the reminders you want in the Zikr tab. Their text and delivery times are yours to choose.") }
                Section("How Quran time works") {
                    Label("Pick a session duration and daily lock times.", systemImage: "clock")
                    Label("Selected apps stay locked while a session is waiting.", systemImage: "lock.shield")
                    Label("The timer advances while you read on screen or listen to a recitation.", systemImage: "book")
                    Label("Finish every waiting session to unlock your apps.", systemImage: "lock.open")
                }.font(.subheadline)
                Section("Privacy & sources") {
                    Text("No account, ads, or analytics. Your routine, reading progress, and zikr are stored locally. The entire Quran is bundled for offline reading.").font(.subheadline).foregroundStyle(QT.muted)
                    Link("Quran text & translation: Quran JSON", destination: URL(string: "https://github.com/risan/quran-json")!)
                    Link("Text source: The Noble Qur’an Encyclopedia", destination: URL(string: "https://quranenc.com/en/home")!)
                    Link("Mushaf pages: King Fahd Glorious Quran Printing Complex", destination: URL(string: "https://qurancomplex.gov.sa/")!)
                    Link("Page and line layout: Quran Foundation", destination: URL(string: "https://api-docs.quran.com/legal/mushaf-fonts-and-images/")!)
                    Link("Recitations: Quran Foundation / QuranicAudio", destination: URL(string: "https://quranicaudio.com/")!)
                    Link("Ayah audio: EveryAyah", destination: URL(string: "https://everyayah.com/")!)
                    Link("Prayer calculations: Adhan by Batoul Apps (MIT)", destination: URL(string: "https://github.com/batoulapps/adhan-swift")!)
                    Link("Content license: CC BY-SA 4.0", destination: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!)
                    Text("Quran JSON by Risan Bagja Pradana. Bundled text is unmodified. The included Quran-LICENSE.txt contains the full license. English text is a translation of the Quran’s meanings.").font(.caption).foregroundStyle(QT.muted)
                }
                Section { Text("Individual Screen Time permission remains under your control in iPhone Settings. QuranPause is a personal focus tool.").font(.caption).foregroundStyle(QT.muted) }
            }.scrollContentBackground(.hidden).background(QT.paper).navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .familyActivityPicker(isPresented: $showPicker, selection: $selection)
                .onChange(of: showPicker) { old, shown in if old && !shown { model.update { $0.selection = selection } } }
                .alert("Screen Time", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                    Button("OK") { model.errorMessage = nil }
                } message: { Text(model.errorMessage ?? "") }
        }
    }
}
