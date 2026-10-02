CREATE OR REPLACE FUNCTION public.memory_schedule_run_step(p_run_key text,p_status text,p_step text,p_summary text DEFAULT NULL,p_details jsonb DEFAULT '{}'::jsonb,p_finish boolean DEFAULT false)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare v_row public.memory_scheduled_runs%rowtype; v_terminal boolean;
begin
 if p_status is null or p_status not in ('started','running','completed','incomplete','failed') then raise exception 'invalid status %',p_status; end if;
 v_terminal:=p_status in ('completed','incomplete','failed');
 if p_finish and not v_terminal then raise exception 'p_finish requires terminal status'; end if;
 select * into v_row from public.memory_scheduled_runs where owner_key='duilio' and run_key=p_run_key for update;
 if not found then raise exception 'run not found: %',p_run_key; end if;
 if (v_row.finished_at is not null or v_row.status in ('completed','incomplete','failed')) and not v_terminal then
  return jsonb_build_object('ok',true,'ignored',true,'reason','terminal_run','run_key',v_row.run_key,'status',v_row.status,'step',v_row.step,'started_at',v_row.started_at,'finished_at',v_row.finished_at);
 end if;
 update public.memory_scheduled_runs set status=p_status,step=p_step,summary=coalesce(p_summary,summary),
 details=coalesce(details,'{}'::jsonb)||coalesce(p_details,'{}'::jsonb),last_heartbeat_at=now(),
 finished_at=case when v_terminal then coalesce(finished_at,now()) else null end,updated_at=now()
 where id=v_row.id returning * into v_row;
 return jsonb_build_object('ok',true,'run_key',v_row.run_key,'status',v_row.status,'step',v_row.step,'started_at',v_row.started_at,'finished_at',v_row.finished_at);
end;
$function$;
REVOKE ALL ON FUNCTION public.memory_schedule_run_step(text,text,text,text,jsonb,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.memory_schedule_run_step(text,text,text,text,jsonb,boolean) TO service_role;
