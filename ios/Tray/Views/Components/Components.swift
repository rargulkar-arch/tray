import SwiftUI

/// "here 12 min" / "here 1h 20m" — the only number in the app, so it should
/// read like something a person would say out loud.
func sinceText(_ date: Date) -> String {
    let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
    if minutes < 1 { return "just sat down" }
    if minutes < 60 { return "here \(minutes) min" }
    let hours = minutes / 60
    let rest = minutes % 60
    return rest == 0 ? "here \(hours)h" : "here \(hours)h \(rest)m"
}

struct Avatar: View {
    let emoji: String
    var size: CGFloat = 44

    var body: some View {
        Text(emoji)
            .font(.system(size: size * 0.5))
            .frame(width: size, height: size)
            .background(Color.accentColor.opacity(0.14), in: Circle())
    }
}

struct Pill: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(tint)
            .background(tint.opacity(0.13), in: Capsule())
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 28)
    }
}

/// Bucket names come from the database so that the thresholds live in one place.
func busynessTint(_ bucket: String) -> Color {
    switch bucket {
    case "packed": return .red
    case "busy":   return .orange
    case "some":   return .yellow
    case "a few":  return .green
    default:       return .secondary
    }
}

extension Color {
    /// Label colours, stored as names so the database stays readable.
    static func label(_ name: String) -> Color {
        switch name {
        case "red":    return .red
        case "orange": return .orange
        case "green":  return .green
        case "purple": return .purple
        case "pink":   return .pink
        case "teal":   return .teal
        default:       return .blue
        }
    }

    static let labelChoices = ["blue", "green", "orange", "red", "purple", "pink", "teal"]
}
