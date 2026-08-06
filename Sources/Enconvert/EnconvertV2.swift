/**
 * V2 API namespace, reached as `client.v2`.
 *
 * One method per V2 endpoint (21 total across six groups: perceive,
 * discover, lookup, distill, ingest, watch). Options are camelCase and
 * serialized to the API's snake_case wire format; responses are mapped back
 * to camelCase. User-data payloads (schemas, extracted data, tracked
 * fields, diff changes) pass through untouched via `JSONValue`.
 *
 * All V2 endpoints require a private API key (public keys are rejected) and
 * are plan-gated: a disabled feature or exhausted monthly quota raises
 * `EnconvertError.quota` (HTTP 402).
 */

import Foundation

public final class EnconvertV2 {
    private let transport: Transport

    init(transport: Transport) {
        self.transport = transport
    }

    // ------------------------------------------------------------------
    // Perceive — render a URL into agent-ready artifacts
    // ------------------------------------------------------------------

    /// Render one URL into the requested outputs (markdown, screenshots,
    /// PDF, links, structured data, ...). Synchronous: returns the completed
    /// operation with 15-minute signed artifact URLs.
    public func perceive(_ url: String, options: PerceiveOptions = PerceiveOptions()) async throws -> PerceiveResult {
        var body = Self.serializePerceiveOptions(options)
        body["url"] = url
        let data = try await post("/v2/perceive", body: body)
        return try Self.toPerceiveResult(data)
    }

    /// Re-fetch a perceive operation by id (`per_...`). Artifact URLs are
    /// freshly re-signed on every call.
    public func getPerceiveOperation(_ operationId: String) async throws -> PerceiveResult {
        let data = try await get("/v2/perceive/\(Internal.percentEncodePathComponent(operationId))")
        return try Self.toPerceiveResult(data)
    }

    /// Perceive up to 1000 URLs with one shared options block. Small
    /// batches run inline (completed result); larger ones return status
    /// "queued" — poll `getPerceiveBatch` with the jobId.
    public func perceiveBatch(
        _ urls: [String],
        options: PerceiveBatchOptions = PerceiveBatchOptions()
    ) async throws -> PerceiveBatchResult {
        var body: [String: Any] = [
            "urls": urls,
            "options": Self.serializePerceiveOptions(options),
        ]
        if let outputMode = options.outputMode { body["output_mode"] = outputMode.rawValue }
        let data = try await post("/v2/perceive/batch", body: body)
        return try Self.toPerceiveBatchResult(data)
    }

    /// Poll a perceive batch by jobId. Items fill in as URLs complete.
    public func getPerceiveBatch(_ jobId: String) async throws -> PerceiveBatchResult {
        let data = try await get("/v2/perceive/batch/\(Internal.percentEncodePathComponent(jobId))")
        return try Self.toPerceiveBatchResult(data)
    }

    /// Outputs that produce a downloadable artifact (everything except
    /// `structured`, which is inline JSON).
    private static let artifactOutputs: [PerceiveOutputName] = [
        .markdown, .htmlCleaned, .htmlRaw, .screenshot, .screenshotFullPage, .pdf, .links, .images,
    ]

    /// Render one URL and stream the artifact bytes back directly
    /// (`direct_download`), skipping the JSON envelope and the signed-URL
    /// round trip. Requires exactly one artifact-producing output in
    /// `options.outputs`; metadata is returned via response headers.
    public func perceiveDirect(_ url: String, options: PerceiveOptions = PerceiveOptions()) async throws -> PerceiveDirectResult {
        let outputs = options.outputs ?? [.markdown, .structured]
        let artifactCount = outputs.filter { Self.artifactOutputs.contains($0) }.count
        guard artifactCount == 1 else {
            let valid = Self.artifactOutputs.map { $0.rawValue }.joined(separator: ", ")
            throw EnconvertError.invalidArgument(
                "perceiveDirect: requires exactly one artifact-producing output (\(valid)); got \(artifactCount)"
            )
        }
        var body = Self.serializePerceiveOptions(options)
        body["url"] = url
        body["direct_download"] = true
        let (data, statusCode, headers) = try await transport.sendWithHeaders(
            path: "/v2/perceive", method: "POST", jsonBody: body
        )
        try Internal.raiseForStatus(statusCode: statusCode, data: data)
        return Self.toPerceiveDirectResult(data, headers: headers)
    }

    /// Stream one stored artifact of an earlier perceive operation. `output`
    /// may be omitted when the operation produced exactly one artifact
    /// (otherwise 400 listing the available outputs); 410 once the artifact
    /// passes the plan's retention window.
    public func downloadPerceiveArtifact(
        _ operationId: String,
        output: PerceiveOutputName? = nil
    ) async throws -> PerceiveDirectResult {
        var params: [(String, String)] = [("direct_download", "true")]
        if let output { params.append(("output", output.rawValue)) }
        let path = "/v2/perceive/\(Internal.percentEncodePathComponent(operationId))\(Internal.queryString(params))"
        let (data, statusCode, headers) = try await transport.sendWithHeaders(path: path, method: "GET")
        try Internal.raiseForStatus(statusCode: statusCode, data: data)
        return Self.toPerceiveDirectResult(data, headers: headers)
    }

