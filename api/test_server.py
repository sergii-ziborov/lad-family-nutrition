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
        self.family = Path(self.temporary.name) / "private-family.json"
        self.family.write_text(json.dumps({"members": [{"id": "member1", "name": "Тест", "goal": "Без цели по весу", "portion": 1.0, "allergies": [], "ageYears": 30}]}), encoding="utf-8")
        self.images = Path(self.temporary.name) / "images"
        self.images.mkdir()
        (self.images / "dish.jpg").write_bytes(b"\xff\xd8\xfftest-image")
        self.token = "a-long-random-test-token"
        self.server = make_server("127.0.0.1", 0, hashlib.sha256(self.token.encode()).hexdigest(), self.catalog, self.family, self.images)
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

    def test_family_requires_token_and_stays_private(self):
        with self.assertRaises(urllib.error.HTTPError) as result:
            urllib.request.urlopen(self.base + "/v1/family", timeout=3)
        self.assertEqual(result.exception.code, 401)
        result.exception.close()
        request = urllib.request.Request(self.base + "/v1/family", headers={"Authorization": "Bearer " + self.token})
        with urllib.request.urlopen(request, timeout=3) as response:
            self.assertEqual(response.headers["Cache-Control"], "no-store")
            self.assertEqual(json.load(response)["members"][0]["name"], "Тест")

    def test_other_paths_do_not_expose_file(self):
        with self.assertRaises(urllib.error.HTTPError) as result:
            urllib.request.urlopen(self.base + "/private-recipes.json", timeout=3)
        self.assertEqual(result.exception.code, 404)
        result.exception.close()

    def test_private_image_requires_token_and_is_not_cacheable(self):
        with self.assertRaises(urllib.error.HTTPError) as result:
            urllib.request.urlopen(self.base + "/v1/recipe-images/dish", timeout=3)
        self.assertEqual(result.exception.code, 401)
        result.exception.close()
        request = urllib.request.Request(self.base + "/v1/recipe-images/dish", headers={"Authorization": "Bearer " + self.token})
        with urllib.request.urlopen(request, timeout=3) as response:
            self.assertEqual(response.status, 200)
            self.assertEqual(response.headers["Content-Type"], "image/jpeg")
            self.assertEqual(response.headers["Cache-Control"], "no-store")
            self.assertEqual(response.read(), b"\xff\xd8\xfftest-image")

    def test_image_path_traversal_is_rejected(self):
        request = urllib.request.Request(self.base + "/v1/recipe-images/..%2Fprivate-family", headers={"Authorization": "Bearer " + self.token})
        with self.assertRaises(urllib.error.HTTPError) as result:
            urllib.request.urlopen(request, timeout=3)
        self.assertEqual(result.exception.code, 404)
        result.exception.close()

    def test_non_loopback_bind_is_rejected(self):
        with self.assertRaises(ValueError):
            make_server("0.0.0.0", 0, hashlib.sha256(self.token.encode()).hexdigest(), self.catalog)


if __name__ == "__main__":
    unittest.main()
