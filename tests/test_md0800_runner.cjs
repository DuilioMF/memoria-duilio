const vm=require('node:vm');const assert=require('node:assert/strict');const fs=require('node:fs');
const source=fs.readFileSync(process.argv[2],'utf8').replace(/^import .*;\n/gm,'');
async function scenario({terminal=false,body={},failure=false,authorized=true}={}){
 let handler,calls=[],fetches=[];
 const sb={rpc:async(name,args)=>{calls.push({name,args});return {data:name==='memory_md0800_bootstrap'?{run_key:'TEST-0800'}:{ok:true},error:null};},from:()=>({select:()=>({eq:()=>({eq:()=>({single:async()=>({data:{status:terminal?'completed':'started',finished_at:terminal?'2026-01-01':null},error:null})})})})})};
 vm.runInNewContext(source,{Deno:{env:{get:n=>n==='SUPABASE_URL'?'https://example.test':'test-secret'},serve:h=>handler=h},createClient:()=>sb,Response,Request,Intl,Date,AbortSignal,fetch:async(u,o)=>{fetches.push(JSON.parse(o.body));return new Response('{}',{status:failure?500:200});}});
 const res=await handler(new Request('https://example.test',{method:'POST',headers:authorized?{apikey:'test-secret'}:{},body:JSON.stringify(body)}));return {result:await res.json(),status:res.status,calls,fetches};
}
(async()=>{
 let r=await scenario();assert.equal(r.result.mode,'bootstrap_only');assert.equal(r.fetches.length,0);assert.equal(r.calls.length,1);
 r=await scenario({terminal:true,body:{request:'work',card_url:'https://trello.com/c/test',project_key:'md'}});assert.equal(r.result.skipped,'terminal_run');assert.equal(r.fetches.length,0);
 r=await scenario({body:{request:'work',card_url:'https://trello.com/c/test',project_key:'md'}});assert.equal(r.fetches[0].request,'work');assert.equal(r.result.executed,false);assert(r.calls.filter(x=>x.name==='memory_schedule_run_step').every(x=>x.args.p_status==='running'&&!x.args.p_finish));
 r=await scenario({failure:true,body:{request:'work',card_url:'https://trello.com/c/test',project_key:'md'}});assert.equal(r.status,502);assert(r.calls.every(x=>!x.args?.p_finish));
 r=await scenario({authorized:false});assert.equal(r.status,401);assert.equal(r.calls.length,0);
 console.log('PASS 5 runner scenarios: bootstrap, terminal, routing, failure, unauthorized');
})().catch(e=>{console.error(e);process.exitCode=1;});
