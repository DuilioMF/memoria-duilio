import "jsr:@supabase/functions-js@2/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const url = Deno.env.get("SUPABASE_URL") ?? "";
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const supabase = createClient(url, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false }
});
const headers = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store"
};
const reply = (body: unknown, status=200) =>
  new Response(JSON.stringify(body), {status, headers});

Deno.serve(async (req: Request) => {
  if (!["GET","POST"].includes(req.method)) return reply({ok:false,error:"METHOD_NOT_ALLOWED"},405);
  try {
    if (req.method === "GET") {
      const {data,error} = await supabase.rpc("memory_home_payload_v1");
      if (error) throw error;
      return reply({ok:true,action:"home",data});
    }
    const body = await req.json().catch(()=>({}));
    const action = String(body?.action ?? "home").toLowerCase();
    if (action === "home") {
      const {data,error} = await supabase.rpc("memory_home_payload_v1");
      if (error) throw error;
      return reply({ok:true,action,data});
    }
    if (action === "plan") {
      const request = String(body?.request ?? "").trim();
      if (!request) return reply({ok:false,error:"REQUEST_REQUIRED"},400);
      const {data,error} = await supabase.rpc("memory_query_plan_v1", {
        p_request: request,
        p_project_key: body?.project_key ?? null
      });
      if (error) throw error;
      return reply({ok:true,action,data});
    }
    return reply({ok:false,error:"UNSUPPORTED_ACTION"},400);
  } catch (e) {
    return reply({ok:false,error:e instanceof Error ? e.message : String(e)},500);
  }
});