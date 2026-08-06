/**
 * Shared internal helpers used by both the V1 client and the V2 namespace.
 * Mirrors `internal.ts` (`raiseForStatus`, `serializePdfOptions`, `newJobId`)
 * plus the lenient `str` / `optStr` / `num` / `optNum` / `strArr` / `optObj`
 * style guards used throughout `v2.ts`'s response mappers.
 */

import Foundation

enum Internal {
    /// A UUID v4 with dashes removed, lowercased (32 hex chars).
    static func newJobId() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    static func sleep(ms: Int) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(ms, 0)) * 1_000_000)
    }

    /// Maps a non-2xx HTTP response to the appropriate `EnconvertError`.
    static func raiseForStatus(statusCode: Int, data: Data) throws {
        guard statusCode >= 400 else { return }
        let message = extractErrorMessage(data: data, statusCode: statusCode)
        switch statusCode {
        case 401, 403: throw EnconvertError.authentication(message: message)
        case 402: throw EnconvertError.quota(message: message)
        case 429: throw EnconvertError.rateLimit(message: message)
        default: throw EnconvertError.api(statusCode: statusCode, message: message)
        }
    }

    private static func extractErrorMessage(data: Data, statusCode: Int) -> String {
        if let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            if let detail = object["detail"] as? String { return detail }
            if let error = object["error"] as? String { return error }
            if let restringified = try? JSONSerialization.data(withJSONObject: object),
               let text = String(data: restringified, encoding: .utf8) {
                return text
            }
        }
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text
        }
        return "HTTP \(statusCode)"
    }

    /// Percent-encodes a single path segment (mirrors `encodeURIComponent`
    /// for opaque ids such as operation/job/watcher ids).
    static func percentEncodePathComponent(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    /// Extracts the `filename="..."` (or bare-token) value from a
    /// `Content-Disposition` header value, or `nil` when it carries none.
    static func filenameFromContentDisposition(_ value: String) -> String? {
        for part in value.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("filename=") else { continue }
            var filename = String(trimmed.dropFirst("filename=".count))
            if filename.count >= 2, filename.hasPrefix("\""), filename.hasSuffix("\"") {
                filename = String(filename.dropFirst().dropLast())
            }
            return filename.isEmpty ? nil : filename
        }
        return nil
    }

    /// Builds a `?a=b&c=d` query string, or `""` when `params` is empty.
    static func queryString(_ params: [(String, String)]) -> String {
        guard !params.isEmpty else { return "" }
        var components = URLComponents()
        components.queryItems = params.map { URLQueryItem(name: $0.0, value: $0.1) }
        return components.percentEncodedQuery.map { "?\($0)" } ?? ""
    }

    // MARK: - File input normalization

    /// Convert a `FileInput` into a normalized `FilePart`. Shared by the V1
    /// file conversions and the V2 file-ingest path.
    static func toFilePart(_ file: FileInput) throws -> FilePart {
        switch file {
        case .path(let path):
            guard let bytes = FileManager.default.contents(atPath: path) else {
                throw EnconvertError.invalidArgument("Could not read file at path: \(path)")
            }
            let filename = (path as NSString).lastPathComponent
            return FilePart(bytes: bytes, filename: filename, contentType: Formats.mime(for: filename))
        case .data(let bytes):
            return FilePart(bytes: bytes, filename: "upload.bin", contentType: "application/octet-stream")
        case .wrapped(let bytes, let filename, let contentType):
            return FilePart(bytes: bytes, filename: filename, contentType: contentType ?? Formats.mime(for: filename))
        }
    }

    // MARK: - Multipart body assembly

    /// A fresh, unique multipart boundary string.
    static func newMultipartBoundary() -> String {
        "----EnconvertBoundary\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
    }

    static func appendMultipartField(_ body: inout Data, boundary: String, name: String, value: String) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(value)\r\n".data(using: .utf8)!)
    }

    static func appendMultipartFile(
        _ body: inout Data,
        boundary: String,
        name: String,
        filename: String,
        contentType: String,
        fileData: Data
    ) {
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
    }

    static func endMultipart(_ body: inout Data, boundary: String) {
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
    }
}

// MARK: - Lenient JSON dictionary accessors

// The API responses are parsed into `[String: Any]` (via
// `JSONSerialization`) rather than decoded directly into typed structs, so
// that a missing or unexpectedly-shaped field degrades to a documented
// default instead of throwing — matching the reference SDK's `str` /
// `optStr` / `num` / `optNum` / `strArr` / `optObj` guards exactly.

func jsonString(_ json: [String: Any], _ key: String, default def: String = "") -> String {
    (json[key] as? String) ?? def
}

func jsonOptString(_ json: [String: Any], _ key: String) -> String? {
    json[key] as? String
}

func jsonInt(_ json: [String: Any], _ key: String, default def: Int = 0) -> Int {
    if let value = json[key] as? Int { return value }
    if let value = json[key] as? Double { return Int(value) }
    return def
}

func jsonOptInt(_ json: [String: Any], _ key: String) -> Int? {
    if let value = json[key] as? Int { return value }
    if let value = json[key] as? Double { return Int(value) }
    return nil
}

func jsonDouble(_ json: [String: Any], _ key: String, default def: Double = 0) -> Double {
    if let value = json[key] as? Double { return value }
    if let value = json[key] as? Int { return Double(value) }
    return def
}

func jsonOptDouble(_ json: [String: Any], _ key: String) -> Double? {
    if let value = json[key] as? Double { return value }
    if let value = json[key] as? Int { return Double(value) }
    return nil
}

func jsonBool(_ json: [String: Any], _ key: String, default def: Bool = false) -> Bool {
    (json[key] as? Bool) ?? def
}

/// True unless the key is explicitly `false` (mirrors `d.x !== false`).
func jsonBoolDefaultTrue(_ json: [String: Any], _ key: String) -> Bool {
    (json[key] as? Bool) != false
}

func jsonStringArray(_ json: [String: Any], _ key: String) -> [String] {
    (json[key] as? [Any])?.compactMap { $0 as? String } ?? []
}

// Named `jsonDict` / `jsonDictArray` (rather than `jsonObject`) to avoid a
// confusing near-collision with the public `JSONObject` type alias.

func jsonDict(_ json: [String: Any], _ key: String) -> [String: Any]? {
    json[key] as? [String: Any]
}

func jsonDictArray(_ json: [String: Any], _ key: String) -> [[String: Any]] {
    (json[key] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
}

/// Parses a required string-backed enum field. Throws `EnconvertError.api`
/// with statusCode `0` (a malformed-but-2xx response) if absent or
/// unrecognized, rather than mirroring the Node SDK's unchecked `as` cast.
func jsonRequiredEnum<T: RawRepresentable>(_ json: [String: Any], _ key: String, as type: T.Type) throws -> T
where T.RawValue == String {
    guard let raw = json[key] as? String, let value = T(rawValue: raw) else {
        throw EnconvertError.api(statusCode: 0, message: "Missing or unrecognized '\(key)' in API response")
    }
    return value
}
