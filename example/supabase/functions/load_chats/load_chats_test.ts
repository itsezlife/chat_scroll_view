import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { handleLoadChats } from "./handler.ts";

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
  content_preview: "latest",
};

function mockSupabase(chatRows: (typeof demoChatRow)[]): SupabaseClient {
  return {
    from(table: string) {
      if (table === "chats") {
        return {
          select(_cols: string) {
            return {
              order(_col: string, _opts: { ascending: boolean }) {
                return Promise.resolve({
                  data: chatRows,
                  error: null,
                });
              },
            };
          },
        };
      }
      if (table === "chat_last_message") {
        return {
          select(_cols: string) {
            return {
              eq(_column: string, _value: unknown) {
                return {
                  maybeSingle: () =>
                    Promise.resolve({
                      data: chatRows.length ? demoChatLastMessageRow : null,
                      error: null,
                    }),
                };
              },
            };
          },
        };
      }
      if (table === "chat_read_state") {
        return {
          select(_cols: string) {
            return {
              eq(_column: string, _value: unknown) {
                return {
                  eq(_col: string, _value: unknown) {
                    return {
                      maybeSingle: () =>
                        Promise.resolve({
                          data: { last_read_message_id: 9951 },
                          error: null,
                        }),
                    };
                  },
                };
              },
            };
          },
        };
      }
      return {};
    },
  } as unknown as SupabaseClient;
}

Deno.test("load_chats returns inbox list from chat_last_message", async () => {
  const response = await handleLoadChats(mockSupabase([demoChatRow]), {});
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.chats.length, 1);
  assertEquals(body.chats[0].id, 1);
  assertEquals(body.chats[0].last_message.id, 10004);
});

Deno.test("load_chats returns empty list when unseeded", async () => {
  const response = await handleLoadChats(mockSupabase([]), {});
  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.chats, []);
});
