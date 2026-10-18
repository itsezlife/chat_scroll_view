# scripts

`scripts/check` runs every gate CI runs: it resolves the workspace
(`flutter pub get`; with `CI` set, `--enforce-lockfile`), then runs
`bin/check.dart`:

1. **Workspace lints** (`lib/src/*_lint.dart`), reported with the legacy
   baseline applied.
2. For each member: `dart analyze --fatal-infos` over its layout
   directories, its tests through `test/unit_test.dart` (`flutter test` if it
   needs the Flutter SDK, `dart test` otherwise), then its `tool/check` hook
   if present. Members run side by side, up to one per processor (at most 8;
   `scripts/check --jobs N` sets it), the largest suites first; each step's
   output is printed whole, in dependency order, with its time.

Every step runs even after a failure; the exit code is 1 if any failed, 2 if
the repository is not a workspace the gates understand (including a package
under `packages/` or `example/` missing from the root `workspace:` list).

`scripts/bench` is not a gate and not part of `scripts/check`: it runs the
headless benchmarks and sets their ratios against the committed baselines. The
nightly workflow calls it; usage, tolerance and re-baselining are in
[benchmarks/README.md](../benchmarks/README.md).

## Chore: raising the Flutter SDK

The SDK is pinned exactly in `.fvmrc`, the root `pubspec.yaml` (`environment:
flutter:`), `packages/composer_editable/pubspec.yaml` and the `flutter-version:`
of `check.yml`, `platform-builds.yml` and `benchmarks.yml`; `flutter pub get`
under any other Flutter fails. `composer_editable` is a patch series over
copies of that SDK's text input files, so an upgrade is one command:

```shell
dart packages/composer_editable/tool/revendor.dart --sdk=<new flutter root>
```

It raises every pin together, re-vendors the package by a three-way merge and
regenerates `DIVERGENCES.md`; run it on a branch and resolve the conflicts it
reports. A test of the package fails when the pins disagree. How it works:
[composer_editable README](../packages/composer_editable/README.md#flutter-pin-and-re-vendor).

`sdk-lookahead.yml` rehearses that command every Monday against the newest
stable Flutter and writes the conflicts and the suite result to the job
summary. It is not a gate: conflicts do not turn it red; only a run that cannot
start does.

## Lints

| Lint | Fails when |
| --- | --- |
| `DependencyLint` | members form a cycle; `content_model` / `chrome_foundation` / `composer_editable` depend on a member; any member but `chat_composer` depends on `composer_editable`; `panel_shell` / `panel_pages` / `panel_presentation` reach `emoji_catalog_pack` or an adapter package; `panel_catalog` reaches `chrome_foundation`; any member but `kv_shared_preferences` declares `shared_preferences` (or a `shared_preferences_*` package); any member outside `example/` depends on `rich_clipboard` |
| `ReexportLint` | a `lib/` file exports another workspace package |
| `FakesLint` | production code under `lib/` exports or imports a fake source |
| `TestEntrypointLint` | a member with test files has no `test/unit_test.dart`, or it does not import one of them |
| `PureDartLint` | `content_model`, `emoji_data` or `emoji_catalog_pack` declares a Flutter SDK dependency, or a file under its `lib/` imports or exports `package:flutter*` or `dart:ui` |

Conventions the lints read:

- **Fake source**: `lib/testing.dart`, any file under a `testing/` or `fakes/`
  directory, or a file named `fake_*.dart` / `*_fake.dart`. Fake sources are
  testing code: they may import other packages' `testing.dart`. Only
  `lib/testing.dart` exports fakes.
- **Adapter package** (codec, decoder, fetcher): a `_`-delimited word of the
  package name is `codec`, `decoder` or `fetcher` (or the plural).
- **`tool/check`**: an executable in a member, run from the member directory
  after its tests; non-zero exit fails the gate.
- **`test/unit_test.dart`**: the member's one test entrypoint. It imports every
  `*_test.dart` under `test/` and calls each `main` in a `group` of its own
  (named by the file's path), so a file's `setUp` / `tearDown` stay with its
  tests. One compile and one process run the whole suite, where `flutter
  test` on the directory starts both per file. The files share the process: a
  test that changes global state (`FlutterError.onError`, a static cache, a
  process-wide handler) restores it, and a golden test points
  `goldenFileComparator` at its own file, since goldens otherwise resolve
  next to the entrypoint.

## Legacy baseline

`LegacyBaseline.current` lists known violations of the current tree. It only
shrinks: a new violation fails, and an entry that matches nothing fails as
stale. The change that removes the offending code deletes its entry.

## Adding a lint

Add a `LintRule` (with its explanation), a lint class returning `Violation`s,
its unit test against a deliberate violation, and list it in `bin/check.dart`.
