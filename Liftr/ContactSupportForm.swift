import SwiftUI
import Supabase

struct ContactSupportForm: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var userEmail: String = ""
    @State private var selectedSubject: String = "Bug Report"
    @State private var message: String = ""
    
    @State private var loading = false
    @State private var error: String?
    @State private var banner: Banner?
    
    private let subjects = [
        "Bug Report",
        "User Report",
        "Feature Request",
        "Account Problem",
        "Login Issue",
        "Data or Stats Issue",
        "Workout Sync Problem",
        "Payment Issue",
        "Lost Purchases or Coins",
        "Abuse or Harassment",
        "Privacy Concern",
        "Security Vulnerability",
        "General Feedback",
        "Other"
    ]
    
    private var isFormValid: Bool {
        !userEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !selectedSubject.isEmpty &&
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        GradientBackground {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.blue.opacity(0.25), .purple.opacity(0.20)],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                    .frame(width: 320, height: 320)
                    .blur(radius: 90)
                    .offset(y: -170)
                    .allowsHitTesting(false)
                
                VStack(spacing: 18) {
                    Spacer(minLength: 0)
                    
                    Text("Tell us what’s going on and we’ll get back to you as soon as possible.")
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
                        
                        LabeledContent {
                            Text(userEmail.isEmpty ? "—" : userEmail)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        } label: {
                            Text("Your email")
                                .foregroundStyle(.secondary)
                        }
                        .labelStyle(.titleOnly)
                        
                        Divider().padding(.vertical, 2)
                        
                        LabeledContent {
                            Picker("", selection: $selectedSubject) {
                                ForEach(subjects, id: \.self) { subject in
                                    Text(subject).tag(subject)
                                }
                            }
                            .pickerStyle(.menu)
                        } label: {
                            Text("Subject")
                                .foregroundStyle(.secondary)
                        }
                        .labelStyle(.titleOnly)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Message")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            ZStack(alignment: .topLeading) {
                                if message.isEmpty {
                                    Text("Describe the issue or request in as much detail as possible…")
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 8)
                                }
                                
                                TextEditor(text: $message)
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 180, maxHeight: 260)
                                    .padding(8)
                                    .background(Color.clear)
                                    .onChange(of: message) { _, newValue in
                                        if newValue.count > 1000 {
                                            message = String(newValue.prefix(1000))
                                        }
                                    }
                            }
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            
                            HStack {
                                Spacer()
                                Text("\(message.count)/1000")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        VStack(spacing: 12) {
                            Text("We’ll use your account email to contact you if we need more details.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            
                            Button {
                                guard isFormValid else { return }
                                Task { await sendContactMessage() }
                            } label: {
                                HStack {
                                    if loading { ProgressView().tint(.white) }
                                    Text(loading ? "Sending…" : "Send message")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    (!loading && isFormValid)
                                    ? Color.blue
                                    : Color.gray.opacity(0.5),
                                    in: RoundedRectangle(cornerRadius: 14)
                                )
                                .foregroundStyle(.white)
                            }
                            .disabled(loading || !isFormValid)
                        }
                        .padding(.top, 6)
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
            .banner($banner)
            .task { await loadUserEmail() }
        }
    }
        
    private func loadUserEmail() async {
        let client = SupabaseManager.shared.client
        if let session = try? await client.auth.session {
            await MainActor.run {
                self.userEmail = session.user.email ?? ""
            }
        }
    }
    
    private func sendContactMessage() async {
        guard !loading else { return }
        guard !userEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await MainActor.run {
                self.error = "We couldn’t detect your account email. Please sign out and sign in again."
            }
            return
        }
        
        loading = true
        error = nil
        defer { loading = false }
        
        let client = SupabaseManager.shared.client
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        
        struct ContactInsert: Encodable {
            let user_email: String
            let subject: String
            let message: String
        }
        
        let payload = ContactInsert(
            user_email: userEmail,
            subject: selectedSubject,
            message: trimmedMessage
        )
        
        do {
            _ = try await client
                .from("contact_messages")
                .insert(payload)
                .execute()
            
            await BannerAction.showSuccessAndDismiss(
                "Message sent! We’ll review it shortly. 💬",
                banner: $banner,
                dismiss: dismiss
            )
        } catch {
            print("🔴 Contact support error:", error.localizedDescription)
            await MainActor.run {
                self.error = "Couldn’t send your message. Please try again."
            }
        }
    }
}
