import SwiftUI

struct RoutineView: View {
    @Environment(AppModel.self) private var model
    @State private var minutes = 10
    @State private var slots: [LockTime] = []
    @State private var enabled = false
    @State private var cadence: ScheduleCadence = .custom
    @State private var saved = false
    @State private var showSettings = false
    @Namespace private var presets
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                PageHeading(eyebrow: "Protect what matters", title: "Find your rhythm.", subtitle: "Build a little Quran time into every day. We’ll hold the distractions for you.").reveal(0)
                Card {
                    VStack(alignment: .leading, spacing: 20) {
                        Label("Your focus commitment", systemImage: "hourglass").font(.system(size: 15, weight: .semibold)).foregroundStyle(QT.green)
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(minutes)").font(QT.serif(55)).foregroundStyle(QT.ink)
                                .contentTransition(.numericText(value: Double(minutes))).animation(.snappy, value: minutes)
                            Text("minutes per session").font(.system(size: 13)).foregroundStyle(QT.muted)
                            Spacer()
                        }
                        Slider(value: Binding(get: { Double(minutes) }, set: { minutes = Int($0); saved = false }), in: 1...120, step: 1).accessibilityLabel("Session duration")
                            .sensoryFeedback(.selection, trigger: minutes)
                        HStack(spacing: 9) {
                            ForEach([5, 10, 15, 30], id: \.self) { value in
                                Button { withAnimation(QT.spring) { minutes = value; saved = false } } label: {
                                    Text("\(value) min").font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 10)
                                        .background {
                                            Capsule().fill(QT.sage.opacity(0.5))
                                            if minutes == value { Capsule().fill(QT.forest).matchedGeometryEffect(id: "preset", in: presets) }
                                        }
                                        .foregroundStyle(minutes == value ? .white : QT.green)
                                }.buttonStyle(.pressable)
                            }
                        }
                        Text("Time counts while you read on screen or listen to an audible recitation. Leaving the reader or stopping the recitation pauses the timer.").font(.system(size: 12)).foregroundStyle(QT.muted).lineSpacing(4)
                    }
                }.reveal(1)
                Card {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Daily sessions").font(QT.serif(23))
                                Text("How often would you like to reconnect?").font(.system(size: 11)).foregroundStyle(QT.muted)
                            }
                            Spacer()
                        }
                        Picker("Repeat", selection: $cadence) {
                            ForEach(ScheduleCadence.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
                        }.onChange(of: cadence) { _, value in
                            if value == .daily { changeCount(1) }
                            if value == .twiceDaily { changeCount(2) }
                            saved = false
                        }
                        if cadence.isFrequent {
                            Label(LocalizedStringKey(cadence == .hourly ? "A new session at the start of every hour." : "A new session on the hour and half-hour."), systemImage: "repeat")
                                .font(.subheadline).foregroundStyle(QT.muted)
                            Text("Frequent routines run all day. Unfinished sessions remain queued.").font(.footnote).foregroundStyle(QT.muted)
                        }
                        if cadence == .custom {
                        Stepper(value: Binding(get: { slots.count }, set: { changeCount($0); saved = false }), in: 1...8) {
                            Text(I18n.format("%lld sessions a day", slots.count)).font(.system(size: 16, weight: .semibold)).foregroundStyle(QT.green)
                        }.accessibilityLabel("Daily lock frequency")
                        }
                        if !cadence.isFrequent {
                        ForEach($slots) { $slot in
                            HStack {
                                Image(systemName: slot.hour < 12 ? "sunrise" : slot.hour < 18 ? "sun.max" : "moon.stars").foregroundStyle(QT.gold).frame(width: 27)
                                DatePicker("Session \((slots.firstIndex(where: { $0.id == slot.id }) ?? 0) + 1)", selection: Binding(get: { slot.date }, set: { date in
                                    slot.hour = Calendar.current.component(.hour, from: date)
                                    slot.minute = Calendar.current.component(.minute, from: date)
                                    saved = false
                                }), displayedComponents: .hourAndMinute).font(.system(size: 14))
                            }
                            if slot.id != slots.last?.id { Divider() }
                        }
                        }
                    }.foregroundStyle(QT.ink)
                    .animation(QT.spring, value: cadence)
                    .animation(QT.spring, value: slots.count)
                }.reveal(2)
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle(isOn: $enabled) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Automatic daily locks").font(.system(size: 15, weight: .semibold))
                                Text(LocalizedStringKey(enabled ? "Make your intention a daily habit." : "Turn on when you’re ready.")).font(.system(size: 11)).foregroundStyle(QT.muted)
                            }
                        }.onChange(of: enabled) { _, _ in saved = false }
                            .sensoryFeedback(.selection, trigger: enabled)
                        Divider()
                        Button { showSettings = true } label: {
                            HStack { Label("Choose apps to lock", systemImage: "square.stack.3d.up"); Spacer(); Text("\(model.state.selectionCount)"); Image(systemName: "chevron.right") }.font(.system(size: 13))
                        }
                    }
                }.reveal(3)
                Label("Each scheduled lock needs its own completed session. Turning off the schedule stops future locks; it keeps any current commitment.", systemImage: "lock.shield")
                    .font(.system(size: 12)).foregroundStyle(QT.muted).lineSpacing(4)
                PrimaryButton(title: saved ? "Routine saved" : "Save my routine", symbol: saved ? "checkmark" : "arrow.right") {
                    let result = model.saveRoutine(minutes: minutes, slots: slots, enabled: enabled, cadence: cadence)
                    withAnimation(QT.spring) { saved = result }
                }
                .sensoryFeedback(.success, trigger: saved) { _, now in now }
                if saved {
                    Label("Your routine starts with the next scheduled time.", systemImage: "checkmark.circle.fill").font(.footnote).foregroundStyle(QT.green).accessibilityIdentifier("routineSaved")
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                }
            }.padding(24).padding(.bottom, 15)
        }.background(QT.paper).navigationBarTitleDisplayMode(.inline)
            .onAppear { minutes = model.state.durationMinutes; slots = model.state.lockTimes; enabled = model.state.scheduleEnabled; cadence = model.state.lockCadence }
            .sheet(isPresented: $showSettings) { SettingsView().appPresentation() }
    }
    private func changeCount(_ count: Int) {
        while slots.count < count {
            let occupied = Set(slots.map(\.minutes))
            let minute = stride(from: 360, to: 1440, by: 60).first { !occupied.contains($0) } ?? 0
            slots.append(LockTime(hour: minute / 60, minute: minute % 60))
        }
        if slots.count > count { slots.removeLast(slots.count - count) }
    }
}
