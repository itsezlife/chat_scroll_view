-- Demo chat protocol schema (Postgres storage for JSON HTTP Edge Functions).
-- Maps protocol types to relational tables; timestamps stored as timestamptz,
-- serialized as Unix seconds in JSON responses.

-- users — profile row for UserEntry JSON (id, flags, profile fields, timestamps).
create table if not exists public.users (
  -- Internal sequential user id; JSON field: id (number).
  id int4 primary key,
  -- UserFlags bitfield (int2 / u16). Combinable with OR; bits 3–15 reserved (0x0008–0x8000).
  --   bit 0  0x0001 SYSTEM  — server-generated account
  --   bit 1  0x0002 BOT     — server sets MessageFlags.BOT on outbound messages
  --   bit 2  0x0004 PREMIUM — premium badge in clients
  -- Demo seeds: 0 (no flags). JSON field: flags (number).
  flags int2 not null default 0,
  -- Account creation time; JSON field: created_at (Unix seconds).
  created_at timestamptz not null default now(),
  -- Last profile update; JSON field: updated_at (Unix seconds).
  updated_at timestamptz not null default now(),
  -- Public handle; JSON field: username (string or null).
  username text,
  -- Display first name; JSON field: first_name (string or null).
  first_name text,
  -- Display last name; JSON field: last_name (string or null).
  last_name text,
  -- Avatar URL; JSON field: avatar_url (string or null).
  avatar_url text
);

-- chats — conversation metadata for ChatEntry JSON (last_message from chat_last_message).
create table if not exists public.chats (
  -- Globally unique chat id; JSON field: id (number).
  id int4 primary key,
  -- ChatKind discrete enum (int2) — single value, NOT a bitfield. JSON: kind (number).
  --   0 Direct  — two participants; title null
  --   1 Group   — multi-member; demo chat id 1
  --   2 Channel — broadcast; parent_id references group
  -- Values 3+ invalid until protocol extended.
  kind int2 not null default 1,
  -- Parent group id for channels; JSON field: parent_id (number or null).
  parent_id int4,
  -- Creation time; JSON field: created_at (Unix seconds).
  created_at timestamptz not null default now(),
  -- Last metadata change; JSON field: updated_at (Unix seconds); bumped on tail insert.
  updated_at timestamptz not null default now(),
  -- Display title; JSON field: title (string or null); null for direct chats.
  title text,
  -- Avatar URL; JSON field: avatar_url (string or null).
  avatar_url text,
  -- Member count; JSON field: member_count (number).
  member_count int4 not null default 1
);

-- messages — persisted Message rows; composite PK (chat_id, id) per conversation.
create table if not exists public.messages (
  -- Conversation id; JSON field: chat_id (number).
  chat_id int4 not null references public.chats (id) on delete cascade,
  -- Sequential message id within chat (starts at 1); JSON field: id (number).
  id int4 not null,
  -- Sender user id; JSON field: sender_id (number).
  sender_id int4 not null references public.users (id),
  -- Send time; JSON field: created_at (Unix seconds).
  created_at timestamptz not null,
  -- Last edit time; JSON field: updated_at (Unix seconds).
  updated_at timestamptz not null,
  -- MessageKind discrete enum (int2). JSON: kind (number).
  --   0 Text   — plain text; send_message inserts 0
  --   1 Image  — image attachment (rich_content / extra hold payload)
  --   2 File   — file attachment
  --   3 System — system event; SHOULD also set flags bit 0x0020 (SYSTEM)
  -- Values 4+ invalid.
  kind int2 not null default 0,
  -- MessageFlags bitfield (int2 / u16). Combinable OR. JSON: flags (number).
  --   bit 0  0x0001 EDITED    — show "edited" in UI
  --   bit 1  0x0002 DELETED   — tombstone; JSON content ""; preview cleared
  --   bit 2  0x0004 FORWARDED — origin in extra JSON
  --   bit 3  0x0008 PINNED
  --   bit 4  0x0010 SILENT    — no push
  --   bit 5  0x0020 SYSTEM    — pair with kind=3
  --   bit 6  0x0040 BOT
  --   bit 7  0x0080 REPLY     — reply_to_id required
  --   bits 8–15 0x0100–0x8000 reserved (MUST be 0 on write)
  -- Demo: 0. Trigger tests DELETED with (flags & 2) != 0.
  flags int2 not null default 0,
  -- Reply target message id; JSON field: reply_to_id (number or null).
  reply_to_id int4,
  -- Plain text body; JSON field: content (string); empty when DELETED flag set.
  content text not null default '',
  -- Rich spans JSON; JSON field: rich_content (array or null).
  rich_content jsonb,
  -- Extra metadata JSON; JSON field: extra (object or null).
  extra jsonb,
  primary key (chat_id, id)
);

