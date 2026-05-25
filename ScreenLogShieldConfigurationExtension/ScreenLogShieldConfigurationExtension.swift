import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ScreenLogShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        configuration(
            copy: ExtensionBlockingSupport.shieldCopy(
                matching: application.token,
                itemName: application.localizedDisplayName
            )
        )
    }

    override func configuration(
        shielding application: Application,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        configuration(
            copy: ExtensionBlockingSupport.shieldCopy(
                matching: application.token,
                itemName: application.localizedDisplayName
            )
        )
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        configuration(
            copy: ExtensionBlockingSupport.shieldCopy(
                matching: webDomain.token,
                itemName: "this website"
            )
        )
    }

    override func configuration(
        shielding webDomain: WebDomain,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        configuration(
            copy: ExtensionBlockingSupport.shieldCopy(
                matching: webDomain.token,
                itemName: "this website"
            )
        )
    }

    private func configuration(copy: ShieldCopy) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemMaterial,
            backgroundColor: .systemBackground,
            icon: UIImage(systemName: "lock.shield.fill"),
            title: ShieldConfiguration.Label(
                text: copy.title,
                color: .label
            ),
            subtitle: ShieldConfiguration.Label(
                text: copy.subtitle,
                color: .secondaryLabel
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: copy.primaryButton,
                color: .white
            ),
            primaryButtonBackgroundColor: .systemBlue,
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: copy.secondaryButton,
                color: copy.isFriendRequestEnabled ? .systemBlue : .tertiaryLabel
            )
        )
    }
}
