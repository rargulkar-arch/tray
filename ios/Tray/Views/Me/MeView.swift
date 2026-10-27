import CoreLocation
import SwiftUI
import UIKit

struct MeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Avatar(emoji: store.me?.emoji ?? "🍜", size: 56)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.me?.displayName ?? "—").font(.title3.weight(.semibold))
                            Text("@\(store.me?.username ?? "")")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    Toggle("Invisible today", isOn: Binding(
                        get: { store.me?.isInvisible ?? false },
                        set: { on in
                            Task {
                                if on { await store.setInvisibleForToday() }
                                else  { await store.setVisible() }
                            }
                        }))
                } header: {
                    Text("Privacy")
                } footer: {
                    Text(store.me?.isInvisible == true
                         ? "Nobody can see where you're eating until midnight. Tray still checks you in quietly, so turning this off puts you straight back on the list."
                         : "Hides you from every friend until midnight. Friends aren't told, and they can't tell the difference between invisible and not eating.")
                }

                Section("Asks") {
                    if recentInvites.isEmpty {
                        Text("Nothing recent.").foregroundStyle(.secondary)
                    }
                    ForEach(recentInvites) { invite in
                        HStack(spacing: 12) {
                            Avatar(emoji: invite.otherEmoji, size: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(inviteLine(invite)).font(.subheadline)
                                Text(invite.hallName).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let reply = invite.reply {
                                Pill(text: "\(reply.emoji) \(reply.label)",
                                     tint: reply == .omw ? .green : .secondary)
                            } else if invite.hasExpired {
                                Pill(text: "expired")
                            } else {
                                Pill(text: "waiting")
                            }
                        }
                    }
                }

                Section("Automatic check-in") {
                    LabeledContent("Location access", value: permissionText)
                    LabeledContent("Halls watched", value: "\(store.location.monitoredCount)")
                    if store.location.authorization != .authorizedAlways {
                        Button("Fix location access") {
                            if store.location.authorization == .denied {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            } else {
                                store.location.requestPermission()
                            }
                        }
                    }
                }

                Section {
                    Button("Sign out", role: .destructive) { confirmSignOut = true }
                } footer: {
                    Text("Tray \(appVersion)")
                }
            }
            .navigationTitle("Me")
            .refreshable { await store.refreshAll() }
            .confirmationDialog("Sign out of Tray?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { Task { await store.signOut() } }
                Button("Cancel", role: .cancel) { }
            }
        }
    }

    private var recentInvites: [Invite] {
        store.invites.filter { !$0.isIncoming || $0.isAnswered }
    }

    private func inviteLine(_ invite: Invite) -> String {
        invite.isIncoming
            ? "\(invite.otherName) asked you"
            : "You asked \(invite.otherName)"
    }

    private var permissionText: String {
        switch store.location.authorization {
        case .authorizedAlways:    return "Always"
        case .authorizedWhenInUse: return "Only while open"
        case .denied:              return "Denied"
        case .restricted:          return "Restricted"
        default:                   return "Not asked"
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version ?? "0.1"
    }
}
