"""Favorites shared by every app and the web page."""
import os
import tempfile
import unittest
from pathlib import Path

_sandbox = tempfile.TemporaryDirectory(prefix="torrenttube-test-")
os.environ.setdefault("TORRENTTUBE_DOWNLOAD_DIR", _sandbox.name)
os.environ.setdefault("TORRENTTUBE_STATE_DIR", str(Path(_sandbox.name) / "state"))
import app as server
from favorites import Favorites


class FavoritesStoreTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.path = Path(self.folder.name) / "favorites.json"

    def tearDown(self):
        self.folder.cleanup()

    def test_add_keeps_first_date_and_survives_restart(self):
        store = Favorites(self.path)
        store.add([{"id": "magnet:?xt=1", "title": "Film", "kind": "movie", "added_at": 100}])
        store.add([{"id": "magnet:?xt=1", "title": "Film (2020)", "kind": "movie", "added_at": 500},
                   {"id": "/Movies/Other", "title": "Other", "kind": "cartoon", "added_at": 200,
                    "source_override": {"path": "/Movies/Other", "file": 2, "junk": "x"}}])
        items = Favorites(self.path).items()
        self.assertEqual([i["id"] for i in items], ["/Movies/Other", "magnet:?xt=1"])
        self.assertEqual(items[1]["title"], "Film (2020)")
        self.assertEqual(items[1]["added_at"], 100)
        self.assertEqual(items[0]["source_override"], {"path": "/Movies/Other", "file": 2})

    def test_bad_entries_are_dropped_and_kind_defaults_to_movie(self):
        store = Favorites(self.path)
        store.add([{"title": "No id"}, {"id": "x"}, "text", {"id": "y", "title": "Y", "kind": "music", "tmdb_id": True}])
        self.assertEqual(store.items()[0]["kind"], "movie")
        self.assertNotIn("tmdb_id", store.items()[0])
        self.assertEqual(len(store.items()), 1)

    def test_remove(self):
        store = Favorites(self.path)
        store.add([{"id": "a", "title": "A"}, {"id": "b", "title": "B"}])
        store.remove(["a", 5])
        self.assertEqual([i["id"] for i in Favorites(self.path).items()], ["b"])

    def test_broken_file_starts_empty(self):
        self.path.write_text("{not json")
        self.assertEqual(Favorites(self.path).items(), [])


class FavoritesAPITests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.saved = server.FAVORITES
        server.FAVORITES = Favorites(Path(self.folder.name) / "favorites.json")
        self.client = server.app.test_client()

    def tearDown(self):
        server.FAVORITES = self.saved
        self.folder.cleanup()

    def test_add_list_remove(self):
        self.assertEqual(self.client.get("/api/favorites").get_json(), {"items": []})
        reply = self.client.post("/api/favorites", json={"items": [{"id": "a", "title": "A", "kind": "tv"}]})
        self.assertEqual([i["id"] for i in reply.get_json()["items"]], ["a"])
        reply = self.client.post("/api/favorites/remove", json={"ids": ["a"]})
        self.assertEqual(reply.get_json()["items"], [])

    def test_wrong_body_is_rejected(self):
        self.assertEqual(self.client.post("/api/favorites", json={"items": "a"}).status_code, 400)
        self.assertEqual(self.client.post("/api/favorites/remove", data="x").status_code, 400)

    def test_config_reports_favorites(self):
        self.assertTrue(self.client.get("/api/config").get_json()["capabilities"]["favorites"])


if __name__ == "__main__":
    unittest.main()
