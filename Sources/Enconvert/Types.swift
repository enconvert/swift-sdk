/** Enconvert SDK V1 option and result types. */

import Foundation

// MARK: - Conversion result

public struct ConversionResult: Codable, Equatable, Sendable {
    public let presignedUrl: String
    public let objectKey: String
    public let filename: String
    public let fileSize: Int?
    public let conversionTimeSeconds: Double?
    public let jobId: String?

    enum CodingKeys: String, CodingKey {
        case presignedUrl = "presigned_url"
        case objectKey = "object_key"
        case filename
        case fileSize = "file_size"
        case conversionTimeSeconds = "conversion_time_seconds"
        case jobId = "job_id"
    }
}

// MARK: - Job status

public enum JobStatusValue: String, Codable, Sendable {
    case processing
    case success
    case failed
}

public struct JobStatus: Codable, Equatable, Sendable {
    public let status: JobStatusValue
    public let presignedUrl: String?
    public let objectKey: String?
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case status
        case presignedUrl = "presigned_url"
        case objectKey = "object_key"
        case error
    }
}

// MARK: - PDF options

public enum PdfOrientation: String, Codable, Sendable {
    case portrait
    case landscape
}

public struct PdfMargins: Equatable, Sendable {
    public var top: Double?
    public var bottom: Double?
    public var left: Double?
    public var right: Double?

    public init(top: Double? = nil, bottom: Double? = nil, left: Double? = nil, right: Double? = nil) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
    }

    func toJSONDict() -> [String: Any] {
        var dict: [String: Any] = [:]
        if let top { dict["top"] = top }
        if let bottom { dict["bottom"] = bottom }
        if let left { dict["left"] = left }
        if let right { dict["right"] = right }
        return dict
    }
}

/// Header or footer block rendered on each PDF page.
public struct PdfHeaderFooter: Equatable, Sendable {
    /// Text content, max 2000 characters.
    public var content: String?
    /// Block height.
    public var height: Double?

    public init(content: String? = nil, height: Double? = nil) {
        self.content = content
        self.height = height
    }

    func toJSONDict() -> [String: Any] {
        var dict: [String: Any] = [:]
        if let content { dict["content"] = content }
        if let height { dict["height"] = height }
        return dict
    }
}

public struct PdfOptions: Equatable, Sendable {
    public var pageSize: String?
    /// Custom page width; overrides pageSize when set together with pageHeight.
    public var pageWidth: Double?
    /// Custom page height; overrides pageSize when set together with pageWidth.
    public var pageHeight: Double?
    public var orientation: PdfOrientation?
    public var margins: PdfMargins?
    public var scale: Double?
    public var grayscale: Bool?
    public var header: PdfHeaderFooter?
    public var footer: PdfHeaderFooter?

    public init(
        pageSize: String? = nil,
        pageWidth: Double? = nil,
        pageHeight: Double? = nil,
        orientation: PdfOrientation? = nil,
        margins: PdfMargins? = nil,
        scale: Double? = nil,
        grayscale: Bool? = nil,
        header: PdfHeaderFooter? = nil,
        footer: PdfHeaderFooter? = nil
    ) {
        self.pageSize = pageSize
        self.pageWidth = pageWidth
        self.pageHeight = pageHeight
        self.orientation = orientation
        self.margins = margins
        self.scale = scale
        self.grayscale = grayscale
        self.header = header
        self.footer = footer
    }

    /// Snake_case, only-if-set serialization (mirrors `serializePdfOptions`).
    func toJSONDict() -> [String: Any] {
        var dict: [String: Any] = [:]
        if let pageSize { dict["page_size"] = pageSize }
        if let pageWidth { dict["page_width"] = pageWidth }
        if let pageHeight { dict["page_height"] = pageHeight }
        if let orientation { dict["orientation"] = orientation.rawValue }
        if let margins { dict["margins"] = margins.toJSONDict() }
        if let scale { dict["scale"] = scale }
        if let grayscale { dict["grayscale"] = grayscale }
        if let header { dict["header"] = header.toJSONDict() }
        if let footer { dict["footer"] = footer.toJSONDict() }
        return dict
    }
}

