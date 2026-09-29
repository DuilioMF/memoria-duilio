"""Offline contracts for MD's three in-review integrations.

These tests are structural regression checks, NOT an end-to-end credential,
authentic Notion signature, or autonomous GitHub queue execution test.
"""
import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
N8N = ROOT / "n8n"

def workflow(name):
    return json.loads((N8N / name).read_text(encoding="utf-8"))

def node(w, name):
    found = [n for n in w["nodes"] if n["name"] == name]
    if len(found) != 1:
        raise AssertionError(f"Expected exactly one n8n node: {name}")
    return found[0]

class ThreeIntegrationsContract(unittest.TestCase):
    def test_notion_v2_preserves_signed_raw_bytes_and_bridge_id(self):
        w = workflow("memoria-notion-signed-v2-fixed.json")
        webhook = node(w, "Notion Webhook v2 (inactivo)")
        self.assertEqual(webhook["parameters"]["path"], "memoria-sync-notion-signed-v2")
        self.assertTrue(webhook["parameters"]["options"].get("rawBody"))
        capture = node(w, "Separar handshake y exigir firma")["parameters"]["jsCode"]
        self.assertIn("getBinaryDataBuffer", capture)
        self.assertIn("RAW_BINARY_REQUIRED", capture)
        self.assertIn("signature", capture.lower())
        bridge = node(w, "Subworkflow verificacion HMAC y Supabase")
        self.assertEqual(bridge["parameters"]["workflowId"]["value"], "systJoudk1ZUY0hz")
        verifier = node(w, "Exigir validación HMAC real")["parameters"]["jsCode"]
        self.assertIn("authenticated===true", verifier)
        self.assertIn("status_code", verifier)
        self.assertIn("503", verifier)
        self.assertFalse(w["settings"].get("availableInMCP", False))

    def test_notion_bridge_is_fail_closed(self):
        w = workflow("memoria-notion-bridge-fixed.json")
        capture = node(w, "Exigir cuerpo original y firma")["parameters"]["jsCode"]
        self.assertIn("RAW_BODY_REQUIRED", capture)
        self.assertIn("signature", capture.lower())
        verifier = node(w, "Verificar firma y guardar en Supabase")
        self.assertEqual(verifier["parameters"]["method"], "POST")
        self.assertIn("memoria-notion-signed-ingest", verifier["parameters"]["url"])
        confirm = node(w, "Normalizar resultado firmado")["parameters"]["jsCode"]
        self.assertIn("authenticated===true", confirm)
        self.assertIn("status===200", confirm)
        self.assertFalse(w["settings"].get("availableInMCP", False))

    def test_github_dispatch_requires_real_queue_claim(self):
        w = workflow("memoria-fase10-github-dispatch-v1.json")
        guard = node(w, "Validar claim y tarea acotada")["parameters"]["jsCode"]
        for marker in ("queue_run_v2", "VERIFIED_QUEUE_V2_CLAIM_REQUIRED",
                       "WRONG_EXECUTOR", "CLAIM_PAYLOAD_MISMATCH",
                       "REAL_CARD_AND_DAILY_RUN_REQUIRED"):
            self.assertIn(marker, guard)
        # Real memory_queue_claim_v2 returns job.metadata, not top-level task.
        self.assertIn("job.metadata?.task", guard)
        self.assertIn("WORKER_ID_REQUIRED", guard)
        self.assertIn("execution_run_id:claim.execution_run_id", guard)
        self.assertIn("claim.run_key&&claim.run_key!==req.run_key", guard)
        dispatch = node(w, "GitHub repository_dispatch")
        self.assertEqual(dispatch["parameters"]["method"], "POST")
        self.assertEqual(dispatch["parameters"]["authentication"], "genericCredentialType")
        self.assertIn("/repos/DuilioMF/memoria-duilio/dispatches",
                      dispatch["parameters"]["url"])
        confirm = node(w, "Confirmar 204 sin cerrar tarea")["parameters"]["jsCode"]
        self.assertIn("code!==204", confirm)
        self.assertIn("dispatched_waiting_for_pr", confirm)
        self.assertNotIn("completed:true", confirm)
        # An unconnected draft must not be represented as an active dispatcher.
        self.assertFalse(w.get("active", False))


    def test_dispatch_guard_executes_real_metadata_and_rejects_bad_claims(self):
        import subprocess
        guard = node(workflow("memoria-fase10-github-dispatch-v1.json"),
                     "Validar claim y tarea acotada")["parameters"]["jsCode"]
        script = "const execute = new Function('$input', " + json.dumps(guard) + ");\n" + r"""
const assert = require('node:assert/strict');
const id = '11111111-1111-4111-8111-111111111111';
const task = {queue_id:id,card_url:'https://trello.com/c/E7ZOVRGE',
 project_key:'memoria-duilio',run_key:'AUTO-20260929-0757',
 title:'Pilot',problem:'Document bounded pilot',allowed_files:['docs/pilot.md']};
const claim = {ok:true,claimed:true,protocol:'queue_run_v2',
 worker_id:'github-actions-md',execution_run_id:id,
 job:{id,executor_key:'github-actions-md',card_url:task.card_url,
 metadata:{dispatch_task:task}}};
const run=c=>execute({first:()=>({json:c})});
assert.equal(run(claim)[0].json.client_payload.worker_id,claim.worker_id);
assert.equal(run(claim)[0].json.client_payload.execution_run_id,id);
for (const c of [{...claim,claimed:false},{...claim,worker_id:''},
 {...claim,job:{...claim.job,executor_key:'other'}},
 {...claim,job:{...claim.job,metadata:{dispatch_task:{...task,allowed_files:['ui/config.js']}}}},
 {...claim,job:{...claim.job,metadata:{dispatch_task:{...task,allowed_files:['docs/../secret']}}}},
 {...claim,job:{...claim.job,metadata:{dispatch_task:{...task,queue_id:'22222222-2222-4222-8222-222222222222'}}}}])
 assert.throws(()=>run(c));
"""
        result = subprocess.run(["node", "-e", script], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_github_job_preparation_is_fail_closed(self):
        sql = (ROOT / "supabase" / "migrations" /
               "20260929220500_md_prepare_github_proposal.sql").read_text(encoding="utf-8")
        for required in ("security invoker", "revoke all on function",
                         "to service_role", "active heartbeat",
                         "memory_scheduled_runs", "recent eligible Trello",
                         "metadata->'dispatch_task'", "dispatch_ready',false",
                         "only an unclaimed GitHub"):
            self.assertIn(required, sql)
        self.assertNotIn("repository_dispatch", sql)

    def test_control_staging_requires_owner_session(self):
        config = (ROOT / "ui" / "config.js").read_text(encoding="utf-8")
        self.assertIn("/functions/v1/memoria-home-auth-v1", config)
        self.assertIn('accessToken: ""', config)
        self.assertNotIn("service_role", config.lower())
        self.assertIn("STAGING", config)

if __name__ == "__main__":
    unittest.main()
