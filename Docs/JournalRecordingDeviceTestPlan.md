# Journal recording real-device test plan

The background-first start is intentionally treated as a device experiment.
`ToggleJournalRecordingIntent` starts the Live Activity and
`CLLocationUpdate.liveUpdates(.fitness)` from the background App Intent. If
Core Location immediately reports `insufficientlyInUse`, the intent continues
in the foreground and the coordinator establishes a
`CLBackgroundActivitySession`. The independently selectable **Toggle Journal
Recording in App** shortcut always uses that foreground path.

An initial real-device test on August 24, 2026 validated the ideal path with
the app terminated and the phone locked: the Action Button started recording,
real coordinates arrived, and stopping created a place visit. That short test
establishes the baseline; the longer-duration and movement scenarios below
still need hardware coverage.

## Why the session APIs are scoped this way

- `CLLocationUpdate.liveUpdates()` provides the update sequence and the Core
  Location relaunch contract. The app recreates the sequence during launch when
  a durable active recording exists.
- A newly created `CLBackgroundActivitySession` can only become active while the
  app is foregrounded and directly in use. It is therefore used for the reliable
  fallback, and recreated immediately after a Core Location relaunch for a
  recording that previously established one.
- The app does not opt into `CLRequireExplicitServiceSession`, so a
  `CLServiceSession` is not added merely to duplicate the implicit service
  session managed by `liveUpdates()`. Revisit this if recordings are changed to
  rely on Always authorization while the app is not otherwise in use.
- An active Live Activity may make When In Use delivery viable for the direct
  App Intent path, but that exact start sequence is the item this matrix must
  validate on hardware.

## Setup

1. Install a development build on a physical iPhone that supports Live
   Activities and the Action Button.
2. Grant Precise Location and Motion access. Test When In Use and Always
   authorization separately.
3. Add **Toggle Recording** from Journal to Shortcuts and assign it to the
   Action Button.
4. Stream the `Recording`, `Location`, `Motion`, and `Classifier` log categories
   from Console or Xcode.

## Matrix

| Scenario | Action | Pass condition |
| --- | --- | --- |
| Cold background start | Terminate the process without force-quitting the app, lock the phone, then invoke the Action Button | The intent logs a background start, the Live Activity appears, and useful points arrive without opening the app; otherwise the foreground continuation opens Journal and tracking begins there. |
| Lock screen continuation | Start, lock for 10–20 minutes, and walk at least 500 m | The Live Activity timer continues and persisted samples span the locked interval. |
| App switching | Start, use other apps for 10–20 minutes, then stop from the Action Button | Stop succeeds without navigating Journal and creates one entry. |
| Live Activity stop | Start from the Action Button, then tap **Stop** on the expanded Live Activity | The button stops exactly one session, shows a saved-entry summary, and the activity remains visible for about two minutes. |
| System relaunch | Start through the foreground fallback, let tracking become established, then terminate the process from Xcode (do not swipe-force-quit) and move | A later Core Location launch logs `app restored with active session` and appends points to the same session. |
| Fast double invocation | Invoke the shortcut twice as nearly simultaneously as practical | Only one Live Activity and one location sequence exist; the second execution reports a transition in progress or performs the opposite durable transition. |
| Stationary visit | Record 15+ minutes inside one building | Finalization logs `visit`; the representative coordinate resolves through the existing location pipeline. |
| Walking transit | Walk 500+ m and stop | Finalization logs `transit`, stores a simplified route, and motion is predominantly walking. |
| Mixed journey | Walk, ride in a vehicle, then walk | The entry retains timestamped motion observations and uses the dominant meaningful mode. |
| Permission denied | Deny location and invoke the Action Button | No false “active tracking” state is reported; Journal opens for the foreground fallback without adding success/status messages to the shortcut. |

Do not use a swipe-up force quit as the relaunch test. iOS treats a user force
quit as an instruction not to relaunch the app for ordinary background events.

## Useful log sequence

```text
[Recording] intent invoked
[Recording] started session <id> via backgroundIntent
[Recording] Live Activity started
[Location] liveUpdates sequence started
[Location] received <latitude>, <longitude>, accuracy <meters>m
[Recording] stopping session <id>
[Motion] queried <start> → <end>; <count> observations
[Classifier] transit; <distance>m; dominant mode <mode>
[Recording] finalized session <id>
```
