import Foundation

enum PingError: LocalizedError {
    case missingCredentials
    case invalidURL
    case network(URLError)
    case sessionExpired
    case rateLimited
    case serverError(Int, String)
    case unexpectedResponse(String)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Session key, organization ID, or model is missing. Open Settings to add them."
        case .invalidURL:
            return "Could not build a valid request URL. Check the organization ID."
        case .network(let urlError):
            return "Network error: \(urlError.localizedDescription)"
        case .sessionExpired:
            return "Session key looks expired or invalid. Grab a fresh one from your browser."
        case .rateLimited:
            return "Rate limited by the server. Will try again next scheduled time."
        case .serverError(let code, let body):
            return "Server returned \(code): \(body.prefix(200))"
        case .unexpectedResponse(let details):
            return "Unexpected response: \(details.prefix(200))"
        case .unknown(let error):
            return "Unexpected error: \(error.localizedDescription)"
        }
    }
}
