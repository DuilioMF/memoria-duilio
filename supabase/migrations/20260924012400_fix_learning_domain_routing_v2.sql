-- Memoria Duilio 0.6.3: consistent, deterministic domain routing.
-- Final implementation combines the earlier classification precedence fix
-- and the explicit bare-n8n regression fix. Safe to rerun.
create or replace function public.memory_classify_learning_domain(
 p_problem_type text,p_context text default null,p_solution text default null,p_metadata jsonb default '{}'::jsonb
) returns text
language plpgsql immutable
set search_path to 'public','pg_temp'
as $$
declare t text:=lower(concat_ws(' ',p_problem_type,p_context,p_solution,coalesce(p_metadata::text,'')));
begin
 if t ~ '(^|[^[:alnum:]_])n8n([^[:alnum:]_]|$)|workflow|webhook|execute workflow|node |credencial|credential' then return 'n8n_limitation'; end if;
 if t ~ 'ypf|revalsoft|revalsoftia|oleum|estaci[oó]n de servicio|surtidor|tanque|combustible|varillaje|afip|arca|iibb' then return 'business_rule_ypf'; end if;
 if t ~ 'sql server|postgres|postgresql|select |insert |update |delete |index|indice|índice|stored procedure|procedure|trigger|query|consulta|surpla|database|base de datos' then return 'sql_pattern'; end if;
 if t ~ 'api|integraci[oó]n|connector|conector|supabase|trello|notion|github|cloudflare|oauth|failed to fetch|rate limit' then return 'integration_gotcha'; end if;
 return null;
end $$;
