from typing import Callable
from urllib.parse import urldefrag

from extractors.base import ExtractionError
from extractors.registry import get_extractor
from services.chapter_titles import clean_chapter_title
from services.epub_builder import EpubBuilder


class ExtractionCancelled(Exception):
    """The client cancelled an extraction."""


class ExtractionService:
    def __init__(self, extractor_factory=get_extractor):
        self.extractor_factory = extractor_factory

    def detect_book(self, url: str) -> dict:
        return self.extractor_factory(url).get_book_metadata(url)

    def extract_book(self, url: str, title: str, author: str, chapter_url: str,
                     cover_bytes: bytes | None = None,
                     progress_callback: Callable[[int, str], None] | None = None,
                     cancel_callback: Callable[[], bool] | None = None) -> bytes:
        def check_cancelled():
            if cancel_callback and cancel_callback():
                raise ExtractionCancelled()

        check_cancelled()
        extractor = self.extractor_factory(url)
        if extractor.official_epub:
            return self._official_epub(extractor, chapter_url or url, progress_callback, check_cancelled)
        if cover_bytes is None:
            cover_url = extractor.get_book_metadata(url).get("cover_url")
            if cover_url:
                cover_bytes = extractor.fetch(cover_url).content
        builder = EpubBuilder(title, author, cover_bytes)
        visited = set()
        next_url = chapter_url
        count = 1
        while next_url:
            check_cancelled()
            next_url = urldefrag(next_url)[0]
            if not extractor.supports(next_url):
                raise ExtractionError(f"Chapter navigation left the supported site: {next_url}")
            if next_url in visited:
                raise ExtractionError(f"Chapter navigation loop at {next_url}")
            visited.add(next_url)
            chapter = extractor.get_chapter(next_url, count)
            check_cancelled()
            name = clean_chapter_title(chapter.title, title, count)
            builder.add_chapter(name, chapter.html, count)
            if progress_callback:
                progress_callback(count, name)
            next_url = chapter.next_url
            count += 1
        check_cancelled()
        return builder.finalize()

    @staticmethod
    def _official_epub(extractor, url, progress_callback, check_cancelled) -> bytes:
        """Download the site's own EPUB for the book."""
        from io import BytesIO
        from zipfile import BadZipFile, ZipFile

        from bs4 import BeautifulSoup

        page = extractor.fetch(extractor.fetch_url(url))
        link = extractor.epub_link(BeautifulSoup(page.content, "html.parser"), page.url)
        if not link or not extractor.supports(link):
            raise ExtractionError("The site didn't offer an EPUB for this book.")
        check_cancelled()
        data = extractor.fetch_file(link)
        try:
            with ZipFile(BytesIO(data)) as archive:
                if not archive.read("mimetype").startswith(b"application/epub+zip"):
                    raise ExtractionError("The site sent a file that isn't an EPUB.")
        except (BadZipFile, KeyError) as exc:
            raise ExtractionError("The site sent a file that isn't an EPUB.") from exc
        if progress_callback:
            progress_callback(1, "Downloaded the EPUB")
        return data
