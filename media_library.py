"""The server's own library: video files already in the category folders
(Movies, Cartoon, TV Shows), listed per title and played straight from disk -
no torrent, nothing downloaded, nothing cached."""
import os
import re
import threading
import time
from pathlib import Path

# Category folder -> the kind the apps sort by.
KINDS = {"movies": "movie", "movie": "movie", "cartoon": "cartoon", "cartoons": "cartoon",
         "tv shows": "tv", "tv": "tv", "series": "tv"}


def _natural(name: str):
    """Episode 2 before Episode 10."""
    return [int(part) if part.isdigit() else part.lower() for part in re.split(r"(\d+)", name)]


# S01E02, 1x02, or "1-1-2 Name" (season 1, episodes 1 and 2 in one file).
_EPISODE_RE = re.compile(r"(?i)(?:^|[^a-z0-9])s(\d{1,2})[ ._-]*e\d{1,3}(?!\d)|(?:^|[^a-z0-9])(\d{1,2})x\d{1,3}(?!\d)"
                         r"|^(\d{1,2})-\d{1,3}-\d{1,3}(?=[ ._])")
_SEASON_FOLDER_RE = re.compile(r"(?i)(?:^|[^\w])(?:season|сезон|s)[ ._-]*(\d{1,2})(?!\d)|(?:^|[^\w])(\d{1,2})[ ._-]+(?:season|сезон)")


def season_of(path: Path):
    """The season a video belongs to: from S01E02 / 1x02 in its name, else
    from a "Season 1" / "Сезон 1" folder above it. None for a film."""
    match = _EPISODE_RE.search(path.name)
    if match:
        return int(match.group(1) or match.group(2) or match.group(3))
    for folder in reversed(path.parent.parts[-3:]):
        match = _SEASON_FOLDER_RE.search(folder)
        if match:
            return int(match.group(1) or match.group(2))
    return None


def _hidden(name: str) -> bool:
    # Synology's @eaDir thumbnails, .DS_Store, the stream cache, app state.
    return name.startswith((".", "@", "#"))


class MediaLibrary:
    def __init__(self, root: Path, categories, video_exts, ttl=60, clock=time.monotonic, describe=None):
        self.root = Path(root)
        self.categories = list(categories)
        self.video_exts = {e.lower() for e in video_exts}
        self.ttl = ttl
        self.clock = clock
        # name -> (clean title, year): the readable name shown before (or
        # without) a TMDB match.
        self.describe = describe or (lambda name: (name, None))
        self._lock = threading.Lock()
        self._cache = None
        self._cached_at = 0.0

    def _is_video(self, path: Path) -> bool:
        return path.suffix.lower() in self.video_exts and not _hidden(path.name)

    def _videos(self, folder: Path) -> list:
        found = []
        for current, dirs, files in os.walk(folder):
            dirs[:] = sorted((d for d in dirs if not _hidden(d)), key=_natural)
            for name in sorted(files, key=_natural):
                path = Path(current) / name
                if self._is_video(path):
                    found.append(path)
        return found

    def _scan(self) -> list:
        items = []
        for category in self.categories:
            folder = self.root / category
            if not folder.is_dir():
                continue
            kind = KINDS.get(category.lower(), "movie")
            for entry in sorted(folder.iterdir(), key=lambda p: _natural(p.name)):
                if _hidden(entry.name):
                    continue
                try:
                    if entry.is_file() and self._is_video(entry):
                        videos, name = [entry], entry.stem
                    elif entry.is_dir():
                        videos, name = self._videos(entry), entry.name
                    else:
                        continue
                    if not videos:
                        continue
                    title, year = self.describe(name)
                    items.append({
                        "title": title or name,
                        "year": year,
                        "id": entry.relative_to(self.root).as_posix(),
                        "name": name,
                        "category": category,
                        "kind": kind,
                        "files": len(videos),
                        # How many seasons the episodes are in (0 for a film).
                        "seasons": len({s for s in map(season_of, videos) if s is not None}) if len(videos) > 1 else 0,
                        "size": sum(v.stat().st_size for v in videos),
                        "added": int(entry.stat().st_mtime),
                    })
                except OSError:
                    continue  # unreadable or vanished mid-scan
        items.sort(key=lambda item: item["added"], reverse=True)
        return items

    def items(self, refresh=False) -> list:
        with self._lock:
            if refresh or self._cache is None or self.clock() - self._cached_at > self.ttl:
                self._cache = self._scan()
                self._cached_at = self.clock()
            return self._cache

    def resolve(self, relative: str):
        """The real path for a library path, or None if it isn't one: inside a
        category folder, not hidden, existing. Never anything outside."""
        if not isinstance(relative, str) or not relative or "\x00" in relative:
            return None
        parts = Path(relative).parts
        if not parts or parts[0] not in self.categories or any(_hidden(p) or p == ".." for p in parts):
            return None
        root = self.root.resolve()
        try:
            path = (self.root / relative).resolve()
            path.relative_to(root / parts[0])
        except (OSError, ValueError):
            return None
        return path if path.exists() else None

    def files(self, relative: str):
        """The videos of one title, in play order, or None if it isn't one."""
        path = self.resolve(relative)
        if path is None:
            return None
        videos = [path] if path.is_file() and self._is_video(path) else (self._videos(path) if path.is_dir() else [])
        root = self.root.resolve()
        return [{"index": i, "name": v.name, "path": v.resolve().relative_to(root).as_posix(), "size": v.stat().st_size}
                for i, v in enumerate(videos)]
