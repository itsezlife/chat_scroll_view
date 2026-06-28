-- Denormalized last-message preview for load_chat / load_chats.
-- One row per chat mirrors LastMessagePreview nested in ChatEntry.last_message JSON.
-- Maintained by AFTER INSERT trigger on messages; bulk seed uses post-seed backfill.

-- chat_last_message — tail preview for load_chat / load_chats (ChatEntry.last_message).
create table if not exists public.chat_last_message (
  -- Chat id (PK, 1:1 with chats); not repeated on nested JSON object.
  chat_id int4 primary key references public.chats (id) on delete cascade,
  -- Tail message id; JSON field last_message.id (number).
  message_id int4 not null,
  -- Sender of tail message; JSON field last_message.sender_id (number).
  sender_id int4 not null references public.users (id),
  -- Tail message time; JSON field last_message.created_at (Unix seconds).
  created_at timestamptz not null,
  -- MessageKind of tail (int2) — same value table as messages.kind (0 Text … 3 System).
  kind int2 not null default 0,
  -- MessageFlags of tail (int2/u16) — same bit table as messages.flags.
  -- Trigger: (flags & 2) != 0 forces content_preview ''.
  flags int2 not null default 0,
  -- Truncated plain text; JSON field last_message.content_preview (max 100 UTF-8 bytes).
  content_preview text not null default ''
);

comment on table public.chat_last_message is
  'Denormalized LastMessagePreview per chat; exposed as ChatEntry.last_message in JSON.';
comment on column public.chat_last_message.chat_id is
  'Chat id (PK); one preview row per conversation.';
comment on column public.chat_last_message.message_id is
  'Tail message id; JSON last_message.id (number).';
comment on column public.chat_last_message.sender_id is
  'Tail sender id; JSON last_message.sender_id (number).';
comment on column public.chat_last_message.created_at is
  'Tail timestamp; JSON last_message.created_at as Unix seconds.';
comment on column public.chat_last_message.kind is
  'MessageKind copy of tail: 0 Text, 1 Image, 2 File, 3 System.';
comment on column public.chat_last_message.flags is
  'MessageFlags copy of tail; 0x0002 DELETED clears content_preview in trigger.';
comment on column public.chat_last_message.content_preview is
  'Truncated body; JSON last_message.content_preview (max 100 UTF-8 bytes).';

-- truncate_utf8_preview — UTF-8-safe string truncation for content_preview column.
create or replace function public.truncate_utf8_preview(
  -- Source plain text from messages.content.
  input text,
  -- Maximum encoded byte length (default 100).
  max_bytes int default 100
) returns text
language plpgsql
immutable
as $$
declare
  raw bytea;
  len int;
  result bytea;
begin
  if coalesce(input, '') = '' then
    return '';
  end if;

  begin
    raw := convert_to(input, 'UTF8');
  exception
    when others then
      return left(coalesce(input, ''), 100);
  end;

  if octet_length(raw) <= max_bytes then
    return input;
  end if;

  len := max_bytes;
  result := substring(raw from 1 for len);
  while len > 0 and (get_byte(result, len - 1) & 192) = 128 loop
    len := len - 1;
    result := substring(raw from 1 for len);
  end loop;

  begin
    return convert_from(result, 'UTF8');
  exception
    when others then
      return left(coalesce(input, ''), 100);
  end;
end;
$$;

comment on function public.truncate_utf8_preview(text, int) is
  'UTF-8-safe truncation for LastMessagePreview.content_preview (default 100 bytes).';

-- sync_chat_last_message_on_insert — advance denormalized tail on new messages.
create or replace function public.sync_chat_last_message_on_insert()
returns trigger
language plpgsql
as $$
declare
  preview text;
  existing_id int4;
begin
  select clm.message_id into existing_id
  from public.chat_last_message clm
  where clm.chat_id = new.chat_id;

  if existing_id is not null and existing_id >= new.id then
    return new;
  end if;

  if (new.flags & 2) != 0 then
    preview := '';
  else
    preview := public.truncate_utf8_preview(new.content);
  end if;

  insert into public.chat_last_message (
    chat_id,
    message_id,
    sender_id,
    created_at,
    kind,
    flags,
    content_preview
  ) values (
    new.chat_id,
    new.id,
    new.sender_id,
    new.created_at,
    new.kind,
    new.flags,
    preview
  )
  on conflict (chat_id) do update set
    message_id = excluded.message_id,
    sender_id = excluded.sender_id,
    created_at = excluded.created_at,
    kind = excluded.kind,
    flags = excluded.flags,
    content_preview = excluded.content_preview
  where chat_last_message.message_id < excluded.message_id;

  update public.chats
  set updated_at = new.created_at
  where id = new.chat_id;

  return new;
end;
$$;

comment on function public.sync_chat_last_message_on_insert() is
  'AFTER INSERT on messages: upsert chat_last_message when NEW.id advances tail; sync chats.updated_at.';

drop trigger if exists messages_sync_chat_last_message on public.messages;

create trigger messages_sync_chat_last_message
  after insert on public.messages
  for each row
  execute function public.sync_chat_last_message_on_insert();

alter table public.chat_last_message enable row level security;

create policy anon_select_demo_chat_last_message on public.chat_last_message
  for select to anon
  using (chat_id = 1);
