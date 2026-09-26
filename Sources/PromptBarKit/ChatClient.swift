// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// An error whose message is meant for the result panel as it stands.
public struct PromptError: LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Where requests go and who pays for them.
public struct ModelSettings: Equatable, Sendable {
    public var apiKey: String
    public var baseURL: String
    public var model: String

    public static let defaultBaseURL = "https://openrouter.ai/api/v1"

    public init(apiKey: String, baseURL: String, model: String) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
    }
}

/// Sends one prompt to an OpenAI-compatible chat completions endpoint.
public struct ChatClient: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public static let timeout: TimeInterval = 60

    private let transport: Transport

    public init(transport: @escaping Transport = { try await ChatClient.session.data(for: $0) }) {
        self.transport = transport
    }

    /// A request's timeout only bounds the gaps between bytes; the resource
    /// timeout bounds the whole exchange, as the extension's 60 s abort did.
    public static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = timeout
        return URLSession(configuration: configuration)
    }()

    /// Turns a base URL such as `https://openrouter.ai/api/v1` into its
    /// `/chat/completions` endpoint. Plain HTTP is allowed only for a model
    /// running on this Mac.
    public static func endpoint(for baseURL: String) throws -> URL {
        guard var components = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(), let host = components.host?.lowercased(), !host.isEmpty
        else { throw PromptError("Enter a valid Base URL in Settings.") }
        let isLocal = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
        guard scheme == "https" || (scheme == "http" && isLocal) else {
            throw PromptError("Use HTTPS, or HTTP for a localhost model.")
        }
        if components.user != nil || components.password != nil || components.query != nil || components.fragment != nil {
            throw PromptError("Enter a base URL without credentials, query, or fragment.")
        }
        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix("/chat/completions") { path += "/chat/completions" }
        components.path = path
        guard let url = components.url else { throw PromptError("Enter a valid Base URL in Settings.") }
        return url
    }

    /// Builds the request without sending it, so tests can inspect it.
    public static func request(task: PromptTask, text: String, imageDataURL: String? = nil,
                               settings: ModelSettings) throws -> URLRequest {
        let url = try endpoint(for: settings.baseURL)
        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty, !model.isEmpty else {
            throw PromptError("Set your API Key and Model in Settings.")
        }
        let userContent: Any
        if let imageDataURL {
            userContent = [
                ["type": "text", "text": PromptTask.imageInstruction + text],
                ["type": "image_url", "image_url": ["url": imageDataURL]],
            ]
        } else {
            userContent = text
        }
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": task.systemPrompt + PromptTask.guardSuffix],
                ["role": "user", "content": userContent],
            ],
            "stream": false,
        ]
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    public func generate(_ task: PromptTask, text: String, imageDataURL: String? = nil,
                         settings: ModelSettings) async throws -> String {
        let request = try Self.request(task: task, text: text, imageDataURL: imageDataURL, settings: settings)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw PromptError("Request failed or timed out. Check your endpoint and network.")
        }
        try Task.checkCancellation()
        return try Self.parse(data: data, response: response, sentImage: imageDataURL != nil)
    }

    static func parse(data: Data, response: URLResponse, sentImage: Bool) throws -> String {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let hints: [Int: String] = [
                400: sentImage ? "Check that your model and endpoint support image input." : "Check your model and request settings.",
                401: "Check your API key.",
                402: "Check your provider balance.",
                403: "Check model access.",
                404: "Check the endpoint and model ID.",
                429: "Rate limited. Try again later.",
            ]
            throw PromptError("API error \(status). \(hints[status] ?? "Try again later or check your provider.")")
        }
        struct Completion: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message?
                let finish_reason: String?
            }
            let choices: [Choice]?
        }
        let choice = (try? JSONDecoder().decode(Completion.self, from: data))?.choices?.first
        if choice?.finish_reason == "length" {
            throw PromptError("The model truncated its response. Try a shorter selection.")
        }
        let result = choice?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !result.isEmpty else { throw PromptError("The model returned no text. Check your model settings.") }
        return result
    }
}
