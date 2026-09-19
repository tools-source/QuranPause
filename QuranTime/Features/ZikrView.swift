import SwiftUI

struct ZikrView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: ZikrReminder?
    @State private var busy = false
    @State private var deleting: ZikrReminder?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(eyebrow: "Keep your heart connected", title: "A gentle reminder.", subtitle: "Let remembrance find you in the everyday. Your words, at your chosen time.").reveal(0)
                VStack(spacing: 16) {
                    Image(systemName: "sparkles").font(.system(size: 26, weight: .light)).foregroundStyle(QT.gold)
                    Text("فَاذْكُرُونِي أَذْكُرْكُمْ").font(.system(size: 32)).foregroundStyle(QT.green)
                    Text("“So remember Me; I will remember you.”").font(QT.serif(17)).foregroundStyle(QT.ink).multilineTextAlignment(.center)
                    Eyebrow(text: "Quran · Al-Baqarah 2:152")
                }.frame(maxWidth: .infinity).padding(26).background(QT.sage.opacity(0.65), in: RoundedRectangle(cornerRadius: 24)).reveal(1)
                HStack { Text("Your reminders").font(QT.serif(24)); Spacer(); Text("\(model.state.reminders.filter(\.enabled).count) ACTIVE").font(.system(size: 9, weight: .bold)).tracking(I18n.isArabic ? 0 : 1).foregroundStyle(QT.muted) }
                if model.state.reminders.isEmpty { ContentUnavailableView("Your words belong here", systemImage: "bell", description: Text("Add a zikr and a time to receive it each day.")) }
                ForEach(model.state.reminders) { reminder in
                    Card {
                        VStack(alignment: .leading, spacing: 15) {
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(reminder.displayTitle).font(.system(size: 16, weight: .semibold, design: .serif)).foregroundStyle(QT.ink)
                                    Text(reminder.scheduleDescription).font(.system(size: 11)).foregroundStyle(QT.muted)
                                }
                                Spacer()
                                Toggle("Enable \(reminder.title)", isOn: Binding(get: { reminder.enabled }, set: { enabled in
                                    var changed = reminder; changed.enabled = enabled; busy = true
                                    Task { _ = await model.saveReminder(changed); busy = false }
                                })).labelsHidden().disabled(busy)
                                    .sensoryFeedback(.selection, trigger: reminder.enabled)
                            }
                            Text(reminder.displayText).font(.system(size: 16)).lineSpacing(7).foregroundStyle(reminder.enabled ? QT.green : QT.muted).frame(maxWidth: .infinity, alignment: .leading)
                                .animation(QT.spring, value: reminder.enabled)
                            Divider()
                            HStack {
                                Button { editing = reminder } label: { Label("Edit reminder", systemImage: "pencil").font(.system(size: 12, weight: .medium)) }
                                Spacer()
                                Button(role: .destructive) { deleting = reminder } label: { Image(systemName: "trash").font(.system(size: 13)) }.accessibilityLabel("Delete \(reminder.title)")
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
                PrimaryButton(title: "Add your own zikr", symbol: "plus") {
                    if model.state.reminders.count < 50 { editing = ZikrReminder(title: "", text: "", enabled: true) }
                    else { model.errorMessage = I18n.text("You can save up to 50 reminders. Remove one to make room for another.") }
                }
                Text("Reminders appear as iPhone notifications. Focus modes and notification settings can silence them.").font(.system(size: 12)).foregroundStyle(QT.muted).lineSpacing(4)
            }.padding(24).padding(.bottom, 12)
                .animation(QT.spring, value: model.state.reminders.map(\.id))
        }.background(QT.paper).navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editing) { ReminderEditor(reminder: $0.editableCopy).appPresentation() }
            .confirmationDialog("Delete this zikr reminder?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete reminder", role: .destructive) { if let deleting { model.deleteReminder(deleting) }; deleting = nil }
            }
    }
}
struct ReminderEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var reminder: ZikrReminder
    @State private var saving = false
    private var valid: Bool { !reminder.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !reminder.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var body: some View {
        NavigationStack {
            Form {
                Section("Reminder title") { TextField("For example, Morning gratitude", text: $reminder.title).onChange(of: reminder.title) { _, value in reminder.title = String(value.prefix(80)) } }
                Section { TextEditor(text: $reminder.text).frame(minHeight: 140).onChange(of: reminder.text) { _, value in reminder.text = String(value.prefix(1000)) }.accessibilityLabel("Zikr notification text") }
                header: { Text("Your zikr") } footer: { Text("Write exactly what you want the notification to say, in any language.") }
                Section("When to remember") {
                    Picker("Repeat", selection: $reminder.cadence) {
                        ForEach(ScheduleCadence.allCases.filter { $0 != .custom }) { Text(LocalizedStringKey($0.title)).tag($0) }
                    }
                    if !reminder.cadence.isFrequent {
                    DatePicker("First reminder", selection: Binding(get: { reminder.date }, set: { reminder.hour = Calendar.current.component(.hour, from: $0); reminder.minute = Calendar.current.component(.minute, from: $0) }), displayedComponents: .hourAndMinute)
                    if reminder.cadence == .twiceDaily {
                        DatePicker("Second reminder", selection: Binding(get: { reminder.secondDate }, set: { reminder.secondHour = Calendar.current.component(.hour, from: $0); reminder.secondMinute = Calendar.current.component(.minute, from: $0) }), displayedComponents: .hourAndMinute)
                    }
                    } else {
                        Text(LocalizedStringKey(reminder.cadence == .hourly ? "Delivered at the start of every hour, all day." : "Delivered on the hour and half-hour, all day.")).font(.footnote).foregroundStyle(QT.muted)
                    }
                    Toggle("Send notification", isOn: $reminder.enabled)
                }
                Section("Notification preview") {
                    HStack(alignment: .top, spacing: 13) {
                        BrandMark(size: 38)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("QURANPAUSE").font(.caption2).foregroundStyle(QT.muted)
                            Text(reminder.title.isEmpty ? I18n.text("Your reminder") : reminder.title).font(.subheadline.bold())
                            Text(reminder.text.isEmpty ? I18n.text("Your zikr will appear here.") : reminder.text).font(.subheadline)
                        }
                    }.padding(.vertical, 6)
                }
            }.scrollContentBackground(.hidden).background(QT.paper).navigationTitle("A moment to remember").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(LocalizedStringKey(saving ? "Saving…" : "Save")) {
                            saving = true
                            reminder.title = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
                            reminder.text = reminder.text.trimmingCharacters(in: .whitespacesAndNewlines)
                            Task { if await model.saveReminder(reminder) { dismiss() }; saving = false }
                        }.disabled(!valid || saving)
                    }
                }
                .alert("Reminder not saved", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                    Button("OK") { model.errorMessage = nil }
                } message: { Text(model.errorMessage ?? "") }
        }.interactiveDismissDisabled(saving)
    }
}

extension ZikrReminder {
    var displayTitle: String { presetKey == nil ? title : I18n.text(title) }
    var displayText: String { presetKey == nil ? text : I18n.text(text) }
    var editableCopy: ZikrReminder {
        var copy = self
        copy.title = displayTitle; copy.text = displayText; copy.presetKey = nil
        return copy
    }
    var scheduleDescription: String {
        switch cadence {
        case .daily, .custom: return I18n.format("Every day at %@", I18n.time(date))
        case .twiceDaily: return I18n.format("Twice a day · %@ and %@", I18n.time(date), I18n.time(secondDate))
        case .hourly, .halfHourly: return I18n.text(cadence.title)
        }
    }
}
