/**
 * V2 API option and result types (distill, ingest, watch).
 * See `V2Types.swift` for the perceive/discover/lookup half and a note on
 * why these result types are `Codable` without being decoded directly from
 * raw API responses.
 */

import Foundation

// MARK: - CSS extraction schema (distill)

public enum CssFieldType: String, Codable, Sendable {
    case text
    case attribute
    case html
    case regex
    case nested
    case list
    case nestedList = "nested_list"
}

public enum CssFieldTransform: String, Codable, Sendable {
    case lowercase
    case uppercase
    case strip
}

/// One field of a CSS extraction schema (recursive for nested types).
///
/// Note: the wire field `default` is named `defaultValue` here since
/// `default` is a Swift keyword.
public struct CssField: Sendable {
    public var name: String
    public var type: CssFieldType
    public var selector: String?
    /// Required when type is `.attribute`.
    public var attribute: String?
    /// Required when type is `.regex`. Compiled server-side; ReDoS-screened.
    public var pattern: String?
    public var defaultValue: JSONValue?
    public var transform: CssFieldTransform?
    /// Required (non-empty) for `.nested` / `.list` / `.nestedList`. Max depth 5.
    public var fields: [CssField]?

    public init(
        name: String,
        type: CssFieldType,
        selector: String? = nil,
        attribute: String? = nil,
        pattern: String? = nil,
        defaultValue: JSONValue? = nil,
        transform: CssFieldTransform? = nil,
        fields: [CssField]? = nil
    ) {
        self.name = name
        self.type = type
        self.selector = selector
        self.attribute = attribute
        self.pattern = pattern
        self.defaultValue = defaultValue
        self.transform = transform
        self.fields = fields
    }
}

/// Free CSS extraction pass run before any LLM escalation.
public struct CssSchema: Sendable {
    /// Matches the repeating container; one extracted record per match.
    public var baseSelector: String
    public var fields: [CssField]
    public var name: String?
    /// Top-level output-schema property the CSS records fill. Array property
    /// receives the full list; scalar/object the first record. Inferred when
    /// omitted and the schema has exactly one array property.
    public var targetField: String?

    public init(baseSelector: String, fields: [CssField], name: String? = nil, targetField: String? = nil) {
        self.baseSelector = baseSelector
        self.fields = fields
        self.name = name
        self.targetField = targetField
    }
}

// MARK: - Distill

public struct DistillDiscoverFrom: Sendable {
    public var url: String
    /// Default `.hybrid`.
    public var mode: DiscoverMode?
    /// 1-50, default 10. Cap on URLs discovered AND distilled.
    public var maxPages: Int?

    public init(url: String, mode: DiscoverMode? = nil, maxPages: Int? = nil) {
        self.url = url
        self.mode = mode
        self.maxPages = maxPages
    }
}

public struct DistillOptions: Sendable {
    /// Explicit URLs to distill (max 50). Exactly one of `urls`/`discoverFrom`.
    public var urls: [String]?
    /// Discover a site's URLs first, then distill each.
    public var discoverFrom: DistillDiscoverFrom?
    /// Required output shape: a JSON-Schema object
    /// (`{"type": "object", "properties": {...}}`) or a flat
    /// `{field: description}` map. The response data matches this shape.
    public var schema: JSONObject
    /// Optional free CSS pass; missing fields escalate to the LLM tier.
    public var cssSchema: CssSchema?
    public var waitFor: String?
    /// 0-60000, default 30000.
    public var waitTimeoutMs: Int?
    public var headers: [String: String]?
    public var cookies: [BrowserCookie]?
    public var respectRobots: Bool?

    public init(
        urls: [String]? = nil,
        discoverFrom: DistillDiscoverFrom? = nil,
        schema: JSONObject,
        cssSchema: CssSchema? = nil,
        waitFor: String? = nil,
        waitTimeoutMs: Int? = nil,
        headers: [String: String]? = nil,
        cookies: [BrowserCookie]? = nil,
        respectRobots: Bool? = nil
    ) {
        self.urls = urls
        self.discoverFrom = discoverFrom
        self.schema = schema
        self.cssSchema = cssSchema
        self.waitFor = waitFor
        self.waitTimeoutMs = waitTimeoutMs
        self.headers = headers
        self.cookies = cookies
        self.respectRobots = respectRobots
    }
}