    // ------------------------------------------------------------------
    // Discover — enumerate a site's URLs without rendering
    // ------------------------------------------------------------------

    /// List a site's URLs via sitemap, HTTP crawl, or both. No browser
    /// rendering — fast and does not consume perceive quota.
    public func discover(_ url: String, options: DiscoverOptions = DiscoverOptions()) async throws -> DiscoverResult {
        var body: [String: Any] = ["url": url]
        if let mode = options.mode { body["mode"] = mode.rawValue }
        if let maxUrls = options.maxUrls { body["max_urls"] = maxUrls }
        if let maxDepth = options.maxDepth { body["max_depth"] = maxDepth }
        if let includePatterns = options.includePatterns { body["include_patterns"] = includePatterns }
        if let excludePatterns = options.excludePatterns { body["exclude_patterns"] = excludePatterns }
        if let sameDomainOnly = options.sameDomainOnly { body["same_domain_only"] = sameDomainOnly }
        if let respectRobots = options.respectRobots { body["respect_robots"] = respectRobots }
        let data = try await post("/v2/discover", body: body)
        return try Self.toDiscoverResult(data)
    }

    // ------------------------------------------------------------------
    // Lookup — web search with optional auto-perceive
    // ------------------------------------------------------------------

    /// Run a categorized web search. With `perceiveTop > 0`, the top-N
    /// result URLs are auto-perceived (each consumes one perceive-quota
    /// unit) and carry their full `PerceiveResult` inline.
    public func lookup(_ query: String, options: LookupOptions = LookupOptions()) async throws -> LookupResult {
        var body: [String: Any] = ["query": query]
        if let category = options.category { body["category"] = category.rawValue }
        if let country = options.country { body["country"] = country }
        if let locale = options.locale { body["locale"] = locale }
        if let timeFilter = options.timeFilter { body["time_filter"] = timeFilter.rawValue }
        if let numResults = options.numResults { body["num_results"] = numResults }
        if let page = options.page { body["page"] = page }
        if let location = options.location { body["location"] = location }
        if let autocorrect = options.autocorrect { body["autocorrect"] = autocorrect }
        if let perceiveTop = options.perceiveTop { body["perceive_top"] = perceiveTop }
        let data = try await post("/v2/lookup", body: body)
        return try Self.toLookupResult(data)
    }

    // ------------------------------------------------------------------
    // Distill — schema-driven structured extraction
    // ------------------------------------------------------------------

    /// Extract structured data matching `schema` from explicit URLs or from
    /// a discovered site. An optional `cssSchema` answers fields for free;
    /// anything it misses escalates to the LLM tier (plan-gated).
    public func distill(_ options: DistillOptions) async throws -> DistillResult {
        let hasUrls = !(options.urls ?? []).isEmpty
        let hasDiscover = options.discoverFrom != nil
        guard hasUrls != hasDiscover else {
            throw EnconvertError.invalidArgument("distill: provide exactly one of 'urls' or 'discoverFrom'")
        }

        var body: [String: Any] = ["schema": options.schema.jsonSerializable]
        if hasUrls { body["urls"] = options.urls }
        if let discoverFrom = options.discoverFrom {
            var df: [String: Any] = ["url": discoverFrom.url]
            if let mode = discoverFrom.mode { df["mode"] = mode.rawValue }
            if let maxPages = discoverFrom.maxPages { df["max_pages"] = maxPages }
            body["discover_from"] = df
        }
        if let cssSchema = options.cssSchema { body["css_schema"] = Self.serializeCssSchema(cssSchema) }
        if let waitFor = options.waitFor { body["wait_for"] = waitFor }
        if let waitTimeoutMs = options.waitTimeoutMs { body["wait_timeout_ms"] = waitTimeoutMs }
        if let headers = options.headers { body["headers"] = headers }
        if let cookies = options.cookies { body["cookies"] = cookies.map { $0.toJSONDict() } }
        if let respectRobots = options.respectRobots { body["respect_robots"] = respectRobots }
        let data = try await post("/v2/distill", body: body)
        return Self.toDistillResult(data)
    }

    // ------------------------------------------------------------------
    // Ingest — site to RAG-ready JSONL chunks (always async)
    // ------------------------------------------------------------------

