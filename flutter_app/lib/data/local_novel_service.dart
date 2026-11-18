import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

import 'chapter_titles.dart';
import 'epub_writer.dart';
import 'novel_service.dart';
import 'page_loader.dart';
import 'site_extractors.dart';

class _LocalJob {
  _LocalJob(this.id);
  final String id;
  String status = 'queued';
  String title = '';
  String? error;
  int chapters = 0;
  Uint8List? bytes;
  bool get cancelled => status == 'cancelled';
  ExtractionJob get snapshot => ExtractionJob(
    id: id,
    status: status,
    chapters: chapters,
    chapterTitle: title,
    error: error,
  );
}

/// Installed apps fetch and package books on the device. No API server is used.
class LocalNovelService implements NovelService {
  LocalNovelService({http.Client? client, this.browser, this.politeDelay})
    : _client = client ?? http.Client();
  final http.Client _client;

  /// Loads pages for sites with a human check. Without it those sites
  /// report that they need the app's built-in browser.
  final PageLoader? browser;

  /// Pause between chapter pages loaded in the browser, to read at a gentle
  /// pace. Defaults to 1.5 seconds.
  final Duration? politeDelay;
  final _jobs = <String, _LocalJob>{};
  int _sequence = 0;
  bool _closed = false;

  Future<String> _fetch(Uri uri) async {
    final parser = extractorFor(uri);
    uri = parser.fetchUrl(uri);
    if (parser.needsBrowser) {
      final loader = browser;
      if (loader == null) {
        throw ApiException(
          '${parser.name} asks visitors to confirm they’re human, so it needs '
          'Moonleaf’s built-in browser. It’s available in the Android, iOS and '
          'macOS apps.',
        );
      }
      return loader.load(uri);
    }
    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw ApiException(
          'The novel site returned HTTP ${response.statusCode}. Try again later or check that the chapter is publicly readable.',
        );
      }
      return response.body;
    } on TimeoutException {
      throw const ApiException(
        'The novel site took too long to respond. Try again.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Cannot reach the novel site. Check your internet connection.',
      );
    }
  }

  @override
  Future<BookMetadata> detect(String url) async {
    var uri = Uri.parse(url.trim()).removeFragment();
    final parser = extractorFor(uri);
    // A chapter link works too: find its novel and download from chapter 1.
    if (parser.isChapter(uri)) {
      final novel =
          parser.novelFromPath(uri) ??
          parser.novelFromChapter(await _fetch(uri), uri);
      if (novel == null || parser.isChapter(novel)) {
        throw const ApiException(
          "Couldn't find the novel page for this chapter. Paste the novel's main page instead.",
        );
      }
      extractorFor(novel);
      uri = novel;
    }
    final metadata = parser
        .book(await _fetch(uri), uri)
        .withUrl(uri.toString());
    if (metadata.firstChapter.isNotEmpty) {
      final first = Uri.parse(metadata.firstChapter);
      if (extractorFor(first).runtimeType != parser.runtimeType ||
          !sameNovel(first, first)) {
        throw const ApiException(
          'The site returned an invalid first chapter link.',
        );
      }
    }
    return metadata;
  }

  @override
  Future<String> extract({
    required String url,
    required String title,
    required String author,
    required String chapterUrl,
    Uint8List? cover,
  }) async {
    if (_closed) {
      throw const ApiException('The app has closed this extraction session.');
    }
    if (_jobs.values.any((j) => j.snapshot.active)) {
      throw const ApiException('Wait for the current extraction to finish.');
    }
    final parser = extractorFor(Uri.parse(url));
    final first = Uri.parse(chapterUrl).removeFragment();
    if (extractorFor(first).runtimeType != parser.runtimeType ||
        !sameNovel(first, first)) {
      throw const ApiException(
        'Choose a chapter URL from the same supported novel site.',
      );
    }
    if (title.trim().isEmpty) throw const ApiException('Enter a book title.');
    _jobs.clear();
    final job = _LocalJob('local-${++_sequence}');
    _jobs[job.id] = job;
    unawaited(
      parser.officialEpub
          ? _runOfficial(job, parser, first)
          : _run(job, parser, first, title, author, cover),
    );
    return job.id;
  }

  /// Sites that publish their own EPUB: download that file as the book.
  Future<void> _runOfficial(
    _LocalJob job,
    SiteExtractor parser,
    Uri page,
  ) async {
    job.status = 'running';
    try {
      final link = parser.epubLink(await _fetch(page), page);
      if (link == null ||
          extractorFor(link).runtimeType != parser.runtimeType) {
        throw ApiException(
          '${parser.name} didn’t offer an EPUB for this book.',
        );
      }
      job.title = 'Downloading the EPUB';
      final bytes = await _fetchFile(link);
      if (_closed || job.cancelled) return;
      final archive = ZipDecoder().decodeBytes(bytes);
      final mime = archive.findFile('mimetype');
      if (mime == null ||
          !utf8
              .decode(mime.content as List<int>)
              .startsWith('application/epub+zip')) {
        throw ApiException('${parser.name} sent a file that isn’t an EPUB.');
      }
      job.chapters = archive.files
          .where((f) => RegExp(r'\.x?html?$').hasMatch(f.name))
          .length;
      job.bytes = bytes;
      job.status = 'complete';
    } catch (error) {
      if (_closed || job.cancelled) return;
      job.error = error is ApiException
          ? error.message
          : 'Could not download this book: $error';
      job.status = 'failed';
    }
  }

  /// Downloads a file, following an HTML "your download is starting" page.
  Future<Uint8List> _fetchFile(Uri uri) async {
    for (var hop = 0; hop < 3; hop++) {
      extractorFor(uri);
      final http.Response response;
      try {
        response = await _client.get(uri).timeout(const Duration(seconds: 90));
      } on TimeoutException {
        throw const ApiException('The download took too long. Try again.');
      } on http.ClientException {
        throw const ApiException(
          'Cannot reach the site. Check your internet connection.',
        );
      }
      if (response.statusCode != 200) {
        throw ApiException(
          'The site returned HTTP ${response.statusCode} for the EPUB. Try again later.',
        );
      }
      final type = response.headers['content-type'] ?? '';
      if (!type.contains('html')) return response.bodyBytes;
      final refresh = RegExp(
        r'''http-equiv=["']refresh["'][^>]*url=([^"'>\s]+)''',
        caseSensitive: false,
      ).firstMatch(response.body);
      final next = refresh == null
          ? null
          : resolveLink(uri, refresh[1]!.replaceAll('&amp;', '&'));
      if (next == null) break;
      uri = next;
    }
    throw const ApiException('The site sent a web page instead of the EPUB.');
  }

  Future<void> _run(
    _LocalJob job,
    SiteExtractor parser,
    Uri first,
    String title,
    String author,
    Uint8List? cover,
  ) async {
    final chapters = <NovelChapter>[];
    final visited = <String>{};
    Uri? current = first;
    job.status = 'running';
    try {
      while (current != null) {
        if (_closed || job.cancelled) return;
        if (!sameNovel(first, current)) {
          throw const ApiException(
            'Stopped because the next link points outside this novel.',
          );
        }
        if (!visited.add(current.removeFragment().toString())) {
          throw const ApiException(
            'The site has a repeated chapter link. Extraction stopped to avoid a loop.',
          );
        }
        if (parser.needsBrowser && chapters.isNotEmpty) {
          await Future<void>.delayed(
            politeDelay ?? const Duration(milliseconds: 1500),
          );
          if (_closed || job.cancelled) return;
        }
        final source = await _fetch(current);
        if (_closed || job.cancelled) return;
        final chapter = parser.chapter(source, current, chapters.length + 1);
        chapters.add(chapter);
        job.chapters = chapters.length;
        job.title = cleanChapterTitle(chapter.title, title, chapters.length);
        current = chapter.next;
      }
      if (_closed || job.cancelled) return;
      final named = [
        for (var i = 0; i < chapters.length; i++)
          NovelChapter(
            cleanChapterTitle(chapters[i].title, title, i + 1),
            chapters[i].content,
            chapters[i].url,
            chapters[i].next,
          ),
      ];
      final bytes = await compute(
        buildEpub,
        EpubBook(title, author, named, cover),
      );
      if (_closed || job.cancelled) return;
      job.bytes = bytes;
      job.status = 'complete';
    } catch (error) {
      if (_closed || job.cancelled) return;
      job.error = error is ApiException
          ? error.message
          : 'Could not create this book: $error';
      job.status = 'failed';
    }
  }

  _LocalJob _get(String id) =>
      _jobs[id] ??
      (throw const ApiException(
        'This extraction is no longer available.',
        statusCode: 404,
      ));
  @override
  Future<ExtractionJob> job(String id) async => _get(id).snapshot;
  @override
  Future<void> cancel(String id) async {
    final job = _get(id);
    if (job.snapshot.active) job.status = 'cancelled';
  }

  @override
  Future<Uint8List> download(String id) async =>
      _get(id).bytes ??
      (throw const ApiException('The EPUB is not ready yet.'));
  @override
  void close() {
    _closed = true;
    for (final job in _jobs.values) {
      if (job.snapshot.active) job.status = 'cancelled';
    }
    _client.close();
    _jobs.clear();
  }
}
