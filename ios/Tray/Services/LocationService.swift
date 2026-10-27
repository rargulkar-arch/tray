import CoreLocation
import Foundation

/// Watches the dining halls and reports arrivals and departures.
///
/// Two things make this harder than "register a geofence":
///
/// 1. Stetson East and Stetson West are roughly 50m apart, so a single step can
///    sit inside both circles. iOS will happily fire both. So an entry event is
///    treated as a hint, not an answer — the service takes a fresh fix and
///    checks you into whichever hall is actually closest.
/// 2. iOS does not promise an exit event. The app re-checks its regions on every
///    launch and on every significant location change, and the database expires
///    a forgotten check-in after three hours regardless.
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {

    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var monitoredCount: Int = 0

    /// Called with the hall the user has actually arrived at.
    var onArrive: ((DiningHall) -> Void)?
    /// Called with the hall the user has left.
    var onDepart: ((DiningHall) -> Void)?

    private let manager = CLLocationManager()
    private var halls: [DiningHall] = []
    private var fixWaiters: [(CLLocation?) -> Void] = []

    /// iOS allows twenty monitored regions per app, shared with everything else
    /// the app might want to watch one day.
    private let maxRegions = 20

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = true
        authorization = manager.authorizationStatus
    }

    // MARK: - Permission

    /// Ask for "While Using" first; iOS only offers "Always" as a follow-up.
    func requestPermission() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    var hasBackgroundPermission: Bool { authorization == .authorizedAlways }

    // MARK: - Geofences

    func start(halls: [DiningHall]) {
        self.halls = halls.filter(\.active)
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }

        for region in manager.monitoredRegions where region.identifier.hasPrefix("hall:") {
            manager.stopMonitoring(for: region)
        }

        let watched = nearestHalls(limit: maxRegions)
        for hall in watched {
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: hall.lat, longitude: hall.lng),
                radius: hall.radiusM,
                identifier: "hall:\(hall.id)")
            region.notifyOnEntry = true
            region.notifyOnExit = true
            manager.startMonitoring(for: region)
        }

        // monitoredRegions fills in asynchronously, so report what was asked for.
        monitoredCount = watched.count
        manager.startMonitoringSignificantLocationChanges()
        reconcile()
    }

    func stop() {
        for region in manager.monitoredRegions where region.identifier.hasPrefix("hall:") {
            manager.stopMonitoring(for: region)
        }
        manager.stopMonitoringSignificantLocationChanges()
        monitoredCount = 0
        halls = []
    }

    /// Ask iOS where we stand right now. Used at launch, so that opening the app
    /// inside a hall checks you in even if the entry event was missed.
    func reconcile() {
        guard !halls.isEmpty else { return }
        requestFix { [weak self] location in
            guard let self, let location else { return }
            if let hall = self.nearestHall(to: location), self.isInside(location, hall) {
                self.onArrive?(hall)
            } else {
                self.onDepart?(DiningHall.nowhere)
            }
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if authorization == .authorizedAlways || authorization == .authorizedWhenInUse {
            if !halls.isEmpty { start(halls: halls) }
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier.hasPrefix("hall:") else { return }
        // Do not trust the region that fired — two halls overlap on this campus.
        requestFix { [weak self] location in
            guard let self else { return }
            let resolved = location.flatMap { self.nearestHall(to: $0) }
                ?? self.hall(forRegion: region.identifier)
            if let resolved { self.onArrive?(resolved) }
        }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier.hasPrefix("hall:"),
              let left = hall(forRegion: region.identifier) else { return }
        // Leaving Stetson East may just mean stepping into Stetson West.
        requestFix { [weak self] location in
            guard let self else { return }
            if let location, let near = self.nearestHall(to: location), self.isInside(location, near) {
                self.onArrive?(near)
            } else {
                self.onDepart?(left)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let latest = locations.last
        let waiters = fixWaiters
        fixWaiters = []
        waiters.forEach { $0(latest) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let waiters = fixWaiters
        fixWaiters = []
        waiters.forEach { $0(manager.location) }
    }

    func locationManager(_ manager: CLLocationManager,
                         monitoringDidFailFor region: CLRegion?, withError error: Error) {
        monitoredCount = manager.monitoredRegions.count
    }

    // MARK: - Geometry

    private func requestFix(_ completion: @escaping (CLLocation?) -> Void) {
        // A fix from the last half minute is good enough and costs no battery.
        if let cached = manager.location, cached.timestamp.timeIntervalSinceNow > -30 {
            completion(cached)
            return
        }
        fixWaiters.append(completion)
        manager.requestLocation()
    }

    private func hall(forRegion identifier: String) -> DiningHall? {
        let id = String(identifier.dropFirst("hall:".count))
        return halls.first { $0.id == id }
    }

    private func nearestHall(to location: CLLocation) -> DiningHall? {
        halls.min { distance(location, $0) < distance(location, $1) }
    }

    private func distance(_ location: CLLocation, _ hall: DiningHall) -> CLLocationDistance {
        CLLocation(latitude: hall.lat, longitude: hall.lng).distance(from: location)
    }

    /// Allow a little slack past the drawn radius: GPS indoors is not generous,
    /// and a dining hall is a building, not a point.
    private func isInside(_ location: CLLocation, _ hall: DiningHall) -> Bool {
        distance(location, hall) <= hall.radiusM + min(location.horizontalAccuracy, 50)
    }

    private func nearestHalls(limit: Int) -> [DiningHall] {
        guard halls.count > limit else { return halls }
        guard let here = manager.location else { return Array(halls.prefix(limit)) }
        return halls.sorted { distance(here, $0) < distance(here, $1) }.prefix(limit).map { $0 }
    }
}

extension DiningHall {
    /// A sentinel meaning "not at any hall", used only to signal a departure.
    static let nowhere = DiningHall(id: "", name: "", building: nil, lat: 0, lng: 0,
                                    radiusM: 0, sortOrder: 0, active: false)
}
