import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { messageRowToLastMessagePreview } from "../_shared/chat_entry.ts";
import { handleLoadChat } from "./handler.ts";

const demoChatRow = {
  id: 1,
  kind: 1,
  parent_id: null,
  created_at: "2020-01-01T00:00:00.000Z",
  updated_at: "2020-03-02T00:19:16.000Z",
  title: "Flutter GitHub Discussions",
  avatar_url: null,
  member_count: 1,
};

const demoChatLastMessageRow = {
  chat_id: 1,
  message_id: 10004,
  sender_id: 1,
  created_at: "2020-03-02T00:19:16.000Z",
  kind: 0,
  flags: 0,
  content_preview: "latest message preview",
};

const demoMessageRow = {
  chat_id: 1,
  id: 10004,
  sender_id: 1,
  created_at: "2020-03-02T00:19:16.000Z",
  updated_at: "2020-03-02T00:19:16.000Z",
  kind: 0,
  flags: 0,
  reply_to_id: null,
  content: "latest message preview",
  rich_content: null,
  extra: null,
};

function mockSupabase(options: {
  chatRow?: typeof demoChatRow | null;
  lastMessage?: typeof demoChatLastMessageRow | null;
  lastReadId?: number | null;
  chatError?: string;
}): SupabaseClient {
  const {
    chatRow = demoChatRow,
    lastMessage = demoChatLastMessageRow,
    lastReadId = 9951,
    chatError,
  } = options;

  return {
    from(table: string) {
      const builder = {
        select(_cols: string) {
          return {
            eq(column: string, _value: unknown) {
              if (table === "chats" && column === "id") {
                return {
                  maybeSingle: () =>
                    Promise.resolve({
                      data: chatRow,
                      error: chatError ? { message: chatError } : null,
                    }),
                };
              }
              if (table === "chat_last_message" && column === "chat_id") {
                return {
                  maybeSingle: () =>
                    Promise.resolve({
                      data: lastMessage,
                      error: null,
                    }),
                };
              }
              if (table === "chat_read_state" && column === "chat_id") {
                return {
                  eq(_col: string, _value: unknown) {
                    return {
                      maybeSingle: () =>
                        Promise.resolve({
                          data: lastReadId == null
                            ? null
                            : { last_read_message_id: lastReadId },
                          error: null,
                        }),
                    };
                  },
                };
              }
              return {
                maybeSingle: () => Promise.resolve({ data: null, error: null }),
              };
            },
          };
        },
      };
      return builder;
    },
  } as unknown as SupabaseClient;
}

Deno.test("messageRowToLastMessagePreview truncates long content", () => {
  const long = "x".repeat(200);
  const preview = messageRowToLastMessagePreview({
    ...demoMessageRow,
    content: long,
  });
  assertEquals(
    new TextEncoder().encode(preview.content_preview).length <= 100,
    true,
  );
  assertEquals(preview.id, 10004);
});

Deno.test("load_chat returns ChatEntry with last_message from chat_last_message", async () => {
  const response = await handleLoadChat(mockSupabase({}), { chat_id: 1 });
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.chat.id, 1);
  assertEquals(body.chat.last_message.id, 10004);
  assertEquals(
    body.chat.last_message.content_preview,
    "latest message preview",
  );
  assertEquals(body.chat.unread_count, 53);
});

Deno.test("load_chat returns null last_message when chat_last_message missing", async () => {
  const response = await handleLoadChat(
    mockSupabase({ lastMessage: null }),
    { chat_id: 1 },
  );
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.chat.last_message, null);
  assertEquals(body.chat.unread_count, 0);
});

Deno.test("load_chat returns chat_not_found when missing", async () => {
  const response = await handleLoadChat(
    mockSupabase({ chatRow: null }),
    { chat_id: 1 },
  );
  assertEquals(response.status, 404);
  const body = await response.json();
  assertEquals(body.error.slug, "chat_not_found");
});

Deno.test("load_chat rejects invalid chat_id", async () => {
  const response = await handleLoadChat(mockSupabase({}), {});
  assertEquals(response.status, 400);
  const body = await response.json();
  assertEquals(body.error.slug, "malformed_frame");
});
