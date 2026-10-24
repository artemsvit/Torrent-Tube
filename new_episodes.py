"""Download new episodes: for every show already in the library, find the
newest episode on disk, look for newer ones on the trackers, and download
only the missing files - from the release most like the files already
there (same group, resolution, codec, source, audio).

The search, the torrent file list and the download itself are passed in
(app.py gives Jackett and libtorrent), so the choices here are testable on
their own. What was fetched or tried is kept in a state file, so an episode
is never fetched twice and a torrent with nothing new is not opened again
every run."""
import json
import re
import threading
import time
from collections import Counter
from pathlib import PurePosixPath

import episodes
import languages
from release_titles import extract_title_and_year

INTERVAL = 30 * 60          # one check every 30 minutes while it is on
TRIED_FOR = 24 * 3600       # a torrent with nothing new is not opened again for a day
CHECK_PER_SHOW = 5          # torrents whose file list is fetched per show and run
RECENT_KEPT = 20
VIDEO_EXTS = {".mkv", ".mp4", ".m4v", ".mov", ".avi", ".ts", ".m2ts", ".webm", ".wmv", ".mpg", ".mpeg"}

_RESOLUTION = re.compile(r"(?i)(?<!\d)(2160|1080|720|576|480)[pi](?![a-z])|(?<![a-z])(4k|uhd)(?![a-z])")
_SOURCES = [("web-dl", r"web[ ._-]?dl"), ("webrip", r"web[ ._-]?rip"), ("bluray", r"blu[ ._-]?ray|bdremux|remux"),
            ("bdrip", r"bdrip|brrip"), ("hdtv", r"hdtv"), ("hdrip", r"hdrip"), ("dvdrip", r"dvdrip")]
_SOURCES = [(name, re.compile(rf"(?i)(?<![a-z]){words}(?![a-z])")) for name, words in _SOURCES]
_CODECS = [("hevc", re.compile(r"(?i)(?<![a-z0-9])(?:x[ .]?265|h[ .]?265|hevc)(?![a-z0-9])")),
           ("avc", re.compile(r"(?i)(?<![a-z0-9])(?:x[ .]?264|h[ .]?264|avc)(?![a-z0-9])"))]
_BRACKETS = re.compile(r"\[([^\[\]]+)\]")
_SCENE_GROUP = re.compile(r"-([A-Za-z0-9]{2,})$")
_NOT_GROUP = re.compile(r"(?i)season|сезон|серії|серія|episode|епізод|\d+\s*(?:з|of|из)\s*\d+|^[\d\s,.+\-]+$")
_UKRAINIAN_LETTERS = re.compile(r"[іїєґІЇЄҐ]")

# What a tracker title says it holds: "S02", "S01-S03", "Season 2", "Сезон 2",
# "S02E01-05", "серії 1-5 з 10", "[1-5 з 10]".
_T_SXE = re.compile(r"(?i)(?<![a-z0-9])s(\d{1,2})[ ._-]?e(\d{1,3})(?:[ ._]*-[ ._]*e?(\d{1,3}))?(?!\d)")
_T_S = re.compile(r"(?i)(?<![a-z0-9])s(\d{1,2})(?:[ ._]*-[ ._]*s?(\d{1,2}))?(?![\de])")
_T_WORDS = re.compile(r"(?i)(?:season|сезон\w*)[ ._:]*(\d{1,2})(?:[ ._]*[-–][ ._]*(\d{1,2}))?(?!\d)")
_T_EPISODES = re.compile(r"(?i)(?:серії|серія|серий|епізоди|епізод|episodes?|eps?)[ ._:]*(\d{1,3})(?:[ ._]*[-–][ ._]*(\d{1,3}))?(?!\d)")
_T_OF = re.compile(r"(?i)[\[(,][ ._]*(\d{1,3})(?:[ ._]*[-–][ ._]*(\d{1,3}))?[ ._]*(?:з|of|из)[ ._]*(\d{1,3})(?!\d)")


# ---------- What a name says about its release ----------

