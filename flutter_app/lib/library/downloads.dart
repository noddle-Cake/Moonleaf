import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/chapter_titles.dart';
import '../data/epub_writer.dart';
import '../data/local_novel_service.dart';
import '../data/novel_service.dart';
import '../data/site_extractors.dart';
import 'chapter_store.dart';
import 'library_store.dart';
import 'reading.dart';

enum DownloadPhase { queued, running, failed }

class DownloadStatus {
  const DownloadStatus(
    this.phase, {
    this.chapters = 0,
    this.chapterTitle = '',
    this.error,
  });
  final DownloadPhase phase;
  final int chapters;
  final String chapterTitle;
  final String? error;
  bool get active => phase != DownloadPhase.failed;
}

/// Downloads library novels into EPUBs in the background, one at a time.
///
/// Adding a novel queues it here, so the book is ready to read without a
/// separate export step. Finished books are kept with the novel.
class DownloadManager extends ChangeNotifier {
  DownloadManager({
    required this.store,
    required this.service,
    http.Client? client,
    this.poll = const Duration(milliseconds: 800),
    this.fetchCovers = true,
    this.keep = keepEpub,
    ChapterStore Function(String url)? chapters,
  }) : _client = client ?? http.Client(),
       chapters = chapters ?? _deviceChapters;

  static ChapterStore _deviceChapters(String url) =>
      ChapterStore(DeviceChapterFiles(chapterFolder(url)));

  /// Each novel's downloaded chapters.
  final ChapterStore Function(String url) chapters;

  /// Stores a finished book with its novel.
  final Future<Object?> Function(
    LibraryStore store,
    String url,
    BookMetadata metadata,
    List<int> bytes, {
    int? chapters,
  })
  keep;
  final LibraryStore store;
  final NovelService service;
  final Duration poll;

  /// Whether to embed the source's cover. The web API fetches covers itself.
  final bool fetchCovers;
  final http.Client _client;
  final _status = <String, DownloadStatus>{};
  final _queue = <String>[];
  String? _running, _jobId;
  bool _disposed = false, _cancelRunning = false;

  DownloadStatus? statusOf(String url) => _status[url];
  bool get busy => _running != null || _queue.isNotEmpty;

  /// Queues every novel from a website that has a kept book, to collect new
  /// chapters.
  int checkAll() {
    var queued = 0;
    for (final n in store.novels) {
      if (!n.isLocal && n.epub != null && !(_status[n.url]?.active ?? false)) {
        enqueue(n.url);
        queued++;
      }
    }
    return queued;
  }

  /// Queues a novel. Already queued or running novels are left alone.
  void enqueue(String url) {
    if (_status[url]?.active ?? false) return;
    _status[url] = const DownloadStatus(DownloadPhase.queued);
    _queue.add(url);
    notifyListeners();
    unawaited(_pump());
  }

  Future<void> cancel(String url) async {
    if (_queue.remove(url)) {
      _status.remove(url);
      notifyListeners();
      return;
    }
    if (_running == url) _cancelRunning = true;
    if (_running == url && _jobId != null) {
      try {
        await service.cancel(_jobId!);
      } catch (_) {}
    }
  }

  /// Queues books whose download stopped part way, such as when the app was
  /// closed, so they continue from their last chapter.
  Future<int> resumeUnfinished() async {
    if (service is! ChapterSource) return 0;
    var queued = 0;
    for (final n in store.novels) {
      if (n.isLocal || _official(n)) continue;
      final kept = chapters(n.url);
      if (await kept.length > 0 && !await kept.done()) {
        enqueue(n.url);
        queued++;
      }
    }
    return queued;
  }

  static bool _official(LibraryNovel novel) {
    try {
      return extractorFor(Uri.parse(novel.url)).officialEpub;
    } catch (_) {
      return false;
    }
  }

  Future<void> _pump() async {
    if (_running != null) return;
    while (_queue.isNotEmpty && !_disposed) {
      final url = _queue.removeAt(0);
      _running = url;
      _cancelRunning = false;
      try {
        await _download(url);
        _status.remove(url);
      } catch (error) {
        if (_disposed) return;
        _status[url] = DownloadStatus(
          DownloadPhase.failed,
          error: error is ApiException
              ? error.message
              : 'The download stopped. Check your connection and try again.',
        );
      } finally {
        _running = null;
        _jobId = null;
        if (!_disposed) notifyListeners();
      }
    }
  }

