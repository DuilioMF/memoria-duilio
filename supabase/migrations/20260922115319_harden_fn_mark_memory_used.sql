-- Applied in Supabase as migration 20260922115319_harden_fn_mark_memory_used
-- Tracks only memory items that were actually used in a response.
-- Deduplicates IDs, scopes updates by owner/project, and records actual usage evidence.

create or replace function public.fn_mark_memory_used(
  p_memory_item_ids uuid[],
  p_owner_key text default 'duilio',
  p_actor text default 'chatgpt',
  p_action text default 'retrieved',
  p_project_id uuid default null
)
returns table(
  out_memory_item_id uuid,
  out_use_count integer,
  out_last_used_at timestamptz
)
language plpgsql
set search_path to 'public'
as $function$
begin
  if p_memory_item_ids is null or array_length(p_memory_item_ids,1) is null then
    return;
  end if;

  return query
  with input_ids as (
    select distinct unnest(p_memory_item_ids) as id
  ),
  updated as (
    update public.memory_items mi
    set use_count = mi.use_count + 1,
        last_used_at = now()
    from input_ids i
    where mi.id = i.id
      and mi.owner_key = p_owner_key
      and (p_project_id is null or mi.project_id = p_project_id)
    returning mi.id, mi.use_count, mi.last_used_at
  ),
  logged_events as (
    insert into public.memory_events(
      owner_key,event_type,memory_item_id,actor,details
    )
    select
      p_owner_key,
      'accessed',
      u.id,
      p_actor,
      jsonb_build_object(
        'action',p_action,
        'project_id',p_project_id,
        'usage_tracking','actual_use'
      )
    from updated u
    returning id
  ),
  logged_retrieval as (
    insert into public.memory_retrieval_events(
      owner_key,project_id,action,result_count
    )
    select p_owner_key,p_project_id,p_action,count(*)::integer
    from updated
    having count(*) > 0
    returning id
  )
  select u.id,u.use_count,u.last_used_at
  from updated u;
end;
$function$;

comment on function public.fn_mark_memory_used(uuid[],text,text,text,uuid)
is 'Marca uso real de memory_items. Deduplica IDs, restringe por owner/proyecto, incrementa use_count y registra eventos sólo para items efectivamente actualizados.';
