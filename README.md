# MedTracker

**Active development** · 2026

A personal, offline iPhone app written in Swift and SwiftUI. Daily medication reminders pause user-selected apps through Apple's Screen Time APIs until every due dose is recorded as **Taken** or **Skipped**. Unresolved doses become **Missed** at local midnight.

## Open and run

1. Open `MedTracker.xcodeproj` in Xcode. The app targets iOS 17 or later, and the project was verified with Xcode 27.1. The generated project is included. Use XcodeGen when changing the project structure.
2. For device builds, create `Config/Signing.local.xcconfig` with your signing settings. This file is ignored by Git.

   ```xcconfig
   MEDTRACKER_TEAM = YOUR_TEAM_ID
   MEDTRACKER_BUNDLE_ID = com.yourname.medtracker
   MEDTRACKER_APP_GROUP = group.$(MEDTRACKER_BUNDLE_ID)
   ```

3. Select a connected iPhone and the **MedTracker** scheme. Enable automatic signing for the app and both extensions. These capabilities require an Apple Developer Program team that can provision Family Controls; a free Personal Team may not support them.
4. In **Signing & Capabilities**, verify:
   - **MedTracker**: Family Controls, Time Sensitive Notifications, and App Groups.
   - **MedTrackerMonitor**: Family Controls and the **same** App Group.
   - **MedTrackerShield**: Family Controls. The static shield does not read shared data and needs no App Group.
5. Register/enable the App Group for the app and monitor App IDs in your developer account if automatic signing does not do so. Its identifier must match `MEDTRACKER_APP_GROUP` exactly. All three bundle IDs derive from the same base identifier.
6. Enable Developer Mode on the iPhone if prompted, then build and run. Complete onboarding, add a medication with a time a few minutes ahead, and enable Screen Time access in the app's Settings. Choose a nonessential app to block and enable notifications separately.

Simulator runs support medication tracking, settings, and history. Screen Time authorization and selection controls are disabled there because enforcement must be validated on a physical device. A simulator-only local store fallback supports unsigned preview builds; device builds never silently fall back when the App Group is missing.

## Behavior

