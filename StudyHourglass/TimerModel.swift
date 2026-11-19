import Foundation
import Observation

/// Countdown state. Elapsed time is derived from wall-clock dates, so the sand
/// animation can sample `progress(at:)` at any frame rate without drift.
@Observable
final class TimerModel {
    enum Phase { case idle, running, paused, finished }

    static let presets = [1, 25, 30, 60]

    private(set) var phase: Phase = .idle
    private(set) var duration: TimeInterval = 25 * 60
    private(set) var remainingSeconds: Int = 25 * 60
    /// True from 00:00 until the user dismisses, restarts or resets: drives the looping
    /// alarm sound, the centered alert window and the flashing pill.
    private(set) var alarmActive = false

    /// Called with `true` when the alarm starts and `false` when it's cleared.
    @ObservationIgnored var onAlarmChange: ((Bool) -> Void)?

    private var accumulated: TimeInterval = 0
    private var runStart: Date?
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    // MARK: Queries

    func elapsed(at date: Date = .now) -> TimeInterval {
        var total = accumulated
        if let runStart { total += date.timeIntervalSince(runStart) }
        return min(max(total, 0), duration)
    }

    /// 0 = all sand on top, 1 = all sand on the bottom.
    func progress(at date: Date = .now) -> Double {
        duration > 0 ? elapsed(at: date) / duration : 1
    }

    // MARK: Actions

    func setMinutes(_ minutes: Double) {
        reset()
        duration = max(1, (minutes * 60).rounded())
        updateRemaining()
    }

    func start() {
        if phase == .finished { reset() }
        dismissAlarm()
        guard phase != .running else { return }
        runStart = .now
        phase = .running
        startTicking()
    }

    func pause() {
        guard phase == .running else { return }
        accumulated = elapsed()
        runStart = nil
        phase = .paused
        stopTicking()
        updateRemaining()
    }

    func toggle() {
        phase == .running ? pause() : start()
    }

    func reset() {
        dismissAlarm()
        stopTicking()
        accumulated = 0
        runStart = nil
        phase = .idle
        updateRemaining()
    }

    /// Silences the alarm and closes the alert; the timer stays at 00:00.
    func dismissAlarm() {
        guard alarmActive else { return }
        alarmActive = false
        ChimePlayer.shared.stopAlarm()
        onAlarmChange?(false)
    }

    /// Same duration again from the top.
    func restart() {
        reset()
        start()
    }

    // MARK: Ticking

    private func startTicking() {
        stopTicking()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    private func tick() {
        updateRemaining()
        if elapsed() >= duration { finish() }
    }

    private func finish() {
        stopTicking()
        accumulated = duration
        runStart = nil
        phase = .finished
        updateRemaining()
        alarmActive = true
        ChimePlayer.shared.startAlarm()
        FinishNotifier.post()
        onAlarmChange?(true)
    }

    private func updateRemaining() {
        let value = Int((duration - elapsed()).rounded(.up))
        if value != remainingSeconds { remainingSeconds = value }
    }

    // MARK: Helpers

    var showsHours: Bool { duration >= 3600 }

    /// Human-readable session length, e.g. "25-minute" or "1 h 5 min".
    var durationDescription: String {
        let total = Int(duration.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return m > 0 ? "\(h) h \(m) min" : "\(h)-hour" }
        if m > 0 { return s > 0 ? "\(m) min \(s) s" : "\(m)-minute" }
        return "\(s)-second"
    }

    /// Remaining time formatted for display. Timers of an hour or more keep the
    /// HH:MM:SS layout for the whole countdown so the clock doesn't change width.
    var remainingText: String {
        Self.format(remainingSeconds, showHours: showsHours)
    }

    /// `HH:MM:SS` when `showHours` (default: when `seconds` is an hour or more), else `MM:SS`.
    static func format(_ seconds: Int, showHours: Bool? = nil) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if showHours ?? (h > 0) {
            return String(format: "%02d:%02d:%02d", h, m, sec)
        }
        return String(format: "%02d:%02d", s / 60, sec)
    }

    static let maxMinutes: Double = 24 * 60

    /// Accepts total minutes ("45", "12.5", "90 min") or H:MM ("1:05");
    /// returns minutes in (0, 1440].
    static func parseMinutes(_ text: String) -> Double? {
        let cleaned = text.lowercased()
            .replacingOccurrences(of: "min", with: "")
            .trimmingCharacters(in: .whitespaces)
        let minutes: Double
        if cleaned.contains(":") {
            let parts = cleaned.split(separator: ":", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[1].count == 2,
                  let h = Int(parts[0]), let m = Int(parts[1]),
                  h >= 0, (0..<60).contains(m) else { return nil }
            minutes = Double(h * 60 + m)
        } else {
            guard let value = Double(cleaned) else { return nil }
            minutes = value
        }
        guard minutes > 0, minutes <= maxMinutes else { return nil }
        return minutes
    }
}
