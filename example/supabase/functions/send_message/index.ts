/**
 * send_message Edge Function entrypoint.
 * POST only; delegates to handleSendMessage with service-role Supabase client.
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { errorResponse } from "../_shared/errors.ts";
import { handleSendMessage } from "./handler.ts";

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

  let body: Parameters<typeof handleSendMessage>[1];
  try {
    body = await req.json();
  } catch {
    return errorResponse("malformed_frame", "Invalid JSON body");
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  return handleSendMessage(supabase, body);
});
