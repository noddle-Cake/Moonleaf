import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_to_epub/data/epub_writer.dart';
import 'package:novel_to_epub/data/site_extractors.dart';
import 'package:novel_to_epub/reader/epub_document.dart';
import 'package:novel_to_epub/reader/reader_screen.dart';
import 'package:novel_to_epub/reader/reader_settings.dart';
import 'package:novel_to_epub/reader/typesetter.dart';
import 'package:novel_to_epub/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Original filler prose for tests and previews (no real books).
String paragraphs(int chapter, int count) => [
  for (var i = 0; i < count; i++)
    '<p>Lantern ${i + 1} of chapter $chapter flickered over the quiet harbor '
        'while the tide counted its slow breaths against the stones. '
        '<em>Somewhere</em> a bell answered, and the keeper wrote the hour '
        'into a book that nobody else would read.</p>',
].join();

Uint8List sampleBook({int chapters = 3, int paras = 30}) => buildEpub(
  EpubBook('The Lantern Keeper', 'A. Writer', [
    for (var c = 1; c <= chapters; c++)
      NovelChapter(
        'Chapter $c',
        paragraphs(c, paras) +
            (c == 1
                ? '<p>See the note<a href="#n1">1</a>.</p><hr/>'
                      '<blockquote><p>A quoted line.</p></blockquote>'
                      '<ul><li><p>First item</p></li><li>Second item</li></ul>'
                      '<p id="n1">Note one: tides are patient.</p>'
                : ''),
        Uri.parse('https://example.com/ch$c'),
        null,
      ),
  ], null),
);

Typesetter typesetter(EpubDocument doc, {double font = 18}) => Typesetter(
  doc,
  ReaderSettings({'fontSize': font}),
  readerPalettes['paper']!,
  const Size(340, 600),
);

