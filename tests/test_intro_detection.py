"""Skip intro: the shared opening of neighbouring episodes, found by sound."""
import os
import random
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

_sandbox = tempfile.TemporaryDirectory(prefix="torrenttube-intro-test-")
os.environ.setdefault("TORRENTTUBE_DOWNLOAD_DIR", _sandbox.name)
os.environ.setdefault("TORRENTTUBE_STATE_DIR", str(Path(_sandbox.name) / "state"))
import app as server
import intro_detection
from intro_detection import IntroDetector, POINT_SECONDS, shared_segment
from media_library import MediaLibrary

rng = random.Random(7)
INTRO = [rng.getrandbits(32) for _ in range(int(40 / POINT_SECONDS))]  # 40 s of theme music


def noise(seconds):
    return [rng.getrandbits(32) for _ in range(int(seconds / POINT_SECONDS))]


def episode(before, after=200):
    """`before` s of cold open, the intro, then the episode."""
    return noise(before) + [v ^ (1 << rng.randrange(32)) for v in INTRO] + noise(after)


class SharedSegmentTests(unittest.TestCase):
    def test_finds_the_intro_at_different_places(self):
        found = shared_segment(episode(30), episode(95))
        self.assertIsNotNone(found)
        a_start, a_end, b_start, b_end = found
        self.assertAlmostEqual(a_start, 30, delta=1)
        self.assertAlmostEqual(a_end, 70, delta=1)
        self.assertAlmostEqual(b_start, 95, delta=1)
        self.assertAlmostEqual(b_end, 135, delta=1)

    def test_no_shared_sound_means_no_intro(self):
        self.assertIsNone(shared_segment(noise(300), noise(300)))

    def test_a_short_logo_is_not_an_intro(self):
        logo = INTRO[:int(5 / POINT_SECONDS)]
        self.assertIsNone(shared_segment(noise(20) + logo + noise(200), noise(50) + logo + noise(200)))


class DetectorTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.TemporaryDirectory()
        season = Path(self.root.name) / "TV Shows" / "Show" / "Season 1"
        season.mkdir(parents=True)
        self.prints = {}
        for n, before in ((1, 10), (2, 60), (3, 25)):
            name = f"Show.S01E{n:02d}.mkv"
            (season / name).write_bytes(bytes([n]) * 10)
            self.prints[name] = episode(before)
        self.library = MediaLibrary(Path(self.root.name), ["TV Shows"], server.VIDEO_EXTS)
        self.detector = IntroDetector(self.library, Path(self.root.name) / "intros.json", fpcalc="/tools/fpcalc")

    def tearDown(self):
        self.detector._executor.shutdown(wait=True)
        self.root.cleanup()

    def test_pending_then_ready_for_the_episode_and_its_neighbour(self):
        with patch.object(intro_detection, "fingerprint", side_effect=lambda path, fpcalc, seconds=600: self.prints[Path(path).name]):
            first = self.detector.intro("TV Shows/Show/Season 1/Show.S01E01.mkv")
            self.assertEqual(first, {"status": "pending"})
            self.detector._executor.submit(lambda: None).result()  # the queued job has finished
            ready = self.detector.intro("TV Shows/Show/Season 1/Show.S01E01.mkv")
            next_one = self.detector.intro("TV Shows/Show/Season 1/Show.S01E02.mkv")
        self.assertEqual(ready["status"], "ready")
        self.assertAlmostEqual(ready["start"], 10, delta=1)
        self.assertAlmostEqual(ready["end"], 50, delta=1)
        self.assertEqual(next_one["status"], "ready", "the neighbour's intro is saved too")
        self.assertAlmostEqual(next_one["start"], 60, delta=1)
        reloaded = IntroDetector(self.library, Path(self.root.name) / "intros.json", fpcalc="/tools/fpcalc")
        self.assertEqual(reloaded.intro("TV Shows/Show/Season 1/Show.S01E01.mkv")["status"], "ready")

    def test_unfinished_downloads_are_not_analysed(self):
        sparse = Path(self.root.name) / "TV Shows" / "Show" / "Season 1" / "Show.S01E04.mkv"
        with open(sparse, "wb") as handle:
            handle.truncate(50 * 1024 * 1024)  # full size reserved, nothing written yet
        self.assertFalse(intro_detection.complete(sparse))
        self.assertTrue(intro_detection.complete(Path(self.root.name) / "TV Shows" / "Show" / "Season 1" / "Show.S01E01.mkv"))
        self.assertEqual(self.detector.intro("TV Shows/Show/Season 1/Show.S01E04.mkv"), {"status": "none"})

    def test_without_fpcalc_or_outside_the_library(self):
        self.assertEqual(IntroDetector(self.library, Path(self.root.name) / "x.json", fpcalc="").intro("TV Shows/Show/Season 1/Show.S01E01.mkv"),
                         {"status": "unavailable"})
        self.assertIsNone(self.detector.intro("../etc/passwd"))


if __name__ == "__main__":
    unittest.main()
