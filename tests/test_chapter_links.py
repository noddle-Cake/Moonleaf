"""A chapter link from a supported site resolves to its novel's main page."""
from types import SimpleNamespace

import pytest
from bs4 import BeautifulSoup

from extractors.base import ExtractionError
from extractors.roliascan import RoliaScanExtractor
from extractors.royalRoad import RoyalRoadExtractor

NOVEL = 'https://roliascan.com/manga/sample-novel/'
CHAPTER = 'https://roliascan.com/read/sample-novel/ch7-130/'
FIRST = 'https://roliascan.com/read/sample-novel/ch1-123/'
BOOK = '''<h1>Sample Novel</h1><a id="start-reading-btn" href="/read/sample-novel/ch1-123/">Read</a>'''
# Shaped like a live RoliaScan chapter page: a breadcrumb trail plus sidebar
# links to other novels.
CHAPTER_PAGE = '''<script type="application/ld+json">{"@context":"https://schema.org","@type":"BreadcrumbList",
"itemListElement":[{"@type":"ListItem","position":1,"name":"Home","item":"https://roliascan.com"},
{"@type":"ListItem","position":3,"name":"Chapter 7","item":"https://roliascan.com/read/sample-novel/ch7-130/"},
{"@type":"ListItem","position":2,"name":"Sample Novel","item":"https://roliascan.com/manga/sample-novel/"}]}</script>
<a href="https://roliascan.com/manga/another-story/">Another Story</a>
<div class="reader-text"><p>Chapter text.</p></div>'''


def session(pages, calls):
    class Session:
        def get(self, url, timeout):
            calls.append(url)
            return SimpleNamespace(content=pages[url].encode(), url=url, raise_for_status=lambda: None)
    return Session()


def test_roliascan_chapter_link_detects_whole_novel():
    calls = []
    extractor = RoliaScanExtractor(session=session({CHAPTER: CHAPTER_PAGE, NOVEL: BOOK}, calls))
    metadata = extractor.get_book_metadata(CHAPTER)
    assert metadata['url'] == NOVEL
    assert metadata['chapter_1'] == FIRST
    assert calls == [CHAPTER, NOVEL]


def test_roliascan_novel_link_is_unchanged():
    calls = []
    extractor = RoliaScanExtractor(session=session({NOVEL: BOOK}, calls))
    assert extractor.get_book_metadata(NOVEL)['url'] == NOVEL
    assert calls == [NOVEL]


@pytest.mark.parametrize('page, expected', [
    # No breadcrumb: prefer this novel's link over sidebar suggestions.
    ('<a href="/manga/another-story/">A</a><a href="/manga/sample-novel/">Info</a>', NOVEL),
    # Nothing to go on: the chapter's novel slug.
    ('<p>No links</p>', NOVEL),
])
def test_roliascan_fallbacks(page, expected):
    assert RoliaScanExtractor().novel_url_from_chapter(
        BeautifulSoup(page, 'html.parser'), CHAPTER) == expected


def test_breadcrumb_ignores_other_sites():
    page = ('<script type="application/ld+json">{"@type":"BreadcrumbList","itemListElement":'
            '[{"position":2,"item":"https://evil.test/manga/sample-novel/"}]}</script>')
    found = RoliaScanExtractor().novel_url_from_chapter(
        BeautifulSoup(page, 'html.parser'), CHAPTER)
    assert found == NOVEL


@pytest.mark.parametrize('url, novel', [
    ('https://www.royalroad.com/fiction/12345/sample-story/chapter/67890/a-chapter',
     'https://www.royalroad.com/fiction/12345/sample-story'),
    ('https://www.royalroad.com/fiction/12345/chapter/67890', 'https://www.royalroad.com/fiction/12345'),
    ('https://royalroad.com/fiction/12345/sample-story/chapter/67890/a-chapter?page=2#comments',
     'https://royalroad.com/fiction/12345/sample-story'),
])
def test_royalroad_chapter_path_gives_novel_without_fetching(url, novel):
    extractor = RoyalRoadExtractor()
    assert extractor.is_chapter(url)
    assert extractor.novel_url(url) == novel


def test_royalroad_short_chapter_link_reads_canonical():
    short = 'https://www.royalroad.com/fiction/chapter/67890'
    page = ('<link rel="canonical" href="https://www.royalroad.com/fiction/12345/sample-story/'
            'chapter/67890/a-chapter"><div class="chapter-content">Text</div>')
    calls = []
    extractor = RoyalRoadExtractor(session=session({short: page}, calls))
    assert extractor.novel_url(short) == 'https://www.royalroad.com/fiction/12345/sample-story'
    assert calls == [short]


def test_unresolvable_chapter_fails_clearly():
    short = 'https://www.royalroad.com/fiction/chapter/67890'
    extractor = RoyalRoadExtractor(session=session({short: '<p>Nothing</p>'}, []))
    with pytest.raises(ExtractionError, match="novel page"):
        extractor.novel_url(short)
