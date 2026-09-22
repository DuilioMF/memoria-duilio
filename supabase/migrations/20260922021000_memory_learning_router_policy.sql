-- Memoria Duilio
-- Política de conocimiento, Router v1.1, autovigilancia e interfaz backend.
-- Aplicado en Supabase el 21/09/2026 (Argentina).
-- Este archivo consolida las migraciones aplicadas en vivo para que GitHub
-- vuelva a ser fuente recuperable del cambio.

create or replace function public.memory_promote_knowledge_candidates(p_owner_key text default 'duilio'::text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  r public.memory_knowledge%rowtype;
  v_verified boolean;
  v_ratio numeric;
  v_old_status text;
  v_promoted integer := 0;
  v_deprecated integer := 0;
  v_scored integer := 0;
begin
  for r in
    select *
    from public.memory_knowledge
    where owner_key=p_owner_key and status='candidate'
    order by created_at
  loop
    update public.memory_knowledge
       set score=public.memory_calculate_knowledge_score(
             success_count,failure_count,partial_count,use_count,confidence,last_used_at
           ),
           updated_at=now()
     where id=r.id
     returning * into r;
    v_scored := v_scored + 1;

    v_ratio := case when coalesce(r.use_count,0) > 0
                    then r.success_count::numeric / r.use_count::numeric
                    else 0 end;

    select exists (
      select 1
      from public.memory_knowledge_experiences ke
      join public.memory_experiences e on e.id=ke.experience_id
      where ke.knowledge_id=r.id
        and (
          e.metadata->>'claim_state'='verified'
          or e.evidence->>'claim_state'='verified'
        )
    ) into v_verified;

    v_old_status := r.status;

    if r.failure_count >= 2 then
      update public.memory_knowledge
         set status='deprecated',
             metadata=coalesce(metadata,'{}'::jsonb) ||
                      jsonb_build_object(
                        'deprecated_by_policy','failure_count_gte_2',
                        'replacement_link_required', supersedes_id is null
                      ),
             updated_at=now()
       where id=r.id;

      insert into public.memory_events(owner_key,event_type,actor,details)
      values(
        p_owner_key,'knowledge_status_changed','memory_promote_knowledge_candidates',
        jsonb_build_object(
          'knowledge_id',r.id,'from_status',v_old_status,'to_status','deprecated',
          'reason','failure_count_gte_2','failure_count',r.failure_count,
          'supersedes_id',r.supersedes_id
        )
      );
      v_deprecated := v_deprecated + 1;

    elsif r.evidence_count >= 2 and v_ratio >= 0.8 and v_verified then
      update public.memory_knowledge
         set status='active',
             last_validated_at=coalesce(last_validated_at,now()),
             metadata=coalesce(metadata,'{}'::jsonb) ||
                      jsonb_build_object(
                        'promoted_by_policy','candidate_v1',
                        'promotion_success_ratio',v_ratio,
                        'promotion_verified_evidence',true
                      ),
             updated_at=now()
       where id=r.id;

      insert into public.memory_events(owner_key,event_type,actor,details)
      values(
        p_owner_key,'knowledge_status_changed','memory_promote_knowledge_candidates',
        jsonb_build_object(
          'knowledge_id',r.id,'from_status',v_old_status,'to_status','active',
          'evidence_count',r.evidence_count,'success_ratio',v_ratio,
          'verified_evidence',true
        )
      );
      v_promoted := v_promoted + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'owner_key',p_owner_key,
    'scored',v_scored,
    'promoted',v_promoted,
    'deprecated',v_deprecated,
    'ran_at',now()
  );
end;
$function$;

