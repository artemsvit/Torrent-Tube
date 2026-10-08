import email.utils
import json
import mimetypes
import os
import re
import shutil
import socket
import threading
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from functools import wraps
from pathlib import Path

import libtorrent as lt
from media_library import MediaLibrary
from playback_sessions import PlaybackSessions
from trailer_streams import TrailerError, TrailerStreams
from flask import Flask, Response, jsonify, redirect, render_template, request, send_file

DOWNLOAD_DIR = Path(os.environ.get("TORRENTTUBE_DOWNLOAD_DIR") or (Path.home() / "Downloads" / "TorrentTube"))
DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)

CATEGORIES = [
    c.strip()
    for c in os.environ.get("TORRENTTUBE_CATEGORIES", "Cartoon,Movies,TV Shows").split(",")
    if c.strip()
]
for _category in CATEGORIES:
    (DOWNLOAD_DIR / _category).mkdir(parents=True, exist_ok=True)

def host_download_dir() -> "str | None":
    """Where the downloads folder really is on the server, when this runs in
    a container (DOWNLOAD_DIR is then the path inside it, e.g. /downloads).
    TORRENTTUBE_HOST_DOWNLOAD_DIR says it outright; otherwise a Synology
    volume is worked out from the container's own mount table: the mount's
    root /@syno/<path> on device .../volume_<n> is /volume<n>/<path>."""
    explicit = os.environ.get("TORRENTTUBE_HOST_DOWNLOAD_DIR", "").strip()
    if explicit:
        return explicit
    if not Path("/.dockerenv").exists():
        return str(DOWNLOAD_DIR)  # not in a container - the path is the real one
    try:
        mounts = Path("/proc/self/mountinfo").read_text().splitlines()
    except OSError:
        return None  # not Linux - not a container either
    target = str(DOWNLOAD_DIR.resolve())
    for line in mounts:
        fields = line.split()
        if len(fields) < 10 or fields[4] != target or "-" not in fields:
            continue
        root, source = fields[3], fields[fields.index("-") + 2]
        volume = re.search(r"volume_?(\d+)$", source)
        if volume and root.startswith("/@syno/"):
            return f"/volume{volume.group(1)}/{root[len('/@syno/'):]}"
    return None


HOST_DOWNLOAD_DIR = host_download_dir()

STATE_DIR = Path(os.environ.get("TORRENTTUBE_STATE_DIR") or (DOWNLOAD_DIR / ".torrenttube"))
STATE_DIR.mkdir(parents=True, exist_ok=True)
RESUME_FILE = STATE_DIR / "torrents.json"

# All user-adjustable settings (bandwidth/connection limits, Jackett/TMDB
# config) live in this one file, editable from the Settings popup in the UI.
# Defined here (not down with DEFAULT_LIMITS below) so it's available to
# load the Jackett/TMDB config immediately below too.
SETTINGS_FILE = STATE_DIR / "settings.json"

TORZNAB_NS = {"torznab": "http://torznab.com/schemas/2015/feed"}
TMDB_CACHE = {}
TMDB_CACHE_TTL = 6 * 3600
TMDB_EXECUTOR = ThreadPoolExecutor(max_workers=8)

app = Flask(__name__)
app.config["TEMPLATES_AUTO_RELOAD"] = True
app.config["MAX_CONTENT_LENGTH"] = 8 * 1024 * 1024  # .torrent files are tiny; 8MB is generous
TRAILER_STREAMS = TrailerStreams()

STATE_NAMES = {
    lt.torrent_status.checking_files: "checking",
    lt.torrent_status.downloading_metadata: "fetching_metadata",
    lt.torrent_status.downloading: "downloading",
    lt.torrent_status.finished: "finished",
    lt.torrent_status.seeding: "seeding",
    lt.torrent_status.checking_resume_data: "checking",
}

ses = lt.session(
    {
        "listen_interfaces": "0.0.0.0:6881",
        "enable_dht": True,
        "enable_lsd": True,
        "enable_upnp": True,
        "enable_natpmp": True,
    }
)

# ---------- Bandwidth / connection limits + Jackett / TMDB config ----------
# Everything here is user-adjustable via /api/settings (Settings popup in the
# UI) and persisted to SETTINGS_FILE so it survives a container restart.
# Bandwidth/connection limits are re-applied to the live libtorrent session
# (and every open torrent handle, for the per-torrent connection cap)
# whenever they change.
DEFAULT_LIMITS = {
    "download_rate_limit": 0,       # KB/s, 0 = unlimited
    "upload_rate_limit": 0,         # KB/s, 0 = unlimited
    "max_connections": 0,           # global peer connections, 0 = libtorrent default
    "max_connections_per_torrent": 0,  # per-torrent peer connections, 0 = no cap
    "max_upload_slots": 0,          # unchoke slots, 0 = libtorrent default
    "seed_after_download": 1,       # 0/1 - pause a torrent as soon as it finishes instead of seeding
    "remove_after_download": 0,     # 0/1 - drop a finished torrent from the list (files are kept)
}

# Jackett does the actual tracker login/scraping (configured with the user's
# own tracker credentials, entered directly into Jackett's own UI) - this
# app only talks to Jackett's local Torznab API with Jackett's own API key.
# TMDB enriches search results with a poster/rating (free key at
# https://www.themoviedb.org/settings/api). Both optional: without them the
# Search/Discover tabs stay disabled. Env vars only seed the *initial*
# value (so an existing docker-compose deploy keeps working unmodified) -
# jackett_url defaults to the bundled compose service's hostname. Once
# something is saved from the Settings UI, settings.json wins from then on.
DEFAULT_SERVICE = {
    "jackett_url": os.environ.get("JACKETTAPI_URL", "http://jackett:9117").rstrip("/"),
    "jackett_api_key": os.environ.get("JACKETTAPI_KEY", ""),
    "jackett_indexer": os.environ.get("JACKETTAPI_INDEXER", "all"),
    "tmdb_api_key": os.environ.get("TMDB_API_KEY", ""),
    "tmdb_language": os.environ.get("TMDB_LANGUAGE", "uk-UA"),
    "default_player": "infuse",  # what Play opens: "infuse" or "vlc"
}
PLAYERS = ("infuse", "vlc")


def load_settings() -> dict:
    values = {**DEFAULT_LIMITS, **DEFAULT_SERVICE}
    if SETTINGS_FILE.exists():
        try:
            saved = json.loads(SETTINGS_FILE.read_text())
            for k in DEFAULT_LIMITS:
                if k in saved:
                    values[k] = int(saved[k])
            for k in DEFAULT_SERVICE:
                if isinstance(saved.get(k), str):
                    values[k] = saved[k]
        except Exception:
            pass
    return values


# LIMITS is an alias for SETTINGS (same dict object), kept around because
# the bandwidth/connection code below reads it by that name - a save from
# /api/settings updates this one dict and both names see it.
SETTINGS = load_settings()
LIMITS = SETTINGS
JACKETT_URL = SETTINGS["jackett_url"]
JACKETT_API_KEY = SETTINGS["jackett_api_key"]
JACKETT_INDEXER = SETTINGS["jackett_indexer"]
TMDB_API_KEY = SETTINGS["tmdb_api_key"]
TMDB_LANGUAGE = SETTINGS["tmdb_language"]


def apply_session_limits():
    ses.apply_settings({
        "download_rate_limit": LIMITS["download_rate_limit"] * 1024,
        "upload_rate_limit": LIMITS["upload_rate_limit"] * 1024,
        "connections_limit": LIMITS["max_connections"] or 200,  # libtorrent's own default
        "unchoke_slots_limit": LIMITS["max_upload_slots"] or -1,
    })


def apply_torrent_limits(handle):
    handle.set_max_connections(LIMITS["max_connections_per_torrent"] or -1)


apply_session_limits()

# info_hash (hex str) -> torrent_handle
HANDLES = {}
# ids the user explicitly paused. libtorrent's own torrent_status.paused flag
# can lag behind pause()/resume() calls by several seconds under load, so we
# track intent ourselves rather than trusting that snapshot for the UI.
PAUSED_IDS = set()
LOCK = threading.Lock()


def torrent_id(handle) -> str:
    return str(handle.status().info_hashes.get_best())


def save_registry():
    """Persist enough info to re-add every torrent after a container restart."""
    entries = []
    with LOCK:
        for h in list(HANDLES.values()):
            if not h.is_valid():
                continue
            st = h.status()
            entry = {"save_path": st.save_path}
            if st.has_metadata:
                ti = h.torrent_file()
                wrapped = lt.bencode({"info": lt.bdecode(ti.info_section())})
                entry["torrent_file_hex"] = wrapped.hex()
                # A streamed torrent only wants its one video file - keep
                # that across restarts instead of fetching everything.
                priorities = list(h.get_file_priorities())
                if 0 in priorities:
                    entry["file_priorities"] = priorities
            else:
                entry["magnet_uri"] = lt.make_magnet_uri(h)
            if torrent_id(h) in STREAM_CACHE_IDS:
                entry["stream_cache"] = True
            entries.append(entry)
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    RESUME_FILE.write_text(json.dumps(entries))


def load_registry():
    if not RESUME_FILE.exists():
        return
    try:
        entries = json.loads(RESUME_FILE.read_text())
    except (json.JSONDecodeError, OSError):
        return
    for entry in entries:
        try:
            if "torrent_file_hex" in entry:
                info = lt.torrent_info(bytes.fromhex(entry["torrent_file_hex"]))
                tid = add_torrent_file(info, entry["save_path"])
                if entry.get("file_priorities"):
                    HANDLES[tid].prioritize_files(entry["file_priorities"])
            elif "magnet_uri" in entry:
                tid = add_magnet(entry["magnet_uri"], entry["save_path"])
            else:
                continue
            if entry.get("stream_cache"):
                # Its player's connection didn't survive the restart: unless
                # the player connects again, the never-opened rule clears it.
                STREAM_CACHE_IDS.add(tid)
                STREAM_LAST_USED[tid] = STREAM_STARTED[tid] = time.time()
        except Exception:
            continue


def resolve_save_path(category: str = None) -> str:
    if category and category in CATEGORIES:
        return str(DOWNLOAD_DIR / category)
    return str(DOWNLOAD_DIR / CATEGORIES[0]) if CATEGORIES else str(DOWNLOAD_DIR)


def add_magnet(uri: str, save_path: str = None) -> str:
    params = lt.parse_magnet_uri(uri)
    params.save_path = save_path or resolve_save_path()
    params.storage_mode = lt.storage_mode_t.storage_mode_sparse
    handle = ses.add_torrent(params)
    apply_torrent_limits(handle)
    tid = torrent_id(handle)
    with LOCK:
        HANDLES[tid] = handle
    return tid


def add_torrent_file(info: "lt.torrent_info", save_path: str = None, nothing_wanted: bool = False) -> str:
    params = lt.add_torrent_params()
    params.ti = info
    params.save_path = save_path or resolve_save_path()
    if nothing_wanted:
        # A stream starts with no file wanted, so a whole season pack never
        # begins downloading - begin_stream turns on just the episode played.
        params.file_priorities = [0] * info.num_files()
    params.storage_mode = lt.storage_mode_t.storage_mode_sparse
    handle = ses.add_torrent(params)
    apply_torrent_limits(handle)
    tid = torrent_id(handle)
    with LOCK:
        HANDLES[tid] = handle
    return tid


def eta_seconds(st) -> "int | None":
    if st.download_rate <= 0 or st.total_wanted <= 0:
        return None
    remaining = st.total_wanted - st.total_wanted_done
    if remaining <= 0:
        return None
    return int(remaining / st.download_rate)


def serialize(tid: str, handle) -> dict:
    st = handle.status()
    name = st.name or "Fetching metadata..."
    # NB: torrent_status.finished/.seeding are not booleans in this libtorrent
    # binding - they alias the state-enum's own constants, so they're always
    # truthy. Compare st.state against the enum instead.
    is_done = st.state in (lt.torrent_status.finished, lt.torrent_status.seeding)
    try:
        category = Path(st.save_path).name
    except Exception:
        category = ""
    if category not in CATEGORIES:
        category = ""
    return {
        "id": tid,
        "name": name,
        "category": category,
        "state": STATE_NAMES.get(st.state, "unknown"),
        "is_paused": tid in PAUSED_IDS and not is_done,
        "progress": round(st.progress * 100, 1),
        "download_rate": st.download_rate,
        "upload_rate": st.upload_rate,
        "num_peers": st.num_peers,
        "num_seeds": st.num_seeds,
        "size": st.total_wanted,
        "downloaded": st.total_wanted_done,
        "eta": eta_seconds(st),
        "has_metadata": st.has_metadata,
        "error": st.error,
    }


@app.route("/")
def index():
    return render_template("index.html")


