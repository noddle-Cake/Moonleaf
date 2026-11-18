// High-resolution reader screenshots for the website (site/assets/screens).
// flutter test tool/site_screens_test.dart --update-goldens
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_to_epub/reader/epub_document.dart';
import 'package:novel_to_epub/reader/reader_screen.dart';
import 'package:novel_to_epub/reader/reader_settings.dart';
import 'package:novel_to_epub/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:novel_to_epub/data/epub_writer.dart';
import 'package:novel_to_epub/data/site_extractors.dart';

/// An original fictional book written for these screenshots.
const _titles = [
  'The Harbor Bell',
  'Salt and Lamplight',
  'A Letter in the Tide',
  "The Cartographer's Daughter",
  'Night Ferry',
  'What the Fog Kept',
  'Ledger of Small Hours',
  'The Lighthouse Choir',
  'Driftwood Crowns',
  'Under the Seawall',
  "The Keeper's Oath",
  'Morning, Finally',
];
const _prose = [
  'The bell at the end of the pier rang twice before anyone saw the boat. Mira counted the beats out of habit, the way her mother had taught her, and only then lifted the lantern from its hook.',
  'Fog had been coming in since noon, slow and patient, swallowing the masts one by one. By evening the harbor was a rumor of itself: a few warm windows, the smell of tar, the hush of water against stone.',
  '“You are late,” said the keeper, though he did not sound surprised. He never sounded surprised. He held out a hand for the letter as if he had been waiting for it all his life, and perhaps he had.',
  'She did not give it to him at once. The paper was damp at the corners and sealed with green wax, pressed with a crest she had never seen: a lantern inside a crescent moon, its leaves curled like a question.',
  'Above them the great lamp turned, sweeping its pale arm across the water. In its light the waves looked almost solid, a floor of hammered silver that a careless person might try to walk upon.',
  '<em>Some doors only open from the sea side</em>, her grandmother used to say. Mira had always thought it was a figure of speech. Standing there, with the letter warm in her hand, she was no longer certain.',
];
String _chapter(int n) =>
    [for (var i = 0; i < 14; i++) '<p>${_prose[(i + n) % _prose.length]}</p>']
        .join();

Uint8List sampleBook() => buildEpub(
  EpubBook('The Lantern Keeper', 'A Moonleaf sample', [
    for (var c = 0; c < _titles.length; c++)
      NovelChapter(
        _titles[c],
        _chapter(c),
        Uri.parse('https://example.com/${c + 1}'),
        null,
      ),
  ], null),
);

void main() {
  setUpAll(() async {
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    for (final name in ['DM Sans', 'Fraunces']) {
      final loader = FontLoader(name)
        ..addFont(
          rootBundle.load(
            'assets/fonts/${name == 'DM Sans' ? 'DMSans' : 'Fraunces'}.ttf',
          ),
        );
      await loader.load();
    }
    // Real faces for the "Book serif" and "Monospace" font chips when these
    // screenshots are rendered on macOS; skipped elsewhere.
    for (final (family, path) in [
      ('Georgia', '/System/Library/Fonts/Supplemental/Georgia.ttf'),
      ('Menlo', '/System/Library/Fonts/Supplemental/Courier New.ttf'),
    ]) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
      await loader.load();
    }
  });
  for (final entry in {
    'reader-paper': ('paper', ''),
    'reader-sepia-menu': ('sepia', 'menu'),
    'reader-night-typeset': ('night', 'typeset'),
    'reader-eink-contents': ('eink', 'contents'),
    'reader-paper-highlight': ('paper', 'highlight'),
    'reader-dusk': ('dusk', ''),
  }.entries) {
    testWidgets('${entry.key} preview', (tester) async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      // Tests draw shadows as solid outlines; real shadows look like the app.
      debugDisableShadows = false;
      tester.view.physicalSize = const Size(780, 1688);
      tester.view.devicePixelRatio = 2;
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
            initialChapter: entry.value.$2 == 'contents' ? 4 : 1,
          ),
        ),
      );
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      switch (entry.value.$2) {
        case 'menu':
          await tester.tapAt(const Offset(195, 40));
        case 'typeset':
          await tester.tapAt(const Offset(195, 820));
        case 'highlight':
          Future<void> select(Offset from, Offset to) async {
            final gesture = await tester.startGesture(from);
            await tester.pump(
              kLongPressTimeout + const Duration(milliseconds: 50),
            );
            await gesture.moveTo(to);
            await tester.pump();
            await gesture.up();
            await tester.pumpAndSettle();
          }

          await select(const Offset(90, 290), const Offset(260, 318));
          await tester.tap(find.text('Highlight'));
          await tester.pumpAndSettle();
          await select(const Offset(255, 551), const Offset(350, 551));
        case 'contents':
          await tester.tapAt(const Offset(195, 40));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Contents'));
      }
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('site_screens/${entry.key}.png'),
      );
      debugDisableShadows = true;
    });
  }
}
