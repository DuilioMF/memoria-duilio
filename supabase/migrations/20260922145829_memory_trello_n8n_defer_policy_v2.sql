create or replace function public.memory_trello_is_n8n_deferred(p_title text,p_content text default null)
returns boolean language sql immutable set search_path to '' as $function$
select lower(coalesce(p_title,'')) like '%n8n%';
$function$;

create or replace function public.memory_enqueue_trello_card(
 p_memory_item_id uuid,p_priority smallint default 50,p_prefer_executor text default null,p_exclude_n8n boolean default true)
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $function$
declare m public.memory_items%rowtype; v_project_key text; v_card_url text; v_existing public.memory_execution_queue%rowtype; v_task_type text; v_executor text;
begin
 if p_priority<0 or p_priority>100 then raise exception 'priority out of range'; end if;
 select * into m from public.memory_items where id=p_memory_item_id and owner_key='duilio' and status='active' and category='trello_card' for update;
 if not found then raise exception 'active trello card memory item not found'; end if;
 if coalesce(m.metadata->>'list_name','') not in('Por hacer','En ejecución') then return jsonb_build_object('ok',false,'reason','trello_list_not_executable','list_name',m.metadata->>'list_name'); end if;
 if p_exclude_n8n and public.memory_trello_is_n8n_deferred(m.title,m.content) then return jsonb_build_object('ok',false,'reason','n8n_deferred_by_policy','memory_item_id',m.id); end if;
 v_card_url:=regexp_replace(coalesce(m.metadata->>'card_url',''),'/[0-9]+-.*$','');
 if v_card_url='' then return jsonb_build_object('ok',false,'reason','missing_card_url','memory_item_id',m.id); end if;
 select * into v_existing from public.memory_execution_queue where card_url=v_card_url and state not in('completed','failed','cancelled') order by created_at desc limit 1;
 if found then return jsonb_build_object('ok',true,'duplicate',true,'queue_id',v_existing.id,'state',v_existing.state,'executor_key',v_existing.executor_key); end if;
 v_project_key:=public.memory_resolve_trello_project(m.id);
 v_task_type:=public.memory_classify_task(coalesce(m.title,'')||E'\n'||coalesce(m.content,''));
 v_executor:=p_prefer_executor;
 if p_exclude_n8n and v_executor is null then v_executor:=case when v_task_type in('code','multi_step') then 'chatgpt-work' else 'chatgpt-chat' end; end if;
 return public.memory_orchestrate_request(coalesce(m.title,'')||E'\n'||coalesce(m.content,''),v_project_key,v_card_url,v_executor,p_priority)
 || jsonb_build_object('source_memory_item_id',m.id,'trello_list',m.metadata->>'list_name','intake','trello_v2');
end;
$function$;
revoke execute on function public.memory_enqueue_trello_card(uuid,smallint,text,boolean) from public,anon,authenticated;
grant execute on function public.memory_enqueue_trello_card(uuid,smallint,text,boolean) to service_role;

create or replace view public.memory_trello_execution_candidates_v with (security_invoker=true) as
select m.id memory_item_id,public.memory_resolve_trello_project(m.id) project_key,m.title,m.metadata->>'list_name' list_name,
regexp_replace(coalesce(m.metadata->>'card_url',''),'/[0-9]+-.*$','') card_url,m.metadata->>'last_activity_at' last_activity_at,
public.memory_trello_is_n8n_deferred(m.title,m.content) deferred_n8n,
exists(select 1 from public.memory_execution_queue q where q.card_url=regexp_replace(coalesce(m.metadata->>'card_url',''),'/[0-9]+-.*$','') and q.state not in('completed','failed','cancelled')) already_queued
from public.memory_items m where m.owner_key='duilio' and m.status='active' and m.category='trello_card'
and coalesce(m.metadata->>'list_name','') in('Por hacer','En ejecución');
revoke all on public.memory_trello_execution_candidates_v from public,anon,authenticated;
grant select on public.memory_trello_execution_candidates_v to service_role;
