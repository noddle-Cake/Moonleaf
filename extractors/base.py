import json
import re
from abc import ABC, abstractmethod
from urllib.parse import urljoin, urlsplit

import requests
from bs4 import BeautifulSoup

from models.chapter import Chapter
from models.metadata import BookMetadata


class ExtractionError(ValueError):
    """The page does not contain the expected novel data."""


class BaseExtractor(ABC):
    hosts: tuple[str, ...] = ()
    # Sites that publish their own EPUB: download it instead of chapters.
    official_epub = False

    def __init__(self, session=None, timeout: float = 30):
        self.session = session if session is not None else requests.Session()
        self.timeout = timeout

    @classmethod
    def supports(cls, url: str) -> bool:
        parsed = urlsplit(url)
        return parsed.scheme in {"http", "https"} and parsed.hostname in cls.hosts

    def fetch(self, url: str):
        response = self.session.get(url, timeout=self.timeout)
        response.raise_for_status()
        return response

    def get_book_metadata(self, url: str) -> BookMetadata:
        """Metadata for a novel page, or for the novel a chapter link belongs to."""
        url = self.novel_url(url)
        requested = self.fetch_url(url)
        response = self.fetch(requested)
        metadata = self.parse_book(BeautifulSoup(response.content, "html.parser"), response.url)
        # Keep redirects (such as a slug being added), but not request flags.
        metadata["url"] = url if response.url == requested else response.url
        return metadata

    def novel_url(self, url: str) -> str:
        """The novel's main page for a novel or chapter URL."""
        if not self.is_chapter(url):
            return url
        novel = self.novel_url_from_path(url)
        if novel is None:
            response = self.fetch(url)
            novel = self.novel_url_from_chapter(
                BeautifulSoup(response.content, "html.parser"), response.url)
        if not novel or not self.supports(novel) or self.is_chapter(novel):
            raise ExtractionError(
                "Couldn't find the novel page for this chapter. Paste the novel's main page instead.")
        return novel

    def fetch_url(self, url: str) -> str:
        """The address to request for a page (for example with consent flags)."""
        return url

    def epub_link(self, soup: BeautifulSoup, url: str) -> str | None:
        """The official EPUB linked from a book page."""
        return None

    def fetch_file(self, url: str) -> bytes:
        """Download a file, following an HTML "your download is starting" page."""
        for _ in range(3):
            if not self.supports(url):
                raise ExtractionError(f"The download left the supported site: {url}")
            response = self.fetch(url)
            if "html" not in response.headers.get("content-type", ""):
                return response.content
            refresh = re.search(r'http-equiv=["\']refresh["\'][^>]*url=([^"\'>\s]+)',
                                response.text, re.I)
            target = self.link(url, refresh.group(1).replace("&amp;", "&")) if refresh else None
            if not target:
                break
            url = target
        raise ExtractionError("The site sent a web page instead of the EPUB.")

    @staticmethod
    def segments(url: str) -> list[str]:
        return [s for s in urlsplit(url).path.split("/") if s]

    def is_chapter(self, url: str) -> bool:
        """Whether the URL is a chapter page rather than the novel's main page."""
        return False

    def novel_url_from_path(self, url: str) -> str | None:
        """The novel page when the chapter address alone is enough."""
        return None

    def novel_url_from_chapter(self, soup: BeautifulSoup, url: str) -> str | None:
        """The novel page as linked from a chapter page."""
        return None

    @staticmethod
    def breadcrumb_parent(soup: BeautifulSoup, url: str, accept) -> str | None:
        """The nearest page above this one in a schema.org BreadcrumbList."""
        for script in soup.select('script[type="application/ld+json"]'):
            try:
                data = json.loads(script.get_text())
            except (ValueError, TypeError):
                continue
            nodes = data if isinstance(data, list) else [data]
            for node in nodes:
                if not isinstance(node, dict):
                    continue
                for item in node.get("@graph", [node]):
                    if not isinstance(item, dict) or item.get("@type") != "BreadcrumbList":
                        continue
                    crumbs = [c for c in item.get("itemListElement", []) if isinstance(c, dict)]
                    crumbs.sort(key=lambda c: c.get("position") or 0, reverse=True)
                    for crumb in crumbs:
                        target = crumb.get("item")
                        if isinstance(target, dict):
                            target = target.get("@id") or target.get("url")
                        link = BaseExtractor.link(url, target if isinstance(target, str) else None)
                        if link and accept(link):
                            return link
        return None

    def get_chapter(self, url: str, count: int) -> Chapter:
        response = self.fetch(url)
        chapter = self.parse_chapter(BeautifulSoup(response.content, "html.parser"), response.url, count)
        if not chapter.html.strip():
            raise ExtractionError(f"No chapter content found at {url}")
        return chapter

    @staticmethod
    def link(url: str, href: str | None) -> str | None:
        if not href or not href.strip() or href.startswith("#"):
            return None
        resolved = urljoin(url, href)
        return resolved if urlsplit(resolved).scheme in {"http", "https"} else None

    @abstractmethod
    def parse_book(self, soup: BeautifulSoup, url: str) -> BookMetadata:
        """Parse metadata without performing network requests."""

    @abstractmethod
    def parse_chapter(self, soup: BeautifulSoup, url: str, count: int) -> Chapter:
        """Parse body and explicit next-chapter navigation."""
