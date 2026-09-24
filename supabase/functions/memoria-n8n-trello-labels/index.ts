import "jsr:@supabase/functions-js/edge-runtime.d.ts";
const J=(x:unknown,s=200)=>new Response(JSON.stringify(x),{status:s,headers:{"Content-Type":"application/json","Cache-Control":"no-store"}});
const SB=(Deno.env.get("SUPABASE_URL")||"").replace(/\/$/,""),SR=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||"";
const NK=Deno.env.get("N8N_API_KEY")||"",NB=(Deno.env.get("N8N_BASE_URL")||"https://n8n.srv1251563.hstgr.cloud").replace(/\/$/,"");
const allowedName="Memoria Duilio — Etiquetas y colores automáticos";
async function permitted(req:Request){
 const token=req.headers.get("X-Memoria-Sync-Token")||"";
 if(!token||token.length>1000||!SB||!SR)return false;
 const r=await fetch(SB+"/rest/v1/rpc/memory_verify_n8n_label_bootstrap_token",{
  method:"POST",headers:{"Content-Type":"application/json","apikey":SR,"Authorization":"Bearer "+SR},
  body:JSON.stringify({p_token:token})});
 return r.ok&&(await r.json())===true;
}
async function n8n(path:string,init:RequestInit={}){
 if(!NK)return {ok:false,status:503,body:{code:"N8N_API_KEY_NOT_CONFIGURED"}};
 try{
  const r=await fetch(NB+"/api/v1"+path,{...init,headers:{"X-N8N-API-KEY":NK,"Content-Type":"application/json",...(init.headers||{})}});
  const t=await r.text();let body:any;try{body=JSON.parse(t)}catch{body={message:t.slice(0,140)}}
  return {ok:r.ok,status:r.status,body};
 }catch(e){return {ok:false,status:502,body:{message:String(e).slice(0,130)}}}
}
async function sb(path:string,init:RequestInit={}){
 const r=await fetch(SB+"/rest/v1/"+path,{...init,headers:{
  "Content-Type":"application/json","apikey":SR,"Authorization":"Bearer "+SR,
  "Prefer":"return=representation",...(init.headers||{})
 }});
 const t=await r.text();let b:any;try{b=JSON.parse(t)}catch{b={message:t.slice(0,120)}}
 return {ok:r.ok,status:r.status,body:b};
}
async function findWorkflow(){
 const list=await n8n("/workflows?limit=100");
 const rows=(list.body||{}).data||[];
 return {list_ok:list.ok,matched:Array.isArray(rows)?rows.find((w:any)=>w.name===allowedName):null};
}
Deno.serve(async(req)=>{
 if(req.method!=="POST")return J({ok:false,error:"METHOD_NOT_ALLOWED"},405);
 if(!await permitted(req))return J({ok:false,error:"NOT_AUTHORIZED"},403);
 const action=(await req.json().catch(()=>({})))?.action;
 if(action==="deploy"){
   const s=await sb("memory_n8n_workflow_specs?spec_key=eq.trello_auto_labels&select=spec,status,external_workflow_id");
   if(!s.ok||!Array.isArray(s.body)||s.body.length!==1)return J({ok:false,error:"SPEC_UNAVAILABLE",status:s.status},503);
   const rec=s.body[0],w=rec.spec;
   if(w?.name!==allowedName||!Array.isArray(w.nodes)||w.nodes.length!==14
      ||w.nodes.some((node:any)=>!["n8n-nodes-base.scheduleTrigger","n8n-nodes-base.httpRequest","n8n-nodes-base.trello","n8n-nodes-base.code"].includes(node.type)))
     return J({ok:false,error:"SPEC_NOT_APPROVED"},400);
   const scan=await findWorkflow();
   if(!scan.list_ok)return J({ok:false,error:"N8N_LIST_FAILED"},502);
   let id=scan.matched?.id||rec.external_workflow_id;
   let created=false;
   if(!id){
     const out=await n8n("/workflows",{method:"POST",body:JSON.stringify(w)});
     if(!out.ok||!out.body?.id)return J({ok:false,error:"CREATE_FAILED",http_status:out.status,reason:String(out.body?.message||"unknown").slice(0,250)},502);
     id=out.body.id;created=true;
   }else if(scan.matched && rec.external_workflow_id && rec.external_workflow_id!==id){
     return J({ok:false,error:"EXISTING_WORKFLOW_CONFLICT"},409);
   }else{
     const out=await n8n("/workflows/"+encodeURIComponent(id),{method:"PUT",body:JSON.stringify(w)});
     if(!out.ok)return J({ok:false,error:"UPDATE_FAILED",http_status:out.status,reason:String(out.body?.message||"unknown").slice(0,250)},502);
   }
   await sb("memory_n8n_workflow_specs?spec_key=eq.trello_auto_labels",{
     method:"PATCH",body:JSON.stringify({external_workflow_id:id,status:"created",result:{created},updated_at:new Date().toISOString()})
   });
   const activate=await n8n("/workflows/"+encodeURIComponent(id)+"/activate",{method:"POST"});
   const final=await n8n("/workflows/"+encodeURIComponent(id));
   const active=Boolean(final.body?.active);
   await sb("memory_n8n_workflow_specs?spec_key=eq.trello_auto_labels",{
     method:"PATCH",body:JSON.stringify({external_workflow_id:id,status:active?"active":"created_inactive",
       result:{created,activation_http_status:activate.status,active},updated_at:new Date().toISOString()})
   });
   return J({ok:active,id,created,active,activation_http_status:activate.status,
     activation_error:active?null:String(activate.body?.message||"unknown").slice(0,160)});
 }
 if(action==="status"){
   const s=await sb("memory_n8n_workflow_specs?spec_key=eq.trello_auto_labels&select=external_workflow_id,status");
   const id=s.body?.[0]?.external_workflow_id||null;
   if(!id)return J({ok:false,error:"NOT_DEPLOYED"},404);
   const [w,e]=await Promise.all([n8n("/workflows/"+encodeURIComponent(id)),
    n8n("/executions?workflowId="+encodeURIComponent(id)+"&limit=10")]);
   const events=Array.isArray(e.body?.data)?e.body.data.map((x:any)=>({
       id:x.id,status:x.status,startedAt:x.startedAt,stoppedAt:x.stoppedAt,mode:x.mode
   })):[];
   return J({ok:true,id,active:Boolean(w.body?.active),name:w.body?.name,
      executions:events,execution_list_status:e.status});
 }
 if(action==="inspect_failure"){
   const s=await sb("memory_n8n_workflow_specs?spec_key=eq.trello_auto_labels&select=external_workflow_id");
   const id=s.body?.[0]?.external_workflow_id||null;
   if(!id)return J({ok:false,error:"NOT_DEPLOYED"},404);
   const e=await n8n("/executions?workflowId="+encodeURIComponent(id)+"&limit=5");
   const last=Array.isArray(e.body?.data)?e.body.data.find((x:any)=>x.status==="error"):null;
   if(!last)return J({ok:true,errors:[],last_count:e.body?.data?.length||0});
   const d=await n8n("/executions/"+encodeURIComponent(last.id)+"?includeData=true");
   const error=d.body?.data?.resultData?.error||{};
   return J({ok:true,errors:[{execution_id:last.id,at:last.startedAt,
     node:error.node?.name||error.nodeName||null,message:String(error.message||"unknown").slice(0,400)}]});
 }
 return J({ok:false,error:"ACTION_NOT_ALLOWED"},400);
});
