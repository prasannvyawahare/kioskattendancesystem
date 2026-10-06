import { createClient as createSupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/database.types";

/// Service-role client: bypasses RLS entirely, so it's used only from
/// server actions (never imported into a "use client" file -- the service
/// role key must never reach the browser bundle). This is what lets the
/// admin panel create/list/revoke kiosk Auth users via auth.admin.*
/// (requires the service role key; the anon key used by lib/supabase/
/// client.ts and server.ts cannot call those endpoints) and read/write
/// profiles rows -- including other kiosks' -- without needing a dedicated
/// SECURITY DEFINER RPC for every device-management operation.
export function createAdminClient() {
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!serviceRoleKey) {
    throw new Error(
      "SUPABASE_SERVICE_ROLE_KEY is not set. Add it to .env.local (server-only -- " +
        "do not prefix with NEXT_PUBLIC_). See .env.local.example.",
    );
  }

  return createSupabaseClient<Database>(process.env.NEXT_PUBLIC_SUPABASE_URL!, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}
