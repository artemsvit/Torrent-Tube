"""Torrent search: Jackett's Torznab feed parsed into results."""
import io
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

_sandbox = tempfile.TemporaryDirectory(prefix="torrenttube-search-test-")
os.environ.setdefault("TORRENTTUBE_DOWNLOAD_DIR", _sandbox.name)
os.environ.setdefault("TORRENTTUBE_STATE_DIR", str(Path(_sandbox.name) / "state"))
import app as server

FEED = b"""<?xml version="1.0"?>
<rss xmlns:torznab="http://torznab.com/schemas/2015/feed"><channel>
<item><title>Friends S01 1080p</title><size>2048</size><link>http://x/dl</link>
<torznab:attr name="seeders" value="42"/><torznab:attr name="peers" value="50"/>
<torznab:attr name="magneturl" value="magnet:?xt=urn:btih:abc"/></item>
</channel></rss>"""


class SearchTests(unittest.TestCase):
    def test_torznab_attributes_are_read(self):
        with patch.object(server.urllib.request, "urlopen", return_value=io.BytesIO(FEED)):
            results = server.jackett_query(q="Friends")
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0]["seeders"], 42)
        self.assertEqual(results[0]["peers"], 50)
        self.assertEqual(results[0]["magnet"], "magnet:?xt=urn:btih:abc")


if __name__ == "__main__":
    unittest.main()
