import WidgetKit
import SwiftUI

@main
struct ScreenTimeSharingWidgetBundle: WidgetBundle {
    var body: some Widget {
        FriendUsageWidget()
        StatsWidget()
    }
}
