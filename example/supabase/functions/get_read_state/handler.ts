/**
 * get_read_state handler — read cursor for open-anchor resolution.
 *
 * POST body: `{ chat_id, user_id }` (both required positive integers).
 * Response: chat_id, user_id, last_read_message_id (null when no row), updated_at (Unix s or null).
 * Errors: malformed_frame, chat_not_found, database_error.
 */

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { errorResponse, jsonResponse } from "../_shared/errors.ts";

export interface GetReadStateRequest {
  chat_id?: number;
  user_id?: number;
}

export interface ReadStateRow {
  chat_id: number;
  user_id: number;
  last_read_message_id: number | null;
  updated_at: string;
}

export async function handleGetReadState(
  supabase: SupabaseClient,
  body: GetReadStateRequest,
): Promise<Response> {
  const chatId = body.chat_id;
  const userId = body.user_id;
  if (
    chatId == null || userId == null ||
    !Number.isInteger(chatId) || !Number.isInteger(userId) ||
    chatId < 1 || userId < 1
  ) {
    return errorResponse(
      "malformed_frame",
      "chat_id and user_id required positive integers",
    );
  }

  const { count: chatCount, error: chatErr } = await supabase
    .from("chats")
    .select("id", { count: "exact", head: true })
    .eq("id", chatId);

  if (chatErr) {
    return errorResponse("database_error", chatErr.message);
  }
  if (!chatCount) {
    return errorResponse("chat_not_found", `Chat ${chatId} does not exist`);
  }

  const { data: row, error } = await supabase
    .from("chat_read_state")
    .select("chat_id, user_id, last_read_message_id, updated_at")
    .eq("chat_id", chatId)
    .eq("user_id", userId)
    .maybeSingle();

  if (error) {
    return errorResponse("database_error", error.message);
  }

  if (!row) {
    return jsonResponse({
      chat_id: chatId,
      user_id: userId,
      last_read_message_id: null,
      updated_at: null,
    });
  }

  const state = row as ReadStateRow;
  return jsonResponse({
    chat_id: state.chat_id,
    user_id: state.user_id,
    last_read_message_id: state.last_read_message_id,
    updated_at: Math.floor(new Date(state.updated_at).getTime() / 1000),
  });
}
