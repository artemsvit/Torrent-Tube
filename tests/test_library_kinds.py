"""TMDB candidate choice and the Library tab (film, show, cartoon) of each title."""
import os
import tempfile
import unittest
from pathlib import Path

_sandbox = tempfile.TemporaryDirectory(prefix="torrenttube-kinds-test-")
os.environ.setdefault("TORRENTTUBE_DOWNLOAD_DIR", _sandbox.name)
os.environ.setdefault("TORRENTTUBE_STATE_DIR", str(Path(_sandbox.name) / "state"))
import app as server


def film(title, year, votes=1000, original=None):
    return {"media_type": "movie", "title": title, "original_title": original or title, "release_date": f"{year}-05-01", "vote_count": votes}


def show(name, year, votes=1000, original=None):
    return {"media_type": "tv", "name": name, "original_name": original or name, "first_air_date": f"{year}-01-01", "vote_count": votes}


class PickTests(unittest.TestCase):
    def test_year_beats_a_same_named_show_listed_first(self):
        results = [show("Ніхто цього не хоче", 2024, 900, "Nobody Wants This"), film("Ніхто", 2021, 4000, "Nobody")]
        item, confident = server._tmdb_pick(results, "Nobody", "2021", "movie")
        self.assertEqual(item["original_title"], "Nobody")
        self.assertTrue(confident)

    def test_film_over_show_with_same_name(self):
        results = [show("Червоні очі", 2005, 20, "Red Eye"), film("Нічний рейс", 2005, 3000, "Red Eye")]
        item, _ = server._tmdb_pick(results, "Red Eye", "2005", "movie")
        self.assertEqual(item["media_type"], "movie")

    def test_a_folder_of_episodes_finds_the_show(self):
        results = [film("House M.D.: The Doctor Director", 2009, 10, "House M.D.: The Doctor Director"), show("Доктор Хаус", 2004, 6000, "House")]
        item, _ = server._tmdb_pick(results, "House M D", None, "tv")
        self.assertEqual(item["media_type"], "tv")

    def test_unrelated_first_result_is_not_confident(self):
        results = [film("Something Else", 1990, 50)]
        _, confident = server._tmdb_pick(results, "Pocahontas Dilogy", None, "movie")
        self.assertFalse(confident)


class StructureTests(unittest.TestCase):
    def item(self, name, files, episodes=0):
        return {"name": name, "files": files, "episodes": episodes}

    def test_episodes_make_a_show(self):
        self.assertEqual(server.library_structure(self.item("House", 2, episodes=2)), "tv")
        # The folder names a season, even when the files are not read as episodes.
        self.assertEqual(server.library_structure(self.item("Патрік Мелроуз (Сезон 1)", 5)), "tv")

    def test_one_file_or_a_film_collection_is_a_film(self):
        self.assertEqual(server.library_structure(self.item("Heat (1995)", 1)), "movie")
        # "1. Aladdin (1992)": numbered like episodes, but no season - films.
        self.assertEqual(server.library_structure(self.item("Aladdin. Trilogy (1992-1996)", 3)), "movie")
        self.assertEqual(server.library_structure(self.item("Show S01", 1, episodes=1)), "movie")


class LibraryScanEpisodeTests(unittest.TestCase):
    """The scan counts episodes with episodes.py - the reading the apps use."""

    def scan(self, folder, names):
        root = Path(tempfile.mkdtemp())
        for name in names:
            path = root / "Cartoon" / folder / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"v")
        from media_library import MediaLibrary
        return MediaLibrary(root, ["Cartoon"], server.VIDEO_EXTS).items()[0]

    def test_a_numbered_film_collection_has_no_episodes(self):
        item = self.scan("Aladdin. Trilogy (1992-1996)", ["1. Aladdin (1992).mkv", "2. Aladdin 2. Return of Jafar (1994).mkv"])
        self.assertEqual((item["episodes"], item["seasons"]), (0, 0))
        self.assertEqual(server.library_structure(item), "movie")

    def test_cyrillic_and_double_episode_files_are_episodes(self):
        item = self.scan("Bluey", ["1-1-2 Ксилофон & Лікарня.mp4", "1-3-4 Підкидайки.mp4", "Гільда С02Е01.mkv"])
        self.assertEqual((item["episodes"], item["seasons"]), (3, 2))
        self.assertEqual(server.library_structure(item), "tv")


