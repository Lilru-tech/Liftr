import SwiftUI
import Supabase
import Security

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var loading = false
    @State private var error: String?
    @State private var banner: Banner?
    @State private var rememberMe = false
    
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
                
                VStack(spacing: 18) {
                    Spacer(minLength: 0)
                    
                    Text("Sign in to continue tracking your workouts.")
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
                        
                        TextField("Email", text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .textContentType(.username)
                            .autocorrectionDisabled(true)
                        
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                        
                        Toggle("Remember me", isOn: $rememberMe)
                            .tint(.blue)
                        
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
        .onAppear { loadRemembered() }
    }
    
    private func loadRemembered() {
        if let storedEmail = KeychainHelper.read(key: "settleit.email"),
           let storedPassword = KeychainHelper.read(key: "settleit.password"),
           !storedEmail.isEmpty, !storedPassword.isEmpty {
            email = storedEmail
            password = storedPassword
            rememberMe = true
        }
    }
    
    private func signIn() async {
        error = nil
        loading = true
        defer { loading = false }
        
        do {
            try await SupabaseManager.shared.client.auth.signIn(email: email, password: password)
            await MainActor.run {
                if rememberMe {
                    KeychainHelper.save(key: "settleit.email", value: email)
                    KeychainHelper.save(key: "settleit.password", value: password)
                } else {
                    KeychainHelper.delete(key: "settleit.email")
                    KeychainHelper.delete(key: "settleit.password")
                }
                banner = Banner(message: "Welcome back 👋", type: .success)
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                banner = Banner(message: "Sign in failed", type: .error)
            }
        }
    }
    
    struct KeychainHelper {
        private static let service = "com.settleit.app.credentials"
        
        static func save(key: String, value: String) {
            let data = Data(value.utf8)
            delete(key: key)
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecValueData as String: data
            ]
            SecItemAdd(query as CFDictionary, nil)
        }
        
        static func read(key: String) -> String? {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            guard status == errSecSuccess,
                  let data = item as? Data,
                  let string = String(data: data, encoding: .utf8) else { return nil }
            return string
        }
        
        static func delete(key: String) {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key
            ]
            SecItemDelete(query as CFDictionary)
        }
    }
}
