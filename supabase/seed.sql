-- Demo chat skeleton; message rows in seeds/demo_messages.sql

INSERT INTO public.users (id, flags, username, first_name, last_name)
VALUES (1, 0, 'demo', 'Demo', 'User')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.chats (id, kind, title, member_count)
VALUES (1, 1, 'Flutter GitHub Discussions', 1)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.chat_read_state (chat_id, user_id, last_read_message_id)
VALUES (1, 1, 9951)
ON CONFLICT (chat_id, user_id) DO NOTHING;

-- Bulk demo_messages load: skip per-row last_message trigger; backfill follows.
alter table public.messages disable trigger messages_sync_chat_last_message;
