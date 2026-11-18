"""Sites that publish their own EPUB files: Moonleaf downloads those."""
import re
from urllib.parse import urlsplit, urlunsplit, urlencode, parse_qsl

from .base import BaseExtractor, ExtractionError


def _text(tag) -> str:
    return re.sub(r"\s+", " ", tag.get_text(" ", strip=True)).strip() if tag else ""


def _page(url: str, path: str) -> str:
    split = urlsplit(url)
    return urlunsplit((split.scheme, split.netloc, path, "", ""))


class OfficialEpubExtractor(BaseExtractor):
    official_epub = True

    def parse_chapter(self, soup, url, count):
        raise ExtractionError("This site's books are downloaded as one EPUB.")


class Ao3Extractor(OfficialEpubExtractor):
    hosts = ("archiveofourown.org", "www.archiveofourown.org", "ao3.org")

    def fetch_url(self, url):
        """Skip AO3's "this work may have adult content" notice."""
        split = urlsplit(url)
        query = dict(parse_qsl(split.query))
        query["view_adult"] = "true"
        return urlunsplit((split.scheme, split.netloc, split.path, urlencode(query), ""))

    def _work_id(self, url):
        parts = self.segments(url)
        at = parts.index("works") if "works" in parts else -1
        return parts[at + 1] if 0 <= at < len(parts) - 1 and parts[at + 1].isdigit() else None

    def is_chapter(self, url):
        return self._work_id(url) is not None and len(self.segments(url)) > 2

    def novel_url_from_path(self, url):
        work = self._work_id(url)
        return _page(url, f"/works/{work}") if work else None

    def parse_book(self, soup, url):
        if "only available to registered users" in soup.get_text():
            raise ExtractionError("This AO3 work is visible only to signed-in members, so it can't be downloaded.")
        title = _text(soup.select_one("h2.title.heading"))
        if not title:
            raise ExtractionError(f"This doesn't look like an AO3 work page: {url}")
        authors = []
        for a in soup.select('h3.byline a[rel^="author"], h3.heading a[rel^="author"]'):
            if _text(a) not in authors:
                authors.append(_text(a))
        return {"title": title, "author": ", ".join(authors) or None, "cover_url": None,
                "chapter_1": self.novel_url_from_path(url) or url,
                "description": _text(soup.select_one(".summary blockquote.userstuff")) or None}

    def epub_link(self, soup, url):
        for a in soup.select('li.download a[href*="/downloads/"]'):
            link = self.link(url, a.get("href"))
            if link and urlsplit(link).path.lower().endswith(".epub"):
                return link
        work = self._work_id(url)
        return _page(url, f"/downloads/{work}/work.epub") if work else None


class StandardEbooksExtractor(OfficialEpubExtractor):
    hosts = ("standardebooks.org", "www.standardebooks.org")

    def is_chapter(self, url):
        parts = self.segments(url)
        return bool(parts) and parts[0] == "ebooks" and ("text" in parts or "downloads" in parts)

    def novel_url_from_path(self, url):
        parts = self.segments(url)
        ends = [i for i, p in enumerate(parts) if p in ("text", "downloads")]
        return _page(url, "/" + "/".join(parts[:ends[0]])) if ends and ends[0] >= 3 else None

    def parse_book(self, soup, url):
        title = _text(soup.select_one('h1[property="schema:name"]'))
        if not title:
            raise ExtractionError("Open a book's page on Standard Ebooks, not a list of books.")
        authors = []
        for name in soup.select('[property="schema:author"] [property="schema:name"]'):
            if _text(name) and _text(name) not in authors:
                authors.append(_text(name))
        cover = next((img.get("src") for img in soup.select('img[src*="/images/covers/"]')
                      if img.get("src", "").endswith("/cover.jpg")), None)
        description = (soup.select_one('#description [property="schema:description"] p')
                       or soup.select_one('#description [property="schema:description"]'))
        return {"title": title, "author": ", ".join(authors) or None, "cover_url": self.link(url, cover),
                "chapter_1": url, "description": _text(description) or None}

    def epub_link(self, soup, url):
        for a in soup.select('a[href$=".epub"]'):
            link = self.link(url, a.get("href"))
            path = urlsplit(link).path if link else ""
            if link and not path.endswith(".kepub.epub") and not path.endswith("_advanced.epub"):
                return link
        return None
