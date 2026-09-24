-- Memoria Duilio 0.6.4: Trello project presentation + strict execution routing.
-- Trello title changes are maintained in Trello activity; this migration protects
-- the backend registry and prevents a rename from creating duplicate memories.
update public.memory_items
set subject_key='trello_card:'||substring(metadata->>'card_url' from '^https?://trello[.]com/c/[^/]+'),
    fingerprint=md5('trello|'||substring(metadata->>'card_url' from '^https?://trello[.]com/c/[^/]+')),
    metadata=metadata||jsonb_build_object(
      'trello_original_url',coalesce(metadata->>'trello_original_url',metadata->>'card_url'),
      'card_url',substring(metadata->>'card_url' from '^https?://trello[.]com/c/[^/]+'),
      'trello_identity_scheme','shortlink_v1'),
    updated_at=clock_timestamp()
where owner_key='duilio' and category='trello_card' and status='active'
  and metadata->>'card_url' ~ '^https?://trello[.]com/c/[^/]+';

update public.memory_projects p
set metadata=coalesce(p.metadata,'{}'::jsonb)||jsonb_build_object(
  'trello',jsonb_strip_nulls(jsonb_build_object(
    'title_prefix',v.title_prefix,
    'label_name',v.label_name,
    'label_color',v.label_color,
    'label_id',case when v.label_object_id is not null then
      'ari:cloud:trello::label/workspace/5fa44242375608633d50f8a2/'||v.label_object_id else null end,
    'inherited_from',v.inherited_from))),
    updated_at=clock_timestamp()
from (values
('memoria-duilio','Memoria Duilio','Memoria Duilio','yellow','6aa35638b2a5a021d29b654d',null),
('doinglio','DoingLio','DoingLio','blue','6aa35638b2a5a021d29b6551',null),
('capitan-rodolfo','Capitán Rodolfo','DoingLio','blue','6aa35638b2a5a021d29b6551','doinglio'),
('ruben','Ruben','DoingLio','blue','6aa35638b2a5a021d29b6551','doinglio'),
('supervision','Supervisión','Supervision','pink_light','6aae8c76564feb22c6f771ac',null),
('revalsoftia-saas','RevalSoftIA SaaS','RevalSoftIA SaaS','orange','6aa35638b2a5a021d29b654e',null),
('feli-salud','Reloj Feli','Reloj Feli','red','6aa35638b2a5a021d29b654f',null),
('conexion','Proyecto Conexión',null,null,null,null)
) as v(project_key,title_prefix,label_name,label_color,label_object_id,inherited_from)
where p.project_key=v.project_key and p.owner_key='duilio' and p.status='active';

