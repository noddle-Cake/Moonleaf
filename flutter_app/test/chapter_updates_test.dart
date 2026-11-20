import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_to_epub/data/local_novel_service.dart';
import 'package:novel_to_epub/data/novel_service.dart';
import 'package:novel_to_epub/data/site_extractors.dart';
import 'package:novel_to_epub/library/chapter_store.dart';
import 'package:novel_to_epub/library/downloads.dart';
import 'package:novel_to_epub/library/library_store.dart';
import 'package:novel_to_epub/platform/background.dart';
import 'package:novel_to_epub/reader/epub_document.dart';

const base = 'https://www.royalroad.com/fiction/7/tide/chapter';
String ch(int n) => '$base/$n/part-$n';

/// A site with [count] chapters linked by Next, logging every page fetched.
class FakeSite implements NovelService, ChapterSource {
  FakeSite(this.count);
  int count;
  final fetched = <int>[];
  final failOnce = <int>{};
  final gone = <int>{};

  @override
  Future<NovelChapter> fetchChapter(Uri url, int number) async {
    final n = int.parse(url.pathSegments[4]);
    fetched.add(n);
    if (gone.contains(n)) {
      throw const ApiException('Not found', statusCode: 404);
    }
    if (failOnce.remove(n)) {
      throw const ApiException('Server error', statusCode: 500);
    }
    return NovelChapter(
      'Part $n',
      '<p>Text of part $n.</p>',
      url,
      n < count ? Uri.parse(ch(n + 1)) : null,
    );
  }

  @override
  Duration pauseFor(Uri url) => Duration.zero;
  @override
  Future<String> extract({
    required String url,
    required String title,
    required String author,
    required String chapterUrl,
    Uint8List? cover,
  }) => throw UnimplementedError('The chapter path should be used.');
  @override
  Future<ExtractionJob> job(String id) => throw UnimplementedError();
  @override
  Future<Uint8List> download(String id) => throw UnimplementedError();
  @override
  Future<void> cancel(String id) async {}
  @override
  Future<BookMetadata> detect(String url) => throw UnimplementedError();
  @override
  void close() {}
}