    /// Start an ingest job: turn explicit URLs or a discovered site into
    /// chunked, RAG-ready JSONL. Always asynchronous — returns the queued
    /// job; poll `getIngestJob` or configure `webhookUrl` for completion.
    public func ingest(_ options: IngestOptions) async throws -> IngestJob {
        let mode = options.mode ?? .urls
        switch mode {
        case .urls:
            guard let urls = options.urls, !urls.isEmpty else {
                throw EnconvertError.invalidArgument("ingest: mode 'urls' requires a non-empty 'urls' list")
            }
            guard options.url == nil else {
                throw EnconvertError.invalidArgument("ingest: mode 'urls' does not accept 'url'")
            }
        default:
            guard let seedUrl = options.url, !seedUrl.isEmpty else {
                throw EnconvertError.invalidArgument("ingest: mode '\(mode.rawValue)' requires a seed 'url'")
            }
            guard options.urls == nil else {
                throw EnconvertError.invalidArgument("ingest: mode '\(mode.rawValue)' does not accept 'urls'")
            }
        }

        var body: [String: Any] = [:]
        if let optMode = options.mode { body["mode"] = optMode.rawValue }
        if let url = options.url { body["url"] = url }
        if let urls = options.urls { body["urls"] = urls }
        if let maxPages = options.maxPages { body["max_pages"] = maxPages }
        if let maxDepth = options.maxDepth { body["max_depth"] = maxDepth }
        if let sameDomainOnly = options.sameDomainOnly { body["same_domain_only"] = sameDomainOnly }
        if let includePatterns = options.includePatterns { body["include_patterns"] = includePatterns }
        if let excludePatterns = options.excludePatterns { body["exclude_patterns"] = excludePatterns }
        if let respectRobots = options.respectRobots { body["respect_robots"] = respectRobots }
        if let waitFor = options.waitFor { body["wait_for"] = waitFor }
        if let waitTimeoutMs = options.waitTimeoutMs { body["wait_timeout_ms"] = waitTimeoutMs }
        if let chunk = options.chunk {
            var chunkDict: [String: Any] = [:]
            if let maxWords = chunk.maxWords { chunkDict["max_words"] = maxWords }
            if let sentenceOverlap = chunk.sentenceOverlap { chunkDict["sentence_overlap"] = sentenceOverlap }
            body["chunk"] = chunkDict
        }
        if let webhookUrl = options.webhookUrl { body["webhook_url"] = webhookUrl }
        let data = try await post("/v2/ingest", body: body)
        return try Self.toIngestJob(data)
    }

    /// Ingest one or more uploaded FILES into RAG-ready JSONL chunks — the
    /// file counterpart of `ingest`, sharing the same job lifecycle (mode
    /// `.files`). PDF, DOCX, PPTX, XLSX, CSV, HTML, EPUB, TXT/MD and
    /// legacy/ODF office are accepted. Always asynchronous; poll
    /// `getIngestJob` or configure a webhook.
    public func ingestFiles(_ files: [FileInput], options: IngestFilesOptions = IngestFilesOptions()) async throws -> IngestJob {
        guard !files.isEmpty else {
            throw EnconvertError.invalidArgument("ingestFiles: provide at least one file")
        }
        let boundary = Internal.newMultipartBoundary()
        var body = Data()
        for file in files {
            let part = try Internal.toFilePart(file)
            Internal.appendMultipartFile(
                &body,
                boundary: boundary,
                name: "files",
                filename: part.filename,
                contentType: part.contentType,
                fileData: part.bytes
            )
        }
        if let maxWords = options.chunk?.maxWords {
            Internal.appendMultipartField(&body, boundary: boundary, name: "max_words", value: String(maxWords))
        }
        if let sentenceOverlap = options.chunk?.sentenceOverlap {
            Internal.appendMultipartField(&body, boundary: boundary, name: "sentence_overlap", value: String(sentenceOverlap))
        }
        if let webhookUrl = options.webhookUrl {
            Internal.appendMultipartField(&body, boundary: boundary, name: "webhook_url", value: webhookUrl)
        }
        Internal.endMultipart(&body, boundary: boundary)

        let (data, statusCode) = try await transport.sendMultipart(path: "/v2/ingest/files", method: "POST", body: body, boundary: boundary)
        try Internal.raiseForStatus(statusCode: statusCode, data: data)
        return try Self.toIngestJob(Transport.decodeJSONObject(data))
    }

    /// List ingest jobs, newest first.
    public func listIngestJobs(_ options: V2ListOptions = V2ListOptions()) async throws -> IngestJobList {
        let data = try await get("/v2/ingest\(Self.listQuery(options))")
        let jobs = try jsonDictArray(data, "jobs").map { try Self.toIngestJobSummary($0) }
        return IngestJobList(
            jobs: jobs,
            skip: jsonInt(data, "skip"),
            limit: jsonInt(data, "limit", default: 20),
            hasMore: jsonBool(data, "has_more")
        )
    }

