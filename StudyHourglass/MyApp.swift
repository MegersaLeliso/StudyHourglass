import SwiftUI
import AppKit
import UserNotifications

@main
struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(panel: appDelegate.panel)
                .environment(appDelegate.model)
        } label: {
            MenuBarLabel(model: appDelegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Owns the timer model and the floating widget; runs the app as a menu-bar accessory.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let model = TimerModel()
    lazy var panel = FloatingPanelController(model: model)
    lazy var alarm = AlarmWindowController(model: model)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        FinishNotifier.requestAuthorization()
        model.onAlarmChange = { [weak self] active in
            guard let self else { return }
            active ? self.alarm.present() : self.alarm.dismiss()
        }
        panel.show()
    }

    /// Show the "Time's Up!" banner even when this app counts as frontmost.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

private struct MenuBarLabel: View {
    let model: TimerModel

    var body: some View {
        if model.alarmActive {
            Image(systemName: "alarm.fill")
            Text("Time's up")
        } else if model.phase == .running || model.phase == .paused {
            Image(systemName: model.phase == .running ? "hourglass" : "pause.circle")
            Text(model.remainingText)
        } else {
            Image(systemName: "hourglass")
        }
    }
}

/// Popover shown from the menu bar icon.
private struct MenuBarContent: View {
    @Environment(TimerModel.self) private var model
    let panel: FloatingPanelController
    @State private var customText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Study Hourglass").font(.headline)
                Spacer()
                Text(model.remainingText)
                    .font(.system(.title3, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button(model.phase == .running ? "Pause" : "Start") { model.toggle() }
                    .keyboardShortcut(.defaultAction)
                Button("Reset") { model.reset() }
                if model.alarmActive {
                    Button("Dismiss Alarm") { model.dismissAlarm() }
                }
            }

            Divider()

            Text("Duration").font(.subheadline).foregroundStyle(.secondary)
            HStack {
                ForEach(TimerModel.presets, id: \.self) { minutes in
                    Button("\(minutes)m") { model.setMinutes(Double(minutes)) }
                }
            }
            HStack {
                TextField("Minutes (90) or H:MM (1:30)", text: $customText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(applyCustom)
                Button("Set", action: applyCustom)
                    .disabled(TimerModel.parseMinutes(customText) == nil)
            }

            Divider()

            soundControls

            Divider()

            sizeControls

            Divider()

            HStack {
                Button("Show / Hide Widget") { panel.toggle() }
                Button("Dock Right") { panel.dock() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    /// Alarm sound mute toggle plus a one-strike preview.
    private var soundControls: some View {
        let chime = ChimePlayer.shared
        return HStack {
            Toggle("Alarm sound", isOn: Binding(get: { chime.soundEnabled },
                                                set: { chime.soundEnabled = $0 }))
            Spacer()
            Button("Test Sound") { chime.playTest() }
        }
    }

    /// Widget size: Compact/Normal/Large presets plus a continuous slider (aspect ratio fixed).
    private var sizeControls: some View {
        let layout = panel.layout
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Widget Size").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((layout.scale * 100).rounded()))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack {
                ForEach(WidgetLayout.presets, id: \.name) { preset in
                    Button(preset.name) { panel.setScale(preset.scale, anchor: .center) }
                }
            }
            Slider(value: Binding(get: { layout.scale },
                                  set: { panel.setScale($0, anchor: .center) }),
                   in: WidgetLayout.scaleRange) {
                EmptyView()
            } minimumValueLabel: {
                Image(systemName: "textformat.size.smaller")
            } maximumValueLabel: {
                Image(systemName: "textformat.size.larger")
            }
        }
    }

    private func applyCustom() {
        guard let minutes = TimerModel.parseMinutes(customText) else { return }
        model.setMinutes(minutes)
        customText = ""
    }
}