create index if not exists messages_chat_id_id_idx
  on public.messages (chat_id, id);

-- chat_read_state — per-user read cursor for open-anchor resolution (get/update_read_state).
create table if not exists public.chat_read_state (
  -- Conversation id; JSON field: chat_id (number).
  chat_id int4 not null references public.chats (id) on delete cascade,
  -- Reader user id; JSON field: user_id (number).
  user_id int4 not null references public.users (id) on delete cascade,
  -- Highest message id read; JSON field: last_read_message_id (number or null = first join).
  last_read_message_id int4,
  -- Last update; JSON field: updated_at (Unix seconds).
  updated_at timestamptz not null default now(),
  primary key (chat_id, user_id)
);

create index if not exists chat_read_state_lookup_idx
  on public.chat_read_state (chat_id, user_id);

-- sync_chat_read_state_on_message_delete — retreat cursor when read message row is removed.
create or replace function public.sync_chat_read_state_on_message_delete()
returns trigger
language plpgsql
as $$
declare
  prev_id int4;
begin
  select max(m.id) into prev_id
  from public.messages m
  where m.chat_id = old.chat_id
    and m.id < old.id;

  update public.chat_read_state crs
  set
    last_read_message_id = prev_id,
    updated_at = now()
  where crs.chat_id = old.chat_id
    and crs.last_read_message_id = old.id;

  return old;
end;
$$;

comment on function public.sync_chat_read_state_on_message_delete() is
  'AFTER DELETE on messages: when last_read_message_id matches removed row, walk to previous surviving id (or null).';

drop trigger if exists messages_sync_chat_read_state_on_delete on public.messages;

create trigger messages_sync_chat_read_state_on_delete
  after delete on public.messages
  for each row
  execute function public.sync_chat_read_state_on_message_delete();

comment on table public.users is
  'User profile storage for UserEntry JSON (id, flags, profile fields, timestamps).';
comment on column public.users.id is
  'Internal sequential user id; JSON field id (number).';
comment on column public.users.flags is
  'UserFlags u16 bitfield: 0x0001 SYSTEM, 0x0002 BOT, 0x0004 PREMIUM; bits 3–15 reserved; demo 0.';
comment on column public.users.created_at is
  'Account creation; JSON field created_at as Unix seconds.';
comment on column public.users.updated_at is
  'Last profile update; JSON field updated_at as Unix seconds.';
comment on column public.users.username is
  'Public handle; JSON field username (string or null).';
comment on column public.users.first_name is
  'Display first name; JSON field first_name (string or null).';
comment on column public.users.last_name is
  'Display last name; JSON field last_name (string or null).';
comment on column public.users.avatar_url is
  'Avatar URL; JSON field avatar_url (string or null).';

comment on table public.chats is
  'Conversation metadata for ChatEntry JSON; last_message comes from chat_last_message.';
comment on column public.chats.id is
  'Globally unique chat id; JSON field id (number).';
comment on column public.chats.kind is
  'ChatKind: 0 Direct, 1 Group (demo), 2 Channel; discrete enum not bitfield.';
