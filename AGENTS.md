## Agent skills

### Issue tracker

Issues live in this repo's GitHub Issues and are operated via the `gh` CLI. See `docs/agents/issue-tracker.md`.

Split specs use a **seam branch** (not per-ticket PRs to `master`). Current: [#22](https://github.com/itsezlife/chat_scroll_view/issues/22) → `22-message-span-selection`; child PRs target that branch. See **Seam branches** in the issue-tracker doc.

### Triage labels

Canonical roles map 1:1 to tracker labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: glossary in `CONTEXT.md`, policy in `docs/adr/`, runtime constitution in `docs/architecture/`. See `docs/agents/domain.md`.
