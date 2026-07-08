import Foundation

/// A snapshot of claude.ai plan usage, mirroring what claude.ai/settings/usage
/// shows: the rolling 5-hour session window and the 7-day weekly window.
struct ClaudeUsage: Equatable {
    var sessionPercent: Int?
    var sessionResetsAt: Date?
    var weeklyPercent: Int?
    var weeklyResetsAt: Date?
    var fetchedAt: Date
}

/// Claude service health, read from the public Claude status page.
struct ClaudeServiceStatus: Equatable {
    var operational: Bool
    var message: String
    var checkedAt: Date
}

enum UsageError: Error, LocalizedError {
    case missingCredentials
    case sessionExpired
    case network(URLError)
    case serverError(Int)
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Add your session key and organization ID in Settings to see usage."
        case .sessionExpired:
            return "Session key expired or invalid -- sign in again from Settings."
        case .network(let error):
            return "Network error while fetching usage: \(error.localizedDescription)"
        case .serverError(let code):
            return "claude.ai returned an error while fetching usage (HTTP \(code))."
        case .unexpectedResponse:
            return "Couldn't read usage data -- claude.ai's usage API may have changed."
        }
    }
}

/// Fetches claude.ai plan usage and Claude service status. Reads the same
/// internal endpoint that backs claude.ai/settings/usage (the approach used
/// by ClaudeUsageBar and similar menu bar trackers), authenticated with the
/// session key cookie this app already stores for pinging.
enum UsageChecker {
    static func fetchUsage(sessionKey: String, organizationID: String) async throws -> ClaudeUsage {
        let trimmedKey = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOrg = organizationID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, !trimmedOrg.isEmpty else {
            throw UsageError.missingCredentials
        }
        guard let url = URL(string: "https://claude.ai/api/organizations/\(trimmedOrg)/usage") else {
            throw UsageError.unexpectedResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://claude.ai/settings/usage", forHTTPHeaderField: "Referer")
        request.setValue("sessionKey=\(trimmedKey)", forHTTPHeaderField: "Cookie")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            throw UsageError.network(error)
        } catch {
            throw UsageError.unexpectedResponse
        }
        guard let http = response as? HTTPURLResponse else {
            throw UsageError.unexpectedResponse
        }
        switch http.statusCode {
        case 200...299:
            break
        case 401, 403:
            throw UsageError.sessionExpired
        default:
            throw UsageError.serverError(http.statusCode)
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageError.unexpectedResponse
        }
        let session = usageWindow(in: object, keys: ["five_hour", "fiveHour", "session"])
        let weekly = usageWindow(in: object, keys: ["seven_day", "sevenDay", "seven_day_all_models", "weekly"])
        guard session != nil || weekly != nil else {
            throw UsageError.unexpectedResponse
        }
        return ClaudeUsage(
            sessionPercent: session?.percent,
            sessionResetsAt: session?.resetsAt,
            weeklyPercent: weekly?.percent,
            weeklyResetsAt: weekly?.resetsAt,
            fetchedAt: Date()
        )
    }

    /// Never throws -- service status is informational and must not break the
    /// usage display when the status page is unreachable.
    static func fetchServiceStatus() async -> ClaudeServiceStatus? {
        for host in ["https://status.claude.com", "https://status.anthropic.com"] {
            guard let url = URL(string: "\(host)/api/v2/status.json") else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            guard
                let (data, response) = try? await URLSession.shared.data(for: request),
                let http = response as? HTTPURLResponse,
                (200...299).contains(http.statusCode),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let status = object["status"] as? [String: Any],
                let indicator = status["indicator"] as? String
            else { continue }
            let operational = indicator.lowercased() == "none"
            let message = operational
                ? "All Claude services operational"
                : ((status["description"] as? String) ?? "Claude is reporting service issues")
            return ClaudeServiceStatus(operational: operational, message: message, checkedAt: Date())
        }
        return nil
    }

    /// Fetches the account's organization UUID straight from claude.ai using
    /// the captured session key. Used right after login as a fallback when
    /// the `lastActiveOrg` cookie hasn't been set yet, so signing in always
    /// captures everything the app needs. Never throws -- returns nil and
    /// lets the manual Settings field handle it.
    static func fetchOrganizationID(sessionKey: String) async -> String? {
        let trimmedKey = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, let url = URL(string: "https://claude.ai/api/organizations") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://claude.ai/settings/usage", forHTTPHeaderField: "Referer")
        request.setValue("sessionKey=\(trimmedKey)", forHTTPHeaderField: "Cookie")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")
        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse,
            (200...299).contains(http.statusCode),
            let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }
        // Some responses are the organizations themselves; others wrap them
        // in membership objects. Prefer an org with chat capability.
        func uuid(of item: [String: Any]) -> String? {
            (item["uuid"] as? String) ?? ((item["organization"] as? [String: Any])?["uuid"] as? String)
        }
        func capabilities(of item: [String: Any]) -> [String] {
            (item["capabilities"] as? [String])
                ?? ((item["organization"] as? [String: Any])?["capabilities"] as? [String])
                ?? []
        }
        let preferred = array.first { capabilities(of: $0).contains("chat") } ?? array.first
        return preferred.flatMap { uuid(of: $0) }
    }

    // MARK: - Tolerant JSON parsing

    private struct UsageWindow {
        var percent: Int?
        var resetsAt: Date?
    }

    private static func usageWindow(in object: [String: Any], keys: [String]) -> UsageWindow? {
        for key in keys {
            guard let dict = object[key] as? [String: Any] else { continue }
            let percent = percentValue(dict["utilization"])
                ?? percentValue(dict["percentage"])
                ?? percentValue(dict["percent_used"])
            let resets = dateValue(dict["resets_at"])
                ?? dateValue(dict["reset_at"])
                ?? dateValue(dict["resetsAt"])
            if percent != nil || resets != nil {
                return UsageWindow(percent: percent, resetsAt: resets)
            }
        }
        return nil
    }

    /// claude.ai reports utilization as a 0-100 number; numeric strings are
    /// also accepted. Clamped to 0...100.
    private static func percentValue(_ raw: Any?) -> Int? {
        let number: Double?
        if let value = raw as? Double {
            number = value
        } else if let value = raw as? Int {
            number = Double(value)
        } else if let text = raw as? String, let value = Double(text) {
            number = value
        } else {
            number = nil
        }
        guard let number else { return nil }
        return max(0, min(100, Int(number.rounded())))
    }

    private static func dateValue(_ raw: Any?) -> Date? {
        if let seconds = raw as? Double, seconds > 1_000_000_000 {
            return Date(timeIntervalSince1970: seconds)
        }
        if let text = raw as? String {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: text) { return date }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            return plain.date(from: text)
        }
        return nil
    }
}
