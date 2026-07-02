import Foundation

/// Minimal encodable JSON tree — used to express `output_config` schemas.
indirect enum JSONValue: Encodable, Equatable {
    case string(String)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

struct MessagesRequestBody: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct OutputConfig: Encodable {
        struct Format: Encodable {
            let type: String
            let schema: JSONValue
        }

        let format: Format
    }

    let model: String
    let maxTokens: Int
    let messages: [Message]
    let outputConfig: OutputConfig

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case messages
        case outputConfig = "output_config"
    }
}

/// One typed Messages API call: how to build the body and what JSON comes back.
protocol AnthropicRequest: Sendable {
    associatedtype Response: Decodable & Sendable
    var body: MessagesRequestBody { get }
}

enum AnthropicClientError: LocalizedError, Equatable {
    /// Non-success HTTP status after retries; `type`/`message` from the API error envelope when present.
    case apiError(status: Int, type: String?, message: String?)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .apiError(let status, let type, let message):
            "Anthropic API error \(status)\(type.map { " (\($0))" } ?? "")\(message.map { ": \($0)" } ?? "")"
        case .invalidResponse(let detail):
            "Unexpected Anthropic API response: \(detail)"
        }
    }
}

/// Typed Messages API client. Retries 429/500/529 (honoring `retry-after`),
/// fails fast on other 4xx. The API key travels only in the `x-api-key`
/// header — never log requests or the key itself.
struct AnthropicClient: Sendable {
    struct Configuration: Sendable {
        var endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
        var apiVersion = "2023-06-01"
        var maxRetries = 2
        var fallbackRetryDelay: TimeInterval = 1
    }

    private struct MessagesResponse: Decodable {
        struct ContentBlock: Decodable {
            let type: String
            let text: String?
        }

        let content: [ContentBlock]
        let stopReason: String?

        enum CodingKeys: String, CodingKey {
            case content
            case stopReason = "stop_reason"
        }
    }

    private struct ErrorEnvelope: Decodable {
        struct Detail: Decodable {
            let type: String
            let message: String
        }

        let error: Detail
    }

    private let apiKey: String
    private let configuration: Configuration
    private let session: URLSession
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    init(
        apiKey: String,
        configuration: Configuration = Configuration(),
        session: URLSession = .shared,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
            try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000))
        }
    ) {
        self.apiKey = apiKey
        self.configuration = configuration
        self.session = session
        self.sleep = sleep
    }

    func send<Request: AnthropicRequest>(_ request: Request) async throws -> Request.Response {
        let urlRequest = try makeURLRequest(for: request.body)

        var attempt = 0
        while true {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                throw AnthropicClientError.invalidResponse("not an HTTP response")
            }

            if (200..<300).contains(http.statusCode) {
                return try decodeResponse(from: data)
            }

            let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            let isRetryable = [429, 500, 529].contains(http.statusCode)
            if isRetryable && attempt < configuration.maxRetries {
                attempt += 1
                try await sleep(retryDelay(from: http))
                continue
            }
            throw AnthropicClientError.apiError(
                status: http.statusCode,
                type: envelope?.error.type,
                message: envelope?.error.message
            )
        }
    }

    private func makeURLRequest(for body: MessagesRequestBody) throws -> URLRequest {
        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(configuration.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func decodeResponse<Response: Decodable>(from data: Data) throws -> Response {
        let messages: MessagesResponse
        do {
            messages = try JSONDecoder().decode(MessagesResponse.self, from: data)
        } catch {
            throw AnthropicClientError.invalidResponse("undecodable envelope: \(error.localizedDescription)")
        }
        if messages.stopReason == "refusal" {
            throw AnthropicClientError.invalidResponse("model refused the request")
        }
        guard let text = messages.content.first(where: { $0.type == "text" })?.text else {
            throw AnthropicClientError.invalidResponse("no text content block")
        }
        do {
            return try JSONDecoder().decode(Response.self, from: Data(text.utf8))
        } catch {
            throw AnthropicClientError.invalidResponse("content does not match schema: \(error.localizedDescription)")
        }
    }

    private func retryDelay(from response: HTTPURLResponse) -> TimeInterval {
        if let header = response.value(forHTTPHeaderField: "retry-after"),
           let seconds = TimeInterval(header), seconds > 0 {
            return seconds
        }
        return configuration.fallbackRetryDelay
    }
}
