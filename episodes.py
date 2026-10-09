"""Which season and episode a video file is - the one parser the apps and the
web page rely on (the server sends the result with every file).

Understands, in the file name:
  S01E02, s1e2, S010E1, S02EP01, С01Е01 (Cyrillic letters), 1x02,
  "Season 1 Episode 2", and two episodes in one file: S01E01-E02,
  S01E01E02, S01E01-02, "1-1-2 Name" (season 1, episodes 1 and 2).
And with a season folder above it ("Season 1", "Сезон 1", "S01",
"Show (Сезон 2)"): "03 Name", "E03 Name", "03-04 Name", "Серія 03".
A file named only "Серія 03" / "Episode 3" with no season anywhere is
season 1. Films, collections ("[01] Toy Story (1995)") and extras are None.
"""
import re

_E = r"(?:ep|e|е)"           # Latin e, "ep", Cyrillic е
_S = r"[sс]"                 # Latin s, Cyrillic с
_NOT_WORD = r"(?:^|[^\w])"   # \w is Unicode: letters of any alphabet, digits, _

# A second episode right after the first: "-E02", "E02", "-02", " - E02".
_RANGE = rf"(?:[ ._]*-[ ._]*{_E}?|{_E})(\d{{1,3}})"
_SXE = re.compile(rf"(?i)(?:^|[^a-zа-яіїєґ0-9]){_S}0*(\d{{1,2}})[ ._-]*{_E}[ ._-]*(\d{{1,3}})(?:{_RANGE})?(?!\d)")
_WORDS = re.compile(r"(?i)season[ ._-]*(\d{1,2})[ ._-]*episode[ ._-]*(\d{1,3})(?!\d)")
_NXM = re.compile(r"(?i)(?:^|[^a-z0-9])(\d{1,2})x(\d{1,3})(?!\d)")
_DASHED = re.compile(r"^(\d{1,2})-(\d{1,3})-(\d{1,3})(?=[ ._])")

_SEASON_FOLDER = (re.compile(rf"(?i){_NOT_WORD}(?:season|сезон|{_S})[ ._-]*0*(\d{{1,2}})(?!\d)"),
                  re.compile(rf"(?i){_NOT_WORD}(\d{{1,2}})[ ._-]+(?:season|сезон)(?:$|[^\w])"))
_LEADING = re.compile(rf"(?i)^(?:(?:episode|{_E})[ ._-]*)?(\d{{1,3}})(?:[ ._]*[-+&][ ._]*{_E}?(\d{{1,3}}))?(?=[ ._-]|$)")
_EPISODE_WORD = re.compile(rf"(?i){_NOT_WORD}(?:episode|серія|серия|епізод|эпизод)[ ._-]*(\d{{1,3}})(?!\d)")


def _last(first, second):
    """The end of a range only when it is just after the first episode -
    never a resolution, a year or noise ("S01E05 4K")."""
    if second is None:
        return first
    second = int(second)
    return second if first < second <= first + 4 else None


def _result(season, episode, last=None):
    season, episode = int(season), int(episode)
    if episode <= 0:
        return None
    return {"season": season, "episode": episode, "last_episode": last if last and last > episode else episode}


def from_name(name):
    """Season and episode from the file name alone, or None."""
    match = _SXE.search(name)
    if match:
        episode = int(match.group(2))
        last = _last(episode, match.group(3))
        return _result(match.group(1), episode, last)   # not a sensible range: the first episode only
    for pattern in (_WORDS, _NXM):
        match = pattern.search(name)
        if match:
            return _result(match.group(1), match.group(2))
    match = _DASHED.search(name)
    if match:
        episode = int(match.group(2))
        last = _last(episode, match.group(3))
        if last and last > episode:
            return _result(match.group(1), episode, last)
    return None


def _season_from_folders(path):
    for folder in reversed(path.replace("\\", "/").split("/")[:-1]):
        for pattern in _SEASON_FOLDER:
            match = pattern.search(folder)
            if match:
                return int(match.group(1))
    return None


def identify(name, path=None):
    """{"season", "episode", "last_episode"} for a video, or None. `path` is
    its path with the folders above it (the season may be there)."""
    found = from_name(name)
    if found:
        return found
    season = _season_from_folders(path) if path else None
    if season is not None:
        match = _LEADING.search(name)
        if match:
            episode = int(match.group(1))
            if match.group(2) is None:
                return _result(season, episode)
            last = _last(episode, match.group(2))
            return _result(season, episode, last) if last else None  # "03-10": do not guess
    match = _EPISODE_WORD.search(name)
    if match:
        return _result(season if season is not None else 1, match.group(1))
    return None

