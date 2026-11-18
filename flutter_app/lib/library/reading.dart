import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/novel_service.dart';
import '../reader/book_files.dart';
import '../reader/epub_document.dart';
import '../reader/reader_screen.dart';
import '../reader/reader_settings.dart';
import 'library_store.dart';

bool ereaderAppearance(LibraryStore store) =>
    store.appearance == AppAppearance.ereaderLight ||
    store.appearance == AppAppearance.ereaderDark;

void _say(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Stable identifier for imported files, so importing twice finds the book.
String bookFingerprint(List<int> bytes) {
  // Two 32-bit FNV-1a hashes; the arithmetic stays exact on the web too.
  int mix(int hash, int byte) {
    hash = (hash ^ byte) & 0xFFFFFFFF;
    return (((hash << 24) & 0xFFFFFFFF) + hash * 403) & 0xFFFFFFFF;
  }

  var a = 0x811c9dc5, b = 0x050c5d1f;
  final step = bytes.length > 4 << 20 ? bytes.length ~/ (1 << 20) : 1;
  for (var i = 0; i < bytes.length; i += step) {
    a = mix(a, bytes[i]);
    b = mix(b, bytes[bytes.length - 1 - i]);
  }
  return '${bytes.length.toRadixString(36)}-${a.toRadixString(36)}${b.toRadixString(36)}';
}

/// Opens a library book in the reader and keeps its progress in the library.
Future<void> readNovel(
  BuildContext context,
  LibraryStore store,
  LibraryNovel novel,
) async {
  final key = novel.epub;
  if (key == null) return;
  final bytes = await readBook(key);
  if (!context.mounted) return;
  if (bytes == null) {
    _say(
      context,
      persistentBooks
          ? 'This book is missing from the device. Create the EPUB again to read it.'
          : 'Books are kept only until the browser tab closes. Create the EPUB again to read it.',
    );
    return;
  }
  try {
    await store.opened(novel.url);
  } catch (_) {}
  if (!context.mounted) return;
  await openReader(
    context,
    bookId: novel.url,
    bytes: bytes,
    ereaderApp: ereaderAppearance(store),
    onProgress: (p) {
      if ((p - (store.find(novel.url)?.progress ?? -1)).abs() > .0005) {
        store.setProgress(novel.url, p).catchError((Object _) {});
      }
    },
  );
}

/// Saves a freshly created EPUB with its novel so it can be read in the app.
Future<LibraryNovel?> keepEpub(
  LibraryStore store,
  String url,
  BookMetadata metadata,
  List<int> bytes,
) async {
  final canonical = LibraryStore.canonical(url);
  final key = await saveBook(
    'web-${bookFingerprint(canonical.codeUnits)}',
    bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
  );
  await store.attachEpub(canonical, key, metadata);
  return store.find(canonical);
}

/// Lets the reader pick any EPUB on the device, adds it to the library and
/// opens it.
Future<void> importEpub(BuildContext context, LibraryStore store) async {
  final PlatformFile? file;
  final Uint8List bytes;
  try {
    file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['epub'],
    );
    if (file == null) return;
    bytes = await file.readAsBytes();
  } catch (_) {
    if (context.mounted) _say(context, 'That file could not be opened.');
    return;
  }
  final EpubDocument doc;
  try {
    doc = await parseEpub(bytes);
  } catch (error) {
    if (context.mounted) {
      _say(
        context,
        error is FormatException
            ? error.message
            : 'This EPUB could not be read.',
      );
    }
    return;
  }
  final id = 'epub:${bookFingerprint(bytes)}';
  try {
    final existing = store.find(id);
    if (existing == null) {
      final key = await saveBook(id, bytes);
      String? cover;
      final art = doc.cover;
      if (art != null && art.length < 12 << 20) {
        cover = await saveBook(id, art, ext: 'cover');
      }
      await store.addLocal(
        LibraryNovel(
          url: id,
          title: doc.title,
          author: doc.author,
          firstChapter: '',
          addedAt: DateTime.now(),
          shelf: 'Reading',
          epub: key,
          coverFile: cover,
        ),
      );
    }
  } catch (_) {
    if (context.mounted) {
      _say(context, 'Could not save this book on your device.');
    }
    return;
  }
  final novel = store.find(id);
  if (novel != null && context.mounted) await readNovel(context, store, novel);
}

/// Deletes the app's copy of a book and its reading state.
Future<void> forgetBook(LibraryNovel novel) async {
  try {
    if (novel.epub != null) await deleteBook(novel.epub!);
    if (novel.coverFile != null) await deleteBook(novel.coverFile!);
    await BookState.forget(novel.url);
  } catch (_) {}
}
