import SwiftUI

/// Private groups. The people in them are never told, which is the point —
/// labelling your three actual friends should not be a social statement.
struct LabelsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var newName = ""
    @State private var newColor = "blue"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.labels.isEmpty {
                        Text("No groups yet.").foregroundStyle(.secondary)
                    }
                    ForEach(store.labels) { label in
                        HStack {
                            Circle().fill(Color.label(label.color)).frame(width: 11, height: 11)
                            Text(label.name)
                            Spacer()
                            Text("\(label.memberCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            let id = store.labels[index].id
                            Task { await store.deleteLabel(id) }
                        }
                    }
                } header: {
                    Text("Your groups")
                } footer: {
                    Text("Filter the Now screen down to one group. Nobody can see which groups they're in.")
                }

                Section("New group") {
                    TextField("Name, like \"lab group\"", text: $newName)

                    HStack(spacing: 10) {
                        ForEach(Color.labelChoices, id: \.self) { name in
                            Circle()
                                .fill(Color.label(name))
                                .frame(width: 24, height: 24)
                                .overlay {
                                    if name == newColor {
                                        Circle().strokeBorder(.primary, lineWidth: 2)
                                    }
                                }
                                .onTapGesture { newColor = name }
                        }
                    }
                    .padding(.vertical, 2)

                    Button("Add group") {
                        let name = newName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        Task {
                            await store.createLabel(name: name, color: newColor)
                            newName = ""
                        }
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
