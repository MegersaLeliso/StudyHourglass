import AppKit
import Observation
import UserNotifications

/// Alarm sound: a built-in macOS sound that loops every couple of seconds until stopped.
@Observable
final class ChimePlayer {
    static let shared = ChimePlayer()

    /// Crisp built-in system sound; falls back to "Hero" if unavailable.
    static let soundNames = ["Glass", "Hero"]
    /// Time between alarm strikes.
    static let interval: TimeInterval = 2.0

    private static let enabledKey = "soundEnabled"

    /// Mute/unmute (menu bar). Muting mid-alarm silences it immediately; the visual alert stays.
    var soundEnabled: Bool {
        didSet {
            UserDefaults.standard.set(soundEnabled, forKey: Self.enabledKey)
            if !soundEnabled { stopSounds() }
        }
    }

    @ObservationIgnored private var alarmTask: Task<Void, Never>?
    /// Keeps each NSSound alive until it has finished playing.
    @ObservationIgnored private var playing: [NSSound] = []

    private init() {
        soundEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    /// Strikes the alarm sound now and every `interval` seconds until `stopAlarm()`.
    func startAlarm() {
        stopAlarm()
        alarmTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.soundEnabled { self.strike() }
                try? await Task.sleep(for: .seconds(Self.interval))
            }
        }
    }

    func stopAlarm() {
        alarmTask?.cancel()
        alarmTask = nil
        stopSounds()
    }

    /// One strike, for the menu bar's "Test Sound" (plays even when muted).
    func playTest() {
        strike()
    }

    private func strike() {
        playing.removeAll { !$0.isPlaying }
        // A fresh copy per strike: a single NSSound instance can't restart while playing.
        let sound = Self.soundNames.lazy.compactMap { NSSound(named: $0)?.copy() as? NSSound }.first
        guard let sound else { NSSound.beep(); return }
        playing.append(sound)
        sound.play()
    }

    private func stopSounds() {
        playing.forEach { $0.stop() }
        playing.removeAll()
    }
}

/// macOS banner notification for when the countdown reaches 00:00 (kept in Notification
/// Center as a record; the looping alarm provides the sound).
enum FinishNotifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post() {
        let content = UNMutableNotificationContent()
        content.title = "Time's Up!"
        content.body = "Your study session has finished."
        let request = UNNotificationRequest(identifier: "studyhourglass.finished", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
