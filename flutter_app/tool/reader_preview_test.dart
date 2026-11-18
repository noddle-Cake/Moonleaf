// Rendered previews of the reader with an original sample book.
// flutter test tool/reader_preview_test.dart --update-goldens
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_to_epub/reader/epub_document.dart';
import 'package:novel_to_epub/reader/reader_screen.dart';
import 'package:novel_to_epub/reader/reader_settings.dart';
import 'package:novel_to_epub/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/reader_test.dart' show sampleBook;

void main() {
  setUpAll(() async {
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final cupertino = FontLoader('packages/cupertino_icons/CupertinoIcons')
      ..addFont(
        rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
      );
    await cupertino.load();
    for (final name in ['DM Sans', 'Fraunces']) {
      final loader = FontLoader(name)
        ..addFont(
          rootBundle.load(
            'assets/fonts/${name == 'DM Sans' ? 'DMSans' : 'Fraunces'}.ttf',
          ),
        );
      await loader.load();
    }
  });
  for (final entry in {
    'reader-page': ('paper', ''),
    'reader-sepia-menu': ('sepia', 'menu'),
    'reader-night-typeset': ('night', 'typeset'),
    'reader-eink-contents': ('eink', 'contents'),
    'reader-320-menu': ('paper', 'menu'),
  }.entries) {
    testWidgets('${entry.key} preview', (tester) async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = entry.key.contains('320')
          ? const Size(320, 568)
          : const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = ReaderSettings({
        'font': 'fraunces',
        'palette': entry.value.$1,
        'animation': 'none',
        'fullscreen': false,
      });
      addTearDown(settings.dispose);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: novelTheme(Brightness.light),
          home: ReaderScreen(
            bookId: 'preview',
            document: EpubDocument.parse(sampleBook()),
            settings: settings,
            initialChapter: 1,
          ),
        ),
      );
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      switch (entry.value.$2) {
        case 'menu':
          await tester.tapAt(const Offset(160, 30));
        case 'typeset':
          await tester.tapAt(const Offset(195, 820));
        case 'contents':
          await tester.tapAt(const Offset(160, 30));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Contents'));
      }
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../screenshots/${entry.key}.png'),
      );
    });
  }
}
