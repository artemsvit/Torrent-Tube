import io
import json
import subprocess
import unittest
from unittest.mock import patch

from trailer_streams import TrailerError, TrailerStreams, allowed_url


class TrailerStreamTests(unittest.TestCase):
    def test_only_https_provider_urls_are_allowed(self):
        self.assertTrue(allowed_url("https://rr1.googlevideo.com/videoplayback?id=clip"))
        for url in ("http://rr1.googlevideo.com/file", "https://googlevideo.com.evil.test/file", "https://user@rr1.googlevideo.com/file", "http://127.0.0.1/file", "file:///tmp/file"):
            self.assertFalse(allowed_url(url))

    def test_manifests_preserve_proxy_prefix_with_relative_resources(self):
        streams = TrailerStreams()
        base = "https://rr1.googlevideo.com/path/index.m3u8"
        token = streams.register(base)
        playlist = '#EXTM3U\n#EXT-X-MAP:URI="init.mp4"\n#EXTINF:4,\nsegment.ts\n'
        result = streams.rewrite_manifest(token, base, playlist)
        self.assertIn('URI="1"', result)
        self.assertTrue(result.endswith("2\n"))
        self.assertEqual(streams.lookup(token, 2)[0], "https://rr1.googlevideo.com/path/segment.ts")
        with self.assertRaises(TrailerError):
            streams.rewrite_manifest(token, base, "#EXTM3U\nhttp://127.0.0.1/private\n")

    def test_tokens_expire(self):
        now = [0]
        streams = TrailerStreams(clock=lambda: now[0], ttl=10)
        token = streams.register("https://rr1.googlevideo.com/file")
        now[0] = 11
        with self.assertRaises(TrailerError) as result:
            streams.lookup(token, 0)
        self.assertEqual(result.exception.status, 410)

    @patch("trailer_streams.subprocess.run")
    @patch("trailer_streams.shutil.which", return_value="/tools/yt-dlp")
    def test_resolution_never_saves_media_and_returns_both_tracks(self, which, run):
        run.return_value = subprocess.CompletedProcess([], 0, json.dumps({"title": "Trailer", "requested_formats": [
            {"url": "https://rr1.googlevideo.com/video", "vcodec": "avc1", "acodec": "none"},
            {"url": "https://rr1.googlevideo.com/audio", "vcodec": "none", "acodec": "aac"}]}), "")
        result = TrailerStreams().resolve("abcdefghijk")
        self.assertIsNotNone(result["audio_url"])
        self.assertIn("--skip-download", run.call_args.args[0])
        self.assertIn("--ignore-config", run.call_args.args[0])
        self.assertEqual(run.call_args.kwargs["timeout"], 60)
        with self.assertRaises(TrailerError) as invalid:
            TrailerStreams().resolve("bad/input!")
        self.assertEqual(invalid.exception.status, 400)

    @patch("trailer_streams.subprocess.run")
    @patch("trailer_streams.shutil.which", return_value="/tools/yt-dlp")
    def test_provider_failure_has_clear_error_without_exposing_provider_output(self, which, run):
        run.return_value = subprocess.CompletedProcess([], 1, "", "Sign in to verify secret-provider-output")
        with self.assertRaises(TrailerError) as failure:
            TrailerStreams().resolve("abcdefghijk")
        self.assertIn("verification", str(failure.exception))
        self.assertNotIn("secret-provider-output", str(failure.exception))

    @patch("trailer_streams.subprocess.run")
    @patch("trailer_streams.shutil.which", return_value="/tools/yt-dlp")
    def test_ukrainian_subtitles_prefer_own_then_auto_translated(self, which, run):
        timedtext = "https://www.youtube.com/api/timedtext?v=abcdefghijk&lang=en&tlang=uk&fmt=vtt"
        info = {"title": "Trailer", "requested_formats": [{"url": "https://rr1.googlevideo.com/video", "vcodec": "avc1", "acodec": "aac"}],
                "automatic_captions": {"uk": [{"ext": "json3", "url": timedtext}, {"ext": "vtt", "url": timedtext}]}}
        run.return_value = subprocess.CompletedProcess([], 0, json.dumps(info), "")
        streams = TrailerStreams()
        with patch.object(streams, "fetch_subtitles", return_value="WEBVTT\n\n00:00.000 --> 00:01.000\nПривіт\n") as fetch:
            result = streams.resolve("abcdefghijk", "uk")
        fetch.assert_called_once_with(timedtext, {})
        token = result["url"].split("/")[2]
        self.assertEqual(result["subtitle_url"], f"/trailer-stream/{token}/subtitles.vtt")
        self.assertIn("Привіт", streams.subtitles(token))
        # Only YouTube's timedtext endpoint, and no subtitles unless asked for.
        info["automatic_captions"]["uk"] = [{"ext": "vtt", "url": "https://evil.test/api/timedtext"}]
        run.return_value = subprocess.CompletedProcess([], 0, json.dumps(info), "")
        self.assertIsNone(TrailerStreams().resolve("abcdefghijk", "uk")["subtitle_url"])
        self.assertIsNone(TrailerStreams().resolve("abcdefghijk")["subtitle_url"])

    @patch("trailer_streams.subprocess.run")
    @patch("trailer_streams.shutil.which", return_value="/tools/yt-dlp")
    def test_subtitles_fall_back_to_the_next_language(self, which, run):
        uk = "https://www.youtube.com/api/timedtext?v=abcdefghijk&lang=en&tlang=uk&fmt=vtt"
        en = "https://www.youtube.com/api/timedtext?v=abcdefghijk&lang=en&fmt=vtt"
        info = {"title": "Trailer", "requested_formats": [{"url": "https://rr1.googlevideo.com/video", "vcodec": "avc1", "acodec": "aac"}],
                "subtitles": {"en": [{"ext": "vtt", "url": en}]}, "automatic_captions": {"uk": [{"ext": "vtt", "url": uk}]}}
        run.return_value = subprocess.CompletedProcess([], 0, json.dumps(info), "")
        streams = TrailerStreams()
        # Ukrainian is refused (as YouTube does with HTTP 429), English works.
        with patch.object(streams, "fetch_subtitles", side_effect=lambda url, headers: None if url == uk else "WEBVTT\n") as fetch:
            result = streams.resolve("abcdefghijk", "uk,en")
        self.assertEqual([call.args[0] for call in fetch.call_args_list], [uk, en])
        self.assertEqual(result["subtitle_language"], "en")
        self.assertIsNotNone(result["subtitle_url"])

    @patch("trailer_streams.subprocess.run")
    @patch("trailer_streams.shutil.which", return_value="/tools/yt-dlp")
    def test_native_preview_uses_combined_mp4_and_renews_expired_links(self, which, run):
        run.return_value = subprocess.CompletedProcess([], 0, json.dumps({
            "title": "Trailer", "url": "https://rr1.googlevideo.com/preview", "ext": "mp4",
            "vcodec": "avc1.64001f", "acodec": "mp4a.40.2"}), "")
        now = [0]
        streams = TrailerStreams(clock=lambda: now[0], ttl=10)
        first = streams.preview("abcdefghijk")
        self.assertEqual(streams.preview("abcdefghijk"), first)
        self.assertEqual(run.call_count, 1)
        options = run.call_args.args[0]
        selected_format = options[options.index("--format") + 1]
        self.assertIn("ext=mp4", selected_format)
        self.assertTrue(selected_format.startswith("b[ext=mp4]"), "one MP4 first, HLS only as the fallback")
        now[0] = 9
        self.assertNotEqual(streams.preview("abcdefghijk"), first)
        self.assertEqual(run.call_count, 2)
        run.return_value = subprocess.CompletedProcess([], 0, json.dumps({
            "url": "https://rr1.googlevideo.com/video", "ext": "mp4", "vcodec": "avc1", "acodec": "none"}), "")
        with self.assertRaises(TrailerError):
            streams.resolve("abcdefghijk", preview=True)

    @patch("trailer_streams.subprocess.run")
    @patch("trailer_streams.shutil.which", return_value="/tools/yt-dlp")
    def test_preview_joins_hls_picture_and_sound(self, which, run):
        run.return_value = subprocess.CompletedProcess([], 0, json.dumps({"title": "Trailer", "requested_formats": [
            {"url": "https://manifest.googlevideo.com/video.m3u8", "protocol": "m3u8_native", "vcodec": "avc1.4D401F",
             "acodec": "none", "width": 1280, "height": 720, "tbr": 1383},
            {"url": "https://manifest.googlevideo.com/audio.m3u8", "protocol": "m3u8_native", "vcodec": "none", "acodec": None}]}), "")
        streams = TrailerStreams()
        url = streams.preview("abcdefghijk")
        self.assertRegex(url, r"^/trailer-stream/[\w-]+/master\.m3u8$")
        token = url.split("/")[2]
        playlist = streams.master_playlist(token)
        self.assertIn('TYPE=AUDIO,GROUP-ID="audio"', playlist)
        self.assertIn('URI="1"', playlist)
        self.assertIn("RESOLUTION=1280x720", playlist)
        self.assertTrue(playlist.rstrip().endswith("\n0"))
        self.assertEqual(streams.lookup(token, 1)[0], "https://manifest.googlevideo.com/audio.m3u8")

    def test_relay_forwards_range_to_provider(self):
        streams = TrailerStreams()
        token = streams.register("https://rr1.googlevideo.com/file", {"User-Agent": "TrailerPlayer"})
        with patch("trailer_streams.urllib.request.build_opener") as opener:
            streams.relay(token, 0, "bytes=20-39")
            request = opener.return_value.open.call_args.args[0]
            self.assertEqual(request.headers["Range"], "bytes=20-39")
            self.assertEqual(request.headers["User-agent"], "TrailerPlayer")
        with self.assertRaises(TrailerError):
            streams.relay(token, 0, "bytes=1-2,3-4")
