# SwiftData audit — September 2026

This audit covers the model schema, container/context ownership, timeline and search reads, entry creation and editing, review drafts, deletion, share-sheet import, backup restore, automatic detection, enrichment, contacts, HealthKit import, and recording. It changes the shared persistence patterns rather than adding a catch around each visible crash.

The reported device crashes were not individually reproduced or attributed to a captured device stack. The findings below distinguish source-level hazards, tests of the replacement behavior, and failures observed during implementation. No personal journal store was reset or directly edited during the audit.

## Findings and changes

| Area | Finding | Result |
| --- | --- | --- |
| Context ownership | UI, maintenance, feed projection, HealthKit import, recording, and enrichment independently loaded and changed the same relationship graph. Serializing each model actor did not serialize the graph across those actors and the UI. | `JournalPersistenceServices` uses the container's main context for live model work. Services explicitly retain the container. The production app no longer constructs independent `ModelContext`s or model actors. |
| Background work | Photo matching and visit geocoding retained fetched models across suspension. Some recording callbacks and finalization also retained live objects after work could be stopped or records changed. | Photo/visit work captures IDs and values, fetches current models afterward, and checks the original inputs before applying results. Recording finalization snapshots its input and detaches place choices, then resolves current saved places at commit. |
| Timeline and search | Cached entry arrays were traversed to resolve navigation even after an entry could be deleted. Loading a timeline and opening details could also trigger writes. | Navigation caches use UUID lookup with attachment/deletion checks. Detail screens handle unavailable models. Timeline loading and detail presentation no longer reconcile/save as a side effect. Feed grouping runs off the main actor using value snapshots, and reload revisions reject obsolete results. |
| Review drafts | Review entries could reference saved people/places before acceptance. Inverse relationship bookkeeping can bring a draft into a saved graph, and a failed save can invalidate the graph still displayed for review. | Boarding-pass, automation, and timeline-gap reviews use detached related models. Draft location edits and conversions preserve that separation. Confirmation creates a fresh commit graph and resolves saved relationships by UUID. Missing saved choices are not reinserted; historical location values remain. |
| Review editor transitions | People confirmation updated only session IDs, while location/time/photo confirmations rebuilt the session from an entry with no people. Newly created people could also be absent from the view's latest query result. | Confirmed people become detached copies in the draft; selections resolve from the current context. Every editor returns through the same draft reload path. |
| Review link finalization | Accepting an entry linked to a previous entry used chronological link defaults, restoring the previous entry's old place over the reviewed choice. | Finalization explicitly uses the accepted draft's boundary values. A regression creates a saved place during review and verifies the entry and its linked neighbor after acceptance. |
| Nested location editing | Opening linked entries reloaded the whole edit session, discarding unconfirmed location changes. Location selection depended on a deferred SwiftUI change observer. | Nested reloads preserve dirty editor fields and their cancellation baseline. Picker selections update the active session synchronously. |
| Location and import lookup races | Search/current-location tasks could finish after selecting another place or leaving an endpoint. Overlapping airport preparation could mutate newer state. | Revision checks reject superseded/cancelled results. Stopping a picker disconnects its editor callback. Import preparation applies results only for the current preparation revision. |
| Repeated import confirmation | A save could finish before a second confirmation task began; retrying inbox cleanup could then insert another commit graph with the same entry ID. | A successful boarding-pass review remembers its committed state. Later confirmations report success for cleanup without repeating the database write. |
| Codable storage | Existing weather/review-array fixes left optional `Location` composites and several recorded/candidate arrays using automatic SwiftData materialization. | Optional locations in transit, visits, workouts, and automation now use explicit JSON payloads. Candidate arrays, recorded routes/motion, and active recording points use opaque JSON storage as well. |
| Migration | A direct optional `Location` → `Data` rename was tested and **lost location values**, despite opening the migrated store successfully. | A frozen V1 schema migrates to a bridge V2 containing both old locations and new payloads. The custom stage copies and saves values before V3 removes the old composites. Disk migration tests check nil/non-nil values, places, people, arrays, recording points, and subsequent edits. |
| Save failures | Several saves left staged mutations behind or manually restored only part of an edited graph. A later save could commit the remainder. | `JournalPersistence.save` rolls the context back on save failure. Manual partial restoration was removed from the affected editors. Creation services also roll back failures during insertion/reconciliation. |
| Backup restore | Restore saved a deleted/empty graph before inserting replacement records, and relied on creating new models with existing unique IDs. Failure during insertion could leave the original data gone. | Restore updates matching root identities explicitly, resolves relationships into the destination graph, removes unretained records, and commits once. Existing backup validation still runs before mutation. Repeated restores preserve entry/person identity and do not accumulate duplicate detail rows. |
| Deletion | Batch candidate dismissal bypassed ordinary loaded-model deletion. Detail screens and recording logs/callbacks could still access objects after deletion. | Candidate dismissal uses fetched instances and ordinary deletes, then reconciles links. Navigation and detail views reject deleted/detached models. Recording captures its ID before deletion and ignores late tracker callbacks. |
| Recording transitions | Main-actor isolation alone did not prevent reentrant start/stop/resume operations while awaiting tracking, finalization, or Live Activity work. | A transition guard serializes user, intent, and restore transitions. Recording uses the same live context as the application. |
| Saved-place backfill | A sheet retained complete entries in its list of association matches. | Matches contain IDs, dates, locations, and the original association. Applying a selection fetches current entries and rejects stale matches. |
| HealthKit identities | Dictionaries assumed workout/sample keys were unique even when source UUIDs were not a unique entry attribute. | These lookups tolerate historical duplicate source keys. Repeated wake-up snapshots reuse the same selected entry during a sync. |
| Startup | Container initialization used `fatalError`, producing a launch crash when opening or migration failed. | Startup displays the opening error and preserves the store; recording and automation do not start against an unavailable container. There is no automatic empty-store fallback. |

