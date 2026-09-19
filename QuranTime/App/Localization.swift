import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english, arabic
    var id: String { rawValue }
    var label: String { switch self { case .system: return "Follow iPhone"; case .english: return "English"; case .arabic: return "العربية" } }
    var code: String {
        switch self {
        case .system: return Locale.preferredLanguages.first?.hasPrefix("ar") == true ? "ar" : "en"
        case .english: return "en"
        case .arabic: return "ar"
        }
    }
}
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { switch self { case .system: return "Follow iPhone"; case .light: return "Light"; case .dark: return "Dark" } }
    var colorScheme: ColorScheme? { switch self { case .system: return nil; case .light: return .light; case .dark: return .dark } }
}
enum I18n {
    static var language: AppLanguage { AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "system") ?? .system }
    static var isArabic: Bool { language.code == "ar" }
    static var locale: Locale { Locale(identifier: isArabic ? "ar@numbers=arab" : "en") }
    static func text(_ key: String) -> String {
        guard let path = Bundle.main.path(forResource: language.code, ofType: "lproj"), let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
    static func format(_ key: String, _ arguments: CVarArg...) -> String { String(format: text(key), locale: locale, arguments: arguments) }
    static func number(_ number: Int) -> String { number.formatted(.number.locale(locale)) }
    static func time(_ date: Date) -> String { date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale)) }
}

/// Presented controllers can reset layoutDirection; apply preferences inside
/// each sheet as well as the main shell.
struct AppPresentation: ViewModifier {
    @AppStorage("appLanguage") private var language = AppLanguage.system.rawValue
    @AppStorage("appAppearance") private var appearance = AppAppearance.system.rawValue
    func body(content: Content) -> some View {
        let code = (AppLanguage(rawValue: language) ?? .system).code
        content.environment(\.locale, Locale(identifier: code == "ar" ? "ar@numbers=arab" : "en"))
            .environment(\.layoutDirection, code == "ar" ? .rightToLeft : .leftToRight)
            .preferredColorScheme((AppAppearance(rawValue: appearance) ?? .system).colorScheme)
    }
}
extension View {
    func appPresentation() -> some View { modifier(AppPresentation()) }
}
