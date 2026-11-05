"""Local file bridge for Studio (127.0.0.1 only).

GET /list            -> JSON list of every file under src/ (relative paths)
GET /file?path=...   -> raw file text (paths restricted to the project folder)

Run from the project root: py -I tools/bridge.py
"""
import json, os, urllib.parse
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


class H(BaseHTTPRequestHandler):
    def send(self, code, body, ctype="text/plain; charset=utf-8"):
        data = body.encode("utf-8") if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        if u.path == "/list":
            out = []
            for base, _, files in os.walk(os.path.join(ROOT, "src")):
                for f in files:
                    if f.endswith(".luau"):
                        out.append(os.path.relpath(os.path.join(base, f), ROOT).replace("\\", "/"))
            return self.send(200, json.dumps(sorted(out)), "application/json")
        if u.path == "/file":
            rel = q.get("path", [""])[0]
            full = os.path.abspath(os.path.join(ROOT, rel))
            if not full.startswith(ROOT + os.sep) or not os.path.isfile(full):
                return self.send(404, "not found")
            with open(full, "rb") as fh:
                return self.send(200, fh.read())
        self.send(404, "not found")

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    print("bridge on http://127.0.0.1:8767 root", ROOT, flush=True)
    ThreadingHTTPServer(("127.0.0.1", 8767), H).serve_forever()