## Coverage map

| Flow | Main files inspected / changed |
| --- | --- |
| Application startup and lifecycle | `ContentView`, `AutomationLifecycle`, `JournalPersistenceServices`, `JournalBackgroundMaintenance` |
| Home feed, day timeline, search, detail routing | `HomeFeedProjectionStore`, `DaySummaryModel`, `PresentationModel`, `EntrySearchModel`, `DayTimelineScreen`, `Navigation`, `HomeFeedCollection`, detail sheets |
| Guided and manual composition | `GuidedEntryComposerModel`, `ManualComposerModel`, `PlaceVisitComposerModel`, `TransitEntryStore`, `PlaceVisitEntryStore` |
| Entry edits and kind conversion | `DetailEditingService`, `EntryDetailSheet`, transit/visit edit and review models, `KindConversionModel`, photo attachments |
| Links and inferred gap entries | `EntryLinkingService`, `TimelineTransitGapService`, `TimelinePlaceVisitGapService`, gap and boundary review sheets |
| Share-sheet journey import | Shared inbox/parser/deep-link code, extension view/model, `BoardingPassImportCoordinator`, `BoardingPassReviewModel`, review sheet, `AirportPlaceStore` |
| Automatic candidates | `AutomationCandidateStore`, `AutomationCandidateEntryService`, review model/sheet, visit and motion detection, existing repair helpers |
| Weather, distance, geography, photos | `WeatherService`, `DistanceService`, `LocationGeographyService`, `PhotoAutoLinkService`, day-weather persistence |
| Places and people | Editors and library/detail sheets, `ContactsService`, `SavedPlacePromotionService`, `JournalDeletionService`, visit statistics |
| HealthKit workouts and wake-ups | Import coordinator/pipeline, `WorkoutImportPersistence`, workout/wake-up stores, matcher and timeline reconciler |
| Recording and intents | Recording coordinator/finalizer, tracking callbacks, Live Activity/intent entry points, recording model |
| Export and restore | `JournalDataArchiveService`, archive document, settings import/export entry points |
| Persisted schema | All nine model types and their relationships; frozen V1/V2 declarations and V3 migration plan |

The share extension transports value data through the inbox; it does not open SwiftData. The SwiftData boundary for that flow is the app's review and confirmation code.

