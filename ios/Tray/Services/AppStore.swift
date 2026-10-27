import Combine
import CoreLocation
import Foundation
import SwiftUI

/// One observable object for the whole app. Tray is small enough that splitting
/// this into per-screen view models would cost more than it explains.
@MainActor
final class AppStore: ObservableObject {

    enum Phase: Equatable {
        case loading
        case signedOut
        case needsProfile
        case ready
    }

    // MARK: - Published state

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var me: Me?
    @Published private(set) var halls: [DiningHall] = []
    @Published private(set) var feed: [Presence] = []
    @Published private(set) var myCheckIn: MyCheckIn?
    @Published private(set) var busyness: [String: HallBusyness] = [:]
    @Published private(set) var friends: [Friend] = []
    @Published private(set) var invites: [Invite] = []
    @Published private(set) var labels: [FriendLabel] = []

    @Published var errorMessage: String?
    @Published private(set) var isRefreshing = false

    let location = LocationService()

    private var pollTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let lastAlertKey = "tray.lastAlertCheck"

    // MARK: - Derived

    var incomingInvites: [Invite] {
        invites.filter { $0.isIncoming && !$0.isAnswered && !$0.hasExpired }
    }

    var pendingRequests: [Friend] {
        friends.filter { $0.direction == .incoming }
    }

    var acceptedFriends: [Friend] {
        friends.filter { $0.direction == .friend }
    }

    /// Friends currently eating, grouped by hall, busiest hall first.
    var feedByHall: [(hall: DiningHall, people: [Presence])] {
        let grouped = Dictionary(grouping: feed, by: \.hallId)
        return halls.compactMap { hall in
            guard let people = grouped[hall.id], !people.isEmpty else { return nil }
            return (hall, people.sorted { $0.startedAt > $1.startedAt })
        }
        .sorted { $0.people.count > $1.people.count }
    }

    func hall(id: String) -> DiningHall? { halls.first { $0.id == id } }

    // MARK: - Lifecycle

    init() {
        // LocationService is a nested observable object. Without this, a change
        // to the permission state would never redraw anything.
        location.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        location.onArrive = { [weak self] hall in
            guard !hall.id.isEmpty else { return }
            Task { @MainActor in await self?.checkIn(hallID: hall.id, source: "auto") }
        }
        location.onDepart = { [weak self] _ in
            Task { @MainActor in await self?.checkOut(onlyIfAutomatic: true) }
        }
    }

    func bootstrap() async {
        guard Config.isConfigured else {
            phase = .signedOut
            errorMessage = BackendError.notConfigured.errorDescription
            return
        }
        guard await Backend.shared.isSignedIn else {
            phase = .signedOut
            return
        }
        await loadProfile()
    }

    private func loadProfile() async {
        do {
            let rows = try await Backend.shared.rpc("me", as: [Me].self)
            if let profile = rows.first {
                me = profile
                phase = .ready
                await refreshAll()
                await startLocationIfPossible()
            } else {
                phase = .needsProfile
            }
        } catch BackendError.notSignedIn {
            phase = .signedOut
        } catch {
            report(error)
            phase = .signedOut
        }
    }

    // MARK: - Auth

    func sendCode(to phone: String) async throws {
        try await Backend.shared.sendCode(toPhone: phone)
    }

    func verify(phone: String, code: String) async throws {
        try await Backend.shared.verifyCode(phone: phone, code: code)
        await loadProfile()
    }

    func createProfile(username: String, displayName: String, emoji: String) async throws {
        _ = try await Backend.shared.rpc("bootstrap_profile", [
            "p_username": username,
            "p_display_name": displayName,
            "p_emoji": emoji,
            "p_campus_slug": "neu"
        ], as: Me.self)
        await loadProfile()
    }

    func signOut() async {
        stopPolling()
        location.stop()
        await Backend.shared.signOut()
        me = nil
        feed = []
        friends = []
        invites = []
        labels = []
        myCheckIn = nil
        phase = .signedOut
    }

    // MARK: - Loading

    func refreshAll() async {
        guard phase == .ready else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        if halls.isEmpty { await loadHalls() }

        // All six are independent, so they go out together and the screen
        // updates once rather than six times.
        async let feedTask    = Backend.shared.rpc("now_feed", as: [Presence].self)
        async let mineTask    = Backend.shared.rpc("my_checkin", as: [MyCheckIn].self)
        async let busyTask    = Backend.shared.rpc("hall_busyness", as: [HallBusyness].self)
        async let friendsTask = Backend.shared.rpc("friend_list", as: [Friend].self)
        async let invitesTask = Backend.shared.rpc("invite_feed", as: [Invite].self)
        async let labelsTask  = Backend.shared.rpc("label_list", as: [FriendLabel].self)

        if let value = try? await feedTask    { feed = value }
        if let value = try? await mineTask    { myCheckIn = value.first }
        if let value = try? await busyTask    { busyness = Dictionary(uniqueKeysWithValues: value.map { ($0.hallId, $0) }) }
        if let value = try? await friendsTask { friends = value }
        if let value = try? await invitesTask { invites = value }
        if let value = try? await labelsTask  { labels = value }

        await deliverPendingAlerts()
    }

    private func loadHalls() async {
        do {
            halls = try await Backend.shared.select(
                "dining_halls",
                query: [
                    URLQueryItem(name: "select", value: "*"),
                    URLQueryItem(name: "active", value: "eq.true"),
                    URLQueryItem(name: "order", value: "sort_order.asc")
                ],
                as: [DiningHall].self)
        } catch {
            report(error)
        }
    }

