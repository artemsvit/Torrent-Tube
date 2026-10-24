"""The server's own library: video files already in the category folders
(Movies, Cartoon, TV Shows), listed per title and played straight from disk -
no torrent, nothing downloaded, nothing cached."""
import os
import re
import threading
import time
from pathlib import Path

import episodes

# Category folder -> the kind the apps sort by.
KINDS = {"movies": "movie", "movie": "movie", "cartoon": "cartoon", "cartoons": "cartoon",
         "tv shows": "tv", "tv": "tv", "series": "tv"}


def _natural(name: str):
    """Episode 2 before Episode 10."""
    return [int(part) if part.isdigit() else part.lower() for part in re.split(r"(\d+)", name)]


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

    def _films(self, videos: list):
        """A collection folder's films ("[05] Fast Five (2011)", "[06] Furious 6
        (2013)") as (video, name) pairs, or None when the folder is one title.
        Every file must name a film and a year, and two titles at least - a film
        in parts or two cuts of one film stay one title."""
        films = []
        for video in videos:
            title, year = self.describe(video.stem)
            if not title or not year:
                return None
            films.append((video, (title.lower(), year)))
        return [(v, v.stem) for v, _ in films] if len({key for _, key in films}) > 1 else None

    def _item(self, entry: Path, name: str, videos: list, category: str, kind: str, found: list) -> dict:
        title, year = self.describe(name)
        return {
            "title": title or name,
            "year": year,
            "id": entry.relative_to(self.root).as_posix(),
            "name": name,
            "category": category,
            "kind": kind,
            "files": len(videos),
            # How many seasons the episodes are in (0 for a film), and how
            # many files are episodes - two or more make it a show.
            "seasons": len({f["season"] for f in found if f}),
            "episodes": sum(1 for f in found if f),
            "size": sum(v.stat().st_size for v in videos),
            "added": int(entry.stat().st_mtime),
        }

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
                    # Each video's season and episode (episodes.py), for a folder of several.
                    found = [episodes.identify(v.name, self._relative(v)) for v in videos] if len(videos) > 1 else []
                    # A collection of films is a title per film, each with its own match.
                    films = self._films(videos) if len(videos) > 1 and not any(found) else None
                    if films:
                        items.extend(self._item(v, film, [v], category, kind, []) for v, film in films)
                    else:
                        items.append(self._item(entry, name, videos, category, kind, found))
                except OSError:
                    continue  # unreadable or vanished mid-scan
        items.sort(key=lambda item: item["added"], reverse=True)
        return items

    def _relative(self, path: Path) -> str:
        try:
            return path.relative_to(self.root).as_posix()
        except ValueError:
            return path.name

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
        files = []
        for i, v in enumerate(videos):
            relative = v.resolve().relative_to(root).as_posix()
            files.append({"index": i, "name": v.name, "path": relative, "size": v.stat().st_size,
                          **(episodes.identify(v.name, relative) or {})})
        return files
