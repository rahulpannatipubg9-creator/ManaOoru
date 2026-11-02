#!/usr/bin/env python3
"""
Simple HTTP Server for Godot 4 Web / PWA builds.
Injects Cross-Origin-Opener-Policy and Cross-Origin-Embedder-Policy headers,
and binds to 0.0.0.0 so iOS devices on the local Wi-Fi can access the game.
"""

import sys
import os
import socket
from http.server import HTTPServer, SimpleHTTPRequestHandler

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
DEFAULT_DIR = os.path.join(PROJECT_ROOT, "builds", "web")
DIRECTORY = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_DIR

class GodotPWAHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Access-Control-Allow-Origin", "*")
        super().end_headers()

    def guess_type(self, path):
        if path.endswith(".wasm"):
            return "application/wasm"
        if path.endswith(".pck"):
            return "application/octet-stream"
        if path.endswith(".json") or path.endswith(".manifest.json"):
            return "application/manifest+json"
        return super().guess_type(path)

def get_local_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"

def run():
    server_address = ("0.0.0.0", PORT)
    httpd = HTTPServer(server_address, GodotPWAHandler)
    local_ip = get_local_ip()
    print("=" * 60)
    print(f"🎮 MANA OORU Web / PWA Server running!")
    print(f"📂 Serving directory: {DIRECTORY}")
    print(f"📱 Local URL:   http://localhost:{PORT}")
    print(f"📱 iPhone URL:  http://{local_ip}:{PORT}")
    print("=" * 60)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down server.")
        httpd.server_close()

if __name__ == "__main__":
    run()
