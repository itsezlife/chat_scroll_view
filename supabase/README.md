# Supabase demo backend

Copy this `supabase/` folder into any Supabase project.

## Local development

```bash
supabase start
supabase db reset          # migrations + seed (≥10k messages)
supabase functions serve --env-file supabase/.env.local
```

From repo root, `./scripts/dev.sh` runs the above and writes `config/development.supabase.json`.

```bash
flutter run --dart-define-from-file=config/development.supabase.json
```

## Deploy to hosted Supabase

1. `supabase link --project-ref <ref>`
2. `supabase db push`
3. Apply seed SQL on the target database (or run generator + push seeds)
4. `supabase functions deploy load_chats load_chat load_messages send_message get_read_state update_read_state`
5. Seed order: `seed.sql` (disables last-message trigger) → `demo_messages.sql` → `chat_last_message_backfill.sql` (backfill + re-enable trigger)
6. Enable Realtime for `public.messages` if not already published

## Keys

| Key | Use |
|-----|-----|
| **anon** | Flutter app (`SUPABASE_ANON_KEY`) |
| **service_role** | Migrations, seed scripts, CI only — never ship in the app |

## Security (v1)

Anon RLS is permissive for `chat_id = 1` demo only. Tighten policies or enable Supabase Auth before production.

## Message ids

Legacy `assets/comments/` ids are **0-based**; Postgres stores **protocol ids** `legacy_id + 1` (oldest = 1).
