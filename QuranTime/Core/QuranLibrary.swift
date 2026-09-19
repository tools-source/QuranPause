import Foundation

struct Surah: Codable, Identifiable {
    let id: Int
    let name: String
    let transliteration: String
    let translation: String
    let type: String
    let total_verses: Int
    let verses: [Verse]
}
struct Verse: Codable, Identifiable {
    let id: Int
    let text: String
    let translation: String
}
@Observable final class QuranLibrary {
    var surahs: [Surah] = []
    var pages: [QuranPage] = []
    var error: String?
    init() {
        do {
            guard let url = Bundle.main.url(forResource: "quran_en", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
            surahs = try JSONDecoder().decode([Surah].self, from: Data(contentsOf: url))
            guard let pageURL = Bundle.main.url(forResource: "page_index", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
            pages = try JSONDecoder().decode([QuranPage].self, from: Data(contentsOf: pageURL))
            guard pages.count == 604, pages.reduce(0, { $0 + $1.verses.count }) == 6236 else { throw CocoaError(.fileReadCorruptFile) }
            guard surahs.count == 114, surahs.reduce(0, { $0 + $1.verses.count }) == 6236 else { throw CocoaError(.fileReadCorruptFile) }
        } catch { self.error = "The offline Quran could not be loaded. Please reinstall QuranPause. \(error.localizedDescription)" }
    }
}

struct QuranPage: Codable, Identifiable {
    let id: Int
    let verses: [PageVerse]
}
struct PageVerse: Codable {
    let surah: Int
    let ayah: Int
    let juz: Int
}
extension Surah {
    var displayName: String { I18n.isArabic ? name : transliteration }
    var descriptionLine: String {
        I18n.isArabic ? I18n.format("%lld ayahs", total_verses) : I18n.format("%@ · %lld ayahs", translation, total_verses)
    }
}

// The page index lists ayahs that START on a page. Include an ayah continued from
// the previous printed page so every visible ayah is available for copy/listen.
extension QuranPage {
    var selectableVerses: [PageVerse] {
        guard let entry = Mushaf.manifest?.pages.first(where: { $0.page == id }) else { return verses }
        let parts = entry.firstAyah.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, !verses.contains(where: { $0.surah == parts[0] && $0.ayah == parts[1] }) else { return verses }
        return [PageVerse(surah: parts[0], ayah: parts[1], juz: verses.first?.juz ?? 1)] + verses
    }
}

// The reader shows the printed Mushaf page, so ayahs are chosen by tapping the page
// itself. `PageVerse.key` names an ayah the way the verified page data does.
extension PageVerse { var key: String { "\(surah):\(ayah)" } }