public enum DistillExtractionTier: String, Codable, Sendable {
    case css
    case llm
    case mixed
    case none
}

public enum DistillItemStatus: String, Codable, Sendable {
    case completed
    case failed
}

public struct DistillItem: Codable, Equatable, Sendable {
    public let url: String
    public let urlFinal: String?
    public let status: DistillItemStatus
    /// Extracted data matching the requested schema.
    public let data: JSONObject?
    public let extractionTier: DistillExtractionTier
    public let fieldsFromCss: Int
    public let fieldsFromLlm: Int
    public let renderQuality: Double?
    public let tokens: V2Tokens
    public let costCents: Int
    public let error: String?
    public let warnings: [String]

    enum CodingKeys: String, CodingKey {
        case url
        case urlFinal = "url_final"
        case status, data
        case extractionTier = "extraction_tier"
        case fieldsFromCss = "fields_from_css"
        case fieldsFromLlm = "fields_from_llm"
        case renderQuality = "render_quality"
        case tokens
        case costCents = "cost_cents"
        case error, warnings
    }
}

public struct DistillResult: Codable, Equatable, Sendable {
    public let operationId: String
    public let total: Int
    public let completed: Int
    public let failed: Int
    public let results: [DistillItem]
    public let totalCostCents: Int
    public let warnings: [String]

    enum CodingKeys: String, CodingKey {
        case operationId = "operation_id"
        case total, completed, failed, results
        case totalCostCents = "total_cost_cents"
        case warnings
    }
}

// MARK: - Ingest

public enum IngestMode: String, Codable, Sendable {
    case urls
    case sitemap
    case crawl
    case files
}

public enum IngestStatus: String, Codable, Sendable {
    case queued
    case discovering
    case processing
    case completed
    case failed
    case canceled
}

public struct IngestChunkOptions: Sendable {
    /// Words per chunk, 32-4000, default 512.
    public var maxWords: Int?
    /// Sentences repeated between consecutive chunks, 0-10, default 1.
    public var sentenceOverlap: Int?

    public init(maxWords: Int? = nil, sentenceOverlap: Int? = nil) {
        self.maxWords = maxWords
        self.sentenceOverlap = sentenceOverlap
    }
}

public struct IngestOptions: Sendable {
    /// Default `.urls`.
    public var mode: IngestMode?
    /// Seed URL — required for `.sitemap`/`.crawl`, forbidden for `.urls`.
    public var url: String?
    /// Explicit URLs (max 1000) — required for `.urls`, forbidden otherwise.
    public var urls: [String]?
    /// Discovery cap for sitemap/crawl, 1-1000, default 50.
    public var maxPages: Int?
    /// 1-5, default 2.
    public var maxDepth: Int?
    /// Default true.
    public var sameDomainOnly: Bool?
    public var includePatterns: [String]?
    public var excludePatterns: [String]?
    public var respectRobots: Bool?
    public var waitFor: String?
    public var waitTimeoutMs: Int?
    public var chunk: IngestChunkOptions?
    /// Completion webhook, HMAC-signed (see `getWebhookSecret`).
    public var webhookUrl: String?

    public init(
        mode: IngestMode? = nil,
        url: String? = nil,
        urls: [String]? = nil,
        maxPages: Int? = nil,
        maxDepth: Int? = nil,
        sameDomainOnly: Bool? = nil,
        includePatterns: [String]? = nil,
        excludePatterns: [String]? = nil,
        respectRobots: Bool? = nil,
        waitFor: String? = nil,
        waitTimeoutMs: Int? = nil,
        chunk: IngestChunkOptions? = nil,
        webhookUrl: String? = nil
    ) {
        self.mode = mode
        self.url = url
        self.urls = urls
        self.maxPages = maxPages
        self.maxDepth = maxDepth
        self.sameDomainOnly = sameDomainOnly
        self.includePatterns = includePatterns
        self.excludePatterns = excludePatterns
        self.respectRobots = respectRobots
        self.waitFor = waitFor
        self.waitTimeoutMs = waitTimeoutMs
        self.chunk = chunk
        self.webhookUrl = webhookUrl
    }
}

/// Options for `ingestFiles` (POST /v2/ingest/files). Uploaded documents are
/// converted to Markdown and chunked through the same pipeline as `ingest`.
public struct IngestFilesOptions: Sendable {
    /// Heading-aware chunker parameters.
    public var chunk: IngestChunkOptions?
    /// Completion webhook, HMAC-signed (see `getWebhookSecret`).
    public var webhookUrl: String?

