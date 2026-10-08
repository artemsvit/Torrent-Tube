import os
import shutil
import tempfile
import unittest
from pathlib import Path

_sandbox = tempfile.TemporaryDirectory(prefix="torrenttube-caching-test-")
os.environ.setdefault("TORRENTTUBE_DOWNLOAD_DIR", _sandbox.name)
os.environ.setdefault("TORRENTTUBE_STATE_DIR", str(Path(_sandbox.name) / "state"))
import app as server


class TestCaching(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.db_path = Path(self.temp_dir) / "test_cache.db"
        self.cache = server.PersistentCache(self.db_path)

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_cache_hit_and_negative_persistence(self):
        # 1. Miss initially
        found, val = self.cache.get("test:key:1")
        self.assertFalse(found)
        self.assertIsNone(val)

        # 2. Positive hit
        self.cache.set("test:key:1", {"title": "Movie"}, ttl=3600, is_hit=True)
        found, val = self.cache.get("test:key:1")
        self.assertTrue(found)
        self.assertEqual(val, {"title": "Movie"})

        # 3. Negative hit (val is None, but found is True)
        self.cache.set("test:key:2", None, ttl=3600, is_hit=False)
        found, val = self.cache.get("test:key:2")
        self.assertTrue(found)
        self.assertIsNone(val)

        # 4. New instance pointing to same SQLite db persists data across restart
        new_instance = server.PersistentCache(self.db_path)
        found, val = new_instance.get("test:key:1")
        self.assertTrue(found)
        self.assertEqual(val, {"title": "Movie"})

        found, val = new_instance.get("test:key:2")
        self.assertTrue(found)
        self.assertIsNone(val)

    def test_etag_response_and_304(self):
        client = server.app.test_client()
        resp = client.get("/api/library")
        self.assertEqual(resp.status_code, 200)
        etag = resp.headers.get("ETag")
        self.assertTrue(etag)

        # Conditional request with matching ETag -> 304 Not Modified
        resp_304 = client.get("/api/library", headers={"If-None-Match": etag})
        self.assertEqual(resp_304.status_code, 304)


if __name__ == "__main__":
    unittest.main()
