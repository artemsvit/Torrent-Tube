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
        self.assertRegex(page, r'<body\b[^>]*class="has-title-page"')
        details = page.split('<main class="title-page is-open"')[1].split('</main>')[0]
        self.assertNotIn('role="dialog"', details)
        self.assertIn('Loading title…', details)
        self.assertNotIn('dt-topbar', details)
        self.assertNotIn('id="detailsClose"', page)
        self.assertIn('class="logo-mark header-back" id="detailsBack"', page)

    def test_person_links_render_the_same_page_shell(self):
        page = server.app.test_client().get("/?person=2524&name=Tom+Hardy").get_data(as_text=True)
        self.assertRegex(page, r'<body\b[^>]*class="has-title-page"')
        self.assertIn('<main class="title-page is-open"', page)

    @unittest.skipUnless(shutil.which("node"), "Node is required for the browser-helper checks")
    def test_catalog_sources_and_header(self):
        result = subprocess.run([shutil.which("node"), str(Path(__file__).with_name("web_catalog.js"))], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    @unittest.skipUnless(shutil.which("node"), "Node is required for the browser-helper checks")
    def test_server_home_history(self):
        result = subprocess.run([shutil.which("node"), str(Path(__file__).with_name("web_server_home.js"))], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    @unittest.skipUnless(shutil.which("node"), "Node is required for the browser-helper checks")
    def test_library_player_links(self):
        result = subprocess.run([shutil.which("node"), str(Path(__file__).with_name("web_library_playback.js"))], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    @unittest.skipUnless(shutil.which("node"), "Node is required for the browser-helper checks")
    def test_seasons_sources_and_download_workflow(self):
        result = subprocess.run([shutil.which("node"), str(Path(__file__).with_name("web_title_page.js"))], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
