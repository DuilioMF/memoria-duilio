import "jsr:@supabase/functions-js@2/edge-runtime.d.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), {
  status,
  headers: { "content-type": "application/json" },
});

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ ok: false, error: "METHOD_NOT_ALLOWED" }, 405);
  if (!SUPABASE_URL || !SERVICE_ROLE) return json({ ok: false, error: "SERVER_NOT_CONFIGURED" }, 503);

  let body: any;
  try { body = await req.json(); } catch { return json({ ok: false, error: "INVALID_JSON" }, 400); }

  const action = String(body?.action || "").trim();
  const sessionKey = String(body?.session_key || "").trim();
  if (!['claim','heartbeat','complete','block','fail','partial','status'].includes(action)) {
    return json({ ok: false, error: "INVALID_ACTION" }, 400);
  }
  if (!sessionKey) return json({ ok: false, error: "SESSION_KEY_REQUIRED" }, 400);

  const payload = {
    p_action: action,
    p_session_key: sessionKey,
    p_project_key: body?.project_key ?? null,
    p_card_url: body?.card_url ?? null,
    p_action_text: body?.action_text ?? null,
    p_result: body?.result ?? null,
    p_evidence: Array.isArray(body?.evidence) ? body.evidence : [],
    p_blockers: Array.isArray(body?.blockers) ? body.blockers : [],
    p_version: body?.version ?? null,
  };

  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/memory_work_adapter`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'apikey': SERVICE_ROLE,
      'authorization': `Bearer ${SERVICE_ROLE}`,
    },
    body: JSON.stringify(payload),
  });
  const text = await r.text();
  let data: unknown = text;
  try { data = text ? JSON.parse(text) : null; } catch {}
  if (!r.ok) return json({ ok: false, error: data }, r.status);
  return json(data, 200);
});
