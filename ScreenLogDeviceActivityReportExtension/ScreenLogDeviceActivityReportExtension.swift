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
    }
}