comment on column public.chats.parent_id is
  'Parent group for channels; JSON field parent_id (number or null).';
comment on column public.chats.created_at is
  'Creation time; JSON field created_at as Unix seconds.';
comment on column public.chats.updated_at is
  'Last metadata change; JSON field updated_at as Unix seconds.';
comment on column public.chats.title is
  'Display title; JSON field title (string or null).';
comment on column public.chats.avatar_url is
  'Avatar URL; JSON field avatar_url (string or null).';
comment on column public.chats.member_count is
  'Member count; JSON field member_count (number).';

comment on table public.messages is
  'Persisted messages; composite PK (chat_id, id); maps to Message JSON.';
comment on column public.messages.chat_id is
  'Conversation id; JSON field chat_id (number).';
comment on column public.messages.id is
  'Sequential id within chat; JSON field id (number).';
comment on column public.messages.sender_id is
  'Sender user id; JSON field sender_id (number).';
comment on column public.messages.created_at is
  'Send time; JSON field created_at as Unix seconds.';
comment on column public.messages.updated_at is
  'Last edit time; JSON field updated_at as Unix seconds.';
comment on column public.messages.kind is
  'MessageKind: 0 Text (demo send), 1 Image, 2 File, 3 System; values 4+ invalid.';
comment on column public.messages.flags is
  'MessageFlags u16: 0x0001 EDITED, 0x0002 DELETED, 0x0004 FORWARDED, 0x0008 PINNED, 0x0010 SILENT, 0x0020 SYSTEM, 0x0040 BOT, 0x0080 REPLY; 0x0100–0x8000 reserved.';
comment on column public.messages.reply_to_id is
  'Reply target id; JSON field reply_to_id (number or null).';
comment on column public.messages.content is
  'Plain text; JSON field content (string); empty when DELETED flag set.';
comment on column public.messages.rich_content is
  'Rich spans JSON; JSON field rich_content (array or null).';
comment on column public.messages.extra is
  'Extra metadata; JSON field extra (object or null).';

comment on table public.chat_read_state is
  'Per-user read cursor; maps to get_read_state / update_read_state JSON.';
comment on column public.chat_read_state.chat_id is
  'Conversation id; JSON field chat_id (number).';
comment on column public.chat_read_state.user_id is
  'Reader user id; JSON field user_id (number).';
comment on column public.chat_read_state.last_read_message_id is
  'Highest read message id; JSON field last_read_message_id (null = open at tail).';
comment on column public.chat_read_state.updated_at is
  'Last update; JSON field updated_at as Unix seconds.';

-- Realtime: broadcast INSERT/UPDATE/DELETE on messages.
-- FULL replica identity so DELETE (and UPDATE) payloads include the old row
-- (chat_id, id, …) — required for clients to learn which id was removed.
alter table public.messages replica identity full;

alter publication supabase_realtime add table public.messages;

-- RLS (v1 anon demo chat)
alter table public.users enable row level security;
alter table public.chats enable row level security;
alter table public.messages enable row level security;
alter table public.chat_read_state enable row level security;

create policy anon_select_users on public.users
  for select to anon
  using (true);

create policy anon_select_demo_chat on public.chats
  for select to anon
  using (id = 1);

create policy anon_select_demo_messages on public.messages
  for select to anon
  using (chat_id = 1);

create policy anon_insert_demo_messages on public.messages
  for insert to anon
  with check (chat_id = 1);

create policy anon_select_demo_read on public.chat_read_state
  for select to anon
  using (chat_id = 1 and user_id = 1);

create policy anon_insert_demo_read on public.chat_read_state
  for insert to anon
  with check (chat_id = 1 and user_id = 1);

create policy anon_update_demo_read on public.chat_read_state
  for update to anon
  using (chat_id = 1 and user_id = 1)
  with check (chat_id = 1 and user_id = 1);
