"""Dedicated title-page structure and quick JavaScript workflow regressions."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

_sandbox = tempfile.TemporaryDirectory(prefix="torrenttube-title-page-test-")
os.environ.setdefault("TORRENTTUBE_DOWNLOAD_DIR", _sandbox.name)
os.environ.setdefault("TORRENTTUBE_STATE_DIR", str(Path(_sandbox.name) / "state"))
import app as server


class WebTitlePage(unittest.TestCase):
    def test_title_links_render_a_page_without_a_details_dialog(self):
        page = server.app.test_client().get("/?title=MobLand&type=tv&id=247718").get_data(as_text=True)
        self.assertIn('<body class="has-title-page">', page)
        details = page.split('<main class="title-page is-open"')[1].split('</main>')[0]
        self.assertNotIn('role="dialog"', details)
        self.assertIn('Loading title…', details)
        self.assertIn('Downloads &amp; storage', details)

    @unittest.skipUnless(shutil.which("node"), "Node is required for the browser-helper checks")
    def test_seasons_sources_and_download_workflow(self):
        result = subprocess.run([shutil.which("node"), str(Path(__file__).with_name("web_title_page.js"))], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
