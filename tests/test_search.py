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
        self.assertIn({"id": "tv-mystery", "label": "Mystery"}, feeds["tv_filters"])
        self.assertNotIn("tv-mystery", [f["id"] for f in feeds["movie_filters"]])
        self.assertEqual([f["id"] for f in feeds["cartoon_filters"]],
                         ["cartoon-films", "cartoon-series", "cartoon-kids", "cartoon-disney", "cartoon-pixar",
                          "cartoon-dreamworks", "cartoon-illumination", "cartoon-nickelodeon"])
        self.assertNotIn("cartoon-pixar", [f["id"] for f in feeds["feeds"]])

    def test_studio_chips_list_the_studios_cartoons_from_tmdb(self):
        pages = {("/discover/movie", "3", 1): [{"id": 862, "title": "Історія іграшок", "release_date": "1995-11-22",
                                                "poster_path": "/t.jpg", "vote_average": 8, "popularity": 50},
                                               {"id": 9, "title": "No poster", "poster_path": None, "popularity": 99}],
                 ("/discover/movie", "3", 2): [{"id": 354912, "title": "Коко", "release_date": "2017-10-27",
                                                "poster_path": "/c.jpg", "vote_average": 8.2, "popularity": 80}]}
        calls = []

        def tmdb_get(path, **params):
            calls.append((path, params))
            return {"results": pages.get((path, params.get("with_companies"), params["page"]), [])}
        with patch.object(server, "TMDB_API_KEY", "k"), patch.object(server, "_tmdb_get", side_effect=tmdb_get), \
                patch.object(server, "JACKETT_URL", "http://j"), patch.object(server, "JACKETT_API_KEY", "k"), \
                patch.object(server, "indexer_sections", side_effect=AssertionError("no tracker query")):
            rows = server.app.test_client().get("/api/discover?feed=cartoon-pixar").json["results"]
        self.assertEqual([(r["clean_title"], r["year"], r["media_type"]) for r in rows],
                         [("Коко", "2017", "movie"), ("Історія іграшок", "1995", "movie")])
        self.assertNotIn("magnet", rows[0])
        self.assertTrue(all(p["with_genres"] == 16 and p["with_runtime.gte"] == 40 for _, p in calls))

    def test_cartoon_genres_keep_animated_films_and_shows(self):
        rows = [{"title": "Shrek (2001)", "seeders": 4}, {"title": "Bluey S01", "seeders": 8},
                {"title": "9-1-1 S08", "seeders": 30}, {"title": "Cars (2006)", "seeders": 2}]
        metas = {"Shrek": {"id": 808, "media_type": "movie", "genre_ids": [16, 35, 12], "poster": "s", "rating": 7.7,
                           "overview": "", "title": "Шрек"},
                 "Bluey": {"id": 82728, "media_type": "tv", "genre_ids": [16, 35, 10762], "poster": "b", "rating": 8.8,
                           "overview": "", "title": "Блуї"},
                 "9-1-1": {"id": 75219, "media_type": "tv", "genre_ids": [80, 18], "poster": None, "rating": 8.2,
                           "overview": "", "title": "9-1-1"},
                 "Cars": {"id": 920, "media_type": "movie", "genre_ids": [16, 12], "poster": None, "rating": 6.9,
                          "overview": "", "title": "Тачки"}}
        hints = {}

        def lookup(title, base, year, kind):
            hints[title] = kind
            return metas.get(title)
        with patch.object(server, "TMDB_API_KEY", "k"), patch.object(server, "tmdb_lookup", side_effect=lookup):
            films = server.films_of_genre(rows, {"movie": None}, "cartoon")
            series = server.films_of_genre(rows, {"tv": None}, "cartoon")
        self.assertEqual(sorted(r["clean_title"] for r in films), ["Тачки", "Шрек"])
        self.assertEqual([r["clean_title"] for r in series], ["Блуї"])  # 9-1-1 is not animation
        self.assertEqual(hints, {"Shrek": None, "Bluey": "tv", "9-1-1": "tv", "Cars": None})

    def test_tv_genres_keep_only_shows(self):
        rows = [{"title": "Sherlock S01", "seeders": 3}, {"title": "Knives Out (2019)", "seeders": 9}]
        metas = {"Sherlock": {"id": 19885, "media_type": "tv", "genre_ids": [9648, 80], "poster": "s", "rating": 8.5,
                              "overview": "", "title": "Шерлок"},
                 "Knives Out": {"id": 546554, "media_type": "movie", "genre_ids": [9648], "poster": None, "rating": 7.8,
                                "overview": "", "title": "Ножі наголо"}}
        with patch.object(server, "TMDB_API_KEY", "k"), \
                patch.object(server, "tmdb_lookup", side_effect=lambda title, base, year, kind: metas.get(title)):
            shows = server.films_of_genre(rows, 9648, "tv")
        self.assertEqual([(r["clean_title"], r["media_type"]) for r in shows], [("Шерлок", "tv")])

    def test_only_films_of_the_genre_are_kept_with_their_artwork(self):
        rows = [{"title": "Heat (1995) BDRip", "seeders": 5}, {"title": "Friends S01", "seeders": 9},
                {"title": "Up (2009)", "seeders": 7}, {"title": "Heat (1995) 2160p", "seeders": 50}]
        metas = {"Heat": {"id": 949, "media_type": "movie", "genre_ids": [80, 53], "poster": "p", "rating": 8.3,
                          "overview": "", "title": "Жар"},
                 "Friends": {"id": 1668, "media_type": "tv", "genre_ids": [53], "poster": None, "rating": 8,
                             "overview": "", "title": "Друзі"},
                 "Up": {"id": 14160, "media_type": "movie", "genre_ids": [16], "poster": None, "rating": 8,
                        "overview": "", "title": "Вперед і вгору"}}
        with patch.object(server, "TMDB_API_KEY", "k"), \
                patch.object(server, "tmdb_lookup", side_effect=lambda title, *a: metas.get(title)):
            films = server.films_of_genre(rows, 53)
        self.assertEqual([f["title"] for f in films], ["Heat (1995) 2160p"])  # one row per film, best seeded
        self.assertEqual((films[0]["clean_title"], films[0]["tmdb_id"], films[0]["poster"]), ("Жар", 949, "p"))


if __name__ == "__main__":
    unittest.main()
