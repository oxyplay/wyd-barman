import Foundation

enum WydError: Error {
    case notFound
    case incompatible(wydVersion: String?)
    case timeout(what: String)
    case actionFailed(summary: String, detail: String?)
    case decodeFailed(detail: String)
    case staleTarget(target: String)
}

extension WydError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "wyd not found"
        case .incompatible:
            return "wyd needs to be updated"
        case .timeout(let what):
            return "\(what) timed out"
        case .actionFailed(let summary, _):
            return summary
        case .decodeFailed:
            return "Could not read wyd output."
        case .staleTarget:
            return "That resource changed. Refreshed."
        }
    }
}
