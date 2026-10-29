"""TMDB posters, backdrops and stills, kept on the server.

The web page asks for /img/<size>/<file> instead of image.tmdb.org: the
first request fetches the image from TMDB and saves it here, every later
one is a file read. A browser that can't reach TMDB (an ad blocker, a
filtered network) still gets every cover, and a file that is here never
changes - TMDB names a new image with a new file name - so browsers may
keep it for a year. Clearing starts a new generation, which the page puts
in its image links, so browsers fetch every cover again too."""
import os
import re
import shutil
import threading
import urllib.request
from pathlib import Path

TMDB_IMAGES = "https://image.tmdb.org/t/p"
SIZES = {"w45", "w92", "w154", "w185", "w200", "w300", "w342", "w500", "w780", "w1280", "h632", "original"}
NAME_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}\.(?:jpg|jpeg|png|webp|svg)$")
MAX_BYTES = 20 * 1024 * 1024
TYPES = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".webp": "image/webp", ".svg": "image/svg+xml"}


class CoverError(Exception):
    def __init__(self, message: str, status: int):
        super().__init__(message)
        self.status = status


def _fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "TorrentTube"})
    with urllib.request.urlopen(req, timeout=15) as resp:
        if not resp.headers.get("Content-Type", "").startswith("image/"):
            raise CoverError("Not an image", 502)
        data = resp.read(MAX_BYTES + 1)
    if not data or len(data) > MAX_BYTES:
        raise CoverError("Bad image size", 502)
    return data


class CoverCache:
    def __init__(self, folder: Path, fetch=_fetch):
        self.folder = Path(folder)
        self._fetch = fetch
        self._lock = threading.Lock()
        self._fetching = {}  # (size, name) -> lock: one download per image at a time

    @staticmethod
    def content_type(name: str) -> str:
        return TYPES[Path(name).suffix.lower()]

    def get(self, size: str, name: str) -> Path:
        """The image's file here, fetched from TMDB first if it isn't."""
        if size not in SIZES or not NAME_RE.match(name):
            raise CoverError("No such image", 404)
        path = self.folder / size / name
        if path.is_file():
            return path
        with self._lock:
            lock = self._fetching.setdefault((size, name), threading.Lock())
        with lock:
            try:
                if path.is_file():  # fetched while this request waited
                    return path
                try:
                    data = self._fetch(f"{TMDB_IMAGES}/{size}/{name}")
                except CoverError:
                    raise
                except Exception as e:  # HTTP 404 from TMDB, no network, a timeout
                    status = getattr(e, "code", None)
                    raise CoverError("TMDB didn't send the image", 404 if status == 404 else 502)
                path.parent.mkdir(parents=True, exist_ok=True)
                tmp = path.with_name(f".{name}.{threading.get_ident()}.tmp")
                tmp.write_bytes(data)
                os.replace(tmp, path)  # never a half-written file under the real name
                return path
            finally:
                with self._lock:
                    self._fetching.pop((size, name), None)

    @property
    def generation(self) -> int:
        try:
            return int((self.folder / "generation").read_text().strip())
        except (OSError, ValueError):
            return 0

    def stats(self) -> dict:
        files = size = 0
        if self.folder.is_dir():
            for sub in self.folder.iterdir():
                if sub.is_dir():
                    for f in sub.iterdir():
                        if f.is_file() and not f.name.startswith("."):
                            files += 1
                            size += f.stat().st_size
        return {"files": files, "bytes": size, "generation": self.generation}

    def clear(self) -> dict:
        """Deletes every saved image and starts a new generation."""
        generation = self.generation + 1
        with self._lock:
            if self.folder.is_dir():
                for sub in self.folder.iterdir():
                    if sub.is_dir():
                        shutil.rmtree(sub, ignore_errors=True)
            self.folder.mkdir(parents=True, exist_ok=True)
            (self.folder / "generation").write_text(str(generation))
        return self.stats()
