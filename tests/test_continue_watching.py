"""Focused sync regressions: two devices, stale writes, clear, and persistence."""
import os
import tempfile
import unittest
from pathlib import Path

_sandbox = tempfile.TemporaryDirectory(prefix="torrenttube-test-")
os.environ.setdefault("TORRENTTUBE_DOWNLOAD_DIR", _sandbox.name)
os.environ.setdefault("TORRENTTUBE_STATE_DIR", str(Path(_sandbox.name) / "state"))
import app as server
from continue_watching import ContinueWatching


def position(timestamp=100, seconds=120, file=0):
    return dict(torrent_id="same-film", file=file, title="Film", source={"id": "same-film", "file": file},
                seconds=seconds, duration=3600, updated_at=timestamp, removed=False)


class ContinueWatchingTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.path = Path(self.folder.name) / "continue-watching.json"
        self.saved = server.CONTINUE_WATCHING
        server.CONTINUE_WATCHING = ContinueWatching(self.path)
        self.first = server.app.test_client()
        self.second = server.app.test_client()

    def tearDown(self):
        server.CONTINUE_WATCHING = self.saved
        self.folder.cleanup()

    def send(self, client, items, **extra):
        return client.post("/api/continue-watching", json=dict(items=items, **extra))

    def test_devices_share_position_seek_back_and_reject_stale_migration(self):
        self.send(self.first, [position()])
        self.assertEqual(self.second.get("/api/continue-watching").get_json()["items"][0]["seconds"], 120)
        self.send(self.second, [position(200, 60)])  # A deliberate backward seek wins by date.
        self.send(self.first, [position(100, 120)])
        self.assertEqual(ContinueWatching(self.path).items()[0]["seconds"], 60)
        self.assertEqual(self.first.get("/api/continue-watching").headers["Cache-Control"], "no-store")

    def test_completion_and_clear_survive_restart_and_do_not_resurrect(self):
        self.send(self.first, [position(), position(file=1)])
        self.send(self.second, [dict(torrent_id="same-film", file=0, updated_at=200, removed=True)])
        server.CONTINUE_WATCHING = ContinueWatching(self.path)
        self.send(self.first, [position()])
        self.assertEqual([e["file"] for e in server.CONTINUE_WATCHING.items()], [1])
        self.send(self.second, [], clear_before=300)
        server.CONTINUE_WATCHING = ContinueWatching(self.path)
        self.send(self.first, [position(250)])
        self.assertEqual(server.CONTINUE_WATCHING.items(), [])
        self.send(self.first, [position(400)])
        self.assertEqual(len(server.CONTINUE_WATCHING.items()), 1)

    def test_invalid_payload_and_capability(self):
        for body in ([], {"items": "bad"}, None):
            self.assertEqual(self.first.post("/api/continue-watching", json=body).status_code, 400)
        self.send(self.first, [position(seconds=float("nan")), position(seconds=-1), dict(position(), source={})])
        self.assertEqual(server.CONTINUE_WATCHING.items(), [])
        self.assertTrue(self.first.get("/api/config").get_json()["capabilities"]["continue_watching"])


if __name__ == "__main__":
    unittest.main()
