import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_to_epub/data/novel_service.dart';
import 'package:novel_to_epub/library/downloads.dart';
import 'package:novel_to_epub/library/library_store.dart';

/// A service whose jobs advance one chapter per poll.
class FakeService implements NovelService {
  FakeService({this.chapters = 3, this.failFor = const {}});
  final int chapters;
  final Set<String> failFor;
  final started = <String>[];
  final _progress = <String, int>{};
  final _urls = <String, String>{};
  int active = 0, maxActive = 0;

  @override
  Future<String> extract({
    required String url,
    required String title,
    required String author,
    required String chapterUrl,
    Uint8List? cover,
  }) async {
    started.add(url);
    final id = 'job-${started.length}';
    _progress[id] = 0;
    _urls[id] = url;
    active++;
    maxActive = active > maxActive ? active : maxActive;
    return id;
  }

  @override
  Future<ExtractionJob> job(String id) async {
    final done = _progress[id] = _progress[id]! + 1;
    if (failFor.contains(_urls[id])) {
      active--;
      return ExtractionJob(id: id, status: 'failed', error: 'Site said no.');
    }
    if (done > chapters) {
      active--;
      return ExtractionJob(id: id, status: 'complete', chapters: chapters);
    }
    return ExtractionJob(
      id: id,
      status: 'running',
      chapters: done,
      chapterTitle: 'Chapter $done',
    );
  }

  @override
  Future<Uint8List> download(String id) async => Uint8List.fromList([1, 2]);
  @override
  Future<void> cancel(String id) async {}
  @override
  Future<BookMetadata> detect(String url) => throw UnimplementedError();
  @override
  void close() {}
}

LibraryNovel novel(String slug, {String first = 'https://x/ch1'}) =>
    LibraryNovel(
      url: 'https://www.royalroad.com/fiction/1/$slug',
      title: slug,
      author: '',
      firstChapter: first,
      addedAt: DateTime(2026),
    );

void main() {
  test('downloads one book at a time and keeps each one', () async {
    final a = novel('a'), b = novel('b');
    final store = LibraryStore(novels: [a, b]);
    final service = FakeService();
    final kept = <String, int>{};
    final seen = <String>[];
    final downloads = DownloadManager(
      store: store,
      service: service,
      poll: Duration.zero,
      fetchCovers: false,
      keep: (store, url, metadata, bytes, {chapters, since, startAt}) async {
        kept[url] = chapters ?? -1;
        return null;
      },
    );
    addTearDown(downloads.dispose);
    downloads.addListener(() {
      final s = downloads.statusOf(a.url);
      if (s != null && s.phase == DownloadPhase.running && s.chapters > 0) {
        seen.add(s.chapterTitle);
      }
    });
    downloads
      ..enqueue(a.url)
      ..enqueue(b.url)
      ..enqueue(a.url); // Already queued: ignored.
    expect(downloads.statusOf(b.url)?.phase, DownloadPhase.queued);
    while (downloads.busy) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(service.started, [a.url, b.url]);
    expect(service.maxActive, 1);
    expect(kept, {a.url: 3, b.url: 3});
    expect(seen, containsAllInOrder(['Chapter 1', 'Chapter 2', 'Chapter 3']));
    expect(downloads.statusOf(a.url), isNull);
  });

  test('a failed download reports why and can be retried', () async {
    final a = novel('a');
    final store = LibraryStore(novels: [a]);
    final service = FakeService(failFor: {a.url});
    final downloads = DownloadManager(
      store: store,
      service: service,
      poll: Duration.zero,
      fetchCovers: false,
      keep: (_, _, _, _, {chapters, since, startAt}) async => null,
    );
    addTearDown(downloads.dispose);
    downloads.enqueue(a.url);
    while (downloads.busy) {
      await Future<void>.delayed(Duration.zero);
    }
    final status = downloads.statusOf(a.url)!;
    expect(status.phase, DownloadPhase.failed);
    expect(status.error, 'Site said no.');
    downloads.enqueue(a.url);
    expect(downloads.statusOf(a.url)?.phase, isNot(DownloadPhase.failed));
    expect(service.started, hasLength(2));
  });

  test('a novel without a first chapter fails with a clear message', () async {
    final a = novel('a', first: '');
    final downloads = DownloadManager(
      store: LibraryStore(novels: [a]),
      service: FakeService(),
      poll: Duration.zero,
      fetchCovers: false,
      keep: (_, _, _, _, {chapters, since, startAt}) async => null,
    );
    addTearDown(downloads.dispose);
    downloads.enqueue(a.url);
    while (downloads.busy) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(downloads.statusOf(a.url)?.error, contains('first chapter'));
  });
}
