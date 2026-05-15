import SwiftUI
import Supabase

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var loading = false
    @State private var error: String?
    @State private var emailSent = false

    private var isEmailValid: Bool {
        NSPredicate(format: "SELF MATCHES[c] %@", "^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$")
            .evaluate(with: email.uppercased())
    }

    private var isButtonEnabled: Bool { !loading && isEmailValid }

    var body: some View {
        GradientBackground {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.blue.opacity(0.20), .purple.opacity(0.20)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(y: -170)
                .allowsHitTesting(false)

            VStack(spacing: 18) {
                Spacer(minLength: 0)

                Text("Enter the email for your account and we will send you a link to reset your password.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                VStack(spacing: 14) {
                    if emailSent {
                        Text("If an account exists for this email, you will receive a reset link shortly. Open it on this device.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        if let error {
                            Text(error)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        TextField("Email", text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .autocorrectionDisabled(true)

                        Button {
                            Task { await sendResetLink() }
                        } label: {
                            HStack {
                                if loading { ProgressView().tint(.white) }
                                Text(loading ? "Sending…" : "Send reset link")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(isButtonEnabled ? Color.blue : Color.gray.opacity(0.5),
                                        in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                        }
                        .disabled(!isButtonEnabled)
                    }
                }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.white.opacity(0.22), lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
                .padding(.horizontal, 24)

                Spacer(minLength: 0)
            }
            }
        }
        .navigationTitle("Forgot password")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func sendResetLink() async {
        error = nil
        loading = true
        defer { loading = false }

        do {
            try await SupabaseManager.shared.client.auth.resetPasswordForEmail(
                email.trimmingCharacters(in: .whitespacesAndNewlines),
                redirectTo: AuthRedirect.webCallbackURL
            )
            await MainActor.run { emailSent = true }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
            }
        }
    }
}
