/**
 * Low-level HTTP transport shared by the V1 client and the V2 namespace.
 *
 * Split out of `Enconvert` (rather than having `EnconvertV2` hold a closure
 * back into `Enconvert`, as the Node SDK does) because Swift does not allow
 * capturing `self` in a stored closure before every stored property has been
 * initialized. Both `Enconvert` and `EnconvertV2` hold a reference to the
 * same `Transport` instance instead.
 */

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class Transport {
    let apiKey: String
    let baseURL: String
    let timeout: TimeInterval
    private let session: URLSession

    init(apiKey: String, baseURL: String, timeout: TimeInterval) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.timeout = timeout
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        self.session = URLSession(configuration: configuration)
    }

    /// Sends a request and returns the raw response body + HTTP status,
    /// without raising for non-2xx status (callers decide whether to raise
    /// or, for job polling, to keep waiting on a 404).
    func send(
        path: String,
        method: String,
        jsonBody: [String: Any]? = nil
    ) async throws -> (data: Data, statusCode: Int) {
        guard let url = URL(string: baseURL + path) else {
            throw EnconvertError.invalidArgument("Invalid URL: \(baseURL)\(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        if let jsonBody {
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
            request.setValue("application/json", forHTTPHeaderField: "content-type")
        }

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, statusCode)
    }

    /// Sends a multipart/form-data request built from a pre-encoded body.
    func sendMultipart(
        path: String,
        method: String,
        body: Data,
        boundary: String
    ) async throws -> (data: Data, statusCode: Int) {
        guard let url = URL(string: baseURL + path) else {
            throw EnconvertError.invalidArgument("Invalid URL: \(baseURL)\(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "content-type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, statusCode)
    }

    /// Sends a request and decodes a JSON object response, raising for any
    /// non-2xx status.
    func requestJSON(
        path: String,
        method: String,
        jsonBody: [String: Any]? = nil
    ) async throws -> [String: Any] {
        let (data, statusCode) = try await send(path: path, method: method, jsonBody: jsonBody)
        try Internal.raiseForStatus(statusCode: statusCode, data: data)
        return Transport.decodeJSONObject(data)
    }

    static func decodeJSONObject(_ data: Data) -> [String: Any] {
        guard !data.isEmpty, let object = try? JSONSerialization.jsonObject(with: data) else { return [:] }
        return object as? [String: Any] ?? [:]
    }

    /// GET a path without raising for status — used by `pollJob`, which
    /// treats HTTP 404 as "not ready yet" rather than an error.
    func getRaw(path: String) async throws -> (data: Data, statusCode: Int) {
        try await send(path: path, method: "GET")
    }

    /// Downloads a presigned URL (no `X-API-Key` header — it is a signed S3
    /// URL) and writes it to `dest`, creating parent directories as needed.
    func download(url: String, to dest: String) async throws {
        guard let downloadURL = URL(string: url) else {
            throw EnconvertError.invalidArgument("Invalid download URL: \(url)")
        }
        let request = URLRequest(url: downloadURL)
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(statusCode) else {
            throw EnconvertError.api(statusCode: statusCode, message: "Failed to download: HTTP \(statusCode)")
        }
        let destURL = URL(fileURLWithPath: dest)
        let directory = destURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: destURL)
    }
}
