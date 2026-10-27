import CoreLocation
import SwiftUI
import UIKit

struct NowView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedLabel: String?
    @State private var showHalls = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16, pinnedViews: []) {
                    if !store.incomingInvites.isEmpty {
                        ForEach(store.incomingInvites) { invite in
                            InviteCard(invite: invite)
                        }
                    }

                    LocationPermissionBanner()

                    MyStatusCard()

                    if !store.labels.isEmpty {
                        LabelFilterRow(selected: $selectedLabel)
                    }

                    if visibleGroups.isEmpty {
                        EmptyState(
                            icon: "fork.knife.circle",
                            title: noneTitle,
                            message: noneMessage)
                    } else {
                        ForEach(visibleGroups, id: \.hall.id) { group in
                            HallGroupCard(hall: group.hall, people: group.people)
                        }
                    }

                    Button {
                        showHalls = true
                    } label: {
                        Label("How busy is each hall", systemImage: "chart.bar.fill")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .refreshable { await store.refreshAll() }
            .navigationTitle("Eating now")
            .sheet(isPresented: $showHalls) { HallsSheet() }
        }
    }

    /// Friends currently eating, narrowed to one group if a label is selected.
    private var visibleGroups: [(hall: DiningHall, people: [Presence])] {
        guard let selectedLabel else { return store.feedByHall }
        return store.feedByHall.compactMap { group in
            let people = group.people.filter { $0.labelIds.contains(selectedLabel) }
            return people.isEmpty ? nil : (group.hall, people)
        }
    }

    private var noneTitle: String {
        selectedLabel == nil ? "Nobody's eating" : "Nobody from this group"
    }

    private var noneMessage: String {
        store.acceptedFriends.isEmpty
            ? "Add a few friends and they'll show up here the moment they walk into a dining hall."
            : "You'll see your friends here as soon as one of them walks into a dining hall."
    }
}

// MARK: - Your own status

struct MyStatusCard: View {
    @EnvironmentObject private var store: AppStore
    @State private var showPicker = false

    var body: some View {
        VStack(spacing: 0) {
            if let mine = store.myCheckIn {
                HStack(spacing: 12) {
                    Avatar(emoji: store.me?.emoji ?? "🍜", size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You're at \(mine.hallName)").font(.subheadline.weight(.semibold))
                        Text(sinceText(mine.startedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Leave") {
                        Task { await store.checkOut() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                HStack(spacing: 12) {
                    Avatar(emoji: store.me?.emoji ?? "🍜", size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.me?.isInvisible == true ? "You're invisible today" : "You're not at a hall")
                            .font(.subheadline.weight(.semibold))
                        Text(store.me?.isInvisible == true
                             ? "Friends can't see where you eat until tomorrow."
                             : "Tray will check you in on its own.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("I'm here") { showPicker = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
        .confirmationDialog("Which hall?", isPresented: $showPicker, titleVisibility: .visible) {
            ForEach(store.halls) { hall in
                Button(hall.name) {
                    Task { await store.checkIn(hallID: hall.id, source: "manual") }
                }
            }
            Button("Cancel", role: .cancel) { }
        }
    }
}

// MARK: - A hall with friends in it

struct HallGroupCard: View {
    @EnvironmentObject private var store: AppStore
    let hall: DiningHall
    let people: [Presence]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(hall.name).font(.headline)
                    if let building = hall.building {
                        Text(building).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Pill(text: "\(people.count)", tint: .accentColor)
            }
            .padding(.bottom, 10)

            ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                if index > 0 { Divider().padding(.leading, 56) }
                PersonRow(person: person)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct PersonRow: View {
    @EnvironmentObject private var store: AppStore
    let person: Presence

    var body: some View {
        NavigationLink {
            FriendDetailView(userID: person.userId)
        } label: {
            HStack(spacing: 12) {
                Avatar(emoji: person.emoji)
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.displayName).font(.body.weight(.medium))
                    Text(sinceText(person.startedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if person.notifyOn {
                    Image(systemName: "bell.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Filtering by label

struct LabelFilterRow: View {
    @EnvironmentObject private var store: AppStore
    @Binding var selected: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "Everyone", tint: .secondary, isOn: selected == nil) { selected = nil }
                ForEach(store.labels) { label in
                    chip(title: label.name,
                         tint: .label(label.color),
                         isOn: selected == label.id) {
                        selected = selected == label.id ? nil : label.id
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func chip(title: String, tint: Color, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .foregroundStyle(isOn ? .white : tint)
                .background(isOn ? tint : tint.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Permission nudge

struct LocationPermissionBanner: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        if store.location.authorization == .authorizedAlways {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(message).font(.caption).foregroundStyle(.secondary)
                Button(buttonTitle) {
                    if store.location.authorization == .denied {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } else {
                        store.location.requestPermission()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var title: String {
        store.location.authorization == .denied
            ? "Tray can't see dining halls"
            : "Turn on automatic check-ins"
    }

    private var message: String {
        "Tray needs Always location to notice when you walk into a hall while the app is closed. That's the whole point of it — otherwise you'd have to check in by hand."
    }

    private var buttonTitle: String {
        store.location.authorization == .denied ? "Open Settings" : "Allow location"
    }
}