HELPER_SCRIPTS = {"vlc-mac.sh", "vlc-windows.ps1", "vlc-mac-uninstall.sh", "vlc-windows-uninstall.ps1"}


HELPER_KEY_RE = re.compile(r"^[0-9a-f]{16,32}$")
HELPER_INSTALLED = {}  # browser's helper key -> {"at", "installed", "vlc"}: what its (un)installer last said


@app.route("/helper/<name>")
def helper_script(name):
    """One-time installers that let a computer's browser open VLC: they
    register a torrenttube-vlc: link handler that only accepts play links
    from this server - its address, as the browser reached it, is filled in.
    ?k=<key> (the page's own random id) makes the installer report back
    when it's done, so the page can tell without asking."""
    if name not in HELPER_SCRIPTS:
        return jsonify({"error": "No such helper"}), 404
    key = request.args.get("k", "")
    body = render_template(f"helpers/{name}", origin=request.host_url.rstrip("/"),
                           key=key if HELPER_KEY_RE.match(key) else "")
    return Response(body, mimetype="text/plain; charset=utf-8")


@app.route("/api/helper/<key>", methods=["GET", "POST"])
def helper_status(key):
    """POST: an installer saying it finished (vlc=1/0: whether it found VLC
    on that computer - a web page can't see installed apps), or the
    uninstaller saying it's gone (removed=1). GET: the page asking - known
    is false when nothing's been said under this key (since a restart)."""
    if not HELPER_KEY_RE.match(key):
        return jsonify({"error": "Bad key"}), 400
    if request.method == "POST":
        removed = request.values.get("removed") == "1"
        vlc = request.values.get("vlc")
        with LOCK:
            old_vlc = (HELPER_INSTALLED.get(key) or {}).get("vlc")
            HELPER_INSTALLED[key] = {"at": time.time(), "installed": not removed,
                                     "vlc": old_vlc if vlc is None else vlc == "1"}
            for old in [k for k, v in HELPER_INSTALLED.items() if time.time() - v["at"] > 86400]:
                HELPER_INSTALLED.pop(old, None)
        what = "removed" if removed else f"installed, VLC {'found' if vlc == '1' else 'not found'}"
        stream_log(f"VLC helper {what} ({request.headers.get('User-Agent', '?')[:60]!r})")
    entry = HELPER_INSTALLED.get(key)
    return jsonify({"known": bool(entry), "installed": bool(entry and entry["installed"]),
                    "vlc": entry["vlc"] if entry else None})


@app.route("/api/config")
def config():
    search_enabled = bool(JACKETT_URL and JACKETT_API_KEY)
    return jsonify({
        "server": "torrenttube",
        "api_version": 1,
        "capabilities": {"file_selection": True, "playback_sessions": True, "library": True},
        "download_dir": str(DOWNLOAD_DIR),
        # The same folder as the server's own path (None when it isn't
        # known) - what Settings shows, as /downloads means little.
        "download_dir_host": HOST_DOWNLOAD_DIR,
        "categories": CATEGORIES,
        "search_enabled": search_enabled,
        # Descriptive only - never the Jackett/TMDB API keys themselves.
        "search_indexer": JACKETT_INDEXER if search_enabled else None,
        "tmdb_enabled": bool(TMDB_API_KEY),
        "tmdb_language": TMDB_LANGUAGE if TMDB_API_KEY else None,
        "default_player": SETTINGS["default_player"] if SETTINGS["default_player"] in PLAYERS else "infuse",
    })


@app.route("/api/settings", methods=["GET"])
def get_settings():
    return jsonify(SETTINGS)


@app.route("/api/settings", methods=["POST"])
def update_settings():
    global JACKETT_URL, JACKETT_API_KEY, JACKETT_INDEXER, TMDB_API_KEY, TMDB_LANGUAGE
    payload = request.json or {}
    for key in DEFAULT_LIMITS:
        if key not in payload:
            continue
        try:
            SETTINGS[key] = max(0, int(payload[key]))
        except (TypeError, ValueError):
            return jsonify({"error": f"'{key}' must be a non-negative number"}), 400
    for key in DEFAULT_SERVICE:
        if key not in payload:
            continue
        if not isinstance(payload[key], str):
            return jsonify({"error": f"'{key}' must be text"}), 400
        SETTINGS[key] = payload[key].strip()
    if SETTINGS["default_player"] not in PLAYERS:
        SETTINGS["default_player"] = DEFAULT_SERVICE["default_player"]

    JACKETT_URL = SETTINGS["jackett_url"].rstrip("/")
    JACKETT_API_KEY = SETTINGS["jackett_api_key"]
    JACKETT_INDEXER = SETTINGS["jackett_indexer"] or "all"
    TMDB_API_KEY = SETTINGS["tmdb_api_key"]
    TMDB_LANGUAGE = SETTINGS["tmdb_language"] or "uk-UA"
    TMDB_CACHE.clear()
    DISCOVER_QUERY_CACHE.clear()
    INDEXER_CAPS_CACHE["key"] = None

    apply_session_limits()
    with LOCK:
        handles = list(HANDLES.values())
    for h in handles:
        if h.is_valid():
            apply_torrent_limits(h)
    SETTINGS_FILE.write_text(json.dumps(SETTINGS))
    return jsonify(SETTINGS)


# Fallback when TMDB can't be reached (no key yet, offline) - the Settings
# language dropdown still offers the common picks instead of going empty.
FALLBACK_TMDB_LANGUAGES = [
    "uk-UA", "en-US", "en-GB", "pl-PL", "de-DE", "fr-FR", "es-ES", "it-IT",
    "pt-BR", "pt-PT", "cs-CZ", "nl-NL", "sv-SE", "tr-TR", "ja-JP", "ko-KR", "zh-CN",
]
TMDB_LANGUAGES_CACHE = {}


def _jackett_indexers():
    """Configured indexers from Jackett's own Torznab list, as [{id, title}]."""
    params = {"apikey": JACKETT_API_KEY, "t": "indexers", "configured": "true"}
    url = f"{JACKETT_URL}/api/v2.0/indexers/all/results/torznab/api?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": "TorrentTube"})
    with urllib.request.urlopen(req, timeout=8) as resp:
        root = ET.fromstring(resp.read())
    return [
        {"id": el.get("id"), "title": (el.findtext("title") or el.get("id")).strip()}
        for el in root.findall("indexer") if el.get("id")
    ]


def _tmdb_languages():
    """TMDB's primary translations (e.g. 'uk-UA') - the locales it actually
    has titles/overviews for. Cached per key since the list barely changes."""
    if TMDB_API_KEY in TMDB_LANGUAGES_CACHE:
        return TMDB_LANGUAGES_CACHE[TMDB_API_KEY]
    url = f"https://api.themoviedb.org/3/configuration/primary_translations?api_key={urllib.parse.quote(TMDB_API_KEY)}"
    req = urllib.request.Request(url, headers={"User-Agent": "TorrentTube"})
    with urllib.request.urlopen(req, timeout=8) as resp:
        langs = sorted(c for c in json.loads(resp.read()) if isinstance(c, str))
    TMDB_LANGUAGES_CACHE[TMDB_API_KEY] = langs
    return langs


@app.route("/api/settings/options")
def settings_options():
    """Known choices for the Settings dropdowns. The indexer list is None
    when Jackett can't be reached, so the UI can fall back to free text."""
    indexers = None
    if JACKETT_URL and JACKETT_API_KEY:
        try:
            indexers = _jackett_indexers()
        except Exception:
            pass
    languages = None
    if TMDB_API_KEY:
        try:
            languages = _tmdb_languages()
        except Exception:
            pass
    return jsonify({
        "jackett_indexers": indexers,
        "tmdb_languages": languages or FALLBACK_TMDB_LANGUAGES,
    })


COLLECTION_WORDS_RE = re.compile(
    r"\b(complete collection|full collection|collection|quadrilogy|ouadrilogy|tetralogy|trilogy|duology|dilogy|anthology|saga)\b.*",
    re.I,
)


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


def _tmdb_get(path: str, **params):
    params = {"api_key": TMDB_API_KEY, **params}
    url = f"https://api.themoviedb.org/3{path}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": "TorrentTube"})
    with urllib.request.urlopen(req, timeout=8) as resp:
        return json.loads(resp.read())


def _tmdb_search(query: str, year: str = None):
    params = {"query": query, "include_adult": "false", "language": TMDB_LANGUAGE}
    if year:
        params["year"] = year
    data = _tmdb_get("/search/multi", **params)
    for item in data.get("results", []):
        if item.get("media_type") in ("movie", "tv"):
            return item
    return None


def tmdb_lookup(title: str, base: str, year: str):
    if not TMDB_API_KEY or not title:
        return None
    cache_key = (title.lower(), base.lower(), year)
    cached = TMDB_CACHE.get(cache_key)
    if cached and time.time() - cached[0] < TMDB_CACHE_TTL:
        return cached[1]

    item = None
    try:
        item = _tmdb_search(title, year) or _tmdb_search(title)
        if not item and base and base.lower() != title.lower():
            item = _tmdb_search(base, year) or _tmdb_search(base)
    except Exception:
        item = None

    result = None
    if item:
        poster_path = item.get("poster_path")
        result = {
            "id": item.get("id"),
            "title": item.get("title") or item.get("name") or title,
            "poster": f"https://image.tmdb.org/t/p/w200{poster_path}" if poster_path else None,
            "rating": item.get("vote_average"),
            "overview": item.get("overview") or "",
            "year": (item.get("release_date") or item.get("first_air_date") or "")[:4],
            "media_type": item.get("media_type"),
            "genre_ids": item.get("genre_ids") or [],
        }
    TMDB_CACHE[cache_key] = (time.time(), result)
    return result


TMDB_ANIMATION_GENRE_ID = 16
TMDB_IMAGE_BASE = "https://image.tmdb.org/t/p"


def _tmdb_image(path: str, size: str):
    return f"{TMDB_IMAGE_BASE}/{size}{path}" if path else None


def _pick_certification(data: dict, media_type: str, region: str):
    """Age rating for the TMDB language's own country, falling back to the US."""
    if media_type == "movie":
        by_country = {
            c.get("iso_3166_1"): next((r.get("certification") for r in c.get("release_dates", []) if r.get("certification")), None)
            for c in (data.get("release_dates") or {}).get("results", [])
        }
    else:
        by_country = {c.get("iso_3166_1"): c.get("rating") for c in (data.get("content_ratings") or {}).get("results", [])}
    return by_country.get(region) or by_country.get("US") or None


def _pick_trailers(videos: list, lang: str) -> list:
    """YouTube trailers/teasers, best first: the TMDB language's own
    trailers, then official ones, then trailers before teasers."""
    picked = [v for v in videos if v.get("site") == "YouTube" and v.get("key") and v.get("type") in ("Trailer", "Teaser")]
    picked.sort(key=lambda v: (v.get("iso_639_1") != lang, not v.get("official"), v.get("type") != "Trailer"))
    return [{"key": v["key"], "name": v.get("name") or v["type"], "lang": v.get("iso_639_1")} for v in picked[:8]]


def _person(p: dict, role: str) -> dict:
    return {"id": p.get("id"), "name": p.get("name") or "", "role": role or "",
            "photo": _tmdb_image(p.get("profile_path"), "w185")}


