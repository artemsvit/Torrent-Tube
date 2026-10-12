"""The web page loads its stylesheet and script as versioned static files."""
import os
import re
import tempfile
import unittest
from pathlib import Path

_sandbox = tempfile.TemporaryDirectory(prefix="torrenttube-assets-test-")
os.environ.setdefault("TORRENTTUBE_DOWNLOAD_DIR", _sandbox.name)
os.environ.setdefault("TORRENTTUBE_STATE_DIR", str(Path(_sandbox.name) / "state"))
import app as server


class WebAssets(unittest.TestCase):
    def setUp(self):
        self.client = server.app.test_client()

    def test_page_links_versioned_assets_that_are_cached_for_a_year(self):
        page = self.client.get("/").get_data(as_text=True)
        for name in ("app.css", "app.js", "i18n.js", "server-home.css", "server-home.js"):
            match = re.search(rf'/static/{re.escape(name)}\?v=([0-9a-f]{{12}})', page)
            self.assertIsNotNone(match, name)
            response = self.client.get(match.group(0))
            self.assertEqual(response.status_code, 200)
            self.assertIn("immutable", response.headers["Cache-Control"])
            self.assertGreater(len(response.data), 10000)
            response.close()

    def test_theme_script_stays_in_the_head(self):
        # It sets the theme before the stylesheet paints, so there is no flash.
        head = self.client.get("/").get_data(as_text=True).split("</head>")[0]
        self.assertIn("torrenttube-theme", head)
        self.assertIn("torrenttube-language", head)
        self.assertIn("var language = 'uk'", head)

    def test_unversioned_static_files_are_not_cached_for_long(self):
        response = self.client.get("/static/favicon.svg")
        self.assertNotIn("immutable", response.headers.get("Cache-Control", ""))
        response.close()


if __name__ == "__main__":
    unittest.main()
