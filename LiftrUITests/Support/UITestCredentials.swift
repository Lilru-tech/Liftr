import Foundation
import XCTest

enum UITestCredentials {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let envFileCandidates: [URL] = {
        var candidates: [URL] = []
        let ciDirectory = repoRoot.appendingPathComponent("scripts/ci")
        candidates.append(ciDirectory.appendingPathComponent(".ui-test.env"))
        candidates.append(ciDirectory.appendingPathComponent(".branch.env"))

        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        for _ in 0..<8 {
            let ci = directory.appendingPathComponent("scripts/ci")
            candidates.append(ci.appendingPathComponent(".ui-test.env"))
            candidates.append(ci.appendingPathComponent(".branch.env"))
            if directory.pathComponents.count <= 1 {
                break
            }
            directory = directory.deletingLastPathComponent()
        }

        return candidates
    }()

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

    private static let fileValues: [String: String] = {
        for url in envFileCandidates {
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

    static var email: String {
        value(for: "UI_TEST_EMAIL")
    }

    static var password: String {
        value(for: "UI_TEST_PASSWORD")
    }

    static var signupEmail: String {
        value(for: "UI_TEST_SIGNUP_EMAIL")
    }

    static var signupUsername: String {
        value(for: "UI_TEST_SIGNUP_USERNAME")
    }

    static var signupPassword: String {
        let configured = value(for: "UI_TEST_SIGNUP_PASSWORD")
        return configured.isEmpty ? "12345678" : configured
    }

    static var isSignupConfigured: Bool {
        !signupEmail.isEmpty && !signupUsername.isEmpty
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
