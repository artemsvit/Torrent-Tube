import json
import os
import re
import threading
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import libtorrent as lt
from flask import Flask, jsonify, render_template, request

DOWNLOAD_DIR = Path(os.environ.get("TORRENTTUBE_DOWNLOAD_DIR") or (Path.home() / "Downloads" / "TorrentTube"))
DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)

CATEGORIES = [
    c.strip()
    for c in os.environ.get("TORRENTTUBE_CATEGORIES", "Cartoon,Movies,TV Shows").split(",")
    if c.strip()
]
for _category in CATEGORIES:
    (DOWNLOAD_DIR / _category).mkdir(parents=True, exist_ok=True)

STATE_DIR = Path(os.environ.get("TORRENTTUBE_STATE_DIR") or (DOWNLOAD_DIR / ".torrenttube"))
STATE_DIR.mkdir(parents=True, exist_ok=True)
RESUME_FILE = STATE_DIR / "torrents.json"

# Optional: point at a Jackett instance to enable the Search tab. Jackett does
# the actual tracker login/scraping (configured with the user's own tracker
# credentials, entered directly into Jackett's own UI) - this app only talks
# to Jackett's local Torznab API with Jackett's own API key.
JACKETT_URL = os.environ.get("JACKETTAPI_URL", "").rstrip("/")
JACKETT_API_KEY = os.environ.get("JACKETTAPI_KEY", "")
JACKETT_INDEXER = os.environ.get("JACKETTAPI_INDEXER", "all")
TORZNAB_NS = {"torznab": "http://torznab.com/schemas/2015/feed"}

# Optional: enriches search results with a poster/rating from TMDB. Jackett's
# indexers don't carry images, so this looks the parsed title up separately.
# Get a free key at https://www.themoviedb.org/settings/api
TMDB_API_KEY = os.environ.get("TMDB_API_KEY", "")
TMDB_LANGUAGE = os.environ.get("TMDB_LANGUAGE", "uk-UA")
TMDB_CACHE = {}
TMDB_CACHE_TTL = 6 * 3600
TMDB_EXECUTOR = ThreadPoolExecutor(max_workers=8)

app = Flask(__name__)
app.config["TEMPLATES_AUTO_RELOAD"] = True
app.config["MAX_CONTENT_LENGTH"] = 8 * 1024 * 1024  # .torrent files are tiny; 8MB is generous

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

# ---------- Bandwidth / connection limits ----------
# User-adjustable via /api/settings (Settings popup in the UI). Persisted to
# disk so they survive a container restart, and re-applied to the live
# libtorrent session (and every open torrent handle, for the per-torrent
# connection cap) whenever they change.
SETTINGS_FILE = STATE_DIR / "settings.json"
DEFAULT_LIMITS = {
    "download_rate_limit": 0,       # KB/s, 0 = unlimited
    "upload_rate_limit": 0,         # KB/s, 0 = unlimited
    "max_connections": 0,           # global peer connections, 0 = libtorrent default
    "max_connections_per_torrent": 0,  # per-torrent peer connections, 0 = no cap
    "max_upload_slots": 0,          # unchoke slots, 0 = libtorrent default
    "seed_after_download": 1,       # 0/1 - pause a torrent as soon as it finishes instead of seeding
}


def load_limits() -> dict:
    if SETTINGS_FILE.exists():
        try:
            saved = json.loads(SETTINGS_FILE.read_text())
            return {k: int(saved.get(k, v)) for k, v in DEFAULT_LIMITS.items()}
        except Exception:
            pass
    return dict(DEFAULT_LIMITS)


LIMITS = load_limits()


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
            else:
                entry["magnet_uri"] = lt.make_magnet_uri(h)
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
                add_torrent_file(info, entry["save_path"])
            elif "magnet_uri" in entry:
                add_magnet(entry["magnet_uri"], entry["save_path"])
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


def add_torrent_file(info: "lt.torrent_info", save_path: str = None) -> str:
    params = lt.add_torrent_params()
    params.ti = info
    params.save_path = save_path or resolve_save_path()
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


