import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novel_to_epub/data/local_novel_service.dart';
import 'package:novel_to_epub/data/novel_service.dart';
import 'package:novel_to_epub/data/site_extractors.dart';
import 'package:novel_to_epub/reader/epub_document.dart';

const root = 'https://indratranslations.com';
const book = '$root/lantern-keeper/';
const first = '${book}lantern-keeper-chapter-1-the-bell/';
const second = '${book}lantern-keeper-chapter-2-fog/';
String fixture(String name) =>
    File('../tests/fixtures/indra/$name.html').readAsStringSync();

void main() {
  const parser = IndraExtractor();
  final firstUri = Uri.parse(first);
  test('Indra metadata starts at Read Now despite descending contents', () {
    expect(extractorFor(Uri.parse(book)), isA<IndraExtractor>());
    expect(
      extractorFor(Uri.parse(book.replaceFirst('://', '://www.'))),
      isA<IndraExtractor>(),
    );
    final metadata = parser.book(fixture('book'), Uri.parse(book));
    expect(metadata.title, 'The Lantern Keeper');
    expect(metadata.author, 'Indra Team');
    expect(metadata.description, 'A keeper and a bell. A quiet harbor.');
    expect(metadata.firstChapter, first);
    expect(metadata.coverUrl, '$root/cover.jpg');
    expect(parser.isChapter(Uri.parse(book)), isFalse);
    expect(parser.novelFromPath(Uri.parse('$second?x=1')).toString(), book);
    expect(
      () => parser.book('<h1>Not a story</h1>', Uri.parse(book)),
      throwsA(isA<ApiException>()),
    );
  });

  test(
    'Indra preserves displayed order, formatting and visible attribution',
    () {
      final chapter = parser.chapter(fixture('chapter'), firstUri, 1);
      expect(chapter.title, 'Chapter 1: The Bell');
      expect(chapter.next.toString(), second);
      final paragraphs = html.parse(chapter.content).querySelectorAll('p');
      expect(paragraphs.map((p) => p.text), [
        'First paragraph.A bell rang.',
        'Second paragraph.',
        'Translated by Indra Translations.',
        'Third paragraph.',
      ]);
      expect(chapter.content, contains('<em>paragraph</em>'));
      expect(chapter.content, contains('<strong>paragraph</strong>'));
      for (final unwanted in [
        'Hidden',
        'td-reading-probe',
        'advertisement',
        'Comments',
      ]) {
        expect(chapter.content, isNot(contains(unwanted)));
      }
      expect(
        parser.chapter(fixture('final'), Uri.parse(second), 2).next,
        isNull,
      );
    },
  );

  test(
    'Indra rejects empty pages, invalid paragraph order and premium gates',
    () {
      for (final source in [
        '',
        '<h1>404</h1>',
        '<div id="chapter-content-text"> </div>',
        '<div id="chapter-content-text"><span class="td-s-noise">Filler</span></div>',
        '<div id="chapter-content-text"><div class="td-reading-flow"><p data-order="NaN">Text</p></div></div>',
      ]) {
        expect(
          () => parser.chapter(source, firstUri, 1),
          throwsA(isA<ApiException>()),
        );
      }
      expect(
        () => parser.chapter(fixture('premium'), firstUri, 1),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('premium'),
          ),
        ),
      );
    },
  );

  test(
    'Indra navigation stays in this novel and accepts www and slash variants',
    () {
      expect(sameNovel(firstUri, Uri.parse(second)), isTrue);
      expect(
        sameNovel(firstUri, Uri.parse(second.replaceFirst('://', '://www.'))),
        isTrue,
      );
      expect(
        chapterKey(firstUri),
        chapterKey(
          Uri.parse(
            first
                .replaceFirst('://', '://www.')
                .replaceFirst(RegExp(r'/$'), ''),
          ),
        ),
      );
      for (final target in [
        'https://evil.test/lantern-keeper/lantern-keeper-chapter-2-fog/',
        '$root/other/other-chapter-2/',
        '$root/login/',
        'https://indratranslations.com.evil.test/lantern-keeper/lantern-keeper-chapter-2-fog/',
      ]) {
        expect(sameNovel(firstUri, Uri.parse(target)), isFalse);
        expect(
          () => parser.chapter(
            fixture('chapter')
                .replaceFirst('../lantern-keeper-chapter-2-fog/', target),
            firstUri,
            1,
          ),
          throwsA(isA<ApiException>()),
        );
        expect(
          () => parser.book(
            fixture('book').replaceFirst(
              '/lantern-keeper/lantern-keeper-chapter-1-the-bell/',
              target,
            ),
            Uri.parse(book),
          ),
          throwsA(isA<ApiException>()),
        );
      }
      expect(
        () =>
            extractorFor(Uri.parse('https://indratranslations.com.evil.test/')),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test('Indra chapter link detects whole novel and builds EPUB using browser user agent', () async {
    final pages = {
      book: fixture('book'),
      first: fixture('chapter'),
      second: fixture('final'),
    };
    final calls = <String>[];
    final service = LocalNovelService(
      client: MockClient((request) async {
        calls.add(request.url.toString());
        expect(request.headers['user-agent'], 'Mozilla/5.0');
        return http.Response(pages[request.url.toString()]!, 200);
      }),
    );
    addTearDown(service.close);
    final metadata = await service.detect(second);
    expect(metadata.url, book);
    expect(metadata.firstChapter, first);
    final id = await service.extract(
      url: metadata.url,
      title: metadata.title,
      author: metadata.author,
      chapterUrl: metadata.firstChapter,
    );
    ExtractionJob? result;
    for (var i = 0; i < 500; i++) {
      result = await service.job(id);
      if (!result.active) break;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(result!.error, isNull);
    expect(result.status, 'complete');
    expect(result.chapters, 2);
    expect(calls, [book, first, second]);
    final epub = EpubDocument.parse(await service.download(id));
    final text = epub.chapters.map((c) => c.plainText).join();
    expect(text.indexOf('First'), lessThan(text.indexOf('Second')));
    expect(text.indexOf('Second'), lessThan(text.indexOf('Third')));
    expect(text, contains('The end.'));
    expect(text, isNot(contains('Hidden')));
  });
}
