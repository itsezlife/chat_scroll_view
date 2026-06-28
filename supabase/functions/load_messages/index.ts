/**
 * load_messages Edge Function — paginated Message history for a chat.
 *
 * POST body: LoadRequest (chat_id, from_id, to_id, optional limit).
 * Response: MessageBatchJson with boundary flags (has_older, has_newer, oldest_id, newest_id).
 * Reads public.messages; does not use chat_last_message.
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { rowToMessageJson } from "../_shared/protocol.ts";
import { errorResponse, jsonResponse } from "../_shared/errors.ts";
import {
  DEFAULT_LIMIT,
  type LoadRequest,
  MAX_LIMIT,
  validateLoadRequest,
} from "../_shared/load_request.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, content-type",
      },
    });
  }

  if (req.method !== "POST") {
    return errorResponse("malformed_frame", "POST required");
  }

  let body: LoadRequest;
  try {
    body = await req.json();
  } catch {
    return errorResponse("malformed_frame", "Invalid JSON body");
  }

  const validationError = validateLoadRequest(body);
  if (validationError) {
    return errorResponse("malformed_frame", validationError);
  }

  const chatId = body.chat_id!;
  const fromId = body.from_id!;
  const toId = body.to_id!;

  const limit = Math.min(
    Math.max(body.limit ?? DEFAULT_LIMIT, 1),
    MAX_LIMIT,
  );

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

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

  const { data: edgeRows, error: edgeErr } = await supabase
    .from("messages")
    .select("id")
    .eq("chat_id", chatId)
    .order("id", { ascending: true })
    .limit(1);

  if (edgeErr) {
    return errorResponse("database_error", edgeErr.message);
  }

  if (!edgeRows?.length) {
    return jsonResponse({
      messages: [],
      has_more: false,
      has_older: false,
      has_newer: false,
      oldest_id: null,
      newest_id: null,
      requested_from: fromId,
      requested_to: toId,
    });
  }

  const { data: minRow } = await supabase
    .from("messages")
    .select("id")
    .eq("chat_id", chatId)
    .order("id", { ascending: true })
    .limit(1)
    .single();

  const { data: maxRow } = await supabase
    .from("messages")
    .select("id")
    .eq("chat_id", chatId)
    .order("id", { ascending: false })
    .limit(1)
    .single();

  const terminalOldest = minRow?.id ?? null;
  const terminalNewest = maxRow?.id ?? null;

  const { data: rows, error } = await supabase
    .from("messages")
    .select("*")
    .eq("chat_id", chatId)
    .gte("id", fromId)
    .lte("id", toId)
    .order("id", { ascending: true })
    .limit(limit);

  if (error) {
    return errorResponse("database_error", error.message);
  }

  const messages = (rows ?? []).map(rowToMessageJson);
  const windowSpan = toId - fromId + 1;
  const hasMore = messages.length < windowSpan &&
    messages.length >= limit;

  const hasOlder = terminalOldest != null && fromId > terminalOldest;
  const hasNewer = terminalNewest != null && toId < terminalNewest;

  return jsonResponse({
    messages,
    has_more: hasMore,
    has_older: hasOlder,
    has_newer: hasNewer,
    oldest_id: terminalOldest,
    newest_id: terminalNewest,
    requested_from: fromId,
    requested_to: toId,
  });
});