create or replace function public.memory_supersede_knowledge(
  p_old_knowledge_id uuid,
  p_new_knowledge_id uuid,
  p_owner_key text default 'duilio'::text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_old public.memory_knowledge%rowtype;
  v_new public.memory_knowledge%rowtype;
begin
  select * into v_old from public.memory_knowledge
   where id=p_old_knowledge_id and owner_key=p_owner_key for update;
  select * into v_new from public.memory_knowledge
   where id=p_new_knowledge_id and owner_key=p_owner_key for update;

  if v_old.id is null or v_new.id is null then
    raise exception 'knowledge_not_found';
  end if;

  update public.memory_knowledge
     set status='deprecated',
         updated_at=now()
   where id=v_old.id;

  update public.memory_knowledge
     set supersedes_id=v_old.id,
         updated_at=now()
   where id=v_new.id;

  insert into public.memory_events(owner_key,event_type,actor,details)
  values(
    p_owner_key,'knowledge_superseded','memory_supersede_knowledge',
    jsonb_build_object('old_knowledge_id',v_old.id,'new_knowledge_id',v_new.id)
  );

  return jsonb_build_object(
    'ok',true,
    'deprecated_id',v_old.id,
    'replacement_id',v_new.id,
    'replacement_supersedes_id',v_old.id
  );
end;
$function$;

create or replace function public.memory_add_domain_knowledge(
  p_project_key text,
  p_knowledge_type text,
  p_title text,
  p_statement text,
  p_problem_type text default null,
  p_metadata jsonb default '{}'::jsonb,
  p_owner_key text default 'duilio'::text
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_project_id uuid;
  v_id uuid;
  v_fingerprint text;
begin
  if p_knowledge_type not in ('sql_pattern','integration_gotcha','business_rule_ypf','n8n_limitation') then
    raise exception 'invalid domain knowledge_type: %', p_knowledge_type;
  end if;

  if nullif(btrim(p_project_key),'') is not null then
    select id into v_project_id
    from public.memory_projects
    where owner_key=p_owner_key and project_key=p_project_key and status='active';
    if v_project_id is null then raise exception 'project_not_found: %',p_project_key; end if;
  end if;

  v_fingerprint := public.memory_make_knowledge_fingerprint(
    p_owner_key,
    v_project_id,
    coalesce(nullif(btrim(p_problem_type),''),p_knowledge_type),
    p_statement
  );

  insert into public.memory_knowledge(
    owner_key,project_id,knowledge_type,title,statement,status,confidence,
    problem_type,fingerprint,evidence_count,metadata
  )
  values(
    p_owner_key,v_project_id,p_knowledge_type,btrim(p_title),btrim(p_statement),
    'candidate',0.6,coalesce(nullif(btrim(p_problem_type),''),p_knowledge_type),
    v_fingerprint,0,
    coalesce(p_metadata,'{}'::jsonb) || jsonb_build_object(
      'domain_knowledge',true,
      'created_via','memory_add_domain_knowledge'
    )
  )
  on conflict (fingerprint) where fingerprint is not null
  do update set
    title=excluded.title,
    statement=excluded.statement,
    metadata=public.memory_knowledge.metadata || excluded.metadata,
    updated_at=now()
  returning id into v_id;

  insert into public.memory_events(owner_key,event_type,actor,details)
  values(
    p_owner_key,'domain_knowledge_candidate_created','memory_add_domain_knowledge',
    jsonb_build_object(
      'knowledge_id',v_id,
      'knowledge_type',p_knowledge_type,
      'project_key',p_project_key
    )
  );

  return v_id;
end;
$function$;

comment on function public.memory_add_domain_knowledge(text,text,text,text,text,jsonb,text)
is 'Inserta conocimiento técnico de dominio como candidate. Tipos permitidos: sql_pattern, integration_gotcha, business_rule_ypf, n8n_limitation.';

create or replace function public.memory_source_router_v1(p_request text)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  q text := lower(coalesce(p_request,''));
  primary_key text;
  support_keys text[];
begin
  if q ~ '(automatiz|\mn8n\M|webhook|cron|programaci[oó]n recurrente|programaci[oó]n autom[aá]tica|cada d[ií]a|cada lunes|cada semana|todos los d[ií]as)' then
    primary_key := 'n8n'; support_keys := array['supabase','trello'];
  elsif q ~ '(c[oó]digo|repositorio|repo|github|commit|pull request|\mpr\M|\mrama\M|release|apk|versi[oó]n.*c[oó]digo)' then
    primary_key := 'github'; support_keys := array['trello','supabase'];
  elsif q ~ '(corriendo|ejecuci[oó]n real|ejecutor|heartbeat|lease|agente activo|qu[eé] est[aá] ejecutando)' then
    primary_key := 'supabase'; support_keys := array['trello'];
  elsif q ~ '(pendiente|por hacer|en prueba|espera de vos|tarjeta|tarea|pr[oó]xima acci[oó]n|estado del tablero)' then
    primary_key := 'trello'; support_keys := array['supabase'];
  elsif q ~ '(documentaci[oó]n|manual|notion|historial narrativo|especificaci[oó]n)' then
    primary_key := 'notion'; support_keys := array['trello'];
  elsif q ~ '(whatsapp|avisame|aviso|notificaci[oó]n)' then
    primary_key := 'whatsapp'; support_keys := array['n8n'];
  else
    primary_key := 'memoria-duilio'; support_keys := array['trello','supabase'];
  end if;

  return jsonb_build_object(
    'request',p_request,
    'primary_source',(
      select jsonb_build_object(
        'system_key',s.system_key,'name',s.display_name,'role',s.primary_role,
        'authoritative_for',s.authoritative_for,'write_policy',s.write_policy)
      from public.memory_source_of_truth s
      where s.system_key=primary_key and s.enabled),
    'supporting_sources',coalesce((
      select jsonb_agg(jsonb_build_object(
        'system_key',s.system_key,'name',s.display_name,'role',s.primary_role)
        order by array_position(support_keys,s.system_key))
      from public.memory_source_of_truth s
      where s.system_key=any(support_keys) and s.enabled),'[]'::jsonb)
  );
end;
$function$;

create or replace function public.memory_brain_router(
  p_request text,
  p_project_key text default null::text,
  p_owner_key text default 'duilio'::text
)
returns jsonb
language plpgsql
set search_path to ''
as $function$
declare
  v_project public.memory_projects%rowtype;
  v_resume jsonb:='{}'::jsonb;
  v_graph jsonb:='{}'::jsonb;
  v_rules jsonb:='[]'::jsonb;
  v_memories jsonb:='[]'::jsonb;
  v_knowledge jsonb:='[]'::jsonb;
  v_experiences jsonb:='[]'::jsonb;
  v_executor text:='chat';
  v_reason text:='Conversación, análisis o preparación antes de ejecutar.';
  v_clarification boolean:=false;
  q text:=coalesce(nullif(btrim(p_request),''),'estado proyecto');
begin
  if p_project_key is not null then
    select * into v_project
    from public.memory_projects
    where owner_key=p_owner_key and project_key=p_project_key and status='active';
  else
    select p.* into v_project
    from public.memory_projects p
    where p.owner_key=p_owner_key
      and p.status='active'
      and (
        lower(q) like '%'||lower(p.project_key)||'%'
        or lower(q) like '%'||lower(p.project_name)||'%'
        or exists (
          select 1
          from jsonb_array_elements_text(coalesce(p.metadata->'aliases','[]'::jsonb)) a(alias)
          where lower(q) like '%'||lower(a.alias)||'%'
        )
      )
    order by
      case
        when lower(q) like '%'||lower(p.project_key)||'%' then 3
        when lower(q) like '%'||lower(p.project_name)||'%' then 2
        else 1
      end desc,
      greatest(length(p.project_key),length(p.project_name)) desc
    limit 1;
  end if;

  v_clarification := v_project.id is null;

  if v_project.id is not null then
    v_resume:=public.memory_resume_project(v_project.project_key,p_owner_key);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'rule_key',r.rule_key,'statement',r.statement,'confidence',r.confidence,'provenance',r.provenance
  ) order by r.rule_key),'[]'::jsonb)
  into v_rules
  from public.memory_learning_rules r
  where r.owner_key=p_owner_key and r.status='active';

  v_graph:=public.memory_graph_context(
    p_owner_key,
    case when v_project.id is null then null else v_project.project_key end,
    null,2
  );

  begin
    select coalesce(jsonb_agg(to_jsonb(s) order by s.relevance desc),'[]'::jsonb)
      into v_memories
    from public.memory_search_text(q,8,null) s;
  exception when others then
    v_memories:='[]'::jsonb;
  end;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',k.id,'title',k.title,'statement',k.statement,'problem_type',k.problem_type,
    'status',k.status,'score',k.score,'confidence',k.confidence
  ) order by k.score desc nulls last,k.updated_at desc),'[]'::jsonb)
  into v_knowledge
  from (
    select *
    from public.memory_knowledge k
    where k.owner_key=p_owner_key
      and k.status in ('active','candidate','review')
      and (v_project.id is null or k.project_id=v_project.id)
    order by k.score desc nulls last,k.updated_at desc
    limit 8
  ) k;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',e.id,'problem_type',e.problem_type,'solution',e.solution,'outcome',e.outcome,
    'quality_score',e.quality_score,'learning_status',e.learning_status,'occurred_at',e.occurred_at
  ) order by e.occurred_at desc),'[]'::jsonb)
  into v_experiences
  from (
    select *
    from public.memory_experiences e
    where e.owner_key=p_owner_key
      and (v_project.id is null or e.project_id=v_project.id)
    order by e.occurred_at desc
    limit 8
  ) e;

  if lower(q) ~ '(cada |todos los |program|automat|monitor|webhook|cuando ocurra|cada día|cada dia|semanal|diario)' then
    v_executor:='n8n';
    v_reason:='La solicitud parece recurrente, condicional o de automatización.';
  elsif lower(q) ~ '(public|deploy|despleg|github|repositorio|cloudflare|naveg|sitio|archiv|modific.*app|ejecut.*varios|multipaso)' then
    v_executor:='work';
    v_reason:='La solicitud parece requerir navegación, archivos/código o ejecución multipaso; revisar primero la regla de cuota de Work.';
  else
    v_executor:='chat';
    v_reason:='Puede prepararse o resolverse en Chat antes de consumir ejecución externa.';
  end if;

  return jsonb_build_object(
    'router_version','1.1',
    'request',q,
    'project',case when v_project.id is null then null else jsonb_build_object(
      'id',v_project.id,'project_key',v_project.project_key,'project_name',v_project.project_name
    ) end,
    'project_resolution',case when v_project.id is null then 'unresolved' else 'resolved' end,
    'clarification_required',v_clarification,
    'clarification_question',case when v_clarification then '¿De qué proyecto hablás?' else null end,
    'suggested_executor',v_executor,
    'routing_reason',v_reason,
    'operational_rules',v_rules,
    'graph',v_graph,
    'retrieved_memory',v_memories,
    'knowledge',v_knowledge,
    'recent_experiences',v_experiences,
    'project_context',v_resume,
    'policy',jsonb_build_object(
      'verify_before_learning',true,
      'capa0_before_execution',true,
      'work_quota_rule_required',true
    )
  );
