import DeviceActivity
import Foundation

final class ScreenLogActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        let state = ExtensionBlockingSupport.state()
        guard let groupID = ExtensionBlockingSupport.groupID(forRuleNamed: activity.rawValue, state: state) else {
            return
        }

        if activity.rawValue.contains(".allowance.") || BlockingMonitorNameBuilder.isTimeLimitActivity(activity.rawValue) {
            ExtensionBlockingSupport.setShieldActive(false, groupID: groupID, state: state)
        } else {
            ExtensionBlockingSupport.setShieldActive(true, groupID: groupID, state: state)
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        let state = ExtensionBlockingSupport.state()
        guard let groupID = ExtensionBlockingSupport.groupID(forRuleNamed: activity.rawValue, state: state) else {
            return
        }

        ExtensionBlockingSupport.setShieldActive(false, groupID: groupID, state: state)
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        let state = ExtensionBlockingSupport.state()
        guard let groupID = ExtensionBlockingSupport.groupID(forRuleNamed: activity.rawValue, state: state) else {
            return
        }

        ExtensionBlockingSupport.setShieldActive(true, groupID: groupID, state: state)
    }
}