def release_tags(text: str) -> dict:
    """Group, resolution, source, codec and audio languages from a folder,
    file or tracker name: "Show (Season 2) WEB-DL 1080p [Ukr,Eng] [Hurtom]"
    -> group "hurtom", "1080p", "web-dl", languages {"uk", "en"}."""
    text = text or ""
    resolution = None
    match = _RESOLUTION.search(text)
    if match:
        resolution = "2160p" if (match.group(2) or match.group(1) == "2160") else f"{match.group(1)}p"
    source = next((name for name, pattern in _SOURCES if pattern.search(text)), None)
    codec = next((name for name, pattern in _CODECS if pattern.search(text)), None)
    group = None
    for token in _BRACKETS.findall(text):
        token = token.strip()
        if (not token or languages.found_in(token) or _NOT_GROUP.search(token) or _RESOLUTION.search(token)
                or any(p.search(token) for _, p in _SOURCES) or any(p.search(token) for _, p in _CODECS)):
            continue
        group = token.lower()
    if group is None:
        stem = PurePosixPath(text).stem if PurePosixPath(text).suffix.lower() in VIDEO_EXTS else text
        match = _SCENE_GROUP.search(stem.strip())
        if match and match.group(1).lower() not in ("dl", "rip", "ray"):
            group = match.group(1).lower()
    return {"group": group, "resolution": resolution, "source": source, "codec": codec,
            "languages": languages.found_in(text)}


def profile(names) -> dict:
    """The release the files on disk come from: the most common group,
    resolution, source and codec over the folder and file names, and every
    audio language they name."""
    tags = [release_tags(name) for name in names]
    result = {"languages": set().union(*(t["languages"] for t in tags)) if tags else set()}
    for key in ("group", "resolution", "source", "codec"):
        values = Counter(t[key] for t in tags if t[key])
        result[key] = values.most_common(1)[0][0] if values else None
    return result


def _norm(text: str) -> str:
    return re.sub(r"[\W_]+", " ", (text or "").lower()).strip()


def show_names(raw: str) -> set:
    """Every name a folder or tracker title gives the show, normalized:
    "Укр Назва / English Name (Сезон 2) WEB-DL" -> {"укр назва", "english name"}."""
    if not raw:
        return set()
    names = {extract_title_and_year(raw)[0]}
    head = re.split(r"[(\[|]", raw, maxsplit=1)[0]
    if "/" in head:
        names.update(extract_title_and_year(part)[0] for part in head.split("/") if part.strip())
    return {n for n in map(_norm, names) if n}


def release_languages(result: dict) -> set:
    """The audio languages of a tracker result: the ones its title names; a
    title naming none is in its indexer's language, or Ukrainian when it is
    written in Ukrainian ("Сезон 2, серії 1-5")."""
    found = languages.found_in(result.get("title", ""))
    if found:
        return found
    if result.get("language"):
        return {result["language"]}
    return {"uk"} if _UKRAINIAN_LETTERS.search(result.get("title", "")) else set()


def title_coverage(title: str):
    """(seasons, last episode) a tracker title says it holds - either can be
    None when it does not say. The last episode only for one season."""
    seasons, last = set(), None
    for match in _T_SXE.finditer(title):
        seasons.add(int(match.group(1)))
        last = max(last or 0, int(match.group(3) or match.group(2)))
    for pattern in (_T_S, _T_WORDS):
        for match in pattern.finditer(title):
            first, end = int(match.group(1)), int(match.group(2) or match.group(1))
            if first <= end <= first + 30:
                seasons.update(range(first, end + 1))
    for pattern in (_T_EPISODES, _T_OF):
        for match in pattern.finditer(title):
            last = max(last or 0, int(match.group(2) or match.group(1)))
    seasons = seasons or None
    return seasons, (last if seasons and len(seasons) == 1 else None)


# ---------- What is missing ----------

def newest(files):
    """The newest (season, episode) among a show's files, or None."""
    found = [(f["season"], f.get("last_episode") or f["episode"]) for f in files if f.get("season") and f.get("episode")]
    return max(found) if found else None


def episodes_on_disk(files) -> set:
    return {(f["season"], e) for f in files if f.get("season") and f.get("episode")
            for e in range(f["episode"], (f.get("last_episode") or f["episode"]) + 1)}


def could_have(title: str, top) -> bool:
    """False when a tracker title shows it has nothing after `top`: older
    seasons only, a season too far ahead, or episodes up to `top` only."""
    seasons, last = title_coverage(title)
    if not seasons:
        return True
    season, episode = top
    if max(seasons) < season or min(seasons) > season + 1:
        return False
    if seasons == {season} and last is not None and last <= episode:
        return False
    return True


