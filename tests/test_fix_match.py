"""Fix match: a library title matched to the wrong film is matched by hand,
in the language chosen, and stays that way."""
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

_sandbox = tempfile.TemporaryDirectory(prefix="torrenttube-fix-match-test-")
os.environ.setdefault("TORRENTTUBE_DOWNLOAD_DIR", _sandbox.name)
os.environ.setdefault("TORRENTTUBE_STATE_DIR", str(Path(_sandbox.name) / "state"))
import app as server

FILM = "Home Alone (1990) BDRip 1080p [Ukr,Eng].mkv"
ID = f"Movies/{FILM}"


def tmdb(path, **params):
    if path == "/search/movie":
        assert params["language"] == "en-US" and params["year"] == "1990"
        return {"results": [{"id": 771, "title": "Home Alone", "original_title": "Home Alone",
                             "release_date": "1990-11-16", "poster_path": "/h.jpg", "vote_count": 10000}]}
    if path == "/search/multi":
        return {"results": [{"id": 1, "media_type": "person", "name": "Someone"},
                            {"id": 771, "media_type": "movie", "title": "Сам удома", "release_date": "1990-11-16"}]}
    if path == "/movie/771":
        return {"id": 771, "title": "Home Alone" if params["language"] == "en-US" else "Сам удома",
                "release_date": "1990-11-16", "poster_path": "/h.jpg", "vote_average": 7.4, "overview": "Kevin.",
                "genres": [{"id": 35}], "vote_count": 10000}
    raise AssertionError(path)


class FixMatchTests(unittest.TestCase):
    def setUp(self):
        self.client = server.app.test_client()
        (server.DOWNLOAD_DIR / "Movies").mkdir(parents=True, exist_ok=True)
        (server.DOWNLOAD_DIR / "Movies" / FILM).write_bytes(b"v" * 10)
        server.LIBRARY.items(refresh=True)
        self.meta = dict(server.LIBRARY_META)
        server.LIBRARY_META[ID] = {"checked": 9e12, "structure": "movie", "tmdb_id": 999, "media_type": "movie",
                                   "display_title": "Коля дома один", "confident": True}
        self.key = patch.object(server, "TMDB_API_KEY", "k")
        self.key.start()

    def tearDown(self):
        self.key.stop()
        server.LIBRARY_META.clear()
        server.LIBRARY_META.update(self.meta)
        (server.DOWNLOAD_DIR / "Movies" / FILM).unlink()
        server.LIBRARY.items(refresh=True)

    def test_the_screen_shows_the_file_names_and_the_current_match(self):
        info = self.client.get("/api/library/match", query_string={"id": ID}).json
        self.assertEqual(info["files"], [FILM])
        self.assertEqual(info["query"], "Home Alone")
        self.assertEqual(info["year"], "1990")
        self.assertEqual(info["type"], "movie")
        self.assertEqual(info["current"]["title"], "Коля дома один")
        self.assertIn("en-US", info["languages"])
        self.assertEqual(self.client.get("/api/library/match", query_string={"id": "../etc"}).status_code, 404)

    def test_search_in_a_language_with_a_year(self):
        with patch.object(server, "_tmdb_get", side_effect=tmdb):
            found = self.client.get("/api/library/match/search",
                                    query_string={"q": "Home Alone", "type": "movie", "language": "en-US", "year": "1990"}).json
            both = self.client.get("/api/library/match/search", query_string={"q": "Сам удома"}).json
        self.assertEqual(found["results"][0]["tmdb_id"], 771)
        self.assertEqual(found["results"][0]["poster"], "https://image.tmdb.org/t/p/w342/h.jpg")
        self.assertEqual([r["media_type"] for r in both["results"]], ["movie"])  # people are left out

    def test_a_fixed_match_is_kept_in_its_language_and_survives_a_rescan(self):
        with patch.object(server, "_tmdb_get", side_effect=tmdb):
            saved = self.client.post("/api/library/match", json={"id": ID, "tmdb_id": 771, "media_type": "movie",
                                                                 "language": "en-US"})
        self.assertEqual(saved.status_code, 200)
        with patch.object(server.TMDB_EXECUTOR, "submit") as lookup:
            item = next(i for i in server._library_with_metadata(server.LIBRARY.items())[0] if i["id"] == ID)
        self.assertEqual((item["tmdb_id"], item["display_title"]), (771, "Home Alone"))
        self.assertTrue(item["metadata_manual"])
        self.assertEqual(item["metadata_language"], "en-US")
        self.assertFalse(any(c.args[0] is server._lookup_library_item for c in lookup.call_args_list))
        self.client.delete("/api/library/metadata")
        self.assertTrue(server.LIBRARY_META[ID]["manual"])

    def test_a_latin_ukrainian_name_is_tried_in_cyrillic(self):
        self.assertEqual(server.ukrainian_letters("Vartovi Halaktyky 3"), "Вартові Галактики 3")
        asked = []

        def tmdb_search(path, **params):
            asked.append((params["query"], params.get("year")))
            return {"results": [{"id": 447365, "title": "Вартові Галактики 3", "release_date": "2023-05-03"}]
                    if params["query"] == "Вартові Галактики 3" and "year" not in params else []}
        with patch.object(server, "_tmdb_get", side_effect=tmdb_search):
            found = self.client.get("/api/library/match/search",
                                    query_string={"q": "Vartovi Halaktyky 3", "type": "movie", "year": "2024"}).json
        self.assertEqual(found["results"][0]["tmdb_id"], 447365)
        self.assertEqual(found["query"], "Вартові Галактики 3")
        self.assertEqual(asked, [("Vartovi Halaktyky 3", "2024"), ("Vartovi Halaktyky 3", None),
                                 ("Вартові Галактики 3", "2024"), ("Вартові Галактики 3", None)])

    def test_reset_matches_automatically_again(self):
        server.LIBRARY_META[ID]["manual"] = True
        self.assertEqual(self.client.delete("/api/library/match", json={"id": ID}).status_code, 200)
        self.assertNotIn(ID, server.LIBRARY_META)

    def test_bad_requests(self):
        self.assertEqual(self.client.post("/api/library/match", json={"id": ID, "tmdb_id": "771", "media_type": "movie"}).status_code, 400)
        self.assertEqual(self.client.post("/api/library/match", json={"id": "nope", "tmdb_id": 1, "media_type": "movie"}).status_code, 404)

    def test_details_in_a_titles_own_language(self):
        with patch.object(server, "tmdb_details", return_value={"title": "Home Alone"}) as details:
            self.client.get("/api/details", query_string={"type": "movie", "id": "771", "language": "en-US"})
            self.client.get("/api/details", query_string={"type": "movie", "id": "771", "language": "x;drop"})
        self.assertEqual(details.call_args_list[0].args, ("movie", 771, "en-US"))
        self.assertEqual(details.call_args_list[1].args, ("movie", 771, None))


if __name__ == "__main__":
    unittest.main()
