"""Resolve public trailer streams and relay bytes without saving media files."""
import json
import os
import re
import secrets
import shutil
import subprocess
import threading
import time
import urllib.error
import urllib.parse
import urllib.request


class TrailerError(Exception):
    def __init__(self, message, status=502):
        super().__init__(message)
        self.status = status


def allowed_url(url):
    try:
        parts = urllib.parse.urlsplit(url)
        port = parts.port
    except (ValueError, TypeError):
        return False
    host = (parts.hostname or "").lower()
    return (parts.scheme == "https" and parts.username is None and parts.password is None
            and port in (None, 443) and (host == "googlevideo.com" or host.endswith(".googlevideo.com")))


def allowed_subtitle_url(url):
    """Subtitles come from YouTube's own timedtext endpoint, nowhere else."""
    try:
        parts = urllib.parse.urlsplit(url)
    except (ValueError, TypeError):
        return False
    return (parts.scheme == "https" and parts.username is None and parts.password is None
            and (parts.hostname or "").lower() == "www.youtube.com" and parts.path == "/api/timedtext")


def pick_subtitles(info, language):
    """The WebVTT URL of a trailer's subtitles in `language`: the uploader's
    own first, else YouTube's auto-translated captions."""
    for source in ("subtitles", "automatic_captions"):
        tracks = (info.get(source) or {}).get(language) or []
        for track in tracks:
            if track.get("ext") == "vtt" and allowed_subtitle_url(track.get("url", "")):
                return track["url"]
    return None


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not allowed_url(newurl):
            raise TrailerError("The trailer source returned an unsupported redirect")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


