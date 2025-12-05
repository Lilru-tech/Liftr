import Foundation
import Supabase

@MainActor
final class NotificationTokenUploader {

    static let shared = NotificationTokenUploader()

    private init() {}

    func updateFcmToken(_ token: String) async {
        let client = SupabaseManager.shared.client

        guard let user = client.auth.currentUser else {
            print("⚠️ No hay usuario autenticado, no guardo fcm_token")
            return
        }

        do {
            try await client
                .from("profiles")
                .update(["fcm_token": token])
                .eq("user_id", value: user.id)
                .execute()

            print("✅ fcm_token actualizado en Supabase para user_id \(user.id)")
        } catch {
            print("❌ Error actualizando fcm_token en Supabase:", error)
        }
    }
}
