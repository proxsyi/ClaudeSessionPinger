import Foundation

/// The small JSON file this app polls to learn about new releases, e.g.:
/// { "version": "1.4.0", "url": "https://example.com/releases/1.4.0", "notes": "Bug fixes" }
///
/// NOTE: this doesn't point anywhere real yet -- there's no hosting set up
/// for this app's releases. Update `feedURL` once you have somewhere to
/// publish that JSON file (a GitHub Releases API URL, a raw file on
/// versyi.com, etc). Until then, checks simply fail quietly and the app
/// behaves exactly as if update checking were off.
enum UpdateFeed {
    // Left unset on purpose: there's nowhere real to check yet. Point this
    // at a hosted version.json (a GitHub Releases API URL, a raw file on
    // versyi.com, etc.) once one exists, and checks will start working
    // immediately -- no other code changes needed.
    static let feedURL: URL? = nil
}

struct UpdateInfo: Decodable, Equatable {
    let version: String
    let url: String
    let notes: String?
}

enum UpdateCheckResult: Equatable {
    case upToDate
    case updateAvailable(UpdateInfo)
    case failed(String)
}

enum UpdateChecker {
    /// Compares two dotted version strings numerically (e.g. "1.10.0" > "1.9.3"),
    /// rather than lexicographically, so double-digit components sort correctly.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let candidateParts = candidate.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        guard !candidateParts.isEmpty, !currentParts.isEmpty else { return false }
        let count = max(candidateParts.count, currentParts.count)
        for i in 0..<count {
            let c = i < candidateParts.count ? candidateParts[i] : 0
            let d = i < currentParts.count ? currentParts[i] : 0
            if c != d { return c > d }
        }
        return false
    }

    static func check(currentVersion: String) async -> UpdateCheckResult {
        guard let feedURL = UpdateFeed.feedURL else {
            return .failed("Update checking isn't configured yet.")
        }
        do {
            var request = URLRequest(url: feedURL)
            request.timeoutInterval = 15
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return .failed("Update server returned an unexpected response.")
            }
            let info = try JSONDecoder().decode(UpdateInfo.self, from: data)
            if isNewer(info.version, than: currentVersion) {
                return .updateAvailable(info)
            }
            return .upToDate
        } catch {
            return .failed("Couldn't check for updates: \(error.localizedDescription)")
        }
    }
}