@app.route("/api/config")
def config():
    search_enabled = bool(JACKETT_URL and JACKETT_API_KEY)
    return jsonify({
        "download_dir": str(DOWNLOAD_DIR),
        "categories": CATEGORIES,
        "search_enabled": search_enabled,
        # Descriptive only - never the Jackett/TMDB API keys themselves.
        "search_indexer": JACKETT_INDEXER if search_enabled else None,
        "tmdb_enabled": bool(TMDB_API_KEY),
        "tmdb_language": TMDB_LANGUAGE if TMDB_API_KEY else None,
    })


@app.route("/api/settings", methods=["GET"])
def get_settings():
    return jsonify(LIMITS)


@app.route("/api/settings", methods=["POST"])
def update_settings():
    payload = request.json or {}
    for key in DEFAULT_LIMITS:
        if key not in payload:
            continue
        try:
            LIMITS[key] = max(0, int(payload[key]))
        except (TypeError, ValueError):
            return jsonify({"error": f"'{key}' must be a non-negative number"}), 400

    apply_session_limits()
    with LOCK:
        handles = list(HANDLES.values())
    for h in handles:
        if h.is_valid():
            apply_torrent_limits(h)
    SETTINGS_FILE.write_text(json.dumps(LIMITS))
    return jsonify(LIMITS)


COLLECTION_WORDS_RE = re.compile(
    r"\b(complete collection|full collection|collection|quadrilogy|trilogy|duology|anthology|saga)\b.*",
    re.I,
)


def extract_title_and_year(raw_title: str):
    """Best-effort pull of a clean, searchable title (and year) out of a
    tracker listing like 'Ukrainian Title / English Title (2001-2012) BDRip
    Ukr/Eng | Sub Eng'. Heuristic, not exact - trackers don't structure this.
    Also returns a shorter "base" title (franchise name only, no "Complete
    Collection"/"Quadrilogy"/etc.) since those bundle-release words rarely
    match anything on TMDB, which indexes individual films."""
    year_match = re.search(r"(19|20)\d{2}", raw_title)
    year = year_match.group(0) if year_match else None

    parts = raw_title.split("/")
    candidate = max(parts, key=lambda p: sum(c.isascii() and c.isalpha() for c in p)) if len(parts) > 1 else raw_title
    candidate = candidate.split("|")[0]
    candidate = re.split(r"\(\s*(19|20)\d{2}", candidate)[0]
    candidate = re.sub(r"[\[\(].*", "", candidate)
    candidate = re.sub(r"\s+", " ", candidate).strip(" :-|/")
    candidate = re.sub(r"\s+\b(3D|4K|HDR|Remastered)\b\s*$", "", candidate, flags=re.I).strip()

    base = COLLECTION_WORDS_RE.split(candidate)[0].strip(" :.-")
    return candidate, base, year


def _tmdb_search(query: str, year: str = None):
    params = {"api_key": TMDB_API_KEY, "query": query, "include_adult": "false", "language": TMDB_LANGUAGE}
    if year:
        params["year"] = year
    url = f"https://api.themoviedb.org/3/search/multi?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": "TorrentTube"})
    with urllib.request.urlopen(req, timeout=8) as resp:
        data = json.loads(resp.read())
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
            "title": item.get("title") or item.get("name") or title,
            "poster": f"https://image.tmdb.org/t/p/w200{poster_path}" if poster_path else None,
            "rating": item.get("vote_average"),
            "overview": (item.get("overview") or "")[:220],
            "year": (item.get("release_date") or item.get("first_air_date") or "")[:4],
            "media_type": item.get("media_type"),
            "genre_ids": item.get("genre_ids") or [],
        }
    TMDB_CACHE[cache_key] = (time.time(), result)
    return result


TMDB_ANIMATION_GENRE_ID = 16

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


