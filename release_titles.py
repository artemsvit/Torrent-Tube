"""Clean, searchable titles from tracker listings and folder names
("Ukrainian Title / English Title (2001-2012) BDRip Ukr/Eng" -> "English
Title", 2001), and the "this is a show" hint in a name."""
import re


COLLECTION_WORDS_RE = re.compile(
    r"\b(complete collection|full collection|collection|quadrilogy|ouadrilogy|tetralogy|trilogy|duology|dilogy|anthology|saga)\b.*",
    re.I,
)


# "S01", "Season 2", "Сезон 1", "S01E05" in a name - a show, not a film.
SERIES_NAME_RE = re.compile(r"(?i)(?:^|[^a-z0-9])(?:s\d{1,2}(?:e\d{1,3})?|season\s*\d+|seasons\b|сезон\w*\s*\d*)(?![a-z0-9])")

RELEASE_TAIL_RE = re.compile(
    r"\b(?:(?:19|20)\d{2}|S\d{1,2}(?:E\d{1,3})?(?:-\d{1,2})?|Season\s*\d+|Сезон\s*\d+|\d{3,4}p|WEB(?:-?DL|Rip)?|BDRip|BluRay|"
    r"HDRip|DVDRip|HDTV|UHD|x26[45]|H\s?26[45]|HEVC|AMZN|NF)\b", re.I)


def extract_title_and_year(raw_title: str):
    """Best-effort pull of a clean, searchable title (and year) out of a
    tracker listing like 'Ukrainian Title / English Title (2001-2012) BDRip
    Ukr/Eng | Sub Eng'. Heuristic, not exact - trackers don't structure this.
    Also returns a shorter "base" title (franchise name only, no "Complete
    Collection"/"Quadrilogy"/etc.) since those bundle-release words rarely
    match anything on TMDB, which indexes individual films."""
    # Scene-style file names ("Yogi.Bear.2010.1080p.BluRay") use dots or
    # underscores for spaces; a "/" means a tracker listing, left as is.
    scene = "/" not in raw_title and re.match(r"^\S*?[._]\S*?[._]", raw_title) is not None
    if scene:
        raw_title = re.sub(r"(?<!\d)[._]|[._](?!\d)", " ", raw_title)
    # The release year: "(2017)" first, so "Blade Runner 2049 (2017)" and "1917 (2019)" stay right.
    year_match = re.search(r"\(\s*((?:19|20)\d{2})", raw_title) or re.search(r"(?<!\d)((?:19|20)\d{2})(?!\d)", raw_title)
    year = year_match.group(1) if year_match else None

    # Names come before the "(year" / "|" - past it, a "/" is release info
    # ("4xUkr/Eng | Sub Ukr/Eng [Remastered, ...]"), and that tail must not
    # win the most-English-part pick below.
    head = re.split(r"\(\s*(?:19|20)\d{2}|\|", raw_title)[0].strip() or raw_title
    parts = head.split("/")
    candidate = max(parts, key=lambda p: sum(c.isascii() and c.isalpha() for c in p)) if len(parts) > 1 else head
    candidate = candidate.split("|")[0]
    candidate = re.sub(r"^\s*\[\d{1,3}(?:\.\d{1,2})?\]\s*", "", candidate)  # "[05] Fast Five" - a numbered collection
    candidate = re.split(r"\(\s*(19|20)\d{2}", candidate)[0]
    candidate = re.sub(r"[\[\(].*", "", candidate)
    candidate = re.sub(r"\s+", " ", candidate).strip(" :-|/")
    candidate = re.sub(r"\s+\b(3D|4K|HDR|Remastered)\b\s*$", "", candidate, flags=re.I).strip()
    # A bare year, season or quality tag ends the name: "Show S01 2026 WEB-DL" -> "Show".
    # A bare year only counts in scene names, or when release tags follow it
    # ("The Accountant 2 2025 AMZN") - elsewhere it can be part of the title.
    def counts(m):
        if scene or not re.fullmatch(r"(?:19|20)\d{2}", m.group(0)):
            return True
        return RELEASE_TAIL_RE.match(candidate[m.end():].lstrip(" .")) is not None
    tail = next((m for m in RELEASE_TAIL_RE.finditer(candidate) if counts(m)), None)
    if tail and tail.start() > 0:
        candidate = candidate[:tail.start()].strip(" :-|/.")
    candidate = re.sub(r"^\d{1,2}\.\s+", "", candidate)  # "1. The Lion King" - a numbered collection
    candidate = re.sub(r"^S\d{1,2}(?:E\d{1,3})?\s+", "", candidate, flags=re.I)  # "s01 Pluribus"

    base = COLLECTION_WORDS_RE.split(candidate)[0].strip(" :.-")
    return candidate, base, year
