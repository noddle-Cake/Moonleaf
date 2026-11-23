"""Indra Translations' publicly readable novels."""
import math
from copy import deepcopy
from urllib.parse import urlsplit

from .base import BaseExtractor, Chapter, ExtractionError


class IndraExtractor(BaseExtractor):
    hosts = ("indratranslations.com", "www.indratranslations.com")

    def fetch(self, url):
        # The reader returns a 404 to requests' default user agent.
        response = self.session.get(url, timeout=self.timeout,
                                    headers={"User-Agent": "Mozilla/5.0"})
        response.raise_for_status()
        return response

    def is_chapter(self, url):
        parts = self.segments(url)
        return len(parts) == 2 and "-chapter-" in parts[1]

    def novel_url_from_path(self, url):
        if not self.is_chapter(url):
            return None
        parsed = urlsplit(url)
        return f"{parsed.scheme}://{parsed.netloc}/{self.segments(url)[0]}/"

    def novel_url_from_chapter(self, soup, url):
        return self.novel_url_from_path(url)

    def _same_novel(self, book, chapter):
        return (bool(self.segments(book)) and self.supports(chapter) and self.is_chapter(chapter)
                and self.segments(book)[0] == self.segments(chapter)[0])

    def parse_book(self, soup, url):
        heading = soup.select_one("h1.story-main-title")
        first = soup.select_one('.td-story-actions a[href]:has(.fa-book-open)')
        first_url = self.link(url, first.get("href") if first else None)
        title = heading.get_text(" ", strip=True) if heading else ""
        if not title or not first_url or not self._same_novel(url, first_url):
            raise ExtractionError(f"Indra Translations book title or first-chapter link missing at {url}")
        author = soup.select_one('.story-meta-list a[href*="/tac-gia/"]')
        cover = soup.select_one('meta[property="og:image"]')
        description = soup.select_one("#story-synopsis")
        return {"title": title, "author": author.get_text(" ", strip=True) if author else None,
                "chapter_1": first_url,
                "cover_url": self.link(url, cover.get("content") if cover else None),
                "description": description.get_text(" ", strip=True) if description else None}

    def parse_chapter(self, soup, url, count):
        if soup.select_one("#vip-gate-area, .gd-vip-gate"):
            raise ExtractionError("This Indra Translations chapter is premium or requires login; "
                                  "only publicly readable chapters can be downloaded.")
        content = soup.select_one("#chapter-content-text")
        if content is None:
            raise ExtractionError(f"Indra Translations chapter text missing at {url}")
        content = deepcopy(content)
        for unwanted in content.select(
                "script, style, iframe, form, .td-ad-container, .adsbygoogle, "
                ".td-s-noise, .td-s-para-noise, .td-hidden-watermark, "
                ".td-copy-honeypot, .td-canary-trap, [aria-hidden=true], [hidden]"):
            unwanted.decompose()
        # The browser uses flex order; DOM order is deliberately shuffled.
        for flow in content.select(".td-reading-flow"):
            children = flow.find_all(recursive=False)
            try:
                orders = [float(child["data-order"]) for child in children]
                if not all(math.isfinite(order) for order in orders):
                    raise ValueError
            except (KeyError, ValueError):
                raise ExtractionError("Indra Translations paragraph order is missing or invalid.")
            for _, child in sorted(zip(orders, children), key=lambda item: item[0]):
                flow.append(child.extract())
        if not content.get_text(strip=True):
            raise ExtractionError(f"Indra Translations chapter text is empty at {url}")
        heading = soup.select_one("#chapter-heading, h1.chapter-title")
        title = heading.get_text(" ", strip=True) if heading else f"Chapter {count}"
        next_link = soup.select_one('a.btn-next-chap[href]:not(.disabled)')
        next_url = self.link(url, next_link.get("href") if next_link else None)
        if next_url and not self._same_novel(url, next_url):
            raise ExtractionError(f"Indra Translations next link leaves this novel: {next_url}")
        return Chapter(title=title, html=content.decode_contents(), next_url=next_url)
