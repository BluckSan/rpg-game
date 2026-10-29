#!/usr/bin/env python3
"""Тестовый внутренний сервис аккаунтов (только для локальных сетевых тестов, 127.0.0.1).
Токен = имя героя-файла. Герои: каталог $FAKE_DIR/<char_id>.json"""
import json, os, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
D = os.environ.get("FAKE_DIR", "/tmp/fake_internal")
os.makedirs(D, exist_ok=True)
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _send(self, code, obj):
        b = json.dumps(obj).encode(); self.send_response(code)
        self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(b)))
        self.end_headers(); self.wfile.write(b)
    def _body(self):
        n = int(self.headers.get("Content-Length", 0)); return json.loads(self.rfile.read(n) or b"{}")
    def do_POST(self):
        b = self._body()
        if self.path == "/internal/session":
            cid = b.get("char_id", ""); f = os.path.join(D, cid + ".json")
            if b.get("token") != "tok_" + cid or not os.path.exists(f): return self._send(401, {"error": "no"})
            return self._send(200, {"account_id": abs(hash(cid)) % 100000, "username": cid, "character": json.load(open(f))})
        self._send(404, {"error": "nf"})
    def do_PUT(self):
        b = self._body()
        if self.path.startswith("/internal/characters/"):
            cid = self.path.rsplit("/", 1)[1]
            json.dump(b.get("data", {}), open(os.path.join(D, cid + ".json"), "w"))
            return self._send(200, {"ok": True})
        self._send(404, {"error": "nf"})
ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 7791), H).serve_forever()