    public init(chunk: IngestChunkOptions? = nil, webhookUrl: String? = nil) {
        self.chunk = chunk
        self.webhookUrl = webhookUrl
    }
}

public struct IngestJob: Codable, Equatable, Sendable {
    public let jobId: String
    public let status: IngestStatus
    public let mode: IngestMode
    public let pagesDiscovered: Int
    public let pagesProcessed: Int
    public let pagesFailed: Int
    public let totalChunks: Int
    /// Signed URL to the final JSONL, once completed.
    public let outputUrl: String?
    public let errorMessage: String?
    public let webhookUrl: String?
    public let webhookDelivered: Bool
    public let createdAt: String?
    public let completedAt: String?
    public let warnings: [String]

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case status, mode
        case pagesDiscovered = "pages_discovered"
        case pagesProcessed = "pages_processed"
        case pagesFailed = "pages_failed"
        case totalChunks = "total_chunks"
        case outputUrl = "output_url"
        case errorMessage = "error_message"
        case webhookUrl = "webhook_url"
        case webhookDelivered = "webhook_delivered"
        case createdAt = "created_at"
        case completedAt = "completed_at"
        case warnings
    }
}

/// Compact job row from `listIngestJobs` (`webhookUrl` replaced by a flag).
public struct IngestJobSummary: Codable, Equatable, Sendable {
    public let jobId: String
    public let status: IngestStatus
    public let mode: IngestMode
    public let pagesDiscovered: Int
    public let pagesProcessed: Int
    public let pagesFailed: Int
    public let totalChunks: Int
    public let outputUrl: String?
    public let errorMessage: String?
    public let webhookConfigured: Bool
    public let webhookDelivered: Bool
    public let createdAt: String?
    public let completedAt: String?

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case status, mode
        case pagesDiscovered = "pages_discovered"
        case pagesProcessed = "pages_processed"
        case pagesFailed = "pages_failed"
        case totalChunks = "total_chunks"
        case outputUrl = "output_url"
        case errorMessage = "error_message"
        case webhookConfigured = "webhook_configured"
        case webhookDelivered = "webhook_delivered"
        case createdAt = "created_at"
        case completedAt = "completed_at"
    }
}

public struct IngestJobList: Codable, Equatable, Sendable {
    public let jobs: [IngestJobSummary]
    public let skip: Int
    public let limit: Int
    public let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case jobs, skip, limit
        case hasMore = "has_more"
    }
}

public struct WebhookSecret: Codable, Equatable, Sendable {
    public let secret: String
    /// Header carrying the HMAC signature, e.g. "X-Enconvert-Signature".
    public let signatureHeader: String
    public let timestampHeader: String
    public let signatureScheme: String
    public let replayToleranceSeconds: Int
    /// True when this response just replaced the previous secret.
    public let rotated: Bool

    enum CodingKeys: String, CodingKey {
        case secret
        case signatureHeader = "signature_header"
        case timestampHeader = "timestamp_header"
        case signatureScheme = "signature_scheme"
        case replayToleranceSeconds = "replay_tolerance_seconds"
        case rotated
    }
}

public struct WebhookRetryResult: Codable, Equatable, Sendable {
    public let jobId: String
    public let delivered: Bool
    public let attempts: Int
    /// HTTP status of the last attempt; nil on network error.
    public let statusCode: Int?
    public let detail: String

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case delivered, attempts
        case statusCode = "status_code"
        case detail
    }
}

// MARK: - Watch

public enum WatchDiffMode: String, Codable, Sendable {
    case auto
    case text
    case structured
    case tables
    case metadata
}

public enum WatcherStatus: String, Codable, Sendable {
    case active
    case paused
    case deleted
}

/// "active" or "paused". Deleting goes through `deleteWatcher`.
public enum WatchUpdateStatus: String, Codable, Sendable {
    case active
    case paused
}

public struct WatchCreateOptions: Sendable {
    /// Minutes between checks, 60-43200 (hourly floor is hard). Default 60.
    public var frequencyMinutes: Int?
    /// Default `.auto` (diff engine picks by content type).
    public var diffMode: WatchDiffMode?
    /// Optional field/selector subset for the diff engine.
    public var trackFields: JSONObject?
    /// Change-notification webhook, HMAC-signed.
    public var webhookUrl: String?
    /// Email the project owner on changes. Default true.
    public var notifyEmail: Bool?

