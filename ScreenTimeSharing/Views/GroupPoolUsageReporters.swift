import DeviceActivity
import FamilyControls
import SwiftUI
import _DeviceActivity_SwiftUI

/// Hidden host that renders one DeviceActivityReport per assigned pool group so
/// the report extension's group-usage scenes run and refresh each slot's
/// group-scoped seconds while the app is foreground. The reports are 0-sized and
/// accessibility-hidden — they exist only to drive the measurement, not to show.
struct GroupPoolUsageReporters: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            if model.hasScreenTimeAuthorization {
                ForEach(model.poolGroupSlotAssignments, id: \.slot) { assignment in
                    DeviceActivityReport(
                        Self.context(forSlot: assignment.slot),
                        filter: Self.filter(for: assignment.selection)
                    )
                    .frame(width: 0, height: 0)
                    .clipped()
                }
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func context(forSlot slot: Int) -> DeviceActivityReport.Context {
        switch slot {
        case 0: return .screenLogGroupUsage0
        case 1: return .screenLogGroupUsage1
        case 2: return .screenLogGroupUsage2
        case 3: return .screenLogGroupUsage3
        default: return .screenLogGroupUsage4
        }
    }

    private static func filter(for selection: FamilyActivitySelection) -> DeviceActivityFilter {
        DeviceActivityFilter(
            segment: .hourly(during: UsageDateBoundary.dayInterval(containing: Date())),
            devices: .init([.iPhone]),
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens
        )
    }
}
