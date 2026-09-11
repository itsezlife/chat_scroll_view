# Agnostic documentation

Comments, dartdoc, CONTEXT glossaries, package README/API notes, and **OKF
guides** describe **what the pattern or API is** — not how we got here, which
screen uses it in one product, or what bug we fixed.

Treat OKF and package docs like portable knowledge: another team should drop
the guide into a different app and still understand it.

Companion: [portable-surface.md](portable-surface.md) (portable default +
naming).

## Write for the next reader

- Prefer **stable contracts**: purpose, invariants, inputs/outputs, failure
  modes, when to use vs related APIs.
- Prefer **layer-appropriate language**:
  - packages / OKF → generic roles (host, scope, shell, registry, policy)
  - this-app feature notes → may name local composition only when necessary
- Keep docs **short and useful**. Delete narration that does not help apply
  the pattern correctly.

## Ephemeral vs contract

Write contracts. Leave these out of shipped docs / OKF unless the user
explicitly asks for them:

| Smell | Instead |
| ----- | ------- |
| Conversation / PR story | State the invariant or current contract |
| Call-site / screen inventory (route names, host id literals) | Describe the **role** ("scoped page host", "form shell") |
| Product or org leakage in package or OKF | Portable terms; product wiring in a thin app-only note if needed |
| Implementation archaeology (deleted APIs, failed experiments, dates) | Document **current** behavior only |

### Code / API examples

```dart
// ❌ BAD — chat history + product screen
/// Added after the profile boost banner stole horizontal dismiss on
/// EditHeaderView when the form became scrollable.

// ✅ GOOD — stable contract
/// Presents content above the host child so ancestor drag recognizers
/// do not receive those pointers.


// ❌ BAD — package API names the app shell
/// Mount this under AppScaffold so login and register share one messenger.

// ✅ GOOD — package API stays reusable
/// Mount above the subtree that calls [show]. Optional [id] registers
/// with the messenger service (last mount wins).
```

## When explicit coupling is OK

- The type **is** the coupling (a scaffold widget may document which hosts it
  mounts).
- A **required** integration contract (must wrap X, must register id Y) —
  phrase as a contract, not a screen list.
- A **separate, clearly app-local** note (feature `CONTEXT.md` / scratch
  spec) that maps this product’s routes — not the portable package or OKF
  guide itself.

## Done when

1. Would this still read cleanly with no chat history?
2. Could another app adopt this package/OKF guide without renaming half the
   prose?
3. Did I document a footgun that still exists, or a story / call-site list
   that is already over?
