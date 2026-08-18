/**
 * Structured error responses for Edge Functions.
 *
 * ## JSON shape
 * ```json
 * { "error": { "code": 2000, "slug": "chat_not_found", "message": "…",
 *   "retry_after_ms": 0, "extra": null } }
 * ```
 *
 * **Client rule**: match on `slug` (stable across protocol versions), not only `code`.
 *
 * ## Numeric ranges (disjoint; unknown code → treat as generic failure)
 * | Range      | Domain                    |
 * |------------|---------------------------|
 * | 1000–1999  | Authentication            |
 * | 2000–2999  | Chats                     |
 * | 3000–3999  | Messages                  |
 * | 4000–4999  | Media uploads             |
 * | 5000–5999  | Server internal           |
 * | 9000–9999  | Malformed request/payload |
 *
 * ## Retry policy (design)
 * - **Permanent** (do not retry): forbidden, chat_not_found, not_chat_member,
 *   message_too_large, extra_too_large, content_filtered, unsupported_media_type
 * - **Transient** (backoff retry): internal_error, service_unavailable,
 *   database_error, rate_limited — honor `retry_after_ms` when slug is rate_limited
 *
 * ### Authentication (1000–1999)
 * | Code | Slug                 | Demo | Retry |
 * |-----:|----------------------|:----:|:-----:|
 * | 1000 | unauthorized         | —    | no    |
 * | 1001 | token_expired        | —    | yes   |
 * | 1002 | forbidden            | —    | no    |
 * | 1003 | session_revoked      | —    | no    |
 * | 1004 | unsupported_version  | —    | no    |
 *
 * ### Chats (2000–2999)
 * | Code | Slug               | Demo | Retry |
 * |-----:|--------------------|:----:|:-----:|
 * | 2000 | chat_not_found     | ✓    | no    |
 * | 2001 | chat_already_exists| —    | no    |
 * | 2002 | not_chat_member    | —    | no    |
 * | 2003 | chat_full          | —    | no    |
 *
 * ### Messages (3000–3999)
 * | Code | Slug              | Demo | Retry |
 * |-----:|-------------------|:----:|:-----:|
 * | 3000 | message_not_found | ✓    | no    |
 * | 3001 | message_too_large | ✓    | no    |
 * | 3002 | extra_too_large   | —    | no    |
 * | 3003 | rate_limited      | ✓    | yes   |
 * | 3004 | content_filtered  | —    | no    |
 *
 * ### Media (4000–4999)
 * | Code | Slug                   | Demo | Retry |
 * |-----:|------------------------|:----:|:-----:|
 * | 4000 | file_too_large         | —    | no    |
 * | 4001 | unsupported_media_type | —    | no    |
 * | 4002 | upload_failed          | —    | yes   |
 *
 * ### Server (5000–5999)
 * | Code | Slug                 | Demo | Retry |
 * |-----:|----------------------|:----:|:-----:|
 * | 5000 | internal_error       | ✓    | yes   |
 * | 5001 | service_unavailable  | ✓    | yes   |
 * | 5002 | database_error       | ✓    | yes   |
 *
 * ### Protocol / request (9000–9999)
 * | Code | Slug            | Demo | Retry |
 * |-----:|-----------------|:----:|:-----:|
 * | 9000 | malformed_frame | ✓    | no    |
 * | 9001 | unknown_command | —    | no    |
 * | 9002 | frame_too_large | —    | no    |
 */

/** Slugs returned by demo Edge Functions (subset of tables above). */
export type ErrorSlug =
  | "chat_not_found"
  | "message_not_found"
  | "message_too_large"
  | "rate_limited"
  | "internal_error"
  | "service_unavailable"
  | "database_error"
  | "malformed_frame";

const SLUG_TO_CODE: Record<ErrorSlug, number> = {
  chat_not_found: 2000,
  message_not_found: 3000,
  message_too_large: 3001,
  rate_limited: 3003,
  internal_error: 5000,
  service_unavailable: 5001,
  database_error: 5002,
  malformed_frame: 9000,
};

const SLUG_TO_HTTP: Record<ErrorSlug, number> = {
  chat_not_found: 404,
  message_not_found: 404,
  malformed_frame: 400,
  message_too_large: 413,
  rate_limited: 429,
  service_unavailable: 503,
  internal_error: 500,
  database_error: 500,
};

/** Slugs that MUST NOT be retried without user action. */
const PERMANENT_SLUGS: ReadonlySet<string> = new Set([
  "forbidden",
  "chat_not_found",
  "not_chat_member",
  "message_too_large",
  "extra_too_large",
  "content_filtered",
  "unsupported_media_type",
  "malformed_frame",
]);

/** Slugs safe to retry with exponential backoff. */
const TRANSIENT_SLUGS: ReadonlySet<string> = new Set([
  "internal_error",
  "service_unavailable",
  "database_error",
  "rate_limited",
]);

/** Whether clients should avoid automatic retry for this slug. */
export function isPermanentErrorSlug(slug: string): boolean {
  return PERMANENT_SLUGS.has(slug);
}

/** Whether clients may retry after backoff (check retry_after_ms for rate_limited). */
export function isTransientErrorSlug(slug: string): boolean {
  return TRANSIENT_SLUGS.has(slug);
}

/** Wire error object nested under `error` key. */
export interface ErrorPayload {
  error: {
    code: number;
    slug: ErrorSlug;
    message: string;
    retry_after_ms: number;
    extra: unknown | null;
  };
}

/** Build JSON error Response with protocol-shaped body and HTTP status. */
export function errorResponse(
  slug: ErrorSlug,
  message: string,
  retryAfterMs = 0,
  extra: unknown | null = null,
): Response {
  const body: ErrorPayload = {
    error: {
      code: SLUG_TO_CODE[slug],
      slug,
      message,
      retry_after_ms: retryAfterMs,
      extra,
    },
  };
  return new Response(JSON.stringify(body), {
    status: SLUG_TO_HTTP[slug],
    headers: { "Content-Type": "application/json" },
  });
}

/** Build JSON success Response. */
export function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