// MARK: - Browser access (auth / cookies / headers)

/// HTTP Basic Auth credentials for pages behind a login (plan-gated).
public struct HttpBasicAuth: Equatable, Sendable {
    public var username: String
    public var password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    func toJSONDict() -> [String: Any] {
        ["username": username, "password": password]
    }
}

public enum SameSite: String, Codable, Sendable {
    case strict = "Strict"
    case lax = "Lax"
    case none = "None"
}

/// Cookie injected into the browser context before rendering (plan-gated).
/// The API requires `name`, `value`, and either `domain` or `url`. When
/// `domain` is set without `path`, the API defaults `path` to "/".
///
/// Field names on the wire (`httpOnly`, `sameSite`) are camelCase, not
/// snake_case — the API forwards this object to the browser engine as-is.
public struct BrowserCookie: Equatable, Sendable {
    public var name: String
    public var value: String
    public var domain: String?
    public var url: String?
    public var path: String?
    public var expires: Double?
    public var httpOnly: Bool?
    public var secure: Bool?
    public var sameSite: SameSite?

    public init(
        name: String,
        value: String,
        domain: String? = nil,
        url: String? = nil,
        path: String? = nil,
        expires: Double? = nil,
        httpOnly: Bool? = nil,
        secure: Bool? = nil,
        sameSite: SameSite? = nil
    ) {
        self.name = name
        self.value = value
        self.domain = domain
        self.url = url
        self.path = path
        self.expires = expires
        self.httpOnly = httpOnly
        self.secure = secure
        self.sameSite = sameSite
    }

    func toJSONDict() -> [String: Any] {
        var dict: [String: Any] = ["name": name, "value": value]
        if let domain { dict["domain"] = domain }
        if let url { dict["url"] = url }
        if let path { dict["path"] = path }
        if let expires { dict["expires"] = expires }
        if let httpOnly { dict["httpOnly"] = httpOnly }
        if let secure { dict["secure"] = secure }
        if let sameSite { dict["sameSite"] = sameSite.rawValue }
        return dict
    }
}

// MARK: - File input

/// File input accepted by `convertImage` / `convertDocument`.
///
/// - `.path`: a filesystem path, e.g. `.path("./photo.heic")`.
/// - `.data`: raw bytes with no explicit filename (sent as `upload.bin`).
/// - `.wrapped`: raw bytes with an explicit filename and optional content type.
public enum FileInput: Sendable {
    case path(String)
    case data(Data)
    case wrapped(data: Data, filename: String, contentType: String?)
}

struct FilePart {
    var bytes: Data
    var filename: String
    var contentType: String
}

// MARK: - Shared URL render options (interface parity with the Node SDK's
// `UrlRenderOptions`, which `UrlToPdfOptions` etc. structurally extend).

/// Options shared by all URL-based conversions (single page and website).
public protocol UrlRenderOptions {
    var viewportWidth: Int? { get }
    var viewportHeight: Int? { get }
    var loadMedia: Bool? { get }
    var enableScroll: Bool? { get }
    var outputFilename: String? { get }
    /// HTTP Basic Auth for protected pages (plan-gated).
    var auth: HttpBasicAuth? { get }
    /// Cookies injected before rendering, max 50 (plan-gated).
    var cookies: [BrowserCookie]? { get }
    /// Extra request headers, max 20; hop-by-hop headers rejected (plan-gated).
    var headers: [String: String]? { get }
}

public struct UrlToPdfOptions: UrlRenderOptions, Sendable {
    public var viewportWidth: Int?
    public var viewportHeight: Int?
    public var loadMedia: Bool?
    public var enableScroll: Bool?
    public var outputFilename: String?
    public var auth: HttpBasicAuth?
    public var cookies: [BrowserCookie]?
    public var headers: [String: String]?
    public var saveTo: String?
    /// Defaults to `true` when omitted.
    public var singlePage: Bool?
    public var pdfOptions: PdfOptions?