def tmdb_details(media_type: str, tmdb_id: int) -> dict:
    """Everything the details popup shows, in one TMDB round-trip (plus an
    English fallback when there's no overview/trailer in the configured
    language)."""
    cache_key = ("details", media_type, tmdb_id)
    cached = TMDB_CACHE.get(cache_key)
    if cached and time.time() - cached[0] < TMDB_CACHE_TTL:
        return cached[1]

    lang, _, region = TMDB_LANGUAGE.partition("-")
    extra = "credits,videos,external_ids,recommendations," + ("release_dates" if media_type == "movie" else "content_ratings")
    d = _tmdb_get(f"/{media_type}/{tmdb_id}", language=TMDB_LANGUAGE, append_to_response=extra,
                  include_video_language=f"{lang},en,null")

    overview = d.get("overview") or ""
    videos = (d.get("videos") or {}).get("results", [])
    if lang != "en" and (not overview or not videos):
        try:
            en = _tmdb_get(f"/{media_type}/{tmdb_id}", language="en-US", append_to_response="videos")
            overview = overview or en.get("overview") or ""
            videos = videos or (en.get("videos") or {}).get("results", [])
        except Exception:
            pass

    credits = d.get("credits") or {}
    crew = credits.get("crew") or []
    genre_ids = [g.get("id") for g in d.get("genres", [])]
    if media_type == "movie":
        # Directors lead the cast row (Apple TV-style "Cast & Crew").
        leads = [_person(c, "Director") for c in crew if c.get("job") == "Director"][:2]
        facts = [("Writers", list(dict.fromkeys(c["name"] for c in crew if c.get("job") in ("Screenplay", "Writer", "Novel"))))]
    else:
        leads = [_person(c, "Creator") for c in d.get("created_by", [])][:2]
        facts = [("Network", [n["name"] for n in d.get("networks", [])])]
    runtime = d.get("runtime") or next(iter(d.get("episode_run_time") or []), None)
    release_date = d.get("release_date") or d.get("first_air_date") or ""
    next_ep = d.get("next_episode_to_air") or {}
    collection = d.get("belongs_to_collection") or {}

    result = {
        "tmdb_id": tmdb_id,
        "media_type": media_type,
        "kind": "Cartoon" if TMDB_ANIMATION_GENRE_ID in genre_ids else ("Movie" if media_type == "movie" else "TV show"),
        "title": d.get("title") or d.get("name") or "",
        "original_title": d.get("original_title") or d.get("original_name") or "",
        "tagline": d.get("tagline") or "",
        "overview": overview,
        "year": release_date[:4],
        "release_date": release_date,
        "last_air_date": d.get("last_air_date"),
        "in_production": d.get("in_production"),
        "status": d.get("status"),
        "runtime": runtime,
        "seasons": d.get("number_of_seasons"),
        "episodes": d.get("number_of_episodes"),
        "season_list": [
            {"number": se.get("season_number"), "name": se.get("name") or "", "episodes": se.get("episode_count"),
             "year": (se.get("air_date") or "")[:4]}
            for se in d.get("seasons", []) if se.get("season_number")
        ],
        "next_episode": {"season": next_ep.get("season_number"), "episode": next_ep.get("episode_number"),
                         "date": next_ep.get("air_date")} if next_ep.get("air_date") else None,
        "collection": collection.get("name"),
        "genres": [g.get("name") for g in d.get("genres", []) if g.get("name")],
        "countries": [c.get("name") for c in d.get("production_countries", []) if c.get("name")],
        "original_language": d.get("original_language"),
        "certification": _pick_certification(d, media_type, region or lang.upper()),
        "rating": d.get("vote_average"),
        "vote_count": d.get("vote_count"),
        "budget": d.get("budget") or None,
        "revenue": d.get("revenue") or None,
        "facts": [{"label": label, "names": names[:3]} for label, names in facts if names],
        "people": leads + [_person(c, c.get("character")) for c in (credits.get("cast") or [])[:18]],
        "poster": _tmdb_image(d.get("poster_path"), "w342"),
        "backdrop": _tmdb_image(d.get("backdrop_path"), "w1280"),
        "imdb_id": (d.get("external_ids") or {}).get("imdb_id") or d.get("imdb_id"),
        "homepage": d.get("homepage") or None,
        "tmdb_url": f"https://www.themoviedb.org/{media_type}/{tmdb_id}",
        "trailers": _pick_trailers(videos, lang),
        "recommendations": [
            {"tmdb_id": r.get("id"), "media_type": r.get("media_type") or media_type,
             "title": r.get("title") or r.get("name") or "",
             "year": (r.get("release_date") or r.get("first_air_date") or "")[:4],
             "rating": r.get("vote_average"), "poster": _tmdb_image(r.get("poster_path"), "w185")}
            for r in (d.get("recommendations") or {}).get("results", [])
            if r.get("poster_path") and r.get("media_type", media_type) in ("movie", "tv")
        ][:14],
    }
    TMDB_CACHE[cache_key] = (time.time(), result)
    return result


# YouTube search results page, scraped - no API key needed. Only a
# fallback for titles TMDB has no trailer for, so it being best-effort
# (the markup can change under us) is fine: the popup still links out to
# a plain YouTube search either way.
YT_RESULT_RE = re.compile(r'"videoRenderer":\{"videoId":"([\w-]{11})".{0,3000}?"title":\{"runs":\[\{"text":"((?:[^"\\]|\\.)*)"', re.S)
YT_CACHE = {}


def youtube_search(query: str, limit: int = 6) -> list:
    hit = YT_CACHE.get(query)
    if hit and time.time() - hit[0] < TMDB_CACHE_TTL:
        return hit[1]
    url = f"https://www.youtube.com/results?{urllib.parse.urlencode({'search_query': query})}"
    req = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36",
        "Accept-Language": f"{TMDB_LANGUAGE.split('-')[0]},en;q=0.8",
        "Cookie": "SOCS=CAI",  # skips the EU cookie-consent interstitial
    })
    with urllib.request.urlopen(req, timeout=10) as resp:
        html = resp.read().decode("utf-8", "replace")
    videos, seen = [], set()
    for m in YT_RESULT_RE.finditer(html):
        key = m.group(1)
        if key in seen:
            continue
        seen.add(key)
        try:
            name = json.loads(f'"{m.group(2)}"')
        except ValueError:
            name = m.group(2)
        videos.append({"key": key, "name": name, "lang": None})
        if len(videos) >= limit:
            break
    YT_CACHE[query] = (time.time(), videos)
    return videos

# Keyword-based fallback for when there's no TMDB match (or TMDB is unused,
# e.g. for an uploaded .torrent file, which has no time budget for an API
# round-trip). None of this needs the categories to be named exactly
# "Cartoon"/"Movies"/"TV Shows" - it just looks for one whose own name hints
# at the right bucket, so it still works if the user renames them.
CARTOON_KEYWORDS = ("cartoon", "anime", "animat", "мультфільм", "мультсеріал")
TV_KEYWORDS = ("season", "episode", "series", "сезон", "серії", "серія", "епізод")


def find_category_like(*hints) -> str:
    for hint in hints:
        for c in CATEGORIES:
            if hint in c.lower():
                return c
    return ""


def guess_category(title: str, genre_ids=None, media_type: str = None) -> str:
    if not CATEGORIES:
        return ""
    lower = title.lower()

    if genre_ids and TMDB_ANIMATION_GENRE_ID in genre_ids:
        match = find_category_like("cartoon", "anim")
        if match:
            return match
    if any(kw in lower for kw in CARTOON_KEYWORDS):
        match = find_category_like("cartoon", "anim")
        if match:
            return match

    if media_type == "tv" or any(kw in lower for kw in TV_KEYWORDS):
        match = find_category_like("tv", "show", "series")
        if match:
            return match

    return find_category_like("movie") or CATEGORIES[0]


def enrich_with_tmdb(results, limit=40):
    if not TMDB_API_KEY:
        for r in results:
            r["suggested_category"] = guess_category(r["title"])
        return
    # Only the most-likely-to-be-picked results are worth the extra lookups
    # (a 150-result search doesn't need all of them enriched; Discover's
    # much smaller feeds pass a higher limit so nothing is left without a
    # poster).
    top = results[:limit]

    def enrich_one(r):
        title, base, year = extract_title_and_year(r["title"])
        meta = tmdb_lookup(title, base, year)
        if meta:
            r["poster"] = meta["poster"]
            r["rating"] = meta["rating"]
            r["overview"] = meta["overview"]
            r["clean_title"] = meta["title"]
            r["tmdb_id"] = meta["id"]
            r["media_type"] = meta["media_type"]
            r["suggested_category"] = guess_category(meta["title"], meta["genre_ids"], meta["media_type"])
        else:
            r["suggested_category"] = guess_category(r["title"])

    list(TMDB_EXECUTOR.map(enrich_one, top))
    for r in results[limit:]:
        r["suggested_category"] = guess_category(r["title"])


def format_size(num_bytes: int) -> str:
    size = float(num_bytes)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if size < 1024 or unit == "TB":
            return f"{size:.1f} {unit}" if unit != "B" else f"{int(size)} {unit}"
        size /= 1024
    return f"{size:.1f} TB"


def jackett_query(q: str = None, cat: str = None, indexer: str = None):
    """Hits Jackett's Torznab proxy for the configured indexer (or the one
    given) and returns parsed (but not yet TMDB-enriched) result dicts. A
    blank `q` isn't a no-op search - most trackers treat it as "give me the
    latest uploads", which is what the Discover feeds ride on."""
    params = {"apikey": JACKETT_API_KEY, "t": "search"}
    if q:
        params["q"] = q
    if cat:
        params["cat"] = cat
    url = f"{JACKETT_URL}/api/v2.0/indexers/{indexer or JACKETT_INDEXER}/results/torznab/api?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": "TorrentTube"})
    with urllib.request.urlopen(req, timeout=25) as resp:
        data = resp.read()
    root = ET.fromstring(data)

    results = []
    for item in root.findall(".//item"):
        title = (item.findtext("title") or "").strip()
        if not title:
            continue
        size = int(item.findtext("size") or 0)
        seeders = peers = 0
        magnet = ""
        for attr in item.findall("torznab:attr", TORZNAB_NS):
            name, value = attr.get("name"), attr.get("value")
            if name == "seeders":
                seeders = int(value or 0)
            elif name == "peers":
                peers = int(value or 0)
            elif name == "magneturl" and value:
                magnet = value
        results.append({
            "title": title,
            "size": size,
            "size_label": format_size(size),
            "seeders": seeders,
            "peers": peers,
            "magnet": magnet,
            "download_link": item.findtext("link") or "",
            "details_link": item.findtext("comments") or "",
            "pub_date": item.findtext("pubDate") or "",
            "poster": None,
            "rating": None,
            "overview": None,
        })
    return results


@app.route("/api/search")
def search_torrents():
    if not (JACKETT_URL and JACKETT_API_KEY):
        return jsonify({"error": "Search isn't configured on this server"}), 503
    query = request.args.get("q", "").strip()
    if not query:
        return jsonify({"results": []})

    try:
        results = jackett_query(q=query)
    except Exception:
        return jsonify({"error": "Couldn't reach the search service"}), 502

    results.sort(key=lambda r: r["seeders"], reverse=True)
    results = results[:150]
    # The details popup's "Releases" list only needs the tracker rows
    # themselves - skip the per-row TMDB lookups there.
    if request.args.get("enrich") == "0":
        return jsonify({"results": results})
    return jsonify({"results": group_releases(results)})


RELEASE_FIELDS = ("title", "size", "size_label", "seeders", "peers", "magnet", "download_link", "details_link", "pub_date")


def group_releases(results):
    """One card per title instead of one per tracker row: a search for a
    film returns every rip of it (1080p, 4K, remux, each dub) as separate
    rows. Rows are grouped by their cleaned-up title + year, the best-seeded
    row of each group is TMDB-enriched and becomes the card, and the rest
    ride along in "releases" for the details popup to offer. Groups that
    TMDB resolves to the same title (say "Термінатор 2" and "Terminator 2"
    from two trackers) are merged afterwards."""
    groups = {}
    for r in results:  # already sorted by seeders, so each group's first row is its best
        title, base, year = extract_title_and_year(r["title"])
        # Punctuation-blind, so "Terminator 2. Judgment Day" and
        # "Terminator 2: Judgment Day" land in the same group.
        key = (re.sub(r"[\W_]+", " ", (base or title or r["title"]).lower()).strip(), year)
        groups.setdefault(key, []).append(r)

    cards = []
    for rows in groups.values():
        card = dict(rows[0])
        card["releases"] = [{k: row.get(k) for k in RELEASE_FIELDS} for row in rows]
        cards.append(card)
    enrich_with_tmdb(cards)

    merged = {}
    for card in cards:
        key = (card.get("media_type"), card.get("tmdb_id")) if card.get("tmdb_id") else id(card)
        if key in merged:
            merged[key]["releases"].extend(card["releases"])
        else:
            merged[key] = card
    cards = list(merged.values())
    for card in cards:
        card["releases"].sort(key=lambda r: r["seeders"], reverse=True)
    cards.sort(key=lambda c: c["releases"][0]["seeders"], reverse=True)
    return cards


# ---------- Discover ----------
# A browsable catalog instead of a reactive search. Every tracker numbers
# its own sections differently (Jackett exposes them as custom Torznab
# categories, 100000 + the tracker's forum id - mazepa's 100012 is "Movies
# HD", toloka's 100012 is wallpapers), so nothing here is hard-coded per
# tracker. Instead each configured indexer's own category list is read from
# Jackett and sorted into feeds by section *name* ("Мультфільми HD",
# "Серіали", "Новинки фільмів", ...). Querying a category with no q
# returns that section's latest uploads (~50-90 rows, no offset support).
DISCOVER_FEEDS = [
    # "New" and "Popular" span every group, so they're wide rather than
    # capped at one section's ~50 rows; New also pulls any dedicated
    # "new releases" sections a tracker has.
    {"id": "new", "label": "New", "groups": ["new", "movies", "cartoons", "tv"]},
    {"id": "popular", "label": "Popular", "groups": ["movies", "cartoons", "tv"], "sort": "seeders"},
    {"id": "movies", "label": "Movies", "groups": ["movies"]},
    {"id": "cartoons", "label": "Cartoons", "groups": ["cartoons"]},
    {"id": "tv", "label": "TV Shows", "groups": ["tv"]},
    {"id": "docs", "label": "Documentaries", "groups": ["docs"]},
    {"id": "ukrainian", "label": "Ukrainian", "groups": ["ukrainian"]},
]
DISCOVER_FEEDS_BY_ID = {f["id"]: f for f in DISCOVER_FEEDS}

