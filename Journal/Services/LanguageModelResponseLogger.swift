//
//  LanguageModelResponseLogger.swift
//  Journal
//

import Foundation

final class LanguageModelResponseRecorder: @unchecked Sendable {
    static let shared = LanguageModelResponseRecorder()

    private let lock = NSLock()
    private var latestResponseData: Data?

    private init() {}

    func reset() {
        lock.withLock {
            latestResponseData = nil
        }
    }

    func record(_ data: Data) {
        lock.withLock {
            latestResponseData = data
        }
    }

    func printLatestOutput() {
        guard let output = latestOutput() else {
            print("Language model output could not be decoded, but no response body was captured.")
            return
        }

        print("""

        ===== UNDECODABLE LANGUAGE MODEL OUTPUT =====
        \(output)
        ===== END LANGUAGE MODEL OUTPUT =====

        """)
    }

    private func latestOutput() -> String? {
        let data = lock.withLock { latestResponseData }
        guard let data else {
            return nil
        }

        if
            let object = try? JSONSerialization.jsonObject(with: data),
            let response = object as? [String: Any],
            let choices = response["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        {
            return content
        }

        return String(data: data, encoding: .utf8)
    }
}

enum LanguageModelRecordingSession {
    static func make() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LanguageModelRecordingURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class LanguageModelRecordingURLProtocol: URLProtocol, URLSessionDataDelegate,
    @unchecked Sendable
{
    private var forwardingSession: URLSession?
    private var forwardingTask: URLSessionDataTask?
    private var responseData = Data()

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == JournalLanguageModelProvider.endpoint.host
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = []

        let session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: nil
        )
        forwardingSession = session
        forwardingTask = session.dataTask(with: request)
        forwardingTask?.resume()
    }

    override func stopLoading() {
        forwardingTask?.cancel()
        forwardingSession?.invalidateAndCancel()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        responseData.append(data)
        client?.urlProtocol(self, didLoad: data)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        if !responseData.isEmpty {
            LanguageModelResponseRecorder.shared.record(responseData)
        }

        if let error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }

        forwardingSession?.finishTasksAndInvalidate()
    }
}
