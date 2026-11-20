import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../library/downloads.dart';
import '../library/library_store.dart';

/// Keeps downloads running while the app is in the background, using an
/// Android foreground service with a progress notification.
class BackgroundDownloads {
  BackgroundDownloads(this.downloads, this.store) {
    if (!supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'cancel') await downloads.cancelAll();
    });
    downloads.addListener(_changed);
  }

  static const _channel = MethodChannel('moonleaf/background');
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  final DownloadManager downloads;
  final LibraryStore store;
  bool _shown = false;
  String _last = '';
  DateTime _sent = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _later;

  void _changed() {
    if (!downloads.busy) {
      _later?.cancel();
      if (_shown) {
        _shown = false;
        _last = '';
        _channel.invokeMethod<void>('stop').catchError((Object _) {});
      }
      return;
    }
    // Android limits how often a notification can change.
    final wait = const Duration(seconds: 1) - DateTime.now().difference(_sent);
    _later?.cancel();
    if (wait > Duration.zero) {
      _later = Timer(wait, _changed);
      return;
    }
    final (title, text) = describe(downloads, store);
    if ('$title|$text' == _last) return;
    _last = '$title|$text';
    _sent = DateTime.now();
    _shown = true;
    _channel
        .invokeMethod<bool>('update', {
          'title': title,
          'text': text,
          'done': 0,
          'total': 0,
        })
        .catchError((Object _) => false);
  }

  /// The notification's title and text for the current downloads.
  @visibleForTesting
  static (String, String) describe(
    DownloadManager downloads,
    LibraryStore store,
  ) {
    final url = downloads.current;
    final novel = url == null ? null : store.find(url);
    final status = url == null ? null : downloads.statusOf(url);
    final waiting = downloads.queued;
    final title = novel == null
        ? 'Downloading books'
        : 'Downloading ${novel.title}';
    final parts = [
      if (status != null && status.chapters > 0)
        '${status.chapters} ${status.chapters == 1 ? 'chapter' : 'chapters'}',
      if (status != null && status.chapterTitle.isNotEmpty) status.chapterTitle,
      if (waiting > 0)
        '$waiting more ${waiting == 1 ? 'book' : 'books'} waiting',
    ];
    return (title, parts.isEmpty ? 'Starting…' : parts.join(' · '));
  }

  void dispose() {
    _later?.cancel();
    if (!supported) return;
    downloads.removeListener(_changed);
    _channel.setMethodCallHandler(null);
    if (_shown) _channel.invokeMethod<void>('stop').catchError((Object _) {});
  }
}
