"""Skip intro: find a season's opening the way Plex and Jellyfin's Intro
Skipper do - the episodes of a season share their theme music, so the
longest stretch of sound two neighbouring episodes have in common is the
intro. Sound is compared as Chromaprint fingerprints (fpcalc -raw): one
32-bit point per ~0.124 s, nearly equal points (few differing bits) mean
the same sound. Results are saved, so each episode is analysed once."""
import json
import os
import re
import shutil
import subprocess
import threading
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

POINT_SECONDS = 0.1238      # one Chromaprint point (4096 samples at 11025 Hz, 2/3 overlap)
MAX_BIT_DIFF = 6            # points this close are the same sound
MAX_GAP_SECONDS = 3.5       # a quiet moment inside the intro does not split it
MIN_INTRO_SECONDS = 15
MAX_INTRO_SECONDS = 150
ANALYZE_SECONDS = 900       # intros come within 15 minutes, even after a long cold open
VERSION = 3                 # part of each saved key: a new version looks again
CANDIDATE_SHIFTS = 12


def _natural(name):
    return [int(part) if part.isdigit() else part.lower() for part in re.split(r"(\d+)", name)]


def complete(path):
    """False for a file still being downloaded: a torrent reserves the full
    size up front, but the missing parts take no space on disk."""
    try:
        stat = path.stat()
    except OSError:
        return False
    blocks = getattr(stat, "st_blocks", None)
    return blocks is None or stat.st_size == 0 or blocks * 512 >= stat.st_size * 0.9


def _bits(value):
    return bin(value).count("1")


def fingerprint(path, fpcalc, seconds=ANALYZE_SECONDS):
    """The raw fingerprint of the first `seconds` of a file, or None."""
    try:
        result = subprocess.run([fpcalc, "-raw", "-length", str(seconds), str(path)],
                                capture_output=True, text=True, timeout=300)
    except (OSError, subprocess.TimeoutExpired):
        return None
    for line in result.stdout.splitlines():
        if line.startswith("FINGERPRINT="):
            try:
                return [int(v) & 0xFFFFFFFF for v in line.split("=", 1)[1].split(",") if v]
            except ValueError:
                return None
    return None


def shared_segment(a, b):
    """The longest stretch of sound both fingerprints share, as
    (a_start, a_end, b_start, b_end) in seconds, or None."""
    if not a or not b:
        return None
    positions = {}
    for j, value in enumerate(b):
        positions.setdefault(value, []).append(j)
    # Shifts where identical points line up are the candidate alignments.
    votes = Counter()
    for i, value in enumerate(a):
        for j in positions.get(value, ()):
            votes[j - i] += 1
    max_gap = MAX_GAP_SECONDS / POINT_SECONDS
    best = None
    for shift, _ in votes.most_common(CANDIDATE_SHIFTS):
        matches = [i for i in range(max(0, -shift), min(len(a), len(b) - shift))
                   if _bits(a[i] ^ b[i + shift]) <= MAX_BIT_DIFF]
        if not matches:
            continue
        start = previous = matches[0]
        for i in matches[1:] + [None]:
            if i is not None and i - previous <= max_gap:
                previous = i
                continue
            duration = (previous - start) * POINT_SECONDS
            if MIN_INTRO_SECONDS <= duration <= MAX_INTRO_SECONDS and (best is None or duration > best[0]):
                best = (duration, start, previous, shift)
            if i is not None:
                start = previous = i
    if best is None:
        return None
    _, start, end, shift = best
    return (round(start * POINT_SECONDS, 2), round(end * POINT_SECONDS, 2),
            round((start + shift) * POINT_SECONDS, 2), round((end + shift) * POINT_SECONDS, 2))


class IntroDetector:
    def __init__(self, library, state_file, fpcalc=None):
        self.library = library
        self.state_file = Path(state_file)
        self.fpcalc = fpcalc if fpcalc is not None else shutil.which("fpcalc")
        self._lock = threading.Lock()
        self._pending = set()
        self._fingerprints = {}
        self._executor = ThreadPoolExecutor(max_workers=1)  # one at a time: the NAS keeps streaming
        try:
            self._results = json.loads(self.state_file.read_text())
        except (OSError, ValueError):
            self._results = {}

    @staticmethod
    def _key(path):
        stat = path.stat()
        return f"v{VERSION}|{path.name}|{stat.st_size}|{int(stat.st_mtime)}"

    def _save(self):
        try:
            tmp = self.state_file.with_suffix(".tmp")
            tmp.write_text(json.dumps(self._results))
            os.replace(tmp, self.state_file)
        except OSError:
            pass

    def intro(self, relative):
        """{"status": "ready", "start", "end"} | {"status": "none"} |
        {"status": "pending"} | {"status": "unavailable"}."""
        path = self.library.resolve(relative)
        if path is None or not path.is_file():
            return None
        if not self.fpcalc:
            return {"status": "unavailable"}
        if not complete(path):
            return {"status": "none"}  # not saved: asked again once the download is done
        key = f"{relative}|{self._key(path)}"
        with self._lock:
            found = self._results.get(key)
            if found is not None:
                return {"status": "ready", **found} if found else {"status": "none"}
            if key not in self._pending:
                self._pending.add(key)
                self._executor.submit(self._detect, relative, path, key)
        return {"status": "pending"}

    def _fingerprint(self, path):
        key = self._key(path)
        if key not in self._fingerprints:
            if len(self._fingerprints) >= 24:
                self._fingerprints.pop(next(iter(self._fingerprints)))
            self._fingerprints[key] = fingerprint(path, self.fpcalc)
        return self._fingerprints[key]

    def _detect(self, relative, path, key):
        try:
            siblings = sorted((p for p in path.parent.iterdir() if p.is_file() and self.library._is_video(p) and complete(p)),
                              key=lambda p: _natural(p.name))
            here = siblings.index(path) if path in siblings else -1
            # The next episode first, then the previous one.
            neighbours = [siblings[i] for i in (here + 1, here - 1) if 0 <= i < len(siblings) and i != here]
            result = {}
            mine = self._fingerprint(path) if neighbours else None
            if neighbours and mine is None:
                return  # fpcalc failed: try again next time, do not save "no intro"
            for other in neighbours:
                segment = shared_segment(mine, self._fingerprint(other))
                if segment:
                    result = {"start": segment[0], "end": segment[1]}
                    other_relative = (Path(relative).parent / other.name).as_posix()
                    with self._lock:
                        self._results[f"{other_relative}|{self._key(other)}"] = {"start": segment[2], "end": segment[3]}
                    break
            with self._lock:
                self._results[key] = result
                self._save()
        except OSError:
            pass
        finally:
            with self._lock:
                self._pending.discard(key)
