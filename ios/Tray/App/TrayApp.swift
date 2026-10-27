import BackgroundTasks
import SwiftUI
import UserNotifications

@main
struct TrayApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BackgroundRefresh.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(.accentColor)
                .task {
                    await store.bootstrap()
                    _ = await NotificationService.requestPermission()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                store.startPolling()
                Task { await store.refreshAll() }
            case .background:
                store.stopPolling()
                BackgroundRefresh.schedule()
            default:
                store.stopPolling()
            }
        }
    }
}

/// The only way Tray can notify you while closed without a paid developer
/// account. iOS decides when these windows happen and they are not frequent,
/// which is exactly the limitation that push notifications would remove.
enum BackgroundRefresh {
    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Config.refreshTaskID, using: nil
        ) { task in
            schedule()
            // This handler runs off the main queue, and AppStore is main-actor
            // isolated, so it has to be built inside the hop.
            let work = Task { @MainActor in
                let store = AppStore()
                await store.bootstrap()
                await store.deliverPendingAlerts()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: Config.refreshTaskID)
        request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
