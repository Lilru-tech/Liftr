import Foundation
import XCTest

enum UITestCredentials {
    private static let envFileCandidates = [
        "scripts/ci/.ui-test.env",
        "scripts/ci/.branch.env",
        "../scripts/ci/.ui-test.env",
        "../scripts/ci/.branch.env",
    ]

    private static let fileValues: [String: String] = {
        for path in envFileCandidates {
            let url = URL(fileURLWithPath: path)
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let parsed = parseEnvFile(content)
            if !parsed.isEmpty {
                return parsed
            }
        }
        return [:]
    }()

    private static func value(for key: String) -> String {
        let env = ProcessInfo.processInfo.environment
        if let v = env[key], !v.isEmpty { return v }
        if let v = fileValues[key], !v.isEmpty { return v }
        return ""
    }

    private static func parseEnvFile(_ content: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let separator = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<separator])
            var rawValue = String(trimmed[trimmed.index(after: separator)...])
            if rawValue.hasPrefix("\"") && rawValue.hasSuffix("\"") && rawValue.count >= 2 {
                rawValue = String(rawValue.dropFirst().dropLast())
            }
            values[key] = rawValue
        }
        return values
    }

    static var email: String {
        value(for: "UI_TEST_EMAIL")
    }

    static var password: String {
        value(for: "UI_TEST_PASSWORD")
    }

    static var supabaseURL: String {
        value(for: "SUPABASE_URL")
    }

    static var supabaseAnonKey: String {
        let direct = value(for: "SUPABASE_ANON_KEY")
        if !direct.isEmpty { return direct }
        return value(for: "ANON_KEY")
    }

    static var isConfigured: Bool {
        !email.isEmpty && !password.isEmpty && !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty
    }
}
