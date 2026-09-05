# UIKit home feed zoom

The days/months/years switch uses a temporary overlay inside the existing
`HomeFeedViewController` collection view, above its cells and within its native
scroll-edge effects. It is inserted immediately above the highest visible cell,
below UIKit's edge-effect views, rather than brought to the front of the scroll
view. It does not replace the reusable cells,
manual layouts, map/photo caches, or collection-view prefetching. The older
SwiftUI feed does not implement this animation.

## Animation and interruption

Apple's [UIViewPropertyAnimator](https://developer.apple.com/documentation/uikit/uiviewpropertyanimator)
can pause, reverse, scrub and change timing. It is suitable for a fixed pair of
endpoints. This transition additionally needs a third destination and independent
velocities for several moving rectangles, so it uses a small stateful coordinator
instead of assembling or restarting nested property animators.

The coordinator uses Apple's
[Spring.update(value:velocity:target:deltaTime:)](https://developer.apple.com/documentation/swiftui/spring/update(value:velocity:target:deltatime:))
solver with a critically damped spring. SwiftUI supplies the math; all rendered
views are UIKit snapshots. New targets change only the target values of position,
size, scale and opacity springs. Current positions and velocities survive rapid
reversals and days → months → years retargeting. Requests do not wait for earlier
animations to finish.

A [CADisplayLink](https://developer.apple.com/documentation/quartzcore/cadisplaylink/targettimestamp)
advances these values using elapsed time, not an assumed frame count. Its preferred
range follows the screen's refresh rate. The app enables high refresh rates on
supported iPhones. There is no display link at rest, and no cell layout, asset
loading, snapshot capture or matching in the per-frame callback.

Incoming content approaches its native scale while fading in. Both backgrounds
shrink when zooming out and grow when zooming in, using one continuous depth
coordinate. Each level changes scale by a factor of about 1.32, giving a stronger
perception of depth without resetting transforms on reversal. Source-over opacity
is normalized to avoid a dim flash between opaque viewport images.

## Matching and resources

Each UIKit canvas exposes descriptors for its existing tiles only when changing
scale. Maps can match other map roles across overlapping dates; photos and people
require shared content IDs. Movement, sleep, activity and other comparable period
tiles match within their own family. The matcher is deterministic, one-to-one and
limited to **five** actors. It prioritizes distinct visible card owners and then
content variety/identity before geometric proximity.

Period matching uses the visible anchor month/year card. Day matching considers
all visible cards. Only whole tiles inside the unobscured viewport are eligible,
with additional clearance from the soft toolbar edges. Partly obscured tiles stay
on their background surface instead of being split into moving fragments. Multiple period maps can consequently travel to
maps on several days.

The coordinator captures at most three viewport bitmaps during one uninterrupted
session at the screen's native display scale. Moving tiles are rendered separately
from their original views at twice the display scale (6x on a 3x screen), capped
at 2048 pixels on the longest edge. Candidate images are released immediately
after matching; only the five selected actors retain their high-resolution images.
These images become flying views;
their original rectangles are covered with the surface background color. These
slots stay opaque. Moving snapshots carry separate corner masks in points, so
resizing the bitmap does not stretch its radii. Photo grids retain each image's
original clipping and gaps; their live day/period styling is unchanged. Third-level
retargeting extends existing actors instead of allocating another set. All images,
covers and actors are released on completion or cancellation.

The live collection reloads and positions the destination underneath the overlay.
Before a new destination snapshot is taken, all visible maps and avatars resolve
already cached images. This is a cache-only pass, with no wait for a new map render
or contact fetch. Existing motion continues while this preparation runs, and a
new button request cancels obsolete preparation. Returning to an existing scene
reuses its snapshot immediately.

Capture renders visible cell layers directly, including UIImageView map and
avatar contents that have not reached a render-server commit yet. This avoids
freezing placeholder/monogram states and avoids capturing the collection view's
scroll-edge blur/mask surface into a bitmap. The overlay itself remains inside
the collection view, pinned to its viewport as reloads change the content offset.
UIKit therefore continues applying its live progressive toolbar blur to the
animated content.
Reload completions carry a generation number so stale work cannot start a previous
transition. Reversing to an existing scene restores its exact content offset,
including the partly visible first card. Parent anchor inference retains a known
day/month inside the selected period; explicit card navigation still takes priority.

Dragging gives control back to the live collection immediately and removes the
snapshot overlay. Timeline/card activation is suppressed while snapshots are
moving, so a tap cannot open a different underlying card. Resize, disappearance
and Reduce Motion changes cancel stale geometry. Reduce Motion uses only a fade,
with no flying tiles or scale changes. A removed destination row falls back to the
available feed instead of leaving preparation stuck.

## Validation

`HomeFeedZoomTests` covers identity/date matching, distribution across day cards,
the five-actor cap, whole-tile eligibility, cached-map readiness, image pixels in
source snapshots, native-resolution backgrounds, supersampled moving tiles,
native toolbar blur hosting and before/during pixel comparison, refresh-rate independence, momentum preservation,
30 rapid retargets, overlay cleanup, and real collection-view reload/scroll-offset
restoration. The integration test attaches a rendered mid-transition image.

Launch a Debug build with **`-home-zoom-gallery`** to inspect temporary sample
content through the real UIKit feed. It does not insert journal records. Check
all six directed switches, rapid two- and three-button sequences, partial-card
scroll positions, scrolling during a transition, and Reduce Motion.

Simulator validation does not establish an on-device frame-time guarantee. Check
cold maps/photos and rapid switching on a physical ProMotion device with Instruments
before tuning the spring duration, texture scale or five-tile budget further.
