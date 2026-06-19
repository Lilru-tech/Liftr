import Foundation

enum SupabaseRuntimeConfig {
    private static let defaultURLString = "https://rjzhaafvkxmvlnpsikbi.supabase.co"
    private static let defaultAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJqemhhYWZ2a3htdmxucHNpa2JpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjA0NDY4OTQsImV4cCI6MjA3NjAyMjg5NH0.eQt6M6riyj9-wCwQp2JE_KfgKoE7Wv3Xj64NLjCa6Jg"

    static var url: URL {
        let env = ProcessInfo.processInfo.environment
        if let raw = env["SUPABASE_URL"], !raw.isEmpty, let parsed = URL(string: raw) {
            return parsed
        }
        return URL(string: defaultURLString)!
    }

    static var anonKey: String {
        let env = ProcessInfo.processInfo.environment
        if let key = env["SUPABASE_ANON_KEY"], !key.isEmpty {
            return key
        }
        if let key = env["ANON_KEY"], !key.isEmpty {
            return key
        }
        return defaultAnonKey
    }
}
