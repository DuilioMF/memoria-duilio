-- Trello -> Router/Queue intake v1.
create or replace function public.memory_resolve_trello_project(p_memory_item_id uuid)
returns text
language plpgsql
stable
set search_path to 'public','pg_temp'
as $function$
declare m public.memory_items%rowtype; v_label text; v_project text;
begin
  select * into m from public.memory_items
  where id=p_memory_item_id and owner_key='duilio' and category='trello_card';
  if not found then return null; end if;
  if lower(coalesce(m.title,'')) like '%capitán rodolfo%' or lower(coalesce(m.title,'')) like '%capitan rodolfo%' then return 'capitan-rodolfo'; end if;
  if lower(coalesce(m.title,'')) like '%rubén%' or lower(coalesce(m.title,'')) like '%ruben%' then return 'ruben'; end if;
  select x->>'name' into v_label
  from jsonb_array_elements(coalesce(m.metadata->'labels','[]'::jsonb)) x
  where coalesce(x->>'name','')<>''
  order by case lower(x->>'name')
    when 'memoria duilio' then 1 when 'doinglio' then 2 when 'supervision' then 3
    when 'revalsoftia saas' then 4 when 'reloj feli' then 5 else 10 end
  limit 1;
  if v_label is not null then
    v_project:=case lower(v_label)
      when 'memoria duilio' then 'memoria-duilio'
      when 'doinglio' then 'doinglio'
      when 'supervision' then 'supervision'
      when 'revalsoftia saas' then 'revalsoftia-saas'
      when 'reloj feli' then 'feli-salud'
      else null end;
  end if;
  if v_project is null and v_label is not null then
    select project_key into v_project from public.memory_projects p
    where p.owner_key='duilio' and p.status='active'
      and (lower(p.project_name)=lower(v_label) or lower(p.project_key)=lower(v_label)
        or exists(select 1 from unnest(coalesce(p.aliases,array[]::text[])) a where lower(a)=lower(v_label)))
    limit 1;
  end if;
  return coalesce(v_project,'memoria-duilio');
end;
$function$;

create or replace function public.memory_enqueue_trello_card(
  p_memory_item_id uuid,p_priority smallint default 50,p_prefer_executor text default null,p_exclude_n8n boolean default true)
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $function$
declare m public.memory_items%rowtype; v_project_key text; v_card_url text; v_existing public.memory_execution_queue%rowtype; v_task_type text; v_executor text;
begin
  if p_priority<0 or p_priority>100 then raise exception 'priority out of range'; end if;
  select * into m from public.memory_items where id=p_memory_item_id and owner_key='duilio' and status='active' and category='trello_card' for update;
  if not found then raise exception 'active trello card memory item not found'; end if;
  if coalesce(m.metadata->>'list_name','') not in ('Por hacer','En ejecución') then
    return jsonb_build_object('ok',false,'reason','trello_list_not_executable','list_name',m.metadata->>'list_name');
  end if;
  if p_exclude_n8n and (lower(coalesce(m.title,'')) like '%n8n%' or lower(coalesce(m.content,'')) like '%n8n%') then
    return jsonb_build_object('ok',false,'reason','n8n_deferred_by_policy','memory_item_id',m.id);
  end if;
  v_card_url:=regexp_replace(coalesce(m.metadata->>'card_url',''), '/[0-9]+-.*$', '');
  if v_card_url='' then return jsonb_build_object('ok',false,'reason','missing_card_url','memory_item_id',m.id); end if;
  select * into v_existing from public.memory_execution_queue
  where card_url=v_card_url and state not in ('completed','failed','cancelled') order by created_at desc limit 1;
  if found then return jsonb_build_object('ok',true,'duplicate',true,'queue_id',v_existing.id,'state',v_existing.state,'executor_key',v_existing.executor_key); end if;
  v_project_key:=public.memory_resolve_trello_project(m.id);
  v_task_type:=public.memory_classify_task(coalesce(m.title,'')||E'\n'||coalesce(m.content,''));
  v_executor:=p_prefer_executor;
  if p_exclude_n8n and v_executor is null then v_executor:=case when v_task_type in ('code','multi_step') then 'chatgpt-work' else 'chatgpt-chat' end; end if;
  return public.memory_orchestrate_request(coalesce(m.title,'')||E'\n'||coalesce(m.content,''),v_project_key,v_card_url,v_executor,p_priority)
    || jsonb_build_object('source_memory_item_id',m.id,'trello_list',m.metadata->>'list_name','intake','trello_v1');
end;
$function$;

create or replace view public.memory_trello_execution_candidates_v with (security_invoker=true) as
select m.id memory_item_id,public.memory_resolve_trello_project(m.id) project_key,m.title,m.metadata->>'list_name' list_name,
regexp_replace(coalesce(m.metadata->>'card_url',''), '/[0-9]+-.*$', '') card_url,m.metadata->>'last_activity_at' last_activity_at,
(lower(coalesce(m.title,'')) like '%n8n%' or lower(coalesce(m.content,'')) like '%n8n%') deferred_n8n,
exists(select 1 from public.memory_execution_queue q where q.card_url=regexp_replace(coalesce(m.metadata->>'card_url',''), '/[0-9]+-.*$', '') and q.state not in ('completed','failed','cancelled')) already_queued
from public.memory_items m
where m.owner_key='duilio' and m.status='active' and m.category='trello_card' and coalesce(m.metadata->>'list_name','') in ('Por hacer','En ejecución');
