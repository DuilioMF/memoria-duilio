import "jsr:@supabase/functions-js@2/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const url = Deno.env.get("SUPABASE_URL") ?? "";
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const supabase = createClient(url, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false }
});
const fixedHeaders = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
  "vary": "Origin"
};
const ownerUid = Deno.env.get("MD_OWNER_USER_ID") ?? "";
const allowedOrigins = (Deno.env.get("MD_ALLOWED_ORIGINS") ?? "")
  .split(",").map(s => s.trim()).filter(Boolean);
const originHeaders = (req: Request): Record<string,string> => {
  const origin = req.headers.get("origin");
  return origin && allowedOrigins.includes(origin) ? {
    "access-control-allow-origin": origin,
    "access-control-allow-methods": "GET, POST, OPTIONS",
    "access-control-allow-headers": "apikey, authorization, content-type",
    "access-control-max-age": "600"
  } : {};
};
const reply = (body: unknown, status=200, req?: Request) =>
  new Response(JSON.stringify(body), {
    status, headers: {...fixedHeaders, ...(req ? originHeaders(req) : {})}
  });
const ownedSession = async (req: Request): Promise<boolean> => {
  const token = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!token || !ownerUid || !/^[0-9a-f-]{36}$/i.test(ownerUid)) return false;
  const { data, error } = await supabase.auth.getUser(token);
  return !error && !!data.user && data.user.id === ownerUid;
};

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("origin");
  if (origin && !allowedOrigins.includes(origin))
    return reply({ok:false,error:"ORIGIN_NOT_ALLOWED"},403,req);
  if (req.method === "OPTIONS")
    return new Response(null, {status:204,headers:{"vary":"Origin",...originHeaders(req)}});
  if (!["GET","POST"].includes(req.method))
    return reply({ok:false,error:"METHOD_NOT_ALLOWED"},405,req);
  // Fail closed until operator configures the exact authenticated owner UID.
  if (!ownerUid || !/^[0-9a-f-]{36}$/i.test(ownerUid))
    return reply({ok:false,error:"OWNER_NOT_CONFIGURED"},503,req);
  if (!await ownedSession(req))
    return reply({ok:false,error:"UNAUTHORIZED"},401,req);
  try {
    if (req.method === "GET") {
      const {data,error} = await supabase.rpc("memory_home_payload_v1");
      if (error) throw error;
      return reply({ok:true,action:"home",data},200,req);
    }
    const body = await req.json().catch(()=>({}));
    const action = String(body?.action ?? "home").toLowerCase();
    if (action === "home") {
      const {data,error} = await supabase.rpc("memory_home_payload_v1");
      if (error) throw error;
      return reply({ok:true,action,data},200,req);
    }
    if (action === "control_center") {
      const {data,error} = await supabase.rpc("memory_control_center_summary");
      if (error) throw error;
      return reply({ok:true,action,data},200,req);
    }
    if (action === "plan") {
      const request = String(body?.request ?? "").trim();
      if (!request) return reply({ok:false,error:"REQUEST_REQUIRED"},400,req);
      const {data,error} = await supabase.rpc("memory_query_plan_v1", {
        p_request: request,
        p_project_key: body?.project_key ?? null
      });
      if (error) throw error;
      return reply({ok:true,action,data},200,req);
    }
    return reply({ok:false,error:"UNSUPPORTED_ACTION"},400,req);
  } catch (e) {
    console.error('memoria-home failed',e instanceof Error ? e.message : String(e));
    return reply({ok:false,error:"INTERNAL_ERROR"},500,req);
  }
});