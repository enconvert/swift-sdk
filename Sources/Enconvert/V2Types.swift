/**
 * V2 API option and result types (perceive, discover, lookup).
 *
 * Field names are camelCase on the SDK surface and mapped to the API's
 * snake_case wire format by `EnconvertV2`'s serializers/mappers. User-data
 * payloads (extraction schemas, extracted data, search "extra" fields) pass
 * through untouched via `JSONValue`.
 *
 * Result types are populated by `EnconvertV2`'s lenient mapper functions
 * (never by decoding a raw API response directly with `JSONDecoder`), so a
 * missing or unexpected field degrades to a documented default instead of
 * throwing. `Codable` conformance is provided for the common case of caching
 * an already-parsed result to disk and reloading it later, not for decoding
 * raw API responses.
 */

import Foundation

// MARK: - Perceive

public enum PerceiveOutputName: String, Codable, Sendable {
    case markdown
    case markdownFit = "markdown_fit"
    case htmlCleaned = "html_cleaned"
    case htmlRaw = "html_raw"
    case screenshot
    case screenshotFullPage = "screenshot_full_page"
    case pdf
    case links
    case images
    case structured
}

public enum PerceiveExtractName: String, Codable, Sendable {
    case tables
    case prices
    case contacts
    case metadata
    case mainContent = "main_content"
    case headings
    case structuredData = "structured_data"
    case technologies
    case all
}

public enum PerceiveResourceType: String, Codable, Sendable {
    case image
    case media
    case font
    case stylesheet
    case script
    case xhr
    case fetch
    case websocket
    case manifest
    case other
}

public enum PerceiveCacheMode: String, Codable, Sendable {
    case enabled
    case bypass
    case refresh
}

public enum PerceiveStatus: String, Codable, Sendable {
    case queued
    case processing
    case completed
    case failed
}

public struct PerceiveViewport: Codable, Equatable, Sendable {
    /// 320-3840, default 1920.
    public var width: Int?
    /// 240-2160, default 1080.
    public var height: Int?

    public init(width: Int? = nil, height: Int? = nil) {
        self.width = width
        self.height = height
    }
}

/// Per-render options shared by `perceive` and `perceiveBatch`. Mirrors the
/// Node SDK's `PerceiveOptions` interface, which `PerceiveBatchOptions`
/// structurally extends — represented here as a protocol both structs
/// conform to (see `WatcherUpdate`-style pattern used across the SDK).
public protocol PerceiveRenderOptions {
    /// Artifacts to produce. Default: `[.markdown, .structured]`.
    var outputs: [PerceiveOutputName]? { get }
    /// Heuristic extraction targets. Unsupported members yield warnings.
    var extract: [PerceiveExtractName]? { get }
    /// JSON schema for structured extraction (LLM tier, plan-gated).
    var schema: JSONObject? { get }
    /// CSS selector (optionally "css:...") or "js:<expr>" to await.
    var waitFor: String? { get }
    /// 0-60000, default 30000.
    var waitTimeoutMs: Int? { get }
    /// JavaScript executed after navigation. Max 20000 chars.
    var jsCode: String? { get }
    var viewport: PerceiveViewport? { get }
    var headers: [String: String]? { get }
    var cookies: [BrowserCookie]? { get }
    /// HTTP Basic Auth (plan-gated).
    var auth: HttpBasicAuth? { get }
    /// Not yet available server-side — currently rejected with 422.
    var proxyUrl: String? { get }
    /// Not yet available server-side — currently rejected with 422.
    var geolocation: JSONObject? { get }
    /// Not yet available server-side — currently rejected with 422.
    var actionChain: [JSONObject]? { get }
    /// Default "enabled" (1h cache). "bypass" skips, "refresh" re-renders.
    var cacheMode: PerceiveCacheMode? { get }
    /// Only meaningful when outputs includes `.pdf`.
    var pdfOptions: PdfOptions? { get }
    /// Resource types the browser should not load.
    var blockResources: [PerceiveResourceType]? { get }
    var respectRobots: Bool? { get }
    var mobile: Bool? { get }
}

