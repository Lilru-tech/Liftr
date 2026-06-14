import Supabase
import Foundation

class SupabaseManager {
    static let shared = SupabaseManager()
    private let supabaseURL = URL(string: "https://rjzhaafvkxmvlnpsikbi.supabase.co")!
    var supabasePublicStorageBase: String {
        "\(supabaseURL.absoluteString)/storage/v1/object/public"
    }
    private let supabaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJqemhhYWZ2a3htdmxucHNpa2JpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjA0NDY4OTQsImV4cCI6MjA3NjAyMjg5NH0.eQt6M6riyj9-wCwQp2JE_KfgKoE7Wv3Xj64NLjCa6Jg"
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