    public init(
        viewportWidth: Int? = nil,
        viewportHeight: Int? = nil,
        loadMedia: Bool? = nil,
        enableScroll: Bool? = nil,
        outputFilename: String? = nil,
        auth: HttpBasicAuth? = nil,
        cookies: [BrowserCookie]? = nil,
        headers: [String: String]? = nil,
        saveTo: String? = nil,
        singlePage: Bool? = nil,
        pdfOptions: PdfOptions? = nil
    ) {
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
        self.loadMedia = loadMedia
        self.enableScroll = enableScroll
        self.outputFilename = outputFilename
        self.auth = auth
        self.cookies = cookies
        self.headers = headers
        self.saveTo = saveTo
        self.singlePage = singlePage
        self.pdfOptions = pdfOptions
    }
}

public struct UrlToScreenshotOptions: UrlRenderOptions, Sendable {
    public var viewportWidth: Int?
    public var viewportHeight: Int?
    public var loadMedia: Bool?
    public var enableScroll: Bool?
    public var outputFilename: String?
    public var auth: HttpBasicAuth?
    public var cookies: [BrowserCookie]?
    public var headers: [String: String]?
    public var saveTo: String?

    public init(
        viewportWidth: Int? = nil,
        viewportHeight: Int? = nil,
        loadMedia: Bool? = nil,
        enableScroll: Bool? = nil,
        outputFilename: String? = nil,
        auth: HttpBasicAuth? = nil,
        cookies: [BrowserCookie]? = nil,
        headers: [String: String]? = nil,
        saveTo: String? = nil
    ) {
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
        self.loadMedia = loadMedia
        self.enableScroll = enableScroll
        self.outputFilename = outputFilename
        self.auth = auth
        self.cookies = cookies
        self.headers = headers
        self.saveTo = saveTo
    }
}

public struct UrlToMarkdownOptions: UrlRenderOptions, Sendable {
    public var viewportWidth: Int?
    public var viewportHeight: Int?
    public var loadMedia: Bool?
    public var enableScroll: Bool?
    public var outputFilename: String?
    public var auth: HttpBasicAuth?
    public var cookies: [BrowserCookie]?
    public var headers: [String: String]?
    public var saveTo: String?

    public init(
        viewportWidth: Int? = nil,
        viewportHeight: Int? = nil,
        loadMedia: Bool? = nil,
        enableScroll: Bool? = nil,
        outputFilename: String? = nil,
        auth: HttpBasicAuth? = nil,
        cookies: [BrowserCookie]? = nil,
        headers: [String: String]? = nil,
        saveTo: String? = nil
    ) {
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
        self.loadMedia = loadMedia
        self.enableScroll = enableScroll
        self.outputFilename = outputFilename
        self.auth = auth
        self.cookies = cookies
        self.headers = headers
        self.saveTo = saveTo
    }
}

// MARK: - Image / document conversion options

public struct ConvertImageOptions: Sendable {
    public var outputFormat: String
    public var saveTo: String?
    public var outputFilename: String?

    public init(outputFormat: String, saveTo: String? = nil, outputFilename: String? = nil) {
        self.outputFormat = outputFormat
        self.saveTo = saveTo
        self.outputFilename = outputFilename
    }
}

public struct ConvertDocumentOptions: Sendable {
    /// Defaults to `"pdf"` when omitted.
    public var outputFormat: String?
    public var saveTo: String?
    public var outputFilename: String?
    public var pdfOptions: PdfOptions?

    public init(
        outputFormat: String? = nil,
        saveTo: String? = nil,
        outputFilename: String? = nil,
        pdfOptions: PdfOptions? = nil
    ) {
        self.outputFormat = outputFormat
        self.saveTo = saveTo
        self.outputFilename = outputFilename
        self.pdfOptions = pdfOptions
    }
}

