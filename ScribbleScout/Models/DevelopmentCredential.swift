import Foundation

/// Read launch-time credentials only in development; never embed a key in a build setting or resource.
enum DevelopmentCredential {
    static func apiKey(in environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        #if DEBUG
        let key = (environment["OPENAI_API_KEY"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return key.rangeOfCharacter(from: .whitespacesAndNewlines) == nil ? key : ""
        #else
        return ""
        #endif
    }
}
