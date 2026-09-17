/**
 * Enconvert API client (V1).
 *
 * ```swift
 * import Enconvert
 *
 * let client = try Enconvert(apiKey: "sk_...")
 * let result = try await client.convertUrlToPdf("https://example.com")
 * print(result.presignedUrl)
 * ```
 */

import Foundation

public final class Enconvert {
    private let transport: Transport

    /// V2 API namespace: perceive, discover, lookup, distill, ingest, watch.
    /// Requires a private API key; endpoints are plan-gated (`.quota` on 402).
    public let v2: EnconvertV2

    public static let defaultBaseURL = "https://api.enconvert.com"
    public static let defaultTimeout: TimeInterval = 300
    public static let defaultUserAgent = "enconvert-sdk/\(VERSION) (swift)"
    private static let defaultBatchPollIntervalMs = 5_000
    private static let defaultBatchTimeoutMs = 1_800_000

    /// - Parameters:
    ///   - apiKey: Required. Throws `.invalidArgument` if empty.
    ///   - baseURL: Overrides the API base URL. Trailing slashes are stripped.
    ///   - timeout: Request timeout in seconds. Defaults to 300 (5 minutes).
    ///   - userAgent: Overrides the `User-Agent` header sent with every API request.
    public init(
        apiKey: String,
        baseURL: String = Enconvert.defaultBaseURL,
        timeout: TimeInterval = Enconvert.defaultTimeout,
        userAgent: String = Enconvert.defaultUserAgent
    ) throws {
        guard !apiKey.isEmpty else {
            throw EnconvertError.invalidArgument("Enconvert: 'apiKey' is required")
        }
        let normalizedBaseURL = Enconvert.stripTrailingSlashes(baseURL)
        let transport = Transport(apiKey: apiKey, baseURL: normalizedBaseURL, timeout: timeout, userAgent: userAgent)
        self.transport = transport
        self.v2 = EnconvertV2(transport: transport)
    }

    private static func stripTrailingSlashes(_ value: String) -> String {
        var result = value
        while result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }

    // ------------------------------------------------------------------
    // URL conversions (single page)
    // ------------------------------------------------------------------

    /// Convert a URL to PDF.
    @discardableResult
    public func convertUrlToPdf(_ url: String, options: UrlToPdfOptions = UrlToPdfOptions()) async throws -> ConversionResult {
        var body = Self.buildUrlBody(url: url, opts: options)
        body["single_page"] = options.singlePage ?? true
        if let pdfOptions = options.pdfOptions {
            body["pdf_options"] = pdfOptions.toJSONDict()
        }
        let data = try await postJson("/v1/convert/url-to-pdf", body: body)
        let result = try Self.toConversionResult(data)
        if let saveTo = options.saveTo {
            try await transport.download(url: result.presignedUrl, to: saveTo)
        }
        return result
    }

    /// Convert a URL to a PNG screenshot.
    @discardableResult
    public func convertUrlToScreenshot(
        _ url: String,
        options: UrlToScreenshotOptions = UrlToScreenshotOptions()
    ) async throws -> ConversionResult {
        let body = Self.buildUrlBody(url: url, opts: options)
        let data = try await postJson("/v1/convert/url-to-screenshot", body: body)
        let result = try Self.toConversionResult(data)
        if let saveTo = options.saveTo {
            try await transport.download(url: result.presignedUrl, to: saveTo)
        }
        return result
    }

    /// Convert a URL to clean GitHub-Flavored Markdown with YAML frontmatter
    /// (title, description, url, links, images). Strips nav/footer/ads/scripts
    /// and extracts the main article content.
    @discardableResult
    public func convertUrlToMarkdown(
        _ url: String,
        options: UrlToMarkdownOptions = UrlToMarkdownOptions()
    ) async throws -> ConversionResult {
        let body = Self.buildUrlBody(url: url, opts: options)
        let data = try await postJson("/v1/convert/url-to-markdown", body: body)
        let result = try Self.toConversionResult(data)
        if let saveTo = options.saveTo {
            try await transport.download(url: result.presignedUrl, to: saveTo)
        }
        return result
    }

    // ------------------------------------------------------------------
    // Website conversions (async batch, whole-site crawl)
    // ------------------------------------------------------------------

