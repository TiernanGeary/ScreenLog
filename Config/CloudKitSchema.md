# CloudKit Schema

Container: `iCloud.com.jdco.ScreenTimeSharing`

Private custom zone: `ScreenTimeSharing`

## UserProfile

Root record shared through `CKShare`.

| Field | Type | Notes |
| --- | --- | --- |
| `displayName` | String | User-controlled share display name. |
| `avatarColorHex` | String | Widget/app avatar color. |
| `shareStatus` | String | `notShared`, `sharing`, or `revoked`. |
| `updatedAt` | Date | Last profile update. |

## DailyUsageSnapshot

Child of `UserProfile` via `record.parent`; records are shared with accepted participants.

| Field | Type | Notes |
| --- | --- | --- |
| `ownerProfileID` | String | Local profile identifier. |
| `date` | Date | Start of local day. |
| `calendarIdentifier` | String | Calendar used for the day boundary. |
| `timeZoneIdentifier` | String | Time zone used for the day boundary. |
| `totalDuration` | Double | Optional daily total seconds. |
| `selectedAppDuration` | Double | Optional selected-activity total seconds. |
| `appRowsJSON` | Bytes | Optional JSON array of app/web rows; omitted for aggregate-only snapshots. |
| `lastUpdated` | Date | Device Activity data freshness. |
| `capabilityStatus` | String | `fullAppDetail`, `aggregateOnly`, or `unavailable`. |
| `capabilityReason` | String | Optional fallback reason. |
| `profileReference` | Reference | Convenience reference to the profile root. |

## FriendShare

Accepted share state is local in v1. The app stores accepted shared zone IDs in `UserDefaults` under `AcceptedCloudKitShareZones.v1`, then reads `UserProfile` and latest `DailyUsageSnapshot` from `sharedCloudDatabase`.
