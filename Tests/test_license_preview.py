import importlib.util
import json
import tempfile
import threading
import unittest
from http.client import HTTPConnection
from http.server import HTTPServer
from pathlib import Path

spec = importlib.util.spec_from_file_location("license_preview", Path(__file__).resolve().parents[1] / "scripts/license-preview.py")
preview = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preview)


class LicensePreviewTests(unittest.TestCase):
    def setUp(self):
        self.ledger = preview.Ledger(":memory:")

    def tearDown(self):
        self.ledger.db.close()

    def purchase(self):
        order = self.ledger.checkout()
        return order, self.ledger.complete(order, "paid")[1]

    def test_purchase_is_idempotent_and_cancel_does_not_issue_key(self):
        order, key = self.purchase()
        self.assertEqual(self.ledger.complete(order, "paid"), ("paid", key))
        self.assertEqual(self.ledger.complete(order, "cancelled"), ("paid", key))
        cancelled = self.ledger.checkout()
        self.assertEqual(self.ledger.complete(cancelled, "cancelled"), ("cancelled", None))
        self.assertEqual(self.ledger.complete(cancelled, "paid"), ("cancelled", None))
        self.assertEqual(self.ledger.db.execute("SELECT count(*) FROM licenses").fetchone()[0], 1)

    def test_one_device_limit_and_slot_reuse(self):
        _, key = self.purchase()
        self.assertEqual(self.ledger.activation(key, "first"), {"key": key, "devices": 1, "limit": 1})
        self.assertEqual(self.ledger.activation(key.lower(), "first")["devices"], 1)
        with self.assertRaises(preview.LicenseError):
            self.ledger.activation(key, "second")
        self.assertEqual(self.ledger.activation(key, "first", remove=True)["devices"], 0)
        self.assertEqual(self.ledger.activation(key, "first", remove=True)["devices"], 0)
        self.assertEqual(self.ledger.activation(key, "second")["devices"], 1)
        with self.assertRaises(preview.LicenseError):
            self.ledger.activation(key, "first")

    def test_invalid_key_and_device(self):
        _, key = self.purchase()
        for candidate, device in [("INVALID", "one"), (key, ""), (key, None), (None, "one")]:
            with self.assertRaises(preview.LicenseError):
                self.ledger.activation(candidate, device)

    def test_database_survives_restart(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "licenses.sqlite3"
            first = preview.Ledger(path)
            order = first.checkout()
            key = first.complete(order, "paid")[1]
            first.activation(key, "mac-one")
            first.db.close()
            second = preview.Ledger(path)
            self.assertEqual(second.order(order), ("paid", key))
            self.assertEqual(second.activation(key, "mac-one")["devices"], 1)
            second.db.close()

    def test_http_checkout_activation_and_origin_boundary(self):
        server = HTTPServer(("127.0.0.1", 0), preview.Handler)
        def serve():
            server.ledger = preview.Ledger(":memory:")
            try:
                server.serve_forever(poll_interval=0.01)
            finally:
                server.ledger.db.close()
        worker = threading.Thread(target=serve)
        worker.start()
        client = HTTPConnection("127.0.0.1", server.server_port, timeout=3)
        def request(method, path, body=None, headers=None):
            client.request(method, path, body=body, headers=headers or {})
            response = client.getresponse()
            if method == "GET" and response.status == 200:
                self.assertEqual(response.getheader("Referrer-Policy"), "same-origin")
            return response.status, response.read()
        headers = {"Content-Type": "application/json"}
        try:
            status, data = request("POST", "/checkout", "{}", headers)
            self.assertEqual(status, 200)
            path = preview.urlsplit(json.loads(data)["url"]).path
            self.assertEqual(request("GET", path)[0], 200)
            # Visiting a fabricated success redirect must never generate an entitlement.
            _, pending = request("GET", path + "?success=true")
            self.assertIn(b"Simulate payment", pending)
            self.assertNotIn(b"TEST-", pending)
            self.assertEqual(request("POST", path, "outcome=paid", {"Origin": "https://evil.example"})[0], 403)
            self.assertEqual(request("POST", "/checkout", "{}", {"Host": "evil.example", **headers})[0], 403)
            self.assertEqual(request("POST", path, "outcome=paid")[0], 303)
            status, data = request("GET", path)
            self.assertEqual(status, 200)
            import re
            key = re.search(rb'TEST-(?:[A-F0-9]{8}-){3}[A-F0-9]{8}', data).group().decode()
            for i in range(2):
                status, _ = request("POST", "/activate", json.dumps({"key": key, "device": str(i)}), headers)
                self.assertEqual(status, 200 if i == 0 else 409)
            self.assertEqual(request("POST", "/activate", "[]", headers)[0], 400)
        finally:
            client.close()
            server.shutdown()
            worker.join()
            server.server_close()


if __name__ == "__main__":
    unittest.main()