end;
$function$;

create or replace function public.memory_query_plan_v1(
  p_request text,
  p_project_key text default null::text
)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  brain_plan jsonb;
  source_plan jsonb;
  executor_plan jsonb;
  resolved_project_key text;
begin
  brain_plan := public.memory_brain_router(p_request,p_project_key,'duilio');
  resolved_project_key := coalesce(
    nullif(p_project_key,''),
    brain_plan #>> '{project,project_key}'
  );

  source_plan := public.memory_source_router_v1(p_request);
  executor_plan := public.memory_select_executor_v2(
    p_request,
    resolved_project_key,
    null
  );

  return jsonb_build_object(
    'generated_at',clock_timestamp(),
    'request',p_request,
    'project_key',resolved_project_key,
    'clarification_required',coalesce((brain_plan->>'clarification_required')::boolean,false),
    'clarification_question',brain_plan->>'clarification_question',
    'brain_router',brain_plan,
    'source_plan',source_plan,
    'executor_plan',executor_plan
  );
end;
$function$;

-- Project catalog entries explicitly used by the Router test.
insert into public.memory_projects(
  owner_key,project_key,project_name,project_type,status,capture_mode,
  connector_status,auto_capture_enabled,source_system,metadata
)
values
('duilio','integracion-android-ble','Integración Android BLE','chatgpt_project','active','assisted','pending',false,'user_defined',
 '{"aliases":["BLE","Android BLE"]}'::jsonb),
