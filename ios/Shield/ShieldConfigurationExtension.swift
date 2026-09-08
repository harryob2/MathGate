import ManagedSettings
import ManagedSettingsUI
import MathGateKit
import UIKit

/// The screen iOS shows over a blocked app. The Android build draws its own `BlockingActivity`;
/// here the OS renders it, so this only supplies the copy and colours.
final class MathGateShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(
        shielding application: Application,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(
        shielding webDomain: WebDomain,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        makeConfiguration()
    }

    private func makeConfiguration() -> ShieldConfiguration {
        let state = SharedGateStateStore.load()
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1),
            icon: UIImage(named: "ShieldIcon"),
            title: ShieldConfiguration.Label(text: "Do a Math Academy task", color: .white),
            subtitle: ShieldConfiguration.Label(text: subtitle(state), color: UIColor(white: 0.7, alpha: 1)),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Check Math Academy", color: .white),
            primaryButtonBackgroundColor: UIColor(red: 0.49, green: 0.30, blue: 1.0, alpha: 1),
            secondaryButtonLabel: ShieldConfiguration.Label(text: "Not now", color: UIColor(white: 0.7, alpha: 1))
        )
    }

    /// Says exactly why the app is shut, the way the Android blocker does. A failed check is
    /// named rather than hidden, so a wrong password does not look like an unfinished task.
    private func subtitle(_ state: SharedGateState) -> String {
        if let detail = state.lastStatusDetail, !detail.isEmpty {
            return "\(detail)\n\nApps stay locked until MathGate can confirm a completed task."
        }
        let reset = state.resetTime.label
        return "No lesson, review, multistep or quiz completed since \(reset). "
            + "Finish any one of them and this unlocks until tomorrow."
    }
}