void main() {
  test('parses metadata, chapters, contents and anchors', () {
    final doc = EpubDocument.parse(sampleBook());
    expect(doc.title, 'The Lantern Keeper');
    expect(doc.author, 'A. Writer');
    // Title page plus three chapters.
    expect(doc.chapters, hasLength(4));
    expect(doc.toc.map((t) => t.title), [
      'Chapter 1',
      'Chapter 2',
      'Chapter 3',
    ]);
    final ch1 = doc.chapters[doc.toc.first.chapter];
    expect(ch1.title, 'Chapter 1');
    final first = ch1.blocks.first as TextBlock;
    expect(first.kind, BlockKind.heading);
    expect(ch1.blocks.whereType<RuleBlock>(), hasLength(1));
    final quote = ch1.blocks.whereType<TextBlock>().firstWhere(
      (b) => b.kind == BlockKind.quote,
    );
    expect(quote.text, 'A quoted line.');
    final items = ch1.blocks
        .whereType<TextBlock>()
        .where((b) => b.kind == BlockKind.listItem)
        .map((b) => b.text)
        .toList();
    expect(items, ['• First item', '• Second item']);
    // Plain-text offsets line up with block positions.
    for (final b in ch1.blocks) {
      expect(
        ch1.plainText.substring(b.charStart, b.charStart + b.length),
        b.text,
      );
    }
    final italic = (ch1.blocks[1] as TextBlock).runs.where((r) => r.italic);
    expect(italic.single.text, 'Somewhere');
    final (c, o) = doc.locate(.5);
    expect(doc.progressOf(c, o), closeTo(.5, .01));
  });

  test('reads EPUB 2 packages with an NCX table of contents', () {
    final archive = Archive();
    void add(String name, String text) {
      final data = utf8.encode(text);
      archive.addFile(ArchiveFile(name, data.length, data));
    }

    add(
      'META-INF/container.xml',
      '<container><rootfiles><rootfile full-path="OEBPS/book.opf"/></rootfiles></container>',
    );
    add(
      'OEBPS/book.opf',
      '<package xmlns:dc="http://purl.org/dc/elements/1.1/"><metadata>'
          '<dc:title>Old Format</dc:title><dc:creator>Someone</dc:creator>'
          '</metadata><manifest>'
          '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'
          '<item id="a" href="text/a.html" media-type="application/xhtml+xml"/>'
          '</manifest><spine toc="ncx"><itemref idref="a"/></spine></package>',
    );
    add(
      'OEBPS/toc.ncx',
      '<ncx><navMap><navPoint><navLabel><text>Start</text></navLabel>'
          '<content src="text/a.html"/><navPoint><navLabel><text>Middle</text>'
          '</navLabel><content src="text/a.html#mid"/></navPoint></navPoint>'
          '</navMap></ncx>',
    );
    add(
      'OEBPS/text/a.html',
      '<?xml version="1.0"?><html><head><title/></head><body><a id="top"/><p>Begin<a href="#n1">1</a>.</p><div><span id="mid"></span>Middle text '
          '<b>bold</b><br/>next line</div><table><tr><th>A</th><td>B</td></tr>'
          '</table><p id="n1">Note one.</p></body></html>',
    );
    final doc = EpubDocument.parse(
      Uint8List.fromList(ZipEncoder().encode(archive)),
    );
    expect(doc.title, 'Old Format');
    expect(doc.toc.map((t) => (t.title, t.depth)), [
      ('Start', 0),
      ('Middle', 1),
    ]);
    final text = doc.chapters.single.plainText;
    expect(
      text.substring(doc.toc[1].offset),
      startsWith('Middle text bold\nnext'),
    );
    expect(text, contains('A | B'));
    final chapter = doc.chapters.single;
    final note = chapter.anchors['n1']!;
    expect(text.substring(note), 'Note one.');
    expect(doc.resolve(chapter.path, '#n1'), (0, note));
    final link = (chapter.blocks.first as TextBlock).runs.firstWhere(
      (r) => r.href != null,
    );
    expect((link.text, link.href), ('1', '#n1'));
  });

  test('parses on a background isolate', () async {
    final doc = await parseEpub(sampleBook(chapters: 20));
    expect(doc.chapters, hasLength(21));
    expect(doc.resource(doc.chapters[1].path), isNotNull);
    await expectLater(parseEpub(Uint8List(4)), throwsFormatException);
  });

  test('rejects files that are not EPUBs', () {
    expect(
      () => EpubDocument.parse(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });

  testWidgets('paginates chapters without losing or repeating text', (
    tester,
  ) async {
    final doc = EpubDocument.parse(sampleBook());
    final ch = doc.toc.first.chapter;
    final small = await tester.runAsync(
      () => typesetter(doc, font: 14).layout(ch),
    );
    final large = await tester.runAsync(
      () => typesetter(doc, font: 26).layout(ch),
    );
    expect(small!.pages.length, greaterThan(1));
    expect(large!.pages.length, greaterThan(small.pages.length));
    for (final layout in [small, large]) {
      var previous = -1;
      for (final page in layout.pages) {
        expect(page.start, greaterThan(previous));
        expect(page.end, greaterThanOrEqualTo(page.start));
        previous = page.start;
        var bottom = 0.0;
        for (final slice in page.slices) {
          expect(slice.y, greaterThanOrEqualTo(bottom - .01));
          bottom = slice.y + slice.bottom - slice.top;
        }
        expect(bottom, lessThanOrEqualTo(600.5));
      }
      expect(layout.pages.last.end, doc.chapters[ch].length);
      // Every block appears in full across the pages.
      for (var b = 0; b < layout.blocks.length; b++) {
        final covered = layout.pages
            .expand((p) => p.slices)
            .where((s) => s.block == b)
            .fold(0.0, (sum, s) => sum + s.bottom - s.top);
        expect(covered, closeTo(layout.blocks[b].height, .5));
      }
      // Positions map back to the page that shows them.
      final mid = layout.pages[layout.pages.length ~/ 2];
      expect(layout.pageOf(mid.start + 3), layout.pages.indexOf(mid));
      layout.dispose();
    }
  });

  test('keys and buttons map to page turns', () {
    final s = ReaderSettings();
    expect(s.actionFor(LogicalKeyboardKey.audioVolumeDown), KeyAction.next);
    expect(s.actionFor(LogicalKeyboardKey.audioVolumeUp), KeyAction.previous);
    expect(s.actionFor(LogicalKeyboardKey.pageDown), KeyAction.next);
    expect(
      s.actionFor(LogicalKeyboardKey.mediaTrackPrevious),
      KeyAction.previous,
    );
    expect(s.actionFor(LogicalKeyboardKey.keyQ), isNull);
    s.invertVolume = true;
    expect(s.actionFor(LogicalKeyboardKey.audioVolumeUp), KeyAction.next);
    s.volumeKeys = false;
    expect(s.actionFor(LogicalKeyboardKey.audioVolumeUp), isNull);
    s.keys = false;
    expect(s.actionFor(LogicalKeyboardKey.pageDown), isNull);
    // Assigned buttons work even with the built-in keys off, and replace
    // an earlier assignment of the same button.
    s.assignButton(LogicalKeyboardKey.pageDown, forward: false);
    s.assignButton(LogicalKeyboardKey.f13, forward: true);
    s.assignButton(LogicalKeyboardKey.f13, forward: false);
    expect(s.actionFor(LogicalKeyboardKey.pageDown), KeyAction.previous);
    expect(s.actionFor(LogicalKeyboardKey.f13), KeyAction.previous);
    expect(s.buttons, hasLength(2));
    final restored = ReaderSettings(s.toJson());
    expect(restored.actionFor(LogicalKeyboardKey.f13), KeyAction.previous);
    expect(restored.volumeKeys, isFalse);
    expect(restored.invertVolume, isTrue);
    s.dispose();
    restored.dispose();
  });

  group('reader screen', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<ReaderSettings> open(
      WidgetTester tester, {
      Size size = const Size(390, 844),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = ReaderSettings({
        'animation': 'none',
        'fullscreen': false,
      });
      addTearDown(settings.dispose);
      final doc = EpubDocument.parse(sampleBook());
      await tester.pumpWidget(
        MaterialApp(
          theme: novelTheme(Brightness.light),
          home: ReaderScreen(
            bookId: 'test-book',
            document: doc,
            settings: settings,
          ),
        ),
      );
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      return settings;
    }

    testWidgets('turns pages, opens menus and remembers position', (
      tester,
    ) async {
      await open(tester);
      expect(find.byType(CustomPaint), findsWidgets);
      // Title page, then into chapter 1 via taps on the right edge.
      for (var i = 0; i < 3; i++) {
        await tester.tapAt(const Offset(370, 420));
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
      }
      final state = await BookState.load('test-book');
      // Saving is debounced; the menu also saves on close.
      await tester.tapAt(const Offset(195, 40));
      await tester.pumpAndSettle();
      expect(find.text('The Lantern Keeper'), findsOneWidget);
      expect(find.text('Contents'), findsOneWidget);
      await tester.tap(find.byTooltip('Bookmark this page'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove bookmark'), findsOneWidget);
      await tester.tap(find.text('Contents'));
      await tester.pumpAndSettle();
      expect(find.text('Chapter 3'), findsOneWidget);
      await tester.tap(find.text('Chapter 3'));
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Back to where you were'), findsOneWidget);
      // Keyboard navigation.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      final saved = await BookState.load('test-book');
      expect(saved.chapter, 3);
      expect(saved.bookmarks, hasLength(1));
      expect(saved.progress, greaterThan(.6));
      expect(state.id, 'test-book');
    });

    testWidgets('typesetting sheet changes the layout live', (tester) async {
      final settings = await open(tester);
      await tester.tapAt(const Offset(195, 820));
      await tester.pumpAndSettle();
      expect(find.text('Font size'), findsOneWidget);
      await tester.tap(find.byTooltip('Increase font size'));
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(settings.fontSize, 20);
      await tester.tap(find.text('Theme'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Night'));
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(settings.palette, 'night');
      await tester.tap(find.text('Layout'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuous'));
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(settings.view, ReaderView.scroll);
      expect(tester.takeException(), isNull);
    });

    testWidgets('long-press selects text and creates a highlight', (
      tester,
    ) async {
      await open(tester);
      final settings = ReaderSettings();
      settings.dispose();
      // Move to chapter 1, which is full of text.
      for (var i = 0; i < 2; i++) {
        await tester.tapAt(const Offset(370, 420));
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
      }
      await tester.longPressAt(const Offset(120, 300));
      await tester.pumpAndSettle();
      expect(find.text('Highlight'), findsOneWidget);
      await tester.tap(find.text('Highlight'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(195, 40));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notes'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Highlights ('));
      await tester.pumpAndSettle();
      expect(find.text('Highlights (1)'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      final saved = await BookState.load('test-book');
      expect(saved.highlights.single.text, isNotEmpty);
    });

    testWidgets('search finds text across chapters', (tester) async {
      await open(tester);
      await tester.tapAt(const Offset(195, 40));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Search in book'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Lantern 7 of chapter 2');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('1 matches'), findsOneWidget);
      await tester.tap(find.textContaining('flickered').first);
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Back to where you were'), findsOneWidget);
    });

    testWidgets('volume and assigned buttons turn pages', (tester) async {
      final settings = await open(tester);
      // The footer shows "page / pages" once the book is counted.
      String page() => tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .firstWhere((t) => RegExp(r'^\d+ / \d+').hasMatch(t));
      Future<void> press(LogicalKeyboardKey key) async {
        await tester.sendKeyEvent(key);
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
      }

      final start = page();
      await press(LogicalKeyboardKey.audioVolumeDown);
      final second = page();
      expect(second, isNot(start));
      await press(LogicalKeyboardKey.audioVolumeUp);
      expect(page(), start);
      settings.update((s) => s.volumeKeys = false);
      await press(LogicalKeyboardKey.audioVolumeDown);
      expect(page(), start);

      // Assign another button from the reader's Controls settings.
      await tester.tapAt(const Offset(195, 820));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Controls'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Button for next page'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Button for next page'));
      await tester.pumpAndSettle();
      expect(
        find.text('Press the button you want to use now.'),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
      await tester.pumpAndSettle();
      expect(settings.buttons.single.id, LogicalKeyboardKey.mediaPlayPause.keyId);
      expect(settings.buttons.single.forward, isTrue);
      Navigator.of(tester.element(find.text('Controls'))).pop();
      await tester.pumpAndSettle();
      await press(LogicalKeyboardKey.mediaPlayPause);
      expect(page(), second);
    });
  });
}