('duilio','arca-f2002','ARCA F2002','chatgpt_project','active','assisted','pending',false,'user_defined',
 '{"aliases":["F2002","ARCA F2002"]}'::jsonb),
('duilio','google-drive-supabase-ia','Google Drive + Supabase IA','chatgpt_project','active','assisted','pending',false,'user_defined',
 '{"aliases":["Drive","Google Drive","sincronización de Drive"]}'::jsonb),
('duilio','tiendanube-revalsoftia','Tiendanube RevalsoftIA','chatgpt_project','active','assisted','pending',false,'user_defined',
 '{"aliases":["Tiendanube","Tienda Nube"]}'::jsonb)
on conflict(owner_key,project_key) do update
set project_name=excluded.project_name,
    metadata=public.memory_projects.metadata || excluded.metadata,
    updated_at=now();

update public.memory_projects
set metadata=jsonb_set(
  coalesce(metadata,'{}'::jsonb),'{aliases}',
  (
    select jsonb_agg(distinct x)
    from jsonb_array_elements_text(
      coalesce(metadata->'aliases','[]'::jsonb) ||
      '["pico 03","pico 3","chat memory de WhatsApp","chat memory WhatsApp","Rubén","Ruben","siniestro Rubén","siniestro Ruben","Capitán Rodolfo"]'::jsonb
    ) a(x)
  ),true
), updated_at=now()
where owner_key='duilio' and project_key='doinglio';

