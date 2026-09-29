"""Offline safety regression tests; no API keys or external calls needed."""
import copy
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import md_proposal_worker as w

BASE = {
    "card_url": "https://trello.com/c/E7ZOVRGE",
    "queue_id": "11111111-2222-3333-4444-555555555555",
    "run_key": "AUTO-20260927-0800",
    "title": "Corregir pantalla",
    "problem": "Verificar que la pestaña Control se muestre después del login",
    "allowed_files": ["ui/app.js"],
    "acceptance_criteria": ["node --check ui/app.js"],
}

class WorkerValidation(unittest.TestCase):
    def test_valid_bounded_task(self):
        self.assertEqual(w.validate_task(copy.deepcopy(BASE)), ["ui/app.js"])

    def test_valid_pilot_not_mislabeled_daily_run(self):
        payload = copy.deepcopy(BASE)
        payload["run_key"] = "PILOT-20260928-1800"
        self.assertEqual(w.validate_task(payload), ["ui/app.js"])
        payload["run_key"] = "PILOT-20260928-NOT-DAILY"
        with self.assertRaises(ValueError):
            w.validate_task(payload)

    def test_reject_untrusted_paths(self):
        for path in ["../.env", ".github/workflows/pwn.yml", "ui/config.js",
                     "ui/../../secret", "/tmp/evil.py"]:
            self.assertFalse(w.allowed_path(path), path)

    def test_reject_nonstring_file_entries(self):
        payload = copy.deepcopy(BASE)
        payload["allowed_files"] = [{}]
        with self.assertRaises(ValueError):
            w.validate_task(payload)

    def test_reject_wrong_queue_and_card(self):
        for key, bad in [("queue_id", "missing"), ("run_key", "tomorrow"),
                         ("card_url", "https://evil.test")]:
            payload = copy.deepcopy(BASE)
            payload[key] = bad
            with self.assertRaises(ValueError):
                w.validate_task(payload)

    def test_reject_out_of_scope_model_output(self):
        proposal = {"summary": "Unsafe",
                    "changes": [{"path": "ui/config.js", "content": "x" * 30}]}
        with self.assertRaises(ValueError):
            w.validate_proposal(proposal, ["ui/app.js"])

    def test_reject_secret_and_duplicate(self):
        with self.assertRaises(ValueError):
            w.validate_proposal({"changes": [
                {"path": "ui/app.js", "content": "let key='sk-proj-123';"}]},
                ["ui/app.js"])
        with self.assertRaises(ValueError):
            w.validate_proposal({"changes": [
                {"path": "ui/app.js", "content": "const a=123456789;"},
                {"path": "ui/app.js", "content": "const b=123456789;"}]},
                ["ui/app.js"])

    def test_accept_safe_review_proposal(self):
        changes = w.validate_proposal(
            {"changes": [{"path": "ui/app.js", "content": "const x = 'safe change';"}]},
            ["ui/app.js"])
        self.assertEqual(changes[0]["path"], "ui/app.js")

if __name__ == "__main__":
    unittest.main()
