# Screen Time Sharing

Native iOS-first SwiftUI beta for opt-in Screen Time sharing with friends and a configurable WidgetKit friend-card widget.

## Targets

- `ScreenTimeSharing`: SwiftUI iPhone app.
- `ScreenTimeSharingWidget`: WidgetKit extension with AppIntent friend-slot configuration.
- `ScreenTimeSharingCore`: SwiftPM library used for unit-tested models, formatting, upload gating, CloudKit payload mapping, and widget-cache encoding.

## Apple Capabilities

Before running on a device, update the bundle, App Group, and iCloud identifiers in:

- `ScreenTimeSharing/AppConfiguration.swift`
- `ScreenTimeSharing/ScreenTimeSharing.entitlements`
- `ScreenTimeSharingWidget/ScreenTimeSharingWidget.entitlements`
- `ScreenTimeSharing.xcodeproj/project.pbxproj`

The app target includes:

- Family Controls: `com.apple.developer.family-controls`
- Family Controls App and Website Usage: `com.apple.developer.family-controls.app-and-website-usage`
- CloudKit: `iCloud.com.jdco.ScreenTimeSharing`
- App Group: `group.com.jdco.ScreenLog`

The widget target only reads app-group cache data.

## Runtime Behavior

- Users explicitly authorize Screen Time for the individual device owner.
- Home and Stats use all-activity Screen Time reports, so onboarding does not ask users to pick apps.
- Week stats use a Sunday-Saturday calendar week and keep all seven bar slots visible.
- Screen Time app rows keep local application token data for real app icons; upload payloads strip that token data.
- Users choose apps/categories/websites through `FamilyActivityPicker` only when configuring blocking groups.
- `approvedWithDataAccess` maps to per-app/per-website rows.
- Denied, unavailable, or Device Activity errors produce an unavailable snapshot and do not upload placeholder data.
- Friend summaries are mirrored into App Group storage and WidgetKit timelines refresh every 30 minutes.

## Verification

This environment has Command Line Tools but not full Xcode, so app/widget builds and simulator/device runs could not be executed here. The pure Swift core tests run with:

```sh
swift test
```

Device verification still needs a real iPhone with the approved capabilities and an iCloud account.
