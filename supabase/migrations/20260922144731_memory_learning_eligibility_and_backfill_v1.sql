create or replace function public.memory_experience_is_learnable(p_experience_id uuid)
returns boolean language sql stable set search_path to 'public','pg_temp' as $function$
select case
 when e.id is null then false
 when e.problem_type like 'execution:%' then true
 when e.problem_type in ('sql_pattern','integration_gotcha','business_rule_ypf','n8n_limitation','architecture','completion_without_live_e2e','evidence_based_learning','brain_architecture_integration','phase3_test','phase5_e2e_test') then true
 when e.problem_type='project_activity' and (e.metadata?'canonical_version' or e.metadata?'version_authority' or e.metadata?'source_system') then false
 else false end
from public.memory_experiences e where e.id=p_experience_id;
$function$;

create or replace function public.memory_classify_nonlearnable_observations(p_owner_key text default 'duilio')
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $function$
declare v_count integer;
begin
 update public.memory_experiences e set learning_status='observed',
   metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('learning_disposition','not_reusable_knowledge','learning_disposition_at',now()),updated_at=now()
 where e.owner_key=p_owner_key and e.learning_status='pending'
   and public.memory_experience_is_learnable(e.id)=false and e.problem_type='project_activity'
   and (e.metadata?'canonical_version' or e.metadata?'version_authority' or e.metadata?'source_system');
 get diagnostics v_count=row_count;
 return jsonb_build_object('owner_key',p_owner_key,'classified_observations',v_count,'ran_at',now());
end;
$function$;

create or replace function public.memory_learn_pending_experiences(p_limit integer default 100)
returns table(experience_id uuid,knowledge_id uuid)
language plpgsql security definer set search_path to 'public','pg_temp' as $function$
declare r record; v_knowledge_id uuid;
begin
 for r in select e.id from public.memory_experiences e
   where e.learning_status='pending' and public.memory_experience_is_learnable(e.id)=true
   and exists(select 1 from public.memory_verifications v where v.experience_id=e.id)
   order by e.occurred_at asc limit greatest(1,least(coalesce(p_limit,100),1000))
 loop
   begin
     v_knowledge_id:=public.memory_learn_from_experience(r.id);
     experience_id:=r.id; knowledge_id:=v_knowledge_id; return next;
   exception when others then
     update public.memory_experiences set learning_status='error',
       metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('learning_error',sqlerrm,'learning_error_at',now()),updated_at=now()
     where id=r.id;
   end;
 end loop;
end;
$function$;