`LogEntry`'s existing opaque weather/photo/review storage remains. `Place.location` is a nonoptional location value; primitive string arrays and scalar enums remain in their existing representation. The change specifically removes optional composite location paths and custom recorded/candidate collection materialization. Cascade ownership of entry details and the people inverse relationship remain unchanged, avoiding an unrelated relationship-schema migration.

## Persistence rules going forward

1. Live app models that the UI edits belong to the main context. Whole-journal fetching, projection, and enrichment belong to the per-container background service actors (see the follow-up section below); those actors never hand models out and communicate in value snapshots and IDs. A new context is still not a background-work strategy by itself — the actor's serialization and the value-snapshot discipline together are.
2. Retain the `ModelContainer` for the entire lifetime of a persistence service. A cached context alone is insufficient. Container-keyed caches must not outlive the container identity they represent.
3. Across an `await`, carry immutable input values and stable IDs. Resolve the current target again and compare relevant input values before applying a result. Actor isolation does not prevent reentrancy during suspension.
4. Reviews stay detached until confirmation. Do not attach saved people/places to a review or insert the visible draft itself into a transaction that can roll back.
5. Save through `JournalPersistence.save`; keep live mutation sequences synchronous and do not leave staged changes over suspension points. The app configures explicit saves instead of autosave.
6. Never treat changing a SwiftData property type or `originalName` as proof of a lossless migration. Preserve the frozen schemas and test a real on-disk upgrade with populated values and relationships.
7. Confirmed review fields belong to the detached draft, not only to an editor session. Nested navigation must preserve unfinished edits, and finalization must honor the confirmed values.
8. Do not read a model's stored properties after deleting/saving it. Capture IDs beforehand, and remove or reject stale presentation references.

These rules align with Apple's [model context lifecycle](https://developer.apple.com/documentation/swiftdata/modelcontext) and [model actor context](https://developer.apple.com/documentation/swiftdata/modelactor/modelcontext) documentation. The isolation review also checked Swift's [async isolation proposal](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md); the project's approachable-concurrency setting means a `nonisolated async` spelling alone is not evidence of a background-executor hop.

## Validation

- Before changes: 401 tests in 37 suites passed, despite the reported device instability.
- Final Debug simulator run: **414 tests in 38 suites passed**, including all additional review, location, and repeated-import regressions.
- The 18 persistence, migration, and weather tests passed with five repetitions each.
- The two reported review sequences failed against the pre-fix binary, including a saved place reverting from latitude 45 to the previous linked location at latitude 44. The 25-test focused editing/audit run then passed.
- New regressions cover disk migration, container lifetime, detached reviews and relationship resolution, stale photo results, deletion during geocoding, stale timeline/search navigation, and repeated identity-preserving restore.
- During implementation, an intermittent test fetch crash exposed the missing strong container reference after replacing model actors. Services now explicitly retain their container, with a lifetime regression test. The repeated run included the previously affected weather/feed path.
- Final Release simulator build: **BUILD SUCCEEDED**, including the standalone picker and repeated-import fixes.

Commands used (the destination is the dedicated audit simulator):

```sh
xcodebuild test -project Journal.xcodeproj -scheme Journal \
  -destination 'platform=iOS Simulator,id=44D67C8D-9264-497F-92D8-5BAC0FB79EF5' \
  -derivedDataPath /tmp/JournalSwiftDataAuditBuild -parallel-testing-enabled NO

xcodebuild test-without-building -project Journal.xcodeproj -scheme Journal \
  -destination 'platform=iOS Simulator,id=44D67C8D-9264-497F-92D8-5BAC0FB79EF5' \
  -derivedDataPath /tmp/JournalSwiftDataAuditBuild -parallel-testing-enabled NO \
  -only-testing:JournalTests/SwiftDataAuditTests \
  -only-testing:JournalTests/EntryWeatherTests \
  -only-testing:JournalTests/PersistenceActorTests -test-iterations 5
```

## Limits and remaining considerations

This is a source audit with simulator regressions, not proof that every reported device crash has the same cause. The migration fixture represents the schema immediately before this change, not every historical app version or an already-corrupted personal store. Existing dangling relationship references may require separate recovery from an actual affected store; the preexisting raw SQLite repair helper was not newly activated.

