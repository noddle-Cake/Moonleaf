import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:novel_to_epub/library/library_screen.dart';
import 'package:novel_to_epub/library/library_store.dart';
import 'package:novel_to_epub/reader/epub_document.dart';
import 'package:novel_to_epub/reader/reader_settings.dart';
import 'package:novel_to_epub/library/novel_detail_screen.dart';
import 'package:novel_to_epub/main.dart';
import 'package:novel_to_epub/data/novel_service.dart';

import 'widget_test.dart' show fakeApi;

LibraryNovel fixture(
  String title, {
  String shelf = 'Plan to read',
}) => LibraryNovel(
  url:
      'https://roliascan.com/manga/${title.toLowerCase().replaceAll(' ', '-')}',
  title: title,
  author: 'An author',
  firstChapter: 'https://roliascan.com/read/sample/ch1/',
  addedAt: DateTime(2026, 1, 1),
  shelf: shelf,
  description: 'A journey through a world of stories.',
);

void main() {
  testWidgets('fresh install has an empty library and Moonleaf branding', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const NovelApp());
    await tester.pumpAndSettle();
    expect((await LibraryStore.load()).novels, isEmpty);
    expect(find.text('Your next story starts here'), findsOneWidget);
    expect(find.byKey(const Key('library-grid')), findsNothing);
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    expect(find.text('Moonleaf'), findsOneWidget);
  });

  test(
    'library, shelves, history and e-reader preference survive reload',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await LibraryStore.load();
      await store.add(
        'https://roliascan.com/manga/sample/#top',
        const BookMetadata(
          title: 'Sample',
          author: 'Writer',
          firstChapter: 'https://roliascan.com/read/sample/ch1/',
        ),
      );
      await store.add(
        'https://roliascan.com/manga/sample',
        const BookMetadata(title: 'Duplicate'),
      );
      expect(store.novels.length, 1);
      final url = store.novels.single.url;
      await Future.wait([
        store.setShelf(url, 'Reading'),
        store.opened(url),
        store.setAppearance(theme: AppAppearance.ereaderDark, grid: false),
      ]);
      final reloaded = await LibraryStore.load();
      expect(reloaded.novels.single.title, 'Sample');
      expect(reloaded.novels.single.shelf, 'Reading');
      expect(reloaded.novels.single.openedAt, isNotNull);
      expect(reloaded.appearance, AppAppearance.ereaderDark);
      expect(reloaded.grid, isFalse);
      await reloaded.remove(url);
      expect((await LibraryStore.load()).novels, isEmpty);
    },
  );
  testWidgets('add from source, open detail, change shelf and see history', (
    tester,
  ) async {
    final store = LibraryStore();
    final api = fakeApi();
    addTearDown(api.close);
    await tester.pumpWidget(
      NovelApp(store: store, service: api, autoDownload: false),
    );
    // The empty library points to Search, which lists the sources.
    await tester.tap(find.text('Browse Sources'));
    await tester.pumpAndSettle();
    expect(find.text('Indra Translations'), findsOneWidget);
    await tester.tap(find.text('Add a Novel by Link'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('add-novel-url')),
      'https://roliascan.com/manga/sample/',
    );
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(store.novels.single.title, 'A Sample Novel');
    // Adding opens the novel's page straight away.
    expect(find.byType(NovelDetailScreen), findsOneWidget);
    expect(find.text('A story to take with you.'), findsOneWidget);
    // The shelf chip under the title moves the novel between shelves.
    await tester.tap(find.widgetWithText(ActionChip, 'Plan to read'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reading').last);
    await tester.pumpAndSettle();
    expect(store.novels.single.shelf, 'Reading');
    await tester.tap(find.byKey(const Key('download-novel')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('book-title')))
          .controller!
          .text,
      'A Sample Novel',
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reading').last);
    await tester.pumpAndSettle();
    expect(find.text('Recently Opened'), findsOneWidget);
    expect(find.text('A Sample Novel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('search and list view work on desktop', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = LibraryStore(
      novels: [fixture('Paper Kingdom'), fixture('Winter Roads')],
    );
    await tester.pumpWidget(NovelApp(store: store));
    expect(find.byType(NavigationRail), findsOneWidget);
    await tester.enterText(find.byKey(const Key('library-search')), 'winter');
    await tester.pumpAndSettle();
    expect(find.text('Winter Roads'), findsWidgets);
    expect(find.text('Paper Kingdom'), findsNothing);
    await tester.tap(find.byTooltip('Library options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show as List'));
    await tester.pumpAndSettle();
    expect(store.grid, isFalse);
    // Search finds books and turns pasted links into an Add action.
    await tester.tap(find.text('Search').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('global-search')), 'paper');
    await tester.pumpAndSettle();
    expect(find.text('Paper Kingdom'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('global-search')),
      'https://www.royalroad.com/fiction/1/x',
    );
    await tester.pumpAndSettle();
    expect(find.text('Add This Link'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final appearance in [
    AppAppearance.ereaderLight,
    AppAppearance.ereaderDark,
  ]) {
    testWidgets(
      '${appearance.name} is monochrome, high contrast and reduced motion',
      (tester) async {
        final store = LibraryStore();
        await tester.pumpWidget(NovelApp(store: store));
        await tester.tap(find.text('Settings').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Appearance'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('appearance-${appearance.name}')));
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(LibraryScreen));
        expect(
          Theme.of(context).colorScheme.surface,
          appearance == AppAppearance.ereaderDark ? Colors.black : Colors.white,
        );
        expect(MediaQuery.of(context).disableAnimations, isTrue);
        expect(find.byType(ColorFiltered), findsWidgets);
        expect(store.appearance, appearance);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'narrow phone with large type supports library, details and appearance',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final novel = fixture(
        'A Rather Long Light Novel Title About a Quiet Library',
      );
      final store = LibraryStore(novels: [novel]);
      await tester.pumpWidget(NovelApp(store: store));
      // At large text sizes the library shows a list instead of covers.
      expect(find.byKey(ValueKey(novel.url)), findsNothing);
      await tester.tap(find.byKey(ValueKey('row-${novel.url}')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      // Every tab fits a 320-pt phone with large text.
      for (final tab in ['Updates', 'Reading', 'Settings', 'Search']) {
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: tab);
      }
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('kept EPUBs show reading progress and open the reader', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = await LibraryStore.load();
    addTearDown(store.dispose);
    await store.attachEpub(
      'https://www.royalroad.com/fiction/1/sample/',
      'web-sample.epub',
      const BookMetadata(title: 'Kept Novel', author: 'Someone'),
    );
    final url = store.novels.single.url;
    expect(url, 'https://www.royalroad.com/fiction/1/sample');
    expect(store.novels.single.shelf, 'Reading');
    await store.setProgress(url, .4);
    final reloaded = await LibraryStore.load();
    expect(reloaded.novels.single.epub, 'web-sample.epub');
    expect(reloaded.novels.single.progress, .4);
    reloaded.dispose();
    // The reader stopped in the second chapter.
    await (BookState(url)
          ..chapter = 2
          ..offset = 10
          ..progress = .4)
        .save();
    final opened = <(String, int?, int?)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: NovelDetailScreen(
          url: url,
          store: store,
          onExport: (_) {},
          chapters: (_) async => const [
            TocEntry('Chapter 1: Prologue', 1, 0, 0),
            TocEntry('Chapter 2: The Bell', 2, 0, 0),
            TocEntry('Chapter 3: Night Ferry', 3, 0, 0),
          ],
          onRead: (n, {chapter, offset}) async =>
              opened.add((n.url, chapter, offset)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('3 Chapters'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Reading'), findsOneWidget);
    // Newest first, like Mihon; the sort button flips it.
    double y(String t) => tester.getTopLeft(find.text(t)).dy;
    expect(y('Chapter 3: Night Ferry'), lessThan(y('Chapter 1: Prologue')));
    await tester.tap(find.byTooltip('Show oldest first'));
    await tester.pumpAndSettle();
    expect(y('Chapter 1: Prologue'), lessThan(y('Chapter 3: Night Ferry')));
    await tester.tap(find.text('Chapter 3: Night Ferry'));
    await tester.tap(find.text('Resume'));
    await tester.pumpAndSettle();
    expect(opened, [(url, 3, 0), (url, null, null)]);
    await store.addLocal(
      LibraryNovel(
        url: 'epub:abc',
        title: 'Imported',
        author: '',
        firstChapter: '',
        addedAt: DateTime(2026),
        epub: 'epub_abc.epub',
      ),
    );
    final local = store.find('epub:abc')!;
    expect(local.isLocal, isTrue);
    expect(local.source, 'EPUB file');
  });

  test('updates record how many chapters were added', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LibraryStore.load();
    addTearDown(store.dispose);
    const url = 'https://www.royalroad.com/fiction/9/story';
    const meta = BookMetadata(title: 'Story', author: 'A');
    await store.attachEpub(url, 'k.epub', meta, chapters: 10);
    expect(store.find(url)!.chapterCount, 10);
    expect(store.find(url)!.newChapters, 0);
    await store.attachEpub(url, 'k.epub', meta, chapters: 13);
    expect(store.find(url)!.newChapters, 3);
    expect(store.find(url)!.updatedAt, isNotNull);
    await store.attachEpub(url, 'k.epub', meta, chapters: 13);
    expect(store.find(url)!.newChapters, 0);
    final reloaded = await LibraryStore.load();
    expect(reloaded.find(url)!.chapterCount, 13);
    reloaded.dispose();
  });
}