  Future<void> _download(String url) async {
    final novel = store.find(url);
    if (novel == null) return;
    if (novel.firstChapter.isEmpty) {
      throw const ApiException(
        "This novel's first chapter couldn't be found. Use Customize EPUB to set it.",
      );
    }
    _status[url] = const DownloadStatus(DownloadPhase.running);
    notifyListeners();
    if (service case final ChapterSource source when !_official(novel)) {
      return _downloadChapters(novel, source);
    }
    final cover = fetchCovers ? await _cover(novel.coverUrl) : null;
    final id = await service.extract(
      url: novel.url,
      title: novel.title,
      author: novel.author.isEmpty ? 'Unknown author' : novel.author,
      chapterUrl: novel.firstChapter,
      cover: cover,
    );
    _jobId = id;
    var chapters = 0;
    while (!_disposed) {
      final job = await service.job(id);
      if (_disposed) return;
      if (job.status == 'complete') {
        chapters = job.chapters;
        break;
      }
      if (!job.active) {
        throw ApiException(
          job.status == 'cancelled'
              ? 'Download cancelled.'
              : job.error ?? 'The download failed.',
        );
      }
      _status[url] = DownloadStatus(
        DownloadPhase.running,
        chapters: job.chapters,
        chapterTitle: job.chapterTitle,
      );
      notifyListeners();
      await Future<void>.delayed(poll);
    }
    if (_disposed) return;
    final bytes = await service.download(id);
    if (_disposed) return;
    await keep(
      store,
      url,
      novel.metadata,
      bytes,
      chapters: chapters > 0 ? chapters : null,
    );
  }

  void _progress(int count, String title) {
    _status[_running!] = DownloadStatus(
      DownloadPhase.running,
      chapters: count,
      chapterTitle: title,
    );
    notifyListeners();
  }

  void _stopIfCancelled() {
    if (_disposed) throw const ApiException('The app closed.');
    if (_cancelRunning) throw const ApiException('Download cancelled.');
  }

  /// Downloads chapter by chapter, keeping each one, so only chapters after
  /// the last kept one are fetched. An update with no new chapters costs one
  /// page: the last chapter, checked for a Next link.
  Future<void> _downloadChapters(
    LibraryNovel novel,
    ChapterSource source,
  ) async {
    final kept = chapters(novel.url);
    final first = Uri.parse(novel.firstChapter).removeFragment();
    var order = await kept.order();
    Uri? next;
    if (order.isEmpty) {
      next = first;
    } else {
      final last = await kept.chapter(order.last);
      if (last?.next case final resume?) {
        // An interrupted download: carry on from the next chapter.
        next = resume;
      } else {
        _progress(order.length, 'Checking for new chapters');
        final lastUrl = Uri.parse(order.last);
        try {
          final again = await source.fetchChapter(lastUrl, order.length);
          _stopIfCancelled();
          next = again.next;
          if (next != null) await kept.add(again);
        } on ApiException catch (error) {
          // The last chapter is gone (deleted or renumbered): start over.
          if (error.statusCode != 404 && error.statusCode != 410) rethrow;
          await kept.clear();
          order = const [];
          next = first;
        }
      }
    }
    final visited = order.toSet();
    var fetched = 0;
    while (next != null) {
      _stopIfCancelled();
      final current = next.removeFragment();
      if (!sameNovel(first, current)) {
        throw const ApiException(
          'Stopped because the next link points outside this novel.',
        );
      }
      if (!visited.add(current.toString())) {
        throw const ApiException(
          'The site has a repeated chapter link. Extraction stopped to avoid a loop.',
        );
      }
      final pause = source.pauseFor(current);
      if (fetched > 0 && pause > Duration.zero) {
        await Future<void>.delayed(pause);
        _stopIfCancelled();
      }
      final number = visited.length;
      final chapter = await source.fetchChapter(current, number);
      _stopIfCancelled();
      await kept.add(chapter);
      fetched++;
      _progress(number, cleanChapterTitle(chapter.title, novel.title, number));
      next = chapter.next;
    }
    await kept.finish();
    if (fetched == 0 && novel.epub != null) return;
    await _build(novel, kept);
  }

  /// Packages the kept chapters as the novel's EPUB.
  Future<void> _build(LibraryNovel novel, ChapterStore kept) async {
    final all = await kept.all();
    if (all.isEmpty) throw const ApiException('No chapters were found.');
    var cover = await kept.cover();
    if (cover == null && fetchCovers) {
      cover = await _cover(novel.coverUrl);
      if (cover != null) await kept.saveCover(cover);
    }
    _stopIfCancelled();
    final book = EpubBook(
      novel.title,
      novel.author.isEmpty ? 'Unknown author' : novel.author,
      [
        for (var i = 0; i < all.length; i++)
          NovelChapter(
            cleanChapterTitle(all[i].title, novel.title, i + 1),
            all[i].content,
            all[i].url,
            all[i].next,
          ),
      ],
      cover,
    );
    final bytes = await compute(buildEpub, book);
    if (_disposed) return;
    await keep(store, novel.url, novel.metadata, bytes, chapters: all.length);
  }

  /// The source cover as PNG or JPEG bytes, or null. Other formats (such as
  /// WebP) are re-encoded as PNG so every EPUB reader can show them.
  Future<Uint8List?> _cover(String? url) async {
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) return null;
    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 20));
      final bytes = response.bodyBytes;
      if (response.statusCode != 200 || bytes.length > 8 << 20) return null;
      final png = bytes.length > 8 && bytes[0] == 0x89 && bytes[1] == 0x50;
      final jpg = bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8;
      if (png || jpg) return bytes;
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      codec.dispose();
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    final job = _jobId;
    if (job != null) service.cancel(job).catchError((Object _) {});
    _client.close();
    super.dispose();
  }
}
