# scripts

`scripts/check` runs every gate CI runs: it resolves the workspace
(`flutter pub get`; with `CI` set, `--enforce-lockfile`), then runs
`bin/check.dart`:

1. **Workspace lints** (`lib/src/*_lint.dart`), reported with the legacy
   baseline applied.
2. For each member, dependencies first: `dart analyze --fatal-infos` over its
   layout directories, its tests (`flutter test` if it needs the Flutter SDK,
   `dart test` otherwise), then its `tool/check` hook if present.

Every step runs even after a failure; the exit code is 1 if any failed, 2 if
the repository is not a workspace the gates understand (including a package
under `packages/` or `example/` missing from the root `workspace:` list).

## Lints

| Lint | Fails when |
| --- | --- |
| `DependencyLint` | members form a cycle; `content_model` / `chrome_foundation` depend on a member; `panel_shell` / `panel_pages` / `panel_presentation` reach `emoji_catalog_pack` or an adapter package; `panel_catalog` reaches `chrome_foundation`; any member but `kv_shared_preferences` declares `shared_preferences` (or a `shared_preferences_*` package) |
| `ReexportLint` | a `lib/` file exports another workspace package |
| `FakesLint` | production code under `lib/` exports or imports a fake source |
| `PureDartLint` | `content_model` declares a Flutter SDK dependency, or a file under its `lib/` imports or exports `package:flutter*` or `dart:ui` |

Conventions the lints read:

- **Fake source**: `lib/testing.dart`, any file under a `testing/` or `fakes/`
  directory, or a file named `fake_*.dart` / `*_fake.dart`. Fake sources are
  testing code: they may import other packages' `testing.dart`. Only
  `lib/testing.dart` exports fakes.
- **Adapter package** (codec, decoder, fetcher): a `_`-delimited word of the
  package name is `codec`, `decoder` or `fetcher` (or the plural).
- **`tool/check`**: an executable in a member, run from the member directory
  after its tests; non-zero exit fails the gate.

## Legacy baseline

`LegacyBaseline.current` lists known violations of the current tree. It only
shrinks: a new violation fails, and an entry that matches nothing fails as
stale. The change that removes the offending code deletes its entry.

## Adding a lint

Add a `LintRule` (with its explanation), a lint class returning `Violation`s,
its unit test against a deliberate violation, and list it in `bin/check.dart`.
