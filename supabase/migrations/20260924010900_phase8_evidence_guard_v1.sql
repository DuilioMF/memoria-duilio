-- Memoria Duilio 0.6.1
-- Fase 8 se calcula sólo desde evidencia viva.
-- El 100% requiere prueba real de recuperación desde otra conversación.

create or replace function public.memory_phase8_evidence_guard()
returns trigger
language plpgsql
security definer
set search_path to 'public','pg_temp'
as $$
declare
  c1 boolean; c2 boolean; c3 boolean; c4 boolean;
  c5 boolean; c6 boolean; c7 boolean; c8 boolean;
  v_progress integer;
begin
  if new.project_key<>'memoria-duilio' or new.phase<>8 then
    return new;
  end if;

  select exists(select 1 from cron.job
    where jobname='memoria-duilio-daily-consolidation' and active=true) into c1;
  select exists(select 1 from public.memory_daily_consolidations
    where owner_key='duilio' and created_at>=now()-interval '48 hours') into c2;
  select exists(select 1 from public.memory_connector_instances
    where provider='notion' and status='connected') into c3;
  select exists(select 1 from public.memory_connector_instances
    where provider='trello' and status='connected') into c4;
  select count(*)>=7 from public.memory_daily_consolidations
    where owner_key='duilio' into c5;
  select exists(select 1 from public.memory_verifications
    where owner_key='duilio' and test_key='phase8-documentacion-viva-e2e' and result='success') into c6;
  select exists(select 1 from public.memory_project_intake_events
    where status='processed' and matched_project_id is not null) into c7;
  select exists(select 1 from public.memory_verifications
    where owner_key='duilio' and test_key='phase8-cross-conversation-e2e' and result='success') into c8;

  v_progress:=round(100.0 * (
    (case when c1 then 1 else 0 end)+(case when c2 then 1 else 0 end)+
    (case when c3 then 1 else 0 end)+(case when c4 then 1 else 0 end)+
    (case when c5 then 1 else 0 end)+(case when c6 then 1 else 0 end)+
    (case when c7 then 1 else 0 end)+(case when c8 then 1 else 0 end)
  ) / 8.0);

  new.progress_percent:=v_progress;
  new.completed_steps:=to_jsonb(array_remove(array[
    case when c1 then 'Consolidación diaria programada' end,
    case when c2 then 'Consolidación reciente ejecutada' end,
    case when c3 then 'Notion conectado' end,
    case when c4 then 'Trello conectado' end,
    case when c5 then 'Historial de al menos siete consolidaciones' end,
    case when c6 then 'Documentación viva Notion verificada punta a punta' end,
    case when c7 then 'Alta/ingreso automático de proyecto procesado' end,
    case when c8 then 'Recuperación verificada desde otra conversación' end
  ]::text[],null));
  new.pending_steps:=to_jsonb(array_remove(array[
    case when not c1 then 'Programar consolidación diaria' end,
    case when not c2 then 'Ejecutar consolidación reciente' end,
    case when not c3 then 'Conectar Notion' end,
    case when not c4 then 'Conectar Trello' end,
    case when not c5 then 'Acumular siete consolidaciones reales' end,
    case when not c6 then 'Verificar publicación/documentación viva punta a punta' end,
    case when not c7 then 'Probar alta automática real de proyecto' end,
    case when not c8 then 'Verificar recuperación desde otra conversación real' end
  ]::text[],null));

  if v_progress=100 then
    new.status:='completed';
    new.current_step:='Fase completada';
    new.completed_at:=coalesce(new.completed_at,now());
  else
    new.status:='in_progress';
    new.completed_at:=null;
    new.current_step:=case
      when not c1 then 'Programar consolidación diaria'
      when not c2 then 'Ejecutar consolidación reciente'
      when not c3 then 'Conectar Notion'
      when not c4 then 'Conectar Trello'
      when not c5 then 'Completar historial de consolidaciones'
      when not c6 then 'Verificar documentación viva punta a punta'
      when not c7 then 'Probar alta automática real de proyecto'
      when not c8 then 'Verificar recuperación desde otra conversación real'
      else 'Revisar evidencia'
    end;
  end if;

  new.updated_at:=now();
  return new;
end;
$$;

drop trigger if exists trg_memory_phase8_evidence_guard
on public.memory_phase_progress;

create trigger trg_memory_phase8_evidence_guard
before insert or update on public.memory_phase_progress
for each row execute function public.memory_phase8_evidence_guard();

revoke execute on function public.memory_phase8_evidence_guard() from public,anon,authenticated;
grant execute on function public.memory_phase8_evidence_guard() to service_role;
