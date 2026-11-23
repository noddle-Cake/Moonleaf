from io import BytesIO
from pathlib import Path
from types import SimpleNamespace
from zipfile import ZipFile

import pytest
from bs4 import BeautifulSoup

from extractors.base import ExtractionError
from extractors.indra import IndraExtractor
from extractors.registry import get_extractor
from services.extraction import ExtractionService

ROOT = 'https://indratranslations.com'
BOOK = f'{ROOT}/lantern-keeper/'
FIRST = f'{BOOK}lantern-keeper-chapter-1-the-bell/'
SECOND = f'{BOOK}lantern-keeper-chapter-2-fog/'


def fixture(name):
    return (Path(__file__).parent / 'fixtures' / 'indra' / f'{name}.html').read_text()


def soup(source):
    return BeautifulSoup(source, 'html.parser')


def test_book_metadata_and_chapter_urls():
    extractor = get_extractor(BOOK)
    assert isinstance(extractor, IndraExtractor)
    assert extractor.parse_book(soup(fixture('book')), BOOK) == {
        'title': 'The Lantern Keeper', 'author': 'Indra Team',
        'description': 'A keeper and a bell. A quiet harbor.',
        'cover_url': f'{ROOT}/cover.jpg', 'chapter_1': FIRST,
    }
    assert extractor.novel_url(SECOND + '?x=1') == BOOK
    assert not extractor.is_chapter(BOOK)
    assert IndraExtractor.supports(BOOK.replace('://', '://www.'))
    assert not IndraExtractor.supports('https://indratranslations.com.evil.test/x/')


def test_chapter_matches_displayed_order_and_visible_text():
    original = soup(fixture('chapter'))
    chapter = IndraExtractor().parse_chapter(original, FIRST, 1)
    assert chapter.title == 'Chapter 1: The Bell'
    assert chapter.next_url == SECOND
    paragraphs = soup(chapter.html).select('p')
    assert [p.get_text() for p in paragraphs] == [
        'First paragraph.A bell rang.', 'Second paragraph.',
        'Translated by Indra Translations.', 'Third paragraph.',
    ]
    assert '<strong>paragraph</strong>' in chapter.html
    assert '<em>paragraph</em>' in chapter.html
    assert 'Hidden' not in chapter.html
    assert 'td-reading-probe' not in chapter.html
    assert 'advertisement' not in chapter.html
    assert 'Comments' not in chapter.html
    assert original.select_one('.td-s-noise') is not None


def test_final_chapter_and_missing_metadata():
    assert IndraExtractor().parse_chapter(soup(fixture('final')), SECOND, 2).next_url is None
    with pytest.raises(ExtractionError):
        IndraExtractor().parse_book(soup('<h1>Not a story</h1>'), BOOK)


@pytest.mark.parametrize('source', [
    '', '<h1>404</h1>', '<div id="chapter-content-text"> </div>',
    '<div id="chapter-content-text"><span class="td-s-noise">Filler</span></div>',
    '<div id="chapter-content-text"><div class="td-reading-flow"><p data-order="NaN">Text</p></div></div>',
])
def test_missing_empty_or_invalid_content_fails(source):
    with pytest.raises(ExtractionError):
        IndraExtractor().parse_chapter(soup(source), FIRST, 1)


def test_premium_gate_is_never_exported():
    with pytest.raises(ExtractionError, match='premium or requires login'):
        IndraExtractor().parse_chapter(soup(fixture('premium')), FIRST, 1)


@pytest.mark.parametrize('next_url', [
    'https://evil.test/lantern-keeper/lantern-keeper-chapter-2-fog/',
    '/other/other-chapter-2/', '/login/',
])
def test_navigation_cannot_leave_story(next_url):
    source = fixture('chapter').replace('../lantern-keeper-chapter-2-fog/', next_url)
    with pytest.raises(ExtractionError, match='leaves this novel'):
        IndraExtractor().parse_chapter(soup(source), FIRST, 1)
    book = fixture('book').replace('/lantern-keeper/lantern-keeper-chapter-1-the-bell/', next_url)
    with pytest.raises(ExtractionError):
        IndraExtractor().parse_book(soup(book), BOOK)


def test_detect_from_chapter_and_build_epub_with_browser_user_agent():
    pages = {BOOK: fixture('book'), FIRST: fixture('chapter'), SECOND: fixture('final')}
    calls = []

    class Session:
        def get(self, url, timeout, headers):
            calls.append(url)
            assert timeout == 30
            assert headers['User-Agent'] == 'Mozilla/5.0'
            return SimpleNamespace(content=pages[url].encode(), url=url, raise_for_status=lambda: None)

    extractor = IndraExtractor(session=Session())
    service = ExtractionService(lambda url: extractor)
    metadata = service.detect_book(SECOND)
    assert metadata['url'] == BOOK
    assert metadata['chapter_1'] == FIRST
    result = service.extract_book(BOOK, metadata['title'], metadata['author'], FIRST, cover_bytes=b'')
    assert calls == [BOOK, FIRST, SECOND]
    with ZipFile(BytesIO(result)) as archive:
        chapter = archive.read('EPUB/chapter-00001.xhtml').decode()
        assert chapter.index('First') < chapter.index('Second') < chapter.index('Third')
        assert '<em>paragraph</em>' in chapter
        assert 'Hidden' not in chapter
        assert b'The end.' in archive.read('EPUB/chapter-00002.xhtml')
