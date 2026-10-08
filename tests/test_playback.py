"""Real libtorrent file/Range checks in an isolated temporary download folder."""
import os
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

_sandbox = tempfile.TemporaryDirectory(prefix="torrenttube-test-")
os.environ["TORRENTTUBE_DOWNLOAD_DIR"] = _sandbox.name
os.environ["TORRENTTUBE_STATE_DIR"] = str(Path(_sandbox.name) / "state")
import app as server
from playback_sessions import PlaybackSessions


class SessionTests(unittest.TestCase):
    def test_paused_heartbeat_renews_lease_and_expiry_does_not_revive(self):
        now = [0]
        sessions = PlaybackSessions(clock=lambda: now[0])
        token = sessions.create("movie", 2)
        now[0] = 80
        self.assertIsNotNone(sessions.touch(token))
        now[0] = 160
        self.assertTrue(sessions.has_viewers("movie"))
        now[0] = 171
        self.assertIsNone(sessions.touch(token))

    def test_closing_one_viewer_preserves_another(self):
        sessions = PlaybackSessions()
        first = sessions.create("movie", 0)
        second = sessions.create("movie", 1)
        sessions.close(first)
        self.assertTrue(sessions.has_viewers("movie"))
        self.assertIsNotNone(sessions.touch(second))
        sessions.close(second)
        self.assertFalse(sessions.has_viewers("movie"))


