"""The server library: files already in the category folders, played from disk."""
import os
import tempfile
import unittest
from pathlib import Path

_sandbox = tempfile.TemporaryDirectory(prefix="torrenttube-library-test-")
os.environ.setdefault("TORRENTTUBE_DOWNLOAD_DIR", _sandbox.name)
os.environ.setdefault("TORRENTTUBE_STATE_DIR", str(Path(_sandbox.name) / "state"))
import app as server
from media_library import MediaLibrary


class MediaLibraryTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.TemporaryDirectory()
        root = Path(self.root.name)
        (root / "Movies").mkdir()
        (root / "Movies" / "Heat (1995).mkv").write_bytes(b"m" * 1000)
        (root / "Movies" / "notes.txt").write_text("not a video")
        (root / "Movies" / "@eaDir").mkdir()
        (root / "Movies" / "@eaDir" / "thumb.mkv").write_bytes(b"x")
        show = root / "TV Shows" / "Chernobyl" / "Season 1"
        show.mkdir(parents=True)
        for n in (10, 2, 1):
            (show / f"Chernobyl.S01E{n:02d}.mkv").write_bytes(bytes([n]) * 100)
        (root / "TV Shows" / "Empty").mkdir()
        (root / "Cartoon" / "Bluey (2018)").mkdir(parents=True)
        for name in ("1-1-2 Чарівний ксилофон & Лікарня.mp4", "1-3-4 Підкидайки.mp4", "2-1-2 Танці.mp4"):
            (root / "Cartoon" / "Bluey (2018)" / name).write_bytes(b"b" * 100)
        saga = root / "Movies" / "The Fast and the Furious. Collection"
        saga.mkdir()
        for name in ("[01] The Fast and the Furious (2001) BDRip 1080p.mkv", "[05] Fast Five (2011) BDRip 1080p.mkv"):
            (saga / name).write_bytes(b"f" * 100)
        parts = root / "Movies" / "Dune (2021)"
        parts.mkdir()
        for name in ("Dune (2021) CD1.mkv", "Dune (2021) CD2.mkv"):
            (parts / name).write_bytes(b"d" * 100)
        (root / ".stream-cache").mkdir()
        (root / ".stream-cache" / "partial.mkv").write_bytes(b"p")
        self.library = MediaLibrary(root, ["Cartoon", "Movies", "TV Shows"], server.VIDEO_EXTS,
                                    describe=server.LIBRARY.describe)

    def tearDown(self):
        self.root.cleanup()

    def test_lists_one_title_per_file_or_folder_and_skips_the_rest(self):
        items = {item["id"]: item for item in self.library.items()}
        self.assertEqual(set(items), {"Movies/Heat (1995).mkv", "TV Shows/Chernobyl", "Cartoon/Bluey (2018)",
                                      "Movies/Dune (2021)",
                                      "Movies/The Fast and the Furious. Collection/[01] The Fast and the Furious (2001) BDRip 1080p.mkv",
                                      "Movies/The Fast and the Furious. Collection/[05] Fast Five (2011) BDRip 1080p.mkv"})
        self.assertEqual(items["Movies/Heat (1995).mkv"]["name"], "Heat (1995)")
        self.assertEqual(items["Movies/Heat (1995).mkv"]["kind"], "movie")
        self.assertEqual(items["TV Shows/Chernobyl"]["kind"], "tv")
        self.assertEqual(items["TV Shows/Chernobyl"]["files"], 3)

    def test_a_collection_folder_is_a_title_per_film(self):
        items = {item["id"]: item for item in self.library.items()}
        five = items["Movies/The Fast and the Furious. Collection/[05] Fast Five (2011) BDRip 1080p.mkv"]
        self.assertEqual((five["title"], five["year"], five["files"], five["kind"]), ("Fast Five", "2011", 1, "movie"))
        self.assertEqual([f["name"] for f in self.library.files(five["id"])], ["[05] Fast Five (2011) BDRip 1080p.mkv"])
        # One film in two parts stays one title.
        self.assertEqual(items["Movies/Dune (2021)"]["files"], 2)

    def test_series_count_their_seasons_films_none(self):
        items = {item["id"]: item for item in self.library.items()}
        self.assertEqual(items["TV Shows/Chernobyl"]["seasons"], 1)
        self.assertEqual(items["Movies/Heat (1995).mkv"]["seasons"], 0)
        # "1-1-2 Name": season 1, episodes 1 and 2 in one file.
        self.assertEqual(items["Cartoon/Bluey (2018)"]["seasons"], 2)

    def test_files_carry_their_season_and_episode(self):
        files = {f["name"]: f for f in self.library.files("Cartoon/Bluey (2018)")}
        self.assertEqual({k: files["1-3-4 Підкидайки.mp4"][k] for k in ("season", "episode", "last_episode")},
                         {"season": 1, "episode": 3, "last_episode": 4})
        self.assertNotIn("season", self.library.files("Movies/Heat (1995).mkv")[0])

    def test_episodes_play_in_natural_order(self):
        names = [f["name"] for f in self.library.files("TV Shows/Chernobyl")]
        self.assertEqual(names, ["Chernobyl.S01E01.mkv", "Chernobyl.S01E02.mkv", "Chernobyl.S01E10.mkv"])

    def test_paths_outside_the_category_folders_are_refused(self):
        for bad in ("../etc/passwd", "Movies/../../etc", ".stream-cache/partial.mkv", "Movies/@eaDir/thumb.mkv",
                    "Elsewhere/file.mkv", "", "Movies/missing.mkv"):
            self.assertIsNone(self.library.resolve(bad), bad)
            self.assertIsNone(self.library.files(bad), bad)


