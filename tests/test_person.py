import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

_sandbox = tempfile.TemporaryDirectory(prefix="torrenttube-person-test-")
os.environ.setdefault("TORRENTTUBE_DOWNLOAD_DIR", _sandbox.name)
os.environ.setdefault("TORRENTTUBE_STATE_DIR", str(Path(_sandbox.name) / "state"))
import app as server


def _credit(id, media_type, title, popularity, poster="/p.jpg", genres=(), date="2010-07-16"):
    key = "title" if media_type == "movie" else "name"
    date_key = "release_date" if media_type == "movie" else "first_air_date"
    return {"id": id, "media_type": media_type, key: title, date_key: date, "poster_path": poster,
            "popularity": popularity, "vote_average": 8.1234, "genre_ids": list(genres)}


class TestPersonCredits(unittest.TestCase):
    def setUp(self):
        server.TMDB_CACHE.clear()

    def test_cast_first_by_popularity_then_crew_without_duplicates(self):
        data = {"name": "Leonardo DiCaprio", "profile_path": "/l.jpg", "known_for_department": "Acting",
                "combined_credits": {
                    "cast": [_credit(1, "movie", "Inception", 50), _credit(2, "movie", "Titanic", 90),
                             _credit(3, "movie", "No poster", 99, poster=None),
                             _credit(4, "tv", "Late Night Show", 70, genres=[10767])],
                    "crew": [_credit(1, "movie", "Inception", 50), _credit(5, "movie", "The Producer Film", 95)]}}
        with mock.patch.object(server, "_tmdb_get", return_value=data):
            result = server.tmdb_person(6193)
        self.assertEqual(result["name"], "Leonardo DiCaprio")
        self.assertEqual([t["title"] for t in result["titles"]], ["Titanic", "Inception", "The Producer Film"])
        self.assertEqual(result["titles"][0]["rating"], 8.1)
        self.assertEqual(result["titles"][0]["year"], "2010")

    def test_endpoint_rejects_a_bad_id(self):
        with mock.patch.object(server, "TMDB_API_KEY", "key"):
            response = server.app.test_client().get("/api/person?id=abc")
        self.assertEqual(response.status_code, 400)


if __name__ == "__main__":
    unittest.main()