def wanted(paths, top, have=(), season_hint=None) -> list:
    """The files of a torrent that are new episodes: later in the newest
    season on disk, or in the season after it - and not had already.
    [(index, season, episode, last_episode)]. `season_hint` is the one
    season the tracker title names, for files named "05 Name.mkv"."""
    season, episode = top
    have = set(have)
    picks = []
    for index, path in enumerate(paths):
        path = str(path).replace("\\", "/")
        name = PurePosixPath(path).name
        if PurePosixPath(name).suffix.lower() not in VIDEO_EXTS or "sample" in name.lower():
            continue
        found = episodes.identify(name, path)
        if not found and season_hint:
            found = episodes.identify(name, f"Season {season_hint}/{path}")
        if not found:
            continue
        s, first, last = found["season"], found["episode"], found["last_episode"]
        if not ((s == season and last > episode) or s == season + 1):
            continue
        if all((s, e) in have for e in range(first, last + 1)):
            continue
        picks.append((index, s, first, last))
    return picks


# ---------- Picking the release ----------

def score(result: dict, disk: dict) -> float:
    """How much a tracker result looks like the files on disk."""
    title = result.get("title", "")
    tags = release_tags(title)
    points = 0.0
    if disk.get("group") and (tags["group"] == disk["group"] or re.search(
            rf"(?i)(?<![a-z0-9]){re.escape(disk['group'])}(?![a-z0-9])", title)):
        points += 40
    if disk.get("resolution") and tags["resolution"] == disk["resolution"]:
        points += 30
    if disk.get("codec") and tags["codec"] == disk["codec"]:
        points += 10
    if disk.get("source") and tags["source"] == disk["source"]:
        points += 10
    points += 5 * len(release_languages(result) & disk.get("languages", set()))
    points += min(result.get("seeders") or 0, 50) / 10
    return points


def candidates(results, names: set, top, disk: dict, preference) -> list:
    """The results worth opening, best first, as [(language, result)]: the
    same show, with seeders, maybe something newer - first every one in the
    preferred audio language, then the ones in the fallback (English)."""
    seen, usable = set(), []
    for r in results:
        key = (r.get("title"), r.get("size"))
        if key in seen or not (r.get("seeders") or 0) > 0:
            continue
        seen.add(key)
        if show_names(r.get("title", "")) & names and could_have(r.get("title", ""), top):
            usable.append(r)
    ordered = []
    for language in preference:
        tier = [r for r in usable if language in release_languages(r)]
        tier.sort(key=lambda r: score(r, disk), reverse=True)
        ordered.extend((language, r) for r in tier if all(r is not o for _, o in ordered))
    return ordered


# ---------- Where a new file goes ----------

_SEASON_NUMBER = re.compile(r"(?i)((?:^|[^\w])(?:season|сезон|[sс])[ ._-]*)(\d{1,2})(?!\d)")


def _renumber(name: str, season: int, new: int):
    """"Season 02" -> "Season 03"; None when the name holds no such season."""
    for match in _SEASON_NUMBER.finditer(name):
        if int(match.group(2)) == season:
            digits = str(new).zfill(len(match.group(2)))
            return name[:match.start(2)] + digits + name[match.end(2):]
    return None


def place(show: dict, paths, picks) -> list:
    """[(index, library path)] for each picked file. An episode of the newest
    season goes next to the newest episode. An episode of the next season
    goes into a folder named like that season's ("Season 2" -> "Season 3",
    "Show (Сезон 2) ..." -> "Show (Сезон 3) ..."), or next to it when the
    show's folders do not name seasons."""
    files = [f for f in show["files"] if f.get("season") and f.get("episode")]
    last = max(files, key=lambda f: (f["season"], f.get("last_episode") or f["episode"]))
    here = PurePosixPath(last["path"]).parent
    folder = next((PurePosixPath(f) for f in show.get("folders", []) if last["path"].startswith(f.rstrip("/") + "/")), here)
    targets = []
    for index, season, _, _ in picks:
        target = here
        if season != last["season"]:
            if here != folder and _renumber(here.name, last["season"], season):
                target = here.parent / _renumber(here.name, last["season"], season)
            elif here == folder and _renumber(folder.name, last["season"], season):
                target = folder.parent / _renumber(folder.name, last["season"], season)
        targets.append((index, str(target / PurePosixPath(str(paths[index]).replace("\\", "/")).name)))
    return targets


# ---------- The worker ----------

