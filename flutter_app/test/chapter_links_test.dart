// A chapter link from a supported site downloads the whole book.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novel_to_epub/data/local_novel_service.dart';
import 'package:novel_to_epub/data/novel_service.dart';
import 'package:novel_to_epub/data/site_extractors.dart';
import 'package:novel_to_epub/library/add_novel_dialog.dart';
import 'package:novel_to_epub/library/library_store.dart';

const novel = 'https://roliascan.com/manga/sample-novel/';
const chapter = 'https://roliascan.com/read/sample-novel/ch7-130/';
const first = 'https://roliascan.com/read/sample-novel/ch1-123/';
const book =
    '<h1>Sample Novel</h1><a id="start-reading-btn" href="/read/sample-novel/ch1-123/">Read</a>';
// Shaped like a live RoliaScan chapter page: breadcrumbs plus sidebar links.
const chapterPage =
    '''
<script type="application/ld+json">{"@type":"BreadcrumbList","itemListElement":[
{"@type":"ListItem","position":1,"name":"Home","item":"https://roliascan.com"},
{"@type":"ListItem","position":3,"name":"Chapter 7","item":"$chapter"},
{"@type":"ListItem","position":2,"name":"Sample Novel","item":"$novel"}]}</script>
<a href="https://roliascan.com/manga/another-story/">Another Story</a>
<div class="reader-text"><p>Chapter text.</p></div>''';

LocalNovelService service(Map<String, String> pages, List<String> calls) =>
    LocalNovelService(
      client: MockClient((r) async {
        calls.add(r.url.toString());
        final body = pages[r.url.toString()];
        return http.Response(body ?? 'missing', body == null ? 404 : 200);
      }),
    );

void main() {
  test('a RoliaScan chapter link detects its novel from chapter 1', () async {
    final calls = <String>[];
    final s = service({chapter: chapterPage, novel: book}, calls);
    addTearDown(s.close);
    final metadata = await s.detect(chapter);
    expect(metadata.url, novel);
    expect(metadata.title, 'Sample Novel');
    expect(metadata.firstChapter, first);
    expect(calls, [chapter, novel]);
  });

  test('a novel link is unchanged and fetched once', () async {
    final calls = <String>[];
    final s = service({novel: book}, calls);
    addTearDown(s.close);
    expect((await s.detect(novel)).url, novel);
    expect(calls, [novel]);
  });

  test('RoliaScan fallbacks prefer this novel and ignore other sites', () {
    const rolia = RoliaExtractor();
    final at = Uri.parse(chapter);
    expect(
      rolia
          .novelFromChapter(
            '<a href="/manga/another-story/">A</a><a href="/manga/sample-novel/">Info</a>',
            at,
          )
          .toString(),
      novel,
    );
    expect(rolia.novelFromChapter('<p>No links</p>', at).toString(), novel);
    expect(
      rolia
          .novelFromChapter(
            '<script type="application/ld+json">{"@type":"BreadcrumbList","itemListElement":[{"position":2,"item":"https://evil.test/manga/x/"}]}</script>',
            at,
          )
          .toString(),
      novel,
    );
  });

  test('Royal Road chapter links resolve without an extra request', () async {
    const rr = RoyalRoadExtractor();
    for (final (url, expected) in [
      (
        'https://www.royalroad.com/fiction/12345/sample-story/chapter/67890/a-chapter',
        'https://www.royalroad.com/fiction/12345/sample-story',
      ),
      (
        'https://www.royalroad.com/fiction/12345/chapter/67890',
        'https://www.royalroad.com/fiction/12345',
      ),
      (
        'https://royalroad.com/fiction/12345/sample-story/chapter/67890/x?page=2#c',
        'https://royalroad.com/fiction/12345/sample-story',
      ),
    ]) {
      final uri = Uri.parse(url);
      expect(rr.isChapter(uri), isTrue, reason: url);
      expect(rr.novelFromPath(uri).toString(), expected, reason: url);
    }
    expect(
      rr.isChapter(Uri.parse('https://www.royalroad.com/fiction/12345/x')),
      isFalse,
    );
    // Short links name only the chapter; the page's canonical link has the rest.
    const short = 'https://www.royalroad.com/fiction/chapter/67890';
    expect(rr.novelFromPath(Uri.parse(short)), isNull);
    expect(
      rr
          .novelFromChapter(
            '<link rel="canonical" href="https://www.royalroad.com/fiction/12345/sample-story/chapter/67890/a">',
            Uri.parse(short),
          )
          .toString(),
      'https://www.royalroad.com/fiction/12345/sample-story',
    );
    final calls = <String>[];
    final s = service({short: '<p>Nothing useful</p>'}, calls);
    addTearDown(s.close);
    await expectLater(
      s.detect(short),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('novel page'),
        ),
      ),
    );
  });

  testWidgets('pasting a chapter link saves the novel to the library', (
    tester,
  ) async {
    final store = LibraryStore();
    final s = service({chapter: chapterPage, novel: book}, []);
    addTearDown(s.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddNovelDialog(store: store, service: s),
        ),
      ),
    );
    expect(find.text('Novel or chapter URL'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('add-novel-url')), chapter);
    await tester.tap(find.text('Add to library'));
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(store.novels.single.url, 'https://roliascan.com/manga/sample-novel');
    expect(store.novels.single.firstChapter, first);
  });
}
