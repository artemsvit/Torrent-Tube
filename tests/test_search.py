"""Torrent search: Jackett's Torznab feed parsed into results."""
import io
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

_sandbox = tempfile.TemporaryDirectory(prefix="torrenttube-search-test-")
os.environ.setdefault("TORRENTTUBE_DOWNLOAD_DIR", _sandbox.name)
os.environ.setdefault("TORRENTTUBE_STATE_DIR", str(Path(_sandbox.name) / "state"))
import app as server

FEED = b"""<?xml version="1.0"?>
<rss xmlns:torznab="http://torznab.com/schemas/2015/feed"><channel>
<item><title>Friends S01 1080p</title><size>2048</size><link>http://x/dl</link>
<torznab:attr name="seeders" value="42"/><torznab:attr name="peers" value="50"/>
<torznab:attr name="magneturl" value="magnet:?xt=urn:btih:abc"/></item>
</channel></rss>"""


class SearchTests(unittest.TestCase):
    def test_torznab_attributes_are_read(self):
        with patch.object(server.urllib.request, "urlopen", return_value=io.BytesIO(FEED)):
            results = server.jackett_query(q="Friends")
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]["seeders"], 42)
        self.assertEqual(results[0]["peers"], 50)
        self.assertEqual(results[0]["magnet"], "magnet:?xt=urn:btih:abc")


class GenreFeedTests(unittest.TestCase):
    def test_genre_feeds_are_movie_filters_not_tabs(self):
        with patch.object(server, "JACKETT_URL", "http://j"), patch.object(server, "JACKETT_API_KEY", "k"):
            feeds = server.app.test_client().get("/api/discover/feeds").json
        self.assertNotIn("thriller", [f["id"] for f in feeds["feeds"]])
        self.assertEqual(feeds["movie_filters"][0], {"id": "action", "label": "Action"})
        self.assertIn({"id": "thriller", "label": "Thriller"}, feeds["movie_filters"])

    def test_only_films_of_the_genre_are_kept_with_their_artwork(self):
        rows = [{"title": "Heat (1995) BDRip"}, {"title": "Friends S01"}, {"title": "Up (2009)"}]
        metas = {"Heat": {"id": 949, "media_type": "movie", "genre_ids": [80, 53], "poster": "p", "rating": 8.3,
                          "overview": "", "title": "Жар"},
                 "Friends": {"id": 1668, "media_type": "tv", "genre_ids": [53], "poster": None, "rating": 8,
                             "overview": "", "title": "Друзі"},
                 "Up": {"id": 14160, "media_type": "movie", "genre_ids": [16], "poster": None, "rating": 8,
                        "overview": "", "title": "Вперед і вгору"}}
        with patch.object(server, "TMDB_API_KEY", "k"), \
                patch.object(server, "tmdb_lookup", side_effect=lambda title, *a: metas.get(title)):
            films = server.films_of_genre(rows, 53)
        self.assertEqual([f["title"] for f in films], ["Heat (1995) BDRip"])
        self.assertEqual((films[0]["clean_title"], films[0]["tmdb_id"], films[0]["poster"]), ("Жар", 949, "p"))


if __name__ == "__main__":
    unittest.main()
