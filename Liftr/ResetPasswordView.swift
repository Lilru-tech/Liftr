import SwiftUI
import Supabase

struct ResetPasswordView: View {
    @EnvironmentObject private var app: AppState
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var loading = false
    @State private var error: String?

    private var isPasswordValid: Bool { PasswordResetValidation.isPasswordValid(password) }
    private var passwordsMatch: Bool { PasswordResetValidation.passwordsMatch(password, confirmPassword) }
    private var isButtonEnabled: Bool {
        !loading && isPasswordValid && passwordsMatch && !confirmPassword.isEmpty
    }

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

                Text("Choose a new password for your account.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                VStack(spacing: 14) {
                    if let callbackError = app.authCallbackError {
                        Text(callbackError)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let error {
                        Text(error)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    SecureField("New password (min. 8)", text: $password)
                        .textContentType(.newPassword)

                    SecureField("Confirm password", text: $confirmPassword)
                        .textContentType(.newPassword)

                    if !isPasswordValid && !password.isEmpty {
                        Text("Password must be at least 8 characters.")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !passwordsMatch && !confirmPassword.isEmpty {
                        Text("Passwords do not match.")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Task { await updatePassword() }
                    } label: {
                        HStack {
                            if loading { ProgressView().tint(.white) }
                            Text(loading ? "Updating…" : "Update password")
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Reset password")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private func updatePassword() async {
        error = nil
        loading = true
        defer { loading = false }

        do {
            try await SupabaseManager.shared.client.auth.update(
                user: UserAttributes(password: password)
            )
            LoginView.KeychainHelper.delete(key: "settleit.email")
            LoginView.KeychainHelper.delete(key: "settleit.password")
            await MainActor.run {
                app.completePasswordRecovery()
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
            }
        }
    }
}