public struct PerceiveOptions: PerceiveRenderOptions, Sendable {
    public var outputs: [PerceiveOutputName]?
    public var extract: [PerceiveExtractName]?
    public var schema: JSONObject?
    public var waitFor: String?
    public var waitTimeoutMs: Int?
    public var jsCode: String?
    public var viewport: PerceiveViewport?
    public var headers: [String: String]?
    public var cookies: [BrowserCookie]?
    public var auth: HttpBasicAuth?
    public var proxyUrl: String?
    public var geolocation: JSONObject?
    public var actionChain: [JSONObject]?
    public var cacheMode: PerceiveCacheMode?
    public var pdfOptions: PdfOptions?
    public var blockResources: [PerceiveResourceType]?
    public var respectRobots: Bool?
    public var mobile: Bool?

    public init(
        outputs: [PerceiveOutputName]? = nil,
        extract: [PerceiveExtractName]? = nil,
        schema: JSONObject? = nil,
        waitFor: String? = nil,
        waitTimeoutMs: Int? = nil,
        jsCode: String? = nil,
        viewport: PerceiveViewport? = nil,
        headers: [String: String]? = nil,
        cookies: [BrowserCookie]? = nil,
        auth: HttpBasicAuth? = nil,
        proxyUrl: String? = nil,
        geolocation: JSONObject? = nil,
        actionChain: [JSONObject]? = nil,
        cacheMode: PerceiveCacheMode? = nil,
        pdfOptions: PdfOptions? = nil,
        blockResources: [PerceiveResourceType]? = nil,
        respectRobots: Bool? = nil,
        mobile: Bool? = nil
    ) {
        self.outputs = outputs
        self.extract = extract
        self.schema = schema
        self.waitFor = waitFor
        self.waitTimeoutMs = waitTimeoutMs
        self.jsCode = jsCode
        self.viewport = viewport
        self.headers = headers
        self.cookies = cookies
        self.auth = auth
        self.proxyUrl = proxyUrl
        self.geolocation = geolocation
        self.actionChain = actionChain
        self.cacheMode = cacheMode
        self.pdfOptions = pdfOptions
        self.blockResources = blockResources
        self.respectRobots = respectRobots
        self.mobile = mobile
    }
}

public enum PerceiveBatchOutputMode: String, Codable, Sendable {
    case manifest
    case zip
}

/// Options for `perceiveBatch`: shared render options plus the output mode.
public struct PerceiveBatchOptions: PerceiveRenderOptions, Sendable {
    public var outputs: [PerceiveOutputName]?
    public var extract: [PerceiveExtractName]?
    public var schema: JSONObject?
    public var waitFor: String?
    public var waitTimeoutMs: Int?
    public var jsCode: String?
    public var viewport: PerceiveViewport?
    public var headers: [String: String]?
    public var cookies: [BrowserCookie]?
    public var auth: HttpBasicAuth?
    public var proxyUrl: String?
    public var geolocation: JSONObject?
    public var actionChain: [JSONObject]?
    public var cacheMode: PerceiveCacheMode?
    public var pdfOptions: PdfOptions?
    public var blockResources: [PerceiveResourceType]?
    public var respectRobots: Bool?
    public var mobile: Bool?
    /// `.manifest` (default) or `.zip` (bundle all artifacts once complete).
    public var outputMode: PerceiveBatchOutputMode?

    public init(
        outputs: [PerceiveOutputName]? = nil,
        extract: [PerceiveExtractName]? = nil,
        schema: JSONObject? = nil,
        waitFor: String? = nil,
        waitTimeoutMs: Int? = nil,
        jsCode: String? = nil,
        viewport: PerceiveViewport? = nil,
        headers: [String: String]? = nil,
        cookies: [BrowserCookie]? = nil,
        auth: HttpBasicAuth? = nil,
        proxyUrl: String? = nil,
        geolocation: JSONObject? = nil,
        actionChain: [JSONObject]? = nil,
        cacheMode: PerceiveCacheMode? = nil,
        pdfOptions: PdfOptions? = nil,
        blockResources: [PerceiveResourceType]? = nil,
        respectRobots: Bool? = nil,
        mobile: Bool? = nil,
        outputMode: PerceiveBatchOutputMode? = nil
    ) {
        self.outputs = outputs
        self.extract = extract
        self.schema = schema
        self.waitFor = waitFor
        self.waitTimeoutMs = waitTimeoutMs
        self.jsCode = jsCode
        self.viewport = viewport
        self.headers = headers
        self.cookies = cookies
        self.auth = auth
        self.proxyUrl = proxyUrl
        self.geolocation = geolocation
        self.actionChain = actionChain
        self.cacheMode = cacheMode
        self.pdfOptions = pdfOptions
        self.blockResources = blockResources
        self.respectRobots = respectRobots
        self.mobile = mobile
        self.outputMode = outputMode
    }
}