class NewEpisodes:
    """Checks every show every 30 minutes while it is on.

    shows() -> [{"key", "title", "names", "queries", "folders", "files"}]
    search(query) -> tracker results (title, size, seeders, magnet,
        download_link, and "language" when the indexer's is known)
    inspect(result) -> {"hash", "files": [paths in the torrent], ...} or None
    download(torrent, targets) - fetch only [(index, library path)]."""

    def __init__(self, state_file, shows, search, inspect, download, enabled, audio_language,
                 clock=time.time, interval=INTERVAL, log=lambda message: None):
        self.state_file = state_file
        self.shows, self.search, self.inspect, self.download = shows, search, inspect, download
        self.enabled, self.audio_language = enabled, audio_language
        self.clock, self.interval, self.log = clock, interval, log
        self._lock = threading.Lock()
        self._wake = threading.Event()
        self.state = self._load()

    def _load(self) -> dict:
        try:
            state = json.loads(self.state_file.read_text())
            if isinstance(state, dict):
                return {"fetched": state.get("fetched") or {}, "tried": state.get("tried") or {},
                        "last_check": state.get("last_check"), "recent": state.get("recent") or []}
        except (OSError, ValueError):
            pass
        return {"fetched": {}, "tried": {}, "last_check": None, "recent": []}

    def _save(self):
        now = self.clock()
        self.state["tried"] = {k: at for k, at in self.state["tried"].items() if now - at < TRIED_FOR}
        self.state["recent"] = self.state["recent"][-RECENT_KEPT:]
        try:
            self.state_file.parent.mkdir(parents=True, exist_ok=True)
            self.state_file.write_text(json.dumps(self.state, ensure_ascii=False))
        except OSError:
            pass

    def status(self) -> dict:
        return {"last_check": self.state.get("last_check"), "recent": list(reversed(self.state["recent"][-5:]))}

    def due(self) -> bool:
        last = self.state.get("last_check")
        return bool(self.enabled()) and (last is None or self.clock() - last >= self.interval)

    def wake(self):
        """Check soon: the setting was just turned on."""
        self._wake.set()

    def loop(self, tick=60):
        while True:
            self._wake.wait(tick)
            self._wake.clear()
            try:
                if self.due():
                    self.run()
            except Exception as error:
                self.log(f"new episodes: check failed: {error!r}")

    def run(self) -> list:
        """One check of every show. Returns what started downloading."""
        if not self._lock.acquire(blocking=False):
            return []
        try:
            preference = languages.preference(self.audio_language())
            started = []
            for show in self.shows():
                try:
                    started.extend(self.check(show, preference))
                except Exception as error:
                    self.log(f"new episodes: {show.get('title')}: {error!r}")
            self.state["last_check"] = self.clock()
            self._save()
            return started
        finally:
            self._lock.release()

    def check(self, show: dict, preference) -> list:
        top = newest(show["files"])
        if not top:
            return []
        fetched = self.state["fetched"].setdefault(show["key"], {})
        have = episodes_on_disk(show["files"])
        have |= {(int(s), int(e)) for s, e in (re.match(r"S(\d+)E(\d+)", k).groups() for k in fetched)}
        disk = profile([*show.get("names", []), *(f["name"] for f in show["files"])])
        names = set().union(*(show_names(n) for n in show.get("names", [])))
        results = []
        for query in show.get("queries", [])[:3]:
            try:
                results.extend(self.search(query))
            except Exception as error:
                self.log(f"new episodes: search {query!r} failed: {error!r}")
        opened = 0
        for _, result in candidates(results, names, top, disk, preference):
            key = f"{result.get('title')}|{result.get('size')}"
            if self.clock() - self.state["tried"].get(key, float("-inf")) < TRIED_FOR:
                continue
            if opened >= CHECK_PER_SHOW:
                break
            opened += 1
            torrent = self.inspect(result)
            seasons, _ = title_coverage(result.get("title", ""))
            hint = next(iter(seasons)) if seasons and len(seasons) == 1 else None
            picks = wanted(torrent["files"], top, have, hint) if torrent else []
            if not picks:
                self.state["tried"][key] = self.clock()
                continue
            targets = place(show, torrent["files"], picks)
            self.download(torrent, targets)
            now = self.clock()
            labels = []
            for _, season, first, last in picks:
                for episode in range(first, last + 1):
                    label = f"S{season:02d}E{episode:02d}"
                    fetched[label] = {"at": now, "title": result.get("title"), "hash": torrent.get("hash")}
                    labels.append(label)
            self.state["recent"].append({"show": show.get("title"), "episodes": labels,
                                         "release": result.get("title"), "at": now})
            self._save()
            self.log(f"new episodes: {show.get('title')}: {', '.join(labels)} from {result.get('title')!r}")
            return [(show["key"], label) for label in labels]
        return []