class PlaybackAPITests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        server.ses.apply_settings({"enable_dht": False, "enable_lsd": False,
                                   "enable_upnp": False, "enable_natpmp": False})

    def setUp(self):
        self.client = server.app.test_client()
        self.folder = tempfile.TemporaryDirectory(dir=_sandbox.name)
        self.first = bytes(range(256)) * 128
        self.second = bytes(reversed(range(256))) * 256
        fs = server.lt.file_storage()
        Path(self.folder.name, "Show").mkdir()
        for name, data in (("episode1.mkv", self.first), ("episode2.mp4", self.second), ("notes.txt", b"notes")):
            Path(self.folder.name, "Show", name).write_bytes(data)
            fs.add_file("Show/" + name, len(data))
        torrent = server.lt.create_torrent(fs, 16384, flags=server.lt.create_torrent.v1_only)
        server.lt.set_piece_hashes(torrent, self.folder.name)
        info = server.lt.torrent_info(torrent.generate())
        self.tid = server.add_torrent_file(info, self.folder.name)
        self.handle = server.HANDLES[self.tid]
        deadline = time.monotonic() + 5
        while not self.handle.status().is_finished:
            if time.monotonic() > deadline:
                self.fail("local fixture was not verified by libtorrent")
            time.sleep(0.02)
        server.PLAYBACK_SESSIONS = PlaybackSessions()

    def tearDown(self):
        server.PLAYBACK_SESSIONS.discard_torrent(self.tid)
        server.STREAM_CACHE_IDS.discard(self.tid)
        handle = server.HANDLES.pop(self.tid, None)
        if handle and handle.is_valid():
            server.ses.remove_torrent(handle)
        for key in list(server.STREAM_FILES):
            if key[0] == self.tid:
                server.STREAM_FILES.pop(key)
        self.folder.cleanup()

    def start(self, file=0):
        response = self.client.post("/api/playback/sessions", json={"id": self.tid, "file": file})
        self.assertEqual(response.status_code, 200, response.json)
        return response.json

    def test_config_has_capabilities_without_secrets(self):
        data = self.client.get("/api/config").json
        self.assertEqual(data["server"], "torrenttube")
        self.assertTrue(data["capabilities"]["playback_sessions"])
        self.assertNotIn("jackett_api_key", data)

    def test_prepare_lists_episodes_and_accepts_explicit_file(self):
        response = self.client.post("/api/playback/prepare", json={"id": self.tid})
        self.assertEqual(response.status_code, 200)
        self.assertEqual([f["index"] for f in response.json["files"]], [0, 1])
        self.assertEqual(response.json["selected"], 1)
        result = self.start(0)
        self.assertEqual(result["file"], 0)
        self.assertEqual(result["name"], "episode1.mkv")

    def test_range_and_suffix_requests_serve_correct_episode_bytes(self):
        result = self.start(0)
        response = self.client.get(result["url"], headers={"Range": "bytes=10-99"})
        self.assertEqual(response.status_code, 206)
        self.assertEqual(response.data, self.first[10:100])
        self.assertEqual(response.headers["Content-Range"], f"bytes 10-99/{len(self.first)}")
        response.close()
        response = self.client.get(result["url"], headers={"Range": "bytes=-20"})
        self.assertEqual(response.data, self.first[-20:])
        response.close()
        response = self.client.get(result["url"], headers={"Range": f"bytes={len(self.first)}-"})
        self.assertEqual(response.status_code, 416)

    def test_invalid_file_and_payload(self):
        for file in (-1, 3, True, "0", 2):
            response = self.client.post("/api/playback/sessions", json={"id": self.tid, "file": file})
            self.assertEqual(response.status_code, 400, response.json)
        self.assertEqual(self.client.post("/api/playback/sessions", json=[]).status_code, 400)
        for payload in ({"magnet": []}, {"download_link": 42}, {"id": {}}):
            self.assertEqual(self.client.post("/api/playback/sessions", json=payload).status_code, 400)
            self.assertEqual(self.client.post("/api/playback/prepare", json=payload).status_code, 400)
        self.assertEqual(self.client.get(f"/api/stream/{self.tid}/99").status_code, 404)

    def test_lease_keeps_paused_cache_alive_and_web_close_cannot_delete_it(self):
        first = self.start(0)
        second = self.start(1)
        server.STREAM_CACHE_IDS.add(self.tid)
        server.STREAM_OPENED.add(self.tid)
        server.STREAM_LAST_CONNECTED[self.tid] = time.time() - 100
        server.STREAM_LAST_USED[self.tid] = time.time() - 7 * 3600
        server.clean_stream_cache()
        self.assertIn(self.tid, server.HANDLES)
        self.assertEqual(self.client.delete(f"/api/stream/{self.tid}").status_code, 409)
        self.client.get(f"/played/m-{self.tid}")
        self.assertIn(self.tid, server.HANDLES)
        self.client.delete(f'/api/playback/sessions/{first["session"]}')
        self.assertIn(self.tid, server.HANDLES)
        self.assertEqual(self.client.post(f'/api/playback/sessions/{second["session"]}', json={}).status_code, 200)
        with patch.object(server, "drop_cached_stream") as drop:
            self.client.delete(f'/api/playback/sessions/{second["session"]}')
            drop.assert_called_once_with(self.tid)
        self.assertEqual(self.client.post(f'/api/playback/sessions/{first["session"]}', json={}).status_code, 410)

    def test_episode_artwork_is_cached_and_inputs_validated(self):
        with patch.object(server, "TMDB_API_KEY", "fixture-key"), patch.object(server, "_tmdb_get") as fetch:
            fetch.return_value = {"episodes": [{"episode_number": 2, "name": "Second", "still_path": "/frame.jpg", "runtime": 42}]}
            result = self.client.get("/api/episodes?id=12345678&season=2")
            self.assertEqual(result.status_code, 200)
            self.assertEqual(result.json["episodes"][0]["number"], 2)
            self.assertTrue(result.json["episodes"][0]["still"].endswith("/frame.jpg"))
            self.client.get("/api/episodes?id=12345678&season=2")
            fetch.assert_called_once()
            self.assertEqual(self.client.get("/api/episodes?id=bad&season=2").status_code, 400)
            self.assertEqual(self.client.get("/api/episodes?id=12&season=-1").status_code, 400)

    def test_legacy_default_still_selects_largest_video(self):
        response = self.client.post("/api/stream", json={"id": self.tid})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json["file"], 1)
        self.client.delete(f"/api/stream/{self.tid}")
        self.assertIn(self.tid, server.HANDLES)


if __name__ == "__main__":
    unittest.main()
