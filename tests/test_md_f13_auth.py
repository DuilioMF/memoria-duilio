"""Fase 13 live checks: anonymous runner validates protection, not owner login."""
import json, pathlib, re, urllib.error, urllib.request, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
CONFIG=(ROOT/"ui"/"config.js").read_text(encoding="utf-8")
TRUSTED="https://memoria-duilio.revalsoftia.chatgpt.site"
EDGE="https://pddsehshgfynpmibjqhj.supabase.co/functions/v1/memoria-home-auth-v1"

def anon_key():
    m=re.search(r'anonKey:\s*"([^"]+)"',CONFIG)
    if not m or not m.group(1): raise RuntimeError("anonKey pública no configurada")
    return m.group(1)

def get(url,headers=None,method="GET",data=None,timeout=16):
    req=urllib.request.Request(url,headers=headers or {},method=method,data=data)
    try:
        with urllib.request.urlopen(req,timeout=timeout) as r:return r.status,r.headers,r.read(1800)
    except urllib.error.HTTPError as e:return e.code,e.headers,e.read(1800)

class F13(unittest.TestCase):
    def test_config_uses_hardened_edge(self):
        self.assertIn("memoria-home-auth-v1",CONFIG)
    def test_edge_rejects_anon_but_is_configured(self):
        k=anon_key()
        s,h,b=get(EDGE,{"apikey":k,"Authorization":"Bearer "+k,"Origin":TRUSTED,"Content-Type":"application/json"},"POST",b'{"action":"control_center"}')
        self.assertEqual(s,401)
        self.assertEqual(json.loads(b).get("error"),"UNAUTHORIZED")
        self.assertEqual(h.get("Access-Control-Allow-Origin"),TRUSTED)
    def test_public_shell_is_protected_or_reachable(self):
        s,_,body=get(TRUSTED+"/")
        self.assertIn(s,(200,401,403))
        if s==200:self.assertIn(b"Memoria Duilio",body)

if __name__=="__main__": unittest.main(verbosity=2)
