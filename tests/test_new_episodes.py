"""Download new episodes: what is missing, which release to take, where the
file goes, the 30-minute timer - and one full run against the real server
with a mocked tracker search."""
import io
import os
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

_sandbox = tempfile.TemporaryDirectory(prefix="torrenttube-new-episodes-test-")
os.environ.setdefault("TORRENTTUBE_DOWNLOAD_DIR", _sandbox.name)
os.environ.setdefault("TORRENTTUBE_STATE_DIR", str(Path(_sandbox.name) / "state"))
import app as server
import languages
import new_episodes as ne

FOLDER = "The Show (Season 2) WEB-DL 1080p [Ukr,Eng] [Hurtom]"


def disk_files(folder="TV Shows/" + FOLDER, season=2, last=4, sub=""):
    return [{"name": f"The.Show.S{season:02d}E{e:02d}.1080p.WEB-DL.mkv",
             "path": f"{folder}/{sub}The.Show.S{season:02d}E{e:02d}.1080p.WEB-DL.mkv",
             "season": season, "episode": e, "last_episode": e} for e in range(1, last + 1)]


def result(title, seeders=10, size=1000, **extra):
    return {"title": title, "size": size, "seeders": seeders, "magnet": "", "download_link": f"http://x/{title}", **extra}


class GapTests(unittest.TestCase):
    def test_newest_episode_on_disk(self):
        files = disk_files() + [{"name": "S01E01-E03.mkv", "path": "x", "season": 1, "episode": 1, "last_episode": 3}]
        self.assertEqual(ne.newest(files), (2, 4))
        self.assertIn((1, 2), ne.episodes_on_disk(files))
        self.assertIsNone(ne.newest([{"name": "extras.mkv", "path": "x"}]))

    def test_only_the_episodes_after_the_newest_are_wanted(self):
        pack = [f"The Show S02/The.Show.S02E{e:02d}.mkv" for e in range(1, 7)] + ["The Show S02/sample.S02E05.mkv",
                                                                                   "The Show S02/notes.txt"]
        picks = ne.wanted(pack, (2, 4), ne.episodes_on_disk(disk_files()))
        self.assertEqual([(s, e) for _, s, e, _ in picks], [(2, 5), (2, 6)])
        self.assertEqual(picks[0][0], 4)  # the index in the torrent

    def test_already_fetched_episodes_are_skipped(self):
        pack = [f"The.Show.S02E{e:02d}.mkv" for e in range(4, 7)]
        picks = ne.wanted(pack, (2, 4), {(2, 4), (2, 5)})
        self.assertEqual([(s, e) for _, s, e, _ in picks], [(2, 6)])

    def test_the_next_season_counts_but_not_one_after_it(self):
        pack = ["S03/The.Show.S03E01.mkv", "S04/The.Show.S04E01.mkv", "S01/The.Show.S01E09.mkv"]
        self.assertEqual([(s, e) for _, s, e, _ in ne.wanted(pack, (2, 10))], [(3, 1)])

    def test_files_without_a_season_take_the_one_the_title_names(self):
        pack = ["Шоу/05 Назва.mkv", "Шоу/04 Назва.mkv"]
        self.assertEqual(ne.wanted(pack, (2, 4)), [])
        self.assertEqual([(s, e) for _, s, e, _ in ne.wanted(pack, (2, 4), season_hint=2)], [(2, 5)])

    def test_tracker_titles_that_cannot_have_anything_newer(self):
        self.assertFalse(ne.could_have("The Show S01 1080p", (2, 4)))
        self.assertFalse(ne.could_have("Шоу (Сезон 2, серії 1-4 з 10) [Hurtom]", (2, 4)))
        self.assertFalse(ne.could_have("The Show S02E01-04 1080p", (2, 4)))
        self.assertFalse(ne.could_have("The Show S05 1080p", (2, 4)))
        self.assertTrue(ne.could_have("Шоу (Сезон 2, серії 1-5 з 10) [Hurtom]", (2, 4)))
        self.assertTrue(ne.could_have("The Show S02E05 1080p", (2, 4)))
        self.assertTrue(ne.could_have("The Show Season 3", (2, 10)))
        self.assertTrue(ne.could_have("The Show S01-S03 Complete", (2, 10)))
        self.assertTrue(ne.could_have("The Show 1080p", (2, 4)))  # says nothing: open it


