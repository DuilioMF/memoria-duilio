-- Applied in project pddsehshgfynpmibjqhj as migration 20260929021437.
-- Indexes cover the two foreign keys reported by the Supabase performance advisor.
create index if not exists memory_executor_specialty_evidence_verification_id_idx
  on public.memory_executor_specialty_evidence (verification_id);

create index if not exists memory_trello_reconciliation_actions_memory_item_id_idx
  on public.memory_trello_reconciliation_actions (memory_item_id);
