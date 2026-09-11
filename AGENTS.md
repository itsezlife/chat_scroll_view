## Agent skills

### Issue tracker

Issues live as markdown under `.scratch/<feature>/` (spec + numbered issue
files). See `docs/agents/issue-tracker.md`.

### Triage labels

Canonical roles map 1:1 to tracker status strings: `needs-triage`,
`needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See
`docs/agents/triage-labels.md`.

### Domain docs

Glossary in `CONTEXT.md`, policy in `docs/adr/`, runtime constitution in
`docs/architecture/`. See `docs/agents/domain.md`.

### Portable surface

**Portable** packages, public APIs, and shipped docs: any foreign host may
import them alone — name by **glossary** / **roles**, document **contracts**.
See `docs/agents/portable-surface.md` and `docs/agents/agnostic-documentation.md`.
