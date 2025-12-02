import SwiftUI
import Supabase

private struct UpdateProfileBio: Encodable {
    let bio: String?
}

struct EditBioSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var app: AppState
    
    let initialBio: String
    let onSaved: (String) -> Void
    
    @State private var text: String = ""
    @State private var saving = false
    @State private var error: String?
    private let limit = 200
    
    private var editorHeight: CGFloat {
        let lineHeight = UIFont.preferredFont(forTextStyle: .body).lineHeight
        return lineHeight * 6 + 24
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                ZStack {
                    TextEditor(text: $text)
                        .font(.body)
                        .frame(height: editorHeight)
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.2)))
                        .onChange(of: text) { _, new in
                            if new.count > limit { text = String(new.prefix(limit)) }
                        }
                    
                    if text.isEmpty {
                        Text("Tell people a bit about you…")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .allowsHitTesting(false)
                    }
                }
                
                HStack {
                    if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                    Spacer()
                    Text("\(text.count)/\(limit)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .navigationTitle("Edit bio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(saving)
                }
            }
            .task { text = initialBio }
        }
    }
    
    private func save() async {
        guard let uid = app.userId else { return }
        saving = true; defer { saving = false }
        
        do {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let value: String? = {
                let limited = String(trimmed.prefix(limit))
                return limited.isEmpty ? nil : limited
            }()
            
            let payload = UpdateProfileBio(bio: value)
            
            _ = try await SupabaseManager.shared.client
                .from("profiles")
                .update(payload)
                .eq("user_id", value: uid.uuidString)
                .execute()
            
            onSaved(value ?? "")
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