Fetching and snapshotting live models now runs on the main actor. Feed grouping, photo matching, route/network lookups, and HealthKit acquisition still operate on values away from live model mutation. Large-library fetch/import latency needs device profiling; moving live objects back into independent contexts would reintroduce the ownership problem.

Existing kind-conversion code intentionally retains detached old child details so an active view transition does not read invalidated backing data. This audit preserves that policy. Orphan cleanup would need a separate lifecycle policy that runs only when no UI or pending operation can reference those objects.

The first-import smoke check seeded only a synthetic journey in the dedicated simulator's shared inbox and launched the app's import deep link. The app remained alive, but system HealthKit authorization and URL-opening prompts covered it. Simulator UI controls were unavailable through the enabled computer-use tool, so this does **not** count as end-to-end verification of the share-extension handoff or review presentation. The synthetic inbox file was removed. The automated first-import test covers overlapping airport preparation, library writes, detached draft construction, and concurrent feed loading; the exact reported first-import device crash remains unverified.

Physical-device permission changes, background location delivery, HealthKit delivery while locked, and Live Activity behavior are not exercised by the simulator tests. See the existing recording device test plan for those hardware-specific checks. No debugger reproduction is required to use or review these changes.

## Follow-up: threading correction and home feed lifecycle — September 2026

The first pass of this audit consolidated every persistence service onto the
container's main context. That fixed graph ownership but moved whole-journal
fetching, snapshotting, and enrichment onto the main thread: launch blocked
for seconds, every foreground synchronization and timeline notification
re-ran an O(journal) fetch on the UI thread, and scrolling contended with
MapKit renders. This follow-up keeps the first pass's correctness rules
(value snapshots and IDs across suspension points, re-fetch and revalidate
before applying results, `JournalPersistence.save` rollback, detached review
drafts) and moves the heavy work back off the main thread.

### Threading model

| Work | Where it runs |
| --- | --- |
| Live editing, review confirmation, day timeline (one day window), recording | Main context, main actor |
| Home feed projection, search index source | `HomeFeedProjectionStore` actor |
| Detection, candidate sync, photo linking, weather/distance/geography backfill, contact sync, single-entry post-creation enrichment | `JournalBackgroundMaintenance` actor |
| HealthKit workout/wake-up import | `WorkoutImportPersistence` actor |

The service actors conform to `ModelActor` manually and supply their own
serial `DispatchSerialQueue` as the actor executor. This is deliberate:
measured on the current SDK, `DefaultSerialModelExecutor` provides mutual
exclusion but no thread of its own — a `@ModelActor` job awaited from the
main actor executes **on the main thread** (verified by a regression test
that asserts the executor thread from both a main-actor and a detached
caller). Detached construction, the previous workaround, no longer changes
this. With the queue executors, no service call runs on the main thread
regardless of the caller.

Enrichment helpers (`EntryWeatherService`, `TransitDistanceService`,
`LocationGeographyService`, `PhotoAutoLinkService`, `ContactPersonSyncService`,
visit geocoding, and the entry stores) are `nonisolated` and run on whichever
executor owns the context they are handed: the maintenance actor for
backfill, the main actor for a user-visible single-entry operation. The
`nonisolated(nonsending)` default means these calls never silently hop
executors, so a `ModelContext` parameter always stays with its owner.
Cross-context visibility relies on refetches: background saves post
`TimelineDataChange`, and every UI surface reloads from the store instead of
assuming a live object updated in place.

### Home feed loading and lifecycle

- **Reload serialization.** `HomeFeedModel.reload` previously let a newer
  concurrent reload discard an older pass's result. At launch, the scene
  activation reload superseded the launch task's reload, so the launch task
  positioned an empty feed: the empty state flashed and the feed no longer
  started at the bottom. Reloads are now queued (with coalescing: a call
  made while a pass is queued joins that pass), so every awaited `reload`
  returns only after a projection at least as new as the call has been
  applied.
- **Nothing loads on the main actor during scrolling.** Cells configure with
  `loadsDeferredContent: false` while the collection view scrolls: cached
  snapshots (memory or disk, decoded off-main) still appear, but MapKit
  renders — which require main-thread `MKMapView` time — are deferred, as is
  prefetch rendering and browsing-window prewarming. When scrolling settles,
  visible cells are reconfigured, enrichment is rescheduled, and deferred
  renders retry.