- Each medication has a name, optional dose description, and one or more fixed daily local times. Duplicate times are rejected by the editor. The first version supports up to **60 medication/time reminders** to leave room under the local-notification request limit.
- Adding a medication does not create retroactive reminders. Editing changes future occurrences while preserving already-due doses and recorded history, including the original medication name and dose description.
- A single shared app selection applies to all medications. The system picker also supports categories and websites; these are shielded if selected. Avoid selecting essential apps or broad categories containing them.
- Today and Settings show selected apps with their native names/icons and individual statuses, such as Blocked, Available, or Paused. Status reads MedTracker's named Screen Time store and does not report restrictions from other apps. Categories and websites are listed separately when selected. After choosing apps, the picker action changes to **Change selection**.
- Selections are limited to 50 app tokens, 50 category tokens, and 50 website tokens to respect [ManagedSettings limits](https://developer.apple.com/documentation/managedsettings/shieldsettings/applications-swift.property). An oversized selection cannot be saved.
- All due doses must be resolved before unlocking. **Skip** asks for confirmation and never records intake. Repeated taps and callbacks are idempotent. Future and missed doses cannot be marked taken.
- Deleting a medication cancels its unresolved reminders and preserves taken/skipped/missed history. Pausing blocking changes no outcomes and leaves notifications enabled.
- At the start of each new local date, unresolved earlier occurrences become Missed. Previous-day doses no longer block. A dose scheduled for midnight can immediately block on the new day.
- Daily times follow the device's local zone. A nonexistent spring-forward time moves forward while preserving minutes; a repeated autumn time produces one occurrence, using its first instance. A check-in is keyed by medication, local calendar date, and reminder time to prevent duplicates.
- Notification text hides medication names by default. Tapping a notification opens Today. Notification permission and scheduling work independently of Screen Time permission.
- Screen Time access can be revoked in iOS Settings and the app can be deleted. Picker tokens are cleared after a confirmed denial/revocation; an initial unresolved authorization status preserves the saved selection and last known grant. After granting access again following revocation, select apps again.

## Architecture

- `Shared/Core`: Foundation-only data models, daily occurrence engine, and a versioned Codable JSON store. This is also a standalone Swift package for fast tests.
- `Shared/ScreenTime`: individual Family Controls authorization state, opaque picker token persistence, a named ManagedSettings store, and recurring DeviceActivity registration.
- `MedTracker`: SwiftUI onboarding, Today, medication editing, history, settings, and local notifications.
- `MonitorExtension`: reconciles persisted state at interval start/end and applies shields. It uses the same engine as the app.
- `ShieldExtension`: generic shield instructing users to open MedTracker manually. Its Close button closes the shielded app; it does not claim to launch MedTracker.

App and monitor coordinate every read/modify/write with `NSFileCoordinator`; an in-process lock also serializes threads. Writes are atomic, use data protection until first unlock, and finish before shield changes are applied inside the coordinated operation. Unreadable or unsupported data is surfaced rather than overwritten. There are no network calls, accounts, analytics, external dependencies, or sync. Normal device backups may include the local app data.

Monitoring uses one recurring interval per distinct time plus midnight. Intervals last 23 hours 59 minutes so an idle phone does not miss a short monitoring window; both start and end callbacks recalculate actual due doses rather than blindly enabling or disabling blocking. Duplicate times share an activity. Registration errors clear partial schedules and shields and show a retryable issue instead of claiming blocking is active. iOS can reject excessive or closely spaced activities even below the reminder limit; reduce distinct reminder times if this occurs.

DeviceActivity callbacks are system-controlled and occur when the device is used. App foreground entry, a 30-second foreground refresh, significant time changes, and extension callbacks reconcile state. A zone/offset change re-registers monitoring on the next foreground entry. Background callbacks recalculate against the current local time, but exact enforcement after clock/zone changes while the app stays closed requires hardware validation. Missed history and midnight reset are persisted on the next reconciliation; they do not require an exact midnight process wakeup.

## Automated checks

From the repository root:

```sh
swift test
xcodebuild -project MedTracker.xcodeproj -scheme MedTracker \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
xcodebuild -project MedTracker.xcodeproj -scheme MedTracker \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO test
```

Core tests cover overlapping doses, future doses, midnight, several days offline, idempotent reports, editing/deletion, pause semantics, DST, zone changes, persistence, corrupt/newer-schema files, failed transactions, and concurrent store clients. Simulator UI tests cover onboarding, adding a medication, pausing, due-dose check-ins, history, diagnostics, and persistence across relaunch. A layout regression exercises compact app rows and readable badges in dark mode and with accessibility text sizes, using representative labels because real Screen Time tokens require a device. Simulator-only launch fixtures use an isolated temporary store and cannot activate on a physical device.

Core regression coverage also includes queued selection saves during busy updates, unresolved authorization preserving selections, confirmed denial clearing invalid tokens, and read-only diagnostics. A signed install and actual Screen Time enforcement require the hardware checklist below.

## Test without pills or waiting

1. Open **Settings → Try it out → Test mode → Start test**. Two practice doses become due immediately; no medication schedule is required.
2. On a physical iPhone, open one of your selected apps and check its shield. Screen Time access must be enabled and blocking must be unpaused. The simulator supports the practice UI, without actual enforcement.
3. Mark one practice dose **Taken**: blocking remains. Mark the other **Skipped**: test blocking clears. These actions never create real medication-intake records.
4. Use **Make doses due now** to repeat, or **Simulate next day** while doses are unresolved to mark them Missed and reset test blocking. The simulated new day starts before its next dose; tap Make doses due now to trigger it. The iPhone's clock and real schedules are unaffected.
5. Tap **End test** in the test screen or the Today banner to restore normal blocking. Real doses that are currently due can still block apps after ending the test. **Restart test** clears only the practice session and its practice history.

Test mode is clearly marked on Today and persists across relaunches until ended. It uses the same selected apps and ManagedSettings shields as normal operation; real schedules, notifications, and history remain separate. Real scheduled occurrences continue to reconcile against the actual clock. Practice results appear only in the test screen. Normal history never includes practice outcomes.

This tests immediate blocking, resolving multiple doses, missed-dose reset, and persistence. It does not establish the timing of actual DeviceActivity background callbacks; those still need the physical-device schedule checks below. Test mode and its pending count are included in Diagnostics.

## High-priority medication alerts

Medication reminders request **Time Sensitive** delivery with the normal notification sound. The app target includes the Time Sensitive Notifications capability. Opening the updated app re-registers existing daily reminders with this priority. Medication names remain hidden unless explicitly enabled.

In **Settings → Reminders**, **Time Sensitive** shows whether iOS allows that delivery level. Use **Open iOS Settings** to enable notifications and Time Sensitive Notifications, and allow Time Sensitive notifications in the Focus modes you use. This can bypass Focus and Scheduled Summary when allowed; it still respects silent mode and the user's notification/sound settings. Apple's [Time Sensitive documentation](https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel/timesensitive) describes those controls.

Tap **Send test alert** for a clearly labeled practice notification after five seconds. It requests notification permission if needed, uses the same Time Sensitive content builder as medication reminders, and creates no medication history. The one-off test request is preserved when daily reminders are refreshed. Diagnostics logs the notification's stored interruption level and the current permission settings.

Playing sound through silent mode requires [Critical Alerts and Apple's entitlement approval](https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel/critical). This build uses Time Sensitive alerts; it does not request Critical Alerts privileges. Check Focus and silent-mode behavior on your physical iPhone, because simulator request metadata does not establish actual interruption behavior.

## Diagnose an empty selected-app list

1. Install the latest build, open Settings, choose an app, and tap **Done**. The picker now waits for the save and a coordinated readback before closing; an unsuccessful save leaves it open with an error.
2. Open **Settings → About your data → Diagnostics** and tap **Refresh report**. Compare the in-memory and on-disk selection counts. Counts above zero with missing names/icons point to native activity-label rendering; zero counts point to the picker, persistence, or authorization path. Technical counts are kept in Diagnostics so the normal app list stays uncluttered.
3. Tap **Copy report** to capture diagnostics for a bug report. The report includes selection counts, authorization, monitoring/shield state, and the last 200 technical events from the current app session. Copy it after reproducing, before terminating the app.
4. For extension events, connect the iPhone to macOS Console, start streaming device logs, and filter the subsystem **MedTracker**. Xcode's debug console also displays the attached process's logs. Categories include Picker, Selection, Storage, Authorization, Model, Monitoring, Monitor, Shield, UI, and Lifecycle.

The expected sequence is `draft changed apps=1` → `Done tapped apps=1` → `encoded ... round-trip verified` → storage commit → `save verified from disk apps=1` → `Settings selection changed apps=1`. Logs explicitly identify decoding failures, busy-update queuing, confirmed permission-based clearing, and monitoring registration failures. App Group IDs and process IDs help distinguish the app from the monitor. Medication names, dose text, raw app tokens, and serialized JSON are not recorded.

To stream simulator logs:

```sh
xcrun simctl spawn booted log stream --level info --predicate 'subsystem == "MedTracker"'
```

Apple documents [authorization's initial unresolved state](https://developer.apple.com/documentation/familycontrols/authorizationcenter/authorizationstatus) and [viewing unified logs](https://developer.apple.com/documentation/os/viewing-log-messages).

To regenerate the included project after changing `project.yml`:

```sh
brew install xcodegen  # if needed
xcodegen generate
```

## Physical-device acceptance checklist

These checks cannot be established by simulator or unsigned builds:

- Select one test app. Schedule two medications for the same time. Leave MedTracker closed, keep the device idle past the due time, then open the selected app. Confirm it is shielded.
- Record one dose Taken: the shield remains. Record the other Skipped: it disappears. Check history and relaunch MedTracker to verify persistence.
- Leave a due dose unresolved across midnight. Confirm it becomes Missed, the shield clears on the next device activity, and the next day's dose blocks again when due. Repeat with a midnight dose.
- Delete a medication while due, and pause/resume while due. Check shields follow those actions without a false Taken record.
- Deny notifications while granting Screen Time, then reverse the permissions. Confirm each function works independently and status is accurate.
- Revoke Screen Time in iOS Settings; return to MedTracker. Confirm it reports missing access. Grant access, reselect apps, and retry.
- Repeat with the main app terminated, a device restart followed by first unlock, no network, several days without opening MedTracker, and device-use gaps around interval boundaries.
- Check midnight, DST, and time-zone changes on a dedicated test device. Reopen MedTracker after changing the zone to re-register schedules. Verify no duplicate reports.

This repository can be compiled without a signing identity. Installing and establishing real Screen Time behavior requires your developer team and physical iPhone. TestFlight/App Store distribution is deferred and requires [Apple's Family Controls distribution approval](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement) for the app and Screen Time extensions. See also [DeviceActivity callback behavior](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter) and [individual authorization](https://developer.apple.com/videos/play/wwdc2022/110336/).
