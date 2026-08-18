/**
 * Request body for load_messages Edge Function.
 *
 * POST JSON fields:
 * - chat_id (required, positive int) — conversation to load
 * - from_id (required, >= 1) — inclusive start message id
 * - to_id (required, >= from_id) — inclusive end message id
 * - limit (optional, 1–256, default 64) — max rows returned
 *
 * Response: MessageBatchJson (see protocol.ts).
 */

export interface LoadRequest {
  chat_id?: number;
  from_id?: number;
  to_id?: number;
  limit?: number;
}

/** Default page size when limit omitted. */
export const DEFAULT_LIMIT = 64;

/** Hard cap on limit query param. */
export const MAX_LIMIT = 256;

/** Returns human-readable validation error or null when valid. */
export function validateLoadRequest(body: LoadRequest): string | null {
  const chatId = body.chat_id;
  const fromId = body.from_id;
  const toId = body.to_id;
  if (
    chatId == null || fromId == null || toId == null ||
    !Number.isInteger(chatId) || !Number.isInteger(fromId) ||
    !Number.isInteger(toId) || fromId < 1 || toId < fromId
  ) {
    return "chat_id, from_id, to_id required; from_id >= 1; to_id >= from_id";
  }
  return null;
}
