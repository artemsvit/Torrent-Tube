"""episodes.py: the season and episode of a file, as the apps and the web use them.
The names are real ones from the library."""
import unittest

from episodes import identify


def ep(season, episode, last=None):
    return {"season": season, "episode": episode, "last_episode": last or episode}


class EpisodeNames(unittest.TestCase):
    def check(self, cases):
        for name, path, expected in cases:
            with self.subTest(name=name):
                self.assertEqual(identify(name, path), expected)

    def test_season_and_episode_in_the_name(self):
        self.check([
            ("Breaking Bad.S01E01.Pilot.mkv", None, ep(1, 1)),
            ("The.Blacklist.s02e22.WEB-DLRip.Ukr.Eng.avi", None, ep(2, 22)),
            ("House M.D. S05.E03 (2008) BDRip 1080p.mkv", None, ep(5, 3)),
            ("S010E1.mp4", "TV Shows/Friends/Season 10/S010E1.mp4", ep(10, 1)),
            ("Пантеон - S02EP01 [1080p][Clan Kaizoku].mkv", None, ep(2, 1)),
            ("Гільда С01Е01.mkv", None, ep(1, 1)),          # Cyrillic С and Е
            ("Show 1x04.mp4", None, ep(1, 4)),
            ("Show Season 2 Episode 5.mkv", None, ep(2, 5)),
            ("Show.S02E03.1080p.mkv", None, ep(2, 3)),
            ("Show S01E05 4K.mkv", None, ep(1, 5)),
        ])

    def test_two_episodes_in_one_file(self):
        self.check([
            ("1-1-2 Чарівний ксилофон & Лікарня.mp4", None, ep(1, 1, 2)),
            ("1-51-52 Татків вечір & Санта з веранди.mp4", None, ep(1, 51, 52)),
            ("The Office US.S07E25E26.Search Committee (2011).mkv", None, ep(7, 25, 26)),
            ("Show.S01E01-E02.mkv", None, ep(1, 1, 2)),
            ("Show.S01E01-02.mkv", None, ep(1, 1, 2)),
            ("03-04 Combined.m4v", "Show/Season 12/03-04 Combined.m4v", ep(12, 3, 4)),
        ])

    def test_numbered_files_take_the_season_from_their_folders(self):
        self.check([
            ("01 Pilot (HD).m4v", "TV Shows/The Big Bang Theory/Season 1/01 Pilot (HD).m4v", ep(1, 1)),
            ("E03 Title.mkv", "Show/Сезон 2/E03 Title.mkv", ep(2, 3)),
            ("05 Name.mkv", "Cartoon/Show (Сезон 3)/05 Name.mkv", ep(3, 5)),
            ("Кармен Сандієґо - Серія 05 - Витівка.mkv", "Cartoon/Кармен Сандієго Сезон 1/Кармен Сандієґо - Серія 05 - Витівка.mkv", ep(1, 5)),
            ("Серія 03.mkv", "Cartoon/Show/Серія 03.mkv", ep(1, 3)),   # no season anywhere: season 1
        ])

    def test_films_collections_and_noise_are_not_episodes(self):
        self.check([
            ("[01] Toy Story (1995) BDRip 1080p H.265 [UKR_ENG] [Hurtom].mkv", "Cartoon/Toy Story. Collection (1995-2022)/[01] Toy Story (1995).mkv", None),
            ("01. Madagascar (2005) BDRip 1080p.mkv", "Cartoon/Madagascar. Collection (2005-2014)/01. Madagascar (2005).mkv", None),
            ("Shrek.2.2004.1080p.BluRay.mkv", "Cartoon/Shreck.Ouadrilogy.1080p/Shrek.2.2004.1080p.BluRay.mkv", None),
            ("Heat (1995).mkv", "Movies/Heat (1995).mkv", None),
            ("2019-01-02 Vlog.mp4", None, None),
            ("03 Title.m4v", "Show/03 Title.m4v", None),                  # a number but no season folder
            ("03-10 Not a range.m4v", "Show/Season 1/03-10 Not a range.m4v", None),
            ("1080p Episode.mkv", "Show/Season 1/1080p Episode.mkv", None),
            ("Columbo.s01e00.avi", None, None),                          # a pilot, not a numbered episode
        ])


if __name__ == "__main__":
    unittest.main()
