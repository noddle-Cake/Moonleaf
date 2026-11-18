import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/novel_service.dart';
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
  }) : _client = client ?? http.Client();

  /// Stores a finished book with its novel.
  final Future<Object?> Function(
    LibraryStore store,
    String url,
    BookMetadata metadata,
    List<int> bytes,
  )
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
  bool _disposed = false;

  DownloadStatus? statusOf(String url) => _status[url];
  bool get busy => _running != null || _queue.isNotEmpty;

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
    if (_running == url && _jobId != null) {
      try {
        await service.cancel(_jobId!);
      } catch (_) {}
    }
  }

  Future<void> _pump() async {
    if (_running != null) return;
    while (_queue.isNotEmpty && !_disposed) {
      final url = _queue.removeAt(0);
      _running = url;
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
    final cover = fetchCovers ? await _cover(novel.coverUrl) : null;
    final id = await service.extract(
      url: novel.url,
      title: novel.title,
      author: novel.author.isEmpty ? 'Unknown author' : novel.author,
      chapterUrl: novel.firstChapter,
      cover: cover,
    );
    _jobId = id;
    while (!_disposed) {
      final job = await service.job(id);
      if (_disposed) return;
      if (job.status == 'complete') break;
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
    await keep(store, url, novel.metadata, bytes);
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
