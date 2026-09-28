"""Static contract checks for additive MD hybrid brain.
Runtime semantics are exercised separately by tests/hybrid_brain_smoke.sql.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260928015000_hybrid_brain_v1.sql"
EDGE = ROOT / "supabase/functions/memoria-duilio-semantic/index.ts"

class HybridBrainContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.edge = EDGE.read_text(encoding="utf-8")

    def test_preserves_legacy_apis(self):
        self.assertNotIn("DROP FUNCTION PUBLIC.MEMORY_BRAIN_ROUTER", self.sql.upper())
        self.assertNotIn("DROP TABLE", self.sql.upper())
        self.assertIn("memory_brain_hybrid_v1", self.sql)
        self.assertIn("memory_graph_context_at_v1", self.sql)

    def test_only_real_verified_learning_and_specialists(self):
        self.assertIn("proof.result='success'", self.sql)
        self.assertIn("latest.result='success'", self.sql)
        self.assertIn("v.result='success'", self.sql)
        self.assertIn("e.last_health_at>=now()", self.sql)
        self.assertIn("e.automatic IS TRUE", self.sql)
        self.assertIn("'dispatch_authorized',false", self.sql)

    def test_backend_only_public_access_rejected(self):
        self.assertIn("ENABLE ROW LEVEL SECURITY", self.sql)
        self.assertIn("FROM PUBLIC,anon,authenticated", self.sql)
        self.assertIn('if (!isServiceRequest(req)) return json({ error: "service_role_required" }, 403)', self.edge)

    def test_backfill_is_bounded_and_opt_in(self):
        self.assertIn('action === "backfill_items"', self.edge)
        self.assertIn(".is(\"embedding\", null)", self.edge)
        self.assertIn('const batch = Math.min(Math.max(Math.floor(limit || 5), 1), 12)', self.edge)
        self.assertIn('action === "hybrid_context"', self.edge)
        self.assertIn('p_query_embedding: queryVector', self.edge)

if __name__ == "__main__":
    unittest.main()
