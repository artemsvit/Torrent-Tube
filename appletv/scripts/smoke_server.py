#!/usr/bin/env python3
"""Serve generated test media through the real API without using the NAS."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=5069)
    parser.add_argument("--video", type=Path, help="Use an existing permitted MKV instead of generating a 100-second test video.")
    parser.add_argument("--live-trailers", action="store_true", help="Resolve a public official trailer instead of serving generated test footage.")
    parser.add_argument("--episode-library", action="store_true", help="Test numbered episodes in multiple season folders.")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="torrenttube-playback-smoke-") as temporary:
        os.environ["TORRENTTUBE_DOWNLOAD_DIR"] = temporary
        os.environ["TORRENTTUBE_STATE_DIR"] = str(Path(temporary) / "state")
        os.environ["JACKETTAPI_KEY"] = ""
        os.environ["TMDB_API_KEY"] = ""
        sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
        import app
        from waitress import serve
        app.ses.apply_settings({"enable_dht": False, "enable_lsd": False, "enable_upnp": False, "enable_natpmp": False})
        video = args.video
        if video is None:
            video = Path(temporary) / "generated.mkv"
            print("Generating a permitted playback sample…", flush=True)
            subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc2=size=1280x720:rate=24",
                            "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000", "-t", "100", "-c:v", "libx264",
                            "-preset", "ultrafast", "-crf", "28", "-c:a", "aac", str(video)], check=True)
        root = Path(temporary) / "Movies" / "Native playback test"
        root.mkdir(parents=True)
        fs = app.lt.file_storage()
        for name in ("Episode 1.mkv", "Episode 2.mkv"):
            destination = root / name
            shutil.copyfile(video, destination)
            fs.add_file("Native playback test/" + name, destination.stat().st_size)
        torrent = app.lt.create_torrent(fs, 16384, flags=app.lt.create_torrent.v1_only)
        app.lt.set_piece_hashes(torrent, str(root.parent))
        info = app.lt.torrent_info(torrent.generate())
        tid = app.add_torrent_file(info, str(root.parent))
        handle = app.HANDLES[tid]
        while not handle.status().is_finished:
            time.sleep(0.02)
        # Deterministic trailer catalog for the native UI path. The live option
        # exercises the real resolver and provider relay instead of sample bytes.
        app.app.view_functions["find_trailer"] = lambda: app.jsonify({"videos": [{"key": "uLtkt8BonwM", "name": "Official trailer", "lang": "en"}], "query": "Native playback test"})
        if not args.live_trailers:
            app.app.view_functions["resolve_trailer_stream"] = lambda: app.jsonify({"url": "/fixture-trailer", "audio_url": None})
            @app.app.route("/fixture-trailer")
            def fixture_trailer():
                from flask import send_file
                return send_file(root / "Episode 1.mkv", mimetype="video/x-matroska", conditional=True)
        if args.episode_library:
            show = Path(temporary) / "TV Shows" / "Numbered episode playback test"
            for season in (1, 12):
                folder = show / f"Season {season}"
                folder.mkdir(parents=True)
                for episode in (1, 2, 3):
                    shutil.copyfile(video, folder / f"{episode:02d} Episode title.mkv")
            original_config = app.app.view_functions["config"]
            def episode_config():
                response = original_config()
                data = response.get_json()
                data.update(tmdb_enabled=True, numbered_episode_fixture=True)
                return app.jsonify(data)
            app.app.view_functions["config"] = episode_config
            app.app.view_functions["list_library"] = lambda: app.jsonify({"items": [{
                "id": "TV Shows/Numbered episode playback test", "name": show.name, "kind": "tv",
                "files": 6, "added": 0, "tmdb_id": 99999999, "media_type": "tv"}], "metadata_pending": 0})
            app.app.view_functions["item_details"] = lambda: app.jsonify({
                "title": show.name, "tmdb_id": 99999999, "media_type": "tv",
                "season_list": [{"number": n, "name": f"Season {n}", "episodes": 3} for n in (1, 12)]})
            app.app.view_functions["season_episodes"] = lambda: app.jsonify({
                "episodes": [{"number": n, "name": f"Episode {n}"} for n in (1, 2, 3)]})
            @app.app.route("/fixture-selected-episode")
            def selected_episode():
                with app.PLAYBACK_SESSIONS._lock:
                    sessions = [dict(entry) for entry in app.PLAYBACK_SESSIONS._sessions.values()]
                return app.jsonify({"sessions": sessions})
        print(f"Isolated playback server: http://127.0.0.1:{args.port}", flush=True)
        serve(app.app, host="127.0.0.1", port=args.port, threads=12)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
