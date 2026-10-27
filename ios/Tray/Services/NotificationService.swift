import Foundation
import UserNotifications

/// Local notifications only.
///
/// Real push needs an APNs key, which needs a paid Apple developer account. The
/// server already knows how to answer "what happened since X" (`alerts_since`),
/// so when push is switched on the same query moves server-side and nothing
/// here changes except where it is called from. Until then Tray can only speak
/// up while iOS is giving it time: when it is open, when a geofence wakes it,
/// or during a background refresh window.
enum NotificationService {

    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func post(_ alert: Alert) {
        let content = UNMutableNotificationContent()
        content.sound = .default

        switch alert.kind {
        case "arrival":
            content.title = "\(alert.otherName) is eating"
            content.body = "At \(alert.hallName ?? "a dining hall")."
        case "invite":
            content.title = "\(alert.otherName) wants to eat"
            content.body = "They're at \(alert.hallName ?? "a dining hall"). Coming?"
        case "reply":
            content.title = alert.otherName
            content.body = replyText(alert.hallName)
        default:
            return
        }

        // Keyed by the row it came from, so the same event never lands twice.
        let request = UNNotificationRequest(identifier: "\(alert.kind):\(alert.ref)",
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private static func replyText(_ raw: String?) -> String {
        guard let raw, let reply = InviteReply(rawValue: raw) else { return "Replied." }
        switch reply {
        case .omw:        return "On the way."
        case .inABit:     return "Coming in a bit."
        case .alreadyAte: return "Already ate."
        case .cant:       return "Can't make it."
        }
    }
}
