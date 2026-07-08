import Foundation

/// Where this app checks for new releases: the public GitHub Releases API
/// for this repo. Each release must be tagged like "v1.5.0" and have a
/// zipped app bundle attached as an asset named `assetName` below --
/// `Scripts/release.sh` builds and publishes that automatically. Because the
/// repo is public, no token or auth is needed to read releases.
enum UpdateFeed {
    static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/proxsyi/ClaudeSessionPinger/releases/latest")!
    static let assetName = "ClaudeSessionPinger.app.zip"
}

struct UpdateInfo: Equatable {
    let version: String
    let releasePageURL: String
    let notes: String?
    /// GitHub API URL for the release asset itself -- fetching it requires
    /// the same auth token and an `Accept: application/octet-stream` header.
    /// See `Updater.swift`.
    let assetAPIURL: String
}

enum UpdateCheckResult: Equatable {
    case upToDate
    case updateAvailable(UpdateInfo)
    case failed(String)
}

private struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let url: String
    }
    let tag_name: String
    let html_url: String
    let body: String?
    let assets: [Asset]
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
        do {
            var request = URLRequest(url: UpdateFeed.latestReleaseAPIURL)
            request.timeoutInterval = 15
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failed("Couldn't reach GitHub.")
            }
            guard (200...299).contains(http.statusCode) else {
                if http.statusCode == 404 {
                    return .failed("No releases found yet.")
                }
                return .failed("GitHub returned an unexpected response (\(http.statusCode)).")
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
            guard isNewer(version, than: currentVersion) else {
                return .upToDate
            }
            guard let asset = release.assets.first(where: { $0.name == UpdateFeed.assetName }) else {
                return .failed("Release \(release.tag_name) is missing its \(UpdateFeed.assetName) asset.")
            }
            let info = UpdateInfo(version: version, releasePageURL: release.html_url, notes: release.body, assetAPIURL: asset.url)
            return .updateAvailable(info)
        } catch {
            return .failed("Couldn't check for updates: \(error.localizedDescription)")
        }
    }
}
