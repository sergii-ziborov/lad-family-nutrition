import hashlib
import json
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path

from server import make_server


class PrivateCatalogTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.catalog = Path(self.temporary.name) / "private-recipes.json"
        self.catalog.write_text(json.dumps({"recipes": []}), encoding="utf-8")
        self.token = "a-long-random-test-token"
        self.server = make_server("127.0.0.1", 0, hashlib.sha256(self.token.encode()).hexdigest(), self.catalog)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base = f"http://127.0.0.1:{self.server.server_port}"

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=3)
        self.temporary.cleanup()

    def test_private_catalog_requires_token(self):
        for header in ({}, {"Authorization": "Bearer wrong"}):
            with self.subTest(header=header):
                request = urllib.request.Request(self.base + "/v1/recipes", headers=header)
                with self.assertRaises(urllib.error.HTTPError) as result:
                    urllib.request.urlopen(request, timeout=3)
                self.assertEqual(result.exception.code, 401)
                result.exception.close()

    def test_authorized_catalog_is_not_cacheable(self):
        request = urllib.request.Request(self.base + "/v1/recipes", headers={"Authorization": "Bearer " + self.token})
        with urllib.request.urlopen(request, timeout=3) as response:
            self.assertEqual(response.status, 200)
            self.assertEqual(response.headers["Cache-Control"], "no-store")
            self.assertEqual(json.load(response), {"recipes": []})

    def test_other_paths_do_not_expose_file(self):
        with self.assertRaises(urllib.error.HTTPError) as result:
            urllib.request.urlopen(self.base + "/private-recipes.json", timeout=3)
        self.assertEqual(result.exception.code, 404)
        result.exception.close()

    def test_non_loopback_bind_is_rejected(self):
        with self.assertRaises(ValueError):
            make_server("0.0.0.0", 0, hashlib.sha256(self.token.encode()).hexdigest(), self.catalog)


if __name__ == "__main__":
    unittest.main()
