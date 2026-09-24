-- Memoria Duilio 0.6.0
-- GRAFOS 4/5: extracción automática + evidencia de origen
-- Aplicado y probado en Supabase el 23/09/2026.

create table if not exists public.memory_graph_dictionary (
  term_key text primary key,
  entity_type text not null,
  canonical_name text not null,
  aliases text[] not null default '{}'::text[],
  relation_type text not null default 'usa',
  confidence numeric not null default 0.90 check (confidence between 0 and 1),
  active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.memory_graph_dictionary enable row level security;
drop policy if exists memory_graph_dictionary_no_client_access on public.memory_graph_dictionary;
create policy memory_graph_dictionary_no_client_access
on public.memory_graph_dictionary
for all to anon, authenticated
using (false) with check (false);
revoke all on public.memory_graph_dictionary from public, anon, authenticated;
grant select,insert,update,delete on public.memory_graph_dictionary to service_role;

insert into public.memory_graph_dictionary(term_key,entity_type,canonical_name,aliases,relation_type,confidence,metadata)
values
 ('n8n','technology','n8n',array['N8N'],'usa',0.98,'{"source":"graph_dictionary"}'),
 ('supabase','technology','Supabase',array['supabase'],'usa',0.98,'{"source":"graph_dictionary"}'),
 ('postgresql','technology','PostgreSQL',array['Postgres','postgres'],'usa',0.98,'{"source":"graph_dictionary"}'),
 ('sql-server','technology','SQL Server',array['SQLServer','SQL Server','SQLEXPRESS'],'usa',0.98,'{"source":"graph_dictionary"}'),
 ('trello','technology','Trello',array['trello'],'usa',0.98,'{"source":"graph_dictionary"}'),
 ('notion','technology','Notion',array['notion'],'usa',0.98,'{"source":"graph_dictionary"}'),
 ('github','technology','GitHub',array['github','Git'],'usa',0.98,'{"source":"graph_dictionary"}'),
 ('whatsapp','technology','WhatsApp',array['Whatsapp','WhatsApp Cloud API'],'usa',0.96,'{"source":"graph_dictionary"}'),
 ('cloudflare','technology','Cloudflare',array['Cloudflare Workers','Cloudflare Pages'],'usa',0.96,'{"source":"graph_dictionary"}'),
 ('openai','ai_engine','OpenAI',array['GPT','ChatGPT'],'usa',0.94,'{"source":"graph_dictionary"}'),
 ('gemini','ai_engine','Gemini',array['Google Gemini'],'usa',0.94,'{"source":"graph_dictionary"}'),
 ('yolo','technology','YOLO',array['Yolo'],'usa',0.92,'{"source":"graph_dictionary"}')
on conflict(term_key) do update set
  entity_type=excluded.entity_type,
  canonical_name=excluded.canonical_name,
  aliases=excluded.aliases,
  relation_type=excluded.relation_type,
  confidence=excluded.confidence,
  active=true,
  metadata=public.memory_graph_dictionary.metadata || excluded.metadata,
  updated_at=now();

create or replace function public.memory_link_entities_evidenced(
  p_owner_key text,
  p_source_entity_id uuid,
  p_relation_type text,
  p_target_entity_id uuid,
  p_confidence numeric default 1,
  p_memory_item_id uuid default null,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v_id uuid;
  v_evidence jsonb;
begin
  if p_source_entity_id is null or p_target_entity_id is null or p_source_entity_id=p_target_entity_id then
    raise exception 'invalid_relation';
  end if;
  if nullif(btrim(p_relation_type),'') is null then
    raise exception 'relation_type_required';
  end if;

  select id, coalesce(metadata->'evidence_item_ids','[]'::jsonb)
    into v_id,v_evidence
  from public.memory_relations
  where owner_key=p_owner_key
    and source_entity_id=p_source_entity_id
    and relation_type=btrim(p_relation_type)
    and target_entity_id=p_target_entity_id
    and valid_until is null
  limit 1
  for update;

  if p_memory_item_id is not null
     and not (coalesce(v_evidence,'[]'::jsonb) @> jsonb_build_array(p_memory_item_id::text)) then
    v_evidence:=coalesce(v_evidence,'[]'::jsonb) || jsonb_build_array(p_memory_item_id::text);
  end if;

  if v_id is not null then
    update public.memory_relations
       set confidence=greatest(confidence,least(greatest(coalesce(p_confidence,1),0),1)),
           memory_item_id=coalesce(memory_item_id,p_memory_item_id),
           metadata=coalesce(metadata,'{}'::jsonb)
             || coalesce(p_metadata,'{}'::jsonb)
             || jsonb_build_object('evidence_item_ids',coalesce(v_evidence,'[]'::jsonb))
     where id=v_id;
    return v_id;
  end if;

  if p_memory_item_id is not null then
    v_evidence:=jsonb_build_array(p_memory_item_id::text);
  else
    v_evidence:='[]'::jsonb;
  end if;

  insert into public.memory_relations(
    owner_key,source_entity_id,relation_type,target_entity_id,
    memory_item_id,confidence,metadata
  )
  values(
    p_owner_key,p_source_entity_id,btrim(p_relation_type),p_target_entity_id,
    p_memory_item_id,least(greatest(coalesce(p_confidence,1),0),1),
    coalesce(p_metadata,'{}'::jsonb) || jsonb_build_object('evidence_item_ids',v_evidence)
  )
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.memory_extract_graph_from_item(p_item_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  i public.memory_items%rowtype;
  p record;
  d record;
  v_text text;
  v_project_entity uuid;
  v_root_entity uuid;
  v_term_entity uuid;
  v_statement_entity uuid;
  v_project_ids uuid[] := '{}'::uuid[];
  v_project_count integer := 0;
  v_term_count integer := 0;
  v_statement_count integer := 0;
  v_relation_count integer := 0;
  v_role text;
  v_relation text;
  v_conf numeric;
  v_statement_name text;
begin
  select * into i from public.memory_items where id=p_item_id;
  if not found then
    return jsonb_build_object('ok',false,'reason','item_not_found','item_id',p_item_id);
  end if;
  if i.status <> 'active' or nullif(btrim(coalesce(i.content,'')),'') is null then
    return jsonb_build_object('ok',true,'skipped',true,'reason','inactive_or_empty','item_id',p_item_id);
  end if;

  v_text := lower(coalesce(i.title,'') || ' ' || coalesce(i.content,'') || ' ' || coalesce(i.summary,''));
  v_root_entity := public.memory_ensure_entity(
    i.owner_key,'system','Memoria Duilio',array['Memoria 9'],
    jsonb_build_object('system_key','memoria-duilio'),
    jsonb_build_object('role','brain')
  );

  for p in
    select mp.*,
           case when mp.id=i.project_id then 1.00 else 0.90 end as match_conf
    from public.memory_projects mp
    where mp.owner_key=i.owner_key
      and mp.status='active'
      and (
        mp.id=i.project_id
        or position(lower(mp.project_key) in v_text)>0
        or position(lower(coalesce(mp.canonical_name,mp.project_name)) in v_text)>0
        or exists (
          select 1
          from jsonb_array_elements_text(coalesce(mp.metadata->'aliases','[]'::jsonb)) a(alias)
          where length(alias)>=3 and position(lower(alias) in v_text)>0
        )
      )
  loop
    v_project_entity := public.memory_ensure_entity(
      i.owner_key,'project',coalesce(p.canonical_name,p.project_name),
      coalesce(array(select jsonb_array_elements_text(coalesce(p.metadata->'aliases','[]'::jsonb))),'{}'::text[]),
      jsonb_build_object('project_key',p.project_key,'project_id',p.id),
      jsonb_build_object('source','memory_items_auto_extract')
    );
    if not (v_project_entity = any(v_project_ids)) then
      v_project_ids:=array_append(v_project_ids,v_project_entity);
      v_project_count:=v_project_count+1;
    end if;
    insert into public.memory_item_entities(memory_item_id,entity_id,role,metadata)
    values(i.id,v_project_entity,'context_project',
      jsonb_build_object('confidence',p.match_conf,'source','auto_text_or_project_id'))
    on conflict(memory_item_id,entity_id,role) do update
      set metadata=public.memory_item_entities.metadata || excluded.metadata;
  end loop;

  for d in
    select gd.*
    from public.memory_graph_dictionary gd
    where gd.active=true
      and (
        position(lower(gd.canonical_name) in v_text)>0
        or exists(
          select 1 from unnest(gd.aliases) a
          where length(a)>=3 and position(lower(a) in v_text)>0
        )
      )
  loop
    v_term_entity := public.memory_ensure_entity(
      i.owner_key,d.entity_type,d.canonical_name,d.aliases,
      jsonb_build_object('dictionary_key',d.term_key),
      coalesce(d.metadata,'{}'::jsonb) || jsonb_build_object('auto_extracted',true)
    );
    v_term_count:=v_term_count+1;
    insert into public.memory_item_entities(memory_item_id,entity_id,role,metadata)
    values(i.id,v_term_entity,'mentioned',
      jsonb_build_object('confidence',d.confidence,'source','memory_graph_dictionary'))
    on conflict(memory_item_id,entity_id,role) do update
      set metadata=public.memory_item_entities.metadata || excluded.metadata;

    if cardinality(v_project_ids)>0 then
      foreach v_project_entity in array v_project_ids loop
        perform public.memory_link_entities_evidenced(
          i.owner_key,v_project_entity,d.relation_type,v_term_entity,d.confidence,i.id,
          jsonb_build_object('source','memory_item_auto_extract','source_item_id',i.id,'review_required',(d.confidence<0.80))
        );
        v_relation_count:=v_relation_count+1;
      end loop;
    else
      perform public.memory_link_entities_evidenced(
        i.owner_key,v_root_entity,'menciona',v_term_entity,d.confidence,i.id,
        jsonb_build_object('source','memory_item_auto_extract','source_item_id',i.id,'review_required',(d.confidence<0.80))
      );
      v_relation_count:=v_relation_count+1;
    end if;
  end loop;

  if i.memory_type in ('decision','task','constraint','rule','goal','technical_finding','project_idea') then
    v_role := case
      when i.memory_type='decision' then 'decision'
      when i.memory_type='task' then 'task'
      when i.memory_type='constraint' then 'constraint'
      when i.memory_type='rule' then 'rule'
      when i.memory_type='goal' then 'goal'
      when i.memory_type='technical_finding' then 'finding'
      when i.memory_type='project_idea' then 'idea'
      else 'statement'
    end;
    v_relation := case
      when v_role='decision' then 'tiene_decision'
      when v_role='task' then 'tiene_tarea'
      when v_role='constraint' then 'tiene_restriccion'
      when v_role='rule' then 'tiene_regla'
      when v_role='goal' then 'tiene_objetivo'
      when v_role='finding' then 'tiene_hallazgo'
      when v_role='idea' then 'tiene_idea'
      else 'contiene'
    end;
    v_conf:=least(greatest(coalesce(i.confidence,1),0),1);
    v_statement_name:=left(coalesce(nullif(btrim(i.title),''),nullif(btrim(i.summary),''),btrim(i.content)),180);

    v_statement_entity:=public.memory_ensure_entity(
      i.owner_key,v_role,v_statement_name,'{}'::text[],
      jsonb_build_object('memory_item_id',i.id),
      jsonb_build_object(
        'source','memory_item_auto_extract','source_item_id',i.id,
        'memory_type',i.memory_type,'category',i.category,
        'confidence',v_conf,'review_required',(v_conf<0.80),
        'graph_test',coalesce((i.metadata->>'graph_test')::boolean,false)
      )
    );
    v_statement_count:=1;
    insert into public.memory_item_entities(memory_item_id,entity_id,role,metadata)
    values(i.id,v_statement_entity,'statement',
      jsonb_build_object('confidence',v_conf,'source','memory_item_type'))
    on conflict(memory_item_id,entity_id,role) do update
      set metadata=public.memory_item_entities.metadata || excluded.metadata;

    if cardinality(v_project_ids)>0 then
      foreach v_project_entity in array v_project_ids loop
        perform public.memory_link_entities_evidenced(
          i.owner_key,v_project_entity,v_relation,v_statement_entity,v_conf,i.id,
          jsonb_build_object('source','memory_item_auto_extract','source_item_id',i.id,'review_required',(v_conf<0.80))
        );
        v_relation_count:=v_relation_count+1;
      end loop;
    else
      perform public.memory_link_entities_evidenced(
        i.owner_key,v_root_entity,v_relation,v_statement_entity,v_conf,i.id,
        jsonb_build_object('source','memory_item_auto_extract','source_item_id',i.id,'review_required',(v_conf<0.80))
      );
      v_relation_count:=v_relation_count+1;
    end if;
  end if;

  update public.memory_items
     set metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
       'graph_extracted_at',clock_timestamp(),
       'graph_projects',v_project_count,
       'graph_terms',v_term_count,
       'graph_statements',v_statement_count,
       'graph_relations',v_relation_count
     )
   where id=i.id;

  return jsonb_build_object(
    'ok',true,'item_id',i.id,'projects',v_project_count,'terms',v_term_count,
    'statements',v_statement_count,'relations',v_relation_count
  );
end;
$$;

create or replace function public.memory_auto_extract_graph_item()
returns trigger
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
begin
  if tg_op='UPDATE'
     and new.content is not distinct from old.content
     and new.title is not distinct from old.title
     and new.project_id is not distinct from old.project_id
     and new.memory_type is not distinct from old.memory_type
     and new.status is not distinct from old.status then
    return new;
  end if;
  begin
    perform public.memory_extract_graph_from_item(new.id);
  exception when others then
    insert into public.memory_events(owner_key,event_type,actor,details)
    values(coalesce(new.owner_key,'duilio'),'graph_auto_extract_error','memory_auto_extract_graph_item',
      jsonb_build_object('memory_item_id',new.id,'sqlstate',sqlstate,'error',sqlerrm));
  end;
  return new;
end;
$$;

drop trigger if exists trg_memory_items_auto_extract_graph on public.memory_items;
create trigger trg_memory_items_auto_extract_graph
after insert or update of content,title,project_id,memory_type,status
on public.memory_items
for each row execute function public.memory_auto_extract_graph_item();

revoke execute on function public.memory_link_entities_evidenced(text,uuid,text,uuid,numeric,uuid,jsonb) from public,anon,authenticated;
revoke execute on function public.memory_extract_graph_from_item(uuid) from public,anon,authenticated;
revoke execute on function public.memory_auto_extract_graph_item() from public,anon,authenticated;
grant execute on function public.memory_link_entities_evidenced(text,uuid,text,uuid,numeric,uuid,jsonb) to service_role;
grant execute on function public.memory_extract_graph_from_item(uuid) to service_role;
grant execute on function public.memory_auto_extract_graph_item() to service_role;

-- Rollback de emergencia (manual):
-- drop trigger if exists trg_memory_items_auto_extract_graph on public.memory_items;
-- drop function if exists public.memory_auto_extract_graph_item();
-- drop function if exists public.memory_extract_graph_from_item(uuid);
-- drop function if exists public.memory_link_entities_evidenced(text,uuid,text,uuid,numeric,uuid,jsonb);
-- drop table if exists public.memory_graph_dictionary;
