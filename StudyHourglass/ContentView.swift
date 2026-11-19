import SwiftUI

private enum AlarmColors {
    static let amber = Color(red: 1.0, green: 0.70, blue: 0.16)
    static let red = Color(red: 0.95, green: 0.22, blue: 0.18)
}

/// The floating widget: a compact numbers-only timer pill. Hovering reveals a small control
/// bar attached directly beneath it. All sizes come from `WidgetLayout` (no `scaleEffect`),
/// so text re-renders crisply at every size.
struct ContentView: View {
    @Environment(TimerModel.self) private var model
    @Environment(WidgetLayout.self) private var layout
    @State private var hovering = false
    @State private var editingCustom = false
    @State private var customText = ""
    @FocusState private var fieldFocused: Bool

    private var s: CGFloat { layout.scale }

    var body: some View {
        VStack(spacing: layout.controlsGap) {
            pill

            if hovering || editingCustom {
                controls
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        // Near-invisible backing (pill + gap + controls only) keeps the hover region
        // continuous; the rest of the window stays fully transparent and click-through.
        .background(Color.black.opacity(0.01).padding(-2))
        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(.easeInOut(duration: 0.18)) { hovering = inside }
        }
        .padding(.top, layout.pillTop)
        .frame(width: layout.size.width, height: layout.size.height, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Pill

    private var pill: some View {
        let alarm = model.alarmActive
        let rect = layout.pillRect(hours: model.showsHours)
        let shape = RoundedRectangle(cornerRadius: layout.pillCorner, style: .continuous)

        return TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !alarm)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pulse = alarm ? CGFloat(sin(t * 2 * .pi / 0.9) + 1) / 2 : 0

            Text(model.remainingText)
                .font(.system(size: layout.digitFont, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(alarm ? 1 : 0.95))
                .lineLimit(1)
                .fixedSize()
                .frame(width: rect.width, height: rect.height)
                .background {
                    ZStack {
                        shape.fill(.ultraThinMaterial)
                        shape.fill(Color.black.opacity(0.82))
                        if alarm {
                            // Bright red/amber flash, pulsing until dismissed.
                            shape.fill(LinearGradient(colors: [AlarmColors.red, AlarmColors.amber],
                                                      startPoint: .leading, endPoint: .trailing))
                                .opacity(0.45 + 0.55 * pulse)
                        }
                    }
                }
                .overlay(
                    shape.strokeBorder(alarm ? AlarmColors.amber.opacity(0.6 + 0.4 * pulse) : .white.opacity(0.18),
                                       lineWidth: alarm ? max(1.5, 2 * s) : 1)
                )
                .shadow(color: alarm ? AlarmColors.red.opacity(0.85 * pulse) : .clear,
                        radius: alarm ? 3 * s + 5 * s * pulse : 0)
                .overlay(alignment: .bottomTrailing) {
                    if hovering && !alarm { resizeGrip.transition(.opacity) }
                }
                .accessibilityLabel(alarm ? "Time's up" : "\(model.remainingText) remaining")
        }
    }

    /// Subtle corner grip; the drag itself is handled by `DraggableHostingView`, using
    /// `layout.gripRect` (the same corner) so it coexists with window dragging.
    private var resizeGrip: some View {
        Canvas { ctx, size in
            for i in 1...2 {
                let d = size.width * CGFloat(i) / 2
                var line = Path()
                line.move(to: CGPoint(x: size.width - d, y: size.height))
                line.addLine(to: CGPoint(x: size.width, y: size.height - d))
                ctx.stroke(line, with: .color(.white.opacity(0.45)),
                           style: StrokeStyle(lineWidth: max(1, 1.1 * s), lineCap: .round))
            }
        }
        .frame(width: max(5, 7 * s), height: max(5, 7 * s))
        .padding(max(3, 5 * s))
        .frame(width: layout.gripSide, height: layout.gripSide, alignment: .bottomTrailing)
        .allowsHitTesting(false)
    }

    // MARK: Controls

    private var controls: some View {
        let side = layout.buttonSide
        return HStack(spacing: 6 * s) {
            if editingCustom {
                TextField("1:30 or 90", text: $customText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: max(10, 12 * s)))
                    .frame(width: max(60, 78 * s))
                    .focused($fieldFocused)
                    .onSubmit(applyCustom)
                iconButton("checkmark", help: "Set duration (minutes or H:MM)", side: side, action: applyCustom)
                iconButton("xmark", help: "Cancel", side: side) { editingCustom = false }
            } else {
                iconButton(model.phase == .running ? "pause.fill" : "play.fill",
                           help: model.phase == .running ? "Pause" : "Start",
                           side: side, prominent: true) { model.toggle() }
                iconButton("arrow.counterclockwise", help: "Reset", side: side) { model.reset() }
                durationMenu(side: side)
            }
        }
        .padding(.horizontal, 6 * s)
        .padding(.vertical, 4 * s)
        .background(Capsule().fill(Color.black.opacity(0.6)))
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
    }

    private func durationMenu(side: CGFloat) -> some View {
        Menu {
            ForEach(TimerModel.presets, id: \.self) { minutes in
                Button(minutes >= 60 ? "\(minutes / 60) hr" : "\(minutes) min") { model.setMinutes(Double(minutes)) }
            }
            Divider()
            Button("Custom…") {
                customText = ""
                editingCustom = true
                fieldFocused = true
            }
        } label: {
            Image(systemName: "timer")
                .font(.system(size: side * 0.46, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: side, height: side)
                .background(Circle().fill(.white.opacity(0.14)))
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .help("Duration")
    }

    private func iconButton(_ symbol: String, help: String, side: CGFloat, prominent: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: side * (prominent ? 0.42 : 0.46), weight: .semibold))
                .foregroundStyle(prominent ? Color.black.opacity(0.85) : .white)
                .frame(width: side, height: side)
                .background(Circle().fill(prominent ? AnyShapeStyle(AlarmColors.amber)
                                                    : AnyShapeStyle(.white.opacity(0.14))))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func applyCustom() {
        guard let minutes = TimerModel.parseMinutes(customText) else { NSSound.beep(); return }
        model.setMinutes(minutes)
        editingCustom = false
    }
}

// MARK: - Time's Up card

/// Content of the centered alert window shown at 00:00.
struct AlarmView: View {
    @Environment(TimerModel.self) private var model

    var body: some View {
        let card = RoundedRectangle(cornerRadius: 24, style: .continuous)

        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pulse = CGFloat(sin(t * 2 * .pi / 0.9) + 1) / 2

            VStack(spacing: 14) {
                Image(systemName: "alarm.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(AlarmColors.amber)
                    .scaleEffect(1 + 0.08 * pulse)

                Text("Time's Up!")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                Text("Your \(model.durationDescription) study session is complete.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button { model.restart() } label: {
                        Text("Restart")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 120, height: 42)
                            .background(Capsule().fill(.white.opacity(0.14)))
                            .overlay(Capsule().strokeBorder(.white.opacity(0.25)))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("r", modifiers: [])

                    Button { model.dismissAlarm() } label: {
                        Text("Dismiss")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.black.opacity(0.85))
                            .frame(width: 170, height: 42)
                            .background(Capsule().fill(LinearGradient(
                                colors: [AlarmColors.amber, AlarmColors.red.opacity(0.9)],
                                startPoint: .leading, endPoint: .trailing)))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(card.fill(Color.black.opacity(0.85)))
            .background(.ultraThinMaterial, in: card)
            .overlay(card.strokeBorder(AlarmColors.amber.opacity(0.55 + 0.45 * pulse), lineWidth: 2))
            .padding(6)
        }
        .environment(\.colorScheme, .dark)
        .onExitCommand { model.dismissAlarm() }   // Esc
    }
}

#Preview {
    ContentView()
        .environment(TimerModel())
        .environment(WidgetLayout())
}
