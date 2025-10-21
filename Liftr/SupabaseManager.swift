import Supabase
import Foundation

class SupabaseManager {
    static let shared = SupabaseManager()
    private let supabaseURL = URL(string: "https://rjzhaafvkxmvlnpsikbi.supabase.co")!
    private let supabaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJqemhhYWZ2a3htdmxucHNpa2JpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjA0NDY4OTQsImV4cCI6MjA3NjAyMjg5NH0.eQt6M6riyj9-wCwQp2JE_KfgKoE7Wv3Xj64NLjCa6Jg"
    lazy var client: SupabaseClient = {
        return SupabaseClient(supabaseURL: supabaseURL, supabaseKey: supabaseKey)
    }()
}
