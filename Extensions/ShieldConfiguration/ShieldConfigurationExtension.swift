import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    private var configuration: ShieldConfiguration {
        let arabic = PresentationPreferences.language == "ar"
        let appearance = PresentationPreferences.appearance
        let background = UIColor { traits in
            let dark = appearance == "dark" || (appearance == "system" && traits.userInterfaceStyle == .dark)
            return dark ? UIColor(red: 0.06, green: 0.10, blue: 0.08, alpha: 1) : UIColor(red: 0.96, green: 0.95, blue: 0.91, alpha: 1)
        }
        let foreground = UIColor { traits in
            let dark = appearance == "dark" || (appearance == "system" && traits.userInterfaceStyle == .dark)
            return dark ? UIColor(red: 0.92, green: 0.95, blue: 0.91, alpha: 1) : UIColor(red: 0.12, green: 0.29, blue: 0.24, alpha: 1)
        }
        return ShieldConfiguration(
            backgroundBlurStyle: appearance == "dark" ? .systemUltraThinMaterialDark : appearance == "light" ? .systemUltraThinMaterialLight : .systemUltraThinMaterial,
            backgroundColor: background,
            icon: UIImage(systemName: "book.closed.fill"),
            title: .init(text: arabic ? "وقت قليل للقرآن" : "A little time for the Quran", color: foreground),
            subtitle: .init(text: arabic ? "افتح وقفة قرآن، واقرأ أو استمع لتكمل جلسة التركيز وتفتح تطبيقاتك." : "Open QuranPause and read or listen to complete your focus session and unlock your apps.", color: foreground),
            primaryButtonLabel: .init(text: arabic ? "إغلاق" : "Close", color: .white),
            primaryButtonBackgroundColor: UIColor(red: 0.12, green: 0.29, blue: 0.24, alpha: 1)
        )
    }
    override func configuration(shielding application: Application) -> ShieldConfiguration { configuration }
    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration { configuration }
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration { configuration }
    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration { configuration }
}
