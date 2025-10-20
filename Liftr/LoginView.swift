import SwiftUI
import Supabase

struct LoginView: View {
  @State private var email = ""
  @State private var password = ""
  @State private var loading = false
  @State private var error: String?
  @State private var banner: Banner?

  // Validación simple de email
  private var isEmailValid: Bool {
    NSPredicate(format: "SELF MATCHES[c] %@", "^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$")
      .evaluate(with: email.uppercased())
  }
  private var isButtonEnabled: Bool { !loading && isEmailValid && !password.isEmpty }

  var body: some View {
      ZStack {
          ZStack {
            Circle()
              .fill(LinearGradient(colors: [.blue.opacity(0.28), .purple.opacity(0.28)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
              .frame(width: 320, height: 320)
              .blur(radius: 90)
              .offset(y: -170)
              .allowsHitTesting(false)

            // Contenido centrado verticalmente
            VStack(spacing: 18) {
              Spacer(minLength: 0)

              // Subtítulo centrado
              Text("Sign in to continue tracking your workouts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

              // Tarjeta translúcida
              VStack(spacing: 14) {
                if let error {
                  Text(error)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                TextField("Email", text: $email)
                  .textInputAutocapitalization(.never)
                  .keyboardType(.emailAddress)
                  .textContentType(.username)
                  .autocorrectionDisabled(true)

                SecureField("Password", text: $password)
                  .textContentType(.password)

                Button {
                  Task { await signIn() }
                } label: {
                  HStack {
                    if loading { ProgressView().tint(.white) }
                    Text(loading ? "Signing in…" : "Sign in")
                      .fontWeight(.semibold)
                  }
                  .frame(maxWidth: .infinity)
                  .padding(.vertical, 12)
                  .background(isButtonEnabled ? Color.blue : Color.gray.opacity(0.5),
                              in: RoundedRectangle(cornerRadius: 14))
                  .foregroundStyle(.white)
                }
                .disabled(!isButtonEnabled)

                HStack {
                  Rectangle().frame(height: 1).foregroundStyle(.quaternary)
                  Text("or").font(.caption).foregroundStyle(.secondary)
                  Rectangle().frame(height: 1).foregroundStyle(.quaternary)
                }

                NavigationLink {
                  RegisterView()
                } label: {
                  Text("Create an account")
                    .fontWeight(.semibold)
                }
                .padding(.top, 4)
              }
              .padding(20)
              .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
              .overlay(
                RoundedRectangle(cornerRadius: 20)
                  .stroke(.white.opacity(0.22), lineWidth: 0.8)
              )
              .shadow(color: .black.opacity(0.12), radius: 10, y: 6)

              Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
          }
      }
  }

  private func signIn() async {
    error = nil
    loading = true
    defer { loading = false }

    do {
      try await SupabaseManager.shared.client.auth.signIn(email: email, password: password)
      await MainActor.run {
        banner = Banner(message: "Welcome back 👋", type: .success)
      }
    } catch {
      await MainActor.run {
        self.error = error.localizedDescription
        banner = Banner(message: "Sign in failed", type: .error)
      }
    }
  }
}
