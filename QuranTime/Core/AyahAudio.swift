import Foundation

/// Reciter/style names mapped against EveryAyah's published recitations.js catalogue.
/// Each filename is a zero-padded surah and ayah, never a guessed position in a full surah.
enum AyahAudio {
    static let folders: [Int: String] = [
        1: "Abdul_Basit_Mujawwad_128kbps", 2: "Abdul_Basit_Murattal_192kbps",
        3: "Abdurrahmaan_As-Sudais_192kbps", 4: "Abu_Bakr_Ash-Shaatree_128kbps",
        5: "Hani_Rifai_192kbps", 6: "Husary_128kbps", 7: "Alafasy_128kbps",
        9: "Minshawy_Murattal_128kbps", 10: "Saood_ash-Shuraym_128kbps", 12: "Husary_Muallim_128kbps"
    ]
    static func url(surah: Int, ayah: Int, reciterID: Int) -> URL? {
        guard (1...114).contains(surah), (1...286).contains(ayah), let folder = folders[reciterID] else { return nil }
        return URL(string: "https://everyayah.com/data/\(folder)/" + String(format: "%03d%03d.mp3", surah, ayah))
    }
}
