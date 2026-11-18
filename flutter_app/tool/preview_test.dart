// Preview the actual empty first-run library, with no seeded novel data.
// flutter test tool/preview_test.dart --update-goldens
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_to_epub/library/library_store.dart';
import 'package:novel_to_epub/main.dart';

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
    'desktop': (const Size(1280, 900), AppAppearance.dark),
    'phone': (const Size(390, 844), AppAppearance.dark),
    'phone-light': (const Size(390, 844), AppAppearance.light),
    'ereader-light': (const Size(390, 844), AppAppearance.ereaderLight),
    'ereader-dark': (const Size(390, 844), AppAppearance.ereaderDark),
    'settings': (const Size(390, 844), AppAppearance.light),
    'search': (const Size(390, 844), AppAppearance.dark),
    'updates-320': (const Size(320, 568), AppAppearance.light),
    'phone-320': (const Size(320, 568), AppAppearance.light),
    'phone-360': (const Size(360, 780), AppAppearance.dark),
  }.entries) {
    testWidgets('${entry.key} preview', (tester) async {
      tester.view.physicalSize = entry.value.$1;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = LibraryStore(appearance: entry.value.$2);
      await tester.pumpWidget(NovelApp(store: store));
      await tester.pumpAndSettle();
      for (final tab in ['Settings', 'Search', 'Updates']) {
        if (entry.key.startsWith(tab.toLowerCase())) {
          await tester.tap(find.text(tab).last);
          await tester.pumpAndSettle();
        }
      }
      await expectLater(
        find.byType(NovelApp),
        matchesGoldenFile('../screenshots/${entry.key}.png'),
      );
    });
  }
}
