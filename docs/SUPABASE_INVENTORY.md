# Inventario recuperado de Supabase

Proyecto: `pddsehshgfynpmibjqhj`

Generado desde la fuente viva el 20/09/2026 (Argentina).

## Edge Functions recuperadas

- `memoria-duilio-semantic` — versión 15 — estado ACTIVE — JWT no exigido por gateway — SHA-256 `1487354c467d7b59e669cb4540681958a622173ab9a5e27a8de7328934a84890`
- `memoria-duilio-daily` — versión 3 — estado ACTIVE — JWT no exigido por gateway — SHA-256 `3f1ae6f0fa1f0df4a324cdead8bed7edcdb1a493db7e0f3c984047ab22258168`
- `memoria-work-adapter` — versión 1 — estado ACTIVE — JWT obligatorio — SHA-256 `4e590043045c26a39071f34f1030a4e4ad8f18479ce53860014cc21625eb3bc5`
- `memoria-orchestrator` — versión 1 — estado ACTIVE — JWT obligatorio — SHA-256 `4f1029f7a765100ec1526b1605b3cdf2aa3ddf1fa4f055c0ec43779e90305e05`
- `memoria-home` — versión 2 — estado ACTIVE — JWT obligatorio — SHA-256 `cc57708974a976b1b0c1f248f079fe34ae78ff35d0cccfb7c6de135fbd2412e2`

## Migraciones registradas (63)

- `20260901033308_add_memory_ingest_pipeline`
- `20260901033350_fix_memory_ingest_digest_schema`
- `20260901033647_index_memory_ingest_pipeline`
- `20260901034010_enable_memory_sync_scheduler`
- `20260903213910_memoria_duilio_learning_engine_v1`
- `20260903213929_memoria_duilio_learning_engine_v1_security`
- `20260904031116_memoria_duilio_phase3_consolidation_engine_v1`
- `20260904031133_memoria_duilio_phase3_link_uniqueness_fix`
- `20260904031205_memoria_duilio_phase3_relation_mapping_fix`
- `20260904164636_memoria_duilio_phase3_semantic_consolidation`
- `20260904164656_memoria_duilio_phase3_pipeline_bridge`
- `20260904170647_memoria_duilio_phase4_trainer_v1`
- `20260904170720_memoria_duilio_phase4_lockdown_internal_rpcs`
- `20260904171115_memoria_duilio_phase4_trainer_v2_complete`
- `20260904172442_memoria_duilio_phase5_affective_layer_v1`
- `20260904172513_memoria_duilio_phase5_affective_integration_v1`
- `20260906131745_memoria_duilio_phase4_continuity`
- `20260906131802_secure_memoria_duilio_phase4_tables`
- `20260906133325_memoria_duilio_phase5_daily_learning`
- `20260906151751_memoria_duilio_phase5_completion_v1`
- `20260906152453_memoria_duilio_phase5_fk_indexes`
- `20260907124539_memoria_duilio_phase6_evidence_and_continuity`
- `20260907124756_memoria_duilio_phase6_integration_suite`
- `20260907125003_memoria_duilio_phase6_daily_snapshot_integration`
- `20260908002023_phase7_progress_tracking`
- `20260908004936_create_integration_secret_registry`
- `20260908011446_create_donglio_workflow_snapshot`
- `20260908011725_secure_donglio_workflow_snapshot`
- `20260908021225_create_donglio_whatsapp_observation_log`
- `20260908024450_donglio_capture_audit_hardening`
- `20260909155339_memoria_duilio_capa0_startup_context`
- `20260909155510_memoria_duilio_protect_phase_progress`
- `20260909155541_memoria_duilio_daily_startup_checks`
- `20260913202036_phase9_execution_ledger`
- `20260917000048_load_active_operational_rules_in_startup`
- `20260917001813_memory_brain_router_graph_learning_cycle_v2`
- `20260917001914_fix_brain_learning_verification_clock`
- `20260917004745_auto_sync_projects_to_memory_brain`
- `20260917011429_phase9_execution_status_view`
- `20260917013014_phase9_trello_memory_sync`
- `20260917013656_phase9_work_execution_adapter_v2`
- `20260917013919_phase9_work_adapter_integrity`
- `20260917021232_memory_duilio_dashboard_access`
- `20260917021929_memory_dashboard_payload_v1`
- `20260919041849_memory_multi_ai_orchestrator_v1_1`
- `20260919041917_memory_multi_ai_worker_protocol_v1`
- `20260919041952_memory_multi_ai_router_classification_fix_v1`
- `20260919042204_memory_multi_ai_security_lockdown_v1`
- `20260919045402_memory_security_hardening_work_adapter_v1`
- `20260919052425_memory_operating_model_and_home_v1`
- `20260919052556_memory_source_router_and_query_plan_v1`
- `20260919052616_memory_source_router_precedence_fix_v1`
- `20260919061428_canonicalize_doinglio_identity_v3`
- `20260919063016_canonicalize_supervision_project_v4`
- `20260920232013_feli_version_reconciliation_v2`
- `20260920232439_memory_duilio_integrity_gate_v1`
- `20260920232828_memory_duilio_safe_self_heal_v1`
- `20260920233132_memory_duilio_self_integrity_v2`
- `20260920233715_memory_duilio_separate_constitution_from_software_version`
- `20260920234237_memory_daily_schedule_run_ledger_v1`
- `20260920234638_memory_schedule_dispatch_trace_v1`
- `20260921001804_memory_integrity_live_source_freshness_v1`
- `20260921003137_classify_canonical_and_candidate_versions`

## Límites del inventario

- La lista de migraciones acredita nombres y orden registrados, no reconstruye automáticamente el contenido SQL histórico.
- Las Edge Functions listadas sí fueron recuperadas desde el proyecto activo y guardadas en esta rama.
- Los workflows n8n y la UI vigente siguen pendientes de exportación desde su fuente real.
- No se incluyeron secretos, variables de entorno ni datos personales.
