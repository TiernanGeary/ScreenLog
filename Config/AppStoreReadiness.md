# App Store/TestFlight Readiness

## Entitlement Review

- Request Family Controls distribution entitlement for the app target.
- Request Family Controls App and Website Usage if per-app names, bundle identifiers, domains, or category names are needed.
- Keep review notes clear that the audience is peer accountability, not parental control.
- Explain that users select specific apps/categories/websites and can stop sharing through iCloud sharing controls.

## Privacy Notes

- No custom backend in v1.
- No upload when Screen Time authorization is denied, unavailable, or when Device Activity returns no usable data.
- Per-app rows are uploaded only for selected activities and only when Apple returns `approvedWithDataAccess`.
- Aggregate-only fallback omits `appRowsJSON`.
- The widget reads only cached friend summaries from the App Group.

## Device Test Matrix

- Fresh install, denied Screen Time authorization.
- Approved Family Controls without app detail access.
- Approved app detail access on a supported device/account/region.
- Missing iCloud account.
- Create share, accept invite on another Apple Account, revoke share.
- Widget small, medium, and large with 0, 1, 2, and 4 friends.
- Stale cache older than one hour.
- Dynamic Type and narrow display widths.
