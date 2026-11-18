import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/novel_service.dart';
import '../data/site_extractors.dart';

enum AppAppearance { system, light, dark, ereaderLight, ereaderDark }

const shelves = ['Plan to read', 'Reading', 'Completed'];

class LibraryNovel {
  const LibraryNovel({
    required this.url,
    required this.title,
    required this.author,
    required this.firstChapter,
    required this.addedAt,
    this.coverUrl,
    this.description,
    this.shelf = 'Plan to read',
    this.openedAt,
    this.epub,
    this.coverFile,
    this.progress,
  });
  final String url, title, author, firstChapter, shelf;
  final String? coverUrl, description;
  final DateTime addedAt;
  final DateTime? openedAt;

  /// Key of the EPUB stored in the app for the in-app reader.
  final String? epub;

  /// Key of a cover image stored in the app (imported EPUBs).
  final String? coverFile;

  /// Reading progress from 0 to 1, once the book has been opened.
  final double? progress;

  /// Imported EPUB files use `epub:` identifiers instead of web addresses.
  bool get isLocal => url.startsWith('epub:');
  String get source {
    if (isLocal) return 'EPUB file';
    try {
      return extractorFor(Uri.parse(url)).name;
    } catch (_) {
      return Uri.tryParse(url)?.host ?? 'Web';
    }
  }

  BookMetadata get metadata => BookMetadata(
    title: title,
    author: author,
    firstChapter: firstChapter,
    coverUrl: coverUrl,
    description: description,
  );
  LibraryNovel copyWith({
    String? shelf,
    DateTime? openedAt,
    String? epub,
    double? progress,
  }) => LibraryNovel(
    url: url,
    title: title,
    author: author,
    firstChapter: firstChapter,
    addedAt: addedAt,
    coverUrl: coverUrl,
    description: description,
    shelf: shelf ?? this.shelf,
    openedAt: openedAt ?? this.openedAt,
    epub: epub ?? this.epub,
    coverFile: coverFile,
    progress: progress ?? this.progress,
  );
  Map<String, dynamic> toJson() => {
    'url': url,
    'title': title,
    'author': author,
    'firstChapter': firstChapter,
    'addedAt': addedAt.toIso8601String(),
    'coverUrl': coverUrl,
    'description': description,
    'shelf': shelf,
    'openedAt': openedAt?.toIso8601String(),
    'epub': epub,
    'coverFile': coverFile,
    'progress': progress,
  };
  factory LibraryNovel.fromJson(Map<String, dynamic> value) => LibraryNovel(
    url: value['url'] as String,
    title: value['title'] as String,
    author: value['author'] as String,
    firstChapter: value['firstChapter'] as String,
    addedAt: DateTime.parse(value['addedAt'] as String),
    coverUrl: value['coverUrl'] as String?,
    description: value['description'] as String?,
    shelf: value['shelf'] as String? ?? shelves.first,
    openedAt: value['openedAt'] == null
        ? null
        : DateTime.parse(value['openedAt'] as String),
    epub: value['epub'] as String?,
    coverFile: value['coverFile'] as String?,
    progress: (value['progress'] as num?)?.toDouble(),
  );
}

/// Small local UI library. Chapter contents and reader state will be separate.
class LibraryStore extends ChangeNotifier {
  LibraryStore({
    List<LibraryNovel> novels = const [],
    this.appearance = AppAppearance.system,
    this.grid = true,
    this.sortByTitle = false,
  }) : _novels = List.of(novels);
  // Keep the existing private storage key so renaming the app preserves user data.
  static const storageKey = 'chapter_verse_library_v1';
  List<LibraryNovel> _novels;
  List<LibraryNovel> get novels => List.unmodifiable(_novels);
  AppAppearance appearance;
  bool grid, sortByTitle;
  SharedPreferences? _preferences;
  Future<void> _queue = Future.value();

