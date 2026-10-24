"""Library collections: which TMDB collection a film is in, and its place in it."""
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

_sandbox = tempfile.TemporaryDirectory(prefix="torrenttube-collections-test-")
os.environ.setdefault("TORRENTTUBE_DOWNLOAD_DIR", _sandbox.name)
os.environ.setdefault("TORRENTTUBE_STATE_DIR", str(Path(_sandbox.name) / "state"))
import app as server

HARRY_POTTER = {"id": 1241, "name": "Гаррі Поттер (Колекція)", "overview": "Хлопчик-чарівник.",
                "poster_path": "/p.jpg", "backdrop_path": "/b.jpg",
                "parts": [{"id": 672, "release_date": "2002-11-13"}, {"id": 671, "release_date": "2001-11-16"},
                          {"id": 673, "release_date": "2004-05-31"}]}


def tmdb(path, **params):
    if path == "/collection/1241":
        return HARRY_POTTER
    if path in ("/movie/671", "/movie/672"):
        return {"belongs_to_collection": {"id": 1241, "name": "Harry Potter Collection"}}
    return {"belongs_to_collection": None}


class CollectionTests(unittest.TestCase):
    def setUp(self):
        self.meta = dict(server.LIBRARY_META)
        server.TMDB_CACHE.clear()
        server.LIBRARY_META.clear()
        server.LIBRARY_META.update({
            "Movies/HP2": {"tmdb_id": 672, "media_type": "movie", "structure": "movie", "checked": 1},
            "Movies/Heat": {"tmdb_id": 949, "media_type": "movie", "structure": "movie", "checked": 1},
        })

    def tearDown(self):
        server.LIBRARY_META.clear()
        server.LIBRARY_META.update(self.meta)
        server.TMDB_CACHE.clear()

    def test_a_film_gets_its_collection_and_part(self):
        with patch.object(server, "_tmdb_get", side_effect=tmdb):
            server._lookup_library_collection("Movies/HP2", 672)
            server._lookup_library_collection("Movies/Heat", 949)
        collection = server.LIBRARY_META["Movies/HP2"]["collection"]
        self.assertEqual(collection["id"], 1241)
        self.assertEqual(collection["name"], "Гаррі Поттер (Колекція)")
        self.assertEqual(collection["part"], 2)  # by release date, not TMDB's order
        self.assertEqual(collection["total"], 3)
        self.assertTrue(collection["backdrop"].endswith("/w1280/b.jpg"))
        self.assertIsNone(server.LIBRARY_META["Movies/Heat"]["collection"])
        self.assertIn("collection_checked", server.LIBRARY_META["Movies/Heat"])

    def test_the_collection_is_asked_once_for_all_its_films(self):
        with patch.object(server, "_tmdb_get", side_effect=tmdb) as get:
            server.tmdb_collection(1241)
            server.tmdb_collection(1241)
        self.assertEqual([c.args[0] for c in get.call_args_list].count("/collection/1241"), 1)

    def test_library_items_carry_the_collection_and_shows_never_do(self):
        server.LIBRARY_META["Movies/HP2"].update(collection={"id": 1241, "name": "HP", "part": 2}, collection_checked=9e12)
        server.LIBRARY_META["TV Shows/Show"] = {"tmdb_id": 5, "media_type": "tv", "structure": "tv", "checked": 1,
                                                "collection_checked": 9e12}
        items = [{"id": "Movies/HP2", "name": "HP2", "kind": "movie", "files": 1, "episodes": 0, "added": 1},
                 {"id": "TV Shows/Show", "name": "Show", "kind": "tv", "files": 3, "episodes": 3, "added": 1}]
        with patch.object(server, "TMDB_API_KEY", ""):
            merged, _ = server._library_with_metadata(items)
        by_id = {i["id"]: i for i in merged}
        self.assertEqual(by_id["Movies/HP2"]["collection"]["part"], 2)
        self.assertNotIn("collection", by_id["TV Shows/Show"])


if __name__ == "__main__":
    unittest.main()
