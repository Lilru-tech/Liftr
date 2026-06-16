import XCTest

enum UITestCredentials {
    static var email: String {
        let env = ProcessInfo.processInfo.environment
        return env["UI_TEST_EMAIL"] ?? ""
    }

    static var password: String {
        let env = ProcessInfo.processInfo.environment
        return env["UI_TEST_PASSWORD"] ?? ""
    }

    static var supabaseURL: String {
        let env = ProcessInfo.processInfo.environment
        return env["SUPABASE_URL"] ?? ""
    }

    static var supabaseAnonKey: String {
        let env = ProcessInfo.processInfo.environment
        return env["SUPABASE_ANON_KEY"] ?? env["ANON_KEY"] ?? ""
    }

    static var isConfigured: Bool {
        !email.isEmpty && !password.isEmpty && !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty
    }
}
