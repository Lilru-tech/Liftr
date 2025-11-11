import Supabase
import Realtime
import Foundation
import UIKit

final class SupabaseManager {
    static let shared = SupabaseManager()

    private let supabaseURL = URL(string: "https://rjzhaafvkxmvlnpsikbi.supabase.co")!
    private let supabaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJqemhhYWZ2a3htdmxucHNpa2JpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjA0NDY4OTQsImV4cCI6MjA3NjAyMjg5NH0.eQt6M6riyj9-wCwQp2JE_KfgKoE7Wv3Xj64NLjCa6Jg"

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(supabaseURL: supabaseURL, supabaseKey: supabaseKey)

        Task.detached { [client] in
            // 1) Sesión inicial
            let session = try? await client.auth.session
            await client.realtimeV2.setAuth(session?.accessToken ?? "")
            print("[RT] setAuth boot ->", session == nil ? "anon" : "user")
            if let uid = try? await client.auth.user().id.uuidString {
                print("[RT] boot user_id=\(uid)")
            }
            if let tok = session?.accessToken {
                print("[RT] boot jwt.prefix=\(tok.prefix(20))")
            }

            // 2) Conecta socket UNA VEZ, tras setAuth
            await client.realtimeV2.connect()
            print("[RT] connect() boot")
            
            if let tok = session?.accessToken {
                print("[RT] boot jwt.prefix=\(tok.prefix(20))")
                #if DEBUG
                UIPasteboard.general.string = tok
                print("[AUTH] Copiado JWT al portapapeles (boot)")
                #endif
            }
        }

        Task.detached { [weak client] in
            guard let client else { return }
            for await (event, session) in client.auth.authStateChanges {
                print("[AUTH] event=\(event) hasSession=\(session != nil)")
                await client.realtimeV2.setAuth(session?.accessToken ?? "")
                if let tok = session?.accessToken {
                    print("[RT] auth-change jwt.prefix=\(tok.prefix(20))")
                    #if DEBUG
                    UIPasteboard.general.string = tok
                    print("[AUTH] Copiado JWT al portapapeles (auth-change)")
                    #endif
                }

                switch event {
                case .signedIn, .tokenRefreshed:
                    await client.realtimeV2.connect()
                    print("[RT] connect() after \(event)")
                case .signedOut, .userDeleted:
                    await client.realtimeV2.disconnect()
                    print("[RT] disconnect() after \(event)")
                default:
                    // otros: passwordRecovery, userUpdated...
                    await client.realtimeV2.connect()
                    print("[RT] connect() after \(event)")
                }
            }
        }
    }
}
