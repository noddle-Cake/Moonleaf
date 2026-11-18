"""AO3 and Standard Ebooks use the site's own EPUB; browser-only sites explain themselves."""
from types import SimpleNamespace

import pytest

from extractors.base import ExtractionError
from extractors.official import Ao3Extractor, StandardEbooksExtractor
from extractors.registry import get_extractor
from services.epub_builder import EpubBuilder
from services.extraction import ExtractionService


def epub_bytes():
    builder = EpubBuilder('Official Book', 'Writer', None)
    builder.add_chapter('One', '<p>Text.</p>', 1)
    return builder.finalize()


def session(pages, calls):
    class Session:
        def get(self, url, timeout):
            calls.append(url)
            body, kind = pages[url]
            data = body if isinstance(body, bytes) else body.encode()
            return SimpleNamespace(content=data, text=data.decode('latin-1'), url=url,
                                   headers={'content-type': kind}, raise_for_status=lambda: None)
    return Session()


AO3_PAGE = '''<h2 class="title heading">Official Book</h2>
<h3 class="byline heading"><a rel="author" href="/users/w">Writer</a></h3>
<div class="summary module"><blockquote class="userstuff"><p>Short summary.</p></blockquote></div>
<li class="download"><ul><li><a href="/downloads/42/Official%20Book.azw3">AZW3</a></li>
<li><a href="/downloads/42/Official%20Book.epub?updated_at=1">EPUB</a></li></ul></li>'''


def test_ao3_chapter_link_downloads_official_epub():
    calls = []
    pages = {'https://archiveofourown.org/works/42?view_adult=true': (AO3_PAGE, 'text/html'),
             'https://archiveofourown.org/downloads/42/Official%20Book.epub?updated_at=1':
                 (epub_bytes(), 'application/epub+zip')}
    extractor = Ao3Extractor(session=session(pages, calls))
    service = ExtractionService(lambda url: extractor)
    metadata = service.detect_book('https://archiveofourown.org/works/42/chapters/77')
    assert metadata['url'] == 'https://archiveofourown.org/works/42'
    assert metadata['title'] == 'Official Book'
    assert metadata['author'] == 'Writer'
    assert metadata['chapter_1'] == 'https://archiveofourown.org/works/42'
    progress = []
    data = service.extract_book(metadata['chapter_1'], 'x', 'y', metadata['chapter_1'],
                                progress_callback=lambda n, t: progress.append(t))
    assert data == epub_bytes() or data.startswith(b'PK')
    assert progress == ['Downloaded the EPUB']


def test_ao3_members_only_work_is_explained():
    extractor = Ao3Extractor(session=session(
        {'https://archiveofourown.org/works/7?view_adult=true':
            ('This work is only available to registered users of the Archive.', 'text/html')}, []))
    with pytest.raises(ExtractionError, match='signed-in'):
        extractor.get_book_metadata('https://archiveofourown.org/works/7')


def test_standard_ebooks_follows_download_page():
    page = 'https://standardebooks.org/ebooks/jane-doe/a-quiet-harbor'
    file = f'{page}/downloads/jane-doe_a-quiet-harbor.epub'
    html = f'''<h1 property="schema:name">A Quiet Harbor</h1>
<a property="schema:author"><span property="schema:name">Jane Doe</span></a>
<img src="/images/covers/jane-doe_a-quiet-harbor/abc/cover.jpg">
<a href="{file.replace('.epub', '.kepub.epub')}">Kobo</a><a href="{file}">Compatible</a>'''
    calls = []
    pages = {page: (html, 'text/html'),
             file: (f'<meta http-equiv="refresh" content="0; url={file}?source=download" />',
                    'application/xhtml+xml; charset=utf-8'),
             f'{file}?source=download': (epub_bytes(), 'application/epub+zip')}
    extractor = StandardEbooksExtractor(session=session(pages, calls))
    service = ExtractionService(lambda url: extractor)
    metadata = service.detect_book(f'{page}/text/chapter-1')
    assert metadata['title'] == 'A Quiet Harbor'
    assert metadata['author'] == 'Jane Doe'
    assert metadata['cover_url'].endswith('/cover.jpg')
    data = service.extract_book(page, 'x', 'y', page)
    assert data.startswith(b'PK')
    assert calls[-1] == f'{file}?source=download'


def test_not_an_epub_is_rejected():
    page = 'https://standardebooks.org/ebooks/a/b'
    pages = {page: (f'<h1 property="schema:name">B</h1><a href="{page}/downloads/b.epub">e</a>', 'text/html'),
             f'{page}/downloads/b.epub': (b'not a zip', 'application/epub+zip')}
    extractor = StandardEbooksExtractor(session=session(pages, []))
    with pytest.raises(ExtractionError, match="isn't an EPUB"):
        ExtractionService(lambda url: extractor).extract_book(page, 'x', 'y', page)


@pytest.mark.parametrize('url, name', [
    ('https://www.scribblehub.com/series/1/x/', 'Scribble Hub'),
    ('https://m.fanfiction.net/s/1/1/x', 'FanFiction.net'),
    ('https://www.fictionpress.com/s/1/1/x', 'FictionPress'),
])
def test_browser_only_sites_point_to_the_app(url, name):
    with pytest.raises(ValueError, match=f"{name}.*Moonleaf app"):
        get_extractor(url)