/// A rendered output stored server-side, addressed by signed URL.
public struct V2OutputArtifact: Codable, Equatable, Sendable {
    /// Pre-signed download URL (15 minutes). Re-signed on every status GET.
    public let url: String?
    public let objectKey: String
    public let sizeBytes: Int
    public let contentType: String
    public let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case url
        case objectKey = "object_key"
        case sizeBytes = "size_bytes"
        case contentType = "content_type"
        case expiresIn = "expires_in"
    }
}

public struct V2Tokens: Codable, Equatable, Sendable {
    public let input: Int
    public let output: Int
}

public enum PerceiveExtractionTier: String, Codable, Sendable {
    case heuristic
    case css
    case llm
}

public struct PerceiveResult: Codable, Equatable, Sendable {
    public let operationId: String
    public let status: PerceiveStatus
    public let url: String
    public let urlFinal: String?
    public let contentHash: String?
    /// 0.0-1.0 render quality score.
    public let renderQuality: Double?
    public let cacheHit: Bool
    /// Keyed by output name (e.g. "markdown", "screenshot_full_page").
    public let outputs: [String: V2OutputArtifact]
    /// Present when extract/schema was requested. Shape is caller-defined.
    public let structured: JSONObject?
    public let extractionTier: PerceiveExtractionTier?
    public let tokens: V2Tokens
    public let costCents: Int
    public let durationMs: Int?
    public let error: String?
    public let warnings: [String]

    enum CodingKeys: String, CodingKey {
        case operationId = "operation_id"
        case status
        case url
        case urlFinal = "url_final"
        case contentHash = "content_hash"
        case renderQuality = "render_quality"
        case cacheHit = "cache_hit"
        case outputs
        case structured
        case extractionTier = "extraction_tier"
        case tokens
        case costCents = "cost_cents"
        case durationMs = "duration_ms"
        case error
        case warnings
    }
}

public enum PerceiveBatchStatus: String, Codable, Sendable {
    case queued
    case processing
    case completed
    case failed
    case partial
}

public struct PerceiveBatchResult: Codable, Equatable, Sendable {
    public let jobId: String
    public let status: PerceiveBatchStatus
    public let outputMode: PerceiveBatchOutputMode
    public let total: Int
    public let completed: Int
    public let failed: Int
    public let pending: Int
    /// Bundle of every successful artifact (outputMode `.zip`, once done).
    public let zip: V2OutputArtifact?
    /// One entry per URL. Empty on the initial 202 — poll `getPerceiveBatch`.
    public let items: [PerceiveResult]
    public let warnings: [String]

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case status
        case outputMode = "output_mode"
        case total, completed, failed, pending, zip, items, warnings
    }
}

// MARK: - Discover

public enum DiscoverMode: String, Codable, Sendable {
    case sitemap
    case crawl
    case hybrid
}

public struct DiscoverOptions: Sendable {
    /// Default `.hybrid` (sitemap + HTTP crawl).
    public var mode: DiscoverMode?
    /// 1-1000, default 100.
    public var maxUrls: Int?
    /// 1-5, default 2.
    public var maxDepth: Int?
    /// Regex allowlist (re.search semantics), max 50.
    public var includePatterns: [String]?
    /// Regex denylist, applied after includePatterns, max 50.
    public var excludePatterns: [String]?
    /// Default true.
    public var sameDomainOnly: Bool?
    public var respectRobots: Bool?

    public init(
        mode: DiscoverMode? = nil,
        maxUrls: Int? = nil,
        maxDepth: Int? = nil,
        includePatterns: [String]? = nil,
        excludePatterns: [String]? = nil,
        sameDomainOnly: Bool? = nil,
        respectRobots: Bool? = nil
    ) {
        self.mode = mode
        self.maxUrls = maxUrls
        self.maxDepth = maxDepth
        self.includePatterns = includePatterns
        self.excludePatterns = excludePatterns
        self.sameDomainOnly = sameDomainOnly
        self.respectRobots = respectRobots
    }
}

public struct DiscoverResult: Codable, Equatable, Sendable {
    public let url: String
    public let mode: DiscoverMode
    public let total: Int
    public let urls: [String]
    public let pagesCrawled: Int
    /// True when more URLs were found than maxUrls allowed.
    public let truncated: Bool
    public let robotsRespected: Bool
    /// Raw counts per source before dedup, e.g. `{"sitemap": 42, "crawl": 30}`.
    public let sources: [String: Int]
    public let warnings: [String]

