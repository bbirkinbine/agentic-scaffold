"""Stub OpenAI-compatible server for scripts/smoke-test-delegate.sh.

Serves POST /v1/chat/completions from a queue directory and records every
request, so the smoke test can drive the delegate runner without a real
model. Each request consumes the next queued response in name order:

  <queue>/NN.json     response body (required)
  <queue>/NN.status   HTTP status (optional, default 200)
  <queue>/NN.delay    seconds to wait before answering (optional)

Requests are written to <queue>/requests/NN.json and their Authorization
header to <queue>/requests/NN.auth. GET /v1/models lists one model.

Usage: python3 -I delegate-stub-server.py <queue-dir> <port-file>
"""

import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

QUEUE = Path(sys.argv[1])
PORT_FILE = Path(sys.argv[2])
REQUESTS = QUEUE / "requests"
REQUESTS.mkdir(parents=True, exist_ok=True)


def next_response():
    served = {p.stem for p in REQUESTS.glob("*.json")}
    for body in sorted(QUEUE.glob("*.json")):
        if body.stem not in served:
            return body
    return None


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, status, payload):
        data = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path.rstrip("/") == "/v1/models":
            self.reply(200, {"object": "list", "data": [{"id": "stub-model", "object": "model"}]})
        else:
            self.reply(404, {"error": "not found"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        request = self.rfile.read(length)
        if self.path.rstrip("/") != "/v1/chat/completions":
            self.reply(404, {"error": "not found"})
            return
        body = next_response()
        if body is None:
            self.reply(500, {"error": "stub queue empty"})
            return
        (REQUESTS / f"{body.stem}.json").write_bytes(request)
        (REQUESTS / f"{body.stem}.auth").write_text(self.headers.get("Authorization", ""))
        delay = body.with_suffix(".delay")
        if delay.exists():
            time.sleep(float(delay.read_text()))
        status_file = body.with_suffix(".status")
        status = int(status_file.read_text()) if status_file.exists() else 200
        if status == 200 and json.loads(request).get("stream"):
            # Pi speaks streaming chat completions; exercise real client
            # provider plumbing with the same deterministic response queue.
            message = json.loads(body.read_bytes())["choices"][0]
            chunks = [
                {"choices": [{"index": 0, "delta": message["message"], "finish_reason": None}]},
                {"choices": [{"index": 0, "delta": {}, "finish_reason": message["finish_reason"]}]},
            ]
            payload = "".join(f"data: {json.dumps(chunk)}\n\n" for chunk in chunks) + "data: [DONE]\n\n"
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Content-Length", str(len(payload.encode())))
            self.end_headers()
            self.wfile.write(payload.encode())
        else:
            self.reply(status, body.read_bytes())


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
PORT_FILE.write_text(str(server.server_address[1]))
server.serve_forever()