# Matched as lowercase substrings of a section name. Ukrainian/Russian/
# English since that's what trackers here name their sections in.
SKIP_WORDS = ("архів", "архив", "archive", "трейлер", "trailer", "короткометраж",
              "аматорськ", "субтитр", "sport", "спорт", "концерт", "кліп")
DOCS_WORDS = ("документ", "documentary", "bbc", "discovery", "national geographic", "history channel")
# "Ukrainian" means made in Ukraine, not just dubbed - most sections on
# these trackers are Ukrainian-dubbed, and "HD українською" would pull in
# everything. So it takes "українськ..." plus a video word ("Українські
# фільми", "Українське кіно"), leaving out books, music, subtitles, etc.
UKRAINIAN_WORDS = ("українськ", "украинск")
VIDEO_WORDS = ("фільм", "фильм", "кіно", "кино", "серіал", "сериал", "мультф", "мультс", "документ")
# First match wins, so "Мультсеріали" is a cartoon before it's a series.
KIND_RULES = [
    ("new", ("новинк", "new release", "new movies")),
    ("cartoons", ("мультф", "мультс", "мультик", "cartoon", "animation", "animated", "анімаці")),
    ("tv", ("серіал", "сериал", "series", "tv show")),
    ("movies", ("фільм", "фильм", "кіно", "кино", "film", "movie")),
]
# Sections a tracker splits by quality - when HD/UHD versions exist, the
# SD/DVD ones are just the same titles in worse quality.
LOW_QUALITY_RE = re.compile(r"\bSD\b|DVD", re.I)
# Standard Newznab categories, for trackers without named sections.
STANDARD_GROUPS = {"movies": ["2000"], "tv": ["5000"]}
MAX_CATS_PER_GROUP = 5
HD_RE = re.compile(r"\bU?HD\b|1080|2160|4K", re.I)

INDEXER_CAPS_CACHE = {"at": 0, "key": None, "value": None}


def classify_section(name: str) -> list:
    """Every feed group a section belongs to - "Українські фільми HD" is
    both Ukrainian and Movies. Documentaries only feed their own tab."""
    lower = name.lower()
    if any(w in lower for w in SKIP_WORDS):
        return []
    groups = []
    # "...українською" is "in Ukrainian" (dubbed), not made in Ukraine.
    made_in_ua = any(w in lower.replace("українською", "") for w in UKRAINIAN_WORDS)
    if made_in_ua and any(w in lower for w in VIDEO_WORDS):
        groups.append("ukrainian")
    if any(w in lower for w in DOCS_WORDS):
        return groups + ["docs"]
    for group, words in KIND_RULES:
        if any(w in lower for w in words):
            return groups + [group]
    return groups


def indexer_sections():
    """{indexer_id: {group: [category ids]}} for every configured indexer
    (or just the selected one), from Jackett's own capability list. Cached
    10 min - it only changes when an indexer is added in Jackett."""
    cache_key = (JACKETT_URL, JACKETT_API_KEY, JACKETT_INDEXER)
    if INDEXER_CAPS_CACHE["key"] == cache_key and time.time() - INDEXER_CAPS_CACHE["at"] < 600:
        return INDEXER_CAPS_CACHE["value"]

    params = {"apikey": JACKETT_API_KEY, "t": "indexers", "configured": "true"}
    url = f"{JACKETT_URL}/api/v2.0/indexers/all/results/torznab/api?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": "TorrentTube"})
    with urllib.request.urlopen(req, timeout=8) as resp:
        root = ET.fromstring(resp.read())

    sections = {}
    for ix in root.findall("indexer"):
        ix_id = ix.get("id")
        if not ix_id or (JACKETT_INDEXER not in ("", "all") and ix_id != JACKETT_INDEXER):
            continue
        groups = {}
        for cat in ix.iter("category"):
            cat_id, name = cat.get("id") or "", (cat.get("name") or "").strip(" |-")
            if not cat_id.isdigit() or int(cat_id) < 100000:
                continue  # standard categories are only the fallback below
            for group in classify_section(name):
                groups.setdefault(group, []).append((cat_id, name))
        for group, cats in groups.items():
            # HD sections first, then one of each distinct name (trackers
            # repeat e.g. "Мультсеріали" under several parent sections -
            # without this those duplicates use up the whole cap).
            good = [c for c in cats if not LOW_QUALITY_RE.search(c[1])] or cats
            good.sort(key=lambda c: not HD_RE.search(c[1]))
            picked, names = [], set()
            for cid, name in good:
                if name.lower() not in names:
                    names.add(name.lower())
                    picked.append(cid)
            groups[group] = picked[:MAX_CATS_PER_GROUP]
        for group, cats in STANDARD_GROUPS.items():
            groups.setdefault(group, cats)
        sections[ix_id] = groups

    INDEXER_CAPS_CACHE.update(at=time.time(), key=cache_key, value=sections)
    return sections


# Discover re-opens the same feeds constantly (and New/Popular overlap with
# the others), while a tracker's latest uploads only change every few
# minutes - so a section's rows are reused for 5 min instead of re-scraped.
DISCOVER_QUERY_CACHE = {}
DISCOVER_QUERY_TTL = 300


def cached_section_query(indexer: str, cat: str):
    key = (JACKETT_URL, indexer, cat)
    hit = DISCOVER_QUERY_CACHE.get(key)
    if hit and time.time() - hit[0] < DISCOVER_QUERY_TTL:
        return [dict(r) for r in hit[1]]
    rows = jackett_query(cat=cat, indexer=indexer)
    DISCOVER_QUERY_CACHE[key] = (time.time(), rows)
    return [dict(r) for r in rows]


@app.route("/api/discover/feeds")
def discover_feeds():
    enabled = bool(JACKETT_URL and JACKETT_API_KEY)
    return jsonify({"enabled": enabled, "feeds": [{"id": f["id"], "label": f["label"]} for f in DISCOVER_FEEDS] if enabled else []})


@app.route("/api/discover")
def discover_torrents():
    if not (JACKETT_URL and JACKETT_API_KEY):
        return jsonify({"error": "Search isn't configured on this server"}), 503
    feed = DISCOVER_FEEDS_BY_ID.get(request.args.get("feed", "new"))
    if not feed:
        return jsonify({"error": "Unknown feed"}), 400

    try:
        sections = indexer_sections()
    except Exception:
        return jsonify({"error": "Couldn't reach the search service"}), 502

    # Trackers cap out at ~50-90 items per request and don't honor an
    # offset - so there's no real "page 2" to ask for. But each section
    # (Movies HD, Movies UHD, ...) gets its OWN cap and they barely overlap,
    # so querying every matching section of every indexer in parallel and
    # deduping the merged set is effectively the next page, without
    # pretending Jackett supports pagination it doesn't.
    requests_ = []
    for ix_id, groups in sections.items():
        for group in feed["groups"]:
            for cat in groups.get(group, []):
                if (ix_id, cat) not in requests_:
                    requests_.append((ix_id, cat))

    def fetch_one(pair):
        try:
            return cached_section_query(*pair)
        except Exception:
            return []

    if not requests_:
        return jsonify({"results": []})
    with ThreadPoolExecutor(max_workers=min(16, len(requests_))) as ex:
        batches = list(ex.map(fetch_one, requests_))

    seen = set()
    results = []
    for batch in batches:
        for r in batch:
            key = r["download_link"] or r["magnet"] or r["title"]
            if key in seen:
                continue
            seen.add(key)
            results.append(r)

    # TMDB enrichment (poster/rating/overview) is deliberately *not* done
    # here - a merged, multi-category feed can be 200+ raw rows, and
    # waiting on that many TMDB round-trips (even at 8-way concurrency)
    # is exactly what made first open of a Discover tab slow. Instead this
    # returns fast with a locally-computed title (regex-cleaned, no
    # network) good enough for deduping and a placeholder card, and the
    # client fetches real metadata from /api/discover/enrich only for
    # whichever page it's actually showing, once results are on screen.
    for r in results:
        title, base, _year = extract_title_and_year(r["title"])
        r["clean_title"] = title
        r["suggested_category"] = guess_category(r["title"])
        r["_dedupe_key"] = (title or r["title"]).strip().lower()

    # Every quality/language rip of the same movie is its own separate row
    # in the tracker's own listing (confirmed live: a 50-row "New" feed was
    # only 21 distinct movies - the same handful of new releases repeated
    # 2-4x each for BDRip/WEB-DL/2160p/1080p/etc). That reads as broken
    # ("why does this list look like fewer things than the forum shows"),
    # so keep only the best (most-seeded) release per movie, identified by
    # the locally-cleaned title above (TMDB's own title, once enriched,
    # can look slightly different but never needs to move an item between
    # groups - the dedup pass here is what decides the final list).
    best_by_movie = {}
    for r in results:
        current = best_by_movie.get(r["_dedupe_key"])
        if current is None or r["seeders"] > current["seeders"]:
            best_by_movie[r["_dedupe_key"]] = r
    results = list(best_by_movie.values())
    for r in results:
        del r["_dedupe_key"]

    if feed.get("sort") == "seeders":
        results.sort(key=lambda r: r["seeders"], reverse=True)
    else:
        results.sort(key=lambda r: pub_timestamp(r["pub_date"]), reverse=True)
    return jsonify({"results": results})


def pub_timestamp(pub_date: str) -> float:
    """Torznab pubDate is RFC 822 ("Sat, 26 Sep 2026 ...") - sorting the raw
    string orders by weekday name, which is wrong once feeds are merged."""
    try:
        return email.utils.parsedate_to_datetime(pub_date).timestamp()
    except Exception:
        return 0


@app.route("/api/discover/enrich", methods=["POST"])
def discover_enrich():
    """On-demand TMDB lookup for a page's worth of Discover cards, called
    once those specific items are actually about to be shown rather than
    for the whole (possibly 200+ item) feed up front."""
    payload = request.json or {}
    titles = payload.get("titles") or []
    if not isinstance(titles, list):
        return jsonify({"error": "'titles' must be a list"}), 400
    titles = [t for t in titles if isinstance(t, str) and t][:64]

    def enrich_one(raw_title):
        title, base, year = extract_title_and_year(raw_title)
        meta = tmdb_lookup(title, base, year)
        if not meta:
            return raw_title, None
        return raw_title, {
            "poster": meta["poster"],
            "rating": meta["rating"],
            "overview": meta["overview"],
            "clean_title": meta["title"],
            "tmdb_id": meta["id"],
            "media_type": meta["media_type"],
            "suggested_category": guess_category(meta["title"], meta["genre_ids"], meta["media_type"]),
        }

    pairs = list(TMDB_EXECUTOR.map(enrich_one, titles))
    return jsonify({k: v for k, v in pairs if v})


@app.route("/api/details")
def item_details():
    """Full metadata for the details popup. Takes a TMDB type+id when the
    card was already enriched, or the raw tracker/torrent title otherwise
    (a Discover card whose page hasn't been enriched yet, a download)."""
    if not TMDB_API_KEY:
        return jsonify({"error": "Details need a TMDB API key - add one in Settings"}), 503
    media_type = request.args.get("type", "")
    tmdb_id = request.args.get("id", "")
    if media_type not in ("movie", "tv") or not tmdb_id.isdigit():
        raw_title = request.args.get("title", "").strip()
        meta = tmdb_lookup(*extract_title_and_year(raw_title)) if raw_title else None
        if not meta:
            return jsonify({"error": "Couldn't find this title on TMDB"}), 404
        media_type, tmdb_id = meta["media_type"], meta["id"]
    try:
        return jsonify(tmdb_details(media_type, int(tmdb_id)))
    except Exception:
        return jsonify({"error": "Couldn't reach TMDB"}), 502


@app.route("/api/episodes")
def season_episodes():
    """Episode artwork and facts for native title/file selectors."""
    if not TMDB_API_KEY:
        return jsonify({"error": "Episode information is not configured"}), 503
    series = request.args.get("id", "")
    season = request.args.get("season", "")
    if not series.isdigit() or not season.isdigit() or not 0 <= int(season) <= 999:
        return jsonify({"error": "Invalid series or season"}), 400
    key = ("episodes", int(series), int(season), TMDB_LANGUAGE)
    cached = TMDB_CACHE.get(key)
    if cached and time.time() - cached[0] < TMDB_CACHE_TTL:
        return jsonify(cached[1])
    try:
        data = _tmdb_get(f"/tv/{int(series)}/season/{int(season)}", language=TMDB_LANGUAGE)
        result = {"episodes": [{"number": e["episode_number"], "name": e.get("name") or f"Episode {e['episode_number']}",
                                 "overview": e.get("overview"), "runtime": e.get("runtime"),
                                 "still": _tmdb_image(e.get("still_path"), "w780")}
                                for e in data.get("episodes", []) if isinstance(e.get("episode_number"), int)]}
        TMDB_CACHE[key] = (time.time(), result)
        return jsonify(result)
    except Exception:
        return jsonify({"error": "Couldn't reach episode information"}), 502


