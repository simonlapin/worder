import Foundation
import Testing
@testable import Worder

/// Serves queued responses to URLSession; records outgoing requests.
final class MockURLProtocol: URLProtocol {
    enum Stub {
        case http(status: Int, headers: [String: String] = [:], body: Data)
        case networkError(URLError.Code)
    }

    nonisolated(unsafe) private static var stubs: [Stub] = []
    nonisolated(unsafe) private(set) static var requests: [URLRequest] = []
    private static let lock = NSLock()

    static func reset(stubs: [Stub]) {
        lock.lock()
        defer { lock.unlock() }
        self.stubs = stubs
        requests = []
    }

    static var recordedRequests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    private static func nextStub(recording request: URLRequest) -> Stub? {
        lock.lock()
        defer { lock.unlock() }
        requests.append(request)
        return stubs.isEmpty ? nil : stubs.removeFirst()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let stub = Self.nextStub(recording: request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        switch stub {
        case .http(let status, let headers, let body):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .networkError(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    override func stopLoading() {}
}

struct AnthropicClientTests {
    private static let successBody = Data("""
    {
        "content": [{"type": "text", "text": "{\\"sentences\\": [{\\"en\\": \\"I like my dog.\\", \\"ru\\": \\"Я люблю свою собаку.\\"}]}"}],
        "stop_reason": "end_turn"
    }
    """.utf8)

    private func makeClient(sleeps: SleepRecorder? = nil) -> AnthropicClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return AnthropicClient(
            apiKey: "sk-ant-test",
            session: session,
            sleep: { delay in await sleeps?.record(delay) }
        )
    }

    actor SleepRecorder {
        private(set) var delays: [TimeInterval] = []

        func record(_ delay: TimeInterval) {
            delays.append(delay)
        }
    }

    @Test func successDecodesStructuredContent() async throws {
        MockURLProtocol.reset(stubs: [.http(status: 200, body: Self.successBody)])

        let response = try await makeClient().send(
            SentenceGenerationRequest(word: "dog", translations: ["собака"])
        )

        #expect(response.sentences == [GeneratedSentence(en: "I like my dog.", ru: "Я люблю свою собаку.")])

        let request = try #require(MockURLProtocol.recordedRequests.first)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let bodyData = try #require(request.httpBody ?? request.httpBodyStream.map { stream in
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                guard read > 0 else { break }
                data.append(buffer, count: read)
            }
            return data
        })
        let json = try #require(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        #expect(json["model"] as? String == "claude-haiku-4-5")
        #expect(json["max_tokens"] as? Int == 1024)
        let outputConfig = try #require(json["output_config"] as? [String: Any])
        let format = try #require(outputConfig["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
    }

    @Test func rateLimitRetriesHonoringRetryAfterThenSucceeds() async throws {
        let errorBody = Data(#"{"type":"error","error":{"type":"rate_limit_error","message":"slow down"}}"#.utf8)
        MockURLProtocol.reset(stubs: [
            .http(status: 429, headers: ["retry-after": "7"], body: errorBody),
            .http(status: 200, body: Self.successBody),
        ])
        let sleeps = SleepRecorder()

        let response = try await makeClient(sleeps: sleeps).send(
            SentenceGenerationRequest(word: "dog", translations: ["собака"])
        )

        #expect(response.sentences.count == 1)
        #expect(MockURLProtocol.recordedRequests.count == 2)
        #expect(await sleeps.delays == [7])
    }

    @Test func overloadedRetriesWithFallbackDelayThenFailsTyped() async throws {
        let errorBody = Data(#"{"type":"error","error":{"type":"overloaded_error","message":"overloaded"}}"#.utf8)
        MockURLProtocol.reset(stubs: [
            .http(status: 529, body: errorBody),
            .http(status: 529, body: errorBody),
            .http(status: 529, body: errorBody),
        ])
        let sleeps = SleepRecorder()

        await #expect(throws: AnthropicClientError.apiError(
            status: 529, type: "overloaded_error", message: "overloaded"
        )) {
            try await makeClient(sleeps: sleeps).send(
                SentenceGenerationRequest(word: "dog", translations: ["собака"])
            )
        }
        #expect(MockURLProtocol.recordedRequests.count == 3)
        #expect(await sleeps.delays == [1, 1])
    }

    @Test func clientErrorFailsFastWithoutRetry() async throws {
        let errorBody = Data(#"{"type":"error","error":{"type":"invalid_request_error","message":"bad schema"}}"#.utf8)
        MockURLProtocol.reset(stubs: [.http(status: 400, body: errorBody)])

        await #expect(throws: AnthropicClientError.apiError(
            status: 400, type: "invalid_request_error", message: "bad schema"
        )) {
            try await makeClient().send(SentenceGenerationRequest(word: "dog", translations: ["собака"]))
        }
        #expect(MockURLProtocol.recordedRequests.count == 1)
    }

    @Test func networkErrorPropagates() async throws {
        MockURLProtocol.reset(stubs: [.networkError(.notConnectedToInternet)])

        await #expect(throws: (any Error).self) {
            try await makeClient().send(SentenceGenerationRequest(word: "dog", translations: ["собака"]))
        }
    }

    @Test func malformedContentJSONIsATypedError() async throws {
        let body = Data("""
        {"content": [{"type": "text", "text": "not json"}], "stop_reason": "end_turn"}
        """.utf8)
        MockURLProtocol.reset(stubs: [.http(status: 200, body: body)])

        do {
            _ = try await makeClient().send(SentenceGenerationRequest(word: "dog", translations: ["собака"]))
            Issue.record("expected invalidResponse")
        } catch let error as AnthropicClientError {
            guard case .invalidResponse = error else {
                Issue.record("expected invalidResponse, got \(error)")
                return
            }
        }
    }

    @Test func refusalStopReasonIsATypedError() async throws {
        let body = Data("""
        {"content": [{"type": "text", "text": "{}"}], "stop_reason": "refusal"}
        """.utf8)
        MockURLProtocol.reset(stubs: [.http(status: 200, body: body)])

        do {
            _ = try await makeClient().send(SentenceGenerationRequest(word: "dog", translations: ["собака"]))
            Issue.record("expected invalidResponse")
        } catch let error as AnthropicClientError {
            guard case .invalidResponse = error else {
                Issue.record("expected invalidResponse, got \(error)")
                return
            }
        }
    }
}
