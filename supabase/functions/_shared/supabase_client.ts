import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

/** Untyped-schema client, matching what `createClient(url, key)` returns. */
// deno-lint-ignore no-explicit-any
export type ServiceClient = ReturnType<typeof createClient<any>>;