class ReleaseMatchTests(unittest.TestCase):
    def test_tags_from_a_ukrainian_release_name(self):
        tags = ne.release_tags("Шоу (Сезон 2) WEB-DL 1080p H.265 [Ukr,Eng] [5 з 10] [Hurtom]")
        self.assertEqual(tags, {"group": "hurtom", "resolution": "1080p", "source": "web-dl", "codec": "hevc",
                                "languages": {"uk", "en"}})

    def test_tags_from_a_scene_file_name(self):
        tags = ne.release_tags("The.Show.S02E04.2160p.WEBRip.x264-NTb.mkv")
        self.assertEqual((tags["group"], tags["resolution"], tags["source"], tags["codec"]), ("ntb", "2160p", "webrip", "avc"))
        self.assertIsNone(ne.release_tags("The.Show.S02E04.1080p.WEB-DL.mkv")["group"])

    def test_profile_takes_the_most_common_values(self):
        disk = ne.profile([FOLDER, *(f["name"] for f in disk_files())])
        self.assertEqual((disk["group"], disk["resolution"], disk["source"]), ("hurtom", "1080p", "web-dl"))
        self.assertEqual(disk["languages"], {"uk", "en"})

    def test_show_names_come_from_every_part_of_the_name(self):
        self.assertEqual(ne.show_names("Шоу / The Show (Сезон 2) WEB-DL [Hurtom]"), {"шоу", "the show"})
        self.assertEqual(ne.show_names(FOLDER), {"the show"})
        self.assertTrue(ne.show_names("The.Show.S02E05.1080p.WEB-DL") & {"the show"})

    def test_same_group_and_resolution_win_and_other_shows_are_dropped(self):
        disk = ne.profile([FOLDER])
        results = [
            result("Шоу / The Show (Сезон 2, серії 1-5) WEB-DL 720p [Ukr] [Toloka]", seeders=90),
            result("Шоу / The Show (Сезон 2, серії 1-5) WEB-DL 1080p [Ukr,Eng] [Hurtom]", seeders=3),
            result("Шоу / The Show (Сезон 2, серії 1-5) WEB-DL 1080p [Ukr] [Toloka]", seeders=40),
            result("Інше шоу / Other Show (Сезон 2) WEB-DL 1080p [Ukr] [Hurtom]", seeders=50),
            result("The Show (Season 2) 1080p [Ukr] [Hurtom]", seeders=0),
        ]
        ordered = ne.candidates(results, ne.show_names(FOLDER), (2, 4), disk, languages.preference("uk"))
        self.assertEqual([r["title"] for _, r in ordered], [results[1]["title"], results[2]["title"], results[0]["title"]])

    def test_english_releases_only_after_every_ukrainian_one(self):
        disk = ne.profile([FOLDER])
        results = [result("The Show S02E05 1080p WEB-DL [Eng] [Hurtom]", seeders=99),
                   result("Шоу (Сезон 2, серії 1-5) 720p", seeders=1)]  # Ukrainian title, no tags
        ordered = ne.candidates(results, ne.show_names(FOLDER) | {"шоу"}, (2, 4), disk, languages.preference("uk"))
        self.assertEqual([lang for lang, _ in ordered], ["uk", "en"])
        ordered = ne.candidates(results, ne.show_names(FOLDER) | {"шоу"}, (2, 4), disk, languages.preference("en"))
        self.assertEqual([lang for lang, _ in ordered], ["en"])

    def test_untagged_titles_take_their_indexer_language(self):
        self.assertEqual(ne.release_languages({"title": "The Show S02E05", "language": "pl"}), {"pl"})
        self.assertEqual(ne.release_languages({"title": "The Show S02E05 [Ukr]", "language": "pl"}), {"uk"})


class PlaceTests(unittest.TestCase):
    def test_a_new_episode_goes_next_to_the_newest_one(self):
        show = {"files": disk_files(), "folders": ["TV Shows/" + FOLDER]}
        targets = ne.place(show, ["Pack/The.Show.S02E05.mkv"], [(0, 2, 5, 5)])
        self.assertEqual(targets, [(0, f"TV Shows/{FOLDER}/The.Show.S02E05.mkv")])

    def test_a_new_season_gets_a_folder_named_like_the_last(self):
        show = {"files": disk_files(last=10), "folders": ["TV Shows/" + FOLDER]}
        targets = ne.place(show, ["S03/The.Show.S03E01.mkv"], [(0, 3, 1, 1)])
        self.assertEqual(targets, [(0, "TV Shows/The Show (Season 3) WEB-DL 1080p [Ukr,Eng] [Hurtom]/The.Show.S03E01.mkv")])

    def test_season_subfolders_get_a_new_sibling(self):
        show = {"files": disk_files(folder="TV Shows/The Show", sub="Season 02/", last=10), "folders": ["TV Shows/The Show"]}
        targets = ne.place(show, ["The.Show.S03E01.mkv"], [(0, 3, 1, 1)])
        self.assertEqual(targets, [(0, "TV Shows/The Show/Season 03/The.Show.S03E01.mkv")])


class WorkerTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.now = [100000.0]
        self.enabled = [True]
        self.downloads = []
        self.opened = []
        self.results = [
            result("Шоу / The Show (Сезон 2, серії 1-5 з 10) WEB-DL 1080p [Ukr,Eng] [Hurtom]"),
            result("Шоу / The Show (Сезон 2, серії 1-5 з 10) WEB-DL 720p [Ukr] [Toloka]", seeders=80),
        ]
        self.worker = self.make()

    def make(self):
        return ne.NewEpisodes(
            Path(self.folder.name) / "new-episodes.json",
            shows=lambda: [{"key": "tmdb:tv:1", "title": "The Show", "names": [FOLDER], "queries": ["The Show"],
                            "folders": ["TV Shows/" + FOLDER], "files": disk_files()}],
            search=lambda query: self.results,
            inspect=self.inspect, download=lambda torrent, targets: self.downloads.append((torrent["hash"], targets)),
            enabled=lambda: self.enabled[0], audio_language=lambda: "uk", clock=lambda: self.now[0])

    def inspect(self, r):
        self.opened.append(r["title"])
        return {"hash": "h-" + r["title"][-8:], "files": [f"Pack/The.Show.S02E{e:02d}.mkv" for e in range(1, 6)]}

    def tearDown(self):
        self.folder.cleanup()

    def test_downloads_only_the_missing_episode_from_the_matching_release(self):
        started = self.worker.run()
        self.assertEqual(started, [("tmdb:tv:1", "S02E05")])
        self.assertEqual(self.opened, [self.results[0]["title"]])
        self.assertEqual(self.downloads, [("h-[Hurtom]", [(4, f"TV Shows/{FOLDER}/The.Show.S02E05.mkv")])])
        self.assertEqual(self.worker.status()["recent"][0]["episodes"], ["S02E05"])

    def test_an_episode_is_never_fetched_twice(self):
        self.worker.run()
        self.now[0] += ne.INTERVAL
        again = self.make()  # the state file survives a restart
        self.assertEqual(again.run(), [])
        self.assertEqual(len(self.downloads), 1)

    def test_a_torrent_with_nothing_new_is_not_opened_again_for_a_day(self):
        self.results = self.results[:1]
        self.inspect = lambda r: (self.opened.append(r["title"]), {"hash": "x", "files": ["The.Show.S02E04.mkv"]})[1]
        self.worker = self.make()
        self.worker.run()
        self.worker.run()
        self.assertEqual(len(self.opened), 1)
        self.now[0] += ne.TRIED_FOR + 1
        self.worker.run()
        self.assertEqual(len(self.opened), 2)

    def test_runs_every_30_minutes_only_while_on(self):
        self.enabled[0] = False
        self.assertFalse(self.worker.due())
        self.enabled[0] = True
        self.assertTrue(self.worker.due())  # never checked: at once
        self.worker.run()
        self.now[0] += ne.INTERVAL - 1
        self.assertFalse(self.worker.due())
        self.now[0] += 1
        self.assertTrue(self.worker.due())
        self.enabled[0] = False
        self.assertFalse(self.worker.due())


