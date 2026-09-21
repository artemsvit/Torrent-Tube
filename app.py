import json
import os
import threading
import time
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
    return jsonify({"download_dir": str(DOWNLOAD_DIR), "categories": CATEGORIES})


@app.route("/api/torrents")
def list_torrents():
    with LOCK:
        items = [(tid, h) for tid, h in HANDLES.items() if h.is_valid()]
    items.sort(key=lambda pair: pair[1].status().added_time, reverse=True)
    return jsonify({"torrents": [serialize(tid, h) for tid, h in items]})


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
        category = payload.get("category", "")
        if not magnet.lower().startswith("magnet:?"):
            return jsonify({"error": "Paste a magnet link or upload a .torrent file"}), 400
        try:
            tid = add_magnet(magnet, resolve_save_path(category))
        except Exception:
            return jsonify({"error": "Couldn't parse that magnet link"}), 400
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