class StaleMatchTests(unittest.TestCase):
    def test_a_match_saved_as_the_wrong_structure_is_looked_up_again(self):
        item = {"id": "Cartoon/Aladdin. Trilogy (1992-1996)", "name": "Aladdin. Trilogy (1992-1996)", "files": 3,
                "episodes": 0, "seasons": 0, "kind": "cartoon", "size": 3, "category": "Cartoon", "added": 1}
        saved = {"checked": 1e12, "structure": "tv", "tmdb_id": 2745, "media_type": "tv", "confident": True}
        submitted = []
        original = (server.LIBRARY_META.get(item["id"]), server.TMDB_API_KEY, server.TMDB_EXECUTOR.submit)
        try:
            server.LIBRARY_META[item["id"]] = saved
            server.TMDB_API_KEY = "key"
            server.TMDB_EXECUTOR.submit = lambda fn, arg: submitted.append(arg["id"])
            server._library_with_metadata([item])
            self.assertEqual(submitted, [item["id"]])
        finally:
            if original[0] is None:
                server.LIBRARY_META.pop(item["id"], None)
            else:
                server.LIBRARY_META[item["id"]] = original[0]
            server.TMDB_API_KEY = original[1]
            server.TMDB_EXECUTOR.submit = original[2]
            server.LIBRARY_META_PENDING.discard(item["id"])


class ClassifyTests(unittest.TestCase):
    def test_confident_animation_is_a_cartoon_wherever_it_is(self):
        self.assertEqual(server.classify_library_item("movie", "movie", {"confident": True, "animation": True}), "cartoon")

    def test_live_action_in_the_cartoon_folder_moves_to_films(self):
        self.assertEqual(server.classify_library_item("cartoon", "movie", {"confident": True, "animation": False, "votes": 3000}), "movie")

    def test_an_obscure_match_does_not_move_a_title_out_of_cartoons(self):
        self.assertEqual(server.classify_library_item("cartoon", "movie", {"confident": True, "animation": False, "votes": 3}), "cartoon")

    def test_without_a_confident_match_the_folder_decides(self):
        self.assertEqual(server.classify_library_item("cartoon", "movie", {"confident": False, "animation": False}), "cartoon")
        self.assertEqual(server.classify_library_item("movie", "movie", None), "movie")
        self.assertEqual(server.classify_library_item("movie", "tv", None), "tv")


class MergeTests(unittest.TestCase):
    def item(self, path, files, kind="movie", folder="movie", tmdb=7, added=1):
        return {"id": path, "name": path.split("/")[-1], "files": files, "size": files * 10, "category": path.split("/")[0],
                "kind": kind, "folder_kind": folder, "added": added, "tmdb_id": tmdb, "media_type": "movie"}

    def test_copies_of_one_title_become_one_card_with_versions(self):
        items = [self.item("Cartoon/Film.mkv", 1, folder="cartoon"), self.item("Movies/Film.mkv", 1, added=5),
                 self.item("Movies/Other.mkv", 1, tmdb=8)]
        merged = server._merge_library_versions(items)
        self.assertEqual(len(merged), 2)
        film = merged[0]
        self.assertEqual(film["id"], "Movies/Film.mkv", "the copy in the right folder plays by default")
        self.assertEqual([v["id"] for v in film["versions"]], ["Movies/Film.mkv", "Cartoon/Film.mkv"])
        self.assertNotIn("versions", merged[1])

    def test_titles_without_a_match_are_never_merged(self):
        items = [self.item("Movies/A.mkv", 1, tmdb=None), self.item("Movies/B.mkv", 1, tmdb=None)]
        self.assertEqual(len(server._merge_library_versions(items)), 2)


if __name__ == "__main__":
    unittest.main()
