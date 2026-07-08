import Foundation

enum ClaudeClient {
    static func sendPing(
        sessionKey: String,
        organizationID: String,
        model: String,
        message: String,
        cookieHeader: String? = nil,
        timeoutSeconds: TimeInterval = 30
    ) async throws -> PingOutcome {
        let trimmedKey = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOrg = organizationID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, !trimmedOrg.isEmpty, !trimmedModel.isEmpty else {
            throw PingError.missingCredentials
        }
        guard let baseURL = URL(string: "https://claude.ai/api/organizations/\(trimmedOrg)") else {
            throw PingError.invalidURL
        }

        let conversationID = UUID().uuidString.lowercased()
        let createURL = baseURL.appendingPathComponent("chat_conversations")
        var createRequest = URLRequest(url: createURL)
        createRequest.httpMethod = "POST"
        createRequest.timeoutInterval = timeoutSeconds
        applyCommonHeaders(&createRequest, sessionKey: trimmedKey, cookieHeader: cookieHeader)
        createRequest.httpBody = try JSONSerialization.data(withJSONObject: ["uuid": conversationID, "name": ""])

        let (createData, createResponse) = try await perform(createRequest)
        try validate(response: createResponse, data: createData)

        let completionURL = baseURL
            .appendingPathComponent("chat_conversations")
            .appendingPathComponent(conversationID)
            .appendingPathComponent("completion")
        var completionRequest = URLRequest(url: completionURL)
        completionRequest.httpMethod = "POST"
        completionRequest.timeoutInterval = timeoutSeconds
        applyCommonHeaders(&completionRequest, sessionKey: trimmedKey, cookieHeader: cookieHeader)
        let payload: [String: Any] = [
            "prompt": message,
            "timezone": TimeZone.current.identifier,
            "attachments": [],
            "files": [],
            "rendering_mode": "messages",
            "model": trimmedModel
        ]
        completionRequest.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (completionData, completionResponse) = try await perform(completionRequest)
        try validate(response: completionResponse, data: completionData)

        let replyText = parseCompletionStream(completionData).trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = replyText.contains("1")
        return PingOutcome(conversationID: conversationID, replyText: replyText, matchedExpected: matched)
    }

    private static func applyCommonHeaders(_ request: inout URLRequest, sessionKey: String, cookieHeader: String? = nil) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://claude.ai/new", forHTTPHeaderField: "Referer")
        // Send the full captured login cookies when available so requests
        // look exactly like the browser session; fall back to the bare key.
        let cookies = (cookieHeader?.isEmpty == false) ? cookieHeader! : "sessionKey=\(sessionKey)"
        request.setValue(cookies, forHTTPHeaderField: "Cookie")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")
    }

    private static func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            throw PingError.network(error)
        } catch let error as PingError {
            throw error
        } catch {
            throw PingError.unknown(error)
        }
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw PingError.unexpectedResponse("No HTTP response received")
        }
        switch http.statusCode {
        case 200...299:
            return
        case 401, 403:
            throw PingError.sessionExpired
        case 429:
            throw PingError.rateLimited
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            throw PingError.serverError(http.statusCode, body)
        }
    }

    private static func parseCompletionStream(_ data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8) else { return "" }
        var combined = ""
        for line in text.components(separatedBy: "\n") {
            guard line.hasPrefix("data:") else { continue }
            let jsonPart = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            guard !jsonPart.isEmpty, let jsonData = jsonPart.data(using: .utf8) else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { continue }
            if let completion = object["completion"] as? String {
                combined += completion
            } else if let delta = object["delta"] as? [String: Any], let deltaText = delta["text"] as? String {
                combined += deltaText
            }
        }
        return combined
    }
}