    /// Convert every discovered page of a website to PDF. Async-only: pages
    /// are discovered via sitemap or full crawl (plan-dependent), converted
    /// in the background, and bundled into a single ZIP. Poll with
    /// `getBatchStatus` or block with `waitForBatch`. Requires a private API
    /// key with crawl access.
    public func convertWebsiteToPdf(
        _ url: String,
        options: WebsiteToPdfOptions = WebsiteToPdfOptions()
    ) async throws -> BatchSubmission {
        var body = Self.buildWebsiteBody(url: url, opts: options)
        if let singlePage = options.singlePage { body["single_page"] = singlePage }
        if let pdfOptions = options.pdfOptions { body["pdf_options"] = pdfOptions.toJSONDict() }

        // No job-polling fallback: website submissions have no per-job row, so
        // a 5xx here means the submission itself failed and must surface directly.
        let data = try await postJson("/v1/convert/website-to-pdf", body: body, jobFallback: false)
        return try Self.toBatchSubmission(data)
    }

    /// Screenshot every discovered page of a website (PNG). Async-only,
    /// bundled into a single ZIP. Poll with `getBatchStatus` or block with
    /// `waitForBatch`. Requires a private API key with crawl access.
    public func convertWebsiteToScreenshot(
        _ url: String,
        options: WebsiteToScreenshotOptions = WebsiteToScreenshotOptions()
    ) async throws -> BatchSubmission {
        let body = Self.buildWebsiteBody(url: url, opts: options)
        let data = try await postJson("/v1/convert/website-to-screenshot", body: body, jobFallback: false)
        return try Self.toBatchSubmission(data)
    }

    // ------------------------------------------------------------------
    // File conversions
    // ------------------------------------------------------------------

    /// Convert an image between formats (jpeg, png, svg, heic, webp), or
    /// rasterize a PDF to JPEG. Only pairs implemented by the API are
    /// accepted; unsupported pairs throw before any request is made.
    @discardableResult
    public func convertImage(_ file: FileInput, options: ConvertImageOptions) async throws -> ConversionResult {
        let part = try Internal.toFilePart(file)
        let inputFormat = try Formats.resolveInputFormat(part.filename, in: Formats.imageFormats)
        let outputFormat = Formats.normalizeOutputFormat(options.outputFormat)
        let endpoint = try Formats.assertConversionImplemented(inputFormat: inputFormat, outputFormat: outputFormat)
        let data = try await postFile(
            "/v1/convert/\(endpoint)",
            part: part,
            outputFilename: options.outputFilename,
            pdfOptions: nil
        )
        let result = try Self.toConversionResult(data)
        if let saveTo = options.saveTo {
            try await transport.download(url: result.presignedUrl, to: saveTo)
        }
        return result
    }

    /// Convert a document (doc, excel, ppt, odt, ods, odp, ots, pages,
    /// numbers, html, markdown, csv, json, xml, yaml, toml). Output
    /// defaults to pdf. Only pairs implemented by the API are accepted;
    /// unsupported pairs throw before any request is made. (EPUB has no
    /// dedicated pair — use `convertToPdf` / `convertToMarkdown`.)
    @discardableResult
    public func convertDocument(
        _ file: FileInput,
        options: ConvertDocumentOptions = ConvertDocumentOptions()
    ) async throws -> ConversionResult {
        let part = try Internal.toFilePart(file)
        let inputFormat = try Formats.resolveInputFormat(part.filename, in: Formats.documentFormats)
        let outputFormat = Formats.normalizeOutputFormat(options.outputFormat ?? "pdf")
        let endpoint = try Formats.assertConversionImplemented(inputFormat: inputFormat, outputFormat: outputFormat)
        let data = try await postFile(
            "/v1/convert/\(endpoint)",
            part: part,
            outputFilename: options.outputFilename,
            pdfOptions: options.pdfOptions
        )
        let result = try Self.toConversionResult(data)
        if let saveTo = options.saveTo {
            try await transport.download(url: result.presignedUrl, to: saveTo)
        }
        return result
    }

