import SwiftUI
import UIKit
import UserNotifications

enum Haptics {
    static var enabled: Bool {
        UserDefaults.standard.object(forKey: "omnie.haptics") as? Bool ?? true
    }

    static func tap() {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    static func attention() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

/// Local notifications for turns that finish while the app is in the
/// background. Nothing is sent through Apple's push service.
enum Notifier {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func turnFinished(agent: String, title: String?, text: String) {
        guard UserDefaults.standard.object(forKey: "omnie.notify") as? Bool ?? true else { return }
        let content = UNMutableNotificationContent()
        content.title = title ?? agent
        content.subtitle = title == nil ? "" : agent
        content.body = String(text.prefix(240))
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

extension Date {
    /// "2m", "3h", "Yesterday", "Mar 4".
    var shortRelative: String {
        let seconds = Date().timeIntervalSince(self)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        if Calendar.current.isDateInYesterday(self) { return "Yesterday" }
        if seconds < 7 * 86_400 { return formatted(.dateTime.weekday(.abbreviated)) }
        return formatted(.dateTime.month(.abbreviated).day())
    }
}

extension Int {
    /// 1234 → "1.2k".
    var compact: String {
        if self >= 1_000_000 { return String(format: "%.1fM", Double(self) / 1_000_000) }
        if self >= 1_000 { return String(format: "%.1fk", Double(self) / 1_000) }
        return String(self)
    }
}
