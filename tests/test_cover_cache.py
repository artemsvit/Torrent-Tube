"""The server's copy of TMDB covers: fetched once, served from disk after."""
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

_sandbox = tempfile.TemporaryDirectory(prefix="torrenttube-covers-")
os.environ.setdefault("TORRENTTUBE_DOWNLOAD_DIR", _sandbox.name)
os.environ.setdefault("TORRENTTUBE_STATE_DIR", str(Path(_sandbox.name) / "state"))
import app as server
from cover_cache import CoverCache, CoverError

JPEG = b"\xff\xd8\xff\xe0 a tiny jpeg"


class CoverCacheTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.calls = []
        self.fail = None

        def fetch(url):
            self.calls.append(url)
            if self.fail:
                raise self.fail
            return JPEG
        self.cache = CoverCache(Path(self.folder.name), fetch=fetch)

    def tearDown(self):
        self.folder.cleanup()

    def test_fetches_once_then_serves_from_disk(self):
        first = self.cache.get("w342", "abc123.jpg")
        self.assertEqual(first.read_bytes(), JPEG)
        self.assertEqual(self.cache.get("w342", "abc123.jpg"), first)
        self.assertEqual(self.calls, ["https://image.tmdb.org/t/p/w342/abc123.jpg"])
        self.assertEqual(self.cache.stats()["files"], 1)

    def test_rejects_other_sizes_and_paths(self):
        for size, name in (("w9999", "a.jpg"), ("w342", "../app.py"), ("w342", "a.exe"), ("w342", ".hidden.jpg")):
            with self.assertRaises(CoverError) as e:
                self.cache.get(size, name)
            self.assertEqual(e.exception.status, 404)
        self.assertEqual(self.calls, [])

    def test_a_failed_fetch_is_not_kept(self):
        self.fail = OSError("no network")
        with self.assertRaises(CoverError) as e:
            self.cache.get("w342", "abc123.jpg")
        self.assertEqual(e.exception.status, 502)
        self.fail = None
        self.assertEqual(self.cache.get("w342", "abc123.jpg").read_bytes(), JPEG)
        self.assertEqual(len(self.calls), 2)

    def test_clear_deletes_files_and_starts_a_new_generation(self):
        self.cache.get("w342", "abc123.jpg")
        self.assertEqual(self.cache.generation, 0)
        stats = self.cache.clear()
        self.assertEqual((stats["files"], stats["generation"]), (0, 1))
        self.cache.get("w342", "abc123.jpg")
        self.assertEqual(len(self.calls), 2)


class CoverRouteTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.cache = CoverCache(Path(self.folder.name), fetch=lambda url: JPEG)
        self.client = server.app.test_client()

    def tearDown(self):
        self.folder.cleanup()

    def test_image_is_cached_for_a_year_and_errors_are_not(self):
        with patch.object(server, "COVERS", self.cache):
            response = self.client.get("/img/w342/abc123.jpg?g=2")
            self.assertEqual(response.status_code, 200)
            self.assertEqual(response.data, JPEG)
            self.assertEqual(response.mimetype, "image/jpeg")
            self.assertIn("immutable", response.headers["Cache-Control"])
            response.close()
            missing = self.client.get("/img/w342/bad name.jpg")
            self.assertEqual(missing.status_code, 404)
            self.assertEqual(missing.headers["Cache-Control"], "no-store")
            self.assertEqual(self.client.get("/api/covers").json["files"], 1)
            cleared = self.client.delete("/api/covers").json
            self.assertEqual((cleared["files"], cleared["generation"]), (0, 1))
            self.assertEqual(self.client.get("/api/config").json["cover_generation"], 1)


if __name__ == "__main__":
    unittest.main()
