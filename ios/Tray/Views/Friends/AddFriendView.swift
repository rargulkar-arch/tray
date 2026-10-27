import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct AddFriendView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [FoundPerson] = []
    @State private var searching = false
    @State private var searched = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Phone number or @username", text: $query)
                        .keyboardType(.default)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(search)

                    Button(action: search) {
                        HStack {
                            Text("Search")
                            if searching { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(query.trimmingCharacters(in: .whitespaces).count < 3 || searching)
                } footer: {
                    Text("A number only finds someone who already uses Tray. Nothing is uploaded from your contacts.")
                }

                if searched && results.isEmpty && !searching {
                    Section {
                        EmptyState(icon: "magnifyingglass",
                                   title: "Nobody found",
                                   message: "They're probably not on Tray yet. Send them your link below.")
                        .listRowBackground(Color.clear)
                    }
                }

                if !results.isEmpty {
                    Section("Found") {
                        ForEach(results) { person in
                            HStack(spacing: 12) {
                                Avatar(emoji: person.emoji, size: 38)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(person.displayName).font(.body.weight(.medium))
                                    Text("@\(person.username)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                switch person.status {
                                case "accepted":
                                    Pill(text: "friends", tint: .green)
                                case "pending":
                                    Pill(text: "pending")
                                default:
                                    Button("Add") {
                                        Task {
                                            await store.addFriend(person.id)
                                            search()
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                }

                Section("Or send them your link") {
                    ShareInvite()
                }
            }
            .navigationTitle("Add a friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 3 else { return }
        searching = true
        Task {
            // Anything with four or more digits is a phone number, not a handle.
            let digits = text.filter(\.isNumber)
            results = digits.count >= 7
                ? await store.lookUp(phone: text)
                : await store.lookUp(username: text.hasPrefix("@") ? String(text.dropFirst()) : text)
            searching = false
            searched = true
        }
    }
}

/// A link and a QR code so adding someone standing next to you takes one tap.
struct ShareInvite: View {
    @EnvironmentObject private var store: AppStore
    @State private var showQR = false

    var body: some View {
        let link = inviteLink

        VStack(alignment: .leading, spacing: 12) {
            if let link {
                ShareLink(item: link,
                          message: Text("Add me on Tray so you can see when I'm eating.")) {
                    Label("Share my link", systemImage: "square.and.arrow.up")
                }

                Button {
                    showQR.toggle()
                } label: {
                    Label(showQR ? "Hide QR code" : "Show QR code", systemImage: "qrcode")
                }

                if showQR, let image = qrCode(for: link.absoluteString) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 190, height: 190)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            } else {
                Text("Finish setting up your profile first.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Needs a real domain and an apple-app-site-association file before it
    /// opens Tray on a phone that has it installed; until then it is a handle
    /// people can paste into the search box above.
    private var inviteLink: URL? {
        guard let username = store.me?.username else { return nil }
        return URL(string: "https://tray.app/add/\(username)")
    }

    private func qrCode(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
