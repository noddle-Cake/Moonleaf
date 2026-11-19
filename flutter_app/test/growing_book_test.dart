import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_to_epub/data/epub_writer.dart';
import 'package:novel_to_epub/data/site_extractors.dart';
import 'package:novel_to_epub/library/reading.dart';
import 'package:novel_to_epub/reader/epub_document.dart';
import 'package:novel_to_epub/reader/reader_screen.dart';
import 'package:novel_to_epub/reader/reader_settings.dart';
import 'package:novel_to_epub/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const base = 'https://www.royalroad.com/fiction/7/tide/chapter';
Uri ch(int n) => Uri.parse('$base/$n/part-$n');

/// A book holding chapters [numbers] of a novel.
Uint8List book(List<int> numbers) => buildEpub(
  EpubBook('Tide', 'A. Writer', [
    for (final n in numbers)
      NovelChapter(
        'Chapter $n: Part $n',
        List.filled(40, '<p>Words of part $n go on for a while.</p>').join(),
        ch(n),
        null,
      ),
  ], null),
);

int indexOf(List<String> paths, int n) =>
    paths.indexWhere((p) => p.endsWith('${chapterFileId(ch(n))}.xhtml'));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('positions, bookmarks and highlights follow their chapters', () {
    final before = [
      for (final c in EpubDocument.parse(book([3, 4])).chapters) c.path,
    ];
    final after = [
      for (final c in EpubDocument.parse(book([1, 2, 3, 4])).chapters) c.path,
    ];
    final state = BookState('b')
      ..spine = before
      ..chapter = indexOf(before, 4)
      ..offset = 120;
    state.bookmarks.add(Bookmark(indexOf(before, 3), 5, 'x', DateTime(2026)));
    state.highlights.add(
      Highlight(indexOf(before, 4), 1, 9, 'words', DateTime(2026), note: 'n'),
    );
    expect(state.follow(after), isTrue);
    expect(state.chapter, indexOf(after, 4));
    expect(state.offset, 120);
    expect(state.bookmarks.single.chapter, indexOf(after, 3));
    expect(state.highlights.single.chapter, indexOf(after, 4));
    expect(state.highlights.single.note, 'n');
    expect(state.follow(after), isFalse, reason: 'nothing changed');
  });

  test('older saves without chapter files keep their positions', () {
    final paths = [
      for (final c in EpubDocument.parse(book([1, 2])).chapters) c.path,
    ];
    final legacy = BookState('b')
      ..chapter = 2
      ..offset = 40;
    expect(legacy.follow(paths), isTrue);
    expect((legacy.chapter, legacy.offset), (2, 40));
    final renamed = BookState('b')
      ..spine = [
        'EPUB/title.xhtml',
        'EPUB/chapter00001.xhtml',
        'EPUB/chapter00002.xhtml',
      ]
      ..chapter = 2
      ..offset = 40;
    renamed.follow(paths);
    expect((renamed.chapter, renamed.offset), (2, 40));
  });

  test(
    'a chapter link starts the book there, with earlier ones read',
    () async {
      await followChapters('novel', book([21]), ch(21).toString());
      var state = await BookState.load('novel');
      final first = [
        for (final c in EpubDocument.parse(book([21])).chapters) c.path,
      ];
      expect(state.chapter, indexOf(first, 21));
      // Chapters 1–20 arrive later and slot in before it.
      await followChapters(
        'novel',
        book([for (var i = 1; i <= 21; i++) i]),
        ch(21).toString(),
      );
      state = await BookState.load('novel');
      expect(
        state.spine[state.chapter],
        endsWith('${chapterFileId(ch(21))}.xhtml'),
      );
      expect(state.chapter, greaterThan(20));
    },
  );

  testWidgets('the open reader adds new chapters without losing its place', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = ReaderSettings({'animation': 'none', 'fullscreen': false});
    addTearDown(settings.dispose);
    final updates = StreamController<Uint8List>();
    addTearDown(updates.close);
    final downloading = ValueNotifier(true);
    addTearDown(downloading.dispose);
    final doc = EpubDocument.parse(book([3, 4]));
    final start = indexOf([for (final c in doc.chapters) c.path], 4);
    await tester.pumpWidget(
      MaterialApp(
        theme: novelTheme(Brightness.light),
        home: ReaderScreen(
          bookId: 'growing',
          document: doc,
          settings: settings,
          initialChapter: start,
          updates: updates.stream,
          downloading: downloading,
        ),
      ),
    );
    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
    }

    await settle();
    updates.add(book([1, 2, 3, 4, 5]));
    await settle();
    // The menu names the chapter that is open.
    await tester.tapAt(const Offset(195, 40));
    await tester.pumpAndSettle();
    expect(find.textContaining('Part 4'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    final saved = await BookState.load('growing');
    expect(
      saved.spine[saved.chapter],
      endsWith('${chapterFileId(ch(4))}.xhtml'),
    );
    expect(saved.spine, hasLength(greaterThan(5)));
  });
}
