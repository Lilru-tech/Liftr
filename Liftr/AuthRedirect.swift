import Foundation
import os

enum AuthCallbackLogger {
    private static let prefix = "[AuthCallback]"
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Liftr", category: "AuthCallback")

    static func log(_ message: String, url: URL? = nil, source: String = "") {
        var parts: [String] = [prefix]
        if !source.isEmpty {
            parts.append("[\(source)]")
        }
        parts.append(message)
        if let url {
            parts.append("url=\(describe(url))")
        }
        let line = parts.joined(separator: " ")
        print(line)
        logger.info("\(line, privacy: .public)")
    }

    static func describe(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if var items = components?.queryItems {
            for index in items.indices where items[index].name == "code" {
                items[index].value = "<redacted>"
            }
            components?.queryItems = items
        }
        if let fragment = components?.fragment, fragment.contains("code=") {
            components?.fragment = "<redacted>"
        }
        return components?.string ?? url.absoluteString
    }

    static func describeMatch(_ url: URL) -> String {
        let scheme = url.scheme ?? "nil"
        let host = url.host ?? "nil"
        let path = url.path.isEmpty ? "/" : url.path
        let matched = AuthRedirect.isAuthCallback(url)
        return "scheme=\(scheme) host=\(host) path=\(path) isAuthCallback=\(matched)"
    }
}

enum AuthRedirect {
    static let scheme = "com.davidgomez.Liftr"
    static let host = "auth-callback"

    static let webCallbackHost = "settleit-auth.vercel.app"
    static let webCallbackPath = "/auth/callback"

    static var appDeepLinkURL: URL {
        URL(string: "\(scheme)://\(host)")!
    }

    static var webCallbackURL: URL {
        URL(string: "https://\(webCallbackHost)\(webCallbackPath)")!
    }

    static func isAuthCallback(_ url: URL) -> Bool {
        guard url.scheme?.caseInsensitiveCompare(scheme) == .orderedSame else { return false }
        if url.host?.caseInsensitiveCompare(host) == .orderedSame { return true }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.caseInsensitiveCompare(host) == .orderedSame
    }
}

enum PasswordResetValidation {
    static let minimumLength = 8

    static func passwordsMatch(_ password: String, _ confirm: String) -> Bool {
        password == confirm
    }

    static func isPasswordValid(_ password: String) -> Bool {
        password.count >= minimumLength
    }
}
