import Supabase
import Foundation

class SupabaseManager {
    static let shared = SupabaseManager()
    private let supabaseURL = SupabaseRuntimeConfig.url
    var supabasePublicStorageBase: String {
        "\(supabaseURL.absoluteString)/storage/v1/object/public"
    }
    private let supabaseKey = SupabaseRuntimeConfig.anonKey
    lazy var client: SupabaseClient = {
        SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: supabaseKey,
            options: SupabaseClientOptions(
                auth: .init(redirectToURL: AuthRedirect.webCallbackURL)
            )
        )
    }()
}

func isBenignFetchCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if Task.isCancelled { return true }
    if let urlError = error as? URLError, urlError.code == .cancelled { return true }
    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return true }
    return error.localizedDescription.compare("cancelled", options: .caseInsensitive) == .orderedSame
}