    /// Get one ingest job by id (`ing_...`).
    public func getIngestJob(_ jobId: String) async throws -> IngestJob {
        let data = try await get("/v2/ingest/\(Internal.percentEncodePathComponent(jobId))")
        return try Self.toIngestJob(data)
    }

    /// Cancel a queued/processing ingest job. Idempotent: canceling an
    /// already-terminal job returns it unchanged.
    public func cancelIngestJob(_ jobId: String) async throws -> IngestJob {
        let data = try await requestJSON(path: "/v2/ingest/\(Internal.percentEncodePathComponent(jobId))", method: "DELETE")
        return try Self.toIngestJob(data)
    }

    /// Re-deliver the completion webhook of a completed job (409 if the job
    /// is not completed, 400 if it has no webhook configured).
    public func retryIngestWebhook(_ jobId: String) async throws -> WebhookRetryResult {
        let data = try await post("/v2/ingest/\(Internal.percentEncodePathComponent(jobId))/retry-webhook", body: nil)
        return WebhookRetryResult(
            jobId: jsonString(data, "job_id"),
            delivered: jsonBool(data, "delivered"),
            attempts: jsonInt(data, "attempts"),
            statusCode: jsonOptInt(data, "status_code"),
            detail: jsonString(data, "detail")
        )
    }

    /// Get (creating on first call) the project's webhook signing secret
    /// and the header/scheme details needed to verify deliveries.
    public func getWebhookSecret() async throws -> WebhookSecret {
        Self.toWebhookSecret(try await get("/v2/ingest/webhook-secret"))
    }

    /// Rotate the webhook signing secret. Signatures made with the previous
    /// secret stop verifying immediately.
    public func rotateWebhookSecret() async throws -> WebhookSecret {
        Self.toWebhookSecret(try await post("/v2/ingest/webhook-secret/rotate", body: nil))
    }

    // ------------------------------------------------------------------
    // Watch — recurring change monitoring
    // ------------------------------------------------------------------

    /// Create a watcher that re-renders `url` on a fixed cadence (hourly
    /// floor) and notifies on changes via email and/or webhook.
    public func createWatcher(_ url: String, options: WatchCreateOptions = WatchCreateOptions()) async throws -> Watcher {
        var body: [String: Any] = ["url": url]
        if let frequencyMinutes = options.frequencyMinutes { body["frequency_minutes"] = frequencyMinutes }
        if let diffMode = options.diffMode { body["diff_mode"] = diffMode.rawValue }
        if let trackFields = options.trackFields { body["track_fields"] = trackFields.jsonSerializable }
        if let webhookUrl = options.webhookUrl { body["webhook_url"] = webhookUrl }
        if let notifyEmail = options.notifyEmail { body["notify_email"] = notifyEmail }
        let data = try await post("/v2/watch", body: body)
        return try Self.toWatcher(data)
    }

    /// List watchers, newest first.
    public func listWatchers(_ options: V2ListOptions = V2ListOptions()) async throws -> WatcherList {
        let data = try await get("/v2/watch\(Self.listQuery(options))")
        let watchers = try jsonDictArray(data, "watchers").map { try Self.toWatcherSummary($0) }
        return WatcherList(
            watchers: watchers,
            skip: jsonInt(data, "skip"),
            limit: jsonInt(data, "limit", default: 20),
            hasMore: jsonBool(data, "has_more")
        )
    }

    /// Get one watcher by id (`wat_...`). Deleted watchers read as 404.
    public func getWatcher(_ watcherId: String) async throws -> Watcher {
        let data = try await get("/v2/watch/\(Internal.percentEncodePathComponent(watcherId))")
        return try Self.toWatcher(data)
    }

    /// Page through a watcher's check history, newest first.
    public func getWatcherSnapshots(
        _ watcherId: String,
        options: SnapshotListOptions = SnapshotListOptions()
    ) async throws -> WatcherSnapshotList {
        let query = options.limit.map { "?limit=\($0)" } ?? ""
        let data = try await get("/v2/watch/\(Internal.percentEncodePathComponent(watcherId))/snapshots\(query)")
        let snapshots = jsonDictArray(data, "snapshots").map { Self.toWatcherSnapshot($0) }
        return WatcherSnapshotList(
            watcherId: jsonString(data, "watcher_id"),
            snapshots: snapshots,
            limit: jsonInt(data, "limit", default: 20)
        )
    }

