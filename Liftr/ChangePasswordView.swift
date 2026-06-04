import SwiftUI
import Supabase

struct ChangePasswordView: View {
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var loading = false
    @State private var error: String?
    @State private var banner: Banner?

    @Environment(\.dismiss) private var dismiss

    private var newPasswordValid: Bool { PasswordResetValidation.isPasswordValid(newPassword) }
    private var passwordsMatch: Bool { PasswordResetValidation.passwordsMatch(newPassword, confirmPassword) }
    private var newDiffersFromCurrent: Bool { !newPassword.isEmpty && newPassword != currentPassword }
    private var canSubmit: Bool {
        !loading &&
            !currentPassword.isEmpty &&
            newPasswordValid &&
            passwordsMatch &&
            newDiffersFromCurrent &&
            !confirmPassword.isEmpty
    }

    var body: some View {
        GradientBackground {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.20), .purple.opacity(0.20)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 320, height: 320)
                    .blur(radius: 90)
                    .offset(y: -170)
                    .allowsHitTesting(false)

                VStack(spacing: 18) {
                    Spacer(minLength: 0)

                    Text("Update your account password.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    VStack(spacing: 14) {
                        if let error {
                            Text(error)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        SecureField("Current password", text: $currentPassword)
                            .textContentType(.password)

                        SecureField("New password (min. 8)", text: $newPassword)
                            .textContentType(.newPassword)

                        SecureField("Confirm password", text: $confirmPassword)
                            .textContentType(.newPassword)

                        if !newPasswordValid && !newPassword.isEmpty {
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

                        if !newDiffersFromCurrent && !newPassword.isEmpty {
                            Text("New password must be different from your current password.")
                                .font(.caption)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            Task { await changePassword() }
                        } label: {
                            HStack {
                                if loading { ProgressView().tint(.white) }
                                Text(loading ? "Updating…" : "Update password")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(canSubmit ? Color.blue : Color.gray.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                        }
                        .disabled(!canSubmit)

                        NavigationLink {
                            ForgotPasswordView()
                        } label: {
                            Text("Forgot your password? Reset it here.")
                                .font(.footnote.weight(.semibold))
                        }
                        .buttonStyle(.plain)
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
        .toolbarBackground(.hidden, for: .navigationBar)
        .banner($banner)
        .onChange(of: currentPassword) { _, _ in error = nil }
        .onChange(of: newPassword) { _, _ in error = nil }
        .onChange(of: confirmPassword) { _, _ in error = nil }
    }

    private func changePassword() async {
        error = nil
        loading = true
        defer { loading = false }

        do {
            let session = try await SupabaseManager.shared.client.auth.session
            guard let email = session.user.email, !email.isEmpty else {
                await MainActor.run {
                    self.error = "Unable to read your account email. Please sign out and sign in again."
                }
                return
            }

            try await SupabaseManager.shared.client.auth.signIn(email: email, password: currentPassword)
            try await SupabaseManager.shared.client.auth.update(user: UserAttributes(password: newPassword))

            LoginView.KeychainHelper.delete(key: "settleit.email")
            LoginView.KeychainHelper.delete(key: "settleit.password")

            await MainActor.run {
                banner = Banner(message: "Password updated", type: .success)
                dismiss()
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                banner = Banner(message: "Password update failed", type: .error)
            }
        }
    }
}