    /// Convert an uploaded file of (almost) any document format to clean
    /// Markdown — PDF, DOCX, PPTX, XLSX, CSV, HTML, EPUB, TXT/MD, and
    /// legacy/ODF office. The format is auto-detected server-side; a
    /// RAG-ingestion building block. Images are not supported.
    @discardableResult
    public func convertToMarkdown(
        _ file: FileInput,
        options: ConvertToMarkdownOptions = ConvertToMarkdownOptions()
    ) async throws -> ConversionResult {
        let part = try Internal.toFilePart(file)
        let data = try await postFile(
            "/v1/convert/anything-to-markdown",
            part: part,
            outputFilename: options.outputFilename,
            pdfOptions: nil
        )
        let result = try Self.toConversionResult(data)
        if let saveTo = options.saveTo {
            try await transport.download(url: result.presignedUrl, to: saveTo)
        }
        return result
    }

    /// Convert an uploaded file of (almost) any format to PDF —
    /// office/ODF/Pages/Numbers/RTF/CSV, HTML, Markdown, text, raster
    /// images, SVG, EPUB, or an existing PDF (passthrough/normalise). The
    /// format is auto-detected server-side. Only `pdfOptions.grayscale` is
    /// honored on this endpoint.
    @discardableResult
    public func convertToPdf(
        _ file: FileInput,
        options: ConvertToPdfOptions = ConvertToPdfOptions()
    ) async throws -> ConversionResult {
        let part = try Internal.toFilePart(file)
        let data = try await postFile(
            "/v1/convert/anything-to-pdf",
            part: part,
            outputFilename: options.outputFilename,
            pdfOptions: options.pdfOptions
        )
        let result = try Self.toConversionResult(data)
        if let saveTo = options.saveTo {
            try await transport.download(url: result.presignedUrl, to: saveTo)
        }
        return result
    }

    // ------------------------------------------------------------------
    // Job + batch status
    // ------------------------------------------------------------------

    /// Poll the status of an async conversion job.
    public func getJobStatus(_ jobId: String) async throws -> JobStatus {
        let data = try await transport.requestJSON(path: "/v1/convert/status/\(jobId)", method: "GET")
        return try Self.toJobStatus(data)
    }

    /// Get the status of an async batch (website conversion). Returns
    /// aggregate counts, per-URL statuses, and download URLs. Private API
    /// keys only.
    public func getBatchStatus(_ batchId: String) async throws -> BatchStatus {
        let data = try await transport.requestJSON(path: "/v1/convert/batch/\(batchId)", method: "GET")
        return try Self.toBatchStatus(data)
    }

    /// Poll a batch until it leaves `.processing`, then return its final
    /// status. With `saveTo`, downloads the batch ZIP once available.
    /// Throws `.api(statusCode: 504, ...)` on timeout.
    public func waitForBatch(_ batchId: String, options: WaitForBatchOptions = WaitForBatchOptions()) async throws -> BatchStatus {
        let intervalMs = options.intervalMs ?? Self.defaultBatchPollIntervalMs
        let timeoutMs = options.timeoutMs ?? Self.defaultBatchTimeoutMs
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000)

