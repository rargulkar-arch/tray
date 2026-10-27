import SwiftUI

/// "Rohit is asking you to join them at The Eatery." Four taps to answer,
/// because the alternative is a text message you will forget to send.
struct InviteCard: View {
    @EnvironmentObject private var store: AppStore
    let invite: Invite

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Avatar(emoji: invite.otherEmoji, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(invite.otherName) wants to eat")
                        .font(.subheadline.weight(.semibold))
                    Text("at \(invite.hallName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                ForEach(InviteReply.allCases) { reply in
                    Button {
                        Task { await store.respond(to: invite.id, with: reply) }
                    } label: {
                        VStack(spacing: 3) {
                            Text(reply.emoji).font(.body)
                            Text(reply.label)
                                .font(.caption2.weight(.medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }
}
