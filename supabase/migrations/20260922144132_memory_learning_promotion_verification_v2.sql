-- 20260922144132_memory_learning_promotion_verification_v2
-- Candidate promotion now requires a real row in memory_verifications.

create or replace function public.memory_promote_knowledge_candidates(p_owner_key text default 'duilio')
returns jsonb
language plpgsql
security definer
set search_path to 'public','pg_temp'
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
  for r in select * from public.memory_knowledge
    where owner_key=p_owner_key and status='candidate' order by created_at
  loop
    update public.memory_knowledge
       set score=public.memory_calculate_knowledge_score(success_count,failure_count,partial_count,use_count,confidence,last_used_at),
           updated_at=now()
     where id=r.id returning * into r;
    v_scored:=v_scored+1;
    v_ratio:=case when coalesce(r.use_count,0)>0 then r.success_count::numeric/r.use_count::numeric else 0 end;
    select exists(
      select 1
      from public.memory_knowledge_experiences ke
      join public.memory_verifications v on v.experience_id=ke.experience_id
      where ke.knowledge_id=r.id and v.owner_key=p_owner_key and v.result='success'
    ) into v_verified;
    v_old_status:=r.status;
    if r.failure_count>=2 then
      update public.memory_knowledge
         set status='deprecated',
             metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
               'deprecated_by_policy','failure_count_gte_2',
               'replacement_link_required',supersedes_id is null
             ),
             updated_at=now()
       where id=r.id;
      insert into public.memory_events(owner_key,event_type,actor,details)
      values(p_owner_key,'knowledge_status_changed','memory_promote_knowledge_candidates',
        jsonb_build_object('knowledge_id',r.id,'from_status',v_old_status,'to_status','deprecated','reason','failure_count_gte_2','failure_count',r.failure_count,'supersedes_id',r.supersedes_id));
      v_deprecated:=v_deprecated+1;
    elsif r.evidence_count>=2 and v_ratio>=0.8 and v_verified then
      update public.memory_knowledge
         set status='active',
             last_validated_at=coalesce(last_validated_at,now()),
             metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
               'promoted_by_policy','candidate_v2',
               'promotion_success_ratio',v_ratio,
               'promotion_verified_evidence',true
             ),
             updated_at=now()
       where id=r.id;
      insert into public.memory_events(owner_key,event_type,actor,details)
      values(p_owner_key,'knowledge_status_changed','memory_promote_knowledge_candidates',
        jsonb_build_object('knowledge_id',r.id,'from_status',v_old_status,'to_status','active','evidence_count',r.evidence_count,'success_ratio',v_ratio,'verified_evidence',true));
      v_promoted:=v_promoted+1;
    end if;
  end loop;
  return jsonb_build_object('owner_key',p_owner_key,'policy','candidate_v2','scored',v_scored,'promoted',v_promoted,'deprecated',v_deprecated,'ran_at',now());
end
$function$;

create or replace view public.memory_learning_verification_backlog_v
with (security_invoker=true)
as
select
  e.id as experience_id,p.project_key,p.project_name,e.problem_type,e.outcome,
  e.learning_status,e.quality_score,e.confidence,e.occurred_at,e.evidence,e.metadata,
  case
    when e.outcome='unknown' then 'classify_outcome'
    when not exists(select 1 from public.memory_verifications v where v.experience_id=e.id) then 'needs_verification'
    else 'ready_to_learn'
  end as next_action
from public.memory_experiences e
left join public.memory_projects p on p.id=e.project_id
where e.owner_key='duilio' and e.learning_status in ('pending','error')
order by case when e.outcome='unknown' then 0 else 1 end,e.occurred_at;
