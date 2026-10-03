#!/usr/bin/env python3
"""Loopback-only fake checkout and license ledger. Never deploy as a payment service."""
import argparse
import html
import json
import secrets
import sqlite3
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit


class LicenseError(Exception):
    pass


class Ledger:
    def __init__(self, path):
        self.db = sqlite3.connect(path)
        self.db.executescript("""
            CREATE TABLE IF NOT EXISTS orders (id TEXT PRIMARY KEY, state TEXT NOT NULL, key TEXT);
            CREATE TABLE IF NOT EXISTS licenses (key TEXT PRIMARY KEY);
            CREATE TABLE IF NOT EXISTS devices (key TEXT NOT NULL, device TEXT NOT NULL,
                PRIMARY KEY (key, device));
        """)

    def checkout(self):
        order = secrets.token_urlsafe(24)
        with self.db:
            self.db.execute("INSERT INTO orders VALUES (?, 'pending', NULL)", (order,))
        return order

    def order(self, order):
        row = self.db.execute("SELECT state, key FROM orders WHERE id = ?", (order,)).fetchone()
        if not row:
            raise LicenseError("Checkout not found.")
        return row

    def complete(self, order, outcome):
        if outcome not in ("paid", "cancelled"):
            raise LicenseError("Unknown checkout result.")
        with self.db:
            state, key = self.order(order)
            if state == "pending":
                if outcome == "paid":
                    key = "TEST-" + "-".join(secrets.token_hex(4).upper() for _ in range(4))
                    self.db.execute("INSERT INTO licenses VALUES (?)", (key,))
                self.db.execute("UPDATE orders SET state = ?, key = ? WHERE id = ?", (outcome, key, order))
        return self.order(order)

    def activation(self, key, device, remove=False):
        if not isinstance(key, str) or not isinstance(device, str) or not 1 <= len(device) <= 128:
            raise LicenseError("A license key and device ID are required.")
        key = key.strip().upper()
        with self.db:
            if not self.db.execute("SELECT 1 FROM licenses WHERE key = ?", (key,)).fetchone():
                raise LicenseError("That license key wasn’t found. Check it and try again.")
            existing = self.db.execute("SELECT 1 FROM devices WHERE key = ? AND device = ?", (key, device)).fetchone()
            count = self.db.execute("SELECT count(*) FROM devices WHERE key = ?", (key,)).fetchone()[0]
            if remove:
                self.db.execute("DELETE FROM devices WHERE key = ? AND device = ?", (key, device))
                count -= bool(existing)
            elif not existing:
                if count >= 1:
                    raise LicenseError("This license is already active on another Mac. Deactivate it there first.")
                self.db.execute("INSERT INTO devices VALUES (?, ?)", (key, device))
                count += 1
        return {"key": key, "devices": count, "limit": 1}