def jackett_query(q: str = None, cat: str = None):
    """Hits Jackett's Torznab proxy for the configured indexer and returns
    parsed (but not yet TMDB-enriched) result dicts. A blank `q` isn't a
    no-op search - most trackers (this one included) treat it as "give me
    the latest uploads", which is what the Discover feeds ride on."""
    params = {"apikey": JACKETT_API_KEY, "t": "search"}
    if q:
        params["q"] = q
    if cat:
        params["cat"] = cat
    url = f"{JACKETT_URL}/api/v2.0/indexers/{JACKETT_INDEXER}/results/torznab/api?{urllib.parse.urlencode(params)}"
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
    enrich_with_tmdb(results)
    return jsonify({"results": results})


# ---------- Discover ----------
# A browsable catalog instead of a reactive search: each feed below maps to
# a specific section of the mazepa forum (Jackett's own indexer definition
# exposes the tracker's forum ids as custom Torznab categories, numbered
# 100000 + the forum id - e.g. "Новинки фільмів UHD/HD", forum id 175, is
# Torznab category 100175). Querying with cat= and no q returns that
# section's latest uploads.
DISCOVER_FEEDS = [
    {"id": "new", "label": "New releases", "cats": "100175"},
    {"id": "movies", "label": "Movies", "cats": "100012,100147"},
    {"id": "cartoons", "label": "Cartoons", "cats": "100041,100155"},
    {"id": "tv", "label": "TV Shows", "cats": "100044,100152"},
]
DISCOVER_FEEDS_BY_ID = {f["id"]: f for f in DISCOVER_FEEDS}


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
        results = jackett_query(cat=feed["cats"])
    except Exception:
        return jsonify({"error": "Couldn't reach the search service"}), 502

    results.sort(key=lambda r: r["pub_date"], reverse=True)
    # This indexer's Torznab endpoint caps out at ~50 items and doesn't
    # honor an offset (confirmed: offset=20 comes back empty rather than
    # the next page) - there's nothing further to fetch server-side, so
    # the whole feed is enriched and handed over in one response. Infinite
    # scroll is done client-side, revealing more of this same list as the
    # user scrolls rather than re-querying Jackett.
    enrich_with_tmdb(results, limit=len(results))
    return jsonify({"results": results})


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
            h.pause()
            with LOCK:
                PAUSED_IDS.add(tid)


@app.route("/api/torrents")
def list_torrents():
    enforce_seed_policy()
    with LOCK:
        items = [(tid, h) for tid, h in HANDLES.items() if h.is_valid()]
    items.sort(key=lambda pair: pair[1].status().added_time, reverse=True)
    return jsonify({"torrents": [serialize(tid, h) for tid, h in items]})


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
        tid = add_torrent_file(info, resolve_save_path(category))
    else:
        payload = (request.json or {}) if request.is_json else request.form
        magnet = payload.get("magnet", "").strip()
        download_link = payload.get("download_link", "").strip()
        category = payload.get("category", "")
        if magnet.lower().startswith("magnet:?"):
            try:
                tid = add_magnet(magnet, resolve_save_path(category))
            except Exception:
                return jsonify({"error": "Couldn't parse that magnet link"}), 400
        elif download_link:
            try:
                req = urllib.request.Request(download_link, headers={"User-Agent": "TorrentTube"})
                with urllib.request.urlopen(req, timeout=25) as resp:
                    info = lt.torrent_info(resp.read())
            except Exception:
                return jsonify({"error": "Couldn't fetch that torrent"}), 400
            tid = add_torrent_file(info, resolve_save_path(category))
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
    handle.resume()
    with LOCK:
        PAUSED_IDS.discard(tid)
    return jsonify({"ok": True})


@app.route("/api/torrents/<tid>", methods=["DELETE"])
def remove_torrent(tid):
    with LOCK:
        handle = HANDLES.pop(tid, None)
        PAUSED_IDS.discard(tid)
    if not handle or not handle.is_valid():
        return jsonify({"error": "Unknown torrent"}), 404
    delete_files = request.args.get("delete_files") == "1"
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


load_registry()
threading.Thread(target=registry_saver_loop, daemon=True).start()


if __name__ == "__main__":
    from waitress import serve

    host = os.environ.get("TORRENTTUBE_HOST", "127.0.0.1")
    port = int(os.environ.get("TORRENTTUBE_PORT", "5058"))
    serve(app, host=host, port=port)
