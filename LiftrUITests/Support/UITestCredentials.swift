import XCTest

enum UITestCredentials {
    private static func readFromLaunchEnvironment(_ key: String) -> String? {
        let env = ProcessInfo.processInfo.environment
        if let v = env[key], !v.isEmpty { return v }
        let launch = CommandLine.arguments
        let prefix = "\(key)="
        if let arg = launch.first(where: { $0.hasPrefix(prefix) }) {
            let value = String(arg.dropFirst(prefix.count))
            return value.isEmpty ? nil : value
        }
        return nil
    }

    static var email: String {
        readFromLaunchEnvironment("UI_TEST_EMAIL") ?? ""
    }

    static var password: String {
        readFromLaunchEnvironment("UI_TEST_PASSWORD") ?? ""
    }

    static var supabaseURL: String {
        readFromLaunchEnvironment("SUPABASE_URL") ?? ""
    }

    static var supabaseAnonKey: String {
        readFromLaunchEnvironment("SUPABASE_ANON_KEY") ?? readFromLaunchEnvironment("ANON_KEY") ?? ""
    }

    static var isConfigured: Bool {
        !email.isEmpty && !password.isEmpty && !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty
    }
}