    // MARK: - Presence

    func checkIn(hallID: String, source: String) async {
        do {
            _ = try await Backend.shared.rpc("check_in",
                                             ["p_hall": hallID, "p_source": source],
                                             as: CheckInRow.self)
            await refreshAll()
        } catch {
            report(error)
        }
    }

    /// `onlyIfAutomatic` protects a check-in the user made by hand: if they
    /// tapped "I'm at United Table", a noisy GPS exit should not undo it.
    func checkOut(onlyIfAutomatic: Bool = false) async {
        if onlyIfAutomatic, let current = myCheckIn, current.wasManual { return }
        do {
            _ = try await Backend.shared.rpc("check_out", as: Int.self)
            await refreshAll()
        } catch {
            report(error)
        }
    }

    // MARK: - Invisible

    func setInvisibleForToday() async {
        let endOfDay = Calendar.current.startOfDay(for: Date()).addingTimeInterval(24 * 3600)
        await setInvisible(until: endOfDay)
    }

    func setVisible() async {
        await setInvisible(until: nil)
    }

    private func setInvisible(until date: Date?) async {
        do {
            // JSONSerialization cannot encode a Swift nil, so becoming visible
            // again has to send an explicit JSON null.
            let value: Any = date.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull()
            let updated = try await Backend.shared.rpc(
                "set_invisible", ["p_until": value], as: ProfileRow.self)
            me?.invisibleUntil = updated.invisibleUntil
        } catch {
            report(error)
        }
    }

    // MARK: - Friends

    func lookUp(phone: String) async -> [FoundPerson] {
        (try? await Backend.shared.rpc("find_by_phone", ["p_phone": phone], as: [FoundPerson].self)) ?? []
    }

    func lookUp(username: String) async -> [FoundPerson] {
        (try? await Backend.shared.rpc("find_by_username", ["p_username": username], as: [FoundPerson].self)) ?? []
    }

    func addFriend(_ userID: String) async {
        await act { _ = try await Backend.shared.rpc("request_friend", ["p_user": userID], as: FriendshipRow.self) }
    }

    func respondToRequest(_ friendshipID: String, accept: Bool) async {
        await act { try await Backend.shared.rpc("respond_friend", ["p_id": friendshipID, "p_accept": accept]) }
    }

    func unfriend(_ userID: String) async {
        await act { try await Backend.shared.rpc("unfriend", ["p_user": userID]) }
    }

    func setNotify(_ userID: String, on: Bool) async {
        await act { try await Backend.shared.rpc("set_notify", ["p_friend": userID, "p_on": on]) }
    }

    // MARK: - Labels

    func createLabel(name: String, color: String) async {
        await act { _ = try await Backend.shared.rpc("create_label", ["p_name": name, "p_color": color], as: LabelRow.self) }
    }

    func deleteLabel(_ labelID: String) async {
        await act { try await Backend.shared.rpc("delete_label", ["p_id": labelID]) }
    }

    func setLabel(_ labelID: String, on friendID: String, member: Bool) async {
        await act {
            try await Backend.shared.rpc("set_label_member",
                                         ["p_label": labelID, "p_friend": friendID, "p_on": member])
        }
    }

    // MARK: - Invites

    func invite(_ userID: String) async {
        await act { _ = try await Backend.shared.rpc("send_invite", ["p_to": userID], as: InviteRow.self) }
    }

    func respond(to inviteID: String, with reply: InviteReply) async {
        await act {
            _ = try await Backend.shared.rpc("respond_invite",
                                             ["p_id": inviteID, "p_response": reply.rawValue],
                                             as: InviteRow.self)
        }
    }

    // MARK: - Alerts

    /// Turn anything that happened since the last check into a local notification.
    func deliverPendingAlerts() async {
        let defaults = UserDefaults.standard
        let since = (defaults.object(forKey: lastAlertKey) as? Date)
            ?? Date().addingTimeInterval(-600)

        guard let alerts = try? await Backend.shared.rpc(
            "alerts_since",
            ["p_since": ISO8601DateFormatter().string(from: since)],
            as: [Alert].self) else { return }

        for alert in alerts { NotificationService.post(alert) }
        defaults.set(Date(), forKey: lastAlertKey)
    }

    // MARK: - Location and polling

    func startLocationIfPossible() async {
        guard !halls.isEmpty else { return }
        location.start(halls: halls)
    }

    func startPolling() {
        stopPolling()
        // Twenty five seconds is frequent enough to feel live over a meal and
        // slow enough that it costs nothing.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshAll() }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Plumbing

    private func act(_ work: @escaping () async throws -> Void) async {
        do {
            try await work()
            await refreshAll()
        } catch {
            report(error)
        }
    }

    private func report(_ error: Error) {
        // A rejected refresh token is not an error to show someone; it just
        // means the session is over.
        if let backend = error as? BackendError, case .notSignedIn = backend {
            phase = .signedOut
            return
        }
        errorMessage = error.localizedDescription
    }
}

// Minimal shapes for RPCs whose return value the app does not display.
struct CheckInRow: Decodable { let id: String; let hallId: String }
struct ProfileRow: Decodable { let id: String; let invisibleUntil: Date? }
struct FriendshipRow: Decodable { let id: String; let status: String }
struct LabelRow: Decodable { let id: String; let name: String }
struct InviteRow: Decodable { let id: String }
