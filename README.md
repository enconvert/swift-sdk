# Enconvert Swift SDK

Honest eyes for your AI agent — the Swift SDK for [Enconvert](https://enconvert.com). Swift 5.9+, `URLSession` + `async`/`await`, no external dependencies.

Read any web page or file into clean Markdown, JSON, or screenshots, and get a `renderQuality` score (0.0–1.0) on **every** read — so a blocked, challenge, or empty-SPA page comes back flagged with a low score and warnings, never mistaken for real content. Perceive, discover, look up, distill, ingest, and watch the web; convert 40+ file and document formats through the same key.

> Wiring an agent (Claude, Cursor, Windsurf, n8n, …)? The [MCP server](https://enconvert.com/mcp) is the native path — `npx @enconvert/mcp setup`. This SDK is the programmatic REST path for everything else.

## Install

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/enconvert/swift-sdk.git", from: "0.1.1")
]
```

Then add `"Enconvert"` to your target's dependencies.

## Quick Start

```swift
import Enconvert

let client = try Enconvert(apiKey: "sk_...")

// Read a page the way your agent should — with a quality score attached.
let op = try await client.v2.perceive(
    "https://example.com",
    options: PerceiveOptions(outputs: [.markdown, .structured])
)
print(op.outputs["markdown"]?.url ?? "", op.renderQuality ?? 0) // e.g. 0.93
```

---

# V2 — agent-ready data (`client.v2`)

The V2 namespace turns web pages into agent-ready data: render, search, extract, ingest, and monitor. All V2 endpoints require a **private API key** and are plan-gated — a disabled feature or exhausted monthly quota throws `EnconvertError.quota` (HTTP 402).

Every render carries `renderQuality` (0.0–1.0). A low score means the page didn't render cleanly (challenge page, cookie wall, empty shell); the content is still returned, flagged, so a bad read never quietly enters your agent's context.

### Perceive — render a URL into artifacts

```swift
let op = try await client.v2.perceive(
    "https://example.com",
    options: PerceiveOptions(outputs: [.markdown, .screenshot, .structured], extract: [.tables, .metadata])
)
print(op.renderQuality ?? 0)              // honesty score, 0.0–1.0
print(op.outputs["markdown"]?.url ?? "")  // 15-min signed URL
print(op.structured ?? [:])

// Re-sign artifact URLs later:
let again = try await client.v2.getPerceiveOperation(op.operationId)

// Batch (<=1000 URLs; small batches run inline, larger return "queued" — poll):
let batch = try await client.v2.perceiveBatch(
    ["https://a.com", "https://b.com"],
    options: PerceiveBatchOptions(outputs: [.markdown], outputMode: .zip)
)
let done = try await client.v2.getPerceiveBatch(batch.jobId)

// Direct download — stream the artifact bytes, no signed-URL round trip.
// Requires exactly one artifact-producing output:
let direct = try await client.v2.perceiveDirect(
    "https://example.com",
    options: PerceiveOptions(outputs: [.pdf])
)
try direct.content.write(to: URL(fileURLWithPath: direct.filename ?? "page.pdf"))

// Re-download a stored artifact of an earlier operation (410 past retention):
let bytes = try await client.v2.downloadPerceiveArtifact(op.operationId, output: .markdown)
```

### Discover — enumerate a site's URLs (no rendering)

```swift
let found = try await client.v2.discover(
    "https://example.com",
    options: DiscoverOptions(mode: .hybrid, maxUrls: 200, excludePatterns: ["/tag/"]) // .sitemap | .crawl | .hybrid
)
print(found.total, found.urls)
```

### Lookup — web search with optional auto-perceive

```swift
let search = try await client.v2.lookup(
    "best static site generators",
    options: LookupOptions(category: .web, numResults: 10, perceiveTop: 3) // auto-render top 3 (uses perceive quota)
)
for hit in search.results {
    print(hit.title ?? "", hit.url ?? "", hit.perceive?.renderQuality ?? 0)
}
```

### Distill — schema-driven structured extraction

```swift
let extraction = try await client.v2.distill(
    DistillOptions(
        urls: ["https://example.com/pricing"],
        schema: ["plans": .string("list of plan names with monthly prices")],
        cssSchema: CssSchema(  // optional free CSS pass before the LLM tier
            baseSelector: ".plan-card",
            fields: [
                CssField(name: "name", type: .text, selector: "h3"),
                CssField(name: "price", type: .text, selector: ".price"),
            ]
        )
    )
)
print(extraction.results[0].data ?? [:], extraction.results[0].extractionTier)

// Or discover-then-distill:
_ = try await client.v2.distill(
    DistillOptions(
        discoverFrom: DistillDiscoverFrom(url: "https://example.com", mode: .sitemap, maxPages: 10),
        schema: ["title": .string("page title"), "summary": .string("one-line summary")]
    )
)
```

### Ingest — site or files to RAG-ready JSONL (always async)

Turn a whole site — or a set of uploaded documents — into chunked, RAG-ready JSONL through one pipeline.

```swift
// From a site:
let job = try await client.v2.ingest(
    IngestOptions(
        mode: .sitemap,
        url: "https://docs.example.com",
        maxPages: 100,
        chunk: IngestChunkOptions(maxWords: 512, sentenceOverlap: 1),
        webhookUrl: "https://my.app/hooks/enconvert"
    )
)

// Or from uploaded files (PDF, DOCX, PPTX, XLSX, CSV, HTML, EPUB, TXT/MD, legacy/ODF office):
let fileJob = try await client.v2.ingestFiles(
    [.path("handbook.pdf"), .path("notes.docx")],
    options: IngestFilesOptions(chunk: IngestChunkOptions(maxWords: 512, sentenceOverlap: 1))
)

let status = try await client.v2.getIngestJob(job.jobId)          // poll
if status.status == .completed { print(status.outputUrl ?? "") } // JSONL

_ = try await client.v2.listIngestJobs(V2ListOptions(limit: 20))
_ = try await client.v2.cancelIngestJob(job.jobId)                // idempotent

// Webhook signing (HMAC):
let secret = try await client.v2.getWebhookSecret()
print(secret.signatureHeader)
_ = try await client.v2.rotateWebhookSecret()                     // invalidates old secret
_ = try await client.v2.retryIngestWebhook(job.jobId)             // re-deliver
```

### Watch — recurring change monitoring

```swift
let watcher = try await client.v2.createWatcher(
    "https://example.com/pricing",
    options: WatchCreateOptions(
        frequencyMinutes: 60,   // hourly floor
        diffMode: .auto,        // auto | text | structured | tables | metadata
        webhookUrl: "https://my.app/hooks/changes",
        notifyEmail: true
    )
)

_ = try await client.v2.listWatchers()
_ = try await client.v2.getWatcher(watcher.watcherId)
_ = try await client.v2.getWatcherSnapshots(watcher.watcherId, options: SnapshotListOptions(limit: 10))
_ = try await client.v2.updateWatcher(watcher.watcherId, updates: WatcherUpdate(status: .paused))
_ = try await client.v2.updateWatcher(watcher.watcherId, updates: WatcherUpdate(webhookUrl: "")) // clears webhook
_ = try await client.v2.deleteWatcher(watcher.watcherId)          // soft-delete, idempotent
```

### V2 error handling

```swift
import Enconvert

do {
    _ = try await client.v2.ingest(IngestOptions(urls: ["https://example.com"]))
} catch EnconvertError.quota(let message) {
    print("Upgrade plan or wait for quota reset: \(message)")
}
```

---

# File conversion

The same key also converts 40+ formats. Two "anything → X" endpoints auto-detect the input; the format-specific endpoints below give you a validated, typed path.

### Anything to Markdown / PDF

```swift
// Any document → clean Markdown (a RAG-ingestion building block):
_ = try await client.convertToMarkdown(.path("report.docx"), options: ConvertToMarkdownOptions(saveTo: "report.md"))
// PDF, DOCX, PPTX, XLSX, CSV, HTML, EPUB, TXT/MD, and legacy/ODF office. (Images not supported.)

// Almost anything → PDF:
_ = try await client.convertToPdf(.path("slides.pptx"), options: ConvertToPdfOptions(saveTo: "slides.pdf"))
// office/ODF/Pages/Numbers/RTF/CSV, HTML, Markdown, text, images, SVG, EPUB, or a PDF passthrough.
// Only pdfOptions.grayscale is honored on this endpoint:
_ = try await client.convertToPdf(
    .path("scan.pdf"),
    options: ConvertToPdfOptions(saveTo: "gray.pdf", pdfOptions: PdfOptions(grayscale: true))
)
```

### Image Conversion

```swift
let result = try await client.convertImage(
    .path("photo.heic"),
    options: ConvertImageOptions(outputFormat: "webp", saveTo: "photo.webp")
)
```

Any pair among `jpeg`, `png`, `svg`, `heic`, `webp` — plus PDF rasterization (`pdf` → `jpeg`). Unsupported pairs throw before any request is made:

```swift
import Enconvert

validOutputsFor("json")  // ["csv", "toml", "xml", "yaml"]
validOutputsFor("pdf")   // ["jpeg"]
```

`FileInput` also accepts raw bytes: `.data(someData)` (sent as `upload.bin`), or `.wrapped(data: someData, filename: "photo.heic", contentType: nil)` when you have bytes but no file on disk.

### Document Conversion

```swift
_ = try await client.convertDocument(.path("report.docx"), options: ConvertDocumentOptions(saveTo: "report.pdf"))
_ = try await client.convertDocument(.path("data.json"), options: ConvertDocumentOptions(outputFormat: "yaml", saveTo: "data.yaml"))
_ = try await client.convertDocument(.path("notes.md"), options: ConvertDocumentOptions(outputFormat: "html", saveTo: "notes.html"))
```

Supported inputs: `doc`/`docx`, `xls`/`xlsx`, `ppt`/`pptx`, `odt`, `ods`, `odp`, `ots`, `pages`, `numbers`, `html`, `markdown`, `csv`, `json`, `xml`, `yaml`, `toml`. (EPUB → use `convertToPdf` / `convertToMarkdown`.)

The SDK validates every `{input}-to-{output}` pair against the conversions the API actually implements and throws immediately — with the list of valid outputs for that input — instead of sending a doomed request.

### Supported conversions

| Input | Outputs |
|-------|---------|
| json | csv, toml, xml, yaml |
| xml | csv, json |
| yaml | json |
| csv | json, xml |
| toml | json |
| markdown | html, pdf |
| html | pdf |
| doc, excel, ppt, odt, ods, odp, ots, pages, numbers | pdf |
| jpeg, png, svg, heic, webp | each other (all 20 pairs) |
| pdf | jpeg |

### URL to PDF / Screenshot / Markdown

```swift
_ = try await client.convertUrlToPdf("https://example.com", options: UrlToPdfOptions(saveTo: "page.pdf"))
_ = try await client.convertUrlToScreenshot("https://example.com", options: UrlToScreenshotOptions(viewportWidth: 1440, saveTo: "shot.png"))
_ = try await client.convertUrlToMarkdown("https://example.com/article", options: UrlToMarkdownOptions(saveTo: "article.md"))
```

### Website to PDF / Screenshot (whole-site batch)

Discover every page of a website (via sitemap, or full crawl on Pro/Business plans), convert each one in the background, and receive a single ZIP. Requires a private API key with crawl access.

```swift
let batch = try await client.convertWebsiteToPdf(
    "https://example.com",
    options: WebsiteToPdfOptions(
        crawlMode: .sitemap,             // .auto (default) | .sitemap | .full
        excludePatterns: ["/blog/tag/"]  // full crawl mode only
    )
)
print(batch.batchId, batch.urlCount, batch.discoveryMethod ?? "")

// Block until done and save the ZIP:
let status = try await client.waitForBatch(batch.batchId, options: WaitForBatchOptions(saveTo: "site.zip"))
print("\(status.completed) of \(status.total) pages converted")

// Or poll yourself:
let s = try await client.getBatchStatus(batch.batchId)
if s.status != .processing { print(s.zipDownloadUrl ?? "") }
```

`convertWebsiteToScreenshot` works the same way and produces a ZIP of PNGs.

### PDF Options & Authenticated Pages

```swift
_ = try await client.convertUrlToPdf(
    "https://internal.example.com/report",
    options: UrlToPdfOptions(
        auth: HttpBasicAuth(username: "user", password: "pass"),
        // or cookies / headers:
        cookies: [BrowserCookie(name: "session", value: "abc123", domain: "internal.example.com")],
        headers: ["X-Tenant": "acme"],
        pdfOptions: PdfOptions(
            pageSize: "A4",              // or custom dimensions via pageWidth + pageHeight
            orientation: .landscape,
            margins: PdfMargins(top: 10, bottom: 10, left: 15, right: 15),
            header: PdfHeaderFooter(content: "Quarterly Report", height: 15),
            footer: PdfHeaderFooter(content: "Confidential", height: 12)
        ),
        saveTo: "report.pdf"
    )
)
```

Do not combine `auth` with an `Authorization` header — the API rejects the conflict.

### Job Status (async polling)

```swift
let status = try await client.getJobStatus("job_abc123")
if status.status == .success {
    print(status.presignedUrl ?? "")
}
```

---

## Error Handling

```swift
import Enconvert

do {
    _ = try await client.v2.perceive("https://example.com")
} catch EnconvertError.authentication(let message) {
    print("Invalid API key: \(message)")
} catch EnconvertError.quota(let message) {
    print("Plan feature off or quota exhausted: \(message)")
} catch EnconvertError.rateLimit(let message) {
    print("Too many requests — slow down: \(message)")
} catch let error as EnconvertError {
    print("API error: \(error)")  // "[<status>] <message>"
}
```

## Configuration

```swift
let client = try Enconvert(
    apiKey: "sk_...",
    baseURL: "https://api.enconvert.com",  // default
    timeout: 300                            // seconds, default
)
```

## Get an API Key

Sign up at [enconvert.com](https://enconvert.com). Free tier: 100 ops/month, no credit card.

## License

MIT
