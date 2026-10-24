"""Release names -> the title and year TMDB is searched with."""
import os
import tempfile
import unittest
from pathlib import Path

_sandbox = tempfile.TemporaryDirectory(prefix="torrenttube-titles-test-")
os.environ.setdefault("TORRENTTUBE_DOWNLOAD_DIR", _sandbox.name)
os.environ.setdefault("TORRENTTUBE_STATE_DIR", str(Path(_sandbox.name) / "state"))
import app as server

CASES = {
    # scene-style file names in the library folders
    "IN.THE.GREY.2026.1080p.AMZN.WEB-DL": ("IN THE GREY", "2026"),
    "Yogi.Bear.2010.1080p.BluRay.DD5.1.x265-SPiLNO": ("Yogi Bear", "2010"),
    "A.Minecraft.Movie.2025.1080p.WEB.H264 ukr eng": ("A Minecraft Movie", "2025"),
    "Dune.Part.Two.2024.2160p.WEB-DL": ("Dune Part Two", "2024"),
    "Ada Twist Scientist S01-04": ("Ada Twist Scientist", None),
    "Stuart Fails to Save the Universe S01 2026 WEB-DL 1080p": ("Stuart Fails to Save the Universe", "2026"),
    "1. The Lion King (1994) BDRip 1080p H.265 [UKR_ENG]": ("The Lion King", "1994"),
    "[05] Fast Five (2011) BDRip 1080p H.265 [2xUKR_ENG] [Hurtom]": ("Fast Five", "2011"),
    "[01.2] Harry Potter and the Sorcerer's Stone (2001) [Ultimate Extended Edition] BDRip 1080p":
        ("Harry Potter and the Sorcerer's Stone", "2001"),
    # tracker listings keep working
    "Останні з нас / The Last of Us (2023) BDRip 1080p": ("The Last of Us", "2023"),
    "Fight Club (1999) [Open Matte] [Amazon] WEB-DL 1080p": ("Fight Club", "1999"),
    "Catch-22 (Season 1) (2019) WEB-DL 2160p [Ukr,Eng] [Hurtom]": ("Catch-22", "2019"),
    "The Accountant 2 2025 AMZN WEB-DL 1080p 2xUkr Eng": ("The Accountant 2", "2025"),
    "Кармен Сандієго Сезон 1": ("Кармен Сандієго", None),
    "Пантеон (Сезон 2) [1080p][Clan Kaizoku]": ("Пантеон", None),
    "s01 Pluribus": ("Pluribus", None),
    # a year that is part of the title stays in it
    "Blade Runner 2049 (2017) BDRip": ("Blade Runner 2049", "2017"),
    "1917 (2019) BDRip": ("1917", "2019"),
}


class TitleCleaningTests(unittest.TestCase):
    def test_release_names(self):
        for raw, (title, year) in CASES.items():
            found, _, found_year = server.extract_title_and_year(raw)
            self.assertEqual((found, found_year), (title, year), raw)


if __name__ == "__main__":
    unittest.main()