def page(title, content):
    return f"""<!doctype html><html lang="en"><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{html.escape(title)} · Glissform preview</title>
    <style>
    :root {{color-scheme:light dark;font:16px/1.5 system-ui;background:light-dark(#f5f5f7,#151517)}}
    body {{margin:0;min-height:100svh;display:grid;place-items:center}}
    main {{box-sizing:border-box;width:min(520px,calc(100% - 40px));padding:36px;border-radius:24px;
        background:light-dark(white,#252528);box-shadow:0 20px 70px #0001}}
    .badge {{font-size:12px;color:light-dark(#765600,#ffd778);letter-spacing:.06em}}
    h1 {{font-size:28px;line-height:1.2;letter-spacing:-.03em;margin:22px 0 12px}}
    p {{color:light-dark(#5e5e65,#c3c3cb)}}
    strong {{color:light-dark(#202025,white)}}
    button {{font:inherit;font-weight:600;border:0;border-radius:10px;padding:12px 18px;cursor:pointer;
        background:#1877da;color:white;margin-top:14px}}
    button.secondary {{background:transparent;color:inherit}} form {{display:inline}}
    input {{box-sizing:border-box;width:100%;font:13px ui-monospace,monospace;padding:14px 10px;
        border:1px solid #8886;border-radius:8px;background:transparent;color:inherit}}
    small {{display:block;margin-top:26px;color:light-dark(#707078,#a8a8b0)}}
    </style><main><div class="badge">LOCAL PREVIEW · NO REAL PAYMENT</div>
    <h1>{html.escape(title)}</h1>{content}
    <small>This checkout simulates a purchase. No payment details are collected and no email is sent.</small>
    </main></html>""".encode()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass  # Do not log license keys or checkout URLs.

    def reply(self, status, content, mime="application/json"):
        if mime == "application/json":
            content = json.dumps(content).encode()
        self.send_response(status)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(content)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        # Preserve same-origin form POST metadata in Safari without leaking URLs externally.
        self.send_header("Referrer-Policy", "same-origin")
        self.send_header("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'")
        self.end_headers()
        self.wfile.write(content)

    def valid_host(self):
        return self.headers.get("Host") == f"127.0.0.1:{self.server.server_port}"

    def do_GET(self):
        if not self.valid_host():
            return self.reply(403, {"error": "Loopback access only."})
        path = urlsplit(self.path).path
        if not path.startswith("/checkout/"):
            return self.reply(404, {"error": "Not found."})
        order = path.removeprefix("/checkout/")
        try:
            state, key = self.server.ledger.order(order)
            if state == "paid":
                title = "Your test license is ready"
                content = f'<p>Copy this key and paste it into <strong>License</strong> in Glissform Dev.</p><input aria-label="License key" readonly value="{html.escape(key)}"><p>Lifetime access for <strong>one Mac</strong>.</p>'
            elif state == "cancelled":
                title = "Checkout cancelled"
                content = '<p>No license was issued. Return to Glissform to continue your trial or start a new checkout.</p>'
            else:
                title = "Make Glissform yours"
                content = f'''<p>Subtle animations for everyday Mac interactions.</p>
                <p>Pay <strong>$2.99 once</strong> for lifetime access on <strong>one Mac</strong>.</p>
                <form method="post" action="/checkout/{order}"><button name="outcome" value="paid">Simulate payment</button>
                <button class="secondary" name="outcome" value="cancelled">Cancel</button></form>'''
            self.reply(200, page(title, content), "text/html; charset=utf-8")
        except LicenseError as error:
            self.reply(404, {"error": str(error)})

    def do_POST(self):
        origin = f"http://127.0.0.1:{self.server.server_port}"
        if not self.valid_host() or self.headers.get("Origin", origin) != origin or self.headers.get("Sec-Fetch-Site") == "cross-site":
            return self.reply(403, {"error": "Loopback access only."})
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 4096:
                raise ValueError()
            body = self.rfile.read(length)
            path = urlsplit(self.path).path
            if path.startswith("/checkout/"):
                order = path.removeprefix("/checkout/")
                outcome = parse_qs(body.decode()).get("outcome", [""])[0]
                self.server.ledger.complete(order, outcome)
                self.send_response(303)
                self.send_header("Location", path)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            if self.headers.get_content_type() != "application/json":
                raise ValueError()
            data = json.loads(body)
            if not isinstance(data, dict):
                raise ValueError()
            if path == "/checkout":
                order = self.server.ledger.checkout()
                result = {"url": f"{origin}/checkout/{order}"}
            elif path in ("/activate", "/deactivate"):
                result = self.server.ledger.activation(data.get("key"), data.get("device"), path == "/deactivate")
            else:
                return self.reply(404, {"error": "Not found."})
            self.reply(200, result)
        except LicenseError as error:
            self.reply(409, {"error": str(error)})
        except (ValueError, UnicodeDecodeError):
            self.reply(400, {"error": "Invalid request."})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", type=Path, default=Path(__file__).resolve().parent.parent / "build/license-preview.sqlite3")
    args = parser.parse_args()
    args.database.parent.mkdir(parents=True, exist_ok=True)
    # Serial request handling keeps the slot check and allocation in one operation.
    server = HTTPServer(("127.0.0.1", 8765), Handler)
    server.ledger = Ledger(args.database)
    print("Glissform fake checkout ready at http://127.0.0.1:8765 — no real payments", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        server.ledger.db.close()


if __name__ == "__main__":
    main()
