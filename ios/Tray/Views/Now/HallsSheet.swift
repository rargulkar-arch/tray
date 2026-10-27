import SwiftUI

/// How busy each hall is right now, counted across everyone on Tray rather than
/// just your friends. The count stays hidden until there are enough people that
/// a number does not single anyone out.
struct HallsSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.halls) { hall in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hall.name).font(.body.weight(.medium))
                                if let building = hall.building {
                                    Text(building).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            let state = store.busyness[hall.id]
                            Pill(text: label(for: state),
                                 tint: busynessTint(state?.bucket ?? "empty"))
                        }
                        .padding(.vertical, 2)
                    }
                } footer: {
                    Text("Counted from people using Tray, so it reads low until more of campus is on it. Nobody's name appears here.")
                }
            }
            .navigationTitle("Dining halls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .refreshable { await store.refreshAll() }
        }
    }

    private func label(for state: HallBusyness?) -> String {
        guard let state else { return "quiet" }
        if state.headcount > 0 { return "\(state.headcount) here" }
        return state.bucket == "empty" ? "quiet" : state.bucket
    }
}