/// Options for `convertToMarkdown` (anything-to-markdown).
public struct ConvertToMarkdownOptions: Sendable {
    public var saveTo: String?
    public var outputFilename: String?

    public init(saveTo: String? = nil, outputFilename: String? = nil) {
        self.saveTo = saveTo
        self.outputFilename = outputFilename
    }
}

/// Options for `convertToPdf` (anything-to-pdf).
public struct ConvertToPdfOptions: Sendable {
    public var saveTo: String?
    public var outputFilename: String?
    /// Only `grayscale` is honored by the anything-to-pdf endpoint.
    public var pdfOptions: PdfOptions?

    public init(saveTo: String? = nil, outputFilename: String? = nil, pdfOptions: PdfOptions? = nil) {
        self.saveTo = saveTo
        self.outputFilename = outputFilename
        self.pdfOptions = pdfOptions
    }
}

// MARK: - Website (whole-site batch) conversions

/// URL discovery strategy for website conversions.
/// - `.auto`: highest mode the plan allows (default)
/// - `.sitemap`: sitemap.xml only (Starter and above)
/// - `.full`: sitemap plus BFS crawl (Pro/Business)
public enum CrawlMode: String, Codable, Sendable {
    case auto
    case sitemap
    case full
}

/// Options shared by `convertWebsiteToPdf` / `convertWebsiteToScreenshot`.
public protocol WebsiteConversionOptions: UrlRenderOptions {
    var crawlMode: CrawlMode? { get }
    /// Only crawl URLs matching these patterns (full crawl mode).
    var includePatterns: [String]? { get }
    /// Skip URLs matching these patterns (full crawl mode).
    var excludePatterns: [String]? { get }
    /// Email notified on completion. Defaults to the project owner's email.
    var notificationEmail: String? { get }
    /// Webhook POSTed when the batch finishes (plan-gated).
    var callbackUrl: String? { get }
}

public struct WebsiteToPdfOptions: WebsiteConversionOptions, Sendable {
    public var viewportWidth: Int?
    public var viewportHeight: Int?
    public var loadMedia: Bool?
    public var enableScroll: Bool?
    public var outputFilename: String?
    public var auth: HttpBasicAuth?
    public var cookies: [BrowserCookie]?
    public var headers: [String: String]?
    public var crawlMode: CrawlMode?
    public var includePatterns: [String]?
    public var excludePatterns: [String]?
    public var notificationEmail: String?
    public var callbackUrl: String?
    public var singlePage: Bool?
    public var pdfOptions: PdfOptions?

    public init(
        viewportWidth: Int? = nil,
        viewportHeight: Int? = nil,
        loadMedia: Bool? = nil,
        enableScroll: Bool? = nil,
        outputFilename: String? = nil,
        auth: HttpBasicAuth? = nil,
        cookies: [BrowserCookie]? = nil,
        headers: [String: String]? = nil,
        crawlMode: CrawlMode? = nil,
        includePatterns: [String]? = nil,
        excludePatterns: [String]? = nil,
        notificationEmail: String? = nil,
        callbackUrl: String? = nil,
        singlePage: Bool? = nil,
        pdfOptions: PdfOptions? = nil
    ) {
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
        self.loadMedia = loadMedia
        self.enableScroll = enableScroll
        self.outputFilename = outputFilename
        self.auth = auth
        self.cookies = cookies
        self.headers = headers
        self.crawlMode = crawlMode
        self.includePatterns = includePatterns
        self.excludePatterns = excludePatterns
        self.notificationEmail = notificationEmail
        self.callbackUrl = callbackUrl
        self.singlePage = singlePage
        self.pdfOptions = pdfOptions
    }
}

public struct WebsiteToScreenshotOptions: WebsiteConversionOptions, Sendable {
    public var viewportWidth: Int?
    public var viewportHeight: Int?
    public var loadMedia: Bool?
    public var enableScroll: Bool?
    public var outputFilename: String?
    public var auth: HttpBasicAuth?
    public var cookies: [BrowserCookie]?
    public var headers: [String: String]?
    public var crawlMode: CrawlMode?
    public var includePatterns: [String]?
    public var excludePatterns: [String]?
    public var notificationEmail: String?
    public var callbackUrl: String?