class TrailerStreams:
    def __init__(self, clock=time.monotonic, ttl=1800):
        self.clock = clock
        self.ttl = ttl
        self._items = {}
        self._lock = threading.Lock()
        self._resolvers = threading.BoundedSemaphore(2)

    def _expire(self):
        now = self.clock()
        self._items = {k: v for k, v in self._items.items() if v["expires"] > now}

    def fetch_subtitles(self, url, headers):
        """The subtitle file itself - small, kept in memory with the token.
        Any failure just means no subtitles, never a failed trailer."""
        try:
            request = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(request, timeout=10) as response:
                data = response.read(2 * 1024 * 1024 + 1)
            if len(data) > 2 * 1024 * 1024 or not data.lstrip().startswith(b"WEBVTT"):
                return None
            return data.decode("utf-8", "replace")
        except (urllib.error.URLError, TimeoutError, OSError, ValueError):
            return None

    def subtitles(self, token):
        with self._lock:
            self._expire()
            item = self._items.get(token)
            if not item:
                raise TrailerError("The trailer link expired. Open the trailer again.", 410)
            if not item.get("subtitles"):
                raise TrailerError("This trailer has no subtitles", 404)
            return item["subtitles"]

    def resolve(self, key, subtitles=None):
        if not isinstance(key, str) or not re.fullmatch(r"[A-Za-z0-9_-]{11}", key):
            raise TrailerError("Invalid trailer identifier", 400)
        executable = os.environ.get("TORRENTTUBE_YTDLP") or shutil.which("yt-dlp")
        if not executable:
            raise TrailerError("Update your server to enable trailer playback", 503)
        if not self._resolvers.acquire(blocking=False):
            raise TrailerError("Another trailer is preparing. Try again in a moment.", 429)
        try:
            result = subprocess.run([
                executable, "--ignore-config", "--no-plugin-dirs", "--no-cache-dir", "--js-runtimes", "node",
                "--socket-timeout", "12", "--retries", "1", "--extractor-retries", "1", "--skip-download", "--no-playlist",
                "--dump-single-json", "--format", "b[height>=720][height<=1080]/bv[height<=1080]+ba/b/bv+ba", "--format-sort", "vcodec:h264,acodec:m4a",
                "--", f"https://www.youtube.com/watch?v={key}"], capture_output=True, text=True, timeout=60)
        except (OSError, subprocess.TimeoutExpired):
            raise TrailerError("The trailer source did not respond. Try another trailer.")
        finally:
            self._resolvers.release()
        if result.returncode:
            if "Sign in" in result.stderr or "confirm" in result.stderr:
                raise TrailerError("YouTube requires verification for this trailer. Choose another trailer.")
            raise TrailerError("A playable stream is not available for this trailer. Choose another trailer.")
        try:
            info = json.loads(result.stdout)
            tracks = info.get("requested_formats") or [info]
            tracks = [track for track in tracks if track.get("url")]
            video = next(track for track in tracks if track.get("vcodec") not in (None, "none"))
            audio = next((track for track in tracks if track.get("vcodec") == "none" and track.get("acodec") not in (None, "none")), None)
            headers = {k: str(v) for k, v in info.get("http_headers", {}).items()
                       if k.lower() in ("user-agent", "referer", "origin", "accept", "accept-language")}
            token = self.register(video["url"], headers)
            audio_resource = self.resource(token, audio["url"]) if audio else None
            # "uk,en": the first language whose subtitles can actually be had.
            # YouTube often refuses its auto-translated captions (HTTP 429)
            # while the uploader's own ones work - hence a fallback.
            subtitle_text = subtitle_language = None
            languages = subtitles.split(",") if isinstance(subtitles, str) else []
            for language in languages[:3]:
                if not re.fullmatch(r"[a-z]{2,3}", language):
                    continue
                subtitle_url = pick_subtitles(info, language)
                subtitle_text = self.fetch_subtitles(subtitle_url, headers) if subtitle_url else None
                if subtitle_text:
                    subtitle_language = language
                    with self._lock:
                        if token in self._items:
                            self._items[token]["subtitles"] = subtitle_text
                    break
            return {"url": f"/trailer-stream/{token}/0", "audio_url": f"/trailer-stream/{token}/{audio_resource}" if audio else None,
                    "subtitle_url": f"/trailer-stream/{token}/subtitles.vtt" if subtitle_text else None,
                    "subtitle_language": subtitle_language,
                    "title": info.get("title") or "Trailer", "expires_after": self.ttl}
        except (ValueError, TypeError, StopIteration, KeyError):
            raise TrailerError("The trailer source returned no playable video")

    def register(self, url, headers=None):
        if not allowed_url(url):
            raise TrailerError("The trailer source returned an unsupported URL")
        with self._lock:
            self._expire()
            if len(self._items) >= 64:
                raise TrailerError("Too many trailers are open. Try again later.", 429)
            token = secrets.token_urlsafe(32)
            self._items[token] = {"urls": [url], "headers": headers or {}, "expires": self.clock() + self.ttl}
            return token

    def resource(self, token, url):
        if not allowed_url(url):
            raise TrailerError("The trailer playlist returned an unsupported URL")
        with self._lock:
            self._expire()
            item = self._items.get(token)
            if not item:
                raise TrailerError("The trailer link expired. Open the trailer again.", 410)
            if url in item["urls"]:
                return item["urls"].index(url)
            if len(item["urls"]) >= 4096:
                raise TrailerError("The trailer playlist is too large")
            item["urls"].append(url)
            return len(item["urls"]) - 1

    def lookup(self, token, index):
        with self._lock:
            self._expire()
            item = self._items.get(token)
            if not item:
                raise TrailerError("The trailer link expired. Open the trailer again.", 410)
            if not 0 <= index < len(item["urls"]):
                raise TrailerError("Unknown trailer resource", 404)
            return item["urls"][index], dict(item["headers"])

    def rewrite_manifest(self, token, base, manifest):
        def target(uri):
            return str(self.resource(token, urllib.parse.urljoin(base, uri)))
        lines = []
        for line in manifest.splitlines():
            if line.startswith("#"):
                line = re.sub(r'URI="([^\"]+)"', lambda m: f'URI="{target(m.group(1))}"', line)
            elif line.strip():
                line = target(line.strip())
            lines.append(line)
        return "\n".join(lines) + "\n"

    def relay(self, token, index, range_header=None, head=False):
        url, headers = self.lookup(token, index)
        if range_header:
            if not re.fullmatch(r"bytes=(?:\d+-\d*|-\d+)", range_header):
                raise TrailerError("Unsupported trailer range", 416)
            headers["Range"] = range_header
        request = urllib.request.Request(url, headers=headers, method="HEAD" if head else "GET")
        try:
            return urllib.request.build_opener(SafeRedirect()).open(request, timeout=20)
        except urllib.error.HTTPError as error:
            error.close()
            raise TrailerError("The trailer source rejected playback. Open the trailer again.")
        except (urllib.error.URLError, TimeoutError, OSError):
            raise TrailerError("The trailer source is unavailable. Try again later.")
