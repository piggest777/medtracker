import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    private var reminder: ShieldConfiguration {
        // The shield is rendered by a system host. Use opaque colors and an
        // original, tinted image so contrast does not depend on its inherited tint.
        let background = UIColor(red: 0.07, green: 0.09, blue: 0.10, alpha: 1)
        let accent = UIColor(red: 0.46, green: 0.87, blue: 0.76, alpha: 1)
        let subtitle = UIColor(red: 0.80, green: 0.84, blue: 0.86, alpha: 1)
        let buttonText = UIColor(red: 0.04, green: 0.16, blue: 0.14, alpha: 1)
        let icon = UIImage(systemName: "pills.fill")?
            .withTintColor(accent, renderingMode: .alwaysOriginal)

        return ShieldConfiguration(
            backgroundBlurStyle: nil,
            backgroundColor: background,
            icon: icon,
            title: .init(text: "Time for a check-in", color: .white),
            subtitle: .init(text: "Open MedTracker to review your due reminders and record Taken or Skipped.", color: subtitle),
            primaryButtonLabel: .init(text: "Close", color: buttonText),
            primaryButtonBackgroundColor: accent
        )
    }

    override func configuration(shielding application: Application) -> ShieldConfiguration { reminder }
    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration { reminder }
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration { reminder }
    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration { reminder }
}
