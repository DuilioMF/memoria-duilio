import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const supabase = createClient(Deno.env.get("SUPABASE_URL") ?? "", serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });

const authorized = async (req: Request) => {
  const apikey = req.headers.get("apikey") ?? "";
  const bearer = (req.headers.get("authorization") ?? "").replace(
    /^Bearer\s+/i,
    "",
  );
  if (serviceKey && (apikey === serviceKey || bearer === serviceKey)) return true;

  const token = req.headers.get("x-memory-sync-token") ?? "";
  if (!token) return false;
  const { data, error } = await supabase.rpc("memory_verify_capability_token", {
    p_capability: "sync",
    p_token: token,
  });
  return !error && data === true;
};

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST required" }, 405);
  if (!(await authorized(req))) return json({ error: "unauthorized" }, 401);

  try {
    const body = await req.json().catch(() => ({}));
    const { data, error } = await supabase.rpc("memory_run_daily_consolidation", {
      p_owner_key: "duilio",
      p_day: body.day ?? null,
    });
    if (error) throw error;
    return json({ function_version: 2, phase: 5, result: data });
  } catch (error) {
    return json(
      { error: error instanceof Error ? error.message : String(error) },
      500,
    );
  }
});
