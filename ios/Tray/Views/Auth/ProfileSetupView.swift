import SwiftUI

struct ProfileSetupView: View {
    @EnvironmentObject private var store: AppStore

    @State private var displayName = ""
    @State private var username = ""
    @State private var emoji = "🍜"
    @State private var busy = false
    @State private var problem: String?

    private let emojiChoices = ["🍜", "🍕", "🥗", "🍔", "🌮", "🍣", "🥞", "☕️", "🍩", "🧋", "🍪", "🥐"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $displayName)
                        .textContentType(.givenName)
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Who you are")
                } footer: {
                    Text("Friends can find you by your number or your username.")
                }

                Section("Your face") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(emojiChoices, id: \.self) { choice in
                            Text(choice)
                                .font(.system(size: 28))
                                .frame(width: 44, height: 44)
                                .background(choice == emoji ? Color.accentColor.opacity(0.2) : .clear,
                                            in: Circle())
                                .onTapGesture { emoji = choice }
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let problem {
                    Section { Text(problem).foregroundStyle(.red).font(.footnote) }
                }

                Section {
                    Button(action: save) {
                        if busy { ProgressView() } else { Text("Start using Tray") }
                    }
                    .disabled(!isValid || busy)
                }
            }
            .navigationTitle("Set up Tray")
        }
    }

    private var isValid: Bool {
        displayName.trimmingCharacters(in: .whitespaces).count >= 1 && username.count >= 2
    }

    private func save() {
        busy = true
        problem = nil
        Task {
            do {
                try await store.createProfile(
                    username: username.trimmingCharacters(in: .whitespaces),
                    displayName: displayName.trimmingCharacters(in: .whitespaces),
                    emoji: emoji)
            } catch {
                problem = error.localizedDescription
            }
            busy = false
        }
    }
}
