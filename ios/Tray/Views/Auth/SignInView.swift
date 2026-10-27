import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var store: AppStore

    @State private var phone = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var busy = false
    @State private var problem: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 10) {
                Text("🍽️").font(.system(size: 54))
                Text("Tray").font(.largeTitle.bold())
                Text("See which friends are eating,\nwithout asking anyone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 14) {
                if codeSent {
                    TextField("6-digit code", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(.title2.monospacedDigit())
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))

                    Button(action: verify) {
                        Label("Sign in", systemImage: "arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(code.count < 4 || busy)

                    Button("Use a different number") {
                        codeSent = false
                        code = ""
                    }
                    .font(.footnote)
                } else {
                    TextField("Phone number", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .padding()
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))

                    Button(action: send) {
                        Label("Send me a code", systemImage: "message")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(phone.count < 10 || busy)
                }

                if let problem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Text("Your number is only used to sign in and to let friends find you. Tray never sees your location history — only which dining hall you walked into.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 40)

            if busy { ProgressView().padding(.bottom, 20) }
        }
    }

    private func send() {
        busy = true
        problem = nil
        Task {
            do {
                try await store.sendCode(to: normalized)
                codeSent = true
            } catch {
                problem = error.localizedDescription
            }
            busy = false
        }
    }

    private func verify() {
        busy = true
        problem = nil
        Task {
            do {
                try await store.verify(phone: normalized, code: code)
            } catch {
                problem = error.localizedDescription
            }
            busy = false
        }
    }

    /// Supabase wants E.164. Students type "617 555 0123".
    private var normalized: String {
        let digits = phone.filter(\.isNumber)
        if digits.count == 10 { return "+1" + digits }
        if digits.count == 11, digits.hasPrefix("1") { return "+" + digits }
        return phone.hasPrefix("+") ? phone : "+" + digits
    }
}
