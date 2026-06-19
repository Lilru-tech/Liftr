enum AppConfig {
    static var supabaseUrl: String { SupabaseRuntimeConfig.url.absoluteString }
    static var supabaseAnonKey: String { SupabaseRuntimeConfig.anonKey }
}