update public.memory_projects
set metadata=jsonb_set(
  coalesce(metadata,'{}'::jsonb),'{aliases}',
  (
    select jsonb_agg(distinct x)
    from jsonb_array_elements_text(
      coalesce(metadata->'aliases','[]'::jsonb) ||
      '["GATT","T10","T10 ultra","reloj"]'::jsonb
    ) a(x)
  ),true
), updated_at=now()
where owner_key='duilio' and project_key='feli-salud';

update public.memory_projects
set metadata=jsonb_set(
  coalesce(metadata,'{}'::jsonb),'{aliases}',
  (
    select jsonb_agg(distinct x)
    from jsonb_array_elements_text(
      coalesce(metadata->'aliases','[]'::jsonb) ||
      '["publicador de redes","publicador redes"]'::jsonb
    ) a(x)
  ),true
), updated_at=now()
where owner_key='duilio' and project_key='redes-revalsoftia';

-- Non-blocking integrity categories.
update public.memory_integrity_incidents
set severity='warning'
where inconsistency_type in ('authority_observation_stale','automatic_connector_not_connected');

-- Freeze unused affective processing without deleting its tables/functions.
do $$
declare r record;
begin
  for r in
    select jobid
    from cron.job
    where jobname in ('memoria-duilio-affective-decay-daily','memoria-duilio-affective-process')
  loop
    perform cron.alter_job(r.jobid,null,null,null,null,false);
  end loop;
end $$;

-- Weekly promotion in the existing 06:xx UTC maintenance window.
do $$
begin
  if not exists (select 1 from cron.job where jobname='memoria-duilio-knowledge-promotion-weekly') then
    perform cron.schedule(
      'memoria-duilio-knowledge-promotion-weekly',
      '25 6 * * 1',
      $cmd$select public.memory_promote_knowledge_candidates('duilio');$cmd$
    );
  end if;
end $$;

insert into public.memory_events(owner_key,event_type,actor,details)
values(
  'duilio','maintenance_policy_changed','migration',
  jsonb_build_object(
    'affective_jobs_frozen',true,
    'knowledge_promotion_job','memoria-duilio-knowledge-promotion-weekly',
    'dispatch_events_added',false
  )
);
