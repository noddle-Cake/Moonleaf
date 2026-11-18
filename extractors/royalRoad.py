import json
from urllib.parse import urlsplit, urlunsplit

from .base import BaseExtractor, Chapter, ExtractionError


class RoyalRoadExtractor(BaseExtractor):
    hosts = ("royalroad.com", "www.royalroad.com")

    def is_chapter(self, url):
        parts = self.segments(url)
        return bool(parts) and parts[0] == "fiction" and "chapter" in parts

    def novel_url_from_path(self, url):
        """/fiction/<id>/<slug>/chapter/<id>/<slug> -> /fiction/<id>/<slug>."""
        parts = self.segments(url)
        at = parts.index("chapter") if "chapter" in parts else -1
        if at < 2 or not parts[1].isdigit():
            return None
        split = urlsplit(url)
        return urlunsplit((split.scheme, split.netloc, "/" + "/".join(parts[:at]), "", ""))

    def novel_url_from_chapter(self, soup, url):
        """Short links like /fiction/chapter/<id> name only the chapter."""
        for tag, attr in (('link[rel="canonical"]', "href"), ('meta[property="og:url"]', "content")):
            found = soup.select_one(tag)
            full = self.link(url, found.get(attr) if found else None)
            novel = self.novel_url_from_path(full) if full else None
            if novel:
                return novel
        for a in soup.select('a[href^="/fiction/"]'):
            link = self.link(url, a.get("href"))
            parts = self.segments(link) if link else []
            if len(parts) >= 2 and parts[1].isdigit() and "chapter" not in parts:
                return link
        return None

    def parse_book(self, soup, url):
        data = {}
        for script in soup.select('script[type="application/ld+json"]'):
            try:
                candidate = json.loads(script.get_text())
            except (ValueError, TypeError):
                continue
            if isinstance(candidate, dict) and candidate.get("name"):
                data = candidate
                break
        heading = soup.select_one("h1")
        author = soup.select_one('a[href^="/profile/"]')
        first = soup.select_one('#chapters tbody a[href*="/chapter/"]')
        target = data.get("potentialAction", {}).get("target", {})
        first_href = target.get("urlTemplate") if isinstance(target, dict) else target
        title = data.get("name") or (heading.get_text(strip=True) if heading else None)
        if not title:
            raise ExtractionError(f"Book title missing at {url}")
        cover = data.get("thumbnailUrl")
        if isinstance(cover, list):
            cover = cover[0] if cover else None
        return {"title": title, "author": author.get_text(strip=True) if author else None,
                "description": data.get("description"), "cover_url": self.link(url, cover),
                "chapter_1": self.link(url, first_href or (first.get("href") if first else None))}

    def parse_chapter(self, soup, url, count):
        content = soup.select_one(".chapter-content")
        if content is None or not content.get_text(strip=True):
            raise ExtractionError(f"Chapter content missing at {url}")
        heading = soup.select_one("h1")
        next_link = soup.select_one('a[rel~="next"]')
        if next_link is None:
            next_link = next((a for a in soup.select('a[href*="/chapter/"]')
                              if a.get_text(" ", strip=True).casefold() == "next chapter"), None)
        return Chapter(heading.get_text(strip=True) if heading else f"Chapter {count}",
                       str(content), self.link(url, next_link.get("href") if next_link else None))
