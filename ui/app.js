const cfg = window.MEMORIA_CONFIG || {};
const state = { home: null, token: cfg.accessToken || sessionStorage.getItem("memoria_access_token") || "" };

const $ = (id) => document.getElementById(id);
const esc = (v) => String(v ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#039;"}[c]));
const fmt = (v) => {
  if (!v || String(v).startsWith("1970-")) return "—";
  try { return new Intl.DateTimeFormat("es-AR",{dateStyle:"short",timeStyle:"short"}).format(new Date(v)); } catch { return String(v); }
};

function setStatus(text){ $("statusText").textContent = text; }
function authHeaders(){
  const headers = {"content-type":"application/json"};
  if (cfg.anonKey) headers.apikey = cfg.anonKey;
  if (state.token) headers.authorization = `Bearer ${state.token}`;
  return headers;
}
async function api(body){
  const r = await fetch(cfg.apiUrl,{method:"POST",headers:authHeaders(),body:JSON.stringify(body)});
  if (r.status === 401) { showAuth(true); throw new Error("Sesión requerida"); }
  const data = await r.json().catch(()=>({}));
  if (!r.ok || data?.ok === false) throw new Error(data?.error || `HTTP ${r.status}`);
  return data.data ?? data.result ?? data;
}
async function semantic(query,projectKey=null){
  if (!cfg.semanticUrl) return null;
  const body = {action:"search",query,limit:5};
  if (projectKey) body.project_key = projectKey;
  const r = await fetch(cfg.semanticUrl,{method:"POST",headers:authHeaders(),body:JSON.stringify(body)});
  if (!r.ok) return null;
  return await r.json().catch(()=>null);
}
function showAuth(show){ $("authPanel").classList.toggle("hidden",!show); }

async function login(email,password){
  if (!cfg.supabaseUrl || !cfg.anonKey) throw new Error("El entorno no tiene anonKey configurada.");
  const r = await fetch(`${cfg.supabaseUrl}/auth/v1/token?grant_type=password`,{
    method:"POST",headers:{"content-type":"application/json",apikey:cfg.anonKey},
    body:JSON.stringify({email,password})
  });
  const data = await r.json();
  if (!r.ok || !data.access_token) throw new Error(data.error_description || data.msg || "No se pudo iniciar sesión");
  state.token = data.access_token;
  sessionStorage.setItem("memoria_access_token",state.token);
  showAuth(false);
  await refreshHome();
}

function countCard(label,value){
  return `<div class="count"><span>${esc(label)}</span><strong>${esc(value ?? 0)}</strong></div>`;
}
function projectCard(p){
  const live = ["running","active","blocked"].includes(String(p.execution_state || "").toLowerCase());
  return `<article class="project">
    <div style="display:flex;justify-content:space-between;gap:8px">
      <h3>${esc(p.project_name)}</h3><span class="badge ${live?"live":""}">${esc(p.execution_state || "idle")}</span>
    </div>
    <div class="meta">
      <span>Ejecutor</span><span>${esc(p.executor || "—")}</span>
      <span>Versión</span><span>${esc(p.version || "—")}</span>
      <span>Última acción</span><span>${esc(p.last_action || "—")}</span>
      <span>Última señal</span><span>${esc(fmt(p.last_activity_at || p.last_event_at))}</span>
      <span>Conector</span><span>${esc(p.connector_status || "—")}</span>
    </div>
  </article>`;
}
function runCard(r){
  return `<div class="run"><strong>${esc(r.project_name || r.project_key || "Ejecución")}</strong>
  <div class="meta"><span>Ejecutor</span><span>${esc(r.executor || "—")}</span><span>Estado</span><span>${esc(r.state || r.observed_state || "—")}</span>
  <span>Acción</span><span>${esc(r.last_action || "—")}</span><span>Última señal</span><span>${esc(fmt(r.last_activity_at || r.heartbeat_at))}</span></div></div>`;
}
function renderHome(home){
  state.home = home;
  const t = home.today || {};
  const c = t.counts || {};
  $("counts").innerHTML =
    countCard("Por hacer",c.por_hacer)+countCard("En prueba",c.en_prueba)+countCard("En ejecución",c.en_ejecucion)+countCard("Espera de vos",c.espera_de_vos)+countCard("Ejecuciones reales",c.ejecuciones_reales);

  $("priorityList").innerHTML = (t.priority_items || []).map(x => `<article class="priority"><h4>${esc(x.title)}</h4><span class="badge">${esc(x.state)}</span> ${x.card_url?`<a href="${esc(x.card_url)}" target="_blank" rel="noreferrer">Trello</a>`:""}</article>`).join("") || "<p class='subtle'>Sin prioridades.</p>";
  $("waitingList").innerHTML = (home.waiting_for_you || []).map(x => `<article class="waiting"><strong>${esc(x.title || x.project_name || "Pendiente")}</strong><div class="meta"><span>Estado</span><span>${esc(x.state || "Espera de vos")}</span><span>Ejecutor</span><span>${esc(x.executor || "—")}</span><span>Última acción</span><span>${esc(x.last_action || "—")}</span></div></article>`).join("") || "<p class='subtle'>Nada espera de vos ahora.</p>";

  const projects = home.projects || [];
  $("projectsGrid").innerHTML = projects.map(projectCard).join("");
  const running = home.running || [];
  $("runningBlock").innerHTML = running.length ? running.map(runCard).join("") : "<p class='subtle'>No hay ejecuciones reales activas.</p>";

  const closed = home.closed_runs || [];
  $("closedCount").textContent = closed.length;
  $("closedList").innerHTML = closed.map(runCard).join("");
  $("closedWorks").classList.toggle("hidden",!closed.length);

  const sync = t.trello_sync?.last_sync_at;
  setStatus(`Actualizado ${fmt(home.generated_at)}${sync?` · Trello ${fmt(sync)}`:""}`);
}

async function refreshHome(){
  setStatus("Actualizando…");
  try{
    const home = await api({action:"home"});
    renderHome(home);
    showAuth(false);
  }catch(e){
    setStatus(e.message);
    if (String(e.message).includes("Sesión")) showAuth(true);
  }
}
function addBubble(text,who="assistant"){
  const el = document.createElement("div");
  el.className = `bubble ${who}`;
  el.textContent = text;
  $("conversation").appendChild(el);
  $("conversation").scrollTop = $("conversation").scrollHeight;
}
function speak(text){
  if (!$("speakToggle").checked || !("speechSynthesis" in window)) return;
  speechSynthesis.cancel();
  const u = new SpeechSynthesisUtterance(text); u.lang="es-AR"; speechSynthesis.speak(u);
}
async function handleMessage(raw){
  const text = String(raw || "").trim(); if(!text) return;
  addBubble(text,"user"); $("messageInput").value="";
  if (/^(hola|buenas|buen día|buenas tardes|buenas noches)[!. ]*$/i.test(text)){
    const answer="Hola Duilio, acá estoy. ¿En qué seguimos?";
    addBubble(answer); speak(answer); return;
  }

  addBubble("Ubicando proyecto…");
  const pending = $("conversation").lastElementChild;

  try{
    const plan = await api({action:"plan",request:text});
    const brain = plan?.brain_router || {};
    const needsClarification = plan?.clarification_required === true || brain?.clarification_required === true;

    if (needsClarification){
      pending.remove();
      const answer = plan?.clarification_question || brain?.clarification_question || "¿De qué proyecto hablás?";
      addBubble(answer); speak(answer); return;
    }

    const projectKey = plan?.project_key || brain?.project?.project_key || null;
    const projectName = brain?.project?.project_name || projectKey || "";
    pending.textContent = projectName ? `Recuperando contexto de ${projectName}…` : "Recuperando contexto…";

    const mem = await semantic(text,projectKey);
    pending.remove();

    const learned = mem?.results || [];
    const snippets = learned.slice(0,3).map(x=>x.title || x.content || x.chunk_content).filter(Boolean);
    const sourceName = plan?.source_plan?.primary_source?.name || plan?.source_plan?.primary_source?.system_key || "";
    const executor = plan?.executor_plan?.executor?.display_name || plan?.executor_plan?.executor?.name || plan?.executor_plan?.executor_key || "";

    let answer = "";
    if (projectName) answer += `Proyecto: ${projectName}.`;
    if (sourceName) answer += `${answer?" ":""}Fuente: ${sourceName}.`;
    if (executor) answer += `${answer?" ":""}Ejecutor sugerido: ${executor}.`;
    if (!answer) answer = "Contexto localizado.";
    if (snippets.length) answer += "\n\nRecuerdos relevantes:\n• "+snippets.join("\n• ");

    addBubble(answer); speak(answer);
  }catch(e){
    pending.remove();
    addBubble(e.message,"error");
  }
}

document.querySelectorAll(".tab").forEach(btn=>btn.addEventListener("click",()=>{
  document.querySelectorAll(".tab").forEach(x=>x.classList.toggle("active",x===btn));
  document.querySelectorAll(".panel").forEach(x=>x.classList.toggle("active",x.id===btn.dataset.tab));
}));
$("refreshBtn").addEventListener("click",refreshHome);
$("messageForm").addEventListener("submit",e=>{e.preventDefault();handleMessage($("messageInput").value);});
$("loginForm").addEventListener("submit",async e=>{
  e.preventDefault(); $("authMessage").textContent="Entrando…";
  try{await login($("email").value,$("password").value);$("authMessage").textContent="";}catch(err){$("authMessage").textContent=err.message;}
});

const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
if (SpeechRecognition){
  const rec = new SpeechRecognition(); rec.lang="es-AR"; rec.interimResults=false;
  rec.onstart=()=>$("micBtn").classList.add("listening");
  rec.onend=()=>$("micBtn").classList.remove("listening");
  rec.onresult=e=>handleMessage(e.results[0][0].transcript);
  $("micBtn").addEventListener("click",()=>rec.start());
}else{
  $("micBtn").title="Reconocimiento de voz no disponible en este navegador";
}
refreshHome();
setInterval(refreshHome,60000);
