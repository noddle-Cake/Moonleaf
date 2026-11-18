// Scribble Hub, FanFiction.net (through the in-app browser), and AO3 and
// Standard Ebooks (their own EPUB files). Fixtures follow each site's layout
// with sample content.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novel_to_epub/data/epub_writer.dart';
import 'package:novel_to_epub/data/local_novel_service.dart';
import 'package:novel_to_epub/data/novel_service.dart';
import 'package:novel_to_epub/data/page_loader.dart';
import 'package:novel_to_epub/data/site_extractors.dart';
import 'package:novel_to_epub/reader/epub_document.dart';

class FakeBrowser implements PageLoader {
  FakeBrowser(this.pages);
  final Map<String, String> pages;
  final loaded = <String>[];
  @override
  Future<String> load(Uri url) async {
    loaded.add(url.toString());
    return pages[url.toString()] ?? (throw ApiException('No fixture for $url'));
  }
}

Future<ExtractionJob> finish(LocalNovelService service, String id) async {
  for (var i = 0; i < 500; i++) {
    final job = await service.job(id);
    if (!job.active) return job;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  throw StateError('Job did not finish');
}

Future<EpubDocument> book(
  LocalNovelService service,
  BookMetadata metadata,
) async {
  final id = await service.extract(
    url: metadata.url,
    title: metadata.title,
    author: metadata.author,
    chapterUrl: metadata.firstChapter,
  );
  final job = await finish(service, id);
  expect(job.error, isNull);
  expect(job.status, 'complete');
  return EpubDocument.parse(await service.download(id));
}

const shSeries = 'https://www.scribblehub.com/series/123/lantern-keeper/';
String shChapter(int n) =>
    'https://www.scribblehub.com/read/123-lantern-keeper/chapter/${1000 + n}/';
final shPages = {
  shSeries:
      '''<div class="fic_title">The Lantern Keeper</div>
<span class="auth_name_fic">Mira</span><div class="fic_image"><img src="/cover.jpg"></div>
<div class="wi_fic_desc">A keeper and a bell.</div>
<a class="read_buttons" href="${shChapter(1)}">Read First</a>
<ol class="toc_ol"><li class="toc_w" order="2"><a class="toc_a" href="${shChapter(2)}">Second</a></li></ol>''',
  shChapter(
    1,
  ): '''<div class="chapter-title">The Lantern Keeper - Chapter 1: The Bell</div>
<div id="chp_raw"><p>It <em>rang</em> twice.</p><script>ad()</script></div>
<a class="btn-wi btn-next" href="${shChapter(2)}">Next</a>''',
  shChapter(2): '''<div class="chapter-title">Fog</div>
<div id="chp_raw"><p>The end.</p></div>
<a class="btn-wi btn-next disabled" href="#">Next</a>''',
};

const ffStory = 'https://www.fanfiction.net/s/555/1/Lantern-Keeper';
final ffPages = {
  ffStory: '''<div id="profile_top"><img class="cimage" src="/image/1/75/"><b class="xcontrast_txt">Lantern Keeper</b>
By: <a class="xcontrast_txt" href="/u/9/Mira">Mira</a><div class="xcontrast_txt">A keeper and a bell.</div></div>
<select name="chapter" id="chap_select"><option value="1" selected>1. The Bell</option><option value="2">2. Fog</option></select>
<div id="storytext"><p>It rang twice.</p></div>
<button class="btn" type="button" onclick="self.location='/s/555/2/Lantern-Keeper'">Next &gt;</button>''',
  'https://www.fanfiction.net/s/555/2/Lantern-Keeper':
      '''<div id="profile_top"><b class="xcontrast_txt">Lantern Keeper</b></div>
<select name="chapter"><option value="1">1. The Bell</option><option value="2" selected>2. Fog</option></select>
<div id="storytext"><p>The end.</p></div>
<button class="btn" onclick="self.location='/s/555/1/Lantern-Keeper'">&lt; Prev</button>''',
};

Uint8List sampleEpub() => buildEpub(
  EpubBook('Official Book', 'Writer', [
    NovelChapter('One', '<p>Text.</p>', Uri.parse('https://x/1'), null),
  ], null),
);

void main() {
  test('Scribble Hub: chapter link → whole book through the browser', () async {
    final browser = FakeBrowser(shPages);
    final service = LocalNovelService(
      browser: browser,
      politeDelay: Duration.zero,
      client: MockClient((_) async => http.Response('blocked', 403)),
    );
    addTearDown(service.close);
    final metadata = await service.detect(shChapter(2));
    expect(
      metadata.url,
      'https://www.scribblehub.com/series/123/lantern-keeper/',
    );
    expect(metadata.title, 'The Lantern Keeper');
    expect(metadata.author, 'Mira');
    expect(metadata.firstChapter, shChapter(1));
    expect(metadata.coverUrl, 'https://www.scribblehub.com/cover.jpg');
    final doc = await book(service, metadata);
    expect(doc.toc.map((t) => t.title), [
      'Chapter 1: The Bell',
      'Chapter 2: Fog',
    ]);
    expect(browser.loaded, [shSeries, shChapter(1), shChapter(2)]);
    final text = doc.chapters.map((c) => c.plainText).join();
    expect(text, contains('It rang twice.'));
    expect(text, isNot(contains('ad()')));
  });

  test('Scribble Hub falls back to the contents order', () {
    final m = const ScribbleHubExtractor().book(
      '<div class="fic_title">T</div><li class="toc_w" order="5"><a class="toc_a" href="/read/1-t/chapter/9/">5</a></li>'
      '<li class="toc_w" order="1"><a class="toc_a" href="/read/1-t/chapter/2/">1</a></li>',
      Uri.parse('https://www.scribblehub.com/series/1/t/'),
    );
    expect(m.firstChapter, 'https://www.scribblehub.com/read/1-t/chapter/2/');
  });

  test('browser-only sites explain what they need without a browser', () async {
    final service = LocalNovelService(
      client: MockClient((_) async => http.Response('blocked', 403)),
    );
    addTearDown(service.close);
    await expectLater(
      service.detect(shSeries),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          allOf(contains('Scribble Hub'), contains('built-in browser')),
        ),
      ),
    );
  });

  test('FanFiction.net: any chapter, mobile links and chapter names', () async {
    final browser = FakeBrowser(ffPages);
    final service = LocalNovelService(
      browser: browser,
      politeDelay: Duration.zero,
    );
    addTearDown(service.close);
    final metadata = await service.detect(
      'https://m.fanfiction.net/s/555/2/Lantern-Keeper',
    );
    expect(metadata.url, ffStory);
    expect(metadata.title, 'Lantern Keeper');
    expect(metadata.author, 'Mira');
    expect(metadata.description, 'A keeper and a bell.');
    // The mobile address is fetched as the desktop page.
    expect(browser.loaded.first, ffStory);
    final doc = await book(service, metadata);
    expect(doc.toc.map((t) => t.title), [
      'Chapter 1: The Bell',
      'Chapter 2: Fog',
    ]);
  });

  test('AO3: downloads the work’s own EPUB, past the adult notice', () async {
    final calls = <String>[];
    final epub = sampleEpub();
    final service = LocalNovelService(
      client: MockClient((r) async {
        calls.add(r.url.toString());
        if (r.url.path == '/works/42') {
          return http.Response(
            '''<h2 class="title heading">Official Book</h2>
<h3 class="byline heading"><a rel="author" href="/users/w">Writer</a></h3>
<div class="summary module"><blockquote class="userstuff"><p>Short summary.</p></blockquote></div>
<li class="download"><ul><li><a href="/downloads/42/Official%20Book.azw3?updated_at=1">AZW3</a></li>
<li><a href="/downloads/42/Official%20Book.epub?updated_at=1">EPUB</a></li></ul></li>''',
            200,
          );
        }
        return http.Response.bytes(
          epub,
          200,
          headers: {'content-type': 'application/epub+zip'},
        );
      }),
    );
    addTearDown(service.close);
    final metadata = await service.detect(
      'https://archiveofourown.org/works/42/chapters/77',
    );
    expect(metadata.url, 'https://archiveofourown.org/works/42');
    expect(metadata.author, 'Writer');
    expect(metadata.description, 'Short summary.');
    final doc = await book(service, metadata);
    expect(doc.title, 'Official Book');
    expect(calls.first, 'https://archiveofourown.org/works/42?view_adult=true');
    expect(
      calls.last,
      'https://archiveofourown.org/downloads/42/Official%20Book.epub?updated_at=1',
    );
  });

  test('AO3 members-only works fail with a clear message', () async {
    final service = LocalNovelService(
      client: MockClient(
        (_) async => http.Response(
          'This work is only available to registered users of the Archive.',
          200,
        ),
      ),
    );
    addTearDown(service.close);
    await expectLater(
      service.detect('https://archiveofourown.org/works/7'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('signed-in'),
        ),
      ),
    );
  });

  test('Standard Ebooks: follows the download page to the EPUB', () async {
    const page = 'https://standardebooks.org/ebooks/jane-doe/a-quiet-harbor';
    const file = '$page/downloads/jane-doe_a-quiet-harbor.epub';
    final epub = sampleEpub();
    final calls = <String>[];
    final service = LocalNovelService(
      client: MockClient((r) async {
        final url = r.url.toString();
        calls.add(url);
        if (url == page) {
          return http.Response(
            '''<h1 property="schema:name">A Quiet Harbor</h1>
<a property="schema:author" href="/ebooks/jane-doe"><span property="schema:name">Jane Doe</span></a>
<img src="/images/covers/jane-doe_a-quiet-harbor/abc/cover.jpg">
<section id="description"><div property="schema:description"><p>A classic.</p></div></section>
<a property="schema:contentUrl" href="$file" class="epub">Compatible epub</a>
<a property="schema:contentUrl" href="${file.replaceFirst('.epub', '.kepub.epub')}">Kobo</a>
<a property="schema:contentUrl" href="${file.replaceFirst('.epub', '_advanced.epub')}">Advanced</a>''',
            200,
          );
        }
        if (url == file) {
          return http.Response(
            '<meta http-equiv="refresh" content="0; url=/ebooks/jane-doe/a-quiet-harbor/downloads/jane-doe_a-quiet-harbor.epub?source=download" />',
            200,
            headers: {'content-type': 'application/xhtml+xml; charset=utf-8'},
          );
        }
        return http.Response.bytes(
          epub,
          200,
          headers: {'content-type': 'application/epub+zip'},
        );
      }),
    );
    addTearDown(service.close);
    final metadata = await service.detect('$page/text/chapter-1');
    expect(metadata.url, page);
    expect(metadata.title, 'A Quiet Harbor');
    expect(metadata.author, 'Jane Doe');
    expect(
      metadata.coverUrl,
      'https://standardebooks.org/images/covers/jane-doe_a-quiet-harbor/abc/cover.jpg',
    );
    final doc = await book(service, metadata);
    expect(doc.title, 'Official Book');
    expect(calls.last, '$file?source=download');
  });

  test('chapter links never cross into another story', () {
    bool same(String a, String b) => sameNovel(Uri.parse(a), Uri.parse(b));
    expect(same(shChapter(1), shChapter(2)), isTrue);
    expect(
      same(
        shChapter(1),
        'https://www.scribblehub.com/read/999-other/chapter/1/',
      ),
      isFalse,
    );
    expect(same(ffStory, 'https://www.fanfiction.net/s/555/9/x'), isTrue);
    expect(same(ffStory, 'https://www.fanfiction.net/s/556/2/x'), isFalse);
    expect(
      same(
        'https://archiveofourown.org/works/1',
        'https://archiveofourown.org/works',
      ),
      isFalse,
    );
  });
}