    public init(
        frequencyMinutes: Int? = nil,
        diffMode: WatchDiffMode? = nil,
        trackFields: JSONObject? = nil,
        webhookUrl: String? = nil,
        notifyEmail: Bool? = nil
    ) {
        self.frequencyMinutes = frequencyMinutes
        self.diffMode = diffMode
        self.trackFields = trackFields
        self.webhookUrl = webhookUrl
        self.notifyEmail = notifyEmail
    }
}

public struct WatcherUpdate: Sendable {
    /// 60-43200.
    public var frequencyMinutes: Int?
    public var diffMode: WatchDiffMode?
    public var trackFields: JSONObject?
    /// An empty string "" explicitly clears the webhook.
    public var webhookUrl: String?
    public var notifyEmail: Bool?
    public var status: WatchUpdateStatus?

    public init(
        frequencyMinutes: Int? = nil,
        diffMode: WatchDiffMode? = nil,
        trackFields: JSONObject? = nil,
        webhookUrl: String? = nil,
        notifyEmail: Bool? = nil,
        status: WatchUpdateStatus? = nil
    ) {
        self.frequencyMinutes = frequencyMinutes
        self.diffMode = diffMode
        self.trackFields = trackFields
        self.webhookUrl = webhookUrl
        self.notifyEmail = notifyEmail
        self.status = status
    }
}

public struct Watcher: Codable, Equatable, Sendable {
    public let watcherId: String
    public let url: String
    public let status: WatcherStatus
    public let frequencyMinutes: Int
    public let diffMode: WatchDiffMode
    public let trackFields: JSONObject?
    public let webhookUrl: String?
    public let notifyEmail: Bool
    public let consecutiveErrors: Int
    public let checksCount: Int
    public let lastCheckAt: String?
    public let nextCheckAt: String?
    public let lastChangeAt: String?
    public let createdAt: String?
    public let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case watcherId = "watcher_id"
        case url, status
        case frequencyMinutes = "frequency_minutes"
        case diffMode = "diff_mode"
        case trackFields = "track_fields"
        case webhookUrl = "webhook_url"
        case notifyEmail = "notify_email"
        case consecutiveErrors = "consecutive_errors"
        case checksCount = "checks_count"
        case lastCheckAt = "last_check_at"
        case nextCheckAt = "next_check_at"
        case lastChangeAt = "last_change_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Compact watcher row from `listWatchers`.
public struct WatcherSummary: Codable, Equatable, Sendable {
    public let watcherId: String
    public let url: String
    public let status: WatcherStatus
    public let frequencyMinutes: Int
    public let checksCount: Int
    public let consecutiveErrors: Int
    public let lastCheckAt: String?
    public let nextCheckAt: String?
    public let lastChangeAt: String?
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case watcherId = "watcher_id"
        case url, status
        case frequencyMinutes = "frequency_minutes"
        case checksCount = "checks_count"
        case consecutiveErrors = "consecutive_errors"
        case lastCheckAt = "last_check_at"
        case nextCheckAt = "next_check_at"
        case lastChangeAt = "last_change_at"
        case createdAt = "created_at"
    }
}

public struct WatcherList: Codable, Equatable, Sendable {
    public let watchers: [WatcherSummary]
    public let skip: Int
    public let limit: Int
    public let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case watchers, skip, limit
        case hasMore = "has_more"
    }
}

public struct WatcherSnapshot: Codable, Equatable, Sendable {
    public let checkedAt: String
    public let hasChanges: Bool
    /// 0.0-1.0 similarity to the previous capture.
    public let similarity: Double?
    public let renderQuality: Double?
    public let changeCount: Int
    /// Diff entries. Values are untrusted page content — escape before render.
    public let changes: [JSONObject]

    enum CodingKeys: String, CodingKey {
        case checkedAt = "checked_at"
        case hasChanges = "has_changes"
        case similarity
        case renderQuality = "render_quality"
        case changeCount = "change_count"
        case changes
    }
}

public struct WatcherSnapshotList: Codable, Equatable, Sendable {
    public let watcherId: String
    public let snapshots: [WatcherSnapshot]
    public let limit: Int

    enum CodingKeys: String, CodingKey {
        case watcherId = "watcher_id"
        case snapshots, limit
    }
}
