import DeviceActivity
import SwiftUI
import _DeviceActivity_SwiftUI

@main
struct ScreenLogDeviceActivityReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        ScreenLogTodaySummaryReport { configuration in
            ScreenLogTodaySummaryReportView(configuration: configuration)
        }
        ScreenLogStatsDayReport { configuration in
            ScreenLogStatsReportView(configuration: configuration)
        }
        ScreenLogStatsWeekReport { configuration in
            ScreenLogStatsReportView(configuration: configuration)
        }
        ScreenLogStatsMonthReport { configuration in
            ScreenLogStatsReportView(configuration: configuration)
        }
        ScreenLogUsageReport { configuration in
            ScreenLogUsageReportView(configuration: configuration)
        }
        ScreenLogGroupUsageReport0 { _ in
            GroupUsageHiddenReportView()
        }
        ScreenLogGroupUsageReport1 { _ in
            GroupUsageHiddenReportView()
        }
        ScreenLogGroupUsageReport2 { _ in
            GroupUsageHiddenReportView()
        }
        ScreenLogGroupUsageReport3 { _ in
            GroupUsageHiddenReportView()
        }
        ScreenLogGroupUsageReport4 { _ in
            GroupUsageHiddenReportView()
        }
    }
}
