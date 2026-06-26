-- Post-seed backfill: one row per chat from tail message.
-- Runs after seeds/demo_messages.sql; avoids per-row trigger cost during bulk load.

insert into public.chat_last_message (
  chat_id,
  message_id,
  sender_id,
  created_at,
  kind,
  flags,
  content_preview
)
select distinct on (m.chat_id)
  m.chat_id,
  m.id,
  m.sender_id,
  m.created_at,
  m.kind,
  m.flags,
  public.truncate_utf8_preview(
    case when (m.flags & 2) != 0 then '' else m.content end
  )
from public.messages m
order by m.chat_id, m.id desc
on conflict (chat_id) do update set
  message_id = excluded.message_id,
  sender_id = excluded.sender_id,
  created_at = excluded.created_at,
  kind = excluded.kind,
  flags = excluded.flags,
  content_preview = excluded.content_preview;

update public.chats c
set updated_at = clm.created_at
from public.chat_last_message clm
where c.id = clm.chat_id;

alter table public.messages enable trigger messages_sync_chat_last_message;