CREATE OR REPLACE FUNCTION public.memory_resolve_trello_project(p_memory_item_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  m public.memory_items%rowtype;
  v_project text;
  v_labels jsonb;
  v_label_count integer;
begin
  select * into m from public.memory_items
  where id=p_memory_item_id and owner_key='duilio' and category='trello_card';
  if not found then return null; end if;

  -- A two-project idea cannot silently turn into a single-project task.
  if lower(m.title) like 'supervisión / reloj feli%' then return null; end if;

  -- The canonical title prefix is authoritative, even if a child inherits
  -- the parent DoingLio label, so no child is routed to the parent.
  select p.project_key into v_project
    from public.memory_projects p
   where p.owner_key='duilio' and p.status='active'
     and p.metadata->'trello'->>'title_prefix' is not null
     and left(lower(btrim(m.title)),length(lower(p.metadata->'trello'->>'title_prefix')))
         = lower(p.metadata->'trello'->>'title_prefix')
   order by length(p.metadata->'trello'->>'title_prefix') desc,p.project_key
   limit 1;
  if v_project is not null then return v_project; end if;

  v_labels:=coalesce(m.metadata->'labels','[]'::jsonb);
  select count(*) into v_label_count
  from jsonb_array_elements(v_labels) x
  where coalesce(x->>'name','') <> ''
    and lower(x->>'name') not in ('control ejecución');

  if v_label_count>1 then return null; end if;

  select p.project_key into v_project
  from public.memory_projects p
  join lateral jsonb_array_elements(v_labels) l on
       lower(coalesce(l->>'name','')) = lower(coalesce(p.metadata->'trello'->>'label_name','~'))
  where p.owner_key='duilio' and p.status='active'
    and p.metadata->'trello'->>'inherited_from' is null
  order by p.project_key limit 1;

  -- No default to Memoria Duilio for an unrelated/unregistered card.
  return v_project;
end;
$function$


create or replace view public.memory_trello_presentation_audit_v
with (security_invoker=true)
as
 SELECT m.id AS memory_item_id,
    m.title,
    m.metadata ->> 'card_url'::text AS card_url,
    m.metadata ->> 'list_name'::text AS list_name,
    m.metadata -> 'labels'::text AS actual_labels,
    r.project_key,
    (p.metadata -> 'trello'::text) ->> 'title_prefix'::text AS expected_title_prefix,
    (p.metadata -> 'trello'::text) ->> 'label_name'::text AS expected_label,
    (p.metadata -> 'trello'::text) ->> 'label_color'::text AS expected_color,
        CASE
            WHEN r.project_key IS NULL AND lower(m.title) ~~ 'supervisión / reloj feli%'::text THEN 'multi_project'::text
            WHEN r.project_key IS NULL THEN 'unresolved_project'::text
            WHEN COALESCE((p.metadata -> 'trello'::text) ->> 'title_prefix'::text, ''::text) <> ''::text AND "left"(lower(btrim(m.title)), length(lower((p.metadata -> 'trello'::text) ->> 'title_prefix'::text))) <> lower((p.metadata -> 'trello'::text) ->> 'title_prefix'::text) THEN 'missing_project_prefix'::text
            WHEN COALESCE((p.metadata -> 'trello'::text) ->> 'label_name'::text, ''::text) <> ''::text AND NOT (EXISTS ( SELECT 1
               FROM jsonb_array_elements(COALESCE(m.metadata -> 'labels'::text, '[]'::jsonb)) x(value)
              WHERE lower(x.value ->> 'name'::text) = lower((p.metadata -> 'trello'::text) ->> 'label_name'::text))) THEN 'missing_project_label'::text
            ELSE 'ok'::text
        END AS issue
   FROM memory_items m
     CROSS JOIN LATERAL ( SELECT memory_resolve_trello_project(m.id) AS project_key) r
     LEFT JOIN memory_projects p ON p.project_key = r.project_key AND p.owner_key = m.owner_key AND p.status = 'active'::text
  WHERE m.owner_key = 'duilio'::text AND m.category = 'trello_card'::text AND m.status = 'active'::text;
revoke all on public.memory_trello_presentation_audit_v from public,anon,authenticated;
grant select on public.memory_trello_presentation_audit_v to service_role;

CREATE OR REPLACE FUNCTION public.memory_trello_presentation_issues()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
select jsonb_build_object(
 'issue_count',count(*) filter(where issue not in ('ok','multi_project')),
 'multi_project_ideas',count(*) filter(where issue='multi_project'),
 'issues',coalesce(jsonb_agg(jsonb_build_object(
   'title',title,'card_url',card_url,'list_name',list_name,
   'issue',issue,'expected_label',expected_label
 ) order by title) filter(where issue not in ('ok','multi_project')),'[]'::jsonb)
)
from public.memory_trello_presentation_audit_v;
$function$

revoke execute on function public.memory_trello_presentation_issues() from public,anon,authenticated;
grant execute on function public.memory_trello_presentation_issues() to service_role;

CREATE OR REPLACE FUNCTION public.memory_sync_trello_cards(p_cards jsonb, p_board_url text DEFAULT 'https://trello.com/b/4sGARptV/memoria-duilio-proyectos-y-ejecuci%C3%B3n'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_project_id uuid;
  v_card jsonb;
  v_subject text;
  v_url text;
  v_seen text[] := array[]::text[];
  v_inserted int := 0;
  v_updated int := 0;
  v_archived int := 0;
  v_existing uuid;
  v_list text;
  v_rank int;
begin
  if p_cards is null or jsonb_typeof(p_cards) <> 'array' then
    raise exception 'p_cards must be a json array';
  end if;

  select id into v_project_id
  from public.memory_projects
  where owner_key='duilio' and project_key='memoria-duilio' and status='active'
  limit 1;

  if v_project_id is null then
    raise exception 'active memoria-duilio project not found';
  end if;

  for v_card in select value from jsonb_array_elements(p_cards)
  loop
    v_url := nullif(trim(v_card->>'url'),'');
    if v_url is null then continue; end if;
    -- Stable identity: Trello slug changes with a rename, short link remains.
    v_url := substring(v_url from '^https?://trello[.]com/c/[^/]+');
    if v_url is null then continue; end if;
    v_subject := 'trello_card:' || v_url;
    v_seen := array_append(v_seen, v_subject);
    v_list := coalesce(nullif(trim(v_card->>'list_name'),''),'Sin lista');
    v_rank := case v_list
      when 'Ideas' then 10
      when 'Por hacer' then 20
      when 'En ejecución' then 30
      when 'Espera de vos' then 40
      when 'En prueba' then 50
      when 'Verificado y cerrado' then 60
      else 99 end;

    select id into v_existing
    from public.memory_items
    where owner_key='duilio'
      and project_id=v_project_id
      and subject_key=v_subject
      and status='active'
    limit 1;

    if v_existing is null then
      insert into public.memory_items(
        owner_key,project_id,memory_type,category,title,content,summary,
        importance,confidence,status,fingerprint,metadata,claim_state,subject_key,
        valid_from,created_at,updated_at
      ) values (
        'duilio',v_project_id,'task','trello_card',coalesce(v_card->>'name','Tarjeta Trello'),
        coalesce(v_card->>'desc',''),v_list,
        case when v_list in ('En ejecución','Espera de vos') then 9 when v_list='Por hacer' then 8 else 6 end,
        1,'active',md5('trello|'||v_url),
        jsonb_build_object(
          'source','trello','board_url',p_board_url,'card_url',v_url,'list_name',v_list,
          'list_rank',v_rank,'last_activity_at',v_card->>'last_activity_at','due',v_card->>'due',
          'due_complete',coalesce((v_card->>'due_complete')::boolean,false),'labels',coalesce(v_card->'labels','[]'::jsonb),
          'synced_at',clock_timestamp()
        ),'recorded',v_subject,clock_timestamp(),clock_timestamp(),clock_timestamp()
      );
      v_inserted := v_inserted + 1;
    else
      update public.memory_items
      set title=coalesce(v_card->>'name',title),
          content=coalesce(v_card->>'desc',content),
          summary=v_list,
          importance=case when v_list in ('En ejecución','Espera de vos') then 9 when v_list='Por hacer' then 8 else 6 end,
          confidence=1,
          metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
            'source','trello','board_url',p_board_url,'card_url',v_url,'list_name',v_list,
            'list_rank',v_rank,'last_activity_at',v_card->>'last_activity_at','due',v_card->>'due',
            'due_complete',coalesce((v_card->>'due_complete')::boolean,false),'labels',coalesce(v_card->'labels','[]'::jsonb),
            'synced_at',clock_timestamp()
          ),
          updated_at=clock_timestamp()
      where id=v_existing;
      v_updated := v_updated + 1;
    end if;
  end loop;

  if coalesce(array_length(v_seen,1),0) > 0 then
    update public.memory_items
    set status='archived', valid_until=clock_timestamp(), updated_at=clock_timestamp(),
        metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object('archived_by_sync_at',clock_timestamp())
    where owner_key='duilio' and project_id=v_project_id and category='trello_card' and status='active'
      and metadata->>'board_url'=p_board_url
      and not (subject_key = any(v_seen));
    get diagnostics v_archived = row_count;
  end if;

  update public.memory_projects
  set last_event_at=clock_timestamp(),
      metadata=coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
        'trello_sync',jsonb_build_object('board_url',p_board_url,'last_sync_at',clock_timestamp(),'card_count',jsonb_array_length(p_cards))
      ),
      updated_at=clock_timestamp()
  where id=v_project_id;

  return jsonb_build_object('ok',true,'cards',jsonb_array_length(p_cards),'inserted',v_inserted,'updated',v_updated,'archived',v_archived,'board_url',p_board_url)
    || jsonb_build_object('presentation_audit', public.memory_trello_presentation_issues());