    /// Update a watcher. At least one field is required. Set `webhookUrl`
    /// to `""` to clear the webhook; resuming a paused watcher re-checks
    /// the plan's watcher cap.
    public func updateWatcher(_ watcherId: String, updates: WatcherUpdate) async throws -> Watcher {
        var body: [String: Any] = [:]
        if let frequencyMinutes = updates.frequencyMinutes { body["frequency_minutes"] = frequencyMinutes }
        if let diffMode = updates.diffMode { body["diff_mode"] = diffMode.rawValue }
        if let trackFields = updates.trackFields { body["track_fields"] = trackFields.jsonSerializable }
        if let webhookUrl = updates.webhookUrl { body["webhook_url"] = webhookUrl }
        if let notifyEmail = updates.notifyEmail { body["notify_email"] = notifyEmail }
        if let status = updates.status { body["status"] = status.rawValue }
        guard !body.isEmpty else {
            throw EnconvertError.invalidArgument("updateWatcher: provide at least one field to update")
        }
        let data = try await requestJSON(
            path: "/v2/watch/\(Internal.percentEncodePathComponent(watcherId))",
            method: "PATCH",
            jsonBody: body
        )
        return try Self.toWatcher(data)
    }

    /// Soft-delete a watcher (idempotent). Returns the tombstoned watcher
    /// with status `.deleted`.
    public func deleteWatcher(_ watcherId: String) async throws -> Watcher {
        let data = try await requestJSON(path: "/v2/watch/\(Internal.percentEncodePathComponent(watcherId))", method: "DELETE")
        return try Self.toWatcher(data)
    }

    // ------------------------------------------------------------------
    // HTTP helpers
    // ------------------------------------------------------------------

    private func requestJSON(path: String, method: String, jsonBody: [String: Any]? = nil) async throws -> [String: Any] {
        try await transport.requestJSON(path: path, method: method, jsonBody: jsonBody)
    }

    private func post(_ path: String, body: [String: Any]?) async throws -> [String: Any] {
        try await requestJSON(path: path, method: "POST", jsonBody: body)
    }

    private func get(_ path: String) async throws -> [String: Any] {
        try await requestJSON(path: path, method: "GET")
    }

    // ------------------------------------------------------------------
    // Request serializers
    // ------------------------------------------------------------------

    private static func serializePerceiveOptions(_ o: any PerceiveRenderOptions) -> [String: Any] {
        var out: [String: Any] = [:]
        if let outputs = o.outputs { out["outputs"] = outputs.map { $0.rawValue } }
        if let extract = o.extract { out["extract"] = extract.map { $0.rawValue } }
        if let schema = o.schema { out["schema"] = schema.jsonSerializable }
        if let waitFor = o.waitFor { out["wait_for"] = waitFor }
        if let waitTimeoutMs = o.waitTimeoutMs { out["wait_timeout_ms"] = waitTimeoutMs }
        if let jsCode = o.jsCode { out["js_code"] = jsCode }
        if let viewport = o.viewport {
            var viewportDict: [String: Any] = [:]
            if let width = viewport.width { viewportDict["width"] = width }
            if let height = viewport.height { viewportDict["height"] = height }
            out["viewport"] = viewportDict
        }
        if let headers = o.headers { out["headers"] = headers }
        if let cookies = o.cookies { out["cookies"] = cookies.map { $0.toJSONDict() } }
        if let auth = o.auth { out["auth"] = auth.toJSONDict() }
        if let proxyUrl = o.proxyUrl { out["proxy_url"] = proxyUrl }
        if let geolocation = o.geolocation { out["geolocation"] = geolocation.jsonSerializable }
        if let actionChain = o.actionChain { out["action_chain"] = actionChain.map { $0.jsonSerializable } }
        if let cacheMode = o.cacheMode { out["cache_mode"] = cacheMode.rawValue }
        if let pdfOptions = o.pdfOptions { out["pdf_options"] = pdfOptions.toJSONDict() }
        if let blockResources = o.blockResources { out["block_resources"] = blockResources.map { $0.rawValue } }
        if let respectRobots = o.respectRobots { out["respect_robots"] = respectRobots }
        if let mobile = o.mobile { out["mobile"] = mobile }
        if let onlyMainContent = o.onlyMainContent { out["only_main_content"] = onlyMainContent }
        if let directDownload = o.directDownload { out["direct_download"] = directDownload }
        return out
    }

    private static func serializeCssField(_ f: CssField) -> [String: Any] {
        var out: [String: Any] = ["name": f.name, "type": f.type.rawValue]
        if let selector = f.selector { out["selector"] = selector }
        if let attribute = f.attribute { out["attribute"] = attribute }
        if let pattern = f.pattern { out["pattern"] = pattern }
        if let defaultValue = f.defaultValue { out["default"] = defaultValue.jsonSerializable }
        if let transform = f.transform { out["transform"] = transform.rawValue }
        if let fields = f.fields { out["fields"] = fields.map { serializeCssField($0) } }
        return out
    }

