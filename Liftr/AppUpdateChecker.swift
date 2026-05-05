import Foundation

struct AppUpdatePrompt: Sendable {
    let latestVersion: String
    let storeURL: URL
}

actor AppUpdateChecker {
    static let shared = AppUpdateChecker()

    private let appStoreBundleId = "com.davidgomez.Liftr"
    private let lookupCountries = ["es", "us"]

    private let defaults = UserDefaults.standard
    private let minCheckInterval: TimeInterval = 60 * 60 * 24
    private let minPromptInterval: TimeInterval = 60 * 60 * 24

    private let lastCheckDateKey = "app_update_last_check_date"
    private let lastPromptDateKey = "app_update_last_prompt_date"
    private let lastPromptVersionKey = "app_update_last_prompt_version"

    func checkForRecommendedUpdate() async -> AppUpdatePrompt? {
        let now = Date()
        if let last = defaults.object(forKey: lastCheckDateKey) as? Date,
           now.timeIntervalSince(last) < minCheckInterval {
            return nil
        }
        defaults.set(now, forKey: lastCheckDateKey)

        guard let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return nil
        }

        let runtimeBundleId = Bundle.main.bundleIdentifier
        let bundleId = (runtimeBundleId?.isEmpty == false) ? runtimeBundleId! : appStoreBundleId

        guard let storeResult = await fetchStoreVersion(bundleId: bundleId) else {
            return nil
        }
        guard Self.isVersion(storeResult.version, newerThan: currentVersion) else {
            return nil
        }

        if !shouldPrompt(for: storeResult.version, now: now) {
            return nil
        }

        defaults.set(now, forKey: lastPromptDateKey)
        defaults.set(storeResult.version, forKey: lastPromptVersionKey)
        return AppUpdatePrompt(latestVersion: storeResult.version, storeURL: storeResult.url)
    }

    private func shouldPrompt(for version: String, now: Date) -> Bool {
        let lastVersion = defaults.string(forKey: lastPromptVersionKey)
        let lastDate = defaults.object(forKey: lastPromptDateKey) as? Date

        if lastVersion == version,
           let lastDate,
           now.timeIntervalSince(lastDate) < minPromptInterval {
            return false
        }
        return true
    }

    private func fetchStoreVersion(bundleId: String) async -> (version: String, url: URL)? {
        let bundleIdsToTry = bundleId == appStoreBundleId ? [bundleId] : [bundleId, appStoreBundleId]

        for currentBundleId in bundleIdsToTry {
            for country in lookupCountries {
                guard let url = lookupURL(bundleId: currentBundleId, country: country) else { continue }
                if let app = await fetchFirstResult(from: url),
                   let parsed = parseStoreResult(app) {
                    return parsed
                }
            }
            if let url = lookupURL(bundleId: currentBundleId, country: nil),
               let app = await fetchFirstResult(from: url),
               let parsed = parseStoreResult(app) {
                return parsed
            }
        }
        return nil
    }

    private func lookupURL(bundleId: String, country: String?) -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        var items = [URLQueryItem(name: "bundleId", value: bundleId)]
        if let country {
            items.append(URLQueryItem(name: "country", value: country))
        }
        components?.queryItems = items
        return components?.url
    }

    private func fetchFirstResult(from url: URL) async -> ItunesAppRecord? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(ItunesLookupResponse.self, from: data)
            return decoded.results.first
        } catch {
            return nil
        }
    }

    private func parseStoreResult(_ app: ItunesAppRecord) -> (version: String, url: URL)? {
        if let trackViewURL = app.trackViewUrl, let url = URL(string: trackViewURL) {
            return (app.version, url)
        }
        if let trackId = app.trackId,
           let fallbackURL = URL(string: "https://apps.apple.com/app/id\(trackId)") {
            return (app.version, fallbackURL)
        }
        return nil
    }

    private static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(left.count, right.count)

        for idx in 0 ..< count {
            let a = idx < left.count ? left[idx] : 0
            let b = idx < right.count ? right[idx] : 0
            if a != b { return a > b }
        }
        return false
    }
}

private struct ItunesLookupResponse: Decodable {
    let results: [ItunesAppRecord]
}

private struct ItunesAppRecord: Decodable {
    let version: String
    let trackViewUrl: String?
    let trackId: Int?
}
