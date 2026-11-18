"""Tidy chapter names into "Chapter N: Name" (mirrors chapter_titles.dart)."""
import re

_SEPARATORS_START = re.compile(r"^[\s:\-–—|·,.()\[\]]+")
_SEPARATORS_END = re.compile(r"[\s:\-–—|·,(\[]+$")
_NUMBERED = re.compile(r"^(?:chapter|chap|ch|episode|ep)\.?\s*#?\s*(\d+(?:\.\d+)?)(?!\d)\s*(.*)$", re.I)
_BARE = re.compile(r"^#?(\d+(?:\.\d+)?)\s*(?:[:.\-–—|)]\s*|\s+-\s*)(.*)$")


def _trim(value: str) -> str:
    return _SEPARATORS_END.sub("", _SEPARATORS_START.sub("", value)).strip()


def clean_chapter_title(raw: str | None, book_title: str | None, position: int) -> str:
    """Drop a repeated book title, keep the site's chapter number, else number by position."""
    title = re.sub(r"\s+", " ", raw or "").strip()
    book = re.sub(r"\s+", " ", book_title or "").strip()
    if len(book) >= 3:
        title = re.sub(re.escape(book), " ", title, flags=re.I)
    title = _trim(re.sub(r"\s+", " ", title))
    match = _NUMBERED.match(title) or _BARE.match(title)
    if match:
        number, rest = match.group(1), _trim(match.group(2) or "")
        repeat = re.fullmatch(r"(?:chapter|chap|ch)\.?\s*" + re.escape(number), rest, re.I)
        return f"Chapter {number}" if not rest or repeat else f"Chapter {number}: {rest}"
    return f"Chapter {position}: {title}" if title else f"Chapter {position}"
