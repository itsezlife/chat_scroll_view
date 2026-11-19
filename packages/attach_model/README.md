# attach_model

The **attach model** every picker front-end shares: what an attach item is,
the ordered **attach selection** with its cap and gates, the host's **attach
limits**, the **send options** and their store, the **send plan** that cuts
a selection into planned sends, and the per-platform **attach policy**.
Pure Dart: it depends on `content_model` (the caption is its `RichText`, the
store a `KeyValueStore` client), `listen` and `meta`, and on no Flutter,
platform code or media package.

Decisions: [ADR 046](../../docs/adr/046-media-picker.md).

## Types

| Type | Role |
| --- | --- |
| `AttachItem` | One thing picked to send: `id`, `source`, `kind`, `facts`, and per-item state (`spoiler`, `timer`, `caption`, `edits`, `derived`). `effectiveDimensions` / `effectiveDuration` / `isMuted` / `isAnimated` read the derived output when there is one. |
| `AttachSource` | Sealed, by plain values: `library(assetId)`, `file(path)`, `blob(handle)`, `captured(localKey)`, `pasted(localKey)`. |
| `AttachKind` | `photo`, `video`, `animation`, `audio`, `file`; classification is the intake's. |
| `AttachFacts`, `AttachDimensions`, `AttachTimer` | Byte size, pixel size, duration, MIME, name, modified time; a timer that is `once` or `after(duration)`. |
| `ItemEdits`, `DerivedOutput` | The **edited item** slot: an editor's opaque, versioned recipe and its rendered output. Nothing writes them yet. |
| `AttachLimits` | Injected per open: allowed kinds, single select, caption length, file size limit, timer / schedule / grouping / spoiler / send-as-file allowed. |
| `AttachSelection` | Ordered by selection: `toggle`, `toggleRange` (every item takes the state the first one takes), `remove`, `reorder`, `update`, `orderOf` (1-based, re-indexed), `snapshot` / `restore`, `changes`. A refused toggle returns `AttachToggle.refused(AttachRefusal)` and changes nothing. |
| `SendOptions`, `SendSchedule`, `SendRequest` | Grouped, as files, high quality, silent, schedule (`at` or `whenOnline`), caption above, video preset; a request is the ordered items, the caption (`RichText`) and the options. |
| `planSend`, `SendPlan`, `PlannedSend`, `SendForm` | `planSend(request, policy, limits)` is pure: a `SendPlan$Ready` of `single(item, caption?)`, `group(items, captionIndex?)` and `text(caption)` sends, or a `SendPlan$Rejected` (`empty`, `captionTooLong`, `timerWithSchedule`, `scheduleNotAllowed`). |
| `SendOptionVisibility` | Which options a menu or box shows for a selection: send as file, without grouping, high quality, caption above, spoiler, and the confirm box's group / as-documents / remember checkboxes. |
| `SendOptionStore` | Remembers options between opens over a `KeyValueStore` (namespace `attach_model`), per the policy's `SendOptionPersistence`. |
| `AttachPolicy` (`$Android`, `$IOS`, `$Desktop`, `$Web`) | The rules per platform family; `forPlatform(AttachHostPlatform, isWeb:)` picks one. Not sealed: extend a stock family to change one rule. |

`testing.dart`: `AttachItems` (an item per kind for tests) and
`AttachPolicyContract` (the suite every policy passes).

## Host contract

| Step | What the host does |
| --- | --- |
| Limits | Builds `AttachLimits` from its rights for every open; the picker never looks them up. |
| Policy | `AttachPolicy.forPlatform(platform, isWeb: kIsWeb)`, or a family it extends. |
| Send | Calls `planSend` with the selection's items, the caption and the options; maps each planned send to a message (ids, reply, upload) and prepares media per the plan's options. The plan never names a message type. |
| Options | Restores `SendOptions` through a `SendOptionStore` on open and saves them after a send (`remember:` from the box's checkbox). |
| Selection | One `AttachSelection(policy:, limits:)` per open; every source of the open (library, camera, files, paste) toggles into it. |
| Refusals | Turns `AttachToggle.refused(reason)` into its feedback (a bulletin, a haptic). |

## Rules and values

| Rule | Android | iOS | Desktop | Web |
| --- | --- | --- | --- | --- |
| Selection cap | 100 | 100 | none | none |
| Single select | cap 1, a toggle replaces | same | same | same |
| Send group | at most 10; photos and videos together, files with files, audio with audio; as files, media groups as files; a change of form starts a group | same | same | same |
| Never grouped | an item with a timer; an animation sent as media | same | same | same |
| Ungroups the batch | nothing | a timer, an animation, a muted video | a timer | an animation |
| Spoiler | a per-item flag inside a group | same | same | same |
| Caption | first send | first if grouped, else last | first of the last group when it is media, else the last item | first send; a text send ahead of two or more sends |
| As files | timers cleared | same | same | same |
| Timer with schedule | rejected | same | same | same |
| Send as file offered | with media | with media, no spoiler | with media | with media |
| High quality offered | every item an unedited photo | same | a photo over 1280 | never |
| Remembered options | high quality; video preset per offered count | high quality; one video preset | grouped, as files, high quality, only with Remember | nothing |