    public init(
        viewportWidth: Int? = nil,
        viewportHeight: Int? = nil,
        loadMedia: Bool? = nil,
        enableScroll: Bool? = nil,
        outputFilename: String? = nil,
        auth: HttpBasicAuth? = nil,
        cookies: [BrowserCookie]? = nil,
        headers: [String: String]? = nil,
        crawlMode: CrawlMode? = nil,
        includePatterns: [String]? = nil,
        excludePatterns: [String]? = nil,
        notificationEmail: String? = nil,
        callbackUrl: String? = nil
    ) {
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
        self.loadMedia = loadMedia
        self.enableScroll = enableScroll
        self.outputFilename = outputFilename
        self.auth = auth
        self.cookies = cookies
        self.headers = headers
        self.crawlMode = crawlMode
        self.includePatterns = includePatterns
        self.excludePatterns = excludePatterns
        self.notificationEmail = notificationEmail
        self.callbackUrl = callbackUrl
    }
}

/// 202 response from an async batch submission (website conversions).
public struct BatchSubmission: Codable, Equatable, Sendable {
    public let batchId: String
    /// Always "processing" on submission.
    public let status: String
    /// Number of pages queued for conversion.
    public let urlCount: Int
    /// Total URLs found during discovery (before plan limits applied).
    public let totalDiscovered: Int?
    /// How URLs were discovered: "sitemap" or "full_crawl".
    public let discoveryMethod: String?
    /// Output packaging, "zip" for website conversions.
    public let outputFormat: String?

    enum CodingKeys: String, CodingKey {
        case batchId = "batch_id"
        case status
        case urlCount = "url_count"
        case totalDiscovered = "total_discovered"
        case discoveryMethod = "discovery_method"
        case outputFormat = "output_format"
    }
}

public enum BatchStatusValue: String, Codable, Sendable {
    case processing
    case completed
    case partial
    case failed
}

public enum BatchOutputMode: String, Codable, Sendable {
    case zip
    case individual
}

/// Per-URL entry in a batch status response.
public struct BatchItem: Codable, Equatable, Sendable {
    public let sourceUrl: String
    /// Raw activity status: "In Progress", "Success", or "Failed".
    public let status: String
    public let downloadUrl: String?
    public let outputFileSize: Int?
    public let duration: String?

    enum CodingKeys: String, CodingKey {
        case sourceUrl = "source_url"
        case status
        case downloadUrl = "download_url"
        case outputFileSize = "output_file_size"
        case duration
    }
}

public struct BatchStatus: Codable, Equatable, Sendable {
    public let batchId: String
    public let status: BatchStatusValue
    public let total: Int
    public let completed: Int
    public let failed: Int
    public let inProgress: Int
    public let outputMode: BatchOutputMode
    /// Presigned URL of the bundled ZIP when outputMode is `.zip`.
    public let zipDownloadUrl: String?
    public let items: [BatchItem]

    enum CodingKeys: String, CodingKey {
        case batchId = "batch_id"
        case status
        case total
        case completed
        case failed
        case inProgress = "in_progress"
        case outputMode = "output_mode"
        case zipDownloadUrl = "zip_download_url"
        case items
    }
}

public struct WaitForBatchOptions: Sendable {
    /// Poll interval in milliseconds. Defaults to 5_000.
    public var intervalMs: Int?
    /// Give up after this many milliseconds. Defaults to 1_800_000 (30 minutes).
    public var timeoutMs: Int?
    /// Save the batch ZIP to this local path once available.
    public var saveTo: String?

    public init(intervalMs: Int? = nil, timeoutMs: Int? = nil, saveTo: String? = nil) {
        self.intervalMs = intervalMs
        self.timeoutMs = timeoutMs
        self.saveTo = saveTo
    }
}
