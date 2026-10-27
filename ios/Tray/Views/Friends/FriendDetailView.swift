import SwiftUI

struct FriendDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let userID: String

    @State private var confirmRemove = false

    var body: some View {
        List {
            if let friend {
                Section {
                    HStack(spacing: 14) {
                        Avatar(emoji: friend.emoji, size: 56)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(friend.displayName).font(.title3.weight(.semibold))
                            Text("@\(friend.username)").font(.subheadline).foregroundStyle(.secondary)
                            if let presence {
                                Text("\(presence.hallName) · \(sinceText(presence.startedAt))")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    Button {
                        Task { await store.invite(userID) }
                    } label: {
                        Label(inviteLabel, systemImage: "hand.wave")
                    }
                    .disabled(store.myCheckIn == nil)
                } footer: {
                    Text(store.myCheckIn == nil
                         ? "You can ask someone to join you once you're at a dining hall."
                         : "Sends them a notification with four ways to answer.")
                }

                Section {
                    Toggle("Tell me when they're eating", isOn: Binding(
                        get: { friend.notifyOn },
                        set: { on in Task { await store.setNotify(userID, on: on) } }))
                } footer: {
                    Text("Off by default. Tray never pings you just because somebody walked into a hall.")
                }

                if !store.labels.isEmpty {
                    Section("Groups") {
                        ForEach(store.labels) { label in
                            Button {
                                let isMember = friend.labelIds.contains(label.id)
                                Task { await store.setLabel(label.id, on: userID, member: !isMember) }
                            } label: {
                                HStack {
                                    Circle()
                                        .fill(Color.label(label.color))
                                        .frame(width: 10, height: 10)
                                    Text(label.name).foregroundStyle(.primary)
                                    Spacer()
                                    if friend.labelIds.contains(label.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    Button("Remove friend", role: .destructive) { confirmRemove = true }
                }
            } else {
                EmptyState(icon: "person.slash", title: "Not a friend", message: "You aren't connected anymore.")
            }
        }
        .navigationTitle(friend?.displayName ?? "Friend")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove this friend?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                Task {
                    await store.unfriend(userID)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You'll both stop seeing each other's meals.")
        }
    }

    private var friend: Friend? {
        store.friends.first { $0.userId == userID && $0.direction == .friend }
    }

    private var presence: Presence? {
        store.feed.first { $0.userId == userID }
    }

    private var inviteLabel: String {
        if let hall = store.myCheckIn?.hallName {
            return "Ask them to join you at \(hall)"
        }
        return "Ask them to join you"
    }
}