# Appended to the YouTube query so results favour trailers dubbed into the
# TMDB language when one exists, falling back to plain "trailer".
TRAILER_WORDS = {"uk": "трейлер українською", "ru": "трейлер", "pl": "zwiastun", "de": "trailer deutsch",
                 "fr": "bande annonce", "es": "tráiler", "it": "trailer italiano", "pt": "trailer", "cs": "trailer"}


@app.route("/api/trailer")
def find_trailer():
    """YouTube fallback for when TMDB has no trailer (or isn't set up).
    Takes a title - a raw tracker/torrent name is cleaned up first - and an
    optional year, and returns the matching videos plus the query used, so
    the popup's "More on YouTube" link searches for the same thing."""
    title = request.args.get("title", "").strip()
    year = request.args.get("year", "").strip()
    if not title:
        return jsonify({"videos": [], "query": ""})
    clean, _base, found_year = extract_title_and_year(title)
    query = " ".join(filter(None, [clean or title, year or found_year,
                                   TRAILER_WORDS.get(TMDB_LANGUAGE.split("-")[0], "trailer")]))[:200]
    try:
        return jsonify({"videos": youtube_search(query), "query": query})
    except Exception:
        return jsonify({"error": "Couldn't reach YouTube", "videos": [], "query": query}), 502


@app.route("/api/trailer/stream", methods=["POST"])
def resolve_trailer_stream():
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return jsonify({"error": "Expected a JSON object"}), 400
    try:
        return jsonify(TRAILER_STREAMS.resolve(payload.get("key"), payload.get("subtitles")))
    except TrailerError as error:
        return jsonify({"error": str(error)}), error.status


@app.route("/trailer-stream/<token>/subtitles.vtt")
def trailer_subtitles(token):
    """The trailer's subtitles (asked for with "subtitles": "uk,en" - the
    first language that works), held in
    memory with its token - nothing is saved."""
    try:
        return Response(TRAILER_STREAMS.subtitles(token), content_type="text/vtt; charset=utf-8",
                        headers={"Cache-Control": "no-store"})
    except TrailerError as error:
        return jsonify({"error": str(error)}), error.status


@app.route("/trailer-stream/<token>/<int:index>")
def relay_trailer_stream(token, index):
    try:
        upstream = TRAILER_STREAMS.relay(token, index, request.headers.get("Range"), request.method == "HEAD")
        headers = {k: upstream.headers[k] for k in ("Content-Type", "Content-Length", "Content-Range", "Accept-Ranges") if k in upstream.headers}
        headers["Cache-Control"] = "no-store"
        status = upstream.status
        if request.method == "HEAD":
            upstream.close()
            return Response(status=status, headers=headers)
        content_type = upstream.headers.get("Content-Type", "").lower()
        if "mpegurl" in content_type:
            with upstream:
                data = upstream.read(1024 * 1024 + 1)
                if len(data) > 1024 * 1024:
                    raise TrailerError("The trailer playlist is too large")
                playlist = TRAILER_STREAMS.rewrite_manifest(token, upstream.geturl(), data.decode("utf-8"))
            return Response(playlist, content_type="application/vnd.apple.mpegurl", headers={"Cache-Control": "no-store"})

        def chunks():
            try:
                while True:
                    data = upstream.read(64 * 1024)
                    if not data:
                        break
                    yield data
            finally:
                upstream.close()
        response = Response(chunks(), status=status, headers=headers, direct_passthrough=True)
        response.call_on_close(upstream.close)
        return response
    except TrailerError as error:
        return jsonify({"error": str(error)}), error.status


# Torrents enforce_remove_policy() just took off the list, so the UI can
# say so with a toast instead of the row silently vanishing. Kept for a
# minute - long enough for any open tab's 1.5s poll to pick it up.
RECENTLY_REMOVED = []


def enforce_remove_policy():
    """Drops finished torrents from the list (keeping their files) when
    "Remove when finished" is on. Runs on the same /api/torrents poll as
    enforce_seed_policy, and wins over seeding - a removed torrent can't seed."""
    now = time.time()
    with LOCK:
        RECENTLY_REMOVED[:] = [r for r in RECENTLY_REMOVED if now - r["at"] < 60]
    if not LIMITS.get("remove_after_download", 0):
        return
    with LOCK:
        handles = list(HANDLES.items())
    removed = False
    for tid, h in handles:
        if not h.is_valid() or tid in STREAM_CACHE_IDS:
            continue  # a cached stream is cleaned up when its player closes
        st = h.status()
        if not (st.has_metadata and st.is_finished):
            continue
        with LOCK:
            HANDLES.pop(tid, None)
            PAUSED_IDS.discard(tid)
            RECENTLY_REMOVED.append({"id": tid, "name": st.name, "at": now})
        ses.remove_torrent(h)
        removed = True
    if removed:
        save_registry()


def enforce_seed_policy():
    """When seeding is turned off, stop uploading as soon as a torrent
    finishes instead of continuing to seed it. Checked on every poll rather
    than via a timer - the UI already polls /api/torrents every 1.5s, so a
    torrent finishing gets caught quickly without a separate background
    loop."""
    if LIMITS.get("seed_after_download", 1):
        return
    with LOCK:
        handles = list(HANDLES.items())
    for tid, h in handles:
        if not h.is_valid() or tid in PAUSED_IDS:
            continue
        if h.status().state == lt.torrent_status.seeding:
            h.unset_flags(lt.torrent_flags.auto_managed)  # same fix as the manual pause endpoint - see its comment
            h.pause()
            with LOCK:
                PAUSED_IDS.add(tid)


@app.route("/api/torrents")
def list_torrents():
    enforce_remove_policy()
    enforce_seed_policy()
    with LOCK:
        # Streams in the cache aren't downloads - they live and go on their own.
        items = [(tid, h) for tid, h in HANDLES.items() if h.is_valid() and tid not in STREAM_CACHE_IDS]
        removed = [{"id": r["id"], "name": r["name"]} for r in RECENTLY_REMOVED]
    items.sort(key=lambda pair: pair[1].status().added_time, reverse=True)
    return jsonify({"torrents": [serialize(tid, h) for tid, h in items], "streams": cached_streams(), "auto_removed": removed})


@app.route("/api/torrents/inspect", methods=["POST"])
def inspect_torrent():
    """Peek at a .torrent file's own name (more reliable than the OS
    filename) to suggest a destination folder and, when TMDB is configured,
    a poster/rating/overview - same enrichment the search results get -
    before the file is actually added."""
    f = request.files.get("file")
    if not f or not f.filename:
        return jsonify({"error": "No file"}), 400
    try:
        info = lt.torrent_info(f.read())
        name = info.name()
    except Exception:
        return jsonify({"error": "That doesn't look like a valid .torrent file"}), 400

    result = {
        "name": name,
        "clean_title": None,
        "poster": None,
        "rating": None,
        "overview": None,
        "suggested_category": guess_category(name),
    }
    if TMDB_API_KEY:
        title, base, year = extract_title_and_year(name)
        meta = tmdb_lookup(title, base, year)
        if meta:
            result["clean_title"] = meta["title"]
            result["poster"] = meta["poster"]
            result["rating"] = meta["rating"]
            result["overview"] = meta["overview"]
            result["suggested_category"] = guess_category(meta["title"], meta["genre_ids"], meta["media_type"])
    return jsonify(result)


@app.route("/api/torrents", methods=["POST"])
def create_torrent():
    if "file" in request.files and request.files["file"].filename:
        f = request.files["file"]
        category = request.form.get("category", "")
        try:
            info = lt.torrent_info(f.read())
        except Exception:
            return jsonify({"error": "That doesn't look like a valid .torrent file"}), 400
        tid = adopt_cached_stream(_info_hash_hex(info=info), category) or add_torrent_file(info, resolve_save_path(category))
    else:
        payload = (request.json or {}) if request.is_json else request.form
        magnet = payload.get("magnet", "").strip()
        download_link = payload.get("download_link", "").strip()
        category = payload.get("category", "")
        if magnet.lower().startswith("magnet:?"):
            try:
                tid = adopt_cached_stream(_info_hash_hex(magnet=magnet), category) or add_magnet(magnet, resolve_save_path(category))
            except Exception:
                return jsonify({"error": "Couldn't parse that magnet link"}), 400
        elif download_link:
            try:
                req = urllib.request.Request(download_link, headers={"User-Agent": "TorrentTube"})
                with urllib.request.urlopen(req, timeout=25) as resp:
                    info = lt.torrent_info(resp.read())
            except Exception:
                return jsonify({"error": "Couldn't fetch that torrent"}), 400
            tid = adopt_cached_stream(_info_hash_hex(info=info), category) or add_torrent_file(info, resolve_save_path(category))
        else:
            return jsonify({"error": "Paste a magnet link or upload a .torrent file"}), 400
    save_registry()
    with LOCK:
        handle = HANDLES[tid]
    return jsonify(serialize(tid, handle))


@app.route("/api/torrents/<tid>/pause", methods=["POST"])
def pause_torrent(tid):
    with LOCK:
        handle = HANDLES.get(tid)
    if not handle or not handle.is_valid():
        return jsonify({"error": "Unknown torrent"}), 404
    # A torrent is auto-managed by default, meaning libtorrent's own queue
    # logic can silently un-pause it again the moment there's room in the
    # active-torrent queue (which there almost always is for a handful of
    # home downloads) - pause() alone doesn't survive that. Taking it out
    # of auto-management first is what makes the pause actually stick.
    handle.unset_flags(lt.torrent_flags.auto_managed)
    handle.pause()
    with LOCK:
        PAUSED_IDS.add(tid)
    return jsonify({"ok": True})


@app.route("/api/torrents/<tid>/resume", methods=["POST"])
def resume_torrent(tid):
    with LOCK:
        handle = HANDLES.get(tid)
    if not handle or not handle.is_valid():
        return jsonify({"error": "Unknown torrent"}), 404
    handle.set_flags(lt.torrent_flags.auto_managed)
    handle.resume()
    with LOCK:
        PAUSED_IDS.discard(tid)
    return jsonify({"ok": True})


@app.route("/api/torrents/<tid>", methods=["DELETE"])
def remove_torrent(tid):
    with LOCK:
        handle = HANDLES.pop(tid, None)
        PAUSED_IDS.discard(tid)
        STREAM_CACHE_IDS.discard(tid)
    if not handle or not handle.is_valid():
        return jsonify({"error": "Unknown torrent"}), 404
    delete_files = request.args.get("delete_files") == "1"
    if delete_files:  # an open stream of it must stop too - see dropped()
        for key in [k for k in STREAM_FILES if k[0] == tid]:
            STREAM_FILES.pop(key, None)
    ses.remove_torrent(handle, lt.session.delete_files if delete_files else 0)
    save_registry()
    return jsonify({"ok": True})


def registry_saver_loop():
    while True:
        time.sleep(15)
        try:
            save_registry()
        except Exception:
            pass


