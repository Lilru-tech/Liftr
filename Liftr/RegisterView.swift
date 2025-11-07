import SwiftUI
import Supabase

struct RegisterView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var sex: Sex = .prefer_not_to_say
    @State private var dateOfBirth: Date = Calendar.current.date(byAdding: .year, value: -20, to: .now) ?? .now
    @State private var height: String = ""
    @State private var weight: String = ""
    
    @State private var loading = false
    @State private var error: String?
    @State private var banner: Banner?
    @State private var usernameDirty = false
    @State private var triedSubmit = false
    
    private var isEmailValid: Bool {
        NSPredicate(format: "SELF MATCHES[c] %@", "^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$")
            .evaluate(with: email.uppercased())
    }
    private var isPasswordValid: Bool { password.count >= 8 }
    private var isUsernameValid: Bool {
        username.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
    }
    private var isFormValid: Bool {
        isEmailValid && isPasswordValid && isUsernameValid
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
                    Text("Create your account to start tracking your workouts.")
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
                            .textContentType(.emailAddress)
                            .autocorrectionDisabled(true)
                        SecureField("Password (min. 8)", text: $password)
                            .textContentType(.newPassword)
                        
                        if !isEmailValid && !email.isEmpty {
                            Text("Invalid email format.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        if !isPasswordValid && !password.isEmpty {
                            Text("Password must be at least 8 characters.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        
                        TextField("Username (required)", text: $username)
                            .textInputAutocapitalization(.never)
                            .textContentType(.nickname)
                            .autocorrectionDisabled(true)
                            .onChange(of: username, initial: false) { _, _ in
                                usernameDirty = true
                            }
                        
                        if (usernameDirty || triedSubmit) &&
                            username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Username is required.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else if (usernameDirty || triedSubmit) && !isUsernameValid {
                            Text("Username must be at least 3 characters.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        
                        Divider().padding(.vertical, 4)
                        
                        LabeledContent {
                            Picker("", selection: $sex) {
                                ForEach(Sex.allCases, id: \.self) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.menu)
                        } label: {
                            Text("Sex")
                                .foregroundStyle(.secondary)
                        }
                        .labelStyle(.titleOnly)
                        
                        LabeledContent {
                            DatePicker("", selection: $dateOfBirth, displayedComponents: .date)
                                .datePickerStyle(.compact)
                        } label: {
                            Text("Date of birth")
                                .foregroundStyle(.secondary)
                        }
                        .labelStyle(.titleOnly)
                        .padding(.vertical, 2)
                        
                        TextField("Height (cm)", text: $height).keyboardType(.decimalPad)
                        TextField("Weight (kg)", text: $weight).keyboardType(.decimalPad)
                        
                        VStack(spacing: 12) {
                            Text("You can update these details later in your profile.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            
                            Button {
                                triedSubmit = true
                                guard isFormValid else { return }
                                Task { await signUp() }
                            } label: {
                                HStack {
                                    if loading { ProgressView().tint(.white) }
                                    Text(loading ? "Creating…" : "Create account")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background((!loading && isFormValid) ? Color.blue : Color.gray.opacity(0.5),
                                            in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.white)
                            }
                            .disabled(loading || !isFormValid)
                        }
                        .padding(.top, 6)
                    }
                    .padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.22), lineWidth: 0.8))
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
                    .padding(.horizontal, 24)
                    
                    Spacer(minLength: 0)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .banner($banner)
        }
    }
    
    private func signUp() async {
        error = nil
        loading = true
        defer { loading = false }
        
        let client = SupabaseManager.shared.client
        try? await client.auth.signOut()
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanUsername.count >= 3 else {
            self.error = "Username is required (min. 3 characters)."
            return
        }
        var meta: [String: AnyJSON] = [:]
        if !cleanUsername.isEmpty, let v = try? AnyJSON(cleanUsername) { meta["username"] = v }
        if let v = try? AnyJSON(sex.rawValue) { meta["sex"] = v }
        if let v = try? AnyJSON(DateFormatter.yyyyMMdd.string(from: dateOfBirth)) { meta["date_of_birth"] = v }
        if let h = Double(height.replacingOccurrences(of: ",", with: ".")), let v = try? AnyJSON(h) { meta["height_cm"] = v }
        if let w = Double(weight.replacingOccurrences(of: ",", with: ".")), let v = try? AnyJSON(w) { meta["weight_kg"] = v }
        
        struct Precheck: Decodable { let email_exists: Bool; let username_exists: Bool }
        
        do {
            let rpcResp = try await client
                .rpc("precheck_signup", params: ["p_email": email, "p_username": cleanUsername])
                .execute()
            
            let precheck = try JSONDecoder().decode([Precheck].self, from: rpcResp.data)
            
            guard let result = precheck.first else {
                self.error = "Validation service unavailable. Please try again."
                return
            }
            if result.email_exists {
                self.error = "Email is already registered."
                return
            }
            if result.username_exists {
                self.error = "Username is already taken."
                return
            }
        } catch {
            self.error = "Could not validate your data. Please try again."
            return
        }
        
        do {
            _ = try await client.auth.signUp(email: email, password: password, data: meta)
        } catch {
            let raw = String(describing: error)
            print("🔴 signUp auth error:", raw)
            
            let msg = raw.lowercased()
            if msg.contains("already registered") || msg.contains("user already registered") || msg.contains("exists") {
                self.error = "Email is already registered."
            } else if msg.contains("password") && msg.contains("length") {
                self.error = "Password must be at least 8 characters."
            } else {
                self.error = raw
            }
            return
        }
        
        guard let session = try? await client.auth.session else {
            await BannerAction.showSuccessAndDismiss("Account created! Welcome 🎉", banner: $banner, dismiss: dismiss)
            return
        }
        
        let userId = session.user.id
        func parseDouble(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }
        struct ProfileUpsert: Encodable {
            let user_id: UUID
            let username: String?
            let sex: String?
            let date_of_birth: String?
            let height_cm: Double?
            let weight_kg: Double?
        }
        let payload = ProfileUpsert(
            user_id: userId,
            username: cleanUsername.isEmpty ? nil : cleanUsername,
            sex: sex.rawValue,
            date_of_birth: DateFormatter.yyyyMMdd.string(from: dateOfBirth),
            height_cm: parseDouble(height),
            weight_kg: parseDouble(weight)
        )
        
        do {
            _ = try await client
                .from("profiles")
                .upsert(payload, onConflict: "user_id")
                .execute()
        } catch {
        }
        
        await BannerAction.showSuccessAndDismiss("Account created! Welcome 🎉", banner: $banner, dismiss: dismiss)
    }
}

enum Sex: String, CaseIterable {
    case male, female, other, prefer_not_to_say
    var label: String {
        switch self {
        case .male: "Male"
        case .female: "Female"
        case .other: "Other"
        case .prefer_not_to_say: "Prefer not to say"
        }
    }
}
extension DateFormatter {
    static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.calendar = .init(identifier: .iso8601)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
