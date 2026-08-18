import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { handleSendMessage } from "./handler.ts";

function mockSupabase(newestId: number, chatCount = 1): SupabaseClient {
  let inserted: Record<string, unknown> | null = null;

  const from = (table: string) => {
    const state = { head: false, orderDesc: false };

    const builder = {
      select(_cols: string, opts?: { count?: string; head?: boolean }) {
        state.head = opts?.head === true;
        return builder;
      },
      eq(_column: string, _value: unknown) {
        return builder;
      },
      order(_column: string, opts?: { ascending?: boolean }) {
        state.orderDesc = opts?.ascending === false;
        return builder;
      },
      limit(_n: number) {
        return builder;
      },
      maybeSingle() {
        if (table === "messages") {
          return Promise.resolve({
            data: newestId > 0 ? { id: newestId } : null,
            error: null,
          });
        }
        return Promise.resolve({ data: null, error: null });
      },
      insert(payload: Record<string, unknown>) {
        inserted = { ...payload };
        return {
          select(_cols: string) {
            return {
              single() {
                return Promise.resolve({
                  data: inserted,
                  error: null,
                });
              },
            };
          },
        };
      },
      then(resolve: (value: { count: number | null; error: null }) => void) {
        if (state.head && table === "chats") {
          resolve({ count: chatCount, error: null });
          return;
        }
        resolve({ count: 0, error: null });
      },
    };

    return builder;
  };

  return { from } as unknown as SupabaseClient;
}

Deno.test("send_message assigns sequential id and returns message shape", async () => {
  const supabase = mockSupabase(10004);

  const response = await handleSendMessage(supabase, {
    chat_id: 1,
    content: "hello",
    sender_id: 1,
  });

  assertEquals(response.status, 200);
  const body = await response.json();
  assertEquals(body.message.id, 10005);
  assertEquals(body.message.chat_id, 1);
  assertEquals(body.message.content, "hello");
  assertEquals(typeof body.message.created_at, "number");
});

Deno.test("send_message rejects empty content", async () => {
  const response = await handleSendMessage(mockSupabase(1), {
    chat_id: 1,
    content: "   ",
  });
  assertEquals(response.status, 400);
  const body = await response.json();
  assertEquals(body.error.slug, "malformed_frame");
});