# ---------- Streaming ----------
# Play a torrent while it downloads: the chosen video file is fetched in
# playback order and served over plain HTTP with Range support, so any
# player that can open a URL - Infuse, VLC, a browser <video>, or a future
# native Apple TV app - can play it and seek in it. Seeking works by
# pulling the pieces under the requested byte range to the front of the
# queue (set_piece_deadline) and waiting for them, instead of waiting for
# the whole file.
#
# A new stream goes to a hidden cache folder, not a category folder, and
# shows in Downloads only as a stream. It keeps downloading - paused or
# not - until the player says it's closed: Infuse (and VLC on iOS) open
# the x-success link /played/<token> when the player closes, which deletes
# it with its data, so "Play in Infuse" leaves nothing behind. Save (or
# Download on the same release) moves it to a real folder and makes it an
# ordinary download.
VIDEO_EXTS = {".mkv", ".mp4", ".m4v", ".mov", ".avi", ".ts", ".m2ts", ".webm", ".wmv", ".mpg", ".mpeg"}
STREAM_READAHEAD = 32 * 1024 * 1024   # bytes ahead of the read position to rush
STREAM_HEAD = 8 * 1024 * 1024         # "ready to play" once this much of the start is in
STREAM_PIECE_TIMEOUT = 90             # seconds to wait for a piece before giving up
STREAM_CHUNK = 256 * 1024
mimetypes.add_type("video/x-matroska", ".mkv")
mimetypes.add_type("video/mp2t", ".ts")
mimetypes.add_type("video/mp2t", ".m2ts")
# (tid, file index) -> file path/size, kept after the handle goes away -
# "Remove when finished" drops a completed torrent from the session, and a
# stream still playing it should just keep reading the finished file.
STREAM_FILES = {}
STREAM_CACHE_DIR = DOWNLOAD_DIR / ".stream-cache"
STREAM_CACHE_DIR.mkdir(parents=True, exist_ok=True)
STREAM_CACHE_IDS = set()   # torrents that live in the cache, not in Downloads
# A paused player and a closed one look the same from here - the connection
# stays open (iOS keeps a suspended app's socket) and no data is taken - so
# only the player's own "closed" callback deletes a stream. The safety net
# for a player that never calls back (force-quit, a phone that died, a
# player without callbacks): STREAM_ABANDON_AFTER without any data taken.
# Dropping a stream also shuts its sockets down, so threads blocked on a
# reader that's gone end.
STREAM_LAST_USED = {}      # tid -> when a player last took data from it
STREAM_OPENED = set()      # tids a player has connected to at least once
STREAM_SOCKETS = {}        # tid -> sockets of its open responses
STREAM_ABANDON_AFTER = 6 * 3600
# Second sign of a closed player, for when its callback never comes (Infuse
# 8.5 doesn't call it): its last connection closes. The download stops at
# once, and the stream is deleted after STREAM_CLOSED_AFTER with no new
# connection. A player opens a new connection before closing the old one
# when it seeks, and a paused one keeps its connection open, so neither
# trips this.
STREAM_CLOSED_AFTER = 30
# Not at once: some players (VLC) close the old connection just before
# opening the new one when they seek, and pausing drops every peer.
STREAM_STOP_AFTER = 5
# Play tapped but the player never connected (the "Open in Infuse?"
# prompt cancelled, a copied link never pasted, a restart mid-stream).
STREAM_NEVER_OPENED_AFTER = 180
STREAM_LAST_CONNECTED = {}  # tid -> when it last had an open response
STREAM_STOPPED = set()      # cached streams paused because no player is connected
STREAM_STARTED = {}         # tid -> when its stream started (or was restored)
STREAM_SETUP_LOCK = threading.RLock()
PLAYBACK_SESSIONS = PlaybackSessions()


def stream_transaction(func):
    @wraps(func)
    def wrapped(*args, **kwargs):
        with STREAM_SETUP_LOCK:
            return func(*args, **kwargs)
    return wrapped


def stream_log(message: str):
    """One line in the container log (docker logs torrenttube) - what the
    players actually do: connections, disconnections, close callbacks."""
    print(time.strftime("%Y-%m-%d %H:%M:%S"), "[stream]", message, flush=True)
STREAM_PLAYING_WINDOW = 30  # took data this recently = "playing"


def _info_hash_hex(magnet: str = None, info=None) -> str:
    hashes = lt.parse_magnet_uri(magnet).info_hashes if magnet else info.info_hashes()
    return str(hashes.get_best())


def pick_video_file(ti) -> int:
    """The main video of a torrent: its biggest video file (a release is
    typically one film plus samples/extras), or its biggest file at all."""
    fs = ti.files()
    files = range(fs.num_files())
    videos = [i for i in files if Path(fs.file_path(i)).suffix.lower() in VIDEO_EXTS
              and "sample" not in fs.file_path(i).lower()]
    return max(videos or files, key=fs.file_size)


def _file_pieces(ti, index: int, start: int, end: int):
    """Piece range covering bytes [start, end) of file `index`."""
    fs = ti.files()
    offset, piece_len = fs.file_offset(index), ti.piece_length()
    first = (offset + start) // piece_len
    last = (offset + max(start, end - 1)) // piece_len
    return first, min(last, ti.num_pieces() - 1)


def rush_pieces(handle, first: int, last: int):
    """Ask for these pieces first, soonest-needed first."""
    for n, piece in enumerate(range(first, last + 1)):
        if not handle.have_piece(piece):
            handle.set_piece_deadline(piece, 300 + n * 150)


def stream_idle_for(tid: str) -> float:
    return time.time() - STREAM_LAST_USED.get(tid, time.time())


def stream_activity(tid: str) -> dict:
    """Is it a cached stream, has a player connected, and is one taking
    data from it right now."""
    playing = tid in STREAM_OPENED and stream_idle_for(tid) < STREAM_PLAYING_WINDOW
    return {"cached": tid in STREAM_CACHE_IDS, "playing": playing, "opened": tid in STREAM_OPENED,
            "connections": len(STREAM_SOCKETS.get(tid, ()))}


def stream_status(tid: str, index: int) -> dict:
    with LOCK:
        handle = HANDLES.get(tid)
    entry = STREAM_FILES.get((tid, index))
    if not handle or not handle.is_valid():
        return {"ready": bool(entry), "done": True, "progress": 100.0, "gone": not entry, **stream_activity(tid)}
    st = handle.status()
    ti = handle.torrent_file()
    size = ti.files().file_size(index)
    first, last = _file_pieces(ti, index, 0, min(size, STREAM_HEAD))
    head_have = sum(handle.have_piece(p) for p in range(first, last + 1))
    progress = handle.file_progress()[index] / size * 100 if size else 0
    return {
        "ready": head_have == last - first + 1,
        "head_progress": round(head_have / (last - first + 1) * 100),
        "progress": round(progress, 1),
        "done": progress >= 100,
        "download_rate": st.download_rate,
        "num_peers": st.num_peers,
        "num_seeds": st.num_seeds,
        **stream_activity(tid),
    }


def cached_streams() -> list:
    """The streams in the cache, for the Downloads list - they aren't
    downloads, but they need to be visible to be stopped."""
    out = []
    with LOCK:
        entries = [(tid, HANDLES.get(tid)) for tid in STREAM_CACHE_IDS]
    for tid, h in entries:
        if not h or not h.is_valid():
            continue
        st = h.status()
        item = {"id": tid, "name": st.name or "Fetching metadata...", "file": None, "progress": 0.0,
                "download_rate": st.download_rate, "num_peers": st.num_peers, **stream_activity(tid)}
        if st.has_metadata:
            ti = h.torrent_file()
            index = next((k[1] for k in STREAM_FILES if k[0] == tid), None)
            if index is None:
                index = pick_video_file(ti)  # STREAM_FILES doesn't survive a restart
            size = ti.files().file_size(index)
            item.update(file=index, name=Path(ti.files().file_path(index)).name,
                        progress=round(h.file_progress()[index] / size * 100, 1) if size else 0.0)
        out.append(item)
    return out


# What a tracker's (Jackett's) download link failing usually means - say
# so, since a player only shows "can't open".
TRACKER_FETCH_ERROR = ("The tracker didn't hand over this torrent - its login in Jackett has probably "
                       "expired: open Jackett (port 9117) and log that indexer in again, or pick a "
                       "release with a magnet link")


class StreamError(Exception):
    def __init__(self, message: str, status: int):
        super().__init__(message)
        self.status = status


def begin_stream(source: dict, prepare_only=False) -> tuple:
    # Native sessions and cleanup use the same lock, so a stream cannot be
    # deleted between preparing its files and registering a viewer.
    with STREAM_SETUP_LOCK:
        return _begin_stream(source, prepare_only)


def _begin_stream(source: dict, prepare_only=False) -> tuple:
    """Start (or reuse) a torrent in streaming mode; returns (tid, file
    index). `source` is {"id"} (something in Downloads), {"magnet"},
    {"download_link"} or {"torrent_hex"} (a .torrent already fetched).
    A new torrent goes to the stream cache. Waits up to ~30s for a
    magnet's metadata - the file list is needed to know what to play."""
    magnet = (source.get("magnet") or "").strip()
    download_link = (source.get("download_link") or "").strip()
    try:
        if source.get("id"):  # something already in Downloads
            info, tid = None, str(source["id"])
            with LOCK:
                if tid not in HANDLES:
                    raise StreamError("That download is gone", 404)
        elif source.get("torrent_hex"):  # before magnet: no metadata to wait for
            info = lt.torrent_info(bytes.fromhex(source["torrent_hex"]))
            tid = _info_hash_hex(info=info)
        elif magnet.lower().startswith("magnet:?"):
            info, tid = None, _info_hash_hex(magnet=magnet)
        elif download_link:
            req = urllib.request.Request(download_link, headers={"User-Agent": "TorrentTube"})
            with urllib.request.urlopen(req, timeout=25) as resp:
                info = lt.torrent_info(resp.read())
            tid = _info_hash_hex(info=info)
        else:
            raise StreamError("Nothing to play", 400)
    except StreamError:
        raise
    except Exception:
        raise StreamError(TRACKER_FETCH_ERROR if download_link else "Couldn't fetch that torrent", 400)

    with LOCK:
        existing = HANDLES.get(tid)
    is_new = not (existing and existing.is_valid())
    if is_new:
        save_path = str(STREAM_CACHE_DIR)
        tid = add_torrent_file(info, save_path, nothing_wanted=True) if info else add_magnet(magnet, save_path)
        STREAM_CACHE_IDS.add(tid)
        STREAM_STARTED[tid] = time.time()
    STREAM_LAST_USED[tid] = time.time()
    with LOCK:
        handle = HANDLES[tid]

    deadline = time.time() + 30
    while not handle.status().has_metadata:
        if time.time() > deadline:
            raise StreamError("Couldn't get the file list - no peers yet. Try again in a bit.", 504)
        time.sleep(0.25)

    ti = handle.torrent_file()
    fs = ti.files()
    index = source.get("file", pick_video_file(ti))
    if isinstance(index, bool) or not isinstance(index, int) or not 0 <= index < fs.num_files():
        raise StreamError("Invalid video file index", 400)
    if "file" in source and Path(fs.file_path(index)).suffix.lower() not in VIDEO_EXTS:
        raise StreamError("That file is not a video", 400)
    if prepare_only:
        if is_new:
            handle.prioritize_files([0] * fs.num_files())
        save_registry()
        return tid, index
    if (tid, index) in STREAM_FILES and handle.is_valid():
        return tid, index  # already streaming - don't re-rush the start on every request

    if is_new:
        # Only the video - not the samples, extras, other episodes.
        priorities = [0] * fs.num_files()
        priorities[index] = 4
        handle.prioritize_files(priorities)
    elif handle.get_file_priorities()[index] == 0:
        handle.file_priority(index, 4)
    handle.set_flags(lt.torrent_flags.sequential_download)
    with LOCK:
        PAUSED_IDS.discard(tid)
    handle.unset_flags(lt.torrent_flags.auto_managed)
    handle.resume()

    size = fs.file_size(index)
    # The start to begin playing, and the very end - containers keep their
    # index there (MKV cues, a non-faststart MP4's moov), and players read
    # it first.
    rush_pieces(handle, *_file_pieces(ti, index, 0, min(size, STREAM_HEAD)))
    rush_pieces(handle, *_file_pieces(ti, index, max(0, size - 2 * 1024 * 1024), size))
    STREAM_FILES[(tid, index)] = {"path": str(Path(handle.status().save_path) / fs.file_path(index)), "size": size}
    save_registry()
    return tid, index


@app.route("/api/stream", methods=["POST"])
def start_stream():
    """Start (or reuse) a torrent in streaming mode and return its stream
    URL. Takes the same magnet / download_link as adding a download, or
    the id of one."""
    try:
        tid, index = begin_stream(request.json or {})
    except StreamError as e:
        return jsonify({"error": str(e)}), e.status
    with LOCK:
        handle = HANDLES[tid]
    fs = handle.torrent_file().files()
    size = fs.file_size(index)
    name = Path(fs.file_path(index)).name
    return jsonify({
        "id": tid,
        "file": index,
        "name": name,
        "size": size,
        "size_label": format_size(size),
        "url": f"/stream/{tid}/{index}/{urllib.parse.quote(name)}",
        "cached": tid in STREAM_CACHE_IDS,
        **stream_status(tid, index),
    })


# ---------- Play links ----------
# Play opens the player straight away with a link the page makes up on the
# tap itself - /play/<token>/<title> - while it tells the server (POST
# /api/play) what that token is. The player's first request waits for the
# torrent to start and its file list to arrive, then streams like /stream.
# A token stays valid after its stream is cleared: opening the link again
# (or a player resuming after a long pause) starts the torrent again, and
# the player remembers its position because the URL is the same.
PLAY_LINKS_FILE = STATE_DIR / "play_links.json"
PLAY_LINKS_MAX = 300
PLAY_LINKS_KEEP = 30 * 86400  # forget a link not played for this long
PLAY_TOKEN_RE = re.compile(r"^[a-z]-[0-9a-f]{6,64}$")
PLAY_LOCKS = {}
PLAY_ERRORS = {}  # token -> why its stream couldn't start (for the page to show)