  static Future<LibraryStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    final data = raw == null
        ? <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
    final store = LibraryStore(
      novels: (data['novels'] as List? ?? [])
          .map(
            (v) => LibraryNovel.fromJson(Map<String, dynamic>.from(v as Map)),
          )
          .toList(),
      appearance:
          AppAppearance.values
              .where((m) => m.name == data['theme'])
              .firstOrNull ??
          AppAppearance.system,
      grid: data['grid'] as bool? ?? true,
      sortByTitle: data['sortByTitle'] as bool? ?? false,
    );
    store._preferences = prefs;
    return store;
  }

  Future<void> _change(void Function() update) {
    final next = _queue.then((_) async {
      final previous = (_novels, appearance, grid, sortByTitle);
      _novels = List.of(_novels);
      update();
      try {
        final saved = await _preferences?.setString(
          storageKey,
          jsonEncode({
            'novels': _novels.map((n) => n.toJson()).toList(),
            'theme': appearance.name,
            'grid': grid,
            'sortByTitle': sortByTitle,
          }),
        );
        if (saved == false) {
          throw StateError('Could not save your library on this device.');
        }
      } catch (_) {
        _novels = previous.$1;
        appearance = previous.$2;
        grid = previous.$3;
        sortByTitle = previous.$4;
        rethrow;
      }
      notifyListeners();
    });
    _queue = next.catchError((Object _) {});
    return next;
  }

  static String canonical(String url) => url.startsWith('epub:')
      ? url
      : Uri.parse(url)
            .removeFragment()
            .replace(query: '')
            .toString()
            .replaceFirst(RegExp(r'\?*$'), '')
            .replaceFirst(RegExp(r'/+$'), '');

  LibraryNovel? find(String url) {
    final key = canonical(url);
    return _novels.where((n) => n.url == key).firstOrNull;
  }

  Future<void> add(String url, BookMetadata metadata) => _change(() {
    final canonical = LibraryStore.canonical(url);
    if (_novels.any((n) => n.url == canonical)) return;
    _novels.add(
      LibraryNovel(
        url: canonical,
        title: metadata.title.isEmpty ? 'Untitled novel' : metadata.title,
        author: metadata.author,
        firstChapter: metadata.firstChapter,
        addedAt: DateTime.now(),
        coverUrl: metadata.coverUrl,
        description: metadata.description,
      ),
    );
  });

  /// Adds an imported EPUB file, or refreshes it if it is already here.
  Future<void> addLocal(LibraryNovel novel) => _change(() {
    final index = _novels.indexWhere((n) => n.url == novel.url);
    if (index < 0) {
      _novels.add(novel);
    } else {
      _novels[index] = _novels[index].copyWith(epub: novel.epub);
    }
  });

  /// Keeps an app copy of a web novel's EPUB for the reader, adding the novel
  /// to the library first if needed.
  Future<void> attachEpub(String url, String key, BookMetadata metadata) =>
      _change(() {
        final canonical = LibraryStore.canonical(url);
        final index = _novels.indexWhere((n) => n.url == canonical);
        if (index < 0) {
          _novels.add(
            LibraryNovel(
              url: canonical,
              title: metadata.title.isEmpty ? 'Untitled novel' : metadata.title,
              author: metadata.author,
              firstChapter: metadata.firstChapter,
              addedAt: DateTime.now(),
              coverUrl: metadata.coverUrl,
              description: metadata.description,
              shelf: 'Reading',
              epub: key,
            ),
          );
        } else {
          _novels[index] = _novels[index].copyWith(epub: key);
        }
      });

  Future<void> setProgress(String url, double progress) => _change(
    () => _novels = _novels
        .map(
          (n) =>
              n.url == url ? n.copyWith(progress: progress.clamp(0.0, 1.0)) : n,
        )
        .toList(),
  );

  Future<void> remove(String url) =>
      _change(() => _novels.removeWhere((n) => n.url == url));
  Future<void> setShelf(String url, String shelf) => _change(() {
    if (!shelves.contains(shelf)) throw ArgumentError('Unknown shelf');
    _novels = _novels
        .map((n) => n.url == url ? n.copyWith(shelf: shelf) : n)
        .toList();
  });
  Future<void> opened(String url) => _change(
    () => _novels = _novels
        .map((n) => n.url == url ? n.copyWith(openedAt: DateTime.now()) : n)
        .toList(),
  );
  Future<void> setAppearance({
    AppAppearance? theme,
    bool? grid,
    bool? sortByTitle,
  }) => _change(() {
    appearance = theme ?? appearance;
    this.grid = grid ?? this.grid;
    this.sortByTitle = sortByTitle ?? this.sortByTitle;
  });
}
