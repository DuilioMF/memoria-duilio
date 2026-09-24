-- Memoria Duilio 0.6.1
-- Corrige el orden clasificación → verificación → aprendizaje.
-- Evita verified_experience_immutable durante una verificación válida.

create or replace function public.memory_before_verification_classify()
returns trigger
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  v_domain text;
begin
  if new.result not in ('success','failure','partial') then
    return new;
  end if;

  select public.memory_classify_learning_domain(
           e.problem_type,e.context,e.solution,e.metadata
         )
    into v_domain
  from public.memory_experiences e
  where e.id=new.experience_id;

  if v_domain is not null then
    update public.memory_experiences e
       set problem_type=v_domain,
           metadata=coalesce(e.metadata,'{}'::jsonb) || jsonb_build_object(
             'original_problem_type',
               case
                 when e.problem_type<>v_domain then e.problem_type
                 else coalesce(e.metadata->>'original_problem_type',e.problem_type)
               end,
             'domain_classified_by','continuous_learning_v1',
             'domain_classified_at',now()
           ),
           updated_at=now()
     where e.id=new.experience_id
       and e.problem_type is distinct from v_domain;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_memory_before_verification_classify
on public.memory_verifications;

create trigger trg_memory_before_verification_classify
before insert on public.memory_verifications
for each row execute function public.memory_before_verification_classify();

create or replace function public.memory_after_verification_learn()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_k uuid;
begin
  if new.result not in ('success','failure','partial') then
    return new;
  end if;

  if public.memory_experience_is_learnable(new.experience_id) then
    begin
      v_k:=public.memory_learn_from_experience(new.experience_id);
      if v_k is not null then
        perform public.memory_refresh_knowledge_score(v_k);
      end if;
    exception when others then
      insert into public.memory_events(owner_key,event_type,actor,details)
      values(
        new.owner_key,
        'continuous_learning_error',
        'continuous_learning_v1',
        jsonb_build_object('experience_id',new.experience_id,'error',sqlerrm)
      );
    end;
  end if;

  return new;
end;
$$;

revoke execute on function public.memory_before_verification_classify() from public,anon,authenticated;
revoke execute on function public.memory_after_verification_learn() from public,anon,authenticated;
grant execute on function public.memory_before_verification_classify() to service_role;
grant execute on function public.memory_after_verification_learn() to service_role;
