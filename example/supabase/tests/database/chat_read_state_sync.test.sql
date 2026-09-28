-- chat_read_state sync: write_tag column, delete-trigger reset, Realtime publication.
-- Run: supabase test db
begin;
create extension if not exists pgtap with schema extensions;

select plan(7);

insert into public.users (id) values (9001);
insert into public.chats (id) values (9001);
insert into public.messages (chat_id, id, sender_id, created_at, updated_at)
values
  (9001, 1, 9001, now(), now()),
  (9001, 2, 9001, now(), now());

select has_column(
  'public', 'chat_read_state', 'write_tag',
  'chat_read_state has write_tag'
);

select col_is_null(
  'public', 'chat_read_state', 'write_tag',
  'write_tag is nullable'
);

select throws_ok(
  $$insert into public.chat_read_state (chat_id, user_id, last_read_message_id, write_tag)
    values (9001, 9001, 2, '')$$,
  '23514',
  null,
  'an empty write_tag is rejected'
);

select throws_ok(
  $$insert into public.chat_read_state (chat_id, user_id, last_read_message_id, write_tag)
    values (9001, 9001, 2, repeat('x', 65))$$,
  '23514',
  null,
  'a write_tag longer than 64 characters is rejected'
);

select lives_ok(
  $$insert into public.chat_read_state (chat_id, user_id, last_read_message_id, write_tag)
    values (9001, 9001, 2, 'client-a')$$,
  'a client write_tag is stored'
);

delete from public.messages where chat_id = 9001 and id = 2;

select results_eq(
  $$select last_read_message_id, write_tag
    from public.chat_read_state
    where chat_id = 9001 and user_id = 9001$$,
  $$values (1, null::text)$$,
  'deleting the read message retreats the cursor and clears write_tag'
);

select ok(
  exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'chat_read_state'
  ),
  'chat_read_state is in the supabase_realtime publication'
);

select * from finish();
rollback;
