import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Group {
            switch store.phase {
            case .loading:
                ProgressView().controlSize(.large)
            case .signedOut:
                SignInView()
            case .needsProfile:
                ProfileSetupView()
            case .ready:
                MainTabs()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.phase)
        .alert("Something went wrong",
               isPresented: Binding(get: { store.errorMessage != nil },
                                    set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

struct MainTabs: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        TabView {
            NowView()
                .tabItem { Label("Now", systemImage: "fork.knife") }
                .badge(store.incomingInvites.count)

            FriendsView()
                .tabItem { Label("Friends", systemImage: "person.2") }
                .badge(store.pendingRequests.count)

            MeView()
                .tabItem { Label("Me", systemImage: "person.crop.circle") }
        }
    }
}
