# ADR 035: The markdown engine is a fork we own

The chat markdown engine is `flutter_md` from `itsezlife/md`, a fork that no
longer merges from the upstream it came from. Hosts consume it by git ref. The
fork owns the grammar `RichTextMarkdown` writes, the inline layer (embeds,
mentions, spoilers) and the default copy formatter.

**Status**: Accepted  
**Date**: 2026-10-18  
**Relates to**: [ADR 013](013-viewport-owns-markdown-text-selection.md), [ADR 017](017-body-linkify-host-invoked.md), [ADR 029](029-host-integration.md), [ADR 034](034-rich-text-wire-and-persistence.md), [ADR 037](037-spoiler-and-mention-inline-styles.md)

## Context

The workspace's bodies render through a markdown library whose selection,
fenced-code chrome, pannable blocks and inline layer exist nowhere upstream and
are not designs upstream would take: they are chat-viewport engine work with
chat-specific invariants (a glyph picture recorded once, selection in
rendered-text offsets, hit rules owned by the viewport). Merging upstream
changes into that code is a recurring conflict cost with no matching benefit.

## Decided

| Concern | Decision |
| ------- | -------- |
| Ownership | `itsezlife/md` is the chat markdown engine. Its `master` holds everything the workspace consumes. The package name `flutter_md` is kept so imports do not change. |
| Upstream | No merges from the original repository. A wanted upstream commit is cherry-picked by hand. |
| Consumption | By git ref (a release tag, so the lockfile is reproducible) from every consuming repo. The fork is not published to a package registry. |
| Override | The workspace root may use a path dependency override for local fork work (`dependency_overrides` only takes effect at the workspace root); no other package and no consuming repo carries one. Its comment says it is for local work against the pinned ref. |
| Dependencies | The fork depends on neither `catalog_assets` nor `content_model`. Its embed contract is its own ([ADR 029](029-host-integration.md)); the viewport's root package adapts. |
| Grammar | The fork owns the grammar `RichTextMarkdown` writes. A conformance suite in the fork, written over markdown strings in the codec's dialect, pins how every spelling the codec emits parses; `content_model` keeps its own round-trip tests. |
| Copy | The fork's default copy formatter writes the dialect back (`MarkdownSourceFormatter`, inline-aware, self-round-trip tested); the text-only formatter stays as `MarkdownSelectionFormatter.plain`. The chat viewport keeps reading spans into `RichText` for its own copy. |
| Releases | A change to the inline layer is a release of the fork both repos can pin; consuming repos move their ref deliberately. |

## Rejected

| Alternative | Why not |
| ----------- | ------- |
| Continuing to merge from the original repository | The forked areas conflict on every merge; the original takes none of this engine work |
| Publishing the fork under a new name | Every import and the consuming repos' pins change for no benefit |
| Folding the engine into this workspace | Other repos consume it; a workspace member cannot be pinned by git ref from outside without the whole workspace |
| The fork depending on `content_model` for the conformance test | The fork would take a workspace dependency; the suite over markdown strings needs none |

## Consequences

- Security and bug fixes upstream are not received; someone reads upstream for
  them if it matters.
- A change to the dialect needs a fork release, a pin move in each consuming
  repo and a `RichTextMarkdown` change together; the conformance suite is the
  alarm when they drift.
