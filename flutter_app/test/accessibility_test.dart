// The app and reader at the largest text sizes and with Reduce Motion.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_to_epub/library/library_store.dart';
import 'package:novel_to_epub/library/novel_detail_screen.dart';
import 'package:novel_to_epub/main.dart';
import 'package:novel_to_epub/reader/epub_document.dart';
import 'package:novel_to_epub/reader/reader_screen.dart';
import 'package:novel_to_epub/reader/reader_settings.dart';
import 'package:novel_to_epub/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'reader_test.dart' show sampleBook;

LibraryNovel novel() => LibraryNovel(
  url: 'https://www.royalroad.com/fiction/1/a-rather-long-title',
  title: 'A Rather Long Light Novel Title About a Quiet Library',
  author: 'Someone With a Long Name',
  firstChapter: 'https://www.royalroad.com/fiction/1/x/chapter/1',
  addedAt: DateTime(2026),
  description: 'A journey through a world of stories.',
  epub: 'book.epub',
  progress: .4,
  openedAt: DateTime(2026, 2),
);

void main() {
  for (final (size, scale) in const [
    (Size(390, 844), 2.0),
    (Size(320, 568), 1.6),
  ]) {
    final name = '${size.width.round()} pt at ${scale}x text';
    testWidgets('app fits $name', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final store = LibraryStore(novels: [novel()]);
      await tester.pumpWidget(NovelApp(store: store, autoDownload: false));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Library');
      for (final tab in ['Updates', 'Reading', 'Settings', 'Search']) {
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: tab);
      }
      await tester.pumpWidget(
        MaterialApp(
          theme: novelTheme(Brightness.light),
          home: NovelDetailScreen(
            url: novel().url,
            store: store,
            onExport: (_) {},
            chapters: (_) async => const [
              TocEntry('Chapter 1: A Very Long Chapter Name Indeed', 1, 0, 0),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Details');
    });

    testWidgets('reader menus fit $name', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final settings = ReaderSettings({'fullscreen': false});
      addTearDown(settings.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: novelTheme(Brightness.light),
          home: ReaderScreen(
            bookId: 'a11y',
            document: EpubDocument.parse(sampleBook()),
            settings: settings,
          ),
        ),
      );
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(Offset(size.width / 2, 30));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'menus');
      await tester.tap(find.byTooltip('Themes & Settings'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Themes & Settings');
    });
  }

  testWidgets('Reduce Motion turns off page transitions', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final store = LibraryStore(novels: [novel()]);
    await tester.pumpWidget(NovelApp(store: store, autoDownload: false));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey(novel().url)));
    // With Reduce Motion the details page appears without a slide.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(NovelDetailScreen), findsOneWidget);
    final box = tester.getTopLeft(find.byType(NovelDetailScreen));
    expect(box.dx, 0);
  });
}
