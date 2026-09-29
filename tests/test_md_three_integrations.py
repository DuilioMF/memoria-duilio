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

    def test_control_staging_requires_owner_session(self):
        config = (ROOT / "ui" / "config.js").read_text(encoding="utf-8")
        self.assertIn("/functions/v1/memoria-home-auth-v1", config)
        self.assertIn('accessToken: ""', config)
        self.assertNotIn("service_role", config.lower())
        self.assertIn("STAGING", config)

if __name__ == "__main__":
    unittest.main()
