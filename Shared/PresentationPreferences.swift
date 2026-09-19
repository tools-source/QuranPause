import Foundation

enum PresentationPreferences {
    static let group = "group.com.quranpause.shared"
    static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }
    static func save(language: String, appearance: String) {
        defaults.set(language, forKey: "displayLanguage")
        defaults.set(appearance, forKey: "displayAppearance")
    }
    static var language: String { defaults.string(forKey: "displayLanguage") ?? (Locale.preferredLanguages.first?.hasPrefix("ar") == true ? "ar" : "en") }
    static var appearance: String { defaults.string(forKey: "displayAppearance") ?? "system" }
}
