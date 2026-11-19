import 'dart:convert';
import 'dart:typed_data';

import '../data/site_extractors.dart';
import '../reader/book_files.dart' as files;

/// The folder holding a novel's downloaded chapters.
String chapterFolder(String novelUrl) {
  var a = 0x811c9dc5, b = 0x050c5d1f;
  for (final unit in novelUrl.codeUnits) {
    a = ((a ^ unit) * 0x01000193) & 0xFFFFFFFF;
    b = ((b ^ unit) * 0x01000193) & 0xFFFFFFFF;
  }
  return 'chapters-${a.toRadixString(36)}${b.toRadixString(36)}';
}

/// Where a [ChapterStore] keeps its files.
abstract class ChapterFiles {
  Future<void> write(String name, Uint8List bytes);
  Future<Uint8List?> read(String name);
  Future<void> deleteAll();
}

/// App storage on the device (memory on the web).
class DeviceChapterFiles implements ChapterFiles {
  DeviceChapterFiles(this.folder);
  final String folder;
  @override
  Future<void> write(String name, Uint8List bytes) =>
      files.saveData(folder, name, bytes);
  @override
  Future<Uint8List?> read(String name) => files.readData(folder, name);
  @override
  Future<void> deleteAll() => files.deleteData(folder);
}

/// Memory only, for tests.
class MemoryChapterFiles implements ChapterFiles {
  final data = <String, Uint8List>{};
  @override
  Future<void> write(String name, Uint8List bytes) async => data[name] = bytes;
  @override
  Future<Uint8List?> read(String name) async => data[name];
  @override
  Future<void> deleteAll() async => data.clear();
}

/// A novel's downloaded chapters, in reading order, with each chapter's link
/// and Next link. Updates start from the last chapter instead of chapter 1,
/// and interrupted downloads continue where they stopped.
class ChapterStore {
  ChapterStore(this.files);
  final ChapterFiles files;
  List<String>? _order;
  bool _done = false, _prefixDone = false;
  String? _head;

  static String _name(String url) {
    // FNV-1a, kept within 32 bits so it's exact on the web too.
    var hash = 0x811c9dc5;
    for (final unit in url.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    return 'c-${hash.toRadixString(36)}-${url.length}.json';
  }

  Future<List<String>> _load() async {
    if (_order case final order?) return order;
    try {
      final raw = await files.read('index.json');
      if (raw != null) {
        final json = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
        _done = json['done'] as bool? ?? false;
        _head = json['head'] as String?;
        _prefixDone = json['prefixDone'] as bool? ?? false;
        return _order = List<String>.from(json['order'] as List);
      }
    } catch (_) {}
    _done = false;
    _head = null;
    _prefixDone = false;
    return _order = [];
  }

  Future<void> _saveIndex() => files.write(
    'index.json',
    Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'order': _order,
          'done': _done,
          'head': _head,
          'prefixDone': _prefixDone,
        }),
      ),
    ),
  );

  /// Chapter links in reading order.
  Future<List<String>> order() async => List.unmodifiable(await _load());

  /// Whether a download reached a chapter with no Next link.
  Future<bool> done() async {
    await _load();
    return _done;
  }

  /// The chapter a download started from when it wasn't chapter 1 (a pasted
  /// chapter link). Chapters before it are fetched after the rest.
  Future<String?> head() async {
    await _load();
    return _head;
  }

  Future<void> setHead(String url) async {
    await _load();
    _head = url;
    await _saveIndex();
  }

  /// Whether the chapters before [head] are all kept.
  Future<bool> prefixDone() async {
    await _load();
    return _head == null || _prefixDone;
  }

  Future<void> finishPrefix() async {
    await _load();
    _prefixDone = true;
    await _saveIndex();
  }

  /// Whether every chapter, before and after [head], is kept.
  Future<bool> complete() async => await done() && await prefixDone();

  Future<int> get length async => (await _load()).length;

  /// Keeps a chapter, after the others or at [at]. A chapter that's already
  /// kept is replaced in place.
  Future<void> add(NovelChapter chapter, {int? at}) async {
    final order = await _load();
    final url = chapter.url.toString();
    await files.write(
      _name(url),
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'url': url,
            'title': chapter.title,
            'content': chapter.content,
            'next': chapter.next?.toString(),
          }),
        ),
      ),
    );
    if (!order.contains(url)) {
      order.insert((at ?? order.length).clamp(0, order.length), url);
    }
    await _saveIndex();
  }

  Future<NovelChapter?> chapter(String url) async {
    try {
      final raw = await files.read(_name(url));
      if (raw == null) return null;
      final json = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      final next = json['next'] as String?;
      return NovelChapter(
        json['title'] as String? ?? '',
        json['content'] as String? ?? '',
        Uri.parse(json['url'] as String),
        next == null ? null : Uri.parse(next),
      );
    } catch (_) {
      return null;
    }
  }

  /// Every kept chapter in order. Chapters whose file is missing are skipped.
  Future<List<NovelChapter>> all() async => [
    for (final url in await _load()) ?await chapter(url),
  ];

  Future<void> finish() async {
    await _load();
    _done = true;
    await _saveIndex();
  }

  Future<void> saveCover(Uint8List bytes) => files.write('cover', bytes);
  Future<Uint8List?> cover() => files.read('cover');

  Future<void> clear() async {
    await files.deleteAll();
    _order = [];
    _done = false;
    _head = null;
    _prefixDone = false;
  }
}