    private static func serializeCssSchema(_ s: CssSchema) -> [String: Any] {
        // Note: `baseSelector` is intentionally NOT snake_cased — the
        // reference implementation sends it camelCase on the wire.
        var out: [String: Any] = [
            "baseSelector": s.baseSelector,
            "fields": s.fields.map { serializeCssField($0) },
        ]
        if let name = s.name { out["name"] = name }
        if let targetField = s.targetField { out["target_field"] = targetField }
        return out
    }

    // ------------------------------------------------------------------
    // Response mappers. Optional fields may be absent entirely
    // (response_model_exclude_none) — every access is guarded.
    // ------------------------------------------------------------------

    private static func toTokens(_ data: [String: Any]?) -> V2Tokens {
        guard let data else { return V2Tokens(input: 0, output: 0) }
        return V2Tokens(input: jsonInt(data, "input"), output: jsonInt(data, "output"))
    }

    private static func toOutputArtifact(_ data: [String: Any]) -> V2OutputArtifact {
        V2OutputArtifact(
            url: jsonOptString(data, "url"),
            objectKey: jsonString(data, "object_key"),
            sizeBytes: jsonInt(data, "size_bytes"),
            contentType: jsonString(data, "content_type", default: "application/octet-stream"),
            expiresIn: jsonInt(data, "expires_in", default: 900)
        )
    }

    private static func toPerceiveResult(_ data: [String: Any]) throws -> PerceiveResult {
        let rawOutputs = jsonDict(data, "outputs") ?? [:]
        var outputs: [String: V2OutputArtifact] = [:]
        for (name, artifact) in rawOutputs {
            if let artifactDict = artifact as? [String: Any] {
                outputs[name] = toOutputArtifact(artifactDict)
            }
        }
        let deductionsRaw = jsonDict(data, "deductions") ?? [:]
        var deductions: [String: Double] = [:]
        for (name, value) in deductionsRaw {
            if let doubleValue = value as? Double {
                deductions[name] = doubleValue
            } else if let intValue = value as? Int {
                deductions[name] = Double(intValue)
            }
        }
        let status = try jsonRequiredEnum(data, "status", as: PerceiveStatus.self)
        return PerceiveResult(
            operationId: jsonString(data, "operation_id"),
            status: status,
            url: jsonString(data, "url"),
            urlFinal: jsonOptString(data, "url_final"),
            contentHash: jsonOptString(data, "content_hash"),
            renderQuality: jsonOptDouble(data, "render_quality"),
            statusCode: jsonOptInt(data, "status_code"),
            deductions: deductions,
            cacheHit: jsonBool(data, "cache_hit"),
            outputs: outputs,
            structured: jsonDict(data, "structured").map { JSONObject.from($0) },
            extractionTier: jsonOptString(data, "extraction_tier").flatMap { PerceiveExtractionTier(rawValue: $0) },
            tokens: toTokens(jsonDict(data, "tokens")),
            costCents: jsonInt(data, "cost_cents"),
            durationMs: jsonOptInt(data, "duration_ms"),
            error: jsonOptString(data, "error"),
            warnings: jsonStringArray(data, "warnings"),
            optionsEcho: jsonDict(data, "options_echo").map { JSONObject.from($0) }
        )
    }

    private static func toPerceiveDirectResult(_ data: Data, headers: [String: String]) -> PerceiveDirectResult {
        PerceiveDirectResult(
            content: data,
            contentType: headers["content-type"] ?? "application/octet-stream",
            filename: headers["content-disposition"].flatMap { Internal.filenameFromContentDisposition($0) },
            operationId: headers["x-operation-id"] ?? "",
            objectKey: headers["x-object-key"] ?? "",
            cacheHit: headers["x-cache-hit"] == "true",
            renderQuality: headers["x-render-quality"].flatMap { Double($0) },
            sourceStatusCode: headers["x-source-status-code"].flatMap { Int($0) },
            contentHash: headers["x-content-hash"],
            warningsCount: headers["x-warnings-count"].flatMap { Int($0) } ?? 0
        )
    }

    private static func toPerceiveBatchResult(_ data: [String: Any]) throws -> PerceiveBatchResult {
        let status = try jsonRequiredEnum(data, "status", as: PerceiveBatchStatus.self)
        let outputMode = jsonOptString(data, "output_mode").flatMap { PerceiveBatchOutputMode(rawValue: $0) } ?? .manifest
        let items = try jsonDictArray(data, "items").map { try toPerceiveResult($0) }
        let zip = jsonDict(data, "zip").map { toOutputArtifact($0) }
        return PerceiveBatchResult(
            jobId: jsonString(data, "job_id"),
            status: status,
            outputMode: outputMode,
            total: jsonInt(data, "total"),
            completed: jsonInt(data, "completed"),
            failed: jsonInt(data, "failed"),
            pending: jsonInt(data, "pending"),
            zip: zip,
            items: items,
            warnings: jsonStringArray(data, "warnings")
        )
    }