class LibraryAPITests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.TemporaryDirectory()
        root = Path(self.root.name)
        (root / "Movies").mkdir()
        self.data = bytes(range(256)) * 40
        (root / "Movies" / "Heat (1995).mkv").write_bytes(self.data)
        self.saved = server.LIBRARY
        server.LIBRARY = MediaLibrary(root, ["Movies"], server.VIDEO_EXTS)
        self.client = server.app.test_client()

    def tearDown(self):
        server.LIBRARY = self.saved
        self.root.cleanup()

    def test_list_prepare_session_and_ranged_playback(self):
        items = self.client.get("/api/library").json["items"]
        self.assertEqual([i["id"] for i in items], ["Movies/Heat (1995).mkv"])
        prepared = self.client.post("/api/playback/prepare", json={"path": items[0]["id"]}).json
        self.assertEqual(prepared["id"], "lib:Movies/Heat (1995).mkv")
        self.assertEqual(len(prepared["files"]), 1)
        session = self.client.post("/api/playback/sessions", json={"path": items[0]["id"], "file": 0}).json
        self.assertTrue(session["ready"])
        self.assertEqual(session["url"], "/media/Movies/Heat%20%281995%29.mkv")
        ranged = self.client.get(session["url"], headers={"Range": "bytes=100-199"})
        self.assertEqual(ranged.status_code, 206)
        self.assertEqual(ranged.data, self.data[100:200])
        ranged.close()
        heartbeat = self.client.post(f"/api/playback/sessions/{session['session']}")
        self.assertTrue(heartbeat.json["ready"])
        self.assertEqual(self.client.delete(f"/api/playback/sessions/{session['session']}").json, {"ok": True})
        self.assertTrue((Path(self.root.name) / "Movies" / "Heat (1995).mkv").exists(), "closing never deletes a library file")

    def test_playlist_lists_the_episodes_from_the_chosen_one(self):
        bad = self.client.post("/api/library/playlist", json={"token": "0123456789abcdef", "files": ["../secret"]})
        self.assertEqual(bad.status_code, 404)
        ok = self.client.post("/api/library/playlist", json={"token": "0123456789abcdef", "files": ["Movies/Heat (1995).mkv"]}).json
        self.assertEqual(ok["url"], "/playlist/0123456789abcdef.m3u")
        playlist = self.client.get(ok["url"])
        self.assertEqual(playlist.mimetype, "audio/x-mpegurl")
        text = playlist.get_data(as_text=True)
        self.assertTrue(text.startswith("#EXTM3U\n#EXTINF:-1,Heat (1995)\n"))
        self.assertIn("/media/Movies/Heat%20%281995%29.mkv", text)

    def test_bad_paths_and_indexes(self):
        self.assertEqual(self.client.post("/api/playback/prepare", json={"path": "../secret"}).status_code, 404)
        self.assertEqual(self.client.post("/api/playback/sessions", json={"path": "Movies/Heat (1995).mkv", "file": 5}).status_code, 400)
        self.assertEqual(self.client.get("/media/..%2Fsecret").status_code, 404)
        self.assertEqual(self.client.get("/media/Movies/missing.mkv").status_code, 404)


if __name__ == "__main__":
    unittest.main()
