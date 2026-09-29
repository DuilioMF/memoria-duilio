"""Non-destructive live F13 checks. No user tokens or service keys.

A public anon key is loaded from the existing staging UI config, never printed.
401 with an anon JWT means the Edge reached its owner-session check. This
does NOT prove that the configured owner UID matches the actual person:
a private interactive login must separately verify that.
"""
import json
import pathlib
import re
import sys
import urllib.error
import urllib.request
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONFIG = (ROOT / "ui" / "config.js").read_text(encoding="utf-8")
URL = "https://pddsehshgfynpmibjqhj.supabase.co/functions/v1/memoria-home-auth-v1"
TRUSTED = "https://memoria-duilio.revalsoftia.chatgpt.site"
UNTRUSTED = "https://unauthorized-origin.invalid"

def anon_key():
    key = re.search(r'anonKey:\s*"([^"]+)"', CONFIG)
    if not key or not key.group(1):
        raise RuntimeError("Staging config has no public anon key")
    return key.group(1)

def get(url, headers=None, method="GET", data=None, timeout=16):
    request = urllib.request.Request(url, headers=headers or {},
                                     method=method, data=data)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, response.headers, response.read(1800)
    except urllib.error.HTTPError as error:
        return error.code, error.headers, error.read(1800)

def endpoint(method="POST", origin=TRUSTED):
    public = anon_key()
    headers = {"apikey": public, "Authorization": "Bearer " + public,
               "Origin": origin}
    data = None
    if method == "POST":
        headers["Content-Type"] = "application/json"
        data = b'{"action":"control_center"}'
    return get(URL, headers, method, data)

def error_type(body):
    try:
        return json.loads(body).get("error")
    except (ValueError, TypeError):
        return "INVALID_JSON"

class BackendNegativeTests(unittest.TestCase):
    def test_denied_origin(self):
        status, _, body = endpoint(origin=UNTRUSTED)
        print("denied_origin status:", status, "error:", error_type(body))
        self.assertEqual((status, error_type(body)), (403, "ORIGIN_NOT_ALLOWED"))

    def test_anonymous_jwt_not_owner_and_secrets_loaded(self):
        status, headers, body = endpoint(origin=TRUSTED)
        print("public_anon_not_owner status:", status, "error:", error_type(body))
        self.assertEqual((status, error_type(body)), (401, "UNAUTHORIZED"),
                         "503 would mean MD_OWNER_USER_ID is not configured; "
                         "a 401 does NOT yet verify ownership identity")
        self.assertEqual(headers.get("Access-Control-Allow-Origin"), TRUSTED,
                         "MD_ALLOWED_ORIGINS must be the exact published origin")

    def test_allowed_preflight(self):
        status, headers, _ = endpoint(method="OPTIONS", origin=TRUSTED)
        print("allowed_origin_preflight status:", status)
        self.assertEqual(status, 204)
        self.assertEqual(headers.get("Access-Control-Allow-Origin"), TRUSTED)

class PublishedFrontendTests(unittest.TestCase):
    def test_public_site_reachable_and_uses_hardened_endpoint(self):
        status, _, page = get(TRUSTED + "/")
        print("published_page status:", status)
        self.assertEqual(status, 200, "This checks GitHub runner reachability only")
        self.assertIn(b"Memoria Duilio", page)
        status, _, js = get(TRUSTED + "/config.js")
        print("published_config status:", status)
        self.assertEqual(status, 200)
        self.assertIn(b"/functions/v1/memoria-home-auth-v1", js,
                      "Published site still points to legacy Edge or serves a different UI")

if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in ("backend", "frontend"):
        raise SystemExit("Usage: python tests/test_md_f13_live.py backend|frontend")
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(
        BackendNegativeTests if sys.argv[1] == "backend" else PublishedFrontendTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)
