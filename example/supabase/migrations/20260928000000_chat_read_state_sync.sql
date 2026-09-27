-- Read-state sync across clients.
-- Clients follow chat_read_state over Realtime for their chat and user. Each
-- update_read_state write stores the writing client's tag, so a client can
-- drop the echo of its own write and treat any other change as a read on
-- another client.

-- write_tag — writer of the current cursor; replaced by every write.
alter table public.chat_read_state
  add column if not exists write_tag text
    constraint chat_read_state_write_tag_length
      check (write_tag is null or char_length(write_tag) between 1 and 64);

comment on column public.chat_read_state.write_tag is
  'Tag of the client whose update_read_state wrote this cursor (1–64 chars); null when absent from the write or when the server moved the cursor. JSON field write_tag (string or null).';

-- sync_chat_read_state_on_message_delete — a server move of the cursor is no
-- client's write, so it clears write_tag.
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
    write_tag = null,
    updated_at = now()
  where crs.chat_id = old.chat_id
    and crs.last_read_message_id = old.id;

  return old;
end;
$$;

comment on function public.sync_chat_read_state_on_message_delete() is
  'AFTER DELETE on messages: when last_read_message_id matches removed row, walk to previous surviving id (or null) and clear write_tag.';

-- Realtime: broadcast INSERT/UPDATE on chat_read_state. Clients read only the
-- new row, so the default replica identity is enough. Guarded because a
-- hosted project may already publish the table from the dashboard.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'chat_read_state'
  ) then
    alter publication supabase_realtime add table public.chat_read_state;
  end if;
end;
$$;