def _load_play_links() -> dict:
    try:
        return json.loads(PLAY_LINKS_FILE.read_text())
    except (OSError, ValueError):
        return {}


PLAY_LINKS = _load_play_links()


def save_play_links():
    """Only what a link plays (magnet / tracker link / download id, title)
    goes to disk - not the .torrent kept in memory to restart quickly, so
    nothing of a watched film's torrent stays behind on disk."""
    with LOCK:
        cutoff = time.time() - PLAY_LINKS_KEEP
        for token in [t for t, l in PLAY_LINKS.items() if l.get("at", 0) < cutoff]:
            PLAY_LINKS.pop(token, None)
        if len(PLAY_LINKS) > PLAY_LINKS_MAX:  # forget the oldest
            for token, _ in sorted(PLAY_LINKS.items(), key=lambda kv: kv[1].get("at", 0))[:len(PLAY_LINKS) - PLAY_LINKS_MAX]:
                PLAY_LINKS.pop(token, None)
        data = json.dumps({t: {k: v for k, v in l.items() if k != "torrent_hex"} for t, l in PLAY_LINKS.items()})
    PLAY_LINKS_FILE.write_text(data)


def _play_lock(token: str) -> threading.Lock:
    with LOCK:
        return PLAY_LOCKS.setdefault(token, threading.Lock())


def resolve_play_link(token: str) -> tuple:
    """(tid, file index) for a play token, starting its torrent if it isn't
    running (first open, or cleared since). One start per token at a time -
    a player opens several connections at once."""
    link = PLAY_LINKS.get(token)
    if not link:
        raise StreamError("Unknown play link", 404)
    link["at"] = time.time()  # played - keep the link another PLAY_LINKS_KEEP
    with _play_lock(token):
        source = {k: link[k] for k in ("id", "magnet", "download_link", "torrent_hex") if link.get(k)}
        if source.get("download_link") and not source.get("torrent_hex"):
            # Fetch the .torrent once and keep it in memory - starting it
            # again after the stream is cleared needn't hit the tracker.
            try:
                req = urllib.request.Request(source["download_link"], headers={"User-Agent": "TorrentTube"})
                with urllib.request.urlopen(req, timeout=25) as resp:
                    raw = resp.read()
                lt.torrent_info(raw)
                link["torrent_hex"] = source["torrent_hex"] = raw.hex()
                save_play_links()
            except Exception:
                raise StreamError(TRACKER_FETCH_ERROR, 400)
        if source.get("id"):
            with LOCK:
                gone = source["id"] not in HANDLES
            if gone and link.get("magnet"):
                source = {"magnet": link["magnet"]}  # removed from Downloads since - stream it again
        tid, index = begin_stream(source)
        if link.get("tid") != tid:
            link["tid"] = tid  # for /played/<token>, after a restart too
            save_play_links()
        return tid, index


@app.route("/api/play", methods=["POST"])
def register_play_link():
    """Says what a play token plays: {token, magnet | download_link | id,
    title, start}. Returns at once; the torrent starts in the background so
    it's already fetching by the time the player asks for the video -
    unless start is false (a copied link), when it waits for the player."""
    payload = request.json or {}
    token = str(payload.get("token", ""))
    if not PLAY_TOKEN_RE.match(token):
        return jsonify({"error": "Bad play token"}), 400
    link = {k: str(payload[k]).strip() for k in ("id", "magnet", "download_link", "title") if payload.get(k)}
    if not any(link.get(k) for k in ("id", "magnet", "download_link")):
        return jsonify({"error": "Nothing to play"}), 400
    link["at"] = time.time()
    with LOCK:
        old = PLAY_LINKS.get(token, {})
        if old.get("torrent_hex") and old.get("download_link") == link.get("download_link"):
            link["torrent_hex"] = old["torrent_hex"]
        PLAY_LINKS[token] = link
    save_play_links()
    stream_log(f"play {token} {link.get('title', '')[:80]!r}{'' if payload.get('start', True) else ' (link copied - starts when a player opens it)'}")
    if not payload.get("start", True):
        # A copied link: nothing downloads until a player really opens it.
        return jsonify({"ok": True})

    PLAY_ERRORS.pop(token, None)

    def start():
        try:
            resolve_play_link(token)
        except StreamError as e:
            note_play_error(token, e)
    threading.Thread(target=start, daemon=True).start()
    return jsonify({"ok": True})


def note_play_error(token: str, error: "StreamError"):
    """A player only says "can't open" - keep the reason for the page."""
    PLAY_ERRORS[token] = str(error)
    stream_log(f"play {token} failed: {error}")


@app.route("/api/play/<token>")
def play_link_status(token):
    """For the page after Play: did the stream start, or why not."""
    link = PLAY_LINKS.get(token) or {}
    tid = link.get("tid")
    return jsonify({"error": PLAY_ERRORS.get(token), "started": bool(tid and (tid in STREAM_CACHE_IDS or tid in HANDLES))})


@app.route("/played/<token>")
@stream_transaction
def player_closed(token):
    """The player's x-success / x-error callback: it was closed (or
    playback failed), so stop the stream - a cached one is deleted with
    its files - and send the browser that opened this back to the app."""
    link = PLAY_LINKS.get(token) or {}
    tid = link.get("tid") or (token[2:] if token.startswith(("m-", "d-")) else None)
    stream_log(f"close callback {token} {request.query_string.decode()[:200]!r} from {request.headers.get('User-Agent', '?')[:80]!r}")
    deleted = False
    if tid and PLAYBACK_SESSIONS.has_viewers(tid):
        return redirect("/")
    if tid and tid in STREAM_CACHE_IDS:
        drop_cached_stream(tid)
        save_registry()
        deleted = True
    elif tid:
        with LOCK:
            handle = HANDLES.get(tid)
        if handle and handle.is_valid():  # a download being streamed - just stop streaming it
            handle.unset_flags(lt.torrent_flags.sequential_download)
            if tid not in PAUSED_IDS:
                handle.set_flags(lt.torrent_flags.auto_managed)
    return redirect("/?stream_closed=1" if deleted else "/")


@app.route("/play/<token>/<path:name>")
def play_link(token, name):
    """The video for a play token. The player may get here before the page's
    POST /api/play does - wait a little for it."""
    deadline = time.time() + 20
    while token not in PLAY_LINKS:
        if time.time() > deadline:
            return jsonify({"error": "Unknown play link"}), 404
        time.sleep(0.2)
    try:
        tid, index = resolve_play_link(token)
    except StreamError as e:
        note_play_error(token, e)
        return jsonify({"error": str(e)}), e.status
    PLAY_ERRORS.pop(token, None)
    with LOCK:
        handle = HANDLES.get(tid)
    real_name = Path(handle.torrent_file().files().file_path(index)).name if handle and handle.is_valid() else name
    return stream_file(tid, index, real_name)


def adopt_cached_stream(tid: str, category: str) -> "str | None":
    """Turns a cached stream into an ordinary download: moved to the
    category folder, back in the Downloads list, every file wanted. None
    when `tid` isn't a cached stream."""
    with LOCK:
        handle = HANDLES.get(tid)
        if tid not in STREAM_CACHE_IDS or not handle or not handle.is_valid():
            return None
        STREAM_CACHE_IDS.discard(tid)
    STREAM_STOPPED.discard(tid)
    handle.move_storage(resolve_save_path(category))
    if handle.status().has_metadata:
        handle.prioritize_files([4] * handle.torrent_file().files().num_files())
    handle.set_flags(lt.torrent_flags.auto_managed)
    handle.resume()
    return tid


def drop_cached_stream(tid: str):
    PLAYBACK_SESSIONS.discard_torrent(tid)
    with LOCK:
        handle = HANDLES.pop(tid, None)
        PAUSED_IDS.discard(tid)
        STREAM_CACHE_IDS.discard(tid)
    STREAM_LAST_USED.pop(tid, None)
    STREAM_OPENED.discard(tid)
    for key in [k for k in STREAM_FILES if k[0] == tid]:
        STREAM_FILES.pop(key, None)
    # A player that stopped reading leaves its response's thread blocked in
    # waitress's output buffer, and waitress never times out a connection
    # mid-response - shutting the socket down is what wakes that thread.
    STREAM_LAST_CONNECTED.pop(tid, None)
    STREAM_STARTED.pop(tid, None)
    STREAM_STOPPED.discard(tid)
    for sock in STREAM_SOCKETS.pop(tid, set()):
        try:
            sock.shutdown(socket.SHUT_RDWR)
        except (OSError, AttributeError):  # AttributeError: a counted non-socket
            pass
    if handle and handle.is_valid():
        if handle.status().has_metadata:
            remember_torrent_file(tid, handle)
        ses.remove_torrent(handle, lt.session.delete_files)


def remember_torrent_file(tid: str, handle):
    """Keep a dropped stream's .torrent with its play links, so opening one
    again starts at once instead of fetching a magnet's metadata again."""
    with LOCK:
        links = [l for t, l in PLAY_LINKS.items() if t == f"m-{tid}"]
    if not links:
        return
    ti = handle.torrent_file()
    raw = lt.bencode({"info": lt.bdecode(ti.info_section())}).hex()
    for link in links:
        link["torrent_hex"] = raw
    save_play_links()


@app.route("/api/stream/<tid>/keep", methods=["POST"])
def keep_stream(tid):
    """Keep a streamed film: it becomes a normal download in that folder."""
    category = (request.json or {}).get("category", "")
    if tid not in STREAM_CACHE_IDS:
        return jsonify({"ok": True})  # already a download
    if not adopt_cached_stream(tid, category):
        return jsonify({"error": "That stream is gone"}), 404
    save_registry()
    return jsonify({"ok": True, "category": Path(resolve_save_path(category)).name})


@app.route("/api/stream/<tid>", methods=["DELETE"])
@stream_transaction
def stop_stream(tid):
    """Stop a stream. A cached one is dropped with its data now instead of
    waiting for its player to close; a stream of something in Downloads just
    goes back to downloading normally (its files are the user's)."""
    if PLAYBACK_SESSIONS.has_viewers(tid):
        return jsonify({"error": "A native player is still using this stream"}), 409
    if tid in STREAM_CACHE_IDS:
        drop_cached_stream(tid)
        save_registry()
        return jsonify({"ok": True, "deleted": True})
    with LOCK:
        handle = HANDLES.get(tid)
    if handle and handle.is_valid():
        handle.unset_flags(lt.torrent_flags.sequential_download)
        if tid not in PAUSED_IDS:
            handle.set_flags(lt.torrent_flags.auto_managed)
    return jsonify({"ok": True, "deleted": False})


def clean_stream_cache():
    with STREAM_SETUP_LOCK:
        _clean_stream_cache()


def _clean_stream_cache():
    """Drops cached streams no player has taken data from for
    STREAM_ABANDON_AFTER (the player never said it closed), and anything
    left in the cache folder that no stream owns (a crash, a restart
    between saves)."""
    now = time.time()
    dropped = False
    for tid in list(STREAM_CACHE_IDS):
        if PLAYBACK_SESSIONS.has_viewers(tid):
            # A paused or fully buffered player may have no media socket.
            STREAM_LAST_CONNECTED[tid] = now
            STREAM_STARTED[tid] = now
            STREAM_LAST_USED[tid] = now
            continue
        if now - STREAM_LAST_USED.get(tid, now) > STREAM_ABANDON_AFTER:
            stream_log(f"deleting {tid}: no data taken for {STREAM_ABANDON_AFTER // 3600} h")
            drop_cached_stream(tid)
            dropped = True
        elif tid not in STREAM_OPENED:
            if now - STREAM_STARTED.get(tid, now) > STREAM_NEVER_OPENED_AFTER:
                stream_log(f"deleting {tid}: no player connected within {STREAM_NEVER_OPENED_AFTER} s")
                drop_cached_stream(tid)
                dropped = True
        elif not STREAM_SOCKETS.get(tid):
            gone_for = now - STREAM_LAST_CONNECTED.get(tid, now)
            if gone_for > STREAM_CLOSED_AFTER:
                stream_log(f"deleting {tid}: player closed (no connection for {STREAM_CLOSED_AFTER} s)")
                drop_cached_stream(tid)
                dropped = True
            elif gone_for > STREAM_STOP_AFTER and tid not in STREAM_STOPPED:
                with LOCK:
                    handle = HANDLES.get(tid)
                if handle and handle.is_valid():
                    stream_log(f"stopping {tid}: player has no connection")
                    STREAM_STOPPED.add(tid)  # player gone - stop downloading
                    handle.pause()
    if dropped:
        save_registry()

    owned = set()
    with LOCK:
        handles = [HANDLES.get(tid) for tid in STREAM_CACHE_IDS]
    for h in handles:
        if not h or not h.is_valid() or not h.status().has_metadata:
            return  # can't tell what it owns yet - sweep next time
        owned.add(h.torrent_file().files().file_path(0).replace("\\", "/").split("/")[0])
        owned.add(h.torrent_file().name())
    live_ids = set(STREAM_CACHE_IDS)
    for child in STREAM_CACHE_DIR.iterdir():
        if child.name in owned or any(t in child.name for t in live_ids):
            continue  # its files, or its ".<hash>.parts" file
        try:
            if now - child.stat().st_mtime < 600:  # might still be starting up
                continue
            if child.is_dir():
                shutil.rmtree(child)
            else:
                child.unlink()
        except OSError:
            pass


