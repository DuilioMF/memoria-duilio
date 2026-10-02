import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
const url=Deno.env.get("SUPABASE_URL")??"";
const key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")??"";
const sb=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
const out=(b,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{"content-type":"application/json","cache-control":"no-store"}});
async function auth(req){
 const a=req.headers.get("apikey")??""; const b=(req.headers.get("authorization")??"").replace(/^Bearer\s+/i,"");
 if(key&&(a===key||b===key)) return true;
 const t=req.headers.get("x-memory-sync-token")??""; if(!t)return false;
 const {data,error}=await sb.rpc("memory_verify_capability_token",{p_capability:"sync",p_token:t});
 return !error&&data===true;
}
async function rpc(name,args){
 const {data,error}=await sb.rpc(name,args);if(error)throw error;return data;
}
Deno.serve(async(req)=>{
 if(req.method!=="POST")return out({error:"POST required"},405);
 if(!(await auth(req)))return out({error:"unauthorized"},401);
 const body=await req.json().catch(()=>({}));
 const origin=body.origin??"scheduler";
 const day=body.day??new Intl.DateTimeFormat("en-CA",{timeZone:"America/Argentina/Cordoba",year:"numeric",month:"2-digit",day:"2-digit"}).format(new Date());
 let runKey="";
 try{
  const boot=await rpc("memory_md0800_bootstrap",{p_run_date:day,p_origin:origin});runKey=boot.run_key;
  const {data:run,error}=await sb.from("memory_scheduled_runs").select("status,finished_at").eq("owner_key","duilio").eq("run_key",runKey).single();if(error)throw error;
  if(run.finished_at||["completed","incomplete","failed"].includes(run.status))return out({ok:true,run_key:runKey,skipped:"terminal_run",status:run.status});
  // The scheduler guarantees bootstrap only. The principal routine selects a card.
  // Routing is optional and cannot finish the productive daily run.
  const request=String(body.request??"").trim();
  const card=String(body.card_url??"").trim();
  const project=String(body.project_key??"").trim();
  if(!request||!card||!project)return out({ok:true,run_key:runKey,mode:"bootstrap_only",awaiting:"main-0800",dispatched:false});
  const step=await rpc("memory_schedule_run_step",{p_run_key:runKey,p_status:"running",p_step:"orchestrator_dispatch",p_summary:"Routing de tarjeta seleccionada; ejecución y cierre pendientes",p_details:{origin},p_finish:false});
  if(step.ignored)return out({ok:true,run_key:runKey,skipped:"terminal_run",status:step.status});
  const response=await fetch("https://n8n.srv1251563.hstgr.cloud/webhook/memoria-duilio-orquestador-prueba-v1",{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({run_key:runKey,origin,request,card_url:card,project_key:project,prefer_executor:body.prefer_executor??null,priority:body.priority??90}),signal:AbortSignal.timeout(30000)});
  const txt=await response.text();
  await rpc("memory_schedule_dispatch_event",{p_schedule_key:"memoria-duilio-0800",p_run_key:runKey,p_stage:"orchestrator",p_target_system:"n8n",p_operation:"Memoria Duilio - Orquestador",p_status:response.ok?"ok":"error",p_request_ref:runKey,p_response_code:String(response.status),p_response_summary:txt.slice(0,1000),p_error_message:response.ok?null:txt.slice(0,1000),p_details:{origin}});
  await rpc("memory_schedule_run_step",{p_run_key:runKey,p_status:"running",p_step:response.ok?"routing_complete":"routing_failed",p_summary:response.ok?"Routing realizado; tarea productiva y cierre pendientes":"Falló routing; rutina principal debe registrar resultado final",p_details:{origin,n8n_status:response.status},p_finish:false});
  return out({ok:response.ok,run_key:runKey,n8n_status:response.status,executed:false,awaiting:"main-0800"},response.ok?200:502);
 }catch(e){
  if(runKey)try{await rpc("memory_schedule_run_step",{p_run_key:runKey,p_status:"running",p_step:"runner_error",p_summary:String(e),p_details:{origin,runner_error:true},p_finish:false});}catch{}
  return out({ok:false,run_key:runKey,error:String(e)},500);
 }
});