    private static func toDiscoverResult(_ data: [String: Any]) throws -> DiscoverResult {
        let mode = try jsonRequiredEnum(data, "mode", as: DiscoverMode.self)
        let sourcesRaw = jsonDict(data, "sources") ?? [:]
        var sources: [String: Int] = [:]
        for (key, value) in sourcesRaw {
            if let intValue = value as? Int {
                sources[key] = intValue
            } else if let doubleValue = value as? Double {
                sources[key] = Int(doubleValue)
            }
        }
        return DiscoverResult(
            url: jsonString(data, "url"),
            mode: mode,
            total: jsonInt(data, "total"),
            urls: jsonStringArray(data, "urls"),
            pagesCrawled: jsonInt(data, "pages_crawled"),
            truncated: jsonBool(data, "truncated"),
            robotsRespected: jsonBool(data, "robots_respected"),
            sources: sources,
            warnings: jsonStringArray(data, "warnings")
        )
    }

    private static func toLookupItem(_ data: [String: Any]) throws -> LookupItem {
        let perceive = jsonDict(data, "perceive")
        return LookupItem(
            title: jsonOptString(data, "title"),
            url: jsonOptString(data, "url"),
            snippet: jsonOptString(data, "snippet"),
            position: jsonOptInt(data, "position"),
            source: jsonOptString(data, "source"),
            date: jsonOptString(data, "date"),
            imageUrl: jsonOptString(data, "image_url"),
            thumbnailUrl: jsonOptString(data, "thumbnail_url"),
            extra: jsonDict(data, "extra").map { JSONObject.from($0) } ?? [:],
            perceive: try perceive.map { try toPerceiveResult($0) }
        )
    }

    private static func toLookupResult(_ data: [String: Any]) throws -> LookupResult {
        let category = try jsonRequiredEnum(data, "category", as: LookupCategory.self)
        let results = try jsonDictArray(data, "results").map { try toLookupItem($0) }
        return LookupResult(
            lookupId: jsonOptInt(data, "lookup_id"),
            query: jsonString(data, "query"),
            category: category,
            country: jsonOptString(data, "country"),
            locale: jsonOptString(data, "locale"),
            timeFilter: jsonOptString(data, "time_filter").flatMap { LookupTimeFilter(rawValue: $0) },
            total: jsonInt(data, "total"),
            results: results,
            perceiveTop: jsonInt(data, "perceive_top"),
            perceiveOperationIds: jsonStringArray(data, "perceive_operation_ids"),
            answerBox: jsonDict(data, "answer_box").map { JSONObject.from($0) },
            knowledgeGraph: jsonDict(data, "knowledge_graph").map { JSONObject.from($0) },
            credits: jsonOptInt(data, "credits"),
            costCents: jsonInt(data, "cost_cents"),
            warnings: jsonStringArray(data, "warnings")
        )
    }

    private static func toDistillItem(_ data: [String: Any]) -> DistillItem {
        let status = jsonOptString(data, "status").flatMap { DistillItemStatus(rawValue: $0) } ?? .completed
        let extractionTier = jsonOptString(data, "extraction_tier").flatMap { DistillExtractionTier(rawValue: $0) } ?? .none
        return DistillItem(
            url: jsonString(data, "url"),
            urlFinal: jsonOptString(data, "url_final"),
            status: status,
            data: jsonDict(data, "data").map { JSONObject.from($0) },
            extractionTier: extractionTier,
            fieldsFromCss: jsonInt(data, "fields_from_css"),
            fieldsFromLlm: jsonInt(data, "fields_from_llm"),
            renderQuality: jsonOptDouble(data, "render_quality"),
            tokens: toTokens(jsonDict(data, "tokens")),
            costCents: jsonInt(data, "cost_cents"),
            error: jsonOptString(data, "error"),
            warnings: jsonStringArray(data, "warnings")
        )
    }

    private static func toDistillResult(_ data: [String: Any]) -> DistillResult {
        DistillResult(
            operationId: jsonString(data, "operation_id"),
            total: jsonInt(data, "total"),
            completed: jsonInt(data, "completed"),
            failed: jsonInt(data, "failed"),
            results: jsonDictArray(data, "results").map { toDistillItem($0) },
            totalCostCents: jsonInt(data, "total_cost_cents"),
            warnings: jsonStringArray(data, "warnings")
        )
    }

    private static func toIngestJob(_ data: [String: Any]) throws -> IngestJob {
        let status = try jsonRequiredEnum(data, "status", as: IngestStatus.self)
        let mode = try jsonRequiredEnum(data, "mode", as: IngestMode.self)
        return IngestJob(
            jobId: jsonString(data, "job_id"),
            status: status,
            mode: mode,
            pagesDiscovered: jsonInt(data, "pages_discovered"),
            pagesProcessed: jsonInt(data, "pages_processed"),
            pagesFailed: jsonInt(data, "pages_failed"),
            totalChunks: jsonInt(data, "total_chunks"),
            outputUrl: jsonOptString(data, "output_url"),
            errorMessage: jsonOptString(data, "error_message"),
            webhookUrl: jsonOptString(data, "webhook_url"),
            webhookDelivered: jsonBool(data, "webhook_delivered"),
            createdAt: jsonOptString(data, "created_at"),
            completedAt: jsonOptString(data, "completed_at"),
            warnings: jsonStringArray(data, "warnings")
        )
    }

