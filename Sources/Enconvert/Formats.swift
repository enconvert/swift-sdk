/**
 * Format tables mirroring the gateway's CONVERTER_MAP (api/v1/convert.py).
 *
 * `implementedConversions` is the client-side gate: the gateway returns 503
 * for any `{input}-to-{output}` endpoint not in its CONVERTER_MAP, so we
 * reject unsupported pairs here with a useful message instead of paying a
 * network round-trip for a guaranteed failure.
 */

import Foundation

public enum Formats {
    /// The 43 implemented `{input}-to-{output}` conversion endpoints.
    public static let implementedConversions: Set<String> = [
        // Structured text (13)
        "json-to-xml",
        "xml-to-json",
        "json-to-yaml",
        "yaml-to-json",
        "csv-to-json",
        "json-to-csv",
        "json-to-toml",
        "toml-to-json",
        "csv-to-xml",
        "xml-to-csv",
        "markdown-to-html",
        "markdown-to-pdf",
        "html-to-pdf",
        // Documents (9) — EPUB→PDF now flows through anything-to-pdf, not a dedicated pair.
        "doc-to-pdf",
        "excel-to-pdf",
        "ppt-to-pdf",
        "odt-to-pdf",
        "ods-to-pdf",
        "odp-to-pdf",
        "ots-to-pdf",
        "pages-to-pdf",
        "numbers-to-pdf",
        // Images (21)
        "jpeg-to-png",
        "png-to-jpeg",
        "jpeg-to-svg",
        "svg-to-jpeg",
        "jpeg-to-heic",
        "heic-to-jpeg",
        "jpeg-to-webp",
        "webp-to-jpeg",
        "png-to-svg",
        "svg-to-png",
        "png-to-heic",
        "heic-to-png",
        "png-to-webp",
        "webp-to-png",
        "svg-to-heic",
        "heic-to-svg",
        "svg-to-webp",
        "webp-to-svg",
        "heic-to-webp",
        "webp-to-heic",
        "pdf-to-jpeg",
    ]

    /// Extension -> API format name (input side).
    public static let imageFormats: [String: String] = [
        ".jpg": "jpeg",
        ".jpeg": "jpeg",
        ".png": "png",
        ".svg": "svg",
        ".heic": "heic",
        ".webp": "webp",
        // PDF is an image input solely for pdf-to-jpeg (rasterization).
        ".pdf": "pdf",
    ]

    public static let documentFormats: [String: String] = [
        ".doc": "doc",
        ".docx": "doc",
        ".xls": "excel",
        ".xlsx": "excel",
        ".ppt": "ppt",
        ".pptx": "ppt",
        ".html": "html",
        ".htm": "html",
        ".odt": "odt",
        ".ods": "ods",
        ".odp": "odp",
        ".ots": "ots",
        ".pages": "pages",
        ".numbers": "numbers",
        // .epub has no dedicated document pair — use convertToPdf / convertToMarkdown.
        ".md": "markdown",
        ".markdown": "markdown",
        ".csv": "csv",
        ".json": "json",
        ".xml": "xml",
        ".yaml": "yaml",
        ".yml": "yaml",
        ".toml": "toml",
    ]

    public static let mimeByExt: [String: String] = [
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".png": "image/png",
        ".svg": "image/svg+xml",
        ".heic": "image/heic",
        ".webp": "image/webp",
        ".pdf": "application/pdf",
        ".doc": "application/msword",
        ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        ".xls": "application/vnd.ms-excel",
        ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        ".ppt": "application/vnd.ms-powerpoint",
        ".pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        ".html": "text/html",
        ".htm": "text/html",
        ".odt": "application/vnd.oasis.opendocument.text",
        ".ods": "application/vnd.oasis.opendocument.spreadsheet",
        ".odp": "application/vnd.oasis.opendocument.presentation",
        ".epub": "application/epub+zip",
        ".md": "text/markdown",
        ".markdown": "text/markdown",
        ".csv": "text/csv",
        ".json": "application/json",
        ".xml": "application/xml",
        ".yaml": "application/x-yaml",
        ".yml": "application/x-yaml",
        ".toml": "application/toml",
    ]

    /// Common aliases users pass that differ from the API's canonical format names.
    private static let outputFormatAliases: [String: String] = [
        "jpg": "jpeg",
        "yml": "yaml",
        "htm": "html",
        "md": "markdown",
    ]

    public static func ext(of name: String) -> String {
        guard let dotIndex = name.lastIndex(of: ".") else { return "" }
        return String(name[dotIndex...]).lowercased()
    }

    public static func mime(for name: String) -> String {
        mimeByExt[ext(of: name)] ?? "application/octet-stream"
    }

    /// The basename (final path component) of a possibly-slashed key, e.g.
    /// an S3 `object_key`. Mirrors `objectKey.split("/").pop()`.
    public static func basename(of path: String) -> String {
        if let lastSlash = path.lastIndex(of: "/") {
            return String(path[path.index(after: lastSlash)...])
        }
        return path
    }

    /// Maps a filename's extension to its API input format, or throws.
    public static func resolveInputFormat(_ name: String, in map: [String: String]) throws -> String {
        let extValue = ext(of: name)
        guard let format = map[extValue] else {
            let supported = Set(map.keys).sorted().joined(separator: ", ")
            throw EnconvertError.invalidArgument(
                "Unsupported file extension '\(extValue)'. Supported: \(supported)"
            )
        }
        return format
    }

    /// Lowercases, strips a leading dot, and resolves aliases (jpg, yml, htm, md).
    public static func normalizeOutputFormat(_ format: String) -> String {
        var value = format.lowercased()
        if value.hasPrefix(".") { value.removeFirst() }
        return outputFormatAliases[value] ?? value
    }

    /// Lists the output formats the API implements for a given input format.
    public static func validOutputs(for inputFormat: String) -> [String] {
        let prefix = "\(inputFormat)-to-"
        return implementedConversions
            .filter { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
            .sorted()
    }

    /// Asserts `{input}-to-{output}` is an implemented endpoint and returns
    /// its endpoint name. Throws with the list of valid outputs for that
    /// input otherwise.
    public static func assertConversionImplemented(inputFormat: String, outputFormat: String) throws -> String {
        let endpoint = "\(inputFormat)-to-\(outputFormat)"
        guard implementedConversions.contains(endpoint) else {
            let outputs = validOutputs(for: inputFormat)
            let hint = outputs.isEmpty
                ? "No conversions are available for input format '\(inputFormat)'"
                : "Supported outputs for '\(inputFormat)': \(outputs.joined(separator: ", "))"
            throw EnconvertError.invalidArgument(
                "Conversion '\(inputFormat)' to '\(outputFormat)' is not supported. \(hint)."
            )
        }
        return endpoint
    }
}

/// The 43 implemented `{input}-to-{output}` conversion endpoints (top-level
/// re-export matching the Node SDK's `IMPLEMENTED_CONVERSIONS`).
public let IMPLEMENTED_CONVERSIONS: Set<String> = Formats.implementedConversions

/// Lists the output formats the API implements for a given input format
/// (top-level re-export matching the Node SDK's `validOutputsFor`).
///
///     validOutputsFor("json")  // ["csv", "toml", "xml", "yaml"]
///     validOutputsFor("pdf")   // ["jpeg"]
public func validOutputsFor(_ inputFormat: String) -> [String] {
    Formats.validOutputs(for: inputFormat)
}
