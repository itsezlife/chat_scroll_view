/**
 * load_chat handler — returns a single ChatEntry by chat_id.
 *
 * POST body: `{ chat_id: number, user_id?: number }` (user_id defaults to 1).
 * Response: `{ chat: ChatEntryJson }` from buildChatEntry (chats + chat_last_message).
 * Errors: malformed_frame, chat_not_found, database_error.
 */

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { buildChatEntry, type ChatRow } from "../_shared/chat_entry.ts";
import { errorResponse, jsonResponse } from "../_shared/errors.ts";

export interface LoadChatRequest {
  chat_id?: number;
  user_id?: number;
}

export async function handleLoadChat(
  supabase: SupabaseClient,
  body: LoadChatRequest,
): Promise<Response> {
  const chatId = body.chat_id;
  const userId = body.user_id ?? 1;
  if (
    chatId == null || !Number.isInteger(chatId) || chatId < 1
  ) {
    return errorResponse(
      "malformed_frame",
      "chat_id required positive integer",
    );
  }
  if (!Number.isInteger(userId) || userId < 1) {
    return errorResponse(
      "malformed_frame",
      "user_id must be a positive integer when provided",
    );
  }

  const { data: row, error } = await supabase
    .from("chats")
    .select(
      "id, kind, parent_id, created_at, updated_at, title, avatar_url, member_count",
    )
    .eq("id", chatId)
    .maybeSingle();

  if (error) {
    return errorResponse("database_error", error.message);
  }
  if (!row) {
    return errorResponse("chat_not_found", `Chat ${chatId} does not exist`);
  }

  const chat = await buildChatEntry(supabase, row as ChatRow, userId);
  return jsonResponse({ chat });
}