    enum CodingKeys: String, CodingKey {
        case url, mode, total, urls
        case pagesCrawled = "pages_crawled"
        case truncated
        case robotsRespected = "robots_respected"
        case sources, warnings
    }
}

// MARK: - Lookup

public enum LookupCategory: String, Codable, Sendable {
    case web
    case news
    case images
    case scholar
    case patents
    case maps
}

public enum LookupTimeFilter: String, Codable, Sendable {
    case hour
    case day
    case week
    case month
    case year
}

public struct LookupOptions: Sendable {
    /// Default `.web`.
    public var category: LookupCategory?
    /// Google "gl" country code, e.g. "us", "in".
    public var country: String?
    /// Google "hl" interface language, e.g. "en".
    public var locale: String?
    public var timeFilter: LookupTimeFilter?
    /// 1-100, default 10.
    public var numResults: Int?
    /// 1-10, default 1.
    public var page: Int?
    /// Free-text location, e.g. "Austin, Texas".
    public var location: String?
    /// Default true.
    public var autocorrect: Bool?
    /// Auto-perceive the top-N result URLs (0-10, default 0). Each consumes
    /// one perceive-quota unit and runs a full browser render.
    public var perceiveTop: Int?

    public init(
        category: LookupCategory? = nil,
        country: String? = nil,
        locale: String? = nil,
        timeFilter: LookupTimeFilter? = nil,
        numResults: Int? = nil,
        page: Int? = nil,
        location: String? = nil,
        autocorrect: Bool? = nil,
        perceiveTop: Int? = nil
    ) {
        self.category = category
        self.country = country
        self.locale = locale
        self.timeFilter = timeFilter
        self.numResults = numResults
        self.page = page
        self.location = location
        self.autocorrect = autocorrect
        self.perceiveTop = perceiveTop
    }
}

/// One search hit, optionally carrying its full perceive result.
public struct LookupItem: Codable, Equatable, Sendable {
    public let title: String?
    public let url: String?
    public let snippet: String?
    public let position: Int?
    public let source: String?
    public let date: String?
    public let imageUrl: String?
    public let thumbnailUrl: String?
    /// Provider-specific passthrough fields.
    public let extra: JSONObject
    /// Present for the top-N results when perceiveTop > 0 and it succeeded.
    public let perceive: PerceiveResult?

    enum CodingKeys: String, CodingKey {
        case title, url, snippet, position, source, date
        case imageUrl = "image_url"
        case thumbnailUrl = "thumbnail_url"
        case extra, perceive
    }
}

public struct LookupResult: Codable, Equatable, Sendable {
    /// Audit row id; nil when the audit write failed (results still valid).
    public let lookupId: Int?
    public let query: String
    public let category: LookupCategory
    public let country: String?
    public let locale: String?
    public let timeFilter: LookupTimeFilter?
    public let total: Int
    public let results: [LookupItem]
    /// How many results were actually perceived (may be below requested).
    public let perceiveTop: Int
    public let perceiveOperationIds: [String]
    public let answerBox: JSONObject?
    public let knowledgeGraph: JSONObject?
    /// Search-provider credits consumed.
    public let credits: Int?
    public let costCents: Int
    public let warnings: [String]

    enum CodingKeys: String, CodingKey {
        case lookupId = "lookup_id"
        case query, category, country, locale
        case timeFilter = "time_filter"
        case total, results
        case perceiveTop = "perceive_top"
        case perceiveOperationIds = "perceive_operation_ids"
        case answerBox = "answer_box"
        case knowledgeGraph = "knowledge_graph"
        case credits
        case costCents = "cost_cents"
        case warnings
    }
}

// MARK: - Shared list options

public struct V2ListOptions: Sendable {
    /// Rows to skip (default 0).
    public var skip: Int?
    /// Page size, 1-100 (default 20).
    public var limit: Int?

    public init(skip: Int? = nil, limit: Int? = nil) {
        self.skip = skip
        self.limit = limit
    }
}

public struct SnapshotListOptions: Sendable {
    /// Page size, 1-100 (default 20).
    public var limit: Int?

    public init(limit: Int? = nil) {
        self.limit = limit
    }
}
