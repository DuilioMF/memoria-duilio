-- Fase 10: attach an explicit bounded, verified dispatch contract to an EXISTING queue job.
-- Fail closed; this function does not enqueue, claim, enable any executor, or dispatch.
create or replace function public.memory_prepare_github_proposal(
  p_queue_id uuid, p_run_key text, p_title text, p_problem text,
  p_allowed_files text[], p_acceptance_criteria text[] default '{}'::text[]
) returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  q public.memory_execution_queue%rowtype;
  v_run public.memory_scheduled_runs%rowtype;
  v_task jsonb;
  v_file text;
  v_criterion text;
begin
  if p_queue_id is null or p_run_key !~ '^AUTO-[0-9]{8}-[0-9]{4}$' then
    raise exception 'real queue id and daily run key required';
  end if;
  if length(btrim(coalesce(p_title,''))) not between 1 and 300
     or length(btrim(coalesce(p_problem,''))) not between 1 and 12000 then
    raise exception 'bounded nonempty title and problem required';
  end if;
  if coalesce(array_length(p_allowed_files,1),0) not between 1 and 3
     or coalesce(array_length(p_acceptance_criteria,1),0)>8
     or array_position(p_allowed_files,null) is not null
     or array_position(p_acceptance_criteria,null) is not null then
    raise exception 'invalid allowed file or acceptance-criterion count';
  end if;
  if (select count(distinct f) from unnest(p_allowed_files) f)
     <> array_length(p_allowed_files,1) then
    raise exception 'allowed files must be unique';
  end if;
  foreach v_file in array p_allowed_files loop
    if v_file !~ '^(ui|docs)/[A-Za-z0-9_./-]+$'
       or v_file like '%..%' or v_file like '%//%'
       or v_file = 'ui/config.js'
       or v_file like 'docs/executable-cards/%'
       or v_file ~* '\.(env|key|pem)$' then
      raise exception 'disallowed source path';
    end if;
  end loop;
  foreach v_criterion in array p_acceptance_criteria loop
    if length(v_criterion)>400 then raise exception 'criterion too long'; end if;
  end loop;

  select * into v_run from public.memory_scheduled_runs
  where run_key=p_run_key and owner_key='duilio'
    and schedule_key='memoria-duilio-0800'
    and status in ('running','started')
    and last_heartbeat_at>clock_timestamp()-interval '5 minutes'
  order by started_at desc limit 1;
  if not found then raise exception 'active heartbeat from natural MD 0800 run required'; end if;

  select * into q from public.memory_execution_queue where id=p_queue_id for update;
  if not found or q.executor_key<>'github-actions-md'
    or q.state not in ('needs_adapter','ready') then
    raise exception 'only an unclaimed GitHub proposal queue job can be prepared';
  end if;
  if q.card_url !~ '^https://trello\.com/c/[A-Za-z0-9]+$' then
    raise exception 'canonical Trello card URL required';
  end if;
  if not exists (
    select 1 from public.memory_projects p
    where p.id=q.project_id and p.owner_key='duilio'
      and p.project_key='memoria-duilio' and p.status='active'
  ) then raise exception 'wrong project'; end if;
  if not exists (
    select 1 from public.memory_items m
    where m.owner_key='duilio' and m.status='active'
      and m.category='trello_card'
      and regexp_replace(coalesce(m.metadata->>'card_url',''),'/[0-9]+-.*$','')=q.card_url
      and m.metadata->>'list_name'='Por hacer'
      and m.updated_at>clock_timestamp()-interval '2 hours'
  ) then raise exception 'recent eligible Trello card snapshot required'; end if;

  v_task := jsonb_build_object(
    'queue_id',q.id,'card_url',q.card_url,
    'project_key','memoria-duilio','run_key',p_run_key,
    'title',btrim(p_title),'problem',btrim(p_problem),
    'allowed_files',to_jsonb(p_allowed_files),
    'acceptance_criteria',to_jsonb(p_acceptance_criteria)
  );
  if q.metadata ? 'dispatch_task' then
    if q.metadata->'dispatch_task'=v_task then
      return jsonb_build_object('ok',true,'duplicate',true,'queue_id',q.id);
    end if;
    raise exception 'already prepared with a different bounded task';
  end if;
  update public.memory_execution_queue
    set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('dispatch_task',v_task),
        updated_at=clock_timestamp()
    where id=q.id;
  return jsonb_build_object('ok',true,'prepared',true,'queue_id',q.id,
    'run_key',p_run_key,'dispatch_ready',false,
    'note','No GitHub dispatch or heartbeat occurs in this function');
end
$$;
revoke all on function public.memory_prepare_github_proposal(uuid,text,text,text,text[],text[]) from public,anon,authenticated;
grant execute on function public.memory_prepare_github_proposal(uuid,text,text,text,text[],text[]) to service_role;
