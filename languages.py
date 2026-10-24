"""Audio languages: the "Default audio track" choices, how a release or a
file names each one ("[Ukr, Eng]", "Ukr/Eng", "Українська"), and the codes
VLC picks a track by. Ukrainian first, English second (the fallback)."""
import re

_EDGE = r"(?<![a-zа-яіїєґё])"
_END = r"(?![a-zа-яіїєґё])"

# code, own name, ISO 639-2 codes for VLC, how names and tags write it.
_TABLE = [
    ("uk", "Українська", ("ukr",), r"ukr|ua|укр|україн\w*|ukrainian"),
    ("en", "English", ("eng",), r"eng|english|англ\w*"),
    ("pl", "Polski", ("pol",), r"pol|polish|polski|польськ\w*"),
    ("de", "Deutsch", ("ger", "deu"), r"ger|deu|german|deutsch|німецьк\w*"),
    ("fr", "Français", ("fre", "fra"), r"fre|fra|french|français|французьк\w*"),
    ("es", "Español", ("spa",), r"spa|spanish|español|іспанськ\w*"),
    ("it", "Italiano", ("ita",), r"ita|italian|italiano|італійськ\w*"),
    ("pt", "Português", ("por",), r"por|portuguese|português"),
    ("cs", "Čeština", ("cze", "ces"), r"cze|ces|czech|čeština"),
    ("tr", "Türkçe", ("tur",), r"tur|turkish|türkçe"),
    ("ja", "日本語", ("jpn",), r"jap|jpn|japanese|японськ\w*"),
    ("ko", "한국어", ("kor",), r"kor|korean|корейськ\w*"),
    ("zh", "中文", ("chi", "zho"), r"chi|zho|chinese|китайськ\w*"),
    ("ru", "Русский", ("rus",), r"rus|russian|російськ\w*"),
]

NAMES = {code: name for code, name, _, _ in _TABLE}
VLC_CODES = {code: codes for code, _, codes, _ in _TABLE}
_PATTERNS = {code: re.compile(rf"(?i){_EDGE}(?:{words}){_END}") for code, _, _, words in _TABLE}
DEFAULT = "uk"
FALLBACK = "en"


def found_in(text: str) -> set:
    """The languages a name lists: "[Ukr, Eng]" -> {"uk", "en"}."""
    text = text or ""
    return {code for code, pattern in _PATTERNS.items() if pattern.search(text)}


def preference(code: str) -> list:
    """The chosen language, then English: what the player and the
    new-episode worker look for, in order."""
    code = code if code in NAMES else DEFAULT
    return [code] if code == FALLBACK else [code, FALLBACK]


def from_locale(locale: str):
    """"uk-UA" (a Jackett indexer's language) -> "uk", or None."""
    code = (locale or "").split("-")[0].split("_")[0].lower()
    return code if code in NAMES else None


def choices(found=(), current=None) -> list:
    """Ukrainian, English, then every other language seen in the library or
    the Jackett indexers (and the saved one), as [{code, name}]."""
    codes = [DEFAULT, FALLBACK]
    for code in [*sorted(found, key=lambda c: NAMES.get(c, c)), current]:
        if code in NAMES and code not in codes:
            codes.append(code)
    return [{"code": code, "name": NAMES[code]} for code in codes]


def vlc_option(code: str) -> str:
    """VLC's audio-language list for a choice: "ukr,eng"."""
    return ",".join(VLC_CODES[c][0] for c in preference(code))