- **Cells observe their row models.** Weather and route enrichment land on
  `DaySummaryRowModel`/`PeriodSummaryRowModel` whenever their background
  work finishes. UIKit cells use `withObservationTracking` to reconfigure
  immediately, so a loaded weather tile or enriched map no longer waits for
  the cell to scroll off-screen and back.
- **Map images never blank while content is replaced.** A map image view
  clears its image only when its *slot* (day/period) changes. Enrichment of
  the same slot keeps the previous image until the replacement is decoded. A
  load pass that could not render (deferred during scroll) leaves no state
  behind that would block a later retry.
- **Snapshot disk cache retains recent content revisions.** A slot's cache
  previously kept exactly one content revision per appearance; days and
  periods alternate between endpoint-only and exact-route projections, so
  the two revisions deleted each other's files on every write and forced a
  fresh `MKMapView` render (with network tile loads) on every pass — the
  “cached but takes forever / blank map” symptom. The store now keeps the
  three most recent superseded revisions per slot; the global 200 MB LRU
  trim is unchanged. Pruning one appearance's files still never touches the
  other appearance.
- **Search reuses the projection.** `EntrySearchModel` built its index by
  fetching and snapshotting every entry on the main thread each time the
  search screen appeared or a timeline change posted. It now consumes
  `HomeFeedProjectionStore.load()` value snapshots and resolves a live model
  by ID only when navigating to a result.
- **Snapshots load at final geometry and resolved appearance.** A map tile
  starts loading from `layoutSubviews`/`didMoveToWindow`, never from a
  configure pass: a reused cell still carries the previous layout's tile
  frames (the decoded image would aspect-fill a differently sized tile,
  visibly zoomed), and a detached cell resolves `userInterfaceStyle` to
  light, queueing wrong-appearance renders that starve the single MapKit
  render slot — the dark-mode hybrid tiles that never appeared. In-flight
  loads restart when layout changes the tile size, and a decoded image is
  dropped (and re-requested) if the tile was re-laid-out while it decoded.
- **Hybrid renders only cache finished imagery.** The hybrid `MKMapView`
  session used to capture whatever was on screen three seconds in, which
  could persist a globe whose imagery had not loaded — a permanently blank
  cached tile. Capture now requires MapKit's finished-loading or
  fully-rendered signal, waits up to twenty seconds for it, and fails (and
  retries later) instead of caching a premature capture. The cache directory
  advanced to v5 to retire tiles poisoned by the old behavior.
- **Bottom-pinned viewports restore to the current bottom.** The zoom
  transition records how far each captured scene was from its bottommost
  offset; restoring a bottom-pinned scene re-pins to the current bottom
  instead of clamping a stale offset (inset/content differences drifted the
  feed upward). Scroll-to-latest targets the maximum content offset —
  `scrollToItem(.bottom)` ignores the section inset below the last row — and
  a no-op animated scroll completes its request directly because UIKit sends
  no end-of-animation callback.

Flows intentionally left on the main context: the day timeline
(`HomePresentationModel`, bounded to one day's window and required to hand
live models to editors), detail sheets and editors, review confirmation,
recording, and archive export/restore (modal, whole-graph, identity
preserving by design). Archive export of a very large journal on the main
thread during an explicit settings action is a known, acceptable cost; move
it behind a progress UI before changing its threading.

### Validation (follow-up)

- Debug simulator: **414 tests in 38 suites passed**; the persistence,
  audit, weather, and snapshot-cache suites passed with five repetitions.
- New/updated regressions: service executors must not run on the main
  thread (asserted from main-actor and detached callers); snapshot cache
  retains alternating content revisions without re-rendering and prunes
  the oldest beyond the window; pruning one appearance preserves the other.
- Release simulator build succeeded.
- Launch smoke test on the audit simulator: app reaches the positioned feed
  and starts its deferred background services (HealthKit prompt appears),
  no crash.
- Scroll-hitch and map-latency behavior needs on-device Instruments
  confirmation with a real journal; the simulator has no representative
  data set.