    private static func toIngestJobSummary(_ data: [String: Any]) throws -> IngestJobSummary {
        let status = try jsonRequiredEnum(data, "status", as: IngestStatus.self)
        let mode = try jsonRequiredEnum(data, "mode", as: IngestMode.self)
        return IngestJobSummary(
            jobId: jsonString(data, "job_id"),
            status: status,
            mode: mode,
            pagesDiscovered: jsonInt(data, "pages_discovered"),
            pagesProcessed: jsonInt(data, "pages_processed"),
            pagesFailed: jsonInt(data, "pages_failed"),
            totalChunks: jsonInt(data, "total_chunks"),
            outputUrl: jsonOptString(data, "output_url"),
            errorMessage: jsonOptString(data, "error_message"),
            webhookConfigured: jsonBool(data, "webhook_configured"),
            webhookDelivered: jsonBool(data, "webhook_delivered"),
            createdAt: jsonOptString(data, "created_at"),
            completedAt: jsonOptString(data, "completed_at")
        )
    }

    private static func toWebhookSecret(_ data: [String: Any]) -> WebhookSecret {
        WebhookSecret(
            secret: jsonString(data, "secret"),
            signatureHeader: jsonString(data, "signature_header"),
            timestampHeader: jsonString(data, "timestamp_header"),
            signatureScheme: jsonString(data, "signature_scheme"),
            replayToleranceSeconds: jsonInt(data, "replay_tolerance_seconds"),
            rotated: jsonBool(data, "rotated")
        )
    }

    private static func toWatcher(_ data: [String: Any]) throws -> Watcher {
        let status = try jsonRequiredEnum(data, "status", as: WatcherStatus.self)
        let diffMode = try jsonRequiredEnum(data, "diff_mode", as: WatchDiffMode.self)
        return Watcher(
            watcherId: jsonString(data, "watcher_id"),
            url: jsonString(data, "url"),
            status: status,
            frequencyMinutes: jsonInt(data, "frequency_minutes"),
            diffMode: diffMode,
            trackFields: jsonDict(data, "track_fields").map { JSONObject.from($0) },
            webhookUrl: jsonOptString(data, "webhook_url"),
            notifyEmail: jsonBoolDefaultTrue(data, "notify_email"),
            consecutiveErrors: jsonInt(data, "consecutive_errors"),
            checksCount: jsonInt(data, "checks_count"),
            lastCheckAt: jsonOptString(data, "last_check_at"),
            nextCheckAt: jsonOptString(data, "next_check_at"),
            lastChangeAt: jsonOptString(data, "last_change_at"),
            createdAt: jsonOptString(data, "created_at"),
            updatedAt: jsonOptString(data, "updated_at")
        )
    }

    private static func toWatcherSummary(_ data: [String: Any]) throws -> WatcherSummary {
        let status = try jsonRequiredEnum(data, "status", as: WatcherStatus.self)
        return WatcherSummary(
            watcherId: jsonString(data, "watcher_id"),
            url: jsonString(data, "url"),
            status: status,
            frequencyMinutes: jsonInt(data, "frequency_minutes"),
            checksCount: jsonInt(data, "checks_count"),
            consecutiveErrors: jsonInt(data, "consecutive_errors"),
            lastCheckAt: jsonOptString(data, "last_check_at"),
            nextCheckAt: jsonOptString(data, "next_check_at"),
            lastChangeAt: jsonOptString(data, "last_change_at"),
            createdAt: jsonOptString(data, "created_at")
        )
    }

    private static func toWatcherSnapshot(_ data: [String: Any]) -> WatcherSnapshot {
        WatcherSnapshot(
            checkedAt: jsonString(data, "checked_at"),
            hasChanges: jsonBool(data, "has_changes"),
            similarity: jsonOptDouble(data, "similarity"),
            renderQuality: jsonOptDouble(data, "render_quality"),
            changeCount: jsonInt(data, "change_count"),
            changes: jsonDictArray(data, "changes").map { JSONObject.from($0) }
        )
    }

    private static func listQuery(_ options: V2ListOptions) -> String {
        var params: [(String, String)] = []
        if let skip = options.skip { params.append(("skip", String(skip))) }
        if let limit = options.limit { params.append(("limit", String(limit))) }
        return Internal.queryString(params)
    }
}
