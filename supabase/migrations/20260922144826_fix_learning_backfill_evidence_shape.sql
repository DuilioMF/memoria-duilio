create or replace function public.memory_backfill_verified_execution_evidence(p_owner_key text default 'duilio',p_limit integer default 100)
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $function$
declare x record; v_verified integer:=0; v_skipped integer:=0; v_id uuid;
begin
 for x in
  select e.id experience_id,e.outcome,e.evidence,e.metadata,r.id run_id,r.card_url,r.state,r.evidence run_evidence
  from public.memory_experiences e join public.memory_execution_runs r on r.id=nullif(e.metadata->>'execution_run_id','')::uuid
  where e.owner_key=p_owner_key and e.learning_status='pending' and e.outcome in ('success','failure','partial')
    and not exists(select 1 from public.memory_verifications v where v.experience_id=e.id)
    and exists(select 1 from jsonb_array_elements(case when jsonb_typeof(r.evidence)='array' then r.evidence else '[]'::jsonb end) ev
      where jsonb_typeof(ev)='object' and (lower(coalesce(ev->>'result','')) like '%pass%' or lower(coalesce(ev->>'status','')) in ('success','succeeded','passed')))
  order by e.occurred_at limit greatest(1,least(coalesce(p_limit,100),1000))
 loop
  begin
   v_id:=public.memory_record_verification(x.experience_id,coalesce(nullif(x.card_url,''),'execution-run:'||x.run_id::text),
    'historical_execution_evidence_backfill_'||left(x.run_id::text,8),x.outcome,
    jsonb_build_object('source','historical_execution_run','run_id',x.run_id,'state',x.state,'evidence',x.run_evidence),
    'memory_learning_backfill_v1',now());
   if v_id is not null then v_verified:=v_verified+1; end if;
  exception when others then
   v_skipped:=v_skipped+1;
   update public.memory_experiences set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('verification_backfill_error',sqlerrm,'verification_backfill_error_at',now()) where id=x.experience_id;
  end;
 end loop;
 return jsonb_build_object('owner_key',p_owner_key,'verified',v_verified,'skipped',v_skipped,'ran_at',now());
end;
$function$;
