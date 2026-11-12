"""Receives script sources POSTed by export_sources.luau (run in Studio's command bar) and
writes them as a Rojo-style tree under src/.

Usage:  py tools/studio-export/receive_sources.py [--port 8765] [--out src]
Then, in Studio (HTTP requests enabled), run tools/studio-export/export_sources.luau.
"""
from __future__ import annotations
import argparse
import json
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

SUFFIX = {"Script": ".server.luau", "LocalScript": ".client.luau", "ModuleScript": ".luau"}
SAFE = re.compile(r'[<>:"/\\|?*]')


def target_path(out: Path, full_name: str, class_name: str, has_children: bool) -> Path:
    parts = [SAFE.sub("_", p) for p in full_name.split(".")]
    suffix = SUFFIX.get(class_name, ".luau")
    if has_children:
        return out.joinpath(*parts, "init" + suffix)
    parts[-1] += suffix
    return out.joinpath(*parts)


class Handler(BaseHTTPRequestHandler):
    out: Path = Path("src")
    written: list[str] = []

    def log_message(self, *_args):  # quiet
        pass

    def _reply(self, code: int, body: dict):
        data = json.dumps(body).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self._reply(200, {"ok": True, "written": len(self.written)})

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
            items = payload if isinstance(payload, list) else [payload]
            for item in items:
                path = target_path(self.out, item["path"], item["class"], bool(item.get("hasChildren")))
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(item["source"].replace("\r\n", "\n"), encoding="utf-8", newline="\n")
                self.written.append(str(path))
            self._reply(200, {"ok": True, "written": len(self.written)})
        except Exception as error:  # noqa: BLE001
            self._reply(400, {"ok": False, "error": str(error)})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--out", default="src")
    args = parser.parse_args()
    Handler.out = Path(args.out).resolve()
    Handler.out.mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"Listening on http://127.0.0.1:{args.port}/ -> {Handler.out}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