def stream_cache_loop():
    while True:
        time.sleep(5)
        try:
            clean_stream_cache()
        except Exception:
            pass


@app.route("/api/stream/<tid>/<int:index>")
def get_stream_status(tid, index):
    with LOCK:
        handle = HANDLES.get(tid)
    if handle and handle.is_valid() and handle.status().has_metadata:
        if index >= handle.torrent_file().files().num_files():
            return jsonify({"error": "No such file"}), 404
    return jsonify(stream_status(tid, index))


LIBRARY = MediaLibrary(DOWNLOAD_DIR, CATEGORIES, VIDEO_EXTS,
                       describe=lambda name: (lambda t: (t[0], t[2]))(extract_title_and_year(name)))
LIBRARY_PREFIX = "lib:"


@app.route("/api/library")
def list_library():
    """Everything already in the category folders, newest first."""
    return jsonify({"items": LIBRARY.items(refresh=request.args.get("refresh") == "1")})


def _library_files(payload):
    path = payload.get("path")
    if not isinstance(path, str):
        raise StreamError("Library path must be text", 400)
    files = LIBRARY.files(path)
    if not files:
        raise StreamError("That title is no longer on the server", 404)
    return path, files


@app.route("/media/<path:relative>")
def library_file(relative):
    """A library video straight from disk, with Range support for seeking."""
    path = LIBRARY.resolve(relative)
    if path is None or not path.is_file() or path.suffix.lower() not in VIDEO_EXTS:
        return jsonify({"error": "No such file"}), 404
    kind = "video/x-matroska" if path.suffix.lower() == ".mkv" else (mimetypes.guess_type(path.name)[0] or "application/octet-stream")
    return send_file(path, mimetype=kind, conditional=True)


@app.route("/api/playback/prepare", methods=["POST"])
def prepare_native_playback():
    """Resolve metadata and list episodes before opening a player."""
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return jsonify({"error": "Expected a JSON object"}), 400
    if "path" in payload:  # already on the server: list its files, nothing to fetch
        try:
            path, files = _library_files(payload)
        except StreamError as e:
            return jsonify({"error": str(e)}), e.status
        selected = max(files, key=lambda f: f["size"])["index"]
        return jsonify({"id": LIBRARY_PREFIX + path, "selected": selected, "files": files})
    if any(k in payload and not isinstance(payload[k], str) for k in ("id", "magnet", "download_link")):
        return jsonify({"error": "Playback source fields must be text"}), 400
    with STREAM_SETUP_LOCK:
        try:
            tid, selected = begin_stream(payload, prepare_only=True)
            with LOCK:
                handle = HANDLES.get(tid)
            fs = handle.torrent_file().files()
            files = [{"index": i, "name": Path(fs.file_path(i)).name,
                      "path": fs.file_path(i), "size": fs.file_size(i)}
                     for i in range(fs.num_files())
                     if Path(fs.file_path(i)).suffix.lower() in VIDEO_EXTS]
            return jsonify({"id": tid, "selected": selected, "files": files})
        except StreamError as e:
            return jsonify({"error": str(e)}), e.status


@app.route("/api/playback/sessions", methods=["POST"])
def create_native_playback():
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return jsonify({"error": "Expected a JSON object"}), 400
    if "path" in payload:
        try:
            path, files = _library_files(payload)
        except StreamError as e:
            return jsonify({"error": str(e)}), e.status
        index = payload.get("file", max(files, key=lambda f: f["size"])["index"])
        if isinstance(index, bool) or not isinstance(index, int) or not 0 <= index < len(files):
            return jsonify({"error": "Invalid video file index"}), 400
        file = files[index]
        token = PLAYBACK_SESSIONS.create(LIBRARY_PREFIX + path, index)
        return jsonify({"session": token, "id": LIBRARY_PREFIX + path, "file": index, "name": file["name"],
                        "url": "/media/" + urllib.parse.quote(file["path"]),
                        "heartbeat_interval": 20, "expires_after": PLAYBACK_SESSIONS.ttl,
                        "ready": True, "head_progress": 100, "progress": 100.0, "done": True})
    if any(k in payload and not isinstance(payload[k], str) for k in ("id", "magnet", "download_link")):
        return jsonify({"error": "Playback source fields must be text"}), 400
    with STREAM_SETUP_LOCK:
        try:
            tid, index = begin_stream(payload)
            with LOCK:
                handle = HANDLES.get(tid)
            fs = handle.torrent_file().files()
            name = Path(fs.file_path(index)).name
            token = PLAYBACK_SESSIONS.create(tid, index)
            return jsonify({"session": token, "id": tid, "file": index, "name": name,
                            "url": f"/stream/{tid}/{index}/{urllib.parse.quote(name)}",
                            "heartbeat_interval": 20, "expires_after": PLAYBACK_SESSIONS.ttl,
                            **stream_status(tid, index)})
        except StreamError as e:
            return jsonify({"error": str(e)}), e.status


@app.route("/api/playback/sessions/<token>", methods=["POST", "DELETE"])
def native_playback_session(token):
    with STREAM_SETUP_LOCK:
        entry = PLAYBACK_SESSIONS.touch(token) if request.method == "POST" else PLAYBACK_SESSIONS.close(token)
        if not entry:
            return jsonify({"error": "Playback session expired. Start playback again."}), 410
        tid = entry["torrent_id"]
        if tid.startswith(LIBRARY_PREFIX):  # a file on disk: always ready, nothing to clean up
            return jsonify({"ok": True} if request.method == "DELETE" else
                           {"ready": True, "head_progress": 100, "progress": 100.0, "done": True})
        if request.method == "DELETE":
            if not PLAYBACK_SESSIONS.has_viewers(tid) and not STREAM_SOCKETS.get(tid):
                if tid in STREAM_CACHE_IDS:
                    drop_cached_stream(tid)
                    save_registry()
                else:
                    with LOCK:
                        handle = HANDLES.get(tid)
                    if handle and handle.is_valid():
                        handle.unset_flags(lt.torrent_flags.sequential_download)
                        if tid not in PAUSED_IDS:
                            handle.set_flags(lt.torrent_flags.auto_managed)
            return jsonify({"ok": True})
        status = stream_status(tid, entry["file"])
        if status.get("gone"):
            PLAYBACK_SESSIONS.close(token)
            return jsonify({"error": "The stream was removed"}), 410
        return jsonify(status)


@app.route("/stream/<tid>/<int:index>/<path:name>")
def stream_file(tid, index, name):
    """The file itself, with HTTP Range support. Each chunk waits for its
    piece (rushed to the front of the queue along with the next
    STREAM_READAHEAD bytes) before it's read from disk."""
    entry = STREAM_FILES.get((tid, index))
    with LOCK:
        handle = HANDLES.get(tid)
    live = handle is not None and handle.is_valid() and handle.status().has_metadata
    if live:
        ti = handle.torrent_file()
        fs = ti.files()
        if index >= fs.num_files():
            return jsonify({"error": "No such file"}), 404
        size = fs.file_size(index)
        path = str(Path(handle.status().save_path) / fs.file_path(index))
    elif entry:
        size, path = entry["size"], entry["path"]
    else:
        return jsonify({"error": "Not streaming that"}), 404

    start, end = 0, size - 1
    range_header = request.headers.get("Range", "")
    match = re.match(r"bytes=(\d*)-(\d*)", range_header)
    if match:
        if match.group(1):
            start = int(match.group(1))
            if match.group(2):
                end = min(int(match.group(2)), size - 1)
        elif match.group(2):  # "bytes=-N": the last N bytes
            start = max(0, size - int(match.group(2)))
        if start >= size or start > end:
            return Response(status=416, headers={"Content-Range": f"bytes */{size}"})

    def dropped():
        # Stopped (or its player closed) while this response was
        # open: its files are gone, so end the response rather than serve
        # a deleted file - an open handle on it would also keep the space.
        return live and not handle.is_valid() and (tid, index) not in STREAM_FILES

    def generate():
        pos = start
        while pos <= end:
            if dropped():
                return
            if live and handle.is_valid():
                piece, _ = _file_pieces(ti, index, pos, pos + 1)
                piece_end = min((piece + 1) * ti.piece_length() - fs.file_offset(index), size)
                if not handle.have_piece(piece):
                    rush_pieces(handle, *_file_pieces(ti, index, pos, min(size, pos + STREAM_READAHEAD)))
                    waited = time.time()
                    while not handle.have_piece(piece):
                        if not handle.is_valid() or dropped():
                            break
                        if client_gone():
                            return  # the player hung up while we waited for the piece
                        if time.time() - waited > STREAM_PIECE_TIMEOUT:
                            return
                        STREAM_LAST_USED[tid] = time.time()  # the player is waiting, not gone
                        time.sleep(0.1)
                chunk_end = min(end + 1, piece_end)
            else:
                chunk_end = end + 1  # finished (and possibly removed) - just read it
            try:
                with open(path, "rb") as f:
                    f.seek(pos)
                    while pos < chunk_end:
                        if dropped():
                            return
                        data = f.read(min(STREAM_CHUNK, chunk_end - pos))
                        if not data:
                            return
                        pos += len(data)
                        yield data
            except OSError:
                return

    headers = {
        "Accept-Ranges": "bytes",
        "Content-Length": str(end - start + 1),
        "Content-Type": mimetypes.guess_type(name)[0] or "application/octet-stream",
    }
    if match:
        headers["Content-Range"] = f"bytes {start}-{end}/{size}"

    # waitress's channel, to reach the socket if the player goes quiet
    # (see drop_cached_stream). Read here: the generator runs after the
    # request context is gone.
    channel = getattr(request.environ.get("waitress.client_disconnected"), "__self__", None)
    sock = getattr(channel, "socket", None)
    ua = request.headers.get("User-Agent", "?")[:80]
    client_gone = request.environ.get("waitress.client_disconnected") or (lambda: False)

    def tracked():
        # Each chunk handed on means the player took the previous one -
        # waitress blocks here once its buffer is full and nobody reads.
        STREAM_OPENED.add(tid)
        conn = sock if sock is not None else object()  # counted either way; only a socket can be shut
        STREAM_SOCKETS.setdefault(tid, set()).add(conn)
        STREAM_LAST_CONNECTED[tid] = time.time()
        if tid in STREAM_STOPPED and live and handle.is_valid():  # back within the grace time
            STREAM_STOPPED.discard(tid)
            handle.resume()
        stream_log(f"player connected to {tid} ({len(STREAM_SOCKETS[tid])} open) bytes={start}- from {ua!r}")
        try:
            for data in generate():
                STREAM_LAST_USED[tid] = time.time()
                yield data
        finally:
            STREAM_SOCKETS.get(tid, set()).discard(conn)
            STREAM_LAST_CONNECTED[tid] = time.time()
            stream_log(f"player connection to {tid} closed ({len(STREAM_SOCKETS.get(tid, ()))} open)")

    STREAM_LAST_USED[tid] = time.time()
    return Response(tracked(), status=206 if match else 200, headers=headers, direct_passthrough=True)


load_registry()
threading.Thread(target=registry_saver_loop, daemon=True).start()
threading.Thread(target=stream_cache_loop, daemon=True).start()


if __name__ == "__main__":
    from waitress import serve

    host = os.environ.get("TORRENTTUBE_HOST", "127.0.0.1")
    port = int(os.environ.get("TORRENTTUBE_PORT", "5058"))
    # Each open stream holds a worker thread for as long as it plays, and
    # players open several connections (probing, seeking) - waitress's
    # default of 4 would leave the UI unresponsive during playback.
    # A 4MB output buffer (waitress's default is 16MB) per connection: a
    # player that stops reading is noticed once it fills - see
    # STREAM_LAST_USED - so a smaller one notices a closed player sooner.
    # channel_request_lookahead lets waitress keep reading a connection while
    # its response runs, so it sees the player hang up even while the
    # response is waiting on a piece - see client_gone in stream_file.
    serve(app, host=host, port=port, threads=24, outbuf_high_watermark=4 * 1024 * 1024,
          channel_request_lookahead=5)