        while true {
            let status = try await getBatchStatus(batchId)
            if status.status != .processing {
                if let saveTo = options.saveTo {
                    guard let zipDownloadUrl = status.zipDownloadUrl else {
                        throw EnconvertError.api(
                            statusCode: 500,
                            message: "Batch \(batchId) finished with status '\(status.status.rawValue)' but no ZIP is available to save"
                        )
                    }
                    try await transport.download(url: zipDownloadUrl, to: saveTo)
                }
                return status
            }
            if Date() >= deadline {
                throw EnconvertError.api(statusCode: 504, message: "Batch \(batchId) did not complete within \(timeoutMs)ms")
            }
            try await Internal.sleep(ms: intervalMs)
        }
    }

    // ------------------------------------------------------------------
    // Internal helpers (mirror of the Node SDK's postJson / postFile /
    // pollJob / download / toFilePart / raiseForStatus)
    // ------------------------------------------------------------------

    private func postJson(_ endpoint: String, body: [String: Any], jobFallback: Bool = true) async throws -> [String: Any] {
        var requestBody = body
        let jobId = jobFallback ? Internal.newJobId() : nil
        if let jobId {
            requestBody["job_id"] = jobId
        }
        do {
            let data = try await transport.requestJSON(path: endpoint, method: "POST", jsonBody: requestBody)
            guard let jobId else { return data }
            // Some success responses omit job_id (URL sync path); backfill the
            // client-generated id so callers can still poll getJobStatus with it.
            var result = data
            if result["job_id"] == nil {
                result["job_id"] = jobId
            }
            return result
        } catch let error as EnconvertError {
            if let jobId, case .api(let statusCode, _) = error, statusCode >= 500 {
                return try await pollJob(jobId)
            }
            throw error
        }
    }

    private func postFile(
        _ endpoint: String,
        part: FilePart,
        outputFilename: String?,
        pdfOptions: PdfOptions?
    ) async throws -> [String: Any] {
        let jobId = Internal.newJobId()
        let boundary = Internal.newMultipartBoundary()
        var body = Data()
        Internal.appendMultipartFile(&body, boundary: boundary, name: "file", filename: part.filename, contentType: part.contentType, fileData: part.bytes)
        Internal.appendMultipartField(&body, boundary: boundary, name: "direct_download", value: "false")
        Internal.appendMultipartField(&body, boundary: boundary, name: "job_id", value: jobId)
        if let outputFilename {
            Internal.appendMultipartField(&body, boundary: boundary, name: "output_filename", value: outputFilename)
        }
        if let pdfOptions {
            let json = try JSONSerialization.data(withJSONObject: pdfOptions.toJSONDict())
            Internal.appendMultipartField(&body, boundary: boundary, name: "pdf_options", value: String(data: json, encoding: .utf8) ?? "{}")
        }
        Internal.endMultipart(&body, boundary: boundary)

        do {
            let (data, statusCode) = try await transport.sendMultipart(path: endpoint, method: "POST", body: body, boundary: boundary)
            try Internal.raiseForStatus(statusCode: statusCode, data: data)
            var result = Transport.decodeJSONObject(data)
            if result["job_id"] == nil {
                result["job_id"] = jobId
            }
            return result
        } catch let error as EnconvertError {
            if case .api(let statusCode, _) = error, statusCode >= 500 {
                return try await pollJob(jobId)
            }
            throw error
        }
    }

    /// Poll job status until success/failure. Used as fallback when the
    /// initial HTTP request fails with a 5xx.
    private func pollJob(_ jobId: String, maxWaitMs: Int = 300_000, intervalMs: Int = 3_000) async throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(Double(maxWaitMs) / 1000)
        while Date() < deadline {
            try await Internal.sleep(ms: intervalMs)
            let (data, statusCode) = try await transport.getRaw(path: "/v1/convert/status/\(jobId)")
            if statusCode == 404 { continue }
            try Internal.raiseForStatus(statusCode: statusCode, data: data)
            let json = Transport.decodeJSONObject(data)
            let status = jsonString(json, "status")
            if status == "success" { return json }
            if status == "failed" {
                throw EnconvertError.api(statusCode: 500, message: jsonOptString(json, "error") ?? "Conversion failed")
            }
        }
        throw EnconvertError.api(statusCode: 504, message: "Conversion timed out")
    }

    // MARK: Request body builders

    /// Request body shared by all single-URL conversions.
    private static func buildUrlBody(url: String, opts: any UrlRenderOptions) -> [String: Any] {
        var body: [String: Any] = [
            "url": url,
            "direct_download": false,
            "viewport_width": opts.viewportWidth ?? 1920,
            "viewport_height": opts.viewportHeight ?? 1080,
            "load_media": opts.loadMedia ?? true,
            "enable_scroll": opts.enableScroll ?? true,
        ]
        if let outputFilename = opts.outputFilename { body["output_filename"] = outputFilename }
        appendBrowserAccess(&body, opts)
        return body
    }

    /// Request body for website (whole-site) conversions. Render options are
    /// only sent when set — the gateway applies the same defaults per page.
    private static func buildWebsiteBody(url: String, opts: any WebsiteConversionOptions) -> [String: Any] {
        var body: [String: Any] = ["url": url]
        if let crawlMode = opts.crawlMode { body["crawl_mode"] = crawlMode.rawValue }
        if let includePatterns = opts.includePatterns { body["include_patterns"] = includePatterns }
        if let excludePatterns = opts.excludePatterns { body["exclude_patterns"] = excludePatterns }
        if let notificationEmail = opts.notificationEmail { body["notification_email"] = notificationEmail }
        if let callbackUrl = opts.callbackUrl { body["callback_url"] = callbackUrl }
        if let outputFilename = opts.outputFilename { body["output_filename"] = outputFilename }
        if let viewportWidth = opts.viewportWidth { body["viewport_width"] = viewportWidth }
        if let viewportHeight = opts.viewportHeight { body["viewport_height"] = viewportHeight }
        if let loadMedia = opts.loadMedia { body["load_media"] = loadMedia }
        if let enableScroll = opts.enableScroll { body["enable_scroll"] = enableScroll }
        appendBrowserAccess(&body, opts)
        return body
    }

    /// Attach the plan-gated auth/cookies/headers fields when provided.
    private static func appendBrowserAccess(_ body: inout [String: Any], _ opts: any UrlRenderOptions) {
        if let auth = opts.auth { body["auth"] = auth.toJSONDict() }
        if let cookies = opts.cookies { body["cookies"] = cookies.map { $0.toJSONDict() } }
        if let headers = opts.headers { body["headers"] = headers }
    }

    // MARK: Response mappers

    private static func toConversionResult(_ data: [String: Any]) throws -> ConversionResult {
        guard let presignedUrl = data["presigned_url"] as? String else {
            throw EnconvertError.api(statusCode: 0, message: "Missing 'presigned_url' in API response")
        }
        // Job-status fallback responses omit `filename`; recover it from the
        // object key so callers never see an empty string unexpectedly.
        let objectKey = jsonString(data, "object_key")
        let filename = jsonOptString(data, "filename") ?? Formats.basename(of: objectKey)
        return ConversionResult(
            presignedUrl: presignedUrl,
            objectKey: objectKey,
            filename: filename,
            fileSize: jsonOptInt(data, "file_size"),
            conversionTimeSeconds: jsonOptDouble(data, "conversion_time_seconds"),
            jobId: jsonOptString(data, "job_id")
        )
    }

    private static func toJobStatus(_ data: [String: Any]) throws -> JobStatus {
        let status = try jsonRequiredEnum(data, "status", as: JobStatusValue.self)
        return JobStatus(
            status: status,
            presignedUrl: jsonOptString(data, "presigned_url"),
            objectKey: jsonOptString(data, "object_key"),
            error: jsonOptString(data, "error")
        )
    }

    private static func toBatchSubmission(_ data: [String: Any]) throws -> BatchSubmission {
        guard let batchId = data["batch_id"] as? String else {
            throw EnconvertError.api(statusCode: 0, message: "Missing 'batch_id' in API response")
        }
        return BatchSubmission(
            batchId: batchId,
            status: jsonString(data, "status", default: "processing"),
            urlCount: jsonInt(data, "url_count"),
            totalDiscovered: jsonOptInt(data, "total_discovered"),
            discoveryMethod: jsonOptString(data, "discovery_method"),
            outputFormat: jsonOptString(data, "output_format")
        )
    }

    private static func toBatchStatus(_ data: [String: Any]) throws -> BatchStatus {
        guard let batchId = data["batch_id"] as? String else {
            throw EnconvertError.api(statusCode: 0, message: "Missing 'batch_id' in API response")
        }
        let status = try jsonRequiredEnum(data, "status", as: BatchStatusValue.self)
        let outputMode = try jsonRequiredEnum(data, "output_mode", as: BatchOutputMode.self)
        let items = jsonDictArray(data, "items").map { item in
            BatchItem(
                sourceUrl: jsonString(item, "source_url"),
                status: jsonString(item, "status"),
                downloadUrl: jsonOptString(item, "download_url"),
                outputFileSize: jsonOptInt(item, "output_file_size"),
                duration: jsonOptString(item, "duration")
            )
        }
        return BatchStatus(
            batchId: batchId,
            status: status,
            total: jsonInt(data, "total"),
            completed: jsonInt(data, "completed"),
            failed: jsonInt(data, "failed"),
            inProgress: jsonInt(data, "in_progress"),
            outputMode: outputMode,
            zipDownloadUrl: jsonOptString(data, "zip_download_url"),
            items: items
        )
    }
}