class ServerRunTests(unittest.TestCase):
    """The real server: a show in the library, a mocked tracker search and
    .torrent - only the new episode starts downloading, into the show folder."""

    def setUp(self):
        server.ses.apply_settings({"enable_dht": False, "enable_lsd": False, "enable_upnp": False, "enable_natpmp": False})
        self.show = server.DOWNLOAD_DIR / "TV Shows" / "The Show (Season 2) WEB-DL 1080p [Ukr,Eng] [Hurtom]"
        self.show.mkdir(parents=True)
        for e in range(1, 5):
            (self.show / f"The.Show.S02E{e:02d}.1080p.WEB-DL.mkv").write_bytes(b"v" * 100)
        self.source = tempfile.TemporaryDirectory()
        fs = server.lt.file_storage()
        Path(self.source.name, "Pack").mkdir()
        for e in range(1, 6):
            Path(self.source.name, "Pack", f"The.Show.S02E{e:02d}.mkv").write_bytes(bytes([e]) * 20000)
            fs.add_file(f"Pack/The.Show.S02E{e:02d}.mkv", 20000)
        torrent = server.lt.create_torrent(fs, 16384, flags=server.lt.create_torrent.v1_only)
        server.lt.set_piece_hashes(torrent, self.source.name)
        self.torrent = server.lt.bencode(torrent.generate())
        self.tid = None
        self.saved = dict(server.SETTINGS)
        server.NEW_EPISODES.state = {"fetched": {}, "tried": {}, "last_check": None, "recent": []}

    def tearDown(self):
        handle = server.HANDLES.pop(self.tid, None) if self.tid else None
        if handle:
            server.ses.remove_torrent(handle)
        server.RENAMED_FILES.pop(self.tid, None)
        server.SETTINGS.update(self.saved)
        shutil.rmtree(self.show.parent, ignore_errors=True)
        self.source.cleanup()
        server.LIBRARY.items(refresh=True)

    def test_one_run_downloads_only_the_new_episode(self):
        results = [{"title": "The Show (Season 2, Episodes 1-5) WEB-DL 1080p [Ukr,Eng] [Hurtom]", "size": 100000,
                    "seeders": 5, "magnet": "", "download_link": "http://jackett/dl/1", "indexer": "toloka"}]
        server.SETTINGS["download_new_episodes"] = 1
        with patch.object(server, "JACKETT_URL", "http://jackett"), patch.object(server, "JACKETT_API_KEY", "k"), \
                patch.object(server, "jackett_query", return_value=results) as search, \
                patch.object(server, "indexer_languages", return_value={"toloka": "uk"}), \
                patch.object(server.urllib.request, "urlopen", return_value=io.BytesIO(self.torrent)):
            self.assertTrue(server.NEW_EPISODES.due())
            started = server.NEW_EPISODES.run()
        search.assert_called_with(q="The Show")
        self.assertEqual(len(started), 1)
        self.assertTrue(started[0][1] == "S02E05")
        self.tid = next(t for t, paths in server.RENAMED_FILES.items() if 4 in paths)
        handle = server.HANDLES[self.tid]
        self.assertEqual(list(handle.get_file_priorities()), [0, 0, 0, 0, 4])
        self.assertEqual(handle.status().save_path, str(server.DOWNLOAD_DIR / "TV Shows"))
        self.assertEqual(server.RENAMED_FILES[self.tid], {4: f"{self.show.name}/The.Show.S02E05.mkv"})
        self.assertFalse(server.NEW_EPISODES.due())

    def test_library_settings_are_shared_and_saved(self):
        client = server.app.test_client()
        with patch.object(server.NEW_EPISODES, "wake") as wake:  # no real check in the background
            response = client.post("/api/library/settings", json={"download_new_episodes": True, "audio_language": "en"})
        wake.assert_called_once()
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json["download_new_episodes"])
        self.assertEqual(response.json["audio_language"], "en")
        self.assertEqual([c["code"] for c in response.json["audio_languages"]][:2], ["uk", "en"])
        self.assertEqual(client.get("/api/config").json["audio_language"], "en")
        self.assertIn('"audio_language": "en"', server.SETTINGS_FILE.read_text())
        self.assertEqual(client.post("/api/library/settings", json={"audio_language": "xx"}).status_code, 400)
        self.assertNotIn("jackett_api_key", client.get("/api/library/settings").json)

    def test_languages_from_the_library_are_offered(self):
        server.LIBRARY_LANGUAGES["at"] = 0
        polish = server.DOWNLOAD_DIR / "TV Shows" / "Serial (Season 1) [Pol]"
        polish.mkdir(parents=True)
        (polish / "Serial.S01E01.mkv").write_bytes(b"v")
        server.LIBRARY.items(refresh=True)
        with patch.object(server, "indexer_languages", return_value={"x": "de"}):
            codes = [c["code"] for c in server.library_audio_languages()]
        self.assertEqual(codes[:2], ["uk", "en"])
        self.assertIn("pl", codes)
        self.assertIn("de", codes)


class LanguageTests(unittest.TestCase):
    def test_ukrainian_falls_back_to_english(self):
        self.assertEqual(languages.preference("uk"), ["uk", "en"])
        self.assertEqual(languages.preference("en"), ["en"])
        self.assertEqual(languages.preference("pl"), ["pl", "en"])
        self.assertEqual(languages.vlc_option("uk"), "ukr,eng")

    def test_tags_are_whole_words(self):
        self.assertEqual(languages.found_in("[Ukr, Eng] | Sub Pol"), {"uk", "en", "pl"})
        self.assertEqual(languages.found_in("Українська, англійська"), {"uk", "en"})
        self.assertEqual(languages.found_in("Engine Ukraine-ready"), set())


if __name__ == "__main__":
    unittest.main()
