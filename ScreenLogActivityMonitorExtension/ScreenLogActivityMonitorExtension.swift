import DeviceActivity
import Foundation

final class ScreenLogActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        BlockingDiagnosticsLog.record("intervalDidStart: \(activity.rawValue)")
        let state = ExtensionBlockingSupport.state()

        // An unblock window's re-block monitor starts its interval at the unblock
        // expiry (a >=15-minute window is required by the system), so this start
        // callback is our signal to re-apply shields.
        if BlockingMonitorNameBuilder.isUnblockActivity(activity.rawValue) {
            ExtensionBlockingSupport.refreshActiveShields(state: state)
            return
        }

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
        BlockingDiagnosticsLog.record("intervalDidEnd: \(activity.rawValue)")
        let state = ExtensionBlockingSupport.state()
        if BlockingMonitorNameBuilder.isUnblockActivity(activity.rawValue) {
            ExtensionBlockingSupport.refreshActiveShields(state: state)
            return
        }

        guard let groupID = ExtensionBlockingSupport.groupID(forRuleNamed: activity.rawValue, state: state) else {
            return
        }

        ExtensionBlockingSupport.setShieldActive(false, groupID: groupID, state: state)
    }

    // Fires `warningTime` before intervalEnd — for unblock windows this lands at
    // the unblock expiry, giving us a reliable sub-15-minute re-block trigger.
    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        BlockingDiagnosticsLog.record("intervalWillEndWarning: \(activity.rawValue)")
        let state = ExtensionBlockingSupport.state()
        if BlockingMonitorNameBuilder.isUnblockActivity(activity.rawValue) {
            ExtensionBlockingSupport.refreshActiveShields(state: state)
        }
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        BlockingDiagnosticsLog.record("eventDidReachThreshold: \(activity.rawValue)")
        let state = ExtensionBlockingSupport.state()
        guard let groupID = ExtensionBlockingSupport.groupID(forRuleNamed: activity.rawValue, state: state) else {
            return
        }

        ExtensionBlockingSupport.setShieldActive(true, groupID: groupID, state: state)
    }
}