end
$function$


CREATE OR REPLACE FUNCTION public.memory_enqueue_trello_card(p_memory_item_id uuid, p_priority smallint DEFAULT 50, p_prefer_executor text DEFAULT NULL::text, p_exclude_n8n boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  m public.memory_items%rowtype;
  v_project_key text;
  v_card_url text;
  v_existing public.memory_execution_queue%rowtype;
  v_task_type text;
  v_executor text;
begin
  if p_priority<0 or p_priority>100 then raise exception 'priority out of range'; end if;

  select * into m
  from public.memory_items
  where id=p_memory_item_id
    and owner_key='duilio'
    and status='active'
    and category='trello_card'
  for update;

  if not found then raise exception 'active trello card memory item not found'; end if;

  if coalesce(m.metadata->>'list_name','') not in ('Por hacer','En ejecución') then
    return jsonb_build_object('ok',false,'reason','trello_list_not_executable','list_name',m.metadata->>'list_name');
  end if;

  if p_exclude_n8n and public.memory_trello_is_n8n_deferred(m.title,m.content) then
    return jsonb_build_object('ok',false,'reason','n8n_deferred_by_policy','memory_item_id',m.id);
  end if;

  v_card_url := regexp_replace(coalesce(m.metadata->>'card_url',''), '/[0-9]+-.*$', '');
  if v_card_url='' then
    return jsonb_build_object('ok',false,'reason','missing_card_url','memory_item_id',m.id);
  end if;

  select * into v_existing
  from public.memory_execution_queue
  where card_url=v_card_url
    and state not in ('completed','failed','cancelled')
  order by created_at desc
  limit 1;

  if found then
    return jsonb_build_object('ok',true,'duplicate',true,'queue_id',v_existing.id,'state',v_existing.state,'executor_key',v_existing.executor_key);
  end if;

  v_project_key := public.memory_resolve_trello_project(m.id);
  if v_project_key is null then
    return jsonb_build_object(
      'ok',false,'reason','trello_project_unresolved',
      'memory_item_id',m.id,'card_url',v_card_url,
      'title',m.title,
      'hint','Assign a known canonical project/title and its Trello label before enqueueing.'
    );
  end if;
  v_task_type := public.memory_classify_task(coalesce(m.title,'')||E'\n'||coalesce(m.content,''));

  v_executor := p_prefer_executor;
  if p_exclude_n8n and v_executor is null then
    v_executor := case when v_task_type in ('code','multi_step') then 'chatgpt-work' else 'chatgpt-chat' end;
  end if;

  return public.memory_orchestrate_request(
    coalesce(m.title,'')||E'\n'||coalesce(m.content,''),
    v_project_key,v_card_url,v_executor,p_priority
  ) || jsonb_build_object(
    'source_memory_item_id',m.id,
    'trello_list',m.metadata->>'list_name',
    'intake','trello_v2'
  );
end;
$function$