void main() {
  late FakeSite site;
  late LibraryStore library;
  late DownloadManager downloads;
  late Map<String, ChapterStore> stores;
  final kept = <List<String>>[];
  final starts = <String?>[];

  final novel = LibraryNovel(
    url: 'https://www.royalroad.com/fiction/7/tide',
    title: 'Tide',
    author: 'A. Writer',
    firstChapter: ch(1),
    addedAt: DateTime(2026),
  );

  DownloadManager manager() => DownloadManager(
    store: library,
    service: site,
    poll: Duration.zero,
    fetchCovers: false,
    chapters: (url) =>
        stores.putIfAbsent(url, () => ChapterStore(MemoryChapterFiles())),
    keep: (store, url, metadata, bytes, {chapters, since, startAt}) async {
      final doc = EpubDocument.parse(Uint8List.fromList(bytes));
      kept.add([for (final t in doc.toc) t.title]);
      starts.add(startAt);
      await store.attachEpub(
        url,
        'book',
        metadata,
        chapters: chapters,
        since: since,
      );
      return null;
    },
  );

  Future<void> run(String url) async {
    downloads.enqueue(url);
    while (downloads.busy) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  setUp(() {
    site = FakeSite(3);
    library = LibraryStore(novels: [novel]);
    stores = {};
    kept.clear();
    starts.clear();
    downloads = manager();
  });
  tearDown(() => downloads.dispose());

  test('downloads every chapter once and names them', () async {
    await run(novel.url);
    expect(site.fetched, [1, 2, 3]);
    // Saved after the first chapter, so reading can start, then complete.
    expect(kept.first, ['Chapter 1: Part 1']);
    expect(kept, hasLength(2));
    expect(kept.last, [
      'Chapter 1: Part 1',
      'Chapter 2: Part 2',
      'Chapter 3: Part 3',
    ]);
    expect(await stores[novel.url]!.done(), isTrue);
  });

  test('an update with nothing new loads only the last chapter', () async {
    await run(novel.url);
    site.fetched.clear();
    final saves = kept.length;
    await run(novel.url);
    expect(site.fetched, [3]);
    expect(kept, hasLength(saves), reason: 'the book is not rebuilt');
  });

  test('an update fetches only the new chapters and adds them', () async {
    await run(novel.url);
    site
      ..count = 5
      ..fetched.clear();
    await run(novel.url);
    expect(site.fetched, [3, 4, 5]);
    expect(kept.last, hasLength(5));
    expect(kept.last.last, 'Chapter 5: Part 5');
    expect(library.find(novel.url)!.newChapters, 2);
  });

  test('an interrupted download continues where it stopped', () async {
    site.failOnce.add(3);
    await run(novel.url);
    expect(downloads.statusOf(novel.url)?.phase, DownloadPhase.failed);
    // What arrived before the failure can already be read.
    expect(kept.last, hasLength(1));
    site.fetched.clear();
    await run(novel.url);
    expect(site.fetched, [3]);
    expect(kept.last, hasLength(3));
  });

  test('a deleted last chapter starts the book over', () async {
    await run(novel.url);
    site
      ..gone.add(3)
      ..count = 2
      ..fetched.clear();
    await run(novel.url);
    expect(site.fetched, [3, 1, 2]);
    expect(kept.last, hasLength(2));
  });

  test('downloads stopped by closing the app resume on launch', () async {
    site.failOnce.add(2);
    await run(novel.url);
    expect(kept.last, hasLength(1));
    downloads.dispose();
    downloads = manager();
    expect(await downloads.resumeUnfinished(), 1);
    while (downloads.busy) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(kept.last, hasLength(3));
    // A finished book isn't queued again.
    expect(await downloads.resumeUnfinished(), 0);
  });

  group('a pasted chapter link', () {
    Future<void> runFrom(String from) async {
      downloads.enqueue(novel.url, from: from);
      while (downloads.busy) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    test('starts at that chapter, then fetches the earlier ones', () async {
      site.count = 5;
      await runFrom(ch(3));
      expect(site.fetched, [3, 4, 5, 1, 2]);
      // Readable right away, unnumbered until the earlier chapters arrive.
      expect(kept.first, ['Part 3']);
      expect(kept.last, [for (var i = 1; i <= 5; i++) 'Chapter $i: Part $i']);
      expect(starts.toSet(), {ch(3)});
      expect(await stores[novel.url]!.complete(), isTrue);
      expect(await downloads.resumeUnfinished(), 0);
    });

    test('resumes the earlier chapters after an interruption', () async {
      site
        ..count = 5
        ..failOnce.add(2);
      await runFrom(ch(3));
      expect(await stores[novel.url]!.complete(), isFalse);
      site.fetched.clear();
      expect(await downloads.resumeUnfinished(), 1);
      while (downloads.busy) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      // The newest chapter is checked once, then only chapter 2 is missing.
      expect(site.fetched, [5, 2]);
      expect(kept.last, hasLength(5));
      expect(kept.last[1], 'Chapter 2: Part 2');
    });

    test('a link to chapter 1 is an ordinary download', () async {
      await runFrom(ch(1));
      expect(site.fetched, [1, 2, 3]);
      expect(await stores[novel.url]!.head(), isNull);
    });
  });

  test('the background notification describes the download', () async {
    final other = LibraryNovel(
      url: 'https://www.royalroad.com/fiction/8/sea',
      title: 'Sea',
      author: '',
      firstChapter: 'https://www.royalroad.com/fiction/8/sea/chapter/1/a',
      addedAt: DateTime(2026),
    );
    library = LibraryStore(novels: [novel, other]);
    downloads.dispose();
    downloads = manager();
    final texts = <(String, String)>[];
    downloads.addListener(() {
      if (downloads.current != null) {
        texts.add(BackgroundDownloads.describe(downloads, library));
      }
    });
    downloads
      ..enqueue(novel.url)
      ..enqueue(other.url);
    await Future<void>.delayed(Duration.zero);
    await downloads.cancelAll();
    while (downloads.busy) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(texts.first.$1, 'Downloading Tide');
    expect(texts.any((t) => t.$2.contains('1 more book waiting')), isTrue);
    expect(downloads.statusOf(other.url), isNull, reason: 'removed from queue');
    expect(site.fetched.length, lessThan(3), reason: 'stopped early');
  });
}
