import CryptoKit
import Foundation

/// The bundled 604-page Madinah Mushaf: KFGQPC QCF V2 page fonts placed on the
/// printed 15-line layout. `scripts/download-mushaf.py` builds and verifies the
/// snapshot; this loader re-verifies each page against `manifest.json` before it
/// is shown, so a damaged or mismatched file is never rendered as Quran text.
enum Mushaf {
    static let pageCount = 604
    static let firstWordGlyph: UInt32 = 0xFC41
    private static let lineTypes: Set<String> = ["text", "surah-header", "basmala"]

    struct Manifest: Decodable {
        struct Page: Decodable {
            let page: Int
            let glyphs: Int
            let firstAyah: String
            let lastAyah: String
            let layoutSHA256: String
            let ayahsSHA256: String
            let fontSHA256: String
        }
        let edition: String
        let glyphs: String
        let pages: [Page]
    }

    struct Layout: Decodable {
        struct Line: Decodable {
            let type: String
            let content: String
            let surah: Int?
        }
        let page: Int
        let lines: [Line]
    }

    /// How many of a page's glyphs belong to one ayah, in printed order.
    /// Built by `scripts/download-mushaf.py` from the same verified word data as the
    /// layout, so a touched glyph resolves to its ayah without inferring a boundary.
    struct AyahRuns: Decodable {
        struct Run: Decodable {
            let key: String
            let glyphs: Int
        }
        let page: Int
        let ayahs: [Run]
    }

    struct Page {
        let layout: Layout
        let font: Data
        /// Page 1's font, whose Al-Fatihah glyphs draw the basmala lines.
        let basmalaFont: Data?
        /// Ayah ownership of the page's glyphs; nil when it fails verification, which
        /// disables on-page selection but still shows the printed page.
        let ayahRuns: [AyahRuns.Run]?
    }

    static let manifest: Manifest? = resource("manifest", "json", "Mushaf")
        .flatMap { try? JSONDecoder().decode(Manifest.self, from: $0) }
        .flatMap { $0.pages.map(\.page) == Array(1...pageCount) ? $0 : nil }

    /// Returns the page only when every file matches the verified snapshot.
    static func page(_ number: Int) -> Page? {
        guard (1...pageCount).contains(number), let entry = manifest?.pages[number - 1],
              let layoutData = verified(String(number), "json", "Mushaf/Pages", sha256: entry.layoutSHA256),
              let font = verified("p\(number)", "woff2", "Mushaf/Fonts", sha256: entry.fontSHA256),
              let layout = try? JSONDecoder().decode(Layout.self, from: layoutData),
              isValid(layout, glyphs: entry.glyphs) else { return nil }
        var basmalaFont: Data?
        if layout.lines.contains(where: { $0.type == "basmala" }) {
            guard let first = manifest?.pages.first,
                  let data = verified("p1", "woff2", "Mushaf/Fonts", sha256: first.fontSHA256) else { return nil }
            basmalaFont = data
        }
        return Page(layout: layout, font: font, basmalaFont: basmalaFont, ayahRuns: ayahRuns(number, entry: entry))
    }

    /// The runs must cover exactly the page's glyphs, once each, in printed order,
    /// starting and ending on the page's own first and last ayah.
    static func ayahRuns(_ number: Int, entry: Manifest.Page) -> [AyahRuns.Run]? {
        guard let data = verified("ayahs-\(number)", "json", "Mushaf/Ayahs", sha256: entry.ayahsSHA256),
              let runs = try? JSONDecoder().decode(AyahRuns.self, from: data), runs.page == number,
              runs.ayahs.allSatisfy({ $0.glyphs > 0 }),
              runs.ayahs.reduce(0, { $0 + $1.glyphs }) == entry.glyphs,
              Set(runs.ayahs.map(\.key)).count == runs.ayahs.count,
              runs.ayahs.first?.key == entry.firstAyah, runs.ayahs.last?.key == entry.lastAyah
        else { return nil }
        return runs.ayahs
    }

    /// One printed line split into runs of glyphs that belong to the same ayah.
    /// `key` is nil for a surah heading or basmala, which are not page glyphs.
    struct Segment: Equatable {
        let key: String?
        let content: String
    }

    /// Splits each line of a verified page into its ayahs, in printed order, so the
    /// reader can mark a touched ayah in place. Returns nil unless every glyph of the
    /// page is covered exactly once by the page's own ayah runs.
    static func segments(_ page: Page) -> [[Segment]]? {
        guard let runs = page.ayahRuns else { return nil }
        var index = 0
        var remaining = runs.first?.glyphs ?? 0
        var lines: [[Segment]] = []
        for line in page.layout.lines {
            guard line.type == "text" else {
                lines.append([Segment(key: nil, content: line.content)])
                continue
            }
            var segments: [Segment] = []
            var content = ""
            for character in line.content {
                if character.unicodeScalars.allSatisfy(\.properties.isWhitespace) {
                    content.append(character)
                    continue
                }
                while remaining == 0 {
                    if !content.isEmpty { segments.append(Segment(key: runs[index].key, content: content)) }
                    content = ""
                    index += 1
                    guard index < runs.count else { return nil }
                    remaining = runs[index].glyphs
                }
                content.append(character)
                remaining -= 1
            }
            guard index < runs.count else { return nil }
            if !content.isEmpty { segments.append(Segment(key: runs[index].key, content: content)) }
            lines.append(segments)
        }
        // Every run must have been used, and the last one exhausted.
        guard index == runs.count - 1, remaining == 0 else { return nil }
        return lines
    }

    /// Pages 1-2 have 8 lines and the rest 15; the text lines must hold exactly the
    /// page's run of word glyphs, in order, so no word is missing, repeated, or foreign.
    static func isValid(_ layout: Layout, glyphs: Int) -> Bool {
        guard layout.lines.count == (layout.page <= 2 ? 8 : 15),
              layout.lines.allSatisfy({ lineTypes.contains($0.type) && !$0.content.isEmpty }) else { return false }
        let placed = layout.lines.filter { $0.type == "text" }
            .flatMap { $0.content.unicodeScalars.filter { !$0.properties.isWhitespace }.map(\.value) }
        return placed == Array(firstWordGlyph..<firstWordGlyph + UInt32(glyphs))
    }

    private static func verified(_ name: String, _ ext: String, _ subdirectory: String, sha256: String) -> Data? {
        guard let data = resource(name, ext, subdirectory) else { return nil }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return digest == sha256 ? data : nil
    }

    private static func resource(_ name: String, _ ext: String, _ subdirectory: String) -> Data? {
        let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory)
            ?? Bundle.main.url(forResource: name, withExtension: ext)
        return url.flatMap { try? Data(contentsOf: $0) }
    }
}
