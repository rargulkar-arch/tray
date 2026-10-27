import SwiftUI

struct FriendsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showAdd = false
    @State private var showLabels = false

    var body: some View {
        NavigationStack {
            List {
                if !store.pendingRequests.isEmpty {
                    Section("Wants to be friends") {
                        ForEach(store.pendingRequests) { request in
                            HStack(spacing: 12) {
                                Avatar(emoji: request.emoji, size: 38)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(request.displayName).font(.body.weight(.medium))
                                    Text("@\(request.username)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Accept") {
                                    Task { await store.respondToRequest(request.friendshipId, accept: true) }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)

                                Button {
                                    Task { await store.respondToRequest(request.friendshipId, accept: false) }
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }

                Section {
                    if store.acceptedFriends.isEmpty {
                        EmptyState(icon: "person.2",
                                   title: "No friends yet",
                                   message: "Add someone by their number, or send them your link.")
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(store.acceptedFriends) { friend in
                            NavigationLink {
                                FriendDetailView(userID: friend.userId)
                            } label: {
                                FriendRow(friend: friend, presence: presence(for: friend))
                            }
                        }
                    }
                } header: {
                    if !store.acceptedFriends.isEmpty { Text("Friends") }
                }

                if !store.outgoing.isEmpty {
                    Section("Waiting on them") {
                        ForEach(store.outgoing) { friend in
                            HStack(spacing: 12) {
                                Avatar(emoji: friend.emoji, size: 34)
                                Text(friend.displayName)
                                Spacer()
                                Pill(text: "requested")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Friends")
            .refreshable { await store.refreshAll() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showLabels = true } label: { Image(systemName: "tag") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "person.badge.plus") }
                }
            }
            .sheet(isPresented: $showAdd) { AddFriendView() }
            .sheet(isPresented: $showLabels) { LabelsView() }
        }
    }

    private func presence(for friend: Friend) -> Presence? {
        store.feed.first { $0.userId == friend.userId }
    }
}

struct FriendRow: View {
    let friend: Friend
    let presence: Presence?

    var body: some View {
        HStack(spacing: 12) {
            Avatar(emoji: friend.emoji, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName).font(.body.weight(.medium))
                if let presence {
                    Text("\(presence.hallName) · \(sinceText(presence.startedAt))")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text("@\(friend.username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if friend.notifyOn {
                Image(systemName: "bell.fill").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

extension AppStore {
    var outgoing: [Friend] { friends.filter { $0.direction == .outgoing } }
}
